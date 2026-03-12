import UIKit

class DiffViewController: UIViewController {

    // MARK: - UI Elements

    private let leftTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        return textView
    }()

    private let rightTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        return textView
    }()

    private let dividerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .separator
        return view
    }()

    /// Full-width text view used for unified comparison modes (ObjC Classes, Security, Imports/Exports, Segments)
    private let unifiedTextView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isEditable = false
        textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = Constants.Colors.secondaryBackground
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        return textView
    }()

    private lazy var segmentedControl: UISegmentedControl = {
        let items = ["Symbols", "Disassembly", "Statistics", "Classes", "Security", "Imports", "Segments"]
        let control = UISegmentedControl(items: items)
        control.translatesAutoresizingMaskIntoConstraints = false
        control.selectedSegmentIndex = 0
        control.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        // Use smaller font so all segments fit
        control.setTitleTextAttributes([.font: UIFont.systemFont(ofSize: 10)], for: .normal)
        return control
    }()

    // MARK: - Properties

    private let leftOutput: DecompiledOutput
    private let rightOutput: DecompiledOutput

    // MARK: - Color Constants for Diff

    private static let addedColor = UIColor.systemGreen
    private static let removedColor = UIColor.systemRed
    private static let modifiedColor = UIColor.systemYellow
    private static let unchangedColor = UIColor.systemGray
    private static let headerColor = UIColor.label
    private static let sectionTitleColor = UIColor.systemBlue

    // MARK: - Initialization

    init(leftOutput: DecompiledOutput, rightOutput: DecompiledOutput) {
        self.leftOutput = leftOutput
        self.rightOutput = rightOutput
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Compare Binaries"
        view.backgroundColor = Constants.Colors.primaryBackground

        setupUI()
        updateContent()
    }

    // MARK: - Setup

    private func setupUI() {
        view.addSubview(segmentedControl)
        view.addSubview(leftTextView)
        view.addSubview(dividerView)
        view.addSubview(rightTextView)
        view.addSubview(unifiedTextView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Constants.UI.compactSpacing),
            segmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.UI.compactSpacing),
            segmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.UI.compactSpacing),

            leftTextView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.standardSpacing),
            leftTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftTextView.trailingAnchor.constraint(equalTo: dividerView.leadingAnchor),

            dividerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            dividerView.topAnchor.constraint(equalTo: leftTextView.topAnchor),
            dividerView.bottomAnchor.constraint(equalTo: leftTextView.bottomAnchor),
            dividerView.widthAnchor.constraint(equalToConstant: 1),

            rightTextView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.standardSpacing),
            rightTextView.leadingAnchor.constraint(equalTo: dividerView.trailingAnchor),
            rightTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            unifiedTextView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: Constants.UI.standardSpacing),
            unifiedTextView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            unifiedTextView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            unifiedTextView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Layout Switching

    /// Shows the side-by-side split layout and hides the unified view.
    private func showSplitLayout() {
        leftTextView.isHidden = false
        rightTextView.isHidden = false
        dividerView.isHidden = false
        unifiedTextView.isHidden = true
    }

    /// Shows the full-width unified view and hides the split layout.
    private func showUnifiedLayout() {
        leftTextView.isHidden = true
        rightTextView.isHidden = true
        dividerView.isHidden = true
        unifiedTextView.isHidden = false
    }

    // MARK: - Content Updates

    @objc private func modeChanged() {
        updateContent()
    }

    private func updateContent() {
        switch segmentedControl.selectedSegmentIndex {
        case 0:
            showSplitLayout()
            showSymbolComparison()
        case 1:
            showSplitLayout()
            showDisassemblyComparison()
        case 2:
            showSplitLayout()
            showStatistics()
        case 3:
            showUnifiedLayout()
            showObjCClassDiff()
        case 4:
            showUnifiedLayout()
            showSecurityPostureComparison()
        case 5:
            showUnifiedLayout()
            showImportExportDiff()
        case 6:
            showUnifiedLayout()
            showSegmentSizeComparison()
        default:
            break
        }
    }

    // MARK: - Existing Comparison Modes

    private func showSymbolComparison() {
        let leftSymbols = leftOutput.symbols.sortedByName()
        let rightSymbols = rightOutput.symbols.sortedByName()

        var leftText = "=== \(leftOutput.fileName) ===\n"
        leftText += "Symbols: \(leftSymbols.count)\n\n"

        for symbol in leftSymbols.prefix(5000) {
            leftText += "\(Constants.formatAddress(symbol.address, padding: 12)) \(symbol.name)\n"
        }

        var rightText = "=== \(rightOutput.fileName) ===\n"
        rightText += "Symbols: \(rightSymbols.count)\n\n"

        for symbol in rightSymbols.prefix(5000) {
            rightText += "\(Constants.formatAddress(symbol.address, padding: 12)) \(symbol.name)\n"
        }

        let leftSet = Set(leftSymbols.map { $0.name })
        let rightSet = Set(rightSymbols.map { $0.name })
        let leftOnly = leftSet.subtracting(rightSet).count
        let rightOnly = rightSet.subtracting(leftSet).count
        let common = leftSet.intersection(rightSet).count

        leftText += "\n\n=== Differences ===\n"
        leftText += "Only in left: \(leftOnly)\n"
        leftText += "Common: \(common)\n"

        rightText += "\n\n=== Differences ===\n"
        rightText += "Only in right: \(rightOnly)\n"
        rightText += "Common: \(common)\n"

        leftTextView.text = leftText
        rightTextView.text = rightText
    }

    private func showDisassemblyComparison() {
        var leftText = "=== \(leftOutput.fileName) ===\n"
        leftText += "Instructions: \(leftOutput.instructions.count)\n\n"

        for inst in leftOutput.instructions.prefix(2000) {
            leftText += inst.fullDisassembly + "\n"
        }

        if leftOutput.instructions.count > 2000 {
            leftText += "\n... and \(leftOutput.instructions.count - 2000) more instructions\n"
        }

        var rightText = "=== \(rightOutput.fileName) ===\n"
        rightText += "Instructions: \(rightOutput.instructions.count)\n\n"

        for inst in rightOutput.instructions.prefix(2000) {
            rightText += inst.fullDisassembly + "\n"
        }

        if rightOutput.instructions.count > 2000 {
            rightText += "\n... and \(rightOutput.instructions.count - 2000) more instructions\n"
        }

        leftTextView.text = leftText
        rightTextView.text = rightText
    }

    private func showStatistics() {
        let leftStats = generateStatistics(for: leftOutput)
        let rightStats = generateStatistics(for: rightOutput)

        leftTextView.text = leftStats
        rightTextView.text = rightStats
    }

    private func generateStatistics(for output: DecompiledOutput) -> String {
        var stats = "=== \(output.fileName) ===\n\n"

        stats += "File Information:\n"
        stats += "  Size: \(Constants.formatBytes(Int64(output.fileSize)))\n"
        stats += "  CPU Type: \(output.header.cpuType)\n"
        stats += "  File Type: \(output.header.fileType)\n"
        stats += "  Architecture: \(output.header.is64Bit ? "64-bit" : "32-bit")\n"
        stats += "  Encrypted: \(output.header.isEncrypted ? "Yes" : "No")\n\n"

        stats += "Structure:\n"
        stats += "  Segments: \(output.segments.count)\n"
        stats += "  Sections: \(output.sections.count)\n"
        stats += "  Load Commands: \(output.header.ncmds)\n\n"

        stats += "Symbols:\n"
        stats += "  Total: \(output.totalSymbols)\n"
        stats += "  Defined: \(output.definedSymbols)\n"
        stats += "  Undefined: \(output.undefinedSymbols)\n"
        stats += "  Functions: \(output.totalFunctions)\n\n"

        stats += "Code:\n"
        stats += "  Instructions: \(output.totalInstructions)\n"
        stats += "  Functions Detected: \(output.functions.count)\n\n"

        stats += "Processing:\n"
        stats += "  Time: \(Constants.formatDuration(output.processingTime))\n"
        stats += "  Date: \(output.processingDate)\n"

        return stats
    }

    // MARK: - Summary Header (shared by new comparison modes)

    /// Builds the summary header attributed string showing binary names, sizes, and a change overview.
    private func buildSummaryHeader() -> NSMutableAttributedString {
        let result = NSMutableAttributedString()
        let monoFont = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let boldFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .bold)
        let titleFont = UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)

        // Binary identification
        let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: DiffViewController.headerColor]
        let normalAttrs: [NSAttributedString.Key: Any] = [.font: monoFont, .foregroundColor: UIColor.label]
        let boldAttrs: [NSAttributedString.Key: Any] = [.font: boldFont, .foregroundColor: UIColor.label]

        result.append(NSAttributedString(string: "BINARY COMPARISON SUMMARY\n", attributes: titleAttrs))
        result.append(NSAttributedString(string: String(repeating: "-", count: 50) + "\n", attributes: normalAttrs))

        result.append(NSAttributedString(string: "Binary A: ", attributes: boldAttrs))
        result.append(NSAttributedString(string: "\(leftOutput.fileName) (\(Constants.formatBytes(Int64(leftOutput.fileSize))))\n", attributes: normalAttrs))

        result.append(NSAttributedString(string: "Binary B: ", attributes: boldAttrs))
        result.append(NSAttributedString(string: "\(rightOutput.fileName) (\(Constants.formatBytes(Int64(rightOutput.fileSize))))\n", attributes: normalAttrs))

        // Compute symbol-level change counts
        let leftSymbolNames = Set(leftOutput.symbols.map { $0.name })
        let rightSymbolNames = Set(rightOutput.symbols.map { $0.name })
        let addedCount = rightSymbolNames.subtracting(leftSymbolNames).count
        let removedCount = leftSymbolNames.subtracting(rightSymbolNames).count

        // For "modified", compare symbols present in both but at different addresses
        let commonNames = leftSymbolNames.intersection(rightSymbolNames)
        let leftAddrMap = Dictionary(leftOutput.symbols.map { ($0.name, $0.address) }, uniquingKeysWith: { first, _ in first })
        let rightAddrMap = Dictionary(rightOutput.symbols.map { ($0.name, $0.address) }, uniquingKeysWith: { first, _ in first })
        var modifiedCount = 0
        for name in commonNames {
            if leftAddrMap[name] != rightAddrMap[name] {
                modifiedCount += 1
            }
        }

        result.append(NSAttributedString(string: "Changes: ", attributes: boldAttrs))

        let addedStr = NSAttributedString(string: "\(addedCount) symbols added", attributes: [.font: monoFont, .foregroundColor: DiffViewController.addedColor])
        let removedStr = NSAttributedString(string: "\(removedCount) removed", attributes: [.font: monoFont, .foregroundColor: DiffViewController.removedColor])
        let modifiedStr = NSAttributedString(string: "\(modifiedCount) modified", attributes: [.font: monoFont, .foregroundColor: DiffViewController.modifiedColor])

        result.append(addedStr)
        result.append(NSAttributedString(string: ", ", attributes: normalAttrs))
        result.append(removedStr)
        result.append(NSAttributedString(string: ", ", attributes: normalAttrs))
        result.append(modifiedStr)
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs))

        result.append(NSAttributedString(string: String(repeating: "=", count: 50) + "\n\n", attributes: normalAttrs))

        return result
    }

    // MARK: - Attributed String Helpers

    private var monoFont: UIFont { .monospacedSystemFont(ofSize: 11, weight: .regular) }
    private var boldMonoFont: UIFont { .monospacedSystemFont(ofSize: 11, weight: .bold) }
    private var sectionFont: UIFont { .monospacedSystemFont(ofSize: 12, weight: .bold) }

    private func normalAttrs(_ color: UIColor = .label) -> [NSAttributedString.Key: Any] {
        return [.font: monoFont, .foregroundColor: color]
    }

    private func boldAttrs(_ color: UIColor = .label) -> [NSAttributedString.Key: Any] {
        return [.font: boldMonoFont, .foregroundColor: color]
    }

    private func sectionAttrs() -> [NSAttributedString.Key: Any] {
        return [.font: sectionFont, .foregroundColor: DiffViewController.sectionTitleColor]
    }

    private func appendSectionTitle(_ title: String, to result: NSMutableAttributedString) {
        result.append(NSAttributedString(string: "\n\(title)\n", attributes: sectionAttrs()))
        result.append(NSAttributedString(string: String(repeating: "-", count: title.count) + "\n", attributes: normalAttrs(.secondaryLabel)))
    }

    // MARK: - 1. ObjC Class Diff Section

    private func showObjCClassDiff() {
        let result = buildSummaryHeader()

        appendSectionTitle("OBJC CLASS COMPARISON", to: result)

        // Extract ObjC analysis from both binaries
        guard let leftAnalysis = leftOutput.objcAnalysis as? ObjCAnalysisResult,
              let rightAnalysis = rightOutput.objcAnalysis as? ObjCAnalysisResult else {
            result.append(NSAttributedString(
                string: "ObjC analysis data is not available for one or both binaries.\n" +
                        "Run ObjC analysis on both binaries before comparing.\n",
                attributes: normalAttrs(.secondaryLabel)))
            unifiedTextView.attributedText = result
            return
        }

        let leftClassNames = Set(leftAnalysis.classes.map { $0.name })
        let rightClassNames = Set(rightAnalysis.classes.map { $0.name })

        let removedClasses = leftClassNames.subtracting(rightClassNames).sorted()
        let addedClasses = rightClassNames.subtracting(leftClassNames).sorted()
        let commonClasses = leftClassNames.intersection(rightClassNames).sorted()

        // Build lookup dictionaries for method counts
        let leftClassMap = Dictionary(leftAnalysis.classes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let rightClassMap = Dictionary(rightAnalysis.classes.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        // Find modified classes (same name but different method counts)
        var modifiedClasses: [(name: String, leftMethods: Int, rightMethods: Int)] = []
        for className in commonClasses {
            let leftMethods = leftClassMap[className]?.totalMethods ?? 0
            let rightMethods = rightClassMap[className]?.totalMethods ?? 0
            if leftMethods != rightMethods {
                modifiedClasses.append((name: className, leftMethods: leftMethods, rightMethods: rightMethods))
            }
        }

        // Summary counts
        result.append(NSAttributedString(
            string: "Total: \(addedClasses.count) added, \(removedClasses.count) removed, \(modifiedClasses.count) modified, \(commonClasses.count - modifiedClasses.count) unchanged\n\n",
            attributes: normalAttrs()))

        // Removed classes (red)
        if !removedClasses.isEmpty {
            result.append(NSAttributedString(string: "Removed Classes (only in Binary A):\n", attributes: boldAttrs(DiffViewController.removedColor)))
            for className in removedClasses.prefix(500) {
                let cls = leftClassMap[className]
                let methodInfo = cls != nil ? " (\(cls!.totalMethods) methods)" : ""
                result.append(NSAttributedString(string: "  - \(className)\(methodInfo)\n", attributes: normalAttrs(DiffViewController.removedColor)))
            }
            if removedClasses.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(removedClasses.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
            result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))
        }

        // Added classes (green)
        if !addedClasses.isEmpty {
            result.append(NSAttributedString(string: "Added Classes (only in Binary B):\n", attributes: boldAttrs(DiffViewController.addedColor)))
            for className in addedClasses.prefix(500) {
                let cls = rightClassMap[className]
                let methodInfo = cls != nil ? " (\(cls!.totalMethods) methods)" : ""
                result.append(NSAttributedString(string: "  + \(className)\(methodInfo)\n", attributes: normalAttrs(DiffViewController.addedColor)))
            }
            if addedClasses.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(addedClasses.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
            result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))
        }

        // Modified classes (yellow)
        if !modifiedClasses.isEmpty {
            result.append(NSAttributedString(string: "Modified Classes (different method counts):\n", attributes: boldAttrs(DiffViewController.modifiedColor)))
            for entry in modifiedClasses.prefix(500) {
                let delta = entry.rightMethods - entry.leftMethods
                let deltaStr = delta > 0 ? "+\(delta)" : "\(delta)"
                result.append(NSAttributedString(
                    string: "  ~ \(entry.name): \(entry.leftMethods) -> \(entry.rightMethods) methods (\(deltaStr))\n",
                    attributes: normalAttrs(DiffViewController.modifiedColor)))
            }
            if modifiedClasses.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(modifiedClasses.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
        }

        if removedClasses.isEmpty && addedClasses.isEmpty && modifiedClasses.isEmpty {
            result.append(NSAttributedString(string: "No ObjC class differences detected.\n", attributes: normalAttrs(.secondaryLabel)))
        }

        unifiedTextView.attributedText = result
    }

    // MARK: - 2. Security Posture Comparison

    private func showSecurityPostureComparison() {
        let result = buildSummaryHeader()

        appendSectionTitle("SECURITY POSTURE COMPARISON", to: result)

        guard let leftPosture = leftOutput.securityPosture as? SecurityPosture,
              let rightPosture = rightOutput.securityPosture as? SecurityPosture else {
            result.append(NSAttributedString(
                string: "Security posture data is not available for one or both binaries.\n" +
                        "Run security analysis on both binaries before comparing.\n",
                attributes: normalAttrs(.secondaryLabel)))
            unifiedTextView.attributedText = result
            return
        }

        // Side-by-side posture ratings
        result.append(NSAttributedString(string: "Posture Ratings:\n", attributes: boldAttrs()))
        result.append(NSAttributedString(string: "  Binary A: ", attributes: boldAttrs()))
        result.append(NSAttributedString(string: "\(leftPosture.postureSummary)\n", attributes: normalAttrs()))
        result.append(NSAttributedString(string: "  Binary B: ", attributes: boldAttrs()))
        result.append(NSAttributedString(string: "\(rightPosture.postureSummary)\n\n", attributes: normalAttrs()))

        // Finding severity comparison
        result.append(NSAttributedString(string: "Finding Counts:\n", attributes: boldAttrs()))
        let severityLabels = ["Critical", "High", "Medium", "Low", "Info"]
        let leftCounts = [leftPosture.criticalCount, leftPosture.highCount, leftPosture.mediumCount, leftPosture.lowCount, leftPosture.infoCount]
        let rightCounts = [rightPosture.criticalCount, rightPosture.highCount, rightPosture.mediumCount, rightPosture.lowCount, rightPosture.infoCount]

        for i in 0..<severityLabels.count {
            let label = severityLabels[i].padding(toLength: 10, withPad: " ", startingAt: 0)
            let leftVal = leftCounts[i]
            let rightVal = rightCounts[i]
            let delta = rightVal - leftVal
            var deltaStr = ""
            var color: UIColor = .label
            if delta > 0 {
                deltaStr = " (+\(delta) REGRESSION)"
                color = DiffViewController.removedColor
            } else if delta < 0 {
                deltaStr = " (\(delta) improved)"
                color = DiffViewController.addedColor
            }
            result.append(NSAttributedString(
                string: "  \(label)  A: \(leftVal)  B: \(rightVal)\(deltaStr)\n",
                attributes: normalAttrs(color)))
        }
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))

        // Security regressions: findings that went from present to absent
        appendSectionTitle("SECURITY REGRESSIONS", to: result)

        let leftFindingMap = Dictionary(leftPosture.findings.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let rightFindingMap = Dictionary(rightPosture.findings.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        var regressionCount = 0
        for (name, leftFinding) in leftFindingMap {
            guard let rightFinding = rightFindingMap[name] else { continue }
            // A regression is when a protection was present and is now absent
            if leftFinding.status == .present && rightFinding.status == .absent {
                result.append(NSAttributedString(
                    string: "  [REGRESSION] \(name): Present -> Absent\n",
                    attributes: normalAttrs(DiffViewController.removedColor)))
                result.append(NSAttributedString(
                    string: "    \(rightFinding.findingDescription)\n",
                    attributes: normalAttrs(.secondaryLabel)))
                regressionCount += 1
            }
        }

        // Also check for improvements
        var improvementCount = 0
        for (name, leftFinding) in leftFindingMap {
            guard let rightFinding = rightFindingMap[name] else { continue }
            if leftFinding.status == .absent && rightFinding.status == .present {
                result.append(NSAttributedString(
                    string: "  [IMPROVED]   \(name): Absent -> Present\n",
                    attributes: normalAttrs(DiffViewController.addedColor)))
                improvementCount += 1
            }
        }

        if regressionCount == 0 && improvementCount == 0 {
            result.append(NSAttributedString(string: "  No security posture changes detected.\n", attributes: normalAttrs(.secondaryLabel)))
        }

        // New dangerous APIs introduced in Binary B
        appendSectionTitle("NEW DANGEROUS APIs IN BINARY B", to: result)

        let leftAPINames = Set(leftPosture.dangerousAPIs.map { $0.functionName })
        let rightAPINames = Set(rightPosture.dangerousAPIs.map { $0.functionName })
        let newAPIs = rightAPINames.subtracting(leftAPINames).sorted()
        let rightAPIMap = Dictionary(rightPosture.dangerousAPIs.map { ($0.functionName, $0) }, uniquingKeysWith: { first, _ in first })

        if newAPIs.isEmpty {
            result.append(NSAttributedString(string: "  No new dangerous APIs introduced.\n", attributes: normalAttrs(.secondaryLabel)))
        } else {
            for apiName in newAPIs {
                let api = rightAPIMap[apiName]
                let severity = api?.severityString ?? "Unknown"
                let risk = api?.riskDescription ?? ""
                result.append(NSAttributedString(
                    string: "  + \(apiName) [\(severity)]\n",
                    attributes: normalAttrs(DiffViewController.removedColor)))
                if !risk.isEmpty {
                    result.append(NSAttributedString(
                        string: "    \(risk)\n",
                        attributes: normalAttrs(.secondaryLabel)))
                }
            }
        }

        // Dangerous APIs removed (good news)
        let removedAPIs = leftAPINames.subtracting(rightAPINames).sorted()
        if !removedAPIs.isEmpty {
            result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))
            result.append(NSAttributedString(string: "Dangerous APIs Removed in Binary B:\n", attributes: boldAttrs(DiffViewController.addedColor)))
            for apiName in removedAPIs {
                result.append(NSAttributedString(
                    string: "  - \(apiName)\n",
                    attributes: normalAttrs(DiffViewController.addedColor)))
            }
        }

        unifiedTextView.attributedText = result
    }

    // MARK: - 3. Import/Export Diff

    private func showImportExportDiff() {
        let result = buildSummaryHeader()

        appendSectionTitle("IMPORT / EXPORT COMPARISON", to: result)

        guard let leftIE = leftOutput.importExportAnalysis as? ImportExportAnalysis,
              let rightIE = rightOutput.importExportAnalysis as? ImportExportAnalysis else {
            result.append(NSAttributedString(
                string: "Import/Export analysis data is not available for one or both binaries.\n" +
                        "Run import/export analysis on both binaries before comparing.\n",
                attributes: normalAttrs(.secondaryLabel)))
            unifiedTextView.attributedText = result
            return
        }

        // --- Imports ---
        let leftImportNames = Set(leftIE.imports.map { $0.name })
        let rightImportNames = Set(rightIE.imports.map { $0.name })
        let newImports = rightImportNames.subtracting(leftImportNames).sorted()
        let removedImports = leftImportNames.subtracting(rightImportNames).sorted()

        result.append(NSAttributedString(
            string: "Imports: \(leftIE.imports.count) (A) vs \(rightIE.imports.count) (B)\n\n",
            attributes: normalAttrs()))

        // New imports (added dependencies)
        result.append(NSAttributedString(string: "New Imports (added dependencies):\n", attributes: boldAttrs(DiffViewController.addedColor)))
        if newImports.isEmpty {
            result.append(NSAttributedString(string: "  None\n", attributes: normalAttrs(.secondaryLabel)))
        } else {
            let rightImportMap = Dictionary(rightIE.imports.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            for name in newImports.prefix(500) {
                let lib = rightImportMap[name]?.libraryName ?? ""
                let libStr = lib.isEmpty ? "" : " (from \(lib))"
                result.append(NSAttributedString(
                    string: "  + \(name)\(libStr)\n",
                    attributes: normalAttrs(DiffViewController.addedColor)))
            }
            if newImports.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(newImports.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))

        // Removed imports
        result.append(NSAttributedString(string: "Removed Imports:\n", attributes: boldAttrs(DiffViewController.removedColor)))
        if removedImports.isEmpty {
            result.append(NSAttributedString(string: "  None\n", attributes: normalAttrs(.secondaryLabel)))
        } else {
            let leftImportMap = Dictionary(leftIE.imports.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
            for name in removedImports.prefix(500) {
                let lib = leftImportMap[name]?.libraryName ?? ""
                let libStr = lib.isEmpty ? "" : " (was from \(lib))"
                result.append(NSAttributedString(
                    string: "  - \(name)\(libStr)\n",
                    attributes: normalAttrs(DiffViewController.removedColor)))
            }
            if removedImports.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(removedImports.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))

        // --- Exports ---
        appendSectionTitle("EXPORTS", to: result)

        let leftExportNames = Set(leftIE.exports.map { $0.name })
        let rightExportNames = Set(rightIE.exports.map { $0.name })
        let newExports = rightExportNames.subtracting(leftExportNames).sorted()
        let removedExports = leftExportNames.subtracting(rightExportNames).sorted()

        result.append(NSAttributedString(
            string: "Exports: \(leftIE.exports.count) (A) vs \(rightIE.exports.count) (B)\n\n",
            attributes: normalAttrs()))

        // New exports
        result.append(NSAttributedString(string: "New Exports:\n", attributes: boldAttrs(DiffViewController.addedColor)))
        if newExports.isEmpty {
            result.append(NSAttributedString(string: "  None\n", attributes: normalAttrs(.secondaryLabel)))
        } else {
            for name in newExports.prefix(500) {
                result.append(NSAttributedString(
                    string: "  + \(name)\n",
                    attributes: normalAttrs(DiffViewController.addedColor)))
            }
            if newExports.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(newExports.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
        }
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))

        // Removed exports
        result.append(NSAttributedString(string: "Removed Exports:\n", attributes: boldAttrs(DiffViewController.removedColor)))
        if removedExports.isEmpty {
            result.append(NSAttributedString(string: "  None\n", attributes: normalAttrs(.secondaryLabel)))
        } else {
            for name in removedExports.prefix(500) {
                result.append(NSAttributedString(
                    string: "  - \(name)\n",
                    attributes: normalAttrs(DiffViewController.removedColor)))
            }
            if removedExports.count > 500 {
                result.append(NSAttributedString(string: "  ... and \(removedExports.count - 500) more\n", attributes: normalAttrs(.secondaryLabel)))
            }
        }

        // Linked library diff
        appendSectionTitle("LINKED LIBRARIES", to: result)
        let leftLibs = Set(leftIE.linkedLibraries)
        let rightLibs = Set(rightIE.linkedLibraries)
        let newLibs = rightLibs.subtracting(leftLibs).sorted()
        let removedLibs = leftLibs.subtracting(rightLibs).sorted()

        if !newLibs.isEmpty {
            result.append(NSAttributedString(string: "New Libraries:\n", attributes: boldAttrs(DiffViewController.addedColor)))
            for lib in newLibs {
                result.append(NSAttributedString(string: "  + \(lib)\n", attributes: normalAttrs(DiffViewController.addedColor)))
            }
            result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))
        }
        if !removedLibs.isEmpty {
            result.append(NSAttributedString(string: "Removed Libraries:\n", attributes: boldAttrs(DiffViewController.removedColor)))
            for lib in removedLibs {
                result.append(NSAttributedString(string: "  - \(lib)\n", attributes: normalAttrs(DiffViewController.removedColor)))
            }
        }
        if newLibs.isEmpty && removedLibs.isEmpty {
            result.append(NSAttributedString(string: "  No library changes.\n", attributes: normalAttrs(.secondaryLabel)))
        }

        unifiedTextView.attributedText = result
    }

    // MARK: - 4. Segment Size Comparison

    private func showSegmentSizeComparison() {
        let result = buildSummaryHeader()

        appendSectionTitle("SEGMENT SIZE COMPARISON", to: result)

        // Build segment lookup maps by name
        let leftSegMap = Dictionary(leftOutput.segments.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let rightSegMap = Dictionary(rightOutput.segments.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })

        // Collect all segment names preserving order from left, then any new from right
        var allSegmentNames: [String] = []
        var seen = Set<String>()
        for seg in leftOutput.segments {
            if seen.insert(seg.name).inserted {
                allSegmentNames.append(seg.name)
            }
        }
        for seg in rightOutput.segments {
            if seen.insert(seg.name).inserted {
                allSegmentNames.append(seg.name)
            }
        }

        // Header row
        let nameCol = "Segment".padding(toLength: 20, withPad: " ", startingAt: 0)
        let oldCol = "Old Size".padding(toLength: 14, withPad: " ", startingAt: 0)
        let newCol = "New Size".padding(toLength: 14, withPad: " ", startingAt: 0)
        let deltaCol = "Delta"
        result.append(NSAttributedString(
            string: "\(nameCol) \(oldCol) \(newCol) \(deltaCol)\n",
            attributes: boldAttrs()))
        result.append(NSAttributedString(
            string: String(repeating: "-", count: 65) + "\n",
            attributes: normalAttrs(.secondaryLabel)))

        var totalLeftSize: UInt64 = 0
        var totalRightSize: UInt64 = 0

        for segName in allSegmentNames {
            let leftSeg = leftSegMap[segName]
            let rightSeg = rightSegMap[segName]

            let leftSize = leftSeg?.fileSize ?? 0
            let rightSize = rightSeg?.fileSize ?? 0

            totalLeftSize += leftSize
            totalRightSize += rightSize

            let delta = Int64(rightSize) - Int64(leftSize)

            let color: UIColor
            if delta > 0 {
                color = DiffViewController.removedColor  // larger = red
            } else if delta < 0 {
                color = DiffViewController.addedColor     // smaller = green
            } else {
                color = DiffViewController.unchangedColor // unchanged = gray
            }

            let nameStr = segName.padding(toLength: 20, withPad: " ", startingAt: 0)
            let oldStr: String
            if leftSeg != nil {
                oldStr = Constants.formatBytes(Int64(leftSize)).padding(toLength: 14, withPad: " ", startingAt: 0)
            } else {
                oldStr = "(none)".padding(toLength: 14, withPad: " ", startingAt: 0)
            }
            let newStr: String
            if rightSeg != nil {
                newStr = Constants.formatBytes(Int64(rightSize)).padding(toLength: 14, withPad: " ", startingAt: 0)
            } else {
                newStr = "(none)".padding(toLength: 14, withPad: " ", startingAt: 0)
            }

            let deltaStr: String
            if delta > 0 {
                deltaStr = "+\(Constants.formatBytes(Int64(delta)))"
            } else if delta < 0 {
                deltaStr = "-\(Constants.formatBytes(Int64(-delta)))"
            } else {
                deltaStr = "unchanged"
            }

            result.append(NSAttributedString(
                string: "\(nameStr) \(oldStr) \(newStr) \(deltaStr)\n",
                attributes: normalAttrs(color)))
        }

        // Total binary size change
        result.append(NSAttributedString(
            string: String(repeating: "-", count: 65) + "\n",
            attributes: normalAttrs(.secondaryLabel)))

        let totalDelta = Int64(totalRightSize) - Int64(totalLeftSize)
        let totalColor: UIColor
        if totalDelta > 0 {
            totalColor = DiffViewController.removedColor
        } else if totalDelta < 0 {
            totalColor = DiffViewController.addedColor
        } else {
            totalColor = DiffViewController.unchangedColor
        }

        let totalNameStr = "TOTAL".padding(toLength: 20, withPad: " ", startingAt: 0)
        let totalOldStr = Constants.formatBytes(Int64(totalLeftSize)).padding(toLength: 14, withPad: " ", startingAt: 0)
        let totalNewStr = Constants.formatBytes(Int64(totalRightSize)).padding(toLength: 14, withPad: " ", startingAt: 0)
        let totalDeltaStr: String
        if totalDelta > 0 {
            totalDeltaStr = "+\(Constants.formatBytes(Int64(totalDelta)))"
        } else if totalDelta < 0 {
            totalDeltaStr = "-\(Constants.formatBytes(Int64(-totalDelta)))"
        } else {
            totalDeltaStr = "unchanged"
        }

        result.append(NSAttributedString(
            string: "\(totalNameStr) \(totalOldStr) \(totalNewStr) \(totalDeltaStr)\n",
            attributes: boldAttrs(totalColor)))

        // Also show overall file size comparison
        result.append(NSAttributedString(string: "\n", attributes: normalAttrs()))
        appendSectionTitle("FILE SIZE", to: result)

        let fileDelta = Int64(rightOutput.fileSize) - Int64(leftOutput.fileSize)
        let fileColor: UIColor
        if fileDelta > 0 {
            fileColor = DiffViewController.removedColor
        } else if fileDelta < 0 {
            fileColor = DiffViewController.addedColor
        } else {
            fileColor = DiffViewController.unchangedColor
        }

        result.append(NSAttributedString(
            string: "  Binary A: \(Constants.formatBytes(Int64(leftOutput.fileSize)))\n",
            attributes: normalAttrs()))
        result.append(NSAttributedString(
            string: "  Binary B: \(Constants.formatBytes(Int64(rightOutput.fileSize)))\n",
            attributes: normalAttrs()))

        let fileDeltaStr: String
        if fileDelta > 0 {
            fileDeltaStr = "+\(Constants.formatBytes(Int64(fileDelta))) (larger)"
        } else if fileDelta < 0 {
            fileDeltaStr = "-\(Constants.formatBytes(Int64(-fileDelta))) (smaller)"
        } else {
            fileDeltaStr = "identical size"
        }
        result.append(NSAttributedString(
            string: "  Change:   \(fileDeltaStr)\n",
            attributes: boldAttrs(fileColor)))

        unifiedTextView.attributedText = result
    }
}
