import UIKit

// MARK: - Cross-View Navigation Protocol

protocol AnalysisNavigationDelegate: AnyObject {
    func navigateToDisassembly(atAddress address: UInt64)
    func navigateToSymbol(named name: String)
    func navigateToHexView(atOffset offset: UInt64)
}

class ResultsViewController: UIViewController {

    // MARK: - UI Elements

    private lazy var segmentedControl: UISegmentedControl = {
        let items = ["Info", "Symbols", "Strings", "Code", "Functions"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        return control
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var searchBar: UISearchBar = {
        let search = UISearchBar()
        search.translatesAutoresizingMaskIntoConstraints = false
        search.placeholder = "Search..."
        search.delegate = self
        search.searchBarStyle = .minimal
        return search
    }()

    // MARK: - iPad Sidebar

    /// Sidebar section descriptors for iPad regular-width layout.
    private struct SidebarItem {
        let title: String
        let iconName: String
        let segmentIndex: Int
    }

    private let sidebarItems: [SidebarItem] = [
        SidebarItem(title: "Header Info", iconName: "doc.text", segmentIndex: 0),
        SidebarItem(title: "Symbols", iconName: "chevron.left.forwardslash.chevron.right", segmentIndex: 1),
        SidebarItem(title: "Strings", iconName: "textformat.abc", segmentIndex: 2),
        SidebarItem(title: "Disassembly", iconName: "scroll", segmentIndex: 3),
        SidebarItem(title: "Functions", iconName: "function", segmentIndex: 4)
    ]

    private lazy var sidebarTableView: UITableView = {
        let table = UITableView(frame: .zero, style: .insetGrouped)
        table.translatesAutoresizingMaskIntoConstraints = false
        table.delegate = self
        table.dataSource = self
        table.register(UITableViewCell.self, forCellReuseIdentifier: "SidebarCell")
        table.rowHeight = Constants.UI.sidebarRowHeight
        table.backgroundColor = Constants.Colors.secondaryBackground
        table.separatorInset = UIEdgeInsets(top: 0, left: Constants.UI.standardSpacing, bottom: 0, right: 0)
        return table
    }()

    private lazy var sidebarDivider: UIView = {
        let divider = UIView()
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.backgroundColor = UIColor.separator
        return divider
    }()

    /// Tracks which layout mode is currently active to avoid redundant rebuilds.
    private var isSidebarVisible = false

    /// Holds the current set of layout constraints so they can be swapped on trait changes.
    private var activeLayoutConstraints: [NSLayoutConstraint] = []

    private var isCompactWidth: Bool {
        traitCollection.horizontalSizeClass == .compact
    }

    private var selectedSidebarIndex: Int = 0

    // MARK: - Child View Controllers

    private lazy var headerViewController: HeaderViewController = {
        return HeaderViewController(output: output)
    }()

    private lazy var symbolsViewController: SymbolsViewController = {
        let vc = SymbolsViewController(symbols: output.symbols)
        vc.navigationDelegate = self
        vc.binaryUUID = output.header.uuid ?? output.filePath
        return vc
    }()

    private lazy var stringsViewController: StringsViewController = {
        return StringsViewController(strings: output.strings)
    }()

    private lazy var disassemblyViewController: DisassemblyViewController = {
        let vc = DisassemblyViewController(instructions: output.instructions)
        vc.navigationDelegate = self
        vc.binaryUUID = output.header.uuid ?? output.filePath
        return vc
    }()

    private lazy var functionsViewController: FunctionsViewController = {
        return FunctionsViewController(functions: output.functions)
    }()

    private lazy var xrefsViewController: XrefsViewController? = {
        guard let xrefAnalysis = output.xrefAnalysis as? XrefAnalysisResult else { return nil }
        let vc = XrefsViewController(xrefAnalysis: xrefAnalysis)
        vc.navigationDelegate = self
        return vc
    }()

    private lazy var objcClassesViewController: ObjCClassesViewController? = {
        guard let objcAnalysis = output.objcAnalysis as? ObjCAnalysisResult else { return nil }
        return ObjCClassesViewController(objcAnalysis: objcAnalysis)
    }()

    private lazy var importsExportsViewController: ImportsExportsViewController? = {
        guard let importExportAnalysis = output.importExportAnalysis as? ImportExportAnalysis else { return nil }
        let vc = ImportsExportsViewController(analysis: importExportAnalysis)
        vc.navigationDelegate = self
        return vc
    }()

    private lazy var dependencyViewController: DependencyViewController? = {
        guard let importExportAnalysis = output.importExportAnalysis as? ImportExportAnalysis,
              let dependencyAnalysis = importExportAnalysis.dependencyAnalysis else { return nil }
        return DependencyViewController(dependencyAnalysis: dependencyAnalysis)
    }()

    private lazy var codeSignatureViewController: CodeSignatureViewController? = {
        guard let codeSignAnalysis = output.codeSigningAnalysis as? CodeSigningAnalysis else { return nil }
        return CodeSignatureViewController(analysis: codeSignAnalysis)
    }()

    private lazy var cfgViewController: CFGViewController? = {
        guard let cfgAnalysis = output.cfgAnalysis as? CFGAnalysisResult else { return nil }
        return CFGViewController(cfgAnalysis: cfgAnalysis)
    }()

    private lazy var callGraphViewController: CallGraphViewController? = {
        let functions = (output.functions as? [FunctionModel]) ?? []
        let symbols = (output.symbols as? [SymbolModel]) ?? []
        guard !functions.isEmpty else { return nil }
        return CallGraphViewController(
            xrefAnalysis: output.xrefAnalysis,
            functions: functions,
            symbols: symbols
        )
    }()

    private lazy var memoryMapViewController: MemoryMapViewController = {
        let segments = (output.segments as? [SegmentModel]) ?? []
        let sections = (output.sections as? [SectionModel]) ?? []
        let baseAddress = segments.map { $0.vmAddress }.min() ?? 0
        return MemoryMapViewController(
            segments: segments,
            sections: sections,
            fileSize: output.fileSize,
            baseAddress: baseAddress
        )
    }()

    // MARK: - Properties

    private let output: DecompiledOutput
    private var currentViewController: UIViewController?

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

        title = output.fileName
        view.backgroundColor = Constants.Colors.primaryBackground

        setupUI()
        setupNavigationBar()

        showViewController(headerViewController)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            updateLayoutForCurrentTraits()
        }
    }

    // MARK: - Setup

    private func setupUI() {
        // Add all subviews; visibility is controlled by updateLayoutForCurrentTraits.
        view.addSubview(sidebarTableView)
        view.addSubview(sidebarDivider)
        view.addSubview(segmentedControl)
        view.addSubview(searchBar)
        view.addSubview(containerView)

        searchBar.isHidden = true

        updateLayoutForCurrentTraits()
    }

    /// Activates the correct set of Auto Layout constraints based on horizontal size class.
    /// On compact width (iPhone): segmented control on top, full-width detail.
    /// On regular width (iPad): sidebar column on left, detail on right, segmented control hidden.
    private func updateLayoutForCurrentTraits() {
        let wantSidebar = !isCompactWidth

        // Skip if layout is already correct.
        if wantSidebar == isSidebarVisible, !activeLayoutConstraints.isEmpty {
            return
        }

        NSLayoutConstraint.deactivate(activeLayoutConstraints)
        activeLayoutConstraints.removeAll()

        if wantSidebar {
            // --- iPad / Regular Width Layout ---
            segmentedControl.isHidden = true
            sidebarTableView.isHidden = false
            sidebarDivider.isHidden = false

            // Select the current row in the sidebar to stay in sync.
            let sidebarIndex = IndexPath(row: selectedSidebarIndex, section: 0)
            sidebarTableView.selectRow(at: sidebarIndex, animated: false, scrollPosition: .none)

            activeLayoutConstraints = [
                // Sidebar
                sidebarTableView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                sidebarTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                sidebarTableView.widthAnchor.constraint(equalToConstant: Constants.UI.sidebarWidth),
                sidebarTableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                // Divider (1pt line between sidebar and detail)
                sidebarDivider.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                sidebarDivider.leadingAnchor.constraint(equalTo: sidebarTableView.trailingAnchor),
                sidebarDivider.widthAnchor.constraint(equalToConstant: 1),
                sidebarDivider.bottomAnchor.constraint(equalTo: view.bottomAnchor),

                // Search bar (above detail pane)
                searchBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                searchBar.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                // Detail container
                containerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
        } else {
            // --- iPhone / Compact Width Layout ---
            segmentedControl.isHidden = false
            sidebarTableView.isHidden = true
            sidebarDivider.isHidden = true

            activeLayoutConstraints = [
                segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.UI.compactSpacing),
                segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.standardSpacing),
                segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.standardSpacing),

                searchBar.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.compactSpacing),
                searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),

                containerView.topAnchor.constraint(equalTo: searchBar.bottomAnchor),
                containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ]
        }

        NSLayoutConstraint.activate(activeLayoutConstraints)
        isSidebarVisible = wantSidebar
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }

    private func setupNavigationBar() {
        let exportButton = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(showExportOptions)
        )

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMoreOptions)
        )

        let infoButton = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showInfo)
        )

        let globalSearchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(showGlobalSearch)
        )

        let bookmarkButton = UIBarButtonItem(
            image: UIImage(systemName: "bookmark"),
            style: .plain,
            target: self,
            action: #selector(showBookmarks)
        )

        navigationItem.rightBarButtonItems = [exportButton, moreButton, infoButton, globalSearchButton, bookmarkButton]
    }

    @objc private func showGlobalSearch() {
        let searchVC = GlobalSearchViewController(output: output)
        searchVC.delegate = self
        let navController = UINavigationController(rootViewController: searchVC)
        navController.modalPresentationStyle = .fullScreen
        present(navController, animated: true)
    }

    @objc private func showBookmarks() {
        let uuid = output.header.uuid ?? output.filePath
        let bookmarksVC = BookmarksViewController(binaryUUID: uuid)
        bookmarksVC.navigationDelegate = self
        let navController = UINavigationController(rootViewController: bookmarksVC)
        navController.modalPresentationStyle = .formSheet
        present(navController, animated: true)
    }

    @objc private func showMoreOptions() {
        let objcResult = output.objcAnalysis as? ObjCAnalysisResult
        let hasObjCData = (objcResult?.totalClasses ?? 0) > 0
        let hasCodeSignature = output.codeSigningAnalysis != nil
        let hasSecurityPosture = output.securityPosture != nil

        let menuVC = AnalysisMenuViewController(hasObjCData: hasObjCData, hasCodeSignature: hasCodeSignature, hasSecurityPosture: hasSecurityPosture)
        menuVC.delegate = self
        let navController = UINavigationController(rootViewController: menuVC)
        present(navController, animated: true)
    }

    // MARK: - View Management

    private func showViewController(_ viewController: UIViewController) {
        if let current = currentViewController {
            current.willMove(toParent: nil)
            current.view.removeFromSuperview()
            current.removeFromParent()
        }

        addChild(viewController)
        containerView.addSubview(viewController.view)
        viewController.view.frame = containerView.bounds
        viewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        viewController.didMove(toParent: self)

        currentViewController = viewController

        let activeIndex = segmentedControl.selectedSegmentIndex
        searchBar.isHidden = (activeIndex == 0)
    }

    /// Switches to the child view controller for the given section index (0-4).
    /// Updates both the segmented control and the sidebar selection to stay in sync.
    private func switchToSection(_ index: Int) {
        searchBar.text = ""
        searchBar.resignFirstResponder()

        segmentedControl.selectedSegmentIndex = index
        selectedSidebarIndex = index

        // Keep sidebar selection in sync when visible.
        if isSidebarVisible {
            sidebarTableView.selectRow(at: IndexPath(row: index, section: 0), animated: true, scrollPosition: .none)
        }

        switch index {
        case 0:
            showViewController(headerViewController)
        case 1:
            showViewController(symbolsViewController)
        case 2:
            showViewController(stringsViewController)
        case 3:
            showViewController(disassemblyViewController)
        case 4:
            showViewController(functionsViewController)
        default:
            break
        }
    }

    @objc private func segmentChanged() {
        switchToSection(segmentedControl.selectedSegmentIndex)
    }

    // MARK: - Actions

    @objc private func showExportOptions() {
        let alert = UIAlertController(title: "Export Analysis", message: "Choose export format", preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "📄 Plain Text (.txt)", style: .default) { [weak self] _ in
            self?.export(format: .text)
        })

        alert.addAction(UIAlertAction(title: "🌐 HTML Report (.html)", style: .default) { [weak self] _ in
            self?.export(format: .html)
        })

        alert.addAction(UIAlertAction(title: "📋 JSON Data (.json)", style: .default) { [weak self] _ in
            self?.export(format: .json)
        })

        alert.addAction(UIAlertAction(title: "📊 Analysis Report (.html)", style: .default) { [weak self] _ in
            self?.generateAnalysisReport()
        })

        alert.addAction(UIAlertAction(title: "📤 Quick Share", style: .default) { [weak self] _ in
            self?.quickShare()
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(alert, animated: true)
    }

    @objc private func showInfo() {
        let dashboardVC = AnalysisDashboardViewController(output: output)
        dashboardVC.quickActionDelegate = self
        navigationController?.pushViewController(dashboardVC, animated: true)
    }

    /// Allows external callers (e.g. the dashboard) to switch the active segment.
    func selectSegment(_ index: Int) {
        guard index >= 0, index < segmentedControl.numberOfSegments else { return }
        switchToSection(index)
    }

    // MARK: - Export Methods

    private func export(format: ExportFormat) {
        guard let data = ExportService.export(output, format: format) else {
            showAlert(title: "Export Failed", message: "Could not generate \(format.displayName) export.")
            return
        }

        let filename = ExportService.generateFilename(for: output, format: format)

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)

            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItems?.first
            }

            activityVC.completionWithItemsHandler = { _, completed, _, error in
                if completed {
                    print("Exported successfully: \(filename)")
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            present(activityVC, animated: true)

        } catch {
            showAlert(title: "Export Failed", message: "Error writing file: \(error.localizedDescription)")
        }
    }

    private func quickShare() {
        guard let data = ExportService.export(output, format: .text),
              let text = String(data: data, encoding: .utf8) else {
            showAlert(title: "Share Failed", message: "Could not generate report.")
            return
        }

        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)

        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }

        present(activityVC, animated: true)
    }

    private func generateAnalysisReport() {
        let htmlString = ReportGenerator.generateHTML(from: output, fileName: output.fileName)

        guard let data = htmlString.data(using: .utf8) else {
            showAlert(title: "Report Failed", message: "Could not generate analysis report.")
            return
        }

        let baseName = (output.fileName as NSString).deletingPathExtension
        let timestamp = DateFormatter.filenameDateFormatter.string(from: Date())
        let filename = "\(baseName)_report_\(timestamp).html"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try data.write(to: tempURL)

            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)

            if let popover = activityVC.popoverPresentationController {
                popover.barButtonItem = navigationItem.rightBarButtonItems?.first
            }

            activityVC.completionWithItemsHandler = { _, completed, _, _ in
                if completed {
                    print("Analysis report exported successfully: \(filename)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            }

            present(activityVC, animated: true)

        } catch {
            showAlert(title: "Report Failed", message: "Error writing report: \(error.localizedDescription)")
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

// MARK: - iPad Sidebar DataSource & Delegate

extension ResultsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard tableView === sidebarTableView else { return 0 }
        return sidebarItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard tableView === sidebarTableView else {
            return UITableViewCell()
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "SidebarCell", for: indexPath)
        let item = sidebarItems[indexPath.row]

        var config = cell.defaultContentConfiguration()
        config.text = item.title
        config.textProperties.font = .systemFont(ofSize: Constants.UI.sidebarFontSize, weight: .medium)
        config.image = UIImage(systemName: item.iconName)
        config.imageProperties.tintColor = Constants.Colors.accentColor
        config.imageProperties.maximumSize = CGSize(width: Constants.UI.sidebarIconSize,
                                                    height: Constants.UI.sidebarIconSize)
        cell.contentConfiguration = config
        cell.backgroundColor = Constants.Colors.secondaryBackground

        // Highlight the selected row with the accent color.
        let selectedBg = UIView()
        selectedBg.backgroundColor = Constants.Colors.accentColor.withAlphaComponent(0.15)
        cell.selectedBackgroundView = selectedBg

        return cell
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard tableView === sidebarTableView else { return nil }
        return "Sections"
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard tableView === sidebarTableView else { return }
        let item = sidebarItems[indexPath.row]
        switchToSection(item.segmentIndex)
    }
}

// MARK: - UISearchBarDelegate

extension ResultsViewController: UISearchBarDelegate {

    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if let symbolsVC = currentViewController as? SymbolsViewController {
            symbolsVC.filterSymbols(query: searchText)
        } else if let stringsVC = currentViewController as? StringsViewController {
            stringsVC.filterStrings(query: searchText)
        } else if let disassemblyVC = currentViewController as? DisassemblyViewController {
            disassemblyVC.filterInstructions(query: searchText)
        } else if let functionsVC = currentViewController as? FunctionsViewController {
            functionsVC.filterFunctions(query: searchText)
        }
    }

    private func showNoDataAvailable(type: String) {
        let alert = UIAlertController(
            title: "No \(type) Data",
            message: "\(type) analysis is not available for this binary.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        searchBar.resignFirstResponder()
    }
}

// MARK: - Analysis Menu Delegate

extension ResultsViewController: AnalysisMenuDelegate {
    func didSelectAnalysisType(_ type: AnalysisType) {
        switch type {
        case .xrefs:
            if let xrefsVC = xrefsViewController {
                navigationController?.pushViewController(xrefsVC, animated: true)
            } else {
                showNoDataAvailable(type: "Xref")
            }
        case .objc:
            if let objcVC = objcClassesViewController {
                navigationController?.pushViewController(objcVC, animated: true)
            } else {
                showNoDataAvailable(type: "Objective-C")
            }
        case .imports:
            if let importExportVC = importsExportsViewController {
                navigationController?.pushViewController(importExportVC, animated: true)
            } else {
                showNoDataAvailable(type: "Import/Export")
            }
        case .dependencies:
            if let dependencyVC = dependencyViewController {
                navigationController?.pushViewController(dependencyVC, animated: true)
            } else {
                showNoDataAvailable(type: "Dependency")
            }
        case .signature:
            if let codeSignVC = codeSignatureViewController {
                navigationController?.pushViewController(codeSignVC, animated: true)
            } else {
                showNoDataAvailable(type: "Code Signature")
            }
        case .cfg:
            if let cfgVC = cfgViewController {
                navigationController?.pushViewController(cfgVC, animated: true)
            } else {
                showNoDataAvailable(type: "CFG")
            }
        case .callGraph:
            if let callGraphVC = callGraphViewController {
                navigationController?.pushViewController(callGraphVC, animated: true)
            } else {
                showNoDataAvailable(type: "Call Graph")
            }
        case .memoryMap:
            navigationController?.pushViewController(memoryMapViewController, animated: true)
        case .pseudocode:
            if let functions = output.functions as? [FunctionModel], let first = functions.first,
               let instructions = first.instructions as? [InstructionModel], !instructions.isEmpty {
                let disassembly = instructions.map { $0.fullDisassembly }.joined(separator: "\n")
                let pseudocodeVC = PseudocodeViewController(disassembly: disassembly,
                                                             startAddress: first.startAddress,
                                                             functionName: first.name)
                navigationController?.pushViewController(pseudocodeVC, animated: true)
            } else {
                showNoDataAvailable(type: "Pseudocode")
            }
        case .security:
            if let posture = output.securityPosture as? SecurityPosture {
                let securityVC = SecurityPostureViewController(posture: posture)
                navigationController?.pushViewController(securityVC, animated: true)
            } else {
                showNoDataAvailable(type: "Security Posture")
            }
        case .binaryPatching:
            let patchVC = BinaryPatchDashboardViewController()
            navigationController?.pushViewController(patchVC, animated: true)
        case .hexViewer:
            let fileURL = URL(fileURLWithPath: output.filePath)
            let sectionInfos: [SectionDisplayInfo] = (output.sections as? [SectionModel])?.map {
                SectionDisplayInfo(name: "\($0.segmentName),\($0.sectionName)",
                                   offset: UInt64($0.offset),
                                   size: $0.size)
            } ?? []
            let hexVC = HexViewerViewController(fileURL: fileURL, sections: sectionInfos.isEmpty ? nil : sectionInfos)
            navigationController?.pushViewController(hexVC, animated: true)
        case .addressConverter:
            let converterVC = AddressConverterViewController(output: output, navigationDelegate: self)
            let navController = UINavigationController(rootViewController: converterVC)
            present(navController, animated: true)
        case .patternScan:
            let fileURL = URL(fileURLWithPath: output.filePath)
            let sectionInfos: [SectionDisplayInfo] = (output.sections as? [SectionModel])?.map {
                SectionDisplayInfo(name: "\($0.segmentName),\($0.sectionName)",
                                   offset: UInt64($0.offset),
                                   size: $0.size)
            } ?? []
            let patternVC = PatternScannerViewController(fileURL: fileURL, sections: sectionInfos.isEmpty ? nil : sectionInfos, navigationDelegate: self)
            navigationController?.pushViewController(patternVC, animated: true)
        case .inspection:
            let report = InspectionRuleEngine.shared.evaluate(output: output)
            let inspectionVC = InspectionResultsViewController(report: report)
            navigationController?.pushViewController(inspectionVC, animated: true)
        }
    }
}

// MARK: - GlobalSearchDelegate

extension ResultsViewController: GlobalSearchDelegate {
    func globalSearch(_ controller: GlobalSearchViewController, didSelectSymbol symbol: SymbolModel) {
        switchToSection(1)
        searchBar.text = symbol.demangledName ?? symbol.name
        symbolsViewController.filterSymbols(query: searchBar.text ?? "")
    }

    func globalSearch(_ controller: GlobalSearchViewController, didSelectFunction function: FunctionModel) {
        let detailVC = FunctionDetailViewController(function: function)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func globalSearch(_ controller: GlobalSearchViewController, didSelectString string: StringModel) {
        switchToSection(2)
        searchBar.text = string.content
        stringsViewController.filterStrings(query: searchBar.text ?? "")
    }
}

// MARK: - Dashboard Quick Action Delegate

extension ResultsViewController: AnalysisDashboardViewController.QuickActionDelegate {
    func dashboardDidRequestNavigation(to analysisType: AnalysisType) {
        didSelectAnalysisType(analysisType)
    }
}

// MARK: - AnalysisNavigationDelegate

extension ResultsViewController: AnalysisNavigationDelegate {
    func navigateToDisassembly(atAddress address: UInt64) {
        if let nav = navigationController, nav.topViewController !== self {
            nav.popToViewController(self, animated: false)
        }
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        switchToSection(3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.disassemblyViewController.scrollToAddress(address)
        }
    }

    func navigateToSymbol(named name: String) {
        if let nav = navigationController, nav.topViewController !== self {
            nav.popToViewController(self, animated: false)
        }
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        switchToSection(1)
        searchBar.text = name
        symbolsViewController.filterSymbols(query: name)
    }

    func navigateToHexView(atOffset offset: UInt64) {
        let fileURL = URL(fileURLWithPath: output.filePath)
        let sectionInfos: [SectionDisplayInfo] = (output.sections as? [SectionModel])?.map {
            SectionDisplayInfo(name: "\($0.segmentName),\($0.sectionName)",
                               offset: UInt64($0.offset),
                               size: $0.size)
        } ?? []
        let hexVC = HexViewerViewController(fileURL: fileURL, sections: sectionInfos.isEmpty ? nil : sectionInfos)
        navigationController?.pushViewController(hexVC, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            hexVC.scrollToOffset(offset)
        }
    }
}

// MARK: - Child View Controllers (50% done)

class HeaderViewController: UIViewController {
    private let output: DecompiledOutput
    private let textView = UITextView()

    init(output: DecompiledOutput) {
        self.output = output
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        textView.frame = view.bounds
        textView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

        view.addSubview(textView)

        loadHeaderInfo()
    }

    private func loadHeaderInfo() {
        var text = "=== Mach-O Header ===\n\n"
        text += "CPU Type: \(output.header.cpuType)\n"
        text += "File Type: \(output.header.fileType)\n"
        text += "Architecture: \(output.header.is64Bit ? "64-bit" : "32-bit")\n"
        text += "Load Commands: \(output.header.ncmds)\n"
        text += "Flags: 0x\(String(format: "%X", output.header.rawFlags))\n"
        if let flagsDesc = output.header.flagsDescription, !flagsDesc.isEmpty {
            text += "  \(flagsDesc)\n"
        }
        if let uuid = output.header.uuid {
            text += "UUID: \(uuid)\n"
        }
        if let platform = output.header.platformName {
            text += "Platform: \(platform)\n"
        }
        if let sourceVersion = output.header.sourceVersion {
            text += "Source Version: \(sourceVersion)\n"
        }
        text += "PIE: \(output.header.isPIE ? "Yes" : "No")\n"
        text += "Chained Fixups: \(output.header.hasChainedFixups ? "Yes" : "No")\n"
        text += "Encrypted: \(output.header.isEncrypted ? "Yes" : "No")\n"
        if output.header.hasEntryPoint {
            text += String(format: "Entry Point: 0x%llX\n", output.header.entryPointAddress)
        }
        text += "\n"

        text += "=== Statistics ===\n\n"
        text += "Symbols: \(output.totalSymbols) (\(output.definedSymbols) defined, \(output.undefinedSymbols) undefined)\n"
        text += "Strings: \(output.totalStrings)\n"
        text += "Instructions: \(output.totalInstructions)\n"
        text += "Functions: \(output.totalFunctions)\n"
        if output.totalObjCClasses > 0 {
            text += "ObjC Classes: \(output.totalObjCClasses)\n"
            text += "ObjC Methods: \(output.totalObjCMethods)\n"
        }
        if output.totalImports > 0 { text += "Imports: \(output.totalImports)\n" }
        if output.totalExports > 0 { text += "Exports: \(output.totalExports)\n" }
        if output.totalLinkedLibraries > 0 { text += "Linked Libraries: \(output.totalLinkedLibraries)\n" }
        if output.totalXrefs > 0 { text += "Cross-References: \(output.totalXrefs)\n" }
        text += String(format: "\nProcessing Time: %.2fs\n\n", output.processingTime)

        text += "=== Segments (\(output.segments.count)) ===\n\n"
        for segment in output.segments {
            let paddedName = segment.name.padding(toLength: 16, withPad: " ", startingAt: 0)
            text += String(format: "%@ VM: 0x%016llX-0x%016llX  File: 0x%016llX-0x%016llX  %@\n",
                          paddedName, segment.vmAddress, segment.vmAddress + segment.vmSize,
                          segment.fileOffset, segment.fileOffset + segment.fileSize, segment.protection)
        }

        if !output.sections.isEmpty {
            text += "\n=== Sections (\(output.sections.count)) ===\n\n"
            for section in output.sections {
                let fullName = "\(section.segmentName),\(section.sectionName)".padding(toLength: 36, withPad: " ", startingAt: 0)
                text += String(format: "%@ Addr: 0x%016llX  Size: %llu\n",
                              fullName, section.address, section.size)
            }
        }

        textView.text = text
    }
}

class SymbolsViewController: UITableViewController {
    weak var navigationDelegate: AnalysisNavigationDelegate?
    var binaryUUID: String?
    private var symbols: [SymbolModel]
    private var filteredSymbols: [SymbolModel]

    init(symbols: [SymbolModel]) {
        self.symbols = symbols.sortedByAddress()
        self.filteredSymbols = self.symbols
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SymbolCell")
        tableView.rowHeight = 44
    }

    func filterSymbols(query: String) {
        if query.isEmpty {
            filteredSymbols = symbols
        } else {
            filteredSymbols = (symbols.searchSymbols(query: query) as? [SymbolModel]) ?? []
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredSymbols.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SymbolCell", for: indexPath)
        guard indexPath.row < filteredSymbols.count else { return cell }
        let symbol = filteredSymbols[indexPath.row]

        let displayName = symbol.demangledName ?? symbol.name
        cell.textLabel?.text = "\(Constants.formatAddress(symbol.address)) \(displayName)"
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.detailTextLabel?.text = "\(symbol.type) | \(symbol.scope)"
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredSymbols.count else { return }
        let symbol = filteredSymbols[indexPath.row]
        let displayName = symbol.demangledName ?? symbol.name

        let alert = UIAlertController(title: displayName, message: Constants.formatAddress(symbol.address), preferredStyle: .actionSheet)

        alert.addAction(UIAlertAction(title: "View in Disassembly", style: .default) { [weak self] _ in
            self?.navigationDelegate?.navigateToDisassembly(atAddress: symbol.address)
        })

        alert.addAction(UIAlertAction(title: "View in Hex", style: .default) { [weak self] _ in
            self?.navigationDelegate?.navigateToHexView(atOffset: symbol.address)
        })

        alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
            UIPasteboard.general.string = Constants.formatAddress(symbol.address)
        })

        alert.addAction(UIAlertAction(title: "Copy Name", style: .default) { _ in
            UIPasteboard.general.string = displayName
        })

        if let uuid = binaryUUID {
            alert.addAction(UIAlertAction(title: "Add Bookmark", style: .default) { [weak self] _ in
                self?.promptAddBookmark(address: symbol.address, defaultLabel: displayName, binaryUUID: uuid)
            })

            alert.addAction(UIAlertAction(title: "Add Annotation", style: .default) { [weak self] _ in
                self?.promptAddAnnotation(address: symbol.address, binaryUUID: uuid)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }

        present(alert, animated: true)
    }

    private func promptAddBookmark(address: UInt64, defaultLabel: String, binaryUUID: String) {
        let alert = UIAlertController(title: "Add Bookmark", message: Constants.formatAddress(address), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultLabel
            textField.placeholder = "Label"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            guard let label = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !label.isEmpty else { return }
            let bookmark = Bookmark(address: address, label: label)
            BookmarkStore.shared.addBookmark(bookmark, forBinaryUUID: binaryUUID)
        })
        present(alert, animated: true)
    }

    private func promptAddAnnotation(address: UInt64, binaryUUID: String) {
        let alert = UIAlertController(title: "Add Annotation", message: Constants.formatAddress(address), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Comment"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            guard let comment = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !comment.isEmpty else { return }
            let annotation = Annotation(address: address, comment: comment)
            BookmarkStore.shared.addAnnotation(annotation, forBinaryUUID: binaryUUID)
        })
        present(alert, animated: true)
    }

    func scrollToSymbol(named name: String) {
        let lowerName = name.lowercased()
        if let index = filteredSymbols.firstIndex(where: {
            ($0.demangledName ?? $0.name).lowercased().contains(lowerName)
        }) {
            tableView.scrollToRow(at: IndexPath(row: index, section: 0), at: .middle, animated: true)
            tableView.selectRow(at: IndexPath(row: index, section: 0), animated: true, scrollPosition: .none)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.tableView.deselectRow(at: IndexPath(row: index, section: 0), animated: true)
            }
        }
    }
}

class StringsViewController: UITableViewController {
    private var strings: [StringModel]
    private var filteredStrings: [StringModel]

    init(strings: [StringModel]) {
        self.strings = strings.sortedByAddress()
        self.filteredStrings = self.strings
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StringCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
    }

    func filterStrings(query: String) {
        if query.isEmpty {
            filteredStrings = strings
        } else {
            filteredStrings = strings.filter { $0.content.localizedCaseInsensitiveContains(query) }
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredStrings.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StringCell", for: indexPath)
        guard indexPath.row < filteredStrings.count else { return cell }
        let string = filteredStrings[indexPath.row]

        var content = cell.defaultContentConfiguration()
        content.text = string.content
        content.secondaryText = "\(Constants.formatAddress(string.address)) - \(string.section)"
        content.textProperties.font = .systemFont(ofSize: 13)
        content.textProperties.numberOfLines = 2
        content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        content.secondaryTextProperties.color = .secondaryLabel

        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredStrings.count else { return }
        let string = filteredStrings[indexPath.row]
        let alert = UIAlertController(title: "String Details", message: nil, preferredStyle: .alert)

        let details = """
        Address: \(Constants.formatAddress(string.address))
        Offset: 0x\(String(format: "%llX", string.offset))
        Length: \(string.length) bytes
        Section: \(string.section)
        Type: \(string.isCString ? "C String" : "Data String")

        Content:
        \(string.content)
        """

        alert.message = details
        alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
            UIPasteboard.general.string = Constants.formatAddress(string.address)
        })
        alert.addAction(UIAlertAction(title: "Copy Content", style: .default) { _ in
            UIPasteboard.general.string = string.content
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel))

        present(alert, animated: true)
    }
}

class DisassemblyViewController: UITableViewController {
    weak var navigationDelegate: AnalysisNavigationDelegate?
    var binaryUUID: String?
    private var instructions: [InstructionModel]
    private var filteredInstructions: [InstructionModel]

    init(instructions: [InstructionModel]) {
        self.instructions = instructions
        self.filteredInstructions = instructions
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "InstructionCell")
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 30
    }

    func filterInstructions(query: String) {
        if query.isEmpty {
            filteredInstructions = instructions
        } else {
            filteredInstructions = instructions.search(mnemonic: query)
        }
        tableView.reloadData()
    }

    func scrollToAddress(_ address: UInt64) {
        filteredInstructions = instructions
        tableView.reloadData()
        if let index = filteredInstructions.firstIndex(where: { $0.address >= address }) {
            let capped = min(index, Constants.Disassembly.maxInstructionsDisplay - 1)
            let indexPath = IndexPath(row: capped, section: 0)
            tableView.scrollToRow(at: indexPath, at: .middle, animated: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                if let cell = self?.tableView.cellForRow(at: indexPath) {
                    cell.backgroundColor = Constants.Colors.accentColor.withAlphaComponent(0.2)
                    UIView.animate(withDuration: 1.0) { cell.backgroundColor = nil }
                }
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return min(filteredInstructions.count, Constants.Disassembly.maxInstructionsDisplay)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "InstructionCell", for: indexPath)
        guard indexPath.row < filteredInstructions.count else { return cell }
        let instruction = filteredInstructions[indexPath.row]

        cell.textLabel?.attributedText = instruction.attributedString()
        cell.textLabel?.numberOfLines = 0

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredInstructions.count else { return }
        let instruction = filteredInstructions[indexPath.row]

        let alert = UIAlertController(
            title: instruction.mnemonic,
            message: Constants.formatAddress(instruction.address),
            preferredStyle: .actionSheet
        )

        if instruction.hasBranchTarget {
            alert.addAction(UIAlertAction(title: "Go to Branch Target", style: .default) { [weak self] _ in
                self?.navigationDelegate?.navigateToDisassembly(atAddress: instruction.branchTarget)
            })
        }

        alert.addAction(UIAlertAction(title: "View in Hex", style: .default) { [weak self] _ in
            self?.navigationDelegate?.navigateToHexView(atOffset: instruction.address)
        })

        alert.addAction(UIAlertAction(title: "Copy Address", style: .default) { _ in
            UIPasteboard.general.string = Constants.formatAddress(instruction.address)
        })

        alert.addAction(UIAlertAction(title: "Copy Instruction", style: .default) { _ in
            UIPasteboard.general.string = instruction.fullDisassembly
        })

        if let uuid = binaryUUID {
            alert.addAction(UIAlertAction(title: "Add Bookmark", style: .default) { [weak self] _ in
                self?.promptAddBookmark(address: instruction.address, defaultLabel: instruction.fullDisassembly, binaryUUID: uuid)
            })

            alert.addAction(UIAlertAction(title: "Add Annotation", style: .default) { [weak self] _ in
                self?.promptAddAnnotation(address: instruction.address, binaryUUID: uuid)
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            if let cell = tableView.cellForRow(at: indexPath) {
                popover.sourceView = cell
                popover.sourceRect = cell.bounds
            }
        }

        present(alert, animated: true)
    }

    private func promptAddBookmark(address: UInt64, defaultLabel: String, binaryUUID: String) {
        let alert = UIAlertController(title: "Add Bookmark", message: Constants.formatAddress(address), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = defaultLabel
            textField.placeholder = "Label"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            guard let label = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !label.isEmpty else { return }
            let bookmark = Bookmark(address: address, label: label)
            BookmarkStore.shared.addBookmark(bookmark, forBinaryUUID: binaryUUID)
        })
        present(alert, animated: true)
    }

    private func promptAddAnnotation(address: UInt64, binaryUUID: String) {
        let alert = UIAlertController(title: "Add Annotation", message: Constants.formatAddress(address), preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "Comment"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Add", style: .default) { _ in
            guard let comment = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !comment.isEmpty else { return }
            let annotation = Annotation(address: address, comment: comment)
            BookmarkStore.shared.addAnnotation(annotation, forBinaryUUID: binaryUUID)
        })
        present(alert, animated: true)
    }
}

class FunctionsViewController: UITableViewController {
    private var functions: [FunctionModel]
    private var filteredFunctions: [FunctionModel]

    init(functions: [FunctionModel]) {
        self.functions = functions.sortedByAddress()
        self.filteredFunctions = self.functions
        super.init(style: .plain)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "FunctionCell")
    }

    func filterFunctions(query: String) {
        if query.isEmpty {
            filteredFunctions = functions
        } else {
            filteredFunctions = functions.search(name: query)
        }
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredFunctions.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "FunctionCell", for: indexPath)
        guard indexPath.row < filteredFunctions.count else { return cell }
        let function = filteredFunctions[indexPath.row]

        let displayName = function.demangledName ?? function.name
        cell.textLabel?.text = displayName
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        cell.detailTextLabel?.text = "\(Constants.formatAddress(function.startAddress)) - \(function.instructionCount) instructions"
        cell.accessoryType = .disclosureIndicator

        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.row < filteredFunctions.count else { return }
        let function = filteredFunctions[indexPath.row]

        let detailVC = FunctionDetailViewController(function: function)
        navigationController?.pushViewController(detailVC, animated: true)
    }
}

// MARK: - Function Detail View Controller

class FunctionDetailViewController: UIViewController {
    private let function: FunctionModel
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let textView = UITextView()

    init(function: FunctionModel) {
        self.function = function
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = function.demangledName ?? function.name
        view.backgroundColor = Constants.Colors.primaryBackground

        setupUI()
        displayFunctionDetails()
    }

    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(textView)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textColor = .label
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            textView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            textView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            textView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
            textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400)
        ])
    }

    private func displayFunctionDetails() {
        var details = ""

        details += "╔═══════════════════════════════════════╗\n"
        details += "║          FUNCTION DETAILS             ║\n"
        details += "╚═══════════════════════════════════════╝\n\n"

        if let demangled = function.demangledName, demangled != function.name {
            details += "Name:          \(demangled)\n"
            details += "Mangled:       \(function.name)\n"
        } else {
            details += "Name:          \(function.name)\n"
        }
        details += "Start Address: \(Constants.formatAddress(function.startAddress))\n"
        details += "End Address:   \(Constants.formatAddress(function.endAddress))\n"

        let size: String
        if function.endAddress >= function.startAddress {
            let sizeBytes = function.endAddress - function.startAddress
            size = "\(sizeBytes) bytes"
        } else {
            size = "Invalid (end < start)"
        }
        details += "Size:          \(size)\n"
        details += "Instructions:  \(function.instructionCount)\n\n"

        details += "╔═══════════════════════════════════════╗\n"
        details += "║          DISASSEMBLY                  ║\n"
        details += "╚═══════════════════════════════════════╝\n\n"

        if let instructions = function.instructions as? [InstructionModel] {
            for inst in instructions {
                details += "\(inst.fullDisassembly)\n"
            }
        }

        textView.text = details
    }
}
