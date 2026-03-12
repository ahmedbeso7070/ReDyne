import UIKit

// MARK: - Search Result Category

enum SearchResultCategory: String, CaseIterable {
    case symbols = "Symbols"
    case functions = "Functions"
    case strings = "Strings"
    case objcClasses = "ObjC Classes"
    case objcMethods = "ObjC Methods"
    case imports = "Imports"
    case exports = "Exports"
    case sections = "Sections"
    case segments = "Segments"
}

// MARK: - Search Result Item

struct SearchResultItem {
    let category: SearchResultCategory
    let title: String
    let subtitle: String?
    let address: UInt64?

    // Hold a reference to the original model for navigation
    let symbol: SymbolModel?
    let function: FunctionModel?
    let string: StringModel?

    init(category: SearchResultCategory, title: String, subtitle: String? = nil, address: UInt64? = nil,
         symbol: SymbolModel? = nil, function: FunctionModel? = nil, string: StringModel? = nil) {
        self.category = category
        self.title = title
        self.subtitle = subtitle
        self.address = address
        self.symbol = symbol
        self.function = function
        self.string = string
    }
}

// MARK: - Search Result Section

struct SearchResultSection {
    let category: SearchResultCategory
    let items: [SearchResultItem]

    var title: String {
        return "\(category.rawValue) (\(items.count))"
    }
}

// MARK: - GlobalSearchDelegate

protocol GlobalSearchDelegate: AnyObject {
    func globalSearch(_ controller: GlobalSearchViewController, didSelectSymbol symbol: SymbolModel)
    func globalSearch(_ controller: GlobalSearchViewController, didSelectFunction function: FunctionModel)
    func globalSearch(_ controller: GlobalSearchViewController, didSelectString string: StringModel)
}

// MARK: - GlobalSearchViewController

class GlobalSearchViewController: UIViewController {

    // MARK: - Properties

    private let output: DecompiledOutput
    weak var delegate: GlobalSearchDelegate?

    private var sections: [SearchResultSection] = []
    private var searchWorkItem: DispatchWorkItem?

    // MARK: - UI Elements

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "Search symbols, strings, functions..."
        sc.searchBar.autocapitalizationType = .none
        sc.searchBar.autocorrectionType = .no
        return sc
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .grouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "SearchResultCell")
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 52
        tv.keyboardDismissMode = .onDrag
        return tv
    }()

    private lazy var emptyStateLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Search across all analysis data"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private lazy var noResultsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "No results"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    // MARK: - Initialization

    init(output: DecompiledOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Global Search"
        view.backgroundColor = Constants.Colors.primaryBackground

        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        let closeButton = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(dismissSearch))
        navigationItem.leftBarButtonItem = closeButton

        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.searchController.searchBar.becomeFirstResponder()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(tableView)
        view.addSubview(emptyStateLabel)
        view.addSubview(noResultsLabel)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyStateLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            emptyStateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            emptyStateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),

            noResultsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            noResultsLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            noResultsLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
            noResultsLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),
        ])
    }

    // MARK: - Actions

    @objc private func dismissSearch() {
        dismiss(animated: true)
    }

    // MARK: - Search Logic

    private func performSearch(query: String) {
        searchWorkItem?.cancel()

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            sections = []
            tableView.reloadData()
            emptyStateLabel.isHidden = false
            noResultsLabel.isHidden = true
            return
        }

        emptyStateLabel.isHidden = true

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let results = self.searchAllCategories(query: query)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.sections = results
                self.tableView.reloadData()
                self.noResultsLabel.isHidden = !results.isEmpty
            }
        }

        searchWorkItem = workItem
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func searchAllCategories(query: String) -> [SearchResultSection] {
        let lowercasedQuery = query.lowercased()
        var resultSections: [SearchResultSection] = []

        // Symbols
        let symbolResults = searchSymbols(query: lowercasedQuery)
        if !symbolResults.isEmpty {
            resultSections.append(SearchResultSection(category: .symbols, items: symbolResults))
        }

        // Functions
        let functionResults = searchFunctions(query: lowercasedQuery)
        if !functionResults.isEmpty {
            resultSections.append(SearchResultSection(category: .functions, items: functionResults))
        }

        // Strings
        let stringResults = searchStrings(query: lowercasedQuery)
        if !stringResults.isEmpty {
            resultSections.append(SearchResultSection(category: .strings, items: stringResults))
        }

        // ObjC Classes
        let objcClassResults = searchObjCClasses(query: lowercasedQuery)
        if !objcClassResults.isEmpty {
            resultSections.append(SearchResultSection(category: .objcClasses, items: objcClassResults))
        }

        // ObjC Methods
        let objcMethodResults = searchObjCMethods(query: lowercasedQuery)
        if !objcMethodResults.isEmpty {
            resultSections.append(SearchResultSection(category: .objcMethods, items: objcMethodResults))
        }

        // Imports
        let importResults = searchImports(query: lowercasedQuery)
        if !importResults.isEmpty {
            resultSections.append(SearchResultSection(category: .imports, items: importResults))
        }

        // Exports
        let exportResults = searchExports(query: lowercasedQuery)
        if !exportResults.isEmpty {
            resultSections.append(SearchResultSection(category: .exports, items: exportResults))
        }

        // Sections
        let sectionResults = searchSections(query: lowercasedQuery)
        if !sectionResults.isEmpty {
            resultSections.append(SearchResultSection(category: .sections, items: sectionResults))
        }

        // Segments
        let segmentResults = searchSegments(query: lowercasedQuery)
        if !segmentResults.isEmpty {
            resultSections.append(SearchResultSection(category: .segments, items: segmentResults))
        }

        // Sort by result count (most matches first)
        resultSections.sort { $0.items.count > $1.items.count }

        return resultSections
    }

    // MARK: - Category Search Methods

    private func searchSymbols(query: String) -> [SearchResultItem] {
        guard let symbols = output.symbols as? [SymbolModel] else { return [] }
        var results: [SearchResultItem] = []

        for symbol in symbols {
            let nameMatch = symbol.name.lowercased().contains(query)
            let demangledMatch = symbol.demangledName?.lowercased().contains(query) ?? false

            if nameMatch || demangledMatch {
                let displayName = symbol.demangledName ?? symbol.name
                let subtitle = "\(symbol.type) | \(symbol.scope)"
                results.append(SearchResultItem(
                    category: .symbols,
                    title: displayName,
                    subtitle: subtitle,
                    address: symbol.address,
                    symbol: symbol
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchFunctions(query: String) -> [SearchResultItem] {
        guard let functions = output.functions as? [FunctionModel] else { return [] }
        var results: [SearchResultItem] = []

        for function in functions {
            let nameMatch = function.name.lowercased().contains(query)
            let demangledMatch = function.demangledName?.lowercased().contains(query) ?? false

            if nameMatch || demangledMatch {
                let displayName = function.demangledName ?? function.name
                let subtitle = "\(function.instructionCount) instructions"
                results.append(SearchResultItem(
                    category: .functions,
                    title: displayName,
                    subtitle: subtitle,
                    address: function.startAddress,
                    function: function
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchStrings(query: String) -> [SearchResultItem] {
        guard let strings = output.strings as? [StringModel] else { return [] }
        var results: [SearchResultItem] = []

        for string in strings {
            if string.content.lowercased().contains(query) {
                let subtitle = string.section
                results.append(SearchResultItem(
                    category: .strings,
                    title: string.content,
                    subtitle: subtitle,
                    address: string.address,
                    string: string
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchObjCClasses(query: String) -> [SearchResultItem] {
        guard let objcAnalysis = output.objcAnalysis as? ObjCAnalysisResult else { return [] }
        var results: [SearchResultItem] = []

        for cls in objcAnalysis.classes {
            if cls.name.lowercased().contains(query) {
                let subtitle = cls.hierarchy
                results.append(SearchResultItem(
                    category: .objcClasses,
                    title: cls.name,
                    subtitle: subtitle,
                    address: cls.address
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchObjCMethods(query: String) -> [SearchResultItem] {
        guard let objcAnalysis = output.objcAnalysis as? ObjCAnalysisResult else { return [] }
        var results: [SearchResultItem] = []

        for cls in objcAnalysis.classes {
            for method in cls.instanceMethods {
                if method.name.lowercased().contains(query) {
                    results.append(SearchResultItem(
                        category: .objcMethods,
                        title: method.displayName,
                        subtitle: cls.name,
                        address: method.implementation
                    ))
                }
                if results.count >= 200 { return results }
            }

            for method in cls.classMethods {
                if method.name.lowercased().contains(query) {
                    results.append(SearchResultItem(
                        category: .objcMethods,
                        title: method.displayName,
                        subtitle: cls.name,
                        address: method.implementation
                    ))
                }
                if results.count >= 200 { return results }
            }
        }

        return results
    }

    private func searchImports(query: String) -> [SearchResultItem] {
        guard let importExport = output.importExportAnalysis as? ImportExportAnalysis else { return [] }
        var results: [SearchResultItem] = []

        for imp in importExport.imports {
            if imp.name.lowercased().contains(query) {
                results.append(SearchResultItem(
                    category: .imports,
                    title: imp.displayName,
                    subtitle: imp.libraryName,
                    address: imp.address
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchExports(query: String) -> [SearchResultItem] {
        guard let importExport = output.importExportAnalysis as? ImportExportAnalysis else { return [] }
        var results: [SearchResultItem] = []

        for exp in importExport.exports {
            if exp.name.lowercased().contains(query) {
                results.append(SearchResultItem(
                    category: .exports,
                    title: exp.displayName,
                    subtitle: exp.exportType,
                    address: exp.address
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchSections(query: String) -> [SearchResultItem] {
        guard let sections = output.sections as? [SectionModel] else { return [] }
        var results: [SearchResultItem] = []

        for section in sections {
            let fullName = "\(section.segmentName),\(section.sectionName)"
            if section.sectionName.lowercased().contains(query) || fullName.lowercased().contains(query) {
                let subtitle = "Size: \(section.size) bytes"
                results.append(SearchResultItem(
                    category: .sections,
                    title: fullName,
                    subtitle: subtitle,
                    address: section.address
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }

    private func searchSegments(query: String) -> [SearchResultItem] {
        guard let segments = output.segments as? [SegmentModel] else { return [] }
        var results: [SearchResultItem] = []

        for segment in segments {
            if segment.name.lowercased().contains(query) {
                let subtitle = "VM Size: \(segment.vmSize) bytes | \(segment.protection)"
                results.append(SearchResultItem(
                    category: .segments,
                    title: segment.name,
                    subtitle: subtitle,
                    address: segment.vmAddress
                ))
            }

            if results.count >= 200 { break }
        }

        return results
    }
}

// MARK: - UISearchResultsUpdating

extension GlobalSearchViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        let query = searchController.searchBar.text ?? ""
        performSearch(query: query)
    }
}

// MARK: - UITableViewDataSource

extension GlobalSearchViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].items.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return sections[section].title
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SearchResultCell", for: indexPath)
        let item = sections[indexPath.section].items[indexPath.row]

        var content = cell.defaultContentConfiguration()

        content.text = item.title
        content.textProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        content.textProperties.numberOfLines = 2
        content.textProperties.lineBreakMode = .byTruncatingMiddle

        var detailParts: [String] = []
        if let address = item.address {
            detailParts.append(Constants.formatAddress(address))
        }
        if let subtitle = item.subtitle, !subtitle.isEmpty {
            detailParts.append(subtitle)
        }

        if !detailParts.isEmpty {
            content.secondaryText = detailParts.joined(separator: " - ")
            content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            content.secondaryTextProperties.color = Constants.Colors.commentColor
        }

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }
}

// MARK: - UITableViewDelegate

extension GlobalSearchViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let item = sections[indexPath.section].items[indexPath.row]

        if let symbol = item.symbol {
            dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                self.delegate?.globalSearch(self, didSelectSymbol: symbol)
            }
        } else if let function = item.function {
            dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                self.delegate?.globalSearch(self, didSelectFunction: function)
            }
        } else if let string = item.string {
            dismiss(animated: true) { [weak self] in
                guard let self = self else { return }
                self.delegate?.globalSearch(self, didSelectString: string)
            }
        } else {
            // For categories without specific navigation (segments, sections, ObjC, imports, exports)
            // show a detail alert with the item info
            showDetailAlert(for: item)
        }
    }

    private func showDetailAlert(for item: SearchResultItem) {
        var message = ""
        message += "Category: \(item.category.rawValue)\n"
        if let address = item.address {
            message += "Address: \(Constants.formatAddress(address))\n"
        }
        if let subtitle = item.subtitle {
            message += "\(subtitle)\n"
        }

        let alert = UIAlertController(title: item.title, message: message, preferredStyle: .alert)
        if let address = item.address {
            alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
                UIPasteboard.general.string = Constants.formatAddress(address)
            })
        }
        alert.addAction(UIAlertAction(title: "Copy Name", style: .default) { _ in
            UIPasteboard.general.string = item.title
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))
        present(alert, animated: true)
    }

    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard let header = view as? UITableViewHeaderFooterView else { return }
        header.textLabel?.font = .systemFont(ofSize: 14, weight: .semibold)
        header.textLabel?.textColor = Constants.Colors.accentColor
    }
}
