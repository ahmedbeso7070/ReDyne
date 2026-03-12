#ifndef SecurityAnalyzer_h
#define SecurityAnalyzer_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"
#include "SymbolTable.h"
#include "CodeSignature.h"

#pragma mark - Security Indicator Status

typedef enum {
    SECURITY_STATUS_PRESENT = 0,     // Protection is present (good)
    SECURITY_STATUS_ABSENT,          // Protection is absent (concerning)
    SECURITY_STATUS_UNCERTAIN,       // Cannot determine
    SECURITY_STATUS_NOT_APPLICABLE   // Does not apply to this binary type
} SecurityStatus;

typedef enum {
    SECURITY_SEVERITY_INFO = 0,
    SECURITY_SEVERITY_LOW,
    SECURITY_SEVERITY_MEDIUM,
    SECURITY_SEVERITY_HIGH,
    SECURITY_SEVERITY_CRITICAL
} SecuritySeverity;

#pragma mark - Individual Security Findings

typedef struct {
    char name[64];
    char description[256];
    SecurityStatus status;
    SecuritySeverity severity;
    char detail[512];
} SecurityFinding;

#pragma mark - Dangerous API Detection

typedef struct {
    char function_name[128];
    char risk_description[256];
    SecuritySeverity severity;
    bool is_imported;
} DangerousAPIEntry;

#pragma mark - Security Analysis Result

typedef struct {
    // Binary protection indicators
    SecurityFinding pie;
    SecurityFinding arc;
    SecurityFinding stack_canaries;
    SecurityFinding nx_heap;
    SecurityFinding nx_stack;
    SecurityFinding code_signing;
    SecurityFinding encryption;
    SecurityFinding restrict_segment;

    // Entitlements analysis
    bool has_dangerous_entitlements;
    int dangerous_entitlement_count;
    char dangerous_entitlements[20][256];

    // Dangerous API usage
    DangerousAPIEntry *dangerous_apis;
    int dangerous_api_count;

    // Insecure function usage
    DangerousAPIEntry *insecure_functions;
    int insecure_function_count;

    // Summary scores
    int total_findings;
    int critical_count;
    int high_count;
    int medium_count;
    int low_count;
    int info_count;

    // Overall posture
    char posture_summary[128];  // e.g., "Good", "Fair", "Concerning", "Poor"
    char posture_detail[1024];
} SecurityAnalysisResult;

#pragma mark - Public API

SecurityAnalysisResult* security_analyze(MachOContext *ctx, SymbolTableContext *sym_ctx, CodeSignatureInfo *sig_info, EntitlementsInfo *ent_info);

void security_free_result(SecurityAnalysisResult *result);

const char* security_status_string(SecurityStatus status);
const char* security_severity_string(SecuritySeverity severity);

#endif
