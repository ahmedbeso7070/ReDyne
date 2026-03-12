import UIKit

// MARK: - Pattern Match Model

struct PatternMatch {
    let offset: UInt64
    let contextBytes: Data      // surrounding bytes (±8)
    let contextStartOffset: UInt64
    let sectionName: String?
}

// MARK: - Pattern Preset

struct PatternPreset {
    let name: String
    let pattern: String
}

// MARK: - Pattern Scanner View Controller

class PatternScannerViewController: UIViewController {

    // MARK: - Constants

    private enum ScanConstants {
        static let chunkSize = 64 * 1024          // 64 KB
        static let maxMatches = 10_000
        static let contextRadius = 8              // ±8 bytes around match
    }

    private static let presets: [PatternPreset] = [
        PatternPreset(name: "MH_MAGIC_64",        pattern: "CF FA ED FE"),
        PatternPreset(name: "MH_MAGIC",           pattern: "CE FA ED FE"),
        PatternPreset(name: "Fat Header",         pattern: "CA FE BA BE"),
        PatternPreset(name: "NOP Sled (ARM64)",   pattern: "1F 20 03 D5"),
        PatternPreset(name: "BRK (ARM64)",        pattern: "00 00 20 D4"),
        PatternPreset(name: "RET (ARM64)",        pattern: "C0 03 5F D6"),
    ]

    // MARK: - Properties

    private let fileURL: URL
    private weak var navigationDelegate: AnalysisNavigationDelegate?
    private var sections: [SectionDisplayInfo]?

    private var matches: [PatternMatch] = []
    private var scanTask: DispatchWorkItem?
    private var isCancelled = false

    // MARK: - UI Elements

    private let patternTextField: UITextField = {
        let tf = UITextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "e.g. 48 8B 05 ?? ?? ?? ?? or \"Hello\""
        tf.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        tf.borderStyle = .none
        tf.backgroundColor = Constants.Colors.secondaryBackground
        tf.layer.cornerRadius = Constants.UI.cornerRadius
        tf.layer.borderWidth = Constants.UI.borderWidth
        tf.layer.borderColor = UIColor.separator.cgColor
        tf.autocapitalizationType = .allCharacters
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.returnKeyType = .search
        tf.clearButtonMode = .whileEditing
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        tf.leftView = paddingView
        tf.leftViewMode = .always
        tf.accessibilityLabel = "Byte pattern"
        tf.accessibilityHint = "Enter hex bytes separated by spaces, use ?? for wildcards"
        return tf
    }()

    private let patternInfoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
        label.text = "Enter hex bytes (e.g. CF FA ED FE), ?? for wildcard, or \"text\" for ASCII"
        return label
    }()

    private let validityIndicator: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.cornerRadius = 5
        view.backgroundColor = .systemGray4
        return view
    }()

    private let patternLengthLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "0 bytes"
        return label
    }()

    private lazy var scanButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Scan"
        config.image = UIImage(systemName: "magnifyingglass")
        config.imagePadding = 6
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(scanTapped), for: .touchUpInside)
        btn.accessibilityLabel = "Scan for pattern"
        return btn
    }()

    private lazy var presetsButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "Presets"
        config.image = UIImage(systemName: "list.bullet")
        config.imagePadding = 4
        config.cornerStyle = .medium
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.addTarget(self, action: #selector(presetsTapped), for: .touchUpInside)
        btn.accessibilityLabel = "Pattern presets"
        return btn
    }()

    private let progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .default)
        pv.translatesAutoresizingMaskIntoConstraints = false
        pv.isHidden = true
        pv.tintColor = Constants.Colors.accentColor
        return pv
    }()

    private lazy var cancelButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Cancel"
        config.baseForegroundColor = Constants.Colors.errorColor
        let btn = UIButton(configuration: config)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.isHidden = true
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        return btn
    }()

    private let headerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.text = "No results"
        return label
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(PatternMatchCell.self, forCellReuseIdentifier: PatternMatchCell.reuseID)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
        tv.backgroundColor = Constants.Colors.primaryBackground
        tv.keyboardDismissMode = .onDrag
        return tv
    }()

    // MARK: - Initialization

    init(fileURL: URL, sections: [SectionDisplayInfo]? = nil, navigationDelegate: AnalysisNavigationDelegate?) {
        self.fileURL = fileURL
        self.sections = sections
        self.navigationDelegate = navigationDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Pattern Scanner"
        view.backgroundColor = Constants.Colors.primaryBackground
        patternTextField.delegate = self
        setupLayout()
    }

    // MARK: - Layout

    private func setupLayout() {
        let inputStack = UIStackView(arrangedSubviews: [patternTextField])
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputStack.axis = .horizontal
        inputStack.spacing = 8

        let indicatorStack = UIStackView(arrangedSubviews: [validityIndicator, patternLengthLabel])
        indicatorStack.translatesAutoresizingMaskIntoConstraints = false
        indicatorStack.axis = .horizontal
        indicatorStack.spacing = 6
        indicatorStack.alignment = .center

        let buttonStack = UIStackView(arrangedSubviews: [presetsButton, scanButton])
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.axis = .horizontal
        buttonStack.spacing = 8
        buttonStack.distribution = .fillEqually

        let progressStack = UIStackView(arrangedSubviews: [progressView, cancelButton])
        progressStack.translatesAutoresizingMaskIntoConstraints = false
        progressStack.axis = .horizontal
        progressStack.spacing = 8
        progressStack.alignment = .center

        view.addSubview(inputStack)
        view.addSubview(indicatorStack)
        view.addSubview(patternInfoLabel)
        view.addSubview(buttonStack)
        view.addSubview(progressStack)
        view.addSubview(headerLabel)
        view.addSubview(tableView)

        let guide = view.safeAreaLayoutGuide
        let sp = Constants.UI.standardSpacing
        let csp = Constants.UI.compactSpacing

        NSLayoutConstraint.activate([
            inputStack.topAnchor.constraint(equalTo: guide.topAnchor, constant: sp),
            inputStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: sp),
            inputStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -sp),
            patternTextField.heightAnchor.constraint(equalToConstant: 44),

            indicatorStack.topAnchor.constraint(equalTo: inputStack.bottomAnchor, constant: csp),
            indicatorStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: sp),
            validityIndicator.widthAnchor.constraint(equalToConstant: 10),
            validityIndicator.heightAnchor.constraint(equalToConstant: 10),

            patternInfoLabel.centerYAnchor.constraint(equalTo: indicatorStack.centerYAnchor),
            patternInfoLabel.leadingAnchor.constraint(equalTo: indicatorStack.trailingAnchor, constant: 12),
            patternInfoLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -sp),

            buttonStack.topAnchor.constraint(equalTo: indicatorStack.bottomAnchor, constant: csp),
            buttonStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: sp),
            buttonStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -sp),
            buttonStack.heightAnchor.constraint(equalToConstant: 44),

            progressStack.topAnchor.constraint(equalTo: buttonStack.bottomAnchor, constant: csp),
            progressStack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: sp),
            progressStack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -sp),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            headerLabel.topAnchor.constraint(equalTo: progressStack.bottomAnchor, constant: sp),
            headerLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: sp),
            headerLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -sp),

            tableView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: csp),
            tableView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
        ])
    }

    // MARK: - Pattern Parsing

    /// Parses user input into (bytes, mask). Mask `true` means the byte must match.
    private func parsePattern(_ input: String) -> (bytes: [UInt8], mask: [Bool])? {
        var cleaned = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        // Handle quoted ASCII strings: "Hello" -> hex bytes
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count >= 2 {
            let inner = String(cleaned.dropFirst().dropLast())
            guard !inner.isEmpty else { return nil }
            let bytes = Array(inner.utf8)
            let mask = [Bool](repeating: true, count: bytes.count)
            return (bytes, mask)
        }

        // Remove all spaces
        cleaned = cleaned.replacingOccurrences(of: " ", with: "")

        // Must be even length (pairs of hex chars or ??)
        guard cleaned.count % 2 == 0, cleaned.count >= 2 else { return nil }

        var bytes = [UInt8]()
        var mask = [Bool]()
        var idx = cleaned.startIndex

        while idx < cleaned.endIndex {
            let nextIdx = cleaned.index(idx, offsetBy: 2)
            let pair = String(cleaned[idx..<nextIdx])
            if pair == "??" {
                bytes.append(0x00)
                mask.append(false)
            } else if let value = UInt8(pair, radix: 16) {
                bytes.append(value)
                mask.append(true)
            } else {
                return nil
            }
            idx = nextIdx
        }

        return (bytes, mask)
    }

    private func updatePatternValidity() {
        let text = patternTextField.text ?? ""
        if text.isEmpty {
            validityIndicator.backgroundColor = .systemGray4
            patternLengthLabel.text = "0 bytes"
            return
        }
        if let parsed = parsePattern(text) {
            validityIndicator.backgroundColor = Constants.Colors.successColor
            patternLengthLabel.text = "\(parsed.bytes.count) byte\(parsed.bytes.count == 1 ? "" : "s")"
        } else {
            validityIndicator.backgroundColor = Constants.Colors.errorColor
            patternLengthLabel.text = "invalid"
        }
    }

    // MARK: - Section Lookup

    private func sectionName(forOffset offset: UInt64) -> String? {
        guard let sections = sections else { return nil }
        for sec in sections {
            if offset >= sec.offset && offset < sec.offset + sec.size {
                return sec.name
            }
        }
        return nil
    }

    // MARK: - Scanning

    @objc private func scanTapped() {
        patternTextField.resignFirstResponder()
        guard let text = patternTextField.text, !text.isEmpty else { return }
        guard let parsed = parsePattern(text) else {
            showAlert(title: "Invalid Pattern", message: "Could not parse the byte pattern. Use hex pairs (e.g. CF FA ED FE), ?? for wildcards, or \"text\" for ASCII.")
            return
        }
        startScan(bytes: parsed.bytes, mask: parsed.mask)
    }

    private func startScan(bytes patternBytes: [UInt8], mask: [Bool]) {
        // Reset state
        isCancelled = false
        matches.removeAll()
        tableView.reloadData()
        headerLabel.text = "Scanning..."
        progressView.progress = 0
        progressView.isHidden = false
        cancelButton.isHidden = false
        scanButton.isEnabled = false

        let patternLen = patternBytes.count

        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            guard let fileHandle = try? FileHandle(forReadingFrom: self.fileURL) else {
                DispatchQueue.main.async {
                    self.finishScan(error: "Could not open file.")
                }
                return
            }
            defer { try? fileHandle.close() }

            let fileSize: UInt64
            do {
                fileHandle.seekToEndOfFile()
                fileSize = fileHandle.offsetInFile
                fileHandle.seek(toFileOffset: 0)
            }

            guard fileSize > 0 else {
                DispatchQueue.main.async { self.finishScan(error: "File is empty.") }
                return
            }

            let chunkSize = ScanConstants.chunkSize
            // We keep an overlap of (patternLen - 1) bytes between chunks so we
            // don't miss matches that span chunk boundaries.
            let overlap = patternLen - 1
            var currentOffset: UInt64 = 0
            var leftover = Data()
            var foundMatches = [PatternMatch]()

            while currentOffset < fileSize && !self.isCancelled {
                let readSize = min(UInt64(chunkSize), fileSize - currentOffset)
                fileHandle.seek(toFileOffset: currentOffset)
                let rawChunk = fileHandle.readData(ofLength: Int(readSize))
                if rawChunk.isEmpty { break }

                // Prepend leftover bytes from previous chunk
                let chunk: Data
                let baseOffset: UInt64
                if !leftover.isEmpty {
                    chunk = leftover + rawChunk
                    baseOffset = currentOffset - UInt64(leftover.count)
                } else {
                    chunk = rawChunk
                    baseOffset = currentOffset
                }

                let chunkBytes = Array(chunk)
                let searchEnd = chunkBytes.count - patternLen

                if searchEnd >= 0 {
                    for i in 0...searchEnd {
                        if self.isCancelled { break }
                        var matched = true
                        for j in 0..<patternLen {
                            if mask[j] && chunkBytes[i + j] != patternBytes[j] {
                                matched = false
                                break
                            }
                        }
                        if matched {
                            let matchOffset = baseOffset + UInt64(i)

                            // Read context bytes (±8 around match)
                            let ctxStart = matchOffset >= UInt64(ScanConstants.contextRadius)
                                ? matchOffset - UInt64(ScanConstants.contextRadius) : 0
                            let ctxEnd = min(matchOffset + UInt64(patternLen) + UInt64(ScanConstants.contextRadius), fileSize)
                            fileHandle.seek(toFileOffset: ctxStart)
                            let contextData = fileHandle.readData(ofLength: Int(ctxEnd - ctxStart))
                            // Seek back for next chunk read (not strictly needed, we seek at loop top)

                            let secName = self.sectionName(forOffset: matchOffset)
                            foundMatches.append(PatternMatch(
                                offset: matchOffset,
                                contextBytes: contextData,
                                contextStartOffset: ctxStart,
                                sectionName: secName
                            ))

                            if foundMatches.count >= ScanConstants.maxMatches {
                                self.isCancelled = true
                                break
                            }
                        }
                    }
                }

                // Keep overlap for next iteration
                if chunkBytes.count > overlap {
                    leftover = Data(chunkBytes.suffix(overlap))
                } else {
                    leftover = Data()
                }

                currentOffset += readSize

                let progress = Float(currentOffset) / Float(fileSize)
                DispatchQueue.main.async {
                    self.progressView.progress = progress
                }
            }

            DispatchQueue.main.async {
                self.matches = foundMatches
                self.finishScan(error: nil)
            }
        }

        scanTask = work
        DispatchQueue.global(qos: .userInitiated).async(execute: work)
    }

    private func finishScan(error: String?) {
        progressView.isHidden = true
        cancelButton.isHidden = true
        scanButton.isEnabled = true

        if let error = error {
            headerLabel.text = error
        } else if matches.count >= ScanConstants.maxMatches {
            headerLabel.text = "\(matches.count) matches (limit reached)"
        } else {
            headerLabel.text = "\(matches.count) match\(matches.count == 1 ? "" : "es") found"
        }

        tableView.reloadData()
    }

    @objc private func cancelTapped() {
        isCancelled = true
        scanTask?.cancel()
    }

    // MARK: - Presets

    @objc private func presetsTapped() {
        let alert = UIAlertController(title: "Pattern Presets", message: nil, preferredStyle: .actionSheet)
        for preset in Self.presets {
            alert.addAction(UIAlertAction(title: "\(preset.name)  (\(preset.pattern))", style: .default) { [weak self] _ in
                self?.patternTextField.text = preset.pattern
                self?.updatePatternValidity()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = presetsButton
            popover.sourceRect = presetsButton.bounds
        }
        present(alert, animated: true)
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - UITextFieldDelegate

extension PatternScannerViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        scanTapped()
        return true
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.updatePatternValidity()
        }
        return true
    }
}

// MARK: - UITableViewDataSource & Delegate

extension PatternScannerViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return matches.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: PatternMatchCell.reuseID, for: indexPath) as! PatternMatchCell
        cell.configure(with: matches[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let match = matches[indexPath.row]
        navigationDelegate?.navigateToHexView(atOffset: match.offset)
    }
}

// MARK: - Pattern Match Cell

private class PatternMatchCell: UITableViewCell {

    static let reuseID = "PatternMatchCell"

    private let offsetLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = Constants.Colors.accentColor
        return label
    }()

    private let sectionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = Constants.Colors.warningColor
        return label
    }()

    private let contextLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        contentView.addSubview(offsetLabel)
        contentView.addSubview(sectionLabel)
        contentView.addSubview(contextLabel)
        accessoryType = .disclosureIndicator

        NSLayoutConstraint.activate([
            offsetLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            offsetLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            sectionLabel.centerYAnchor.constraint(equalTo: offsetLabel.centerYAnchor),
            sectionLabel.leadingAnchor.constraint(equalTo: offsetLabel.trailingAnchor, constant: 12),
            sectionLabel.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),

            contextLabel.topAnchor.constraint(equalTo: offsetLabel.bottomAnchor, constant: 4),
            contextLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            contextLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            contextLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])
    }

    func configure(with match: PatternMatch) {
        offsetLabel.text = String(format: "0x%08llX", match.offset)
        sectionLabel.text = match.sectionName ?? ""
        contextLabel.text = match.contextBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
