import Foundation

// MARK: - Rule Types

enum RuleSeverity: String, Codable {
    case critical, high, medium, low, info

    var displayName: String {
        return rawValue.capitalized
    }
}

enum RuleCategory: String, CaseIterable {
    case security = "Security"
    case quality = "Code Quality"
    case compatibility = "Compatibility"
    case performance = "Performance"
}

struct InspectionRule {
    let id: String
    let name: String
    let description: String
    let category: RuleCategory
    let severity: RuleSeverity
    let evaluate: (DecompiledOutput) -> RuleResult
}

struct RuleResult {
    let passed: Bool
    let message: String
    let details: [String]
}

struct InspectionReport {
    let results: [(rule: InspectionRule, result: RuleResult)]
    let passCount: Int
    let failCount: Int
    let timestamp: Date
}

// MARK: - Rule Engine

final class InspectionRuleEngine {

    static let shared = InspectionRuleEngine()

    private init() {}

    // MARK: - Cached Rules

    private lazy var cachedAllRules: [InspectionRule] = {
        return securityRules() + qualityRules() + compatibilityRules() + performanceRules()
    }()

    // MARK: - Run All Rules

    func evaluate(output: DecompiledOutput) -> InspectionReport {
        let rules = cachedAllRules
        var results = [(rule: InspectionRule, result: RuleResult)]()
        var passCount = 0
        var failCount = 0

        for rule in rules {
            let result = rule.evaluate(output)
            results.append((rule: rule, result: result))
            if result.passed {
                passCount += 1
            } else {
                failCount += 1
            }
        }

        return InspectionReport(
            results: results,
            passCount: passCount,
            failCount: failCount,
            timestamp: Date()
        )
    }

    // MARK: - Built-in Rules

    func allRules() -> [InspectionRule] {
        return securityRules() + qualityRules() + compatibilityRules() + performanceRules()
    }

    // MARK: - Security Rules

    private func securityRules() -> [InspectionRule] {
        return [
            // 1. PIE enabled
            InspectionRule(
                id: "SEC-001",
                name: "PIE Enabled",
                description: "Position Independent Executable should be enabled for ASLR support.",
                category: .security,
                severity: .critical
            ) { output in
                let enabled = output.header.isPIE
                return RuleResult(
                    passed: enabled,
                    message: enabled ? "PIE is enabled." : "PIE is NOT enabled. ASLR will not protect this binary.",
                    details: enabled ? [] : [
                        "The MH_PIE flag is not set in the Mach-O header.",
                        "Without PIE, the binary loads at a fixed address, making exploits easier.",
                        "Recompile with position-independent code enabled."
                    ]
                )
            },

            // 2. ARC usage
            InspectionRule(
                id: "SEC-002",
                name: "ARC Usage",
                description: "Automatic Reference Counting should be used to prevent memory management vulnerabilities.",
                category: .security,
                severity: .high
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let hasARCSymbols = symbols.contains { sym in
                    let name = sym.name
                    return name.contains("objc_release") ||
                           name.contains("objc_retain") ||
                           name.contains("objc_storeStrong") ||
                           name.contains("objc_autoreleaseReturnValue")
                }
                return RuleResult(
                    passed: hasARCSymbols,
                    message: hasARCSymbols ? "ARC runtime symbols detected." : "No ARC runtime symbols found. Manual memory management may be in use.",
                    details: hasARCSymbols ? [] : [
                        "Automatic Reference Counting (ARC) symbols were not found.",
                        "Manual retain/release is error-prone and can lead to use-after-free bugs.",
                        "Consider migrating to ARC if this is an Objective-C binary."
                    ]
                )
            },

            // 3. Stack canaries
            InspectionRule(
                id: "SEC-003",
                name: "Stack Canaries",
                description: "Stack canaries should be present to detect buffer overflow attacks.",
                category: .security,
                severity: .high
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let hasCanaries = symbols.contains { sym in
                    sym.name.contains("__stack_chk_fail") || sym.name.contains("__stack_chk_guard")
                }
                return RuleResult(
                    passed: hasCanaries,
                    message: hasCanaries ? "Stack canary symbols found." : "No stack canary symbols detected.",
                    details: hasCanaries ? [] : [
                        "Stack canaries (stack protector) symbols were not found.",
                        "Without stack canaries, buffer overflows may go undetected.",
                        "Compile with -fstack-protector or -fstack-protector-all."
                    ]
                )
            },

            // 4. No dangerous APIs
            InspectionRule(
                id: "SEC-004",
                name: "No Dangerous APIs",
                description: "Binary should not use dangerous functions like system(), popen(), or exec*.",
                category: .security,
                severity: .critical
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let dangerousAPIs: Set<String> = ["_system", "_popen", "_execl", "_execle",
                                     "_execlp", "_execv", "_execve", "_execvp"]
                var found = [String]()
                for sym in symbols {
                    if dangerousAPIs.contains(sym.name) {
                        found.append(sym.name)
                    }
                }
                let unique = Array(Set(found))
                let passed = unique.isEmpty
                return RuleResult(
                    passed: passed,
                    message: passed ? "No dangerous command execution APIs found." : "Found \(unique.count) dangerous API(s).",
                    details: passed ? [] : unique.map { "Dangerous API referenced: \($0)" } + [
                        "These APIs can execute arbitrary commands and are a security risk.",
                        "Consider using safer alternatives or sandboxing."
                    ]
                )
            },

            // 5. No insecure functions
            InspectionRule(
                id: "SEC-005",
                name: "No Insecure Functions",
                description: "Binary should not use insecure C functions like gets, strcpy, sprintf.",
                category: .security,
                severity: .high
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let insecureFunctions: Set<String> = ["_gets", "_strcpy", "_sprintf", "_strcat",
                                         "_vsprintf", "_scanf", "_sscanf"]
                var found = [String]()
                for sym in symbols {
                    if insecureFunctions.contains(sym.name) {
                        found.append(sym.name)
                    }
                }
                let unique = Array(Set(found))
                let passed = unique.isEmpty
                return RuleResult(
                    passed: passed,
                    message: passed ? "No insecure C functions found." : "Found \(unique.count) insecure function(s).",
                    details: passed ? [] : unique.map { "Insecure function: \($0) (use bounded alternative)" } + [
                        "Replace gets -> fgets, strcpy -> strlcpy, sprintf -> snprintf.",
                        "These functions do not perform bounds checking."
                    ]
                )
            },

            // 6. Code signing present
            InspectionRule(
                id: "SEC-006",
                name: "Code Signing Present",
                description: "Binary should have a code signature for integrity verification.",
                category: .security,
                severity: .high
            ) { output in
                let hasSig = output.codeSigningAnalysis != nil
                return RuleResult(
                    passed: hasSig,
                    message: hasSig ? "Code signature data is present." : "No code signature found.",
                    details: hasSig ? [] : [
                        "The binary does not appear to have a code signature.",
                        "Code signing ensures binary integrity and authenticity.",
                        "Use codesign to sign the binary before distribution."
                    ]
                )
            },

            // 7. No get-task-allow entitlement
            InspectionRule(
                id: "SEC-007",
                name: "No get-task-allow Entitlement",
                description: "Release builds should not have the get-task-allow entitlement.",
                category: .security,
                severity: .medium
            ) { output in
                let strings = (output.strings as? [StringModel]) ?? []
                let hasGetTaskAllow = strings.contains { $0.content.contains("get-task-allow") }
                return RuleResult(
                    passed: !hasGetTaskAllow,
                    message: hasGetTaskAllow ? "get-task-allow entitlement found (debug build?)." : "No get-task-allow entitlement found.",
                    details: hasGetTaskAllow ? [
                        "The get-task-allow entitlement permits debugger attachment.",
                        "This entitlement should be removed for release/production builds.",
                        "It allows other processes to attach and inspect the running binary."
                    ] : []
                )
            },

            // 8. No private API entitlements
            InspectionRule(
                id: "SEC-008",
                name: "No Private API Entitlements",
                description: "Binary should not reference private Apple entitlements.",
                category: .security,
                severity: .medium
            ) { output in
                let strings = (output.strings as? [StringModel]) ?? []
                let privateEntitlementPrefixes = [
                    "com.apple.private.",
                    "com.apple.security.private.",
                    "com.apple.rootless."
                ]
                var found = [String]()
                for str in strings {
                    for prefix in privateEntitlementPrefixes {
                        if str.content.contains(prefix) {
                            found.append(str.content)
                            break
                        }
                    }
                }
                let unique = Array(Set(found))
                let passed = unique.isEmpty
                return RuleResult(
                    passed: passed,
                    message: passed ? "No private API entitlements detected." : "Found \(unique.count) private entitlement reference(s).",
                    details: passed ? [] : unique.prefix(10).map { "Private entitlement: \($0)" } + [
                        "Private entitlements are reserved for Apple system processes.",
                        "Apps using private entitlements will be rejected by App Store review."
                    ]
                )
            },

            // 9. Encryption enabled
            InspectionRule(
                id: "SEC-009",
                name: "Encryption Enabled",
                description: "Binary should have encryption enabled (App Store distribution).",
                category: .security,
                severity: .info
            ) { output in
                let encrypted = output.header.isEncrypted
                return RuleResult(
                    passed: encrypted,
                    message: encrypted ? "Binary encryption is enabled." : "Binary encryption is not enabled.",
                    details: encrypted ? [] : [
                        "The encryption_info load command indicates no active encryption.",
                        "App Store binaries are typically FairPlay encrypted.",
                        "This may be expected for development or sideloaded builds."
                    ]
                )
            }
        ]
    }

    // MARK: - Quality Rules

    private func qualityRules() -> [InspectionRule] {
        return [
            // 10. No duplicate symbol names
            InspectionRule(
                id: "QUA-001",
                name: "No Duplicate Symbols",
                description: "Binary should not have duplicate defined symbol names.",
                category: .quality,
                severity: .medium
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let definedNames = symbols.filter { $0.isDefined }.map { $0.name }
                var seen = Set<String>()
                var duplicates = Set<String>()
                for name in definedNames {
                    if seen.contains(name) {
                        duplicates.insert(name)
                    }
                    seen.insert(name)
                }
                let passed = duplicates.isEmpty
                return RuleResult(
                    passed: passed,
                    message: passed ? "No duplicate symbol names found." : "Found \(duplicates.count) duplicate symbol name(s).",
                    details: passed ? [] : Array(duplicates.prefix(10)).map { "Duplicate: \($0)" } + (
                        duplicates.count > 10 ? ["... and \(duplicates.count - 10) more."] : []
                    )
                )
            },

            // 11. Symbol count within reasonable range
            InspectionRule(
                id: "QUA-002",
                name: "Symbols Not Stripped",
                description: "Binary should have symbols (not fully stripped) for debuggability.",
                category: .quality,
                severity: .low
            ) { output in
                let count = output.totalSymbols
                let passed = count > 0
                return RuleResult(
                    passed: passed,
                    message: passed ? "Binary contains \(count) symbol(s)." : "Binary appears fully stripped (0 symbols).",
                    details: passed ? [] : [
                        "The symbol table is empty, suggesting the binary was fully stripped.",
                        "This makes debugging and crash symbolication impossible.",
                        "Consider shipping a dSYM alongside stripped release builds."
                    ]
                )
            },

            // 12. Has valid UUID
            InspectionRule(
                id: "QUA-003",
                name: "Valid UUID Present",
                description: "Binary should have a UUID for crash report symbolication.",
                category: .quality,
                severity: .medium
            ) { output in
                let uuid = output.header.uuid
                let hasUUID = uuid != nil && !(uuid?.isEmpty ?? true)
                return RuleResult(
                    passed: hasUUID,
                    message: hasUUID ? "UUID: \(uuid ?? "")" : "No UUID found in the binary.",
                    details: hasUUID ? [] : [
                        "A UUID is required to match crash reports to dSYM files.",
                        "Without a UUID, crash symbolication will not work.",
                        "Ensure the binary is compiled with standard build settings."
                    ]
                )
            },

            // 13. Reasonable string-to-code ratio
            InspectionRule(
                id: "QUA-004",
                name: "Reasonable String-to-Code Ratio",
                description: "The ratio of strings to instructions should be reasonable.",
                category: .quality,
                severity: .info
            ) { output in
                let stringCount = output.totalStrings
                let instrCount = output.totalInstructions
                guard instrCount > 0 else {
                    return RuleResult(passed: true, message: "No instructions to compare.", details: [])
                }
                let ratio = Double(stringCount) / Double(instrCount)
                // A ratio above 5.0 is suspicious (e.g. resource-heavy binary with minimal code)
                let passed = ratio < 5.0
                let ratioStr = String(format: "%.2f", ratio)
                return RuleResult(
                    passed: passed,
                    message: passed ? "String-to-code ratio is \(ratioStr) (acceptable)." : "String-to-code ratio is \(ratioStr) (unusually high).",
                    details: passed ? [] : [
                        "\(stringCount) strings vs \(instrCount) instructions.",
                        "A very high ratio may indicate embedded resources or data-heavy binary.",
                        "This is informational and may not indicate an actual problem."
                    ]
                )
            }
        ]
    }

    // MARK: - Compatibility Rules

    private func compatibilityRules() -> [InspectionRule] {
        return [
            // 14. Minimum deployment target
            InspectionRule(
                id: "CMP-001",
                name: "Minimum Deployment Target (iOS 13+)",
                description: "Binary should target at least iOS 13 for modern API support.",
                category: .compatibility,
                severity: .medium
            ) { output in
                guard let minVersion = output.header.minVersion, !minVersion.isEmpty else {
                    return RuleResult(
                        passed: true,
                        message: "No minimum version info available.",
                        details: ["Could not determine the deployment target from the binary."]
                    )
                }
                // Parse version string like "13.0" or "14.0.0"
                let components = minVersion.split(separator: ".").compactMap { Int($0) }
                let major = components.first ?? 0
                let passed = major >= 13
                return RuleResult(
                    passed: passed,
                    message: passed ? "Minimum deployment target: \(minVersion) (iOS 13+ OK)." : "Minimum deployment target: \(minVersion) (below iOS 13).",
                    details: passed ? [] : [
                        "The binary targets iOS \(minVersion), which is below iOS 13.",
                        "iOS 13 is the minimum recommended target for modern SwiftUI/Combine support.",
                        "Consider raising the deployment target."
                    ]
                )
            },

            // 15. 64-bit binary
            InspectionRule(
                id: "CMP-002",
                name: "64-Bit Binary",
                description: "Binary must be 64-bit. 32-bit binaries are no longer supported on iOS.",
                category: .compatibility,
                severity: .critical
            ) { output in
                let is64 = output.header.is64Bit
                return RuleResult(
                    passed: is64,
                    message: is64 ? "Binary is 64-bit." : "Binary is 32-bit.",
                    details: is64 ? [] : [
                        "32-bit binaries are not supported on iOS 11 and later.",
                        "The App Store requires 64-bit support.",
                        "Recompile for arm64 architecture."
                    ]
                )
            },

            // 16. No deprecated load commands
            InspectionRule(
                id: "CMP-003",
                name: "No Deprecated Load Commands",
                description: "Binary should not contain deprecated Mach-O load commands.",
                category: .compatibility,
                severity: .low
            ) { output in
                let strings = (output.strings as? [StringModel]) ?? []
                let sections = (output.sections as? [SectionModel]) ?? []
                // Check for __OBJC segment (legacy ObjC runtime, pre-64bit)
                let hasLegacyObjC = sections.contains { $0.segmentName == "__OBJC" }
                // Check for mentions of deprecated commands in flagsDescription
                let flagsDesc = output.header.flagsDescription ?? ""
                let hasDeprecatedFlags = flagsDesc.contains("LAZY_INIT") || flagsDesc.contains("NO_HEAP_EXECUTION")
                let passed = !hasLegacyObjC && !hasDeprecatedFlags
                var details = [String]()
                if hasLegacyObjC {
                    details.append("Legacy __OBJC segment found (deprecated ObjC runtime).")
                }
                if hasDeprecatedFlags {
                    details.append("Deprecated Mach-O flags detected in header.")
                }
                return RuleResult(
                    passed: passed,
                    message: passed ? "No deprecated load commands detected." : "Deprecated load commands or segments found.",
                    details: details
                )
            }
        ]
    }

    // MARK: - Performance Rules

    private func performanceRules() -> [InspectionRule] {
        return [
            // 17. Binary size
            InspectionRule(
                id: "PRF-001",
                name: "Reasonable Binary Size",
                description: "Binary size should be under 500 MB.",
                category: .performance,
                severity: .medium
            ) { output in
                let sizeBytes = output.fileSize
                let sizeMB = Double(sizeBytes) / (1024.0 * 1024.0)
                let passed = sizeMB < 500.0
                let sizeStr = String(format: "%.1f MB", sizeMB)
                return RuleResult(
                    passed: passed,
                    message: passed ? "Binary size is \(sizeStr) (within limit)." : "Binary size is \(sizeStr) (exceeds 500 MB).",
                    details: passed ? [] : [
                        "Large binaries increase download times and storage usage.",
                        "Consider stripping debug symbols for release builds.",
                        "Review for embedded assets that could be downloaded on demand."
                    ]
                )
            },

            // 18. Not too many ObjC categories
            InspectionRule(
                id: "PRF-002",
                name: "ObjC Category Count",
                description: "Excessive ObjC categories may indicate heavy method swizzling.",
                category: .performance,
                severity: .low
            ) { output in
                let symbols = (output.symbols as? [SymbolModel]) ?? []
                let categorySymbols = symbols.filter { sym in
                    sym.name.contains("(") && sym.name.contains(")") && sym.name.hasPrefix("_OBJC_$_CATEGORY_")
                }
                let count = categorySymbols.count
                // More than 200 categories is a lot
                let passed = count < 200
                return RuleResult(
                    passed: passed,
                    message: passed ? "Found \(count) ObjC category symbol(s) (acceptable)." : "Found \(count) ObjC category symbols (high count).",
                    details: passed ? [] : [
                        "\(count) ObjC categories detected via symbol names.",
                        "Excessive categories can slow app launch due to category loading.",
                        "Review whether all categories are necessary."
                    ]
                )
            }
        ]
    }
}
