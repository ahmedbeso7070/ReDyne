import UIKit

class SecurityPostureViewController: UITableViewController {

    // MARK: - Types

    private enum Section: Int, CaseIterable {
        case summary
        case findings
        case dangerousAPIs
        case insecureFunctions
        case dangerousEntitlements
    }

    // MARK: - Properties

    private let posture: SecurityPosture

    // MARK: - Initialization

    init(posture: SecurityPosture) {
        self.posture = posture
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Security Posture"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SummaryCell")
    }

    // MARK: - Table View Data Source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sec = Section(rawValue: section) else { return nil }
        switch sec {
        case .summary: return "Overall Assessment"
        case .findings: return "Protection Indicators"
        case .dangerousAPIs: return posture.hasDangerousAPIs ? "Dangerous APIs (\(posture.dangerousAPIs.count))" : nil
        case .insecureFunctions: return posture.hasInsecureFunctions ? "Insecure Functions (\(posture.insecureFunctions.count))" : nil
        case .dangerousEntitlements: return posture.hasDangerousEntitlements ? "Dangerous Entitlements (\(posture.dangerousEntitlements.count))" : nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sec = Section(rawValue: section) else { return 0 }
        switch sec {
        case .summary: return 1
        case .findings: return posture.findings.count
        case .dangerousAPIs: return posture.dangerousAPIs.count
        case .insecureFunctions: return posture.insecureFunctions.count
        case .dangerousEntitlements: return posture.dangerousEntitlements.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let sec = Section(rawValue: indexPath.section) else {
            return UITableViewCell()
        }

        switch sec {
        case .summary:
            let cell = tableView.dequeueReusableCell(withIdentifier: "SummaryCell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = "Security Posture: \(posture.postureSummary)"
            content.secondaryText = "\(posture.criticalCount) critical, \(posture.highCount) high, \(posture.mediumCount) medium, \(posture.lowCount) low"
            content.textProperties.font = .systemFont(ofSize: 18, weight: .bold)
            content.secondaryTextProperties.font = .systemFont(ofSize: 14)

            let color: UIColor
            switch posture.postureSummary {
            case "Good": color = .systemGreen
            case "Fair": color = .systemYellow
            case "Concerning": color = .systemOrange
            case "Poor": color = .systemRed
            default: color = .label
            }
            content.textProperties.color = color
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = "Security Posture: \(posture.postureSummary). \(posture.criticalCount) critical, \(posture.highCount) high, \(posture.mediumCount) medium, \(posture.lowCount) low"
            cell.accessibilityTraits = .staticText
            return cell

        case .findings:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let finding = posture.findings[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = finding.name
            content.secondaryText = "\(finding.statusString) - \(finding.detail)"
            content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
            content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            content.secondaryTextProperties.numberOfLines = 3

            let statusColor: UIColor
            switch finding.severity {
            case .critical: statusColor = .systemRed
            case .high: statusColor = .systemOrange
            case .medium: statusColor = .systemYellow
            case .low: statusColor = .secondaryLabel
            case .info: statusColor = .systemGreen
            @unknown default: statusColor = .label
            }
            content.image = UIImage(systemName: finding.status == .present ? "checkmark.circle.fill" : "xmark.circle.fill")
            content.imageProperties.tintColor = statusColor
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = "\(finding.name): \(finding.statusString). \(finding.detail)"
            cell.accessibilityTraits = .staticText
            return cell

        case .dangerousAPIs:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let api = posture.dangerousAPIs[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = api.functionName
            content.secondaryText = api.riskDescription
            content.textProperties.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            content.image = UIImage(systemName: "exclamationmark.triangle.fill")
            content.imageProperties.tintColor = .systemOrange
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = "Dangerous API: \(api.functionName). \(api.riskDescription)"
            cell.accessibilityTraits = .staticText
            return cell

        case .insecureFunctions:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            let func_ = posture.insecureFunctions[indexPath.row]
            var content = cell.defaultContentConfiguration()
            content.text = func_.functionName
            content.secondaryText = func_.riskDescription
            content.textProperties.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            content.image = UIImage(systemName: "exclamationmark.circle.fill")
            content.imageProperties.tintColor = .systemYellow
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = "Insecure function: \(func_.functionName). \(func_.riskDescription)"
            cell.accessibilityTraits = .staticText
            return cell

        case .dangerousEntitlements:
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = posture.dangerousEntitlements[indexPath.row]
            content.textProperties.font = .systemFont(ofSize: 14)
            content.image = UIImage(systemName: "key.fill")
            content.imageProperties.tintColor = .systemRed
            cell.contentConfiguration = content
            cell.isAccessibilityElement = true
            cell.accessibilityLabel = "Dangerous entitlement: \(posture.dangerousEntitlements[indexPath.row])"
            cell.accessibilityTraits = .staticText
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}
