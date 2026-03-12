import UIKit

// MARK: - Section Display Info

struct SectionDisplayInfo {
    let name: String
    let offset: UInt64
    let size: UInt64
}

// MARK: - Hex Viewer View Controller

class HexViewerViewController: UIViewController {

    // MARK: - Constants

    private enum HexConstants {
        static let bytesPerRow: Int = 16
        static let bytesPerGroup: Int = 8
        static let rowHeight: CGFloat = 20
        static let readChunkSize: Int = 64 * 1024  // 64 KB read chunk
    }

    // MARK: - Properties

    private let fileURL: URL
    private let sections: [SectionDisplayInfo]?
    private var fileSize: UInt64 = 0
    private var totalRows: Int = 0
    private var fileHandle: FileHandle?

    /// Cache of recently read chunks keyed by chunk index
    private var chunkCache = NSCache<NSNumber, NSData>()

    // MARK: - UI Elements

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .plain)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.dataSource = self
        table.delegate = self
        table.register(HexRowCell.self, forCellReuseIdentifier: HexRowCell.reuseIdentifier)
        table.rowHeight = HexConstants.rowHeight
        table.estimatedRowHeight = HexConstants.rowHeight
        table.separatorStyle = .none
        table.backgroundColor = Constants.Colors.primaryBackground
        table.allowsSelection = false
        return table
    }()

    private let statusBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.secondaryBackground
        return view
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.text = "Offset: 0x00000000"
        return label
    }()

    private let sectionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = Constants.Colors.accentColor
        label.textAlignment = .right
        label.text = ""
        return label
    }()

    private let headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = Constants.Colors.tertiaryBackground
        return view
    }()

    private let headerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabel
        return label
    }()

    // MARK: - Initialization

    init(fileURL: URL, sections: [SectionDisplayInfo]? = nil) {
        self.fileURL = fileURL
        self.sections = sections
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Hex Viewer"
        view.backgroundColor = Constants.Colors.primaryBackground

        setupNavigationBar()
        setupUI()
        openFile()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let goToButton = UIBarButtonItem(
            image: UIImage(systemName: "arrow.right.to.line"),
            style: .plain,
            target: self,
            action: #selector(showGoToOffset)
        )

        let infoButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showFileInfo)
        )

        navigationItem.rightBarButtonItems = [goToButton, infoButton]
    }

    private func setupUI() {
        // Build header text: "Offset    00 01 02 ... 0F  ASCII"
        var header = "Offset    "
        for i in 0..<HexConstants.bytesPerRow {
            header += String(format: "%02X ", i)
            if i == HexConstants.bytesPerGroup - 1 {
                header += " "
            }
        }
        header += " ASCII"
        headerLabel.text = header

        view.addSubview(headerView)
        headerView.addSubview(headerLabel)
        view.addSubview(tableView)
        view.addSubview(statusBar)
        statusBar.addSubview(statusLabel)
        statusBar.addSubview(sectionLabel)

        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 24),

            headerLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            headerLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            headerLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 28),

            statusLabel.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),

            sectionLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
            sectionLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            sectionLabel.leadingAnchor.constraint(greaterThanOrEqualTo: statusLabel.trailingAnchor, constant: 8)
        ])
    }

    // MARK: - File Operations

    private func openFile() {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            fileSize = (attributes[.size] as? UInt64) ?? 0
            totalRows = Int((fileSize + UInt64(HexConstants.bytesPerRow) - 1) / UInt64(HexConstants.bytesPerRow))

            fileHandle = try FileHandle(forReadingFrom: fileURL)

            chunkCache.countLimit = 32

            tableView.reloadData()
            updateStatusBar(forOffset: 0)
        } catch {
            showAlert(title: "Error", message: "Could not open file: \(error.localizedDescription)")
        }
    }

    /// Reads bytes for a given file offset range using chunked FileHandle reads with caching.
    private func readBytes(at offset: UInt64, count: Int) -> Data? {
        guard let fileHandle = fileHandle else { return nil }
        guard offset < fileSize else { return nil }

        let actualCount = min(count, Int(fileSize - offset))

        // Determine which chunk this offset falls into
        let chunkIndex = Int(offset / UInt64(HexConstants.readChunkSize))
        let chunkStart = UInt64(chunkIndex) * UInt64(HexConstants.readChunkSize)
        let offsetInChunk = Int(offset - chunkStart)

        // Check cache first
        if let cachedData = chunkCache.object(forKey: NSNumber(value: chunkIndex)) {
            let data = cachedData as Data
            let end = min(offsetInChunk + actualCount, data.count)
            guard offsetInChunk < data.count else { return nil }
            return data[offsetInChunk..<end]
        }

        // Read the chunk from file
        do {
            try fileHandle.seek(toOffset: chunkStart)
            let chunkLen = min(HexConstants.readChunkSize, Int(fileSize - chunkStart))
            guard let chunkData = try fileHandle.read(upToCount: chunkLen) else { return nil }

            chunkCache.setObject(chunkData as NSData, forKey: NSNumber(value: chunkIndex))

            let end = min(offsetInChunk + actualCount, chunkData.count)
            guard offsetInChunk < chunkData.count else { return nil }
            return chunkData[offsetInChunk..<end]
        } catch {
            return nil
        }
    }

    // MARK: - Section Lookup

    private func sectionName(forOffset offset: UInt64) -> String? {
        guard let sections = sections else { return nil }
        for section in sections {
            if offset >= section.offset && offset < section.offset + section.size {
                return section.name
            }
        }
        return nil
    }

    private func sectionColor(forOffset offset: UInt64) -> UIColor? {
        guard let sections = sections else { return nil }
        for (index, section) in sections.enumerated() {
            if offset >= section.offset && offset < section.offset + section.size {
                return sectionTintColor(forIndex: index, name: section.name)
            }
        }
        return nil
    }

    private func sectionTintColor(forIndex index: Int, name: String) -> UIColor {
        let lowered = name.lowercased()
        if lowered.contains("__text") || lowered.contains("__stubs") {
            return UIColor.systemBlue.withAlphaComponent(0.06)
        } else if lowered.contains("__data") || lowered.contains("__bss") {
            return UIColor.systemGreen.withAlphaComponent(0.06)
        } else if lowered.contains("__objc") {
            return UIColor.systemPurple.withAlphaComponent(0.06)
        } else if lowered.contains("__linkedit") {
            return UIColor.systemOrange.withAlphaComponent(0.06)
        } else {
            // Cycle through distinguishable tints
            let tints: [UIColor] = [
                UIColor.systemTeal.withAlphaComponent(0.06),
                UIColor.systemPink.withAlphaComponent(0.06),
                UIColor.systemYellow.withAlphaComponent(0.06),
                UIColor.systemIndigo.withAlphaComponent(0.06)
            ]
            return tints[index % tints.count]
        }
    }

    // MARK: - Status Bar

    private func updateStatusBar(forOffset offset: UInt64) {
        statusLabel.text = String(format: "Offset: 0x%08llX  (%llu / %llu bytes)", offset, offset, fileSize)

        if let name = sectionName(forOffset: offset) {
            sectionLabel.text = name
        } else {
            sectionLabel.text = ""
        }
    }

    // MARK: - Actions

    @objc private func showGoToOffset() {
        let alert = UIAlertController(
            title: "Go to Offset",
            message: "Enter a hex (0x...) or decimal offset.",
            preferredStyle: .alert
        )

        alert.addTextField { textField in
            textField.placeholder = "0x00000000"
            textField.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
            textField.autocapitalizationType = .none
            textField.autocorrectionType = .no
        }

        alert.addAction(UIAlertAction(title: "Go", style: .default) { [weak self] _ in
            guard let self = self,
                  let text = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !text.isEmpty else { return }

            let offset: UInt64?
            if text.lowercased().hasPrefix("0x") {
                let hexStr = String(text.dropFirst(2))
                offset = UInt64(hexStr, radix: 16)
            } else {
                offset = UInt64(text)
            }

            guard let targetOffset = offset, targetOffset < self.fileSize else {
                self.showAlert(title: "Invalid Offset",
                               message: "Offset is out of range. File size: \(self.fileSize) bytes.")
                return
            }

            let row = Int(targetOffset / UInt64(HexConstants.bytesPerRow))
            let indexPath = IndexPath(row: row, section: 0)
            self.tableView.scrollToRow(at: indexPath, at: .top, animated: true)
            self.updateStatusBar(forOffset: targetOffset)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func showFileInfo() {
        var info = """
        File: \(fileURL.lastPathComponent)
        Size: \(Constants.formatBytes(Int64(fileSize)))
        Total Rows: \(totalRows)
        """

        if let sections = sections, !sections.isEmpty {
            info += "\n\nSections:"
            for section in sections {
                info += String(format: "\n  %@ (0x%llX, %llu bytes)", section.name, section.offset, section.size)
            }
        }

        let alert = UIAlertController(title: "File Info", message: info, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    /// Scrolls the hex view to the given file offset (called by cross-view navigation).
    func scrollToOffset(_ offset: UInt64) {
        guard offset < fileSize else { return }
        let row = Int(offset / UInt64(HexConstants.bytesPerRow))
        let indexPath = IndexPath(row: row, section: 0)
        tableView.scrollToRow(at: indexPath, at: .top, animated: true)
        updateStatusBar(forOffset: offset)
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITableViewDataSource

extension HexViewerViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return totalRows
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: HexRowCell.reuseIdentifier, for: indexPath) as! HexRowCell

        let rowOffset = UInt64(indexPath.row) * UInt64(HexConstants.bytesPerRow)
        let bytesInRow = min(HexConstants.bytesPerRow, Int(fileSize - rowOffset))

        let data = readBytes(at: rowOffset, count: bytesInRow)
        let bgColor = sectionColor(forOffset: rowOffset)

        cell.configure(
            offset: rowOffset,
            data: data,
            bytesInRow: bytesInRow,
            bytesPerRow: HexConstants.bytesPerRow,
            bytesPerGroup: HexConstants.bytesPerGroup,
            sectionBackground: bgColor
        )

        return cell
    }
}

// MARK: - UITableViewDelegate

extension HexViewerViewController: UITableViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let firstVisible = tableView.indexPathsForVisibleRows?.first else { return }
        let offset = UInt64(firstVisible.row) * UInt64(HexConstants.bytesPerRow)
        updateStatusBar(forOffset: offset)
    }
}

// MARK: - Hex Row Cell

class HexRowCell: UITableViewCell {

    static let reuseIdentifier = "HexRowCell"

    private let hexLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        label.numberOfLines = 1
        label.lineBreakMode = .byClipping
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        selectionStyle = .none
        contentView.addSubview(hexLabel)

        NSLayoutConstraint.activate([
            hexLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            hexLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            hexLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        hexLabel.attributedText = nil
        contentView.backgroundColor = nil
    }

    func configure(offset: UInt64, data: Data?, bytesInRow: Int, bytesPerRow: Int, bytesPerGroup: Int, sectionBackground: UIColor?) {
        contentView.backgroundColor = sectionBackground

        let attributed = NSMutableAttributedString()

        let monoFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let dimAttributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: UIColor.label
        ]
        let offsetAttributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: Constants.Colors.addressColor
        ]
        let asciiNullAttributes: [NSAttributedString.Key: Any] = [
            .font: monoFont,
            .foregroundColor: UIColor.tertiaryLabel
        ]

        // Offset column
        let offsetStr = String(format: "%08llX  ", offset)
        attributed.append(NSAttributedString(string: offsetStr, attributes: offsetAttributes))

        // Hex bytes
        if let data = data {
            for i in 0..<bytesPerRow {
                if i == bytesPerGroup {
                    attributed.append(NSAttributedString(string: " ", attributes: normalAttributes))
                }
                if i < bytesInRow {
                    let byte = data[data.startIndex + i]
                    let hexStr = String(format: "%02X ", byte)
                    let attrs = (byte == 0x00) ? dimAttributes : normalAttributes
                    attributed.append(NSAttributedString(string: hexStr, attributes: attrs))
                } else {
                    attributed.append(NSAttributedString(string: "   ", attributes: normalAttributes))
                }
            }

            // ASCII column
            attributed.append(NSAttributedString(string: " ", attributes: normalAttributes))
            for i in 0..<bytesInRow {
                let byte = data[data.startIndex + i]
                let char: String
                let attrs: [NSAttributedString.Key: Any]
                if byte >= 0x20 && byte <= 0x7E {
                    char = String(UnicodeScalar(byte))
                    attrs = normalAttributes
                } else if byte == 0x00 {
                    char = "."
                    attrs = asciiNullAttributes
                } else {
                    char = "."
                    attrs = dimAttributes
                }
                attributed.append(NSAttributedString(string: char, attributes: attrs))
            }
        }

        hexLabel.attributedText = attributed

        // Accessibility
        isAccessibilityElement = true
        if let data = data {
            let offsetHex = String(format: "%08llX", offset)
            let bytesDescription = (0..<bytesInRow).map { i in
                String(format: "%02X", data[data.startIndex + i])
            }.joined(separator: " ")
            accessibilityLabel = "Offset \(offsetHex): \(bytesDescription)"
        }
        accessibilityTraits = .staticText
    }
}
