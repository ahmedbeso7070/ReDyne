#include "SecurityAnalyzer.h"
#include <stdlib.h>
#include <string.h>
#include <mach-o/loader.h>

#define MAX_DANGEROUS_APIS 1000
#define MAX_INSECURE_FUNCTIONS 1000

// MARK: - Helper: Safe String Copy

static void safe_strncpy(char *dst, const char *src, size_t size) {
    if (!dst || !src || size == 0) return;
    strncpy(dst, src, size - 1);
    dst[size - 1] = '\0';
}

// MARK: - Helper: Check If Symbol Exists

static bool symbol_exists(SymbolTableContext *sym_ctx, const char *name) {
    if (!sym_ctx || !name) return false;
    return symbol_table_find_by_name(sym_ctx, name) >= 0;
}

// MARK: - Helper: Check If Symbol Is Imported (Undefined)

static bool symbol_is_imported(SymbolTableContext *sym_ctx, const char *name) {
    if (!sym_ctx || !name) return false;
    int32_t idx = symbol_table_find_by_name(sym_ctx, name);
    if (idx < 0 || (uint32_t)idx >= sym_ctx->symbol_count) return false;
    return sym_ctx->symbols[idx].type == SYMBOL_TYPE_UNDEFINED;
}

// MARK: - Helper: Check If Binary Has ObjC Symbols

static bool has_objc_symbols(SymbolTableContext *sym_ctx) {
    if (!sym_ctx) return false;
    for (uint32_t i = 0; i < sym_ctx->symbol_count; i++) {
        if (sym_ctx->symbols[i].name &&
            (strstr(sym_ctx->symbols[i].name, "_OBJC_") != NULL ||
             strstr(sym_ctx->symbols[i].name, "_objc_") != NULL)) {
            return true;
        }
    }
    return false;
}

// MARK: - Helper: Initialize Finding

static void init_finding(SecurityFinding *finding, const char *name, const char *description) {
    memset(finding, 0, sizeof(SecurityFinding));
    safe_strncpy(finding->name, name, sizeof(finding->name));
    safe_strncpy(finding->description, description, sizeof(finding->description));
    finding->status = SECURITY_STATUS_UNCERTAIN;
    finding->severity = SECURITY_SEVERITY_INFO;
}

// MARK: - Helper: Add Dangerous API Entry

static bool add_api_entry(DangerousAPIEntry *entries, int *count, int max,
                          const char *func_name, const char *risk,
                          SecuritySeverity severity, bool imported) {
    if (*count >= max) return false;
    DangerousAPIEntry *entry = &entries[*count];
    memset(entry, 0, sizeof(DangerousAPIEntry));
    safe_strncpy(entry->function_name, func_name, sizeof(entry->function_name));
    safe_strncpy(entry->risk_description, risk, sizeof(entry->risk_description));
    entry->severity = severity;
    entry->is_imported = imported;
    (*count)++;
    return true;
}

// MARK: - Analysis: PIE Check

static void analyze_pie(SecurityFinding *finding, MachOContext *ctx) {
    init_finding(finding, "PIE (Position Independent Executable)",
                 "ASLR support through position-independent code");

    if (!ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No binary context available", sizeof(finding->detail));
        return;
    }

    if (ctx->header.filetype == MH_DYLIB) {
        finding->status = SECURITY_STATUS_NOT_APPLICABLE;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Dynamic libraries are always position-independent",
                     sizeof(finding->detail));
        return;
    }

    if (ctx->header.flags & MH_PIE) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Binary is position-independent, ASLR enabled",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_HIGH;
        safe_strncpy(finding->detail, "Binary is not position-independent, ASLR may not be effective",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: ARC Detection

static void analyze_arc(SecurityFinding *finding, SymbolTableContext *sym_ctx) {
    init_finding(finding, "ARC (Automatic Reference Counting)",
                 "Memory management safety through ARC");

    if (!sym_ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No symbol table available for analysis", sizeof(finding->detail));
        return;
    }

    bool has_arc_symbols = symbol_exists(sym_ctx, "_objc_release") ||
                           symbol_exists(sym_ctx, "_objc_retain") ||
                           symbol_exists(sym_ctx, "_objc_storeStrong") ||
                           symbol_exists(sym_ctx, "_objc_autoreleaseReturnValue");

    if (has_arc_symbols) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Likely uses ARC (ARC runtime symbols detected)",
                     sizeof(finding->detail));
    } else if (has_objc_symbols(sym_ctx)) {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_MEDIUM;
        safe_strncpy(finding->detail,
                     "Objective-C symbols present but no ARC runtime symbols found; may use manual retain/release",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_NOT_APPLICABLE;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "No Objective-C symbols detected; ARC is not applicable",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: Stack Canaries

static void analyze_stack_canaries(SecurityFinding *finding, SymbolTableContext *sym_ctx) {
    init_finding(finding, "Stack Canaries",
                 "Stack buffer overflow protection");

    if (!sym_ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No symbol table available for analysis", sizeof(finding->detail));
        return;
    }

    bool has_chk_fail = symbol_exists(sym_ctx, "___stack_chk_fail");
    bool has_chk_guard = symbol_exists(sym_ctx, "___stack_chk_guard");

    if (has_chk_fail || has_chk_guard) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Stack canary symbols detected (-fstack-protector enabled)",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_HIGH;
        safe_strncpy(finding->detail,
                     "No stack canary symbols found; binary may be vulnerable to stack buffer overflows",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: NX Heap

static void analyze_nx_heap(SecurityFinding *finding, MachOContext *ctx) {
    init_finding(finding, "NX Heap",
                 "Non-executable heap memory");

    if (!ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No binary context available", sizeof(finding->detail));
        return;
    }

    if (ctx->header.flags & MH_NO_HEAP_EXECUTION) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "MH_NO_HEAP_EXECUTION flag is set; heap is non-executable",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        finding->severity = SECURITY_SEVERITY_LOW;
        safe_strncpy(finding->detail,
                     "MH_NO_HEAP_EXECUTION flag not set; most modern systems enforce this regardless",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: NX Stack

static void analyze_nx_stack(SecurityFinding *finding, MachOContext *ctx) {
    init_finding(finding, "NX Stack",
                 "Non-executable stack memory");

    if (!ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No binary context available", sizeof(finding->detail));
        return;
    }

    if (ctx->header.flags & MH_ALLOW_STACK_EXECUTION) {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_CRITICAL;
        safe_strncpy(finding->detail,
                     "MH_ALLOW_STACK_EXECUTION is set; stack is executable, enabling stack-based code execution attacks",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Stack is non-executable (W^X enforced)",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: Code Signing

static void analyze_code_signing(SecurityFinding *finding, CodeSignatureInfo *sig_info) {
    init_finding(finding, "Code Signing",
                 "Binary code signature verification");

    if (!sig_info) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No code signature information available", sizeof(finding->detail));
        return;
    }

    if (!sig_info->is_signed) {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_HIGH;
        safe_strncpy(finding->detail, "Binary is not code signed", sizeof(finding->detail));
        return;
    }

    if (sig_info->is_adhoc_signed) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_MEDIUM;
        safe_strncpy(finding->detail,
                     "Binary is ad-hoc signed (no identity verification)",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Binary is code signed with a valid identity",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: Encryption

static void analyze_encryption(SecurityFinding *finding, MachOContext *ctx) {
    init_finding(finding, "Encryption",
                 "Binary encryption (App Store FairPlay DRM)");

    if (!ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No binary context available", sizeof(finding->detail));
        return;
    }

    if (!ctx->is_encrypted) {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail,
                     "Binary is not encrypted (normal for development builds or decrypted binaries)",
                     sizeof(finding->detail));
        return;
    }

    if (ctx->cryptid == 0) {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_LOW;
        safe_strncpy(finding->detail,
                     "Encryption header present but cryptid is 0 (binary has been decrypted)",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail, "Binary is encrypted (FairPlay DRM active)",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: Restrict Segment

static void analyze_restrict_segment(SecurityFinding *finding, MachOContext *ctx) {
    init_finding(finding, "__RESTRICT Segment",
                 "Prevention of DYLD_INSERT_LIBRARIES injection");

    if (!ctx) {
        finding->status = SECURITY_STATUS_UNCERTAIN;
        safe_strncpy(finding->detail, "No binary context available", sizeof(finding->detail));
        return;
    }

    bool found_restrict = false;
    for (uint32_t i = 0; i < ctx->segment_count; i++) {
        if (strncmp(ctx->segments[i].segname, "__RESTRICT", 16) == 0) {
            found_restrict = true;
            break;
        }
    }

    if (found_restrict) {
        finding->status = SECURITY_STATUS_PRESENT;
        finding->severity = SECURITY_SEVERITY_INFO;
        safe_strncpy(finding->detail,
                     "__RESTRICT segment present; DYLD_INSERT_LIBRARIES injection is blocked",
                     sizeof(finding->detail));
    } else {
        finding->status = SECURITY_STATUS_ABSENT;
        finding->severity = SECURITY_SEVERITY_LOW;
        safe_strncpy(finding->detail,
                     "No __RESTRICT segment; binary may be susceptible to DYLD_INSERT_LIBRARIES injection",
                     sizeof(finding->detail));
    }
}

// MARK: - Analysis: Dangerous APIs

static void analyze_dangerous_apis(DangerousAPIEntry *entries, int *count,
                                   SymbolTableContext *sym_ctx) {
    *count = 0;
    if (!sym_ctx) return;

    typedef struct {
        const char *name;
        const char *risk;
        SecuritySeverity severity;
    } APICheck;

    APICheck checks[] = {
        { "_system",       "Executes shell commands, potential injection",     SECURITY_SEVERITY_HIGH },
        { "_popen",        "Opens pipe to shell, potential injection",         SECURITY_SEVERITY_HIGH },
        { "_dlopen",       "Dynamic library loading",                         SECURITY_SEVERITY_MEDIUM },
        { "_exec",         "Process execution",                               SECURITY_SEVERITY_HIGH },
        { "_execv",        "Process execution",                               SECURITY_SEVERITY_HIGH },
        { "_execve",       "Process execution",                               SECURITY_SEVERITY_HIGH },
        { "_execvp",       "Process execution",                               SECURITY_SEVERITY_HIGH },
        { "_fork",         "Process forking",                                 SECURITY_SEVERITY_MEDIUM },
        { "_ptrace",       "Process tracing / anti-debug",                    SECURITY_SEVERITY_MEDIUM },
        { "_task_for_pid", "Task port access",                                SECURITY_SEVERITY_HIGH },
    };

    int num_checks = (int)(sizeof(checks) / sizeof(checks[0]));

    for (int i = 0; i < num_checks && *count < MAX_DANGEROUS_APIS; i++) {
        if (symbol_is_imported(sym_ctx, checks[i].name)) {
            add_api_entry(entries, count, MAX_DANGEROUS_APIS,
                          checks[i].name, checks[i].risk,
                          checks[i].severity, true);
        }
    }
}

// MARK: - Analysis: Insecure Functions

static void analyze_insecure_functions(DangerousAPIEntry *entries, int *count,
                                       SymbolTableContext *sym_ctx) {
    *count = 0;
    if (!sym_ctx) return;

    typedef struct {
        const char *name;
        const char *risk;
        SecuritySeverity severity;
    } FuncCheck;

    FuncCheck checks[] = {
        { "_gets",    "Buffer overflow, use fgets instead",  SECURITY_SEVERITY_CRITICAL },
        { "_strcpy",  "Use strlcpy instead",                 SECURITY_SEVERITY_MEDIUM },
        { "_strcat",  "Use strlcat instead",                 SECURITY_SEVERITY_MEDIUM },
        { "_sprintf", "Use snprintf instead",                SECURITY_SEVERITY_MEDIUM },
        { "_scanf",   "Potential buffer overflow",           SECURITY_SEVERITY_LOW },
        { "_alloca",  "Stack overflow risk",                 SECURITY_SEVERITY_LOW },
    };

    int num_checks = (int)(sizeof(checks) / sizeof(checks[0]));

    for (int i = 0; i < num_checks && *count < MAX_INSECURE_FUNCTIONS; i++) {
        if (symbol_is_imported(sym_ctx, checks[i].name)) {
            add_api_entry(entries, count, MAX_INSECURE_FUNCTIONS,
                          checks[i].name, checks[i].risk,
                          checks[i].severity, true);
        }
    }
}

// MARK: - Analysis: Dangerous Entitlements

static void analyze_dangerous_entitlements(SecurityAnalysisResult *result, EntitlementsInfo *ent_info) {
    result->has_dangerous_entitlements = false;
    result->dangerous_entitlement_count = 0;

    if (!ent_info || !ent_info->entitlements_xml || ent_info->xml_length == 0) return;

    typedef struct {
        const char *key;
        const char *description;
    } EntitlementCheck;

    EntitlementCheck checks[] = {
        { "get-task-allow",
          "Debug entitlement, should not be in production" },
        { "task_for_pid-allow",
          "Allows inspecting other processes" },
        { "com.apple.private",
          "Uses private Apple entitlements" },
        { "com.apple.security.cs.disable-library-validation",
          "Disables library validation" },
        { "com.apple.security.cs.allow-unsigned-executable-memory",
          "Allows unsigned executable memory" },
    };

    int num_checks = (int)(sizeof(checks) / sizeof(checks[0]));

    for (int i = 0; i < num_checks && result->dangerous_entitlement_count < 20; i++) {
        if (strstr(ent_info->entitlements_xml, checks[i].key) != NULL) {
            result->has_dangerous_entitlements = true;
            safe_strncpy(result->dangerous_entitlements[result->dangerous_entitlement_count],
                         checks[i].description,
                         sizeof(result->dangerous_entitlements[0]));
            result->dangerous_entitlement_count++;
        }
    }
}

// MARK: - Helper: Count Severity In Finding

static void count_finding_severity(const SecurityFinding *finding,
                                   int *critical, int *high, int *medium,
                                   int *low, int *info) {
    if (finding->status == SECURITY_STATUS_NOT_APPLICABLE) return;

    switch (finding->severity) {
        case SECURITY_SEVERITY_CRITICAL: (*critical)++; break;
        case SECURITY_SEVERITY_HIGH:     (*high)++;     break;
        case SECURITY_SEVERITY_MEDIUM:   (*medium)++;   break;
        case SECURITY_SEVERITY_LOW:      (*low)++;      break;
        case SECURITY_SEVERITY_INFO:     (*info)++;     break;
    }
}

// MARK: - Posture Summary

static void compute_posture(SecurityAnalysisResult *result) {
    result->critical_count = 0;
    result->high_count = 0;
    result->medium_count = 0;
    result->low_count = 0;
    result->info_count = 0;

    /* Count from binary protection findings */
    const SecurityFinding *findings[] = {
        &result->pie,
        &result->arc,
        &result->stack_canaries,
        &result->nx_heap,
        &result->nx_stack,
        &result->code_signing,
        &result->encryption,
        &result->restrict_segment,
    };

    int num_findings = (int)(sizeof(findings) / sizeof(findings[0]));
    for (int i = 0; i < num_findings; i++) {
        count_finding_severity(findings[i],
                               &result->critical_count, &result->high_count,
                               &result->medium_count, &result->low_count,
                               &result->info_count);
    }

    /* Count from dangerous APIs */
    for (int i = 0; i < result->dangerous_api_count; i++) {
        switch (result->dangerous_apis[i].severity) {
            case SECURITY_SEVERITY_CRITICAL: result->critical_count++; break;
            case SECURITY_SEVERITY_HIGH:     result->high_count++;     break;
            case SECURITY_SEVERITY_MEDIUM:   result->medium_count++;   break;
            case SECURITY_SEVERITY_LOW:      result->low_count++;      break;
            case SECURITY_SEVERITY_INFO:     result->info_count++;     break;
        }
    }

    /* Count from insecure functions */
    for (int i = 0; i < result->insecure_function_count; i++) {
        switch (result->insecure_functions[i].severity) {
            case SECURITY_SEVERITY_CRITICAL: result->critical_count++; break;
            case SECURITY_SEVERITY_HIGH:     result->high_count++;     break;
            case SECURITY_SEVERITY_MEDIUM:   result->medium_count++;   break;
            case SECURITY_SEVERITY_LOW:      result->low_count++;      break;
            case SECURITY_SEVERITY_INFO:     result->info_count++;     break;
        }
    }

    result->total_findings = result->critical_count + result->high_count +
                             result->medium_count + result->low_count +
                             result->info_count;

    /* Determine posture */
    if (result->critical_count >= 2) {
        safe_strncpy(result->posture_summary, "Poor", sizeof(result->posture_summary));
    } else if (result->critical_count == 1) {
        safe_strncpy(result->posture_summary, "Concerning", sizeof(result->posture_summary));
    } else if (result->high_count > 0) {
        safe_strncpy(result->posture_summary, "Fair", sizeof(result->posture_summary));
    } else {
        safe_strncpy(result->posture_summary, "Good", sizeof(result->posture_summary));
    }

    /* Build detail string */
    snprintf(result->posture_detail, sizeof(result->posture_detail),
             "Security posture: %s. "
             "Findings: %d critical, %d high, %d medium, %d low, %d informational.",
             result->posture_summary,
             result->critical_count, result->high_count,
             result->medium_count, result->low_count, result->info_count);
}

// MARK: - Public API

SecurityAnalysisResult* security_analyze(MachOContext *ctx,
                                         SymbolTableContext *sym_ctx,
                                         CodeSignatureInfo *sig_info,
                                         EntitlementsInfo *ent_info) {
    SecurityAnalysisResult *result = (SecurityAnalysisResult *)calloc(1, sizeof(SecurityAnalysisResult));
    if (!result) return NULL;

    /* Allocate arrays for dynamic findings */
    result->dangerous_apis = (DangerousAPIEntry *)calloc(MAX_DANGEROUS_APIS, sizeof(DangerousAPIEntry));
    if (!result->dangerous_apis) {
        free(result);
        return NULL;
    }

    result->insecure_functions = (DangerousAPIEntry *)calloc(MAX_INSECURE_FUNCTIONS, sizeof(DangerousAPIEntry));
    if (!result->insecure_functions) {
        free(result->dangerous_apis);
        free(result);
        return NULL;
    }

    /* Run all analyses */
    analyze_pie(&result->pie, ctx);
    analyze_arc(&result->arc, sym_ctx);
    analyze_stack_canaries(&result->stack_canaries, sym_ctx);
    analyze_nx_heap(&result->nx_heap, ctx);
    analyze_nx_stack(&result->nx_stack, ctx);
    analyze_code_signing(&result->code_signing, sig_info);
    analyze_encryption(&result->encryption, ctx);
    analyze_restrict_segment(&result->restrict_segment, ctx);
    analyze_dangerous_apis(result->dangerous_apis, &result->dangerous_api_count, sym_ctx);
    analyze_insecure_functions(result->insecure_functions, &result->insecure_function_count, sym_ctx);
    analyze_dangerous_entitlements(result, ent_info);

    /* Compute overall posture */
    compute_posture(result);

    return result;
}

void security_free_result(SecurityAnalysisResult *result) {
    if (!result) return;
    free(result->dangerous_apis);
    free(result->insecure_functions);
    free(result);
}

const char* security_status_string(SecurityStatus status) {
    switch (status) {
        case SECURITY_STATUS_PRESENT:        return "Present";
        case SECURITY_STATUS_ABSENT:         return "Absent";
        case SECURITY_STATUS_UNCERTAIN:      return "Uncertain";
        case SECURITY_STATUS_NOT_APPLICABLE: return "N/A";
    }
    return "Unknown";
}

const char* security_severity_string(SecuritySeverity severity) {
    switch (severity) {
        case SECURITY_SEVERITY_INFO:     return "Info";
        case SECURITY_SEVERITY_LOW:      return "Low";
        case SECURITY_SEVERITY_MEDIUM:   return "Medium";
        case SECURITY_SEVERITY_HIGH:     return "High";
        case SECURITY_SEVERITY_CRITICAL: return "Critical";
    }
    return "Unknown";
}
