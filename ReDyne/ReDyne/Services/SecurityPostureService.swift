import Foundation

// MARK: - Security Status Enum

@objc enum SecurityIndicatorStatus: Int {
    case present = 0        // Protection is present (good)
    case absent             // Protection is absent (concerning)
    case uncertain          // Cannot determine
    case notApplicable      // Does not apply to this binary type

    var displayString: String {
        switch self {
        case .present:       return "Present"
        case .absent:        return "Absent"
        case .uncertain:     return "Uncertain"
        case .notApplicable: return "N/A"
        }
    }
}

// MARK: - Security Severity Enum

@objc enum SecurityFindingSeverity: Int {
    case info = 0
    case low
    case medium
    case high
    case critical

    var displayString: String {
        switch self {
        case .info:     return "Info"
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }
}

// MARK: - Security Finding Info

@objc class SecurityFindingInfo: NSObject {
    @objc let name: String
    @objc let findingDescription: String
    @objc let status: SecurityIndicatorStatus
    @objc let severity: SecurityFindingSeverity
    @objc let detail: String

    init(name: String, description: String, status: SecurityIndicatorStatus,
         severity: SecurityFindingSeverity, detail: String) {
        self.name = name
        self.findingDescription = description
        self.status = status
        self.severity = severity
        self.detail = detail
        super.init()
    }

    @objc var statusString: String { status.displayString }
    @objc var severityString: String { severity.displayString }
}

// MARK: - Dangerous API Info

@objc class DangerousAPIInfo: NSObject {
    @objc let functionName: String
    @objc let riskDescription: String
    @objc let severity: SecurityFindingSeverity
    @objc let isImported: Bool

    init(functionName: String, riskDescription: String,
         severity: SecurityFindingSeverity, isImported: Bool) {
        self.functionName = functionName
        self.riskDescription = riskDescription
        self.severity = severity
        self.isImported = isImported
        super.init()
    }

    @objc var severityString: String { severity.displayString }
}

// MARK: - Security Posture

@objc class SecurityPosture: NSObject {
    @objc let findings: [SecurityFindingInfo]
    @objc let dangerousAPIs: [DangerousAPIInfo]
    @objc let insecureFunctions: [DangerousAPIInfo]
    @objc let dangerousEntitlements: [String]
    @objc let postureSummary: String
    @objc let postureDetail: String

    @objc let criticalCount: Int
    @objc let highCount: Int
    @objc let mediumCount: Int
    @objc let lowCount: Int
    @objc let infoCount: Int
    @objc let totalFindings: Int

    init(findings: [SecurityFindingInfo],
         dangerousAPIs: [DangerousAPIInfo],
         insecureFunctions: [DangerousAPIInfo],
         dangerousEntitlements: [String],
         postureSummary: String,
         postureDetail: String,
         criticalCount: Int,
         highCount: Int,
         mediumCount: Int,
         lowCount: Int,
         infoCount: Int,
         totalFindings: Int) {
        self.findings = findings
        self.dangerousAPIs = dangerousAPIs
        self.insecureFunctions = insecureFunctions
        self.dangerousEntitlements = dangerousEntitlements
        self.postureSummary = postureSummary
        self.postureDetail = postureDetail
        self.criticalCount = criticalCount
        self.highCount = highCount
        self.mediumCount = mediumCount
        self.lowCount = lowCount
        self.infoCount = infoCount
        self.totalFindings = totalFindings
        super.init()
    }

    @objc var hasDangerousEntitlements: Bool {
        return !dangerousEntitlements.isEmpty
    }

    @objc var hasDangerousAPIs: Bool {
        return !dangerousAPIs.isEmpty
    }

    @objc var hasInsecureFunctions: Bool {
        return !insecureFunctions.isEmpty
    }
}

// MARK: - Security Posture Service

@objc class SecurityPostureService: NSObject {

    // MARK: - Public API

    @objc static func analyze(binaryPath: String) -> SecurityPosture? {
        // Open the Mach-O file
        var errorMsg = [CChar](repeating: 0, count: 256)
        guard let machoCtx = macho_open(binaryPath, &errorMsg) else {
            print("SecurityPostureService: Failed to open binary - \(String(cString: errorMsg))")
            return nil
        }
        defer { macho_close(machoCtx) }

        // Parse header
        guard macho_parse_header(machoCtx) else {
            print("SecurityPostureService: Failed to parse Mach-O header")
            return nil
        }

        // Parse load commands
        guard macho_parse_load_commands(machoCtx) else {
            print("SecurityPostureService: Failed to parse load commands")
            return nil
        }

        // Extract segments (needed for __RESTRICT detection)
        macho_extract_segments(machoCtx)

        // Create symbol table context
        let symCtx = symbol_table_create(machoCtx)
        defer {
            if let ctx = symCtx {
                symbol_table_free(ctx)
            }
        }
        if let ctx = symCtx {
            symbol_table_parse(ctx)
            symbol_table_categorize(ctx)
        }

        // Parse code signature
        let sigInfo = codesign_parse_signature(machoCtx)
        defer {
            if let info = sigInfo {
                codesign_free_signature(info)
            }
        }

        // Parse entitlements
        var entInfo: UnsafeMutablePointer<EntitlementsInfo>? = nil
        if let sig = sigInfo, sig.pointee.has_entitlements {
            entInfo = codesign_parse_entitlements(machoCtx)
        }
        defer {
            if let info = entInfo {
                codesign_free_entitlements(info)
            }
        }

        // Run security analysis
        guard let result = security_analyze(machoCtx, symCtx, sigInfo, entInfo) else {
            print("SecurityPostureService: security_analyze returned nil")
            return nil
        }
        defer { security_free_result(result) }

        // Convert C result to Swift models
        return convertResult(result.pointee)
    }

    // MARK: - Private Conversion Helpers

    private static func convertResult(_ result: SecurityAnalysisResult) -> SecurityPosture {
        // Convert binary protection findings
        let findings: [SecurityFindingInfo] = [
            convertFinding(result.pie),
            convertFinding(result.arc),
            convertFinding(result.stack_canaries),
            convertFinding(result.nx_heap),
            convertFinding(result.nx_stack),
            convertFinding(result.code_signing),
            convertFinding(result.encryption),
            convertFinding(result.restrict_segment),
        ]

        // Convert dangerous APIs
        var dangerousAPIs: [DangerousAPIInfo] = []
        if let apis = result.dangerous_apis {
            for i in 0..<Int(result.dangerous_api_count) {
                dangerousAPIs.append(convertAPIEntry(apis[i]))
            }
        }

        // Convert insecure functions
        var insecureFunctions: [DangerousAPIInfo] = []
        if let funcs = result.insecure_functions {
            for i in 0..<Int(result.insecure_function_count) {
                insecureFunctions.append(convertAPIEntry(funcs[i]))
            }
        }

        // Convert dangerous entitlements
        var dangerousEntitlements: [String] = []
        for i in 0..<Int(result.dangerous_entitlement_count) {
            var entitlement = result.dangerous_entitlements
            let entString = withUnsafePointer(to: &entitlement) { ptr -> String in
                let base = UnsafeRawPointer(ptr)
                    .assumingMemoryBound(to: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8,
                                               Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8).self)
                // Each entitlement is 256 bytes; offset to i-th entry
                let entPtr = UnsafeRawPointer(base).advanced(by: i * 256)
                    .assumingMemoryBound(to: CChar.self)
                return String(cString: entPtr)
            }
            if !entString.isEmpty {
                dangerousEntitlements.append(entString)
            }
        }

        // Extract posture summary and detail strings
        var summaryCopy = result.posture_summary
        let postureSummary = withUnsafePointer(to: &summaryCopy.0) { String(cString: $0) }

        var detailCopy = result.posture_detail
        let postureDetail = withUnsafePointer(to: &detailCopy.0) { String(cString: $0) }

        return SecurityPosture(
            findings: findings,
            dangerousAPIs: dangerousAPIs,
            insecureFunctions: insecureFunctions,
            dangerousEntitlements: dangerousEntitlements,
            postureSummary: postureSummary,
            postureDetail: postureDetail,
            criticalCount: Int(result.critical_count),
            highCount: Int(result.high_count),
            mediumCount: Int(result.medium_count),
            lowCount: Int(result.low_count),
            infoCount: Int(result.info_count),
            totalFindings: Int(result.total_findings)
        )
    }

    private static func convertFinding(_ finding: SecurityFinding) -> SecurityFindingInfo {
        var nameCopy = finding.name
        let name = withUnsafePointer(to: &nameCopy.0) { String(cString: $0) }

        var descCopy = finding.description
        let desc = withUnsafePointer(to: &descCopy.0) { String(cString: $0) }

        var detailCopy = finding.detail
        let detail = withUnsafePointer(to: &detailCopy.0) { String(cString: $0) }

        let status: SecurityIndicatorStatus
        switch finding.status {
        case SECURITY_STATUS_PRESENT:        status = .present
        case SECURITY_STATUS_ABSENT:         status = .absent
        case SECURITY_STATUS_UNCERTAIN:      status = .uncertain
        case SECURITY_STATUS_NOT_APPLICABLE: status = .notApplicable
        default:                             status = .uncertain
        }

        let severity: SecurityFindingSeverity
        switch finding.severity {
        case SECURITY_SEVERITY_INFO:     severity = .info
        case SECURITY_SEVERITY_LOW:      severity = .low
        case SECURITY_SEVERITY_MEDIUM:   severity = .medium
        case SECURITY_SEVERITY_HIGH:     severity = .high
        case SECURITY_SEVERITY_CRITICAL: severity = .critical
        default:                         severity = .info
        }

        return SecurityFindingInfo(
            name: name,
            description: desc,
            status: status,
            severity: severity,
            detail: detail
        )
    }

    private static func convertAPIEntry(_ entry: DangerousAPIEntry) -> DangerousAPIInfo {
        var funcNameCopy = entry.function_name
        let funcName = withUnsafePointer(to: &funcNameCopy.0) { String(cString: $0) }

        var riskCopy = entry.risk_description
        let riskDesc = withUnsafePointer(to: &riskCopy.0) { String(cString: $0) }

        let severity: SecurityFindingSeverity
        switch entry.severity {
        case SECURITY_SEVERITY_INFO:     severity = .info
        case SECURITY_SEVERITY_LOW:      severity = .low
        case SECURITY_SEVERITY_MEDIUM:   severity = .medium
        case SECURITY_SEVERITY_HIGH:     severity = .high
        case SECURITY_SEVERITY_CRITICAL: severity = .critical
        default:                         severity = .info
        }

        return DangerousAPIInfo(
            functionName: funcName,
            riskDescription: riskDesc,
            severity: severity,
            isImported: entry.is_imported
        )
    }
}
