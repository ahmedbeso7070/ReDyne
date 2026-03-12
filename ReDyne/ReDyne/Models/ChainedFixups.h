#ifndef ChainedFixups_h
#define ChainedFixups_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include "MachOHeader.h"

#pragma mark - Chained Fixup Format Constants

// Chained import formats
#define DYLD_CHAINED_IMPORT          1
#define DYLD_CHAINED_IMPORT_ADDEND   2
#define DYLD_CHAINED_IMPORT_ADDEND64 3

// Chained pointer formats
#define DYLD_CHAINED_PTR_ARM64E                 1
#define DYLD_CHAINED_PTR_64                     2
#define DYLD_CHAINED_PTR_32                     3
#define DYLD_CHAINED_PTR_32_CACHE               4
#define DYLD_CHAINED_PTR_32_FIRMWARE            5
#define DYLD_CHAINED_PTR_64_OFFSET              6
#define DYLD_CHAINED_PTR_ARM64E_KERNEL          7
#define DYLD_CHAINED_PTR_64_KERNEL_CACHE        8
#define DYLD_CHAINED_PTR_ARM64E_USERLAND        9
#define DYLD_CHAINED_PTR_ARM64E_FIRMWARE        10
#define DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE    11
#define DYLD_CHAINED_PTR_ARM64E_USERLAND24      12

#pragma mark - On-disk Structures

typedef struct {
    uint32_t fixups_version;    // 0
    uint32_t starts_offset;     // offset of dyld_chained_starts_in_image
    uint32_t imports_offset;    // offset of imports table
    uint32_t symbols_offset;    // offset of symbol strings
    uint32_t imports_count;     // number of imported symbol names
    uint32_t imports_format;    // DYLD_CHAINED_IMPORT*
    uint32_t symbols_format;    // 0 => uncompressed, 1 => zlib compressed
} dyld_chained_fixups_header_t;

typedef struct {
    uint32_t seg_count;
    // followed by seg_count uint32_t offsets to dyld_chained_starts_in_segment
} dyld_chained_starts_in_image_t;

typedef struct {
    uint32_t size;              // size of this struct (including variable-length page_start array)
    uint16_t page_size;         // 0x1000 or 0x4000
    uint16_t pointer_format;    // DYLD_CHAINED_PTR_*
    uint64_t segment_offset;    // offset in memory to start of segment
    uint32_t max_valid_pointer; // for 32-bit OS, any value beyond this is not a pointer
    uint16_t page_count;        // how many pages are in array
    // followed by page_count uint16_t page_start values
    // DYLD_CHAINED_PTR_START_NONE = 0xFFFF means no fixups on that page
} dyld_chained_starts_in_segment_t;

#pragma mark - Parsed Result Structures

typedef struct {
    char name[256];
    int32_t lib_ordinal;
    bool is_weak;
    uint64_t addend;
} ChainedImportInfo;

typedef struct {
    uint64_t address;           // VM address of the fixup location
    bool is_bind;               // true = bind (import), false = rebase

    // For binds:
    uint32_t bind_ordinal;      // index into imports table
    char symbol_name[256];
    int32_t lib_ordinal;
    bool is_weak;
    int64_t addend;

    // For rebases:
    uint64_t rebase_target;     // target VM address
} ChainedFixupEntry;

typedef struct {
    // Header info
    uint32_t fixups_version;
    uint32_t imports_format;
    uint32_t symbols_format;

    // Imports
    ChainedImportInfo *imports;
    uint32_t import_count;

    // All fixup entries (binds + rebases)
    ChainedFixupEntry *fixups;
    uint32_t fixup_count;
    uint32_t fixup_capacity;

    // Statistics
    uint32_t bind_count;
    uint32_t rebase_count;
    uint32_t segment_count;
    uint16_t pointer_format;

    // Warnings
    char warnings[16][256];
    uint32_t warning_count;
} ChainedFixupsResult;

#pragma mark - Public API

// Parse LC_DYLD_CHAINED_FIXUPS data from a MachO context.
// ctx must have has_chained_fixups == true and valid chained_fixups_offset/size.
ChainedFixupsResult* chained_fixups_parse(MachOContext *ctx);

void chained_fixups_free(ChainedFixupsResult *result);

const char* chained_pointer_format_string(uint16_t format);
const char* chained_import_format_string(uint32_t format);

#endif
