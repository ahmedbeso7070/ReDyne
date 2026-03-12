import UIKit

class AddressConverterViewController: UIViewController {

    // MARK: - Properties

    private let output: DecompiledOutput
    private weak var navigationDelegate: AnalysisNavigationDelegate?

    /// Resolved conversion result, updated each time the user triggers a lookup.
    private struct ConversionResult {
        let fileOffset: UInt64
        let virtualAddress: UInt64
        let segmentName: String
        let sectionName: String?
        let nearestSymbol: String?
        let symbolOffset: Int64 // signed delta from nearest symbol
        let protection: String
    }

    private var currentResult: ConversionResult?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.alwaysBounceVertical = true
        sv.keyboardDismissMode = .interactive
        return sv
    }()

    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = Constants.UI.standardSpacing
        return stack
    }()

    // -- Input section --

    private let inputField: UITextField = {
        let field = UITextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.placeholder = "0x100004000 or 268451840"
        field.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        field.borderStyle = .roundedRect
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .go
        return field
    }()

    private let modeControl: UISegmentedControl = {
        let control = UISegmentedControl(items: ["File Offset", "VM Address"])
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        return control
    }()

    private lazy var convertButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Convert"
        config.image = UIImage(systemName: "arrow.left.arrow.right.circle")
        config.imagePadding = 6
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(performConversion), for: .touchUpInside)
        return button
    }()

    // -- Results section --

    private let resultsTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.isScrollEnabled = false
        table.allowsSelection = true
        return table
    }()

    private var resultsTableHeightConstraint: NSLayoutConstraint!

    // -- Action buttons --

    private lazy var viewInHexButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "View in Hex"
        config.image = UIImage(systemName: "text.magnifyingglass")
        config.imagePadding = 6
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(viewInHex), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()

    private lazy var viewInDisassemblyButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.title = "View in Disassembly"
        config.image = UIImage(systemName: "chevron.left.forwardslash.chevron.right")
        config.imagePadding = 6
        config.cornerStyle = .medium
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(viewInDisassembly), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()

    // -- Error / status label --

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.textColor = Constants.Colors.errorColor
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    // MARK: - Result Row Definitions

    private enum ResultRow: Int, CaseIterable {
        case fileOffsetHex = 0
        case fileOffsetDec
        case virtualAddressHex
        case virtualAddressDec
        case segmentName
        case sectionName
        case nearestSymbol
        case protection

        var title: String {
            switch self {
            case .fileOffsetHex:     return "File Offset (hex)"
            case .fileOffsetDec:     return "File Offset (dec)"
            case .virtualAddressHex: return "VM Address (hex)"
            case .virtualAddressDec: return "VM Address (dec)"
            case .segmentName:       return "Segment"
            case .sectionName:       return "Section"
            case .nearestSymbol:     return "Nearest Symbol"
            case .protection:        return "Protection"
            }
        }
    }

    // MARK: - Initialization

    init(output: DecompiledOutput, navigationDelegate: AnalysisNavigationDelegate?) {
        self.output = output
        self.navigationDelegate = navigationDelegate
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Address Converter"
        view.backgroundColor = Constants.Colors.primaryBackground

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissSelf)
        )

        inputField.delegate = self

        setupLayout()
        setupResultsTable()
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        // Input card
        let inputCard = makeCard()
        let inputTitle = makeSectionTitle("Input")
        inputCard.addArrangedSubview(inputTitle)
        inputCard.addArrangedSubview(modeControl)
        inputCard.addArrangedSubview(inputField)
        inputCard.addArrangedSubview(convertButton)

        // Results card
        let resultsCard = makeCard()
        let resultsTitle = makeSectionTitle("Results")
        resultsCard.addArrangedSubview(resultsTitle)
        resultsCard.addArrangedSubview(statusLabel)
        resultsCard.addArrangedSubview(resultsTableView)

        resultsTableHeightConstraint = resultsTableView.heightAnchor.constraint(equalToConstant: 0)
        resultsTableHeightConstraint.isActive = true

        // Actions card
        let actionsCard = makeCard()
        let actionsTitle = makeSectionTitle("Quick Actions")
        actionsCard.addArrangedSubview(actionsTitle)

        let buttonStack = UIStackView(arrangedSubviews: [viewInHexButton, viewInDisassemblyButton])
        buttonStack.axis = .horizontal
        buttonStack.spacing = Constants.UI.compactSpacing
        buttonStack.distribution = .fillEqually
        actionsCard.addArrangedSubview(buttonStack)

        contentStack.addArrangedSubview(inputCard)
        contentStack.addArrangedSubview(resultsCard)
        contentStack.addArrangedSubview(actionsCard)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.UI.standardSpacing),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.UI.standardSpacing),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.UI.standardSpacing),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.UI.standardSpacing),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -Constants.UI.standardSpacing * 2),

            inputField.heightAnchor.constraint(equalToConstant: 44),
            convertButton.heightAnchor.constraint(equalToConstant: 44),
            viewInHexButton.heightAnchor.constraint(equalToConstant: 44),
            viewInDisassemblyButton.heightAnchor.constraint(equalToConstant: 44),
        ])
    }

    private func makeCard() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = Constants.UI.compactSpacing
        stack.layoutMargins = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layer.cornerRadius = Constants.UI.cornerRadius
        stack.backgroundColor = Constants.Colors.secondaryBackground
        return stack
    }

    private func makeSectionTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }

    private func setupResultsTable() {
        resultsTableView.dataSource = self
        resultsTableView.delegate = self
        resultsTableView.register(UITableViewCell.self, forCellReuseIdentifier: "ResultCell")
        resultsTableView.backgroundColor = .clear
    }

    // MARK: - Conversion Logic

    @objc private func performConversion() {
        inputField.resignFirstResponder()

        guard let raw = inputField.text?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            showStatus("Enter an address to convert.", isError: true)
            return
        }

        guard let inputValue = parseAddress(raw) else {
            showStatus("Invalid address format. Use hex (0x...) or decimal.", isError: true)
            return
        }

        let isFileOffset = (modeControl.selectedSegmentIndex == 0)

        guard let segments = output.segments as? [SegmentModel], !segments.isEmpty else {
            showStatus("No segment data available for conversion.", isError: true)
            return
        }

        if isFileOffset {
            guard let result = convertFileOffsetToVM(inputValue, segments: segments) else {
                showStatus("File offset 0x\(String(inputValue, radix: 16, uppercase: true)) does not fall within any known segment.", isError: true)
                clearResult()
                return
            }
            currentResult = result
        } else {
            guard let result = convertVMToFileOffset(inputValue, segments: segments) else {
                showStatus("VM address 0x\(String(inputValue, radix: 16, uppercase: true)) does not fall within any known segment.", isError: true)
                clearResult()
                return
            }
            currentResult = result
        }

        statusLabel.isHidden = true
        resultsTableView.reloadData()
        updateTableHeight()
        viewInHexButton.isEnabled = true
        viewInDisassemblyButton.isEnabled = true
    }

    private func convertFileOffsetToVM(_ offset: UInt64, segments: [SegmentModel]) -> ConversionResult? {
        for segment in segments {
            let segStart = segment.fileOffset
            let segEnd = segment.fileOffset + segment.fileSize
            guard segStart <= offset, offset < segEnd else { continue }

            let vmAddr = segment.vmAddress + (offset - segment.fileOffset)
            let section = findSection(vmAddress: vmAddr)
            let (symbolName, symbolDelta) = findNearestSymbol(address: vmAddr)

            return ConversionResult(
                fileOffset: offset,
                virtualAddress: vmAddr,
                segmentName: segment.name,
                sectionName: section?.sectionName,
                nearestSymbol: symbolName,
                symbolOffset: symbolDelta,
                protection: protectionString(for: segment)
            )
        }
        return nil
    }

    private func convertVMToFileOffset(_ vmAddr: UInt64, segments: [SegmentModel]) -> ConversionResult? {
        for segment in segments {
            let segStart = segment.vmAddress
            let segEnd = segment.vmAddress + segment.vmSize
            guard segStart <= vmAddr, vmAddr < segEnd else { continue }

            let fileOff = segment.fileOffset + (vmAddr - segment.vmAddress)
            let section = findSection(vmAddress: vmAddr)
            let (symbolName, symbolDelta) = findNearestSymbol(address: vmAddr)

            return ConversionResult(
                fileOffset: fileOff,
                virtualAddress: vmAddr,
                segmentName: segment.name,
                sectionName: section?.sectionName,
                nearestSymbol: symbolName,
                symbolOffset: symbolDelta,
                protection: protectionString(for: segment)
            )
        }
        return nil
    }

    private func findSection(vmAddress: UInt64) -> SectionModel? {
        guard let sections = output.sections as? [SectionModel] else { return nil }
        for section in sections {
            let secStart = section.address
            let secEnd = section.address + section.size
            if secStart <= vmAddress, vmAddress < secEnd {
                return section
            }
        }
        return nil
    }

    private func findNearestSymbol(address: UInt64) -> (String?, Int64) {
        guard let symbols = output.symbols as? [SymbolModel], !symbols.isEmpty else {
            return (nil, 0)
        }

        var bestSymbol: SymbolModel?
        var bestDelta: Int64 = Int64.max

        for symbol in symbols {
            guard symbol.isDefined else { continue }
            let delta = Int64(bitPattern: address) - Int64(bitPattern: symbol.address)
            // Prefer symbols at or before the address (delta >= 0), closest first
            if delta >= 0, delta < bestDelta {
                bestDelta = delta
                bestSymbol = symbol
            }
        }

        guard let sym = bestSymbol else { return (nil, 0) }
        let displayName = sym.demangledName ?? sym.name
        return (displayName, bestDelta)
    }

    private func protectionString(for segment: SegmentModel) -> String {
        // Use the pre-formatted protection string from the model
        let prot = segment.protection ?? "---"
        return prot.isEmpty ? "---" : prot
    }

    // MARK: - Address Parsing

    private func parseAddress(_ raw: String) -> UInt64? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        if trimmed.lowercased().hasPrefix("0x") {
            let hexStr = String(trimmed.dropFirst(2))
            return UInt64(hexStr, radix: 16)
        }

        // Try decimal first, then hex as fallback
        if let dec = UInt64(trimmed, radix: 10) {
            return dec
        }
        return UInt64(trimmed, radix: 16)
    }

    // MARK: - UI Helpers

    private func showStatus(_ message: String, isError: Bool) {
        statusLabel.text = message
        statusLabel.textColor = isError ? Constants.Colors.errorColor : Constants.Colors.successColor
        statusLabel.isHidden = false
    }

    private func clearResult() {
        currentResult = nil
        resultsTableView.reloadData()
        updateTableHeight()
        viewInHexButton.isEnabled = false
        viewInDisassemblyButton.isEnabled = false
    }

    private func updateTableHeight() {
        resultsTableView.layoutIfNeeded()
        let height = currentResult != nil ? resultsTableView.contentSize.height : 0
        resultsTableHeightConstraint.constant = height
        UIView.animate(withDuration: Constants.UI.animationDuration) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Actions

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func viewInHex() {
        guard let result = currentResult else { return }
        dismiss(animated: true) { [weak self] in
            self?.navigationDelegate?.navigateToHexView(atOffset: result.fileOffset)
        }
    }

    @objc private func viewInDisassembly() {
        guard let result = currentResult else { return }
        dismiss(animated: true) { [weak self] in
            self?.navigationDelegate?.navigateToDisassembly(atAddress: result.virtualAddress)
        }
    }

    // MARK: - Result Value Formatting

    private func valueForRow(_ row: ResultRow) -> String {
        guard let r = currentResult else { return "---" }
        switch row {
        case .fileOffsetHex:     return Constants.formatAddress(r.fileOffset)
        case .fileOffsetDec:     return "\(r.fileOffset)"
        case .virtualAddressHex: return Constants.formatAddress(r.virtualAddress)
        case .virtualAddressDec: return "\(r.virtualAddress)"
        case .segmentName:       return r.segmentName
        case .sectionName:       return r.sectionName ?? "N/A"
        case .nearestSymbol:
            guard let sym = r.nearestSymbol else { return "N/A" }
            if r.symbolOffset == 0 {
                return sym
            }
            return "\(sym) + 0x\(String(r.symbolOffset, radix: 16))"
        case .protection:        return r.protection
        }
    }
}

// MARK: - UITableViewDataSource

extension AddressConverterViewController: UITableViewDataSource {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return currentResult != nil ? ResultRow.allCases.count : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ResultCell", for: indexPath)
        let row = ResultRow(rawValue: indexPath.row) ?? .fileOffsetHex

        var content = cell.defaultContentConfiguration()
        content.text = row.title
        content.textProperties.font = .systemFont(ofSize: 13, weight: .regular)
        content.textProperties.color = .secondaryLabel

        content.secondaryText = valueForRow(row)
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        content.secondaryTextProperties.color = .label

        cell.contentConfiguration = content
        cell.backgroundColor = .clear
        cell.selectionStyle = .default
        return cell
    }
}

// MARK: - UITableViewDelegate

extension AddressConverterViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard currentResult != nil else { return }
        let row = ResultRow(rawValue: indexPath.row) ?? .fileOffsetHex
        let value = valueForRow(row)
        UIPasteboard.general.string = value

        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Brief flash to indicate copy
        if let cell = tableView.cellForRow(at: indexPath) {
            let original = cell.backgroundColor
            UIView.animate(withDuration: 0.15, animations: {
                cell.backgroundColor = Constants.Colors.accentColor.withAlphaComponent(0.15)
            }) { _ in
                UIView.animate(withDuration: 0.15) {
                    cell.backgroundColor = original
                }
            }
        }
    }
}

// MARK: - UITextFieldDelegate

extension AddressConverterViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        performConversion()
        return true
    }
}
