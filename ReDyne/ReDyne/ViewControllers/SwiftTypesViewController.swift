import UIKit

// MARK: - Grouping Mode

private enum SwiftTypeGrouping: Int, CaseIterable {
    case byKind = 0
    case byModule = 1

    var title: String {
        switch self {
        case .byKind:   return "By Kind"
        case .byModule: return "By Module"
        }
    }
}

// MARK: - SwiftTypesViewController

/// Displays reconstructed Swift types in a searchable, grouped table view.
/// Each cell shows the type name, kind icon, field count, and conformance count.
/// Tapping a cell shows the full reconstructed definition with syntax highlighting.
class SwiftTypesViewController: UIViewController {

    // MARK: - Properties

    private let allTypes: [ReconstructedSwiftType]
    private var filteredTypes: [ReconstructedSwiftType] = []
    private var sections: [(title: String, types: [ReconstructedSwiftType])] = []
    private var grouping: SwiftTypeGrouping = .byKind

    // MARK: - UI Elements

    private lazy var searchBar: UISearchBar = {
        let bar = UISearchBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.placeholder = "Filter types..."
        bar.searchBarStyle = .minimal
        bar.delegate = self
        return bar
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let items = SwiftTypeGrouping.allCases.map { $0.title }
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(groupingChanged), for: .valueChanged)
        return control
    }()

    private lazy var tableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(SwiftTypeCell.self, forCellReuseIdentifier: SwiftTypeCell.reuseID)
        table.backgroundColor = Constants.Colors.primaryBackground
        table.keyboardDismissMode = .onDrag
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 64
        return table
    }()

    private lazy var summaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    // MARK: - Init

    init(types: [ReconstructedSwiftType]) {
        self.allTypes = types
        self.filteredTypes = types
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Swift Types"
        view.backgroundColor = Constants.Colors.primaryBackground
        setupUI()
        rebuildSections()
        updateSummary()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.addSubview(summaryLabel)
        view.addSubview(segmentedControl)
        view.addSubview(searchBar)
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            summaryLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            summaryLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            segmentedControl.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 8),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Data

    @objc private func groupingChanged() {
        grouping = SwiftTypeGrouping(rawValue: segmentedControl.selectedSegmentIndex) ?? .byKind
        rebuildSections()
        tableView.reloadData()
    }

    private func rebuildSections() {
        switch grouping {
        case .byKind:
            let grouped = Dictionary(grouping: filteredTypes) { $0.kindLabel }
            let order = ["class", "struct", "enum", "protocol", "type"]
            sections = order.compactMap { kind in
                guard let types = grouped[kind], !types.isEmpty else { return nil }
                return (title: kind.capitalized + " (\(types.count))", types: types)
            }
        case .byModule:
            let grouped = Dictionary(grouping: filteredTypes) { type -> String in
                type.moduleName.isEmpty ? "(Unknown Module)" : type.moduleName
            }
            sections = grouped.keys.sorted().map { module in
                let types = grouped[module]!
                return (title: module + " (\(types.count))", types: types)
            }
        }
    }

    private func updateSummary() {
        let total = allTypes.count
        let classes = allTypes.filter { $0.kind == .init(rawValue: 0) }.count
        let structs = allTypes.filter { $0.kind == .init(rawValue: 1) }.count
        let enums = allTypes.filter { $0.kind == .init(rawValue: 2) }.count
        summaryLabel.text = "\(total) types: \(classes) classes, \(structs) structs, \(enums) enums"
    }

    private func applyFilter(_ query: String) {
        if query.isEmpty {
            filteredTypes = allTypes
        } else {
            let lowered = query.lowercased()
            filteredTypes = allTypes.filter { type in
                type.name.lowercased().contains(lowered) ||
                type.moduleName.lowercased().contains(lowered) ||
                type.kindLabel.lowercased().contains(lowered)
            }
        }
        rebuildSections()
        tableView.reloadData()
    }

    // MARK: - Detail Presentation

    private func showDetail(for type: ReconstructedSwiftType) {
        let detailVC = SwiftTypeDetailViewController(type: type)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - UITableViewDataSource / Delegate

extension SwiftTypesViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].types.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: SwiftTypeCell.reuseID, for: indexPath) as! SwiftTypeCell
        let type = sections[indexPath.section].types[indexPath.row]
        cell.configure(with: type)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let type = sections[indexPath.section].types[indexPath.row]
        showDetail(for: type)
    }
}

// MARK: - UISearchBarDelegate

extension SwiftTypesViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        applyFilter(searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - SwiftTypeCell

private class SwiftTypeCell: UITableViewCell {

    static let reuseID = "SwiftTypeCell"

    private let kindImageView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = Constants.Colors.accentColor
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .monospacedSystemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .regular)
        label.textColor = .secondaryLabel
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
        contentView.addSubview(kindImageView)
        contentView.addSubview(nameLabel)
        contentView.addSubview(detailLabel)

        NSLayoutConstraint.activate([
            kindImageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            kindImageView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            kindImageView.widthAnchor.constraint(equalToConstant: 28),
            kindImageView.heightAnchor.constraint(equalToConstant: 28),

            nameLabel.leadingAnchor.constraint(equalTo: kindImageView.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            nameLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            detailLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            detailLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            detailLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(with type: ReconstructedSwiftType) {
        kindImageView.image = UIImage(systemName: type.kindIcon)
        nameLabel.text = type.name
        accessoryType = .disclosureIndicator

        var parts: [String] = [type.kindString]
        parts.append("\(type.fieldCount) field\(type.fieldCount == 1 ? "" : "s")")
        if type.conformanceCount > 0 {
            parts.append("\(type.conformanceCount) conformance\(type.conformanceCount == 1 ? "" : "s")")
        }
        if type.isGeneric {
            parts.append("generic")
        }
        detailLabel.text = parts.joined(separator: " \u{00B7} ")
    }
}

// MARK: - SwiftTypeDetailViewController

/// Shows the full reconstructed definition for a single Swift type
/// with syntax-highlighted pseudocode.
private class SwiftTypeDetailViewController: UIViewController {

    private let type: ReconstructedSwiftType

    private lazy var textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.isEditable = false
        tv.backgroundColor = Constants.Colors.secondaryBackground
        tv.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        tv.alwaysBounceVertical = true
        return tv
    }()

    init(type: ReconstructedSwiftType) {
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = type.name
        view.backgroundColor = Constants.Colors.primaryBackground

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "doc.on.doc"),
            style: .plain,
            target: self,
            action: #selector(copyDefinition)
        )

        view.addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        textView.attributedText = highlightedDefinition(type.definition)
    }

    @objc private func copyDefinition() {
        UIPasteboard.general.string = type.definition
        let alert = UIAlertController(title: "Copied", message: "Type definition copied to clipboard.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Syntax Highlighting

    private func highlightedDefinition(_ source: String) -> NSAttributedString {
        let fontSize: CGFloat = 14
        let baseFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)

        let baseColor: UIColor = .label
        let keywordColor: UIColor = UIColor(red: 0.67, green: 0.25, blue: 0.67, alpha: 1.0) // purple
        let typeColor: UIColor = UIColor(red: 0.16, green: 0.56, blue: 0.70, alpha: 1.0)    // teal
        let commentColor: UIColor = UIColor(red: 0.42, green: 0.56, blue: 0.35, alpha: 1.0) // green
        let stringColor: UIColor = UIColor(red: 0.80, green: 0.30, blue: 0.20, alpha: 1.0)  // red-orange

        let attributed = NSMutableAttributedString(string: source, attributes: [
            .font: baseFont,
            .foregroundColor: baseColor
        ])

        let nsSource = source as NSString

        // Highlight comments
        highlightPattern("//.*", in: attributed, source: nsSource, color: commentColor, font: baseFont)

        // Highlight Swift keywords
        let keywords = [
            "struct", "class", "enum", "protocol",
            "var", "let", "case", "indirect",
            "func", "init", "deinit",
            "public", "private", "internal", "open", "fileprivate",
            "static", "final", "override", "mutating",
            "import", "typealias", "associatedtype",
            "where", "extension", "subscript"
        ]
        for keyword in keywords {
            highlightPattern("\\b\(keyword)\\b", in: attributed, source: nsSource, color: keywordColor, font: boldFont)
        }

        // Highlight known type names
        let builtinTypes = [
            "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
            "UInt8", "UInt16", "UInt32", "UInt64",
            "Float", "Double", "Bool", "String",
            "Void", "Never", "Any", "AnyObject",
            "Optional", "Array", "Dictionary", "Set"
        ]
        for typeName in builtinTypes {
            highlightPattern("\\b\(typeName)\\b", in: attributed, source: nsSource, color: typeColor, font: baseFont)
        }

        // Highlight the type's own name
        highlightPattern("\\b\(NSRegularExpression.escapedPattern(for: type.name))\\b",
                         in: attributed, source: nsSource, color: stringColor, font: boldFont)

        return attributed
    }

    private func highlightPattern(_ pattern: String,
                                  in attributed: NSMutableAttributedString,
                                  source: NSString,
                                  color: UIColor,
                                  font: UIFont) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: source.length)
        for match in regex.matches(in: source as String, range: range) {
            attributed.addAttributes([
                .foregroundColor: color,
                .font: font
            ], range: match.range)
        }
    }
}
