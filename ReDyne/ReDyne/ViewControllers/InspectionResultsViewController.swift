import UIKit

final class InspectionResultsViewController: UIViewController {

    // MARK: - Properties

    private let report: InspectionReport
    private var showFailuresOnly = false

    /// Grouped results by category, preserving category order from RuleCategory.allCases.
    private var groupedResults: [(category: RuleCategory, items: [(rule: InspectionRule, result: RuleResult)])] = []
    private var filteredGroupedResults: [(category: RuleCategory, items: [(rule: InspectionRule, result: RuleResult)])] = []

    // MARK: - UI Elements

    private let tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.backgroundColor = Constants.Colors.primaryBackground
        return tv
    }()

    private let summaryContainer: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Constants.Colors.secondaryBackground
        return v
    }()

    private let summaryLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textAlignment = .center
        label.numberOfLines = 0
        return label
    }()

    private let progressBarBackground: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Constants.Colors.errorColor.withAlphaComponent(0.25)
        v.layer.cornerRadius = 6
        v.clipsToBounds = true
        return v
    }()

    private let progressBarFill: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = Constants.Colors.successColor
        v.layer.cornerRadius = 6
        return v
    }()

    private var progressWidthConstraint: NSLayoutConstraint?

    private let filterButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setTitle("Show Failures Only", for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        return btn
    }()

    // MARK: - Init

    init(report: InspectionReport) {
        self.report = report
        super.init(nibName: nil, bundle: nil)
        buildGroupedResults()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Inspection Results"
        view.backgroundColor = Constants.Colors.primaryBackground
        setupHeader()
        setupTableView()
        updateSummary()
        applyFilter()
    }

    // MARK: - Setup

    private func setupHeader() {
        view.addSubview(summaryContainer)
        summaryContainer.addSubview(summaryLabel)
        summaryContainer.addSubview(progressBarBackground)
        progressBarBackground.addSubview(progressBarFill)
        summaryContainer.addSubview(filterButton)

        let fillWidth = progressBarFill.widthAnchor.constraint(equalToConstant: 0)
        progressWidthConstraint = fillWidth

        NSLayoutConstraint.activate([
            summaryContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            summaryContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            summaryContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            summaryLabel.topAnchor.constraint(equalTo: summaryContainer.topAnchor, constant: 14),
            summaryLabel.leadingAnchor.constraint(equalTo: summaryContainer.leadingAnchor, constant: 16),
            summaryLabel.trailingAnchor.constraint(equalTo: summaryContainer.trailingAnchor, constant: -16),

            progressBarBackground.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 10),
            progressBarBackground.leadingAnchor.constraint(equalTo: summaryContainer.leadingAnchor, constant: 16),
            progressBarBackground.trailingAnchor.constraint(equalTo: summaryContainer.trailingAnchor, constant: -16),
            progressBarBackground.heightAnchor.constraint(equalToConstant: 12),

            progressBarFill.topAnchor.constraint(equalTo: progressBarBackground.topAnchor),
            progressBarFill.leadingAnchor.constraint(equalTo: progressBarBackground.leadingAnchor),
            progressBarFill.bottomAnchor.constraint(equalTo: progressBarBackground.bottomAnchor),
            fillWidth,

            filterButton.topAnchor.constraint(equalTo: progressBarBackground.bottomAnchor, constant: 10),
            filterButton.centerXAnchor.constraint(equalTo: summaryContainer.centerXAnchor),
            filterButton.bottomAnchor.constraint(equalTo: summaryContainer.bottomAnchor, constant: -10),
        ])

        filterButton.addTarget(self, action: #selector(toggleFilter), for: .touchUpInside)
    }

    private func setupTableView() {
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(InspectionRuleCell.self, forCellReuseIdentifier: InspectionRuleCell.reuseID)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: summaryContainer.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Data

    private func buildGroupedResults() {
        var dict = [RuleCategory: [(rule: InspectionRule, result: RuleResult)]]()
        for entry in report.results {
            dict[entry.rule.category, default: []].append(entry)
        }
        groupedResults = RuleCategory.allCases.compactMap { cat in
            guard let items = dict[cat], !items.isEmpty else { return nil }
            return (category: cat, items: items)
        }
    }

    private func applyFilter() {
        if showFailuresOnly {
            filteredGroupedResults = groupedResults.compactMap { group in
                let filtered = group.items.filter { !$0.result.passed }
                return filtered.isEmpty ? nil : (category: group.category, items: filtered)
            }
        } else {
            filteredGroupedResults = groupedResults
        }
        tableView.reloadData()
    }

    private func updateSummary() {
        let total = report.passCount + report.failCount
        summaryLabel.text = "\(report.passCount) passed, \(report.failCount) failed out of \(total) rules"

        // Layout pass needed to read the bar width
        view.layoutIfNeeded()
        let barWidth = progressBarBackground.bounds.width
        let ratio: CGFloat = total > 0 ? CGFloat(report.passCount) / CGFloat(total) : 0
        progressWidthConstraint?.constant = barWidth * ratio
        UIView.animate(withDuration: Constants.UI.animationDuration) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let barWidth = progressBarBackground.bounds.width
        let total = report.passCount + report.failCount
        let ratio: CGFloat = total > 0 ? CGFloat(report.passCount) / CGFloat(total) : 0
        progressWidthConstraint?.constant = barWidth * ratio
    }

    // MARK: - Actions

    @objc private func toggleFilter() {
        showFailuresOnly.toggle()
        filterButton.setTitle(showFailuresOnly ? "Show All" : "Show Failures Only", for: .normal)
        applyFilter()
    }
}

// MARK: - UITableViewDataSource & Delegate

extension InspectionResultsViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        return filteredGroupedResults.count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let group = filteredGroupedResults[section]
        let failCount = group.items.filter { !$0.result.passed }.count
        if failCount > 0 {
            return "\(group.category.rawValue)  (\(failCount) issue\(failCount == 1 ? "" : "s"))"
        }
        return group.category.rawValue
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filteredGroupedResults[section].items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: InspectionRuleCell.reuseID, for: indexPath) as! InspectionRuleCell
        let entry = filteredGroupedResults[indexPath.section].items[indexPath.row]
        cell.configure(rule: entry.rule, result: entry.result)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let entry = filteredGroupedResults[indexPath.section].items[indexPath.row]
        guard !entry.result.passed, !entry.result.details.isEmpty else { return }

        let detailVC = InspectionRuleDetailViewController(rule: entry.rule, result: entry.result)
        navigationController?.pushViewController(detailVC, animated: true)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 72
    }
}

// MARK: - Inspection Rule Cell

private final class InspectionRuleCell: UITableViewCell {
    static let reuseID = "InspectionRuleCell"

    private let statusIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private let nameLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.numberOfLines = 1
        return label
    }()

    private let severityBadge: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        label.layer.cornerRadius = 4
        label.clipsToBounds = true
        label.textColor = .white
        return label
    }()

    private let messageLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .regular)
        label.textColor = .secondaryLabel
        label.numberOfLines = 2
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
        contentView.addSubview(statusIcon)
        contentView.addSubview(nameLabel)
        contentView.addSubview(severityBadge)
        contentView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            statusIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            statusIcon.widthAnchor.constraint(equalToConstant: 24),
            statusIcon.heightAnchor.constraint(equalToConstant: 24),

            nameLabel.leadingAnchor.constraint(equalTo: statusIcon.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),

            severityBadge.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            severityBadge.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            severityBadge.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            severityBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),
            severityBadge.heightAnchor.constraint(equalToConstant: 20),

            messageLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            messageLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),
            messageLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            messageLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
        ])

        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        severityBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    func configure(rule: InspectionRule, result: RuleResult) {
        nameLabel.text = rule.name
        messageLabel.text = result.message

        // Status icon
        if result.passed {
            statusIcon.image = UIImage(systemName: "checkmark.circle.fill")
            statusIcon.tintColor = Constants.Colors.successColor
            accessoryType = .none
        } else {
            statusIcon.image = UIImage(systemName: "xmark.circle.fill")
            statusIcon.tintColor = Constants.Colors.errorColor
            accessoryType = result.details.isEmpty ? .none : .disclosureIndicator
        }

        // Severity badge
        severityBadge.text = " \(rule.severity.displayName) "
        severityBadge.backgroundColor = colorForSeverity(rule.severity)

        // Accessibility
        isAccessibilityElement = true
        accessibilityLabel = "\(result.passed ? "Passed" : "Failed"): \(rule.name), \(rule.severity.displayName) severity. \(result.message)"
        if !result.passed && !result.details.isEmpty {
            accessibilityHint = "Double tap for details"
        }
    }

    private func colorForSeverity(_ severity: RuleSeverity) -> UIColor {
        switch severity {
        case .critical: return Constants.Colors.errorColor
        case .high:     return Constants.Colors.warningColor
        case .medium:   return UIColor.systemYellow
        case .low:      return UIColor.systemTeal
        case .info:     return UIColor.systemGray
        }
    }
}

// MARK: - Rule Detail View Controller

private final class InspectionRuleDetailViewController: UITableViewController {

    private let rule: InspectionRule
    private let result: RuleResult

    init(rule: InspectionRule, result: RuleResult) {
        self.rule = rule
        self.result = result
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = rule.name
        view.backgroundColor = Constants.Colors.primaryBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "DetailCell")
    }

    // Section 0: Rule info, Section 1: Details
    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return section == 0 ? "Rule Information" : "Details"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return section == 0 ? 4 : result.details.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "DetailCell", for: indexPath)
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.font = .systemFont(ofSize: 14)

        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = "ID: \(rule.id)"
            case 1:
                cell.textLabel?.text = "Category: \(rule.category.rawValue)"
            case 2:
                cell.textLabel?.text = "Severity: \(rule.severity.displayName)"
            case 3:
                cell.textLabel?.text = rule.description
                cell.textLabel?.textColor = .secondaryLabel
            default:
                break
            }
        } else {
            cell.textLabel?.text = result.details[indexPath.row]
            cell.textLabel?.textColor = .secondaryLabel
        }
        return cell
    }
}
