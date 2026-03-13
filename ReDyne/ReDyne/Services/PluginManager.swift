import UIKit

// MARK: - Plugin Category

enum PluginCategory: String, CaseIterable {
    case security = "Security"
    case analysis = "Analysis"
    case format = "Format"
    case export = "Export"
    case custom = "Custom"

    var icon: String {
        switch self {
        case .security: return "shield.lefthalf.filled"
        case .analysis: return "waveform.path.ecg"
        case .format: return "doc.richtext"
        case .export: return "square.and.arrow.up"
        case .custom: return "puzzlepiece.extension"
        }
    }
}

// MARK: - Plugin Result Types

struct PluginResult {
    let pluginID: String
    let title: String
    let summary: String
    let findings: [PluginFinding]
    let metadata: [String: String]
    let generatedAt: Date
}

struct PluginFinding {
    let title: String
    let detail: String
    let severity: FindingSeverity
    let address: UInt64?
    let relatedSymbol: String?

    enum FindingSeverity: String, CaseIterable, Comparable {
        case critical
        case high
        case medium
        case low
        case info

        var displayName: String { rawValue.capitalized }

        var color: UIColor {
            switch self {
            case .critical: return .systemRed
            case .high: return .systemOrange
            case .medium: return .systemYellow
            case .low: return .systemBlue
            case .info: return .systemGray
            }
        }

        var icon: String {
            switch self {
            case .critical: return "exclamationmark.octagon.fill"
            case .high: return "exclamationmark.triangle.fill"
            case .medium: return "exclamationmark.circle.fill"
            case .low: return "info.circle.fill"
            case .info: return "text.bubble"
            }
        }

        private var sortOrder: Int {
            switch self {
            case .critical: return 0
            case .high: return 1
            case .medium: return 2
            case .low: return 3
            case .info: return 4
            }
        }

        static func < (lhs: FindingSeverity, rhs: FindingSeverity) -> Bool {
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

// MARK: - Analysis Plugin Protocol

protocol AnalysisPlugin: AnyObject {
    var pluginID: String { get }
    var name: String { get }
    var description: String { get }
    var version: String { get }
    var author: String { get }
    var icon: String { get }
    var category: PluginCategory { get }

    /// Runs the plugin analysis on the given decompiled output.
    func analyze(output: DecompiledOutput, binaryPath: String?) -> PluginResult

    /// Optionally provides a custom view controller for displaying results.
    func resultViewController(for result: PluginResult) -> UIViewController?
}

extension AnalysisPlugin {
    func resultViewController(for result: PluginResult) -> UIViewController? {
        return nil
    }
}

// MARK: - Plugin Manager

class PluginManager {
    static let shared = PluginManager()

    private var registeredPlugins: [String: AnalysisPlugin] = [:]
    private var pluginResults: [String: PluginResult] = [:]

    private init() {
        registerBuiltInPlugins()
    }

    // MARK: - Registration

    func register(plugin: AnalysisPlugin) {
        registeredPlugins[plugin.pluginID] = plugin
    }

    func unregister(pluginID: String) {
        registeredPlugins.removeValue(forKey: pluginID)
        pluginResults.removeValue(forKey: pluginID)
    }

    // MARK: - Queries

    var plugins: [AnalysisPlugin] {
        return Array(registeredPlugins.values).sorted { $0.name < $1.name }
    }

    func plugins(for category: PluginCategory) -> [AnalysisPlugin] {
        return plugins.filter { $0.category == category }
    }

    func plugin(for pluginID: String) -> AnalysisPlugin? {
        return registeredPlugins[pluginID]
    }

    // MARK: - Execution

    @discardableResult
    func runPlugin(_ pluginID: String, output: DecompiledOutput, binaryPath: String?) -> PluginResult? {
        guard let plugin = registeredPlugins[pluginID] else { return nil }
        let result = plugin.analyze(output: output, binaryPath: binaryPath)
        pluginResults[pluginID] = result
        return result
    }

    func runAllPlugins(output: DecompiledOutput, binaryPath: String?) {
        for (pluginID, plugin) in registeredPlugins {
            let result = plugin.analyze(output: output, binaryPath: binaryPath)
            pluginResults[pluginID] = result
        }
    }

    func result(for pluginID: String) -> PluginResult? {
        return pluginResults[pluginID]
    }

    func clearResults() {
        pluginResults.removeAll()
    }

    // MARK: - Built-in Plugins

    private func registerBuiltInPlugins() {
        register(plugin: EntrypointAnalysisPlugin())
        register(plugin: StringPatternPlugin())
        register(plugin: CryptoAPIDetectorPlugin())
        register(plugin: DeprecatedAPIDetectorPlugin())
    }
}

// MARK: - Built-in Plugin: Entrypoint Analysis

class EntrypointAnalysisPlugin: AnalysisPlugin {
    let pluginID = "com.redyne.plugin.entrypoint"
    let name = "Entrypoint Analysis"
    let description = "Analyzes the binary's entry point and reports which function is at the entry address."
    let version = "1.0.0"
    let author = "ReDyne"
    let icon = "arrow.right.to.line"
    let category: PluginCategory = .analysis

    func analyze(output: DecompiledOutput, binaryPath: String?) -> PluginResult {
        var findings: [PluginFinding] = []
        var metadata: [String: String] = [:]

        let header = output.header
        if header.hasEntryPoint, header.entryPointAddress != 0 {
            let entryAddr = header.entryPointAddress
            metadata["entryPointAddress"] = String(format: "0x%llX", entryAddr)

            // Find the function or symbol at this address
            var matchedFunctionName: String?

            if let functions = output.functions as? [FunctionModel] {
                for function in functions {
                    if function.startAddress <= entryAddr && entryAddr < function.endAddress {
                        matchedFunctionName = function.demangledName ?? function.name
                        break
                    }
                }
            }

            if matchedFunctionName == nil, let symbols = output.symbols as? [SymbolModel] {
                for symbol in symbols {
                    if symbol.address == entryAddr {
                        matchedFunctionName = symbol.demangledName ?? symbol.name
                        break
                    }
                }
            }

            if let funcName = matchedFunctionName {
                findings.append(PluginFinding(
                    title: "Entry Point Function Identified",
                    detail: "The binary entry point at \(String(format: "0x%llX", entryAddr)) maps to function: \(funcName)",
                    severity: .info,
                    address: entryAddr,
                    relatedSymbol: funcName
                ))
                metadata["entryFunction"] = funcName
            } else {
                findings.append(PluginFinding(
                    title: "Entry Point Without Named Function",
                    detail: "The entry point at \(String(format: "0x%llX", entryAddr)) does not map to any known named function. This may indicate a stripped binary.",
                    severity: .low,
                    address: entryAddr,
                    relatedSymbol: nil
                ))
            }

            // Check if entry point falls within a known segment
            if let segments = output.segments as? [SegmentModel] {
                for segment in segments {
                    if entryAddr >= segment.vmAddress && entryAddr < segment.vmAddress + segment.vmSize {
                        metadata["entrySegment"] = segment.name
                        findings.append(PluginFinding(
                            title: "Entry Point Segment",
                            detail: "Entry point resides in segment \(segment.name) (VM: \(String(format: "0x%llX", segment.vmAddress)) - \(String(format: "0x%llX", segment.vmAddress + segment.vmSize)))",
                            severity: .info,
                            address: entryAddr,
                            relatedSymbol: nil
                        ))
                        break
                    }
                }
            }
        } else {
            findings.append(PluginFinding(
                title: "No Entry Point",
                detail: "This binary does not have a declared entry point (LC_MAIN). It may be a dylib or framework.",
                severity: .info,
                address: nil,
                relatedSymbol: nil
            ))
        }

        return PluginResult(
            pluginID: pluginID,
            title: "Entrypoint Analysis",
            summary: findings.isEmpty ? "No entry point data available." : "\(findings.count) finding(s) about the binary entry point.",
            findings: findings,
            metadata: metadata,
            generatedAt: Date()
        )
    }
}

// MARK: - Built-in Plugin: String Pattern Scanner

class StringPatternPlugin: AnalysisPlugin {
    let pluginID = "com.redyne.plugin.stringpatterns"
    let name = "String Pattern Scanner"
    let description = "Scans extracted strings for interesting patterns: URLs, file paths, API key patterns, and email addresses."
    let version = "1.0.0"
    let author = "ReDyne"
    let icon = "text.magnifyingglass"
    let category: PluginCategory = .security

    private struct PatternDef {
        let name: String
        let regex: NSRegularExpression
        let severity: PluginFinding.FindingSeverity
    }

    private lazy var patterns: [PatternDef] = {
        var defs: [PatternDef] = []
        let specs: [(String, String, PluginFinding.FindingSeverity)] = [
            ("URL", "https?://[^\\s\"'<>]+", .info),
            ("File Path", "(/usr/|/var/|/tmp/|/etc/|/System/|/Library/|/private/)[^\\s\"']+", .low),
            ("Email Address", "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}", .low),
            ("API Key Pattern", "(?i)(api[_-]?key|apikey|api[_-]?secret|access[_-]?token|auth[_-]?token|bearer)\\s*[:=]\\s*[\"']?[A-Za-z0-9_\\-]{16,}[\"']?", .high),
            ("AWS Key Pattern", "AKIA[0-9A-Z]{16}", .critical),
            ("Private Key Reference", "(?i)(BEGIN\\s+(RSA\\s+)?PRIVATE\\s+KEY|-----BEGIN)", .critical),
            ("Hardcoded Password", "(?i)(password|passwd|pwd)\\s*[:=]\\s*[\"'][^\"']{4,}[\"']", .high),
            ("IP Address", "\\b\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\b", .low),
            ("Base64 Blob (long)", "[A-Za-z0-9+/]{40,}={0,2}", .info),
        ]
        for (name, pattern, severity) in specs {
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                defs.append(PatternDef(name: name, regex: regex, severity: severity))
            }
        }
        return defs
    }()

    func analyze(output: DecompiledOutput, binaryPath: String?) -> PluginResult {
        var findings: [PluginFinding] = []
        var categoryCounts: [String: Int] = [:]

        guard let strings = output.strings as? [StringModel] else {
            return PluginResult(
                pluginID: pluginID,
                title: "String Pattern Scan",
                summary: "No strings available for analysis.",
                findings: [],
                metadata: [:],
                generatedAt: Date()
            )
        }

        for stringModel in strings {
            let content = stringModel.content
            guard content.count >= 4 else { continue }
            let range = NSRange(content.startIndex..., in: content)

            for patternDef in patterns {
                let matches = patternDef.regex.matches(in: content, options: [], range: range)
                if !matches.isEmpty {
                    categoryCounts[patternDef.name, default: 0] += matches.count

                    // Limit per-pattern findings to avoid flooding
                    if (categoryCounts[patternDef.name] ?? 0) <= 25 {
                        let matchedText = matches.first.flatMap { result -> String? in
                            guard let swiftRange = Range(result.range, in: content) else { return nil }
                            let text = String(content[swiftRange])
                            return text.count > 120 ? String(text.prefix(120)) + "..." : text
                        } ?? content

                        findings.append(PluginFinding(
                            title: "\(patternDef.name) Found",
                            detail: matchedText,
                            severity: patternDef.severity,
                            address: stringModel.address,
                            relatedSymbol: nil
                        ))
                    }
                }
            }
        }

        // Build metadata summary
        var metadata: [String: String] = [:]
        metadata["totalStringsScanned"] = "\(strings.count)"
        for (category, count) in categoryCounts.sorted(by: { $0.key < $1.key }) {
            metadata["count_\(category)"] = "\(count)"
        }

        let totalFindings = categoryCounts.values.reduce(0, +)
        let summary: String
        if totalFindings == 0 {
            summary = "No notable patterns found in \(strings.count) strings."
        } else {
            let categories = categoryCounts.keys.sorted().joined(separator: ", ")
            summary = "\(totalFindings) pattern match(es) across \(categoryCounts.count) categories (\(categories)) in \(strings.count) strings."
        }

        return PluginResult(
            pluginID: pluginID,
            title: "String Pattern Scan",
            summary: summary,
            findings: findings.sorted { $0.severity < $1.severity },
            metadata: metadata,
            generatedAt: Date()
        )
    }
}

// MARK: - Built-in Plugin: Crypto API Detector

class CryptoAPIDetectorPlugin: AnalysisPlugin {
    let pluginID = "com.redyne.plugin.crypto-api"
    let name = "Cryptographic API Detector"
    let description = "Detects usage of cryptographic APIs and flags potentially weak or deprecated algorithms."
    let version = "1.0.0"
    let author = "ReDyne"
    let icon = "lock.shield"
    let category: PluginCategory = .security

    private let weakAPIs: [String: String] = [
        "_CC_MD5": "MD5 is cryptographically broken. Use SHA-256 or higher.",
        "_CC_SHA1": "SHA-1 has known collision attacks. Use SHA-256 or higher.",
        "_DES_ecb_encrypt": "DES uses 56-bit keys, trivially brute-forceable.",
        "_RC4": "RC4 has multiple known vulnerabilities.",
    ]

    private let strongAPIs = [
        "_CC_SHA256", "_CC_SHA384", "_CC_SHA512",
        "_CCCrypt", "_SecKeyCreateEncryptedData",
        "_SecKeyCreateDecryptedData"
    ]

    func analyze(output: DecompiledOutput, binaryPath: String?) -> PluginResult {
        var findings = [PluginFinding]()
        let symbols = (output.symbols as? [SymbolModel]) ?? []

        for symbol in symbols {
            if let warning = weakAPIs[symbol.name] {
                findings.append(PluginFinding(
                    title: "Weak Cryptographic API: \(symbol.name)",
                    detail: warning,
                    severity: .high,
                    address: symbol.address,
                    relatedSymbol: symbol.demangledName ?? symbol.name
                ))
            }
        }

        let hasStrongCrypto = symbols.contains { strongAPIs.contains($0.name) }
        if hasStrongCrypto && findings.isEmpty {
            findings.append(PluginFinding(
                title: "Strong Cryptographic APIs in Use",
                detail: "Binary uses modern cryptographic APIs.",
                severity: .info,
                address: nil,
                relatedSymbol: nil
            ))
        }

        return PluginResult(
            pluginID: pluginID,
            title: "Crypto API Analysis",
            summary: findings.isEmpty ? "No weak cryptographic APIs detected." : "\(findings.count) cryptographic finding(s).",
            findings: findings,
            metadata: [
                "weakAPIsFound": "\(findings.filter { $0.severity == .high }.count)",
                "strongAPIsDetected": "\(hasStrongCrypto)"
            ],
            generatedAt: Date()
        )
    }
}

// MARK: - Built-in Plugin: Deprecated API Detector

class DeprecatedAPIDetectorPlugin: AnalysisPlugin {
    let pluginID = "com.redyne.plugin.deprecated-api"
    let name = "Deprecated API Detector"
    let description = "Detects usage of deprecated Apple framework APIs that should be replaced with modern alternatives."
    let version = "1.0.0"
    let author = "ReDyne"
    let icon = "exclamationmark.triangle"
    let category: PluginCategory = .analysis

    private let deprecatedAPIs: [(pattern: String, replacement: String, severity: PluginFinding.FindingSeverity)] = [
        ("UIAlertView", "UIAlertController", .low),
        ("UIActionSheet", "UIAlertController", .low),
        ("UIWebView", "WKWebView", .medium),
        ("AddressBook", "Contacts framework", .low),
        ("UISearchDisplayController", "UISearchController", .low),
        ("MPMoviePlayerController", "AVPlayerViewController", .low),
        ("UIPopoverController", "UIPopoverPresentationController", .low),
    ]

    func analyze(output: DecompiledOutput, binaryPath: String?) -> PluginResult {
        var findings = [PluginFinding]()
        let symbols = (output.symbols as? [SymbolModel]) ?? []

        for symbol in symbols {
            for (pattern, replacement, severity) in deprecatedAPIs {
                if symbol.name.contains(pattern) {
                    findings.append(PluginFinding(
                        title: "Deprecated API: \(pattern)",
                        detail: "Replace with \(replacement). Symbol: \(symbol.demangledName ?? symbol.name)",
                        severity: severity,
                        address: symbol.address,
                        relatedSymbol: symbol.demangledName ?? symbol.name
                    ))
                    break
                }
            }
        }

        return PluginResult(
            pluginID: pluginID,
            title: "Deprecated API Scan",
            summary: findings.isEmpty ? "No deprecated APIs detected." : "\(findings.count) deprecated API(s) found.",
            findings: findings,
            metadata: ["deprecatedAPIsFound": "\(findings.count)"],
            generatedAt: Date()
        )
    }
}
