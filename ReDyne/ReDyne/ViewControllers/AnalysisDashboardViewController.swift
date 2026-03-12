import UIKit

// MARK: - Analysis Dashboard View Controller

class AnalysisDashboardViewController: UIViewController {

    // MARK: - Properties

    private let output: DecompiledOutput

    // MARK: - Quick Action Delegate

    protocol QuickActionDelegate: AnyObject {
        func dashboardDidRequestNavigation(to analysisType: AnalysisType)
    }

    weak var quickActionDelegate: QuickActionDelegate?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .vertical
        sv.spacing = 16
        sv.alignment = .fill
        return sv
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

        title = "Analysis Dashboard"
        view.backgroundColor = Constants.Colors.primaryBackground

        setupScrollView()
        buildCards()
    }

    // MARK: - Setup

    private func setupScrollView() {
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.UI.standardSpacing),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.UI.standardSpacing),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.UI.standardSpacing),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.UI.standardSpacing),
            stackView.widthAnchor.constraint(equalTo: scrollView.widthAnchor, constant: -Constants.UI.standardSpacing * 2)
        ])
    }

    // MARK: - Card Building

    private func buildCards() {
        stackView.addArrangedSubview(buildBinarySummaryCard())
        stackView.addArrangedSubview(buildStatisticsGridCard())

        if let securityCard = buildSecurityOverviewCard() {
            stackView.addArrangedSubview(securityCard)
        }

        stackView.addArrangedSubview(buildQuickActionsCard())
    }

    // MARK: - Card 1: Binary Summary

    private func buildBinarySummaryCard() -> UIView {
        let card = makeCard()
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 10

        let titleLabel = makeCardTitle("Binary Summary", icon: "doc.fill")
        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(makeSeparator())

        content.addArrangedSubview(makeInfoRow(label: "File Name", value: output.fileName))
        content.addArrangedSubview(makeInfoRow(label: "Architecture",
                                                value: "\(output.header.cpuType) (\(output.header.is64Bit ? "64-bit" : "32-bit"))"))
        if let platform = output.header.platformName {
            content.addArrangedSubview(makeInfoRow(label: "Platform", value: platform))
        }
        content.addArrangedSubview(makeInfoRow(label: "File Size",
                                                value: Constants.formatBytes(Int64(output.fileSize))))
        content.addArrangedSubview(makeInfoRow(label: "File Type", value: output.header.fileType))

        if let uuid = output.header.uuid {
            let uuidRow = makeInfoRow(label: "UUID", value: uuid)
            content.addArrangedSubview(uuidRow)
        }

        if output.header.hasEntryPoint {
            content.addArrangedSubview(makeInfoRow(label: "Entry Point",
                                                    value: String(format: "0x%llX", output.header.entryPointAddress)))
        }

        // PIE status with color indicator
        let pieRow = UIStackView()
        pieRow.axis = .horizontal
        pieRow.spacing = 8
        pieRow.alignment = .center

        let pieLabel = UILabel()
        pieLabel.text = "PIE"
        pieLabel.font = .systemFont(ofSize: 14, weight: .medium)
        pieLabel.textColor = .secondaryLabel
        pieLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let pieDot = UIView()
        pieDot.translatesAutoresizingMaskIntoConstraints = false
        pieDot.layer.cornerRadius = 5
        pieDot.backgroundColor = output.header.isPIE ? Constants.Colors.successColor : Constants.Colors.errorColor
        NSLayoutConstraint.activate([
            pieDot.widthAnchor.constraint(equalToConstant: 10),
            pieDot.heightAnchor.constraint(equalToConstant: 10)
        ])

        let pieValue = UILabel()
        pieValue.text = output.header.isPIE ? "Enabled" : "Disabled"
        pieValue.font = .systemFont(ofSize: 14, weight: .semibold)
        pieValue.textColor = output.header.isPIE ? Constants.Colors.successColor : Constants.Colors.errorColor
        pieValue.textAlignment = .right

        pieRow.addArrangedSubview(pieLabel)
        pieRow.addArrangedSubview(UIView()) // spacer
        pieRow.addArrangedSubview(pieDot)
        pieRow.addArrangedSubview(pieValue)
        content.addArrangedSubview(pieRow)

        // Processing time
        content.addArrangedSubview(makeSeparator())
        content.addArrangedSubview(makeInfoRow(label: "Processing Time",
                                                value: Constants.formatDuration(output.processingTime)))

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    // MARK: - Card 2: Statistics Grid

    private func buildStatisticsGridCard() -> UIView {
        let card = makeCard()
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 12

        let titleLabel = makeCardTitle("Statistics", icon: "chart.bar.fill")
        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(makeSeparator())

        // Row 1: Symbols, Strings, Instructions
        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 10

        let symbolSubtitle = "\(output.definedSymbols) def / \(output.undefinedSymbols) undef"
        row1.addArrangedSubview(makeStatCell(value: "\(output.totalSymbols)", label: "Symbols", subtitle: symbolSubtitle))
        row1.addArrangedSubview(makeStatCell(value: "\(output.totalStrings)", label: "Strings"))
        row1.addArrangedSubview(makeStatCell(value: "\(output.totalInstructions)", label: "Instructions"))

        content.addArrangedSubview(row1)

        // Row 2: Functions, Imports/Exports, ObjC Classes
        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 10

        row2.addArrangedSubview(makeStatCell(value: "\(output.totalFunctions)", label: "Functions"))

        let importExportTotal = output.totalImports + output.totalExports
        let ieSubtitle = "\(output.totalImports) in / \(output.totalExports) out"
        row2.addArrangedSubview(makeStatCell(value: "\(importExportTotal)", label: "Imports/Exports",
                                              subtitle: importExportTotal > 0 ? ieSubtitle : nil))

        if output.totalObjCClasses > 0 {
            let objcSubtitle = "\(output.totalObjCMethods) methods"
            row2.addArrangedSubview(makeStatCell(value: "\(output.totalObjCClasses)", label: "ObjC Classes",
                                                  subtitle: objcSubtitle))
        } else {
            let xrefLabel = output.totalXrefs > 0 ? "Cross-Refs" : "Libraries"
            let xrefValue = output.totalXrefs > 0 ? "\(output.totalXrefs)" : "\(output.totalLinkedLibraries)"
            row2.addArrangedSubview(makeStatCell(value: xrefValue, label: xrefLabel))
        }

        content.addArrangedSubview(row2)

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    // MARK: - Card 3: Security Overview

    private func buildSecurityOverviewCard() -> UIView? {
        guard let posture = output.securityPosture as? SecurityPosture else { return nil }

        let card = makeCard()
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 12

        let titleLabel = makeCardTitle("Security Overview", icon: "shield.checkered")
        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(makeSeparator())

        // Posture rating
        let ratingColor = securityColor(for: posture)
        let ratingRow = UIStackView()
        ratingRow.axis = .horizontal
        ratingRow.spacing = 10
        ratingRow.alignment = .center

        let ratingDot = UIView()
        ratingDot.translatesAutoresizingMaskIntoConstraints = false
        ratingDot.layer.cornerRadius = 8
        ratingDot.backgroundColor = ratingColor
        NSLayoutConstraint.activate([
            ratingDot.widthAnchor.constraint(equalToConstant: 16),
            ratingDot.heightAnchor.constraint(equalToConstant: 16)
        ])

        let ratingLabel = UILabel()
        ratingLabel.text = posture.postureSummary
        ratingLabel.font = .systemFont(ofSize: 18, weight: .bold)
        ratingLabel.textColor = ratingColor

        ratingRow.addArrangedSubview(ratingDot)
        ratingRow.addArrangedSubview(ratingLabel)
        ratingRow.addArrangedSubview(UIView()) // spacer
        content.addArrangedSubview(ratingRow)

        // Severity bar
        let barContainer = UIStackView()
        barContainer.axis = .horizontal
        barContainer.spacing = 6
        barContainer.distribution = .fill
        barContainer.alignment = .center

        let severityCounts: [(String, Int, UIColor)] = [
            ("Critical", posture.criticalCount, Constants.Colors.errorColor),
            ("High", posture.highCount, Constants.Colors.warningColor),
            ("Medium", posture.mediumCount, UIColor.systemYellow),
            ("Low", posture.lowCount, Constants.Colors.successColor)
        ]

        for (label, count, color) in severityCounts {
            let pill = makeSeverityPill(label: label, count: count, color: color)
            barContainer.addArrangedSubview(pill)
        }
        barContainer.addArrangedSubview(UIView()) // trailing spacer

        content.addArrangedSubview(barContainer)

        // Dangerous APIs count
        if posture.hasDangerousAPIs {
            let apiRow = UIStackView()
            apiRow.axis = .horizontal
            apiRow.spacing = 8
            apiRow.alignment = .center

            let warningIcon = UIImageView(image: UIImage(systemName: "exclamationmark.triangle.fill"))
            warningIcon.tintColor = Constants.Colors.warningColor
            warningIcon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                warningIcon.widthAnchor.constraint(equalToConstant: 18),
                warningIcon.heightAnchor.constraint(equalToConstant: 18)
            ])

            let apiLabel = UILabel()
            apiLabel.text = "\(posture.dangerousAPIs.count) dangerous API\(posture.dangerousAPIs.count == 1 ? "" : "s") detected"
            apiLabel.font = .systemFont(ofSize: 14, weight: .medium)
            apiLabel.textColor = Constants.Colors.warningColor

            apiRow.addArrangedSubview(warningIcon)
            apiRow.addArrangedSubview(apiLabel)
            apiRow.addArrangedSubview(UIView())
            content.addArrangedSubview(apiRow)
        }

        // Insecure functions
        if posture.hasInsecureFunctions {
            let insecureLabel = UILabel()
            insecureLabel.text = "\(posture.insecureFunctions.count) insecure function\(posture.insecureFunctions.count == 1 ? "" : "s") found"
            insecureLabel.font = .systemFont(ofSize: 13, weight: .regular)
            insecureLabel.textColor = .secondaryLabel
            content.addArrangedSubview(insecureLabel)
        }

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    // MARK: - Card 5: Quick Actions

    private func buildQuickActionsCard() -> UIView {
        let card = makeCard()
        let content = UIStackView()
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 12

        let titleLabel = makeCardTitle("Quick Actions", icon: "bolt.fill")
        content.addArrangedSubview(titleLabel)
        content.addArrangedSubview(makeSeparator())

        let row1 = UIStackView()
        row1.axis = .horizontal
        row1.distribution = .fillEqually
        row1.spacing = 10

        row1.addArrangedSubview(makeQuickActionButton(title: "Symbols", icon: "list.bullet", tag: 0))
        row1.addArrangedSubview(makeQuickActionButton(title: "Strings", icon: "text.quote", tag: 1))
        row1.addArrangedSubview(makeQuickActionButton(title: "Disassembly", icon: "terminal", tag: 2))

        content.addArrangedSubview(row1)

        let row2 = UIStackView()
        row2.axis = .horizontal
        row2.distribution = .fillEqually
        row2.spacing = 10

        let hasSecurityPosture = output.securityPosture != nil
        row2.addArrangedSubview(makeQuickActionButton(title: "Security", icon: "shield.checkered", tag: 3,
                                                       enabled: hasSecurityPosture))
        row2.addArrangedSubview(makeQuickActionButton(title: "Hex Viewer", icon: "text.magnifyingglass", tag: 4))
        row2.addArrangedSubview(makeQuickActionButton(title: "Memory Map", icon: "square.stack.3d.up", tag: 5))

        content.addArrangedSubview(row2)

        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    // MARK: - Quick Action Handler

    @objc private func quickActionTapped(_ sender: UIButton) {
        let analysisType: AnalysisType?

        switch sender.tag {
        case 0: // Symbols - handled by delegate or pop back
            popToResultsAndSelectSegment(1)
            return
        case 1: // Strings
            popToResultsAndSelectSegment(2)
            return
        case 2: // Disassembly
            popToResultsAndSelectSegment(3)
            return
        case 3:
            analysisType = .security
        case 4:
            analysisType = .hexViewer
        case 5:
            analysisType = .memoryMap
        default:
            analysisType = nil
        }

        if let type = analysisType {
            quickActionDelegate?.dashboardDidRequestNavigation(to: type)
        }
    }

    private func popToResultsAndSelectSegment(_ index: Int) {
        guard let navController = navigationController else { return }
        for vc in navController.viewControllers {
            if let resultsVC = vc as? ResultsViewController {
                navController.popToViewController(resultsVC, animated: true)
                resultsVC.selectSegment(index)
                return
            }
        }
    }

    // MARK: - UI Factory Helpers

    private func makeCard() -> UIView {
        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = Constants.Colors.secondaryBackground
        card.layer.cornerRadius = Constants.UI.cornerRadius * 1.5
        card.layer.masksToBounds = true
        return card
    }

    private func makeCardTitle(_ text: String, icon: String) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        let iconView = UIImageView(image: UIImage(systemName: icon))
        iconView.tintColor = Constants.Colors.accentColor
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 22),
            iconView.heightAnchor.constraint(equalToConstant: 22)
        ])

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .label

        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(UIView()) // trailing spacer

        return stack
    }

    private func makeSeparator() -> UIView {
        let separator = UIView()
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator
        separator.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return separator
    }

    private func makeInfoRow(label: String, value: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 8

        let labelView = UILabel()
        labelView.text = label
        labelView.font = .systemFont(ofSize: 14, weight: .medium)
        labelView.textColor = .secondaryLabel
        labelView.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        labelView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let valueView = UILabel()
        valueView.text = value
        valueView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        valueView.textColor = .label
        valueView.textAlignment = .right
        valueView.numberOfLines = 0
        valueView.lineBreakMode = .byTruncatingMiddle

        row.addArrangedSubview(labelView)
        row.addArrangedSubview(UIView()) // spacer
        row.addArrangedSubview(valueView)

        return row
    }

    private func makeStatCell(value: String, label: String, subtitle: String? = nil) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = Constants.Colors.tertiaryBackground
        container.layer.cornerRadius = Constants.UI.cornerRadius
        container.layer.masksToBounds = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .center

        let valueLabel = UILabel()
        valueLabel.text = formatStatNumber(value)
        valueLabel.font = .systemFont(ofSize: 22, weight: .bold)
        valueLabel.textColor = Constants.Colors.accentColor
        valueLabel.textAlignment = .center

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = .secondaryLabel
        nameLabel.textAlignment = .center

        stack.addArrangedSubview(valueLabel)
        stack.addArrangedSubview(nameLabel)

        if let subtitle = subtitle {
            let subLabel = UILabel()
            subLabel.text = subtitle
            subLabel.font = .systemFont(ofSize: 9, weight: .regular)
            subLabel.textColor = .tertiaryLabel
            subLabel.textAlignment = .center
            stack.addArrangedSubview(subLabel)
        }

        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        // Accessibility
        container.isAccessibilityElement = true
        container.accessibilityLabel = "\(label): \(value)"
        if let subtitle = subtitle {
            container.accessibilityValue = subtitle
        }
        container.accessibilityTraits = .staticText

        return container
    }

    private func makeSeverityPill(label: String, count: Int, color: UIColor) -> UIView {
        let pill = UIView()
        pill.translatesAutoresizingMaskIntoConstraints = false
        pill.backgroundColor = color.withAlphaComponent(0.15)
        pill.layer.cornerRadius = 10
        pill.layer.masksToBounds = true

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center

        let countLabel = UILabel()
        countLabel.text = "\(count)"
        countLabel.font = .systemFont(ofSize: 13, weight: .bold)
        countLabel.textColor = color

        let nameLabel = UILabel()
        nameLabel.text = label
        nameLabel.font = .systemFont(ofSize: 11, weight: .medium)
        nameLabel.textColor = color

        stack.addArrangedSubview(countLabel)
        stack.addArrangedSubview(nameLabel)

        pill.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4)
        ])

        // Accessibility
        pill.isAccessibilityElement = true
        pill.accessibilityLabel = "\(count) \(label)"
        pill.accessibilityTraits = .staticText

        return pill
    }

    private func makeQuickActionButton(title: String, icon: String, tag: Int, enabled: Bool = true) -> UIView {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = tag
        button.isEnabled = enabled
        button.addTarget(self, action: #selector(quickActionTapped(_:)), for: .touchUpInside)

        var config = UIButton.Configuration.filled()
        config.cornerStyle = .medium
        config.baseBackgroundColor = Constants.Colors.tertiaryBackground
        config.baseForegroundColor = enabled ? Constants.Colors.accentColor : .tertiaryLabel
        config.image = UIImage(systemName: icon)?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))
        config.imagePlacement = .top
        config.imagePadding = 6
        config.title = title
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 11, weight: .medium)
            return outgoing
        }
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 4, bottom: 12, trailing: 4)

        button.configuration = config

        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 70).isActive = true

        // Accessibility
        button.accessibilityLabel = title
        button.accessibilityHint = enabled ? "Double tap to open \(title)" : "\(title) is not available"
        button.accessibilityTraits = enabled ? .button : [.button, .notEnabled]

        return button
    }

    // MARK: - Utility

    private func securityColor(for posture: SecurityPosture) -> UIColor {
        if posture.criticalCount > 0 {
            return Constants.Colors.errorColor
        } else if posture.highCount > 0 {
            return Constants.Colors.warningColor
        } else if posture.mediumCount > 0 {
            return UIColor.systemYellow
        } else {
            return Constants.Colors.successColor
        }
    }

    private func formatStatNumber(_ value: String) -> String {
        guard let num = Int(value) else { return value }
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000.0)
        } else if num >= 10_000 {
            return String(format: "%.1fK", Double(num) / 1_000.0)
        }
        return value
    }
}
