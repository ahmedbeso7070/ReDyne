#include "ChainedFixups.h"
#include <stdlib.h>
#include <string.h>

#pragma mark - Constants

#define DYLD_CHAINED_PTR_START_NONE  0xFFFF
#define DYLD_CHAINED_PTR_START_MULTI 0x8000

#define MAX_CHAINED_FIXUPS  500000
#define INITIAL_FIXUP_CAPACITY 1024

#pragma mark - Internal Helpers

// Add a warning message to the result (capped at 16 warnings).
static void add_chained_warning(ChainedFixupsResult *result, const char *msg) {
    if (result->warning_count < 16) {
        strncpy(result->warnings[result->warning_count], msg, 255);
        result->warnings[result->warning_count][255] = '\0';
        result->warning_count++;
    }
}

// Add a fixup entry to the result, growing the array if needed.
// Returns false if the safety cap is hit or allocation fails.
static bool add_fixup_entry(ChainedFixupsResult *result, ChainedFixupEntry *entry) {
    if (result->fixup_count >= MAX_CHAINED_FIXUPS) {
        return false;
    }

    if (result->fixup_count >= result->fixup_capacity) {
        uint32_t new_capacity = result->fixup_capacity * 2;
        if (new_capacity > MAX_CHAINED_FIXUPS) {
            new_capacity = MAX_CHAINED_FIXUPS;
        }
        ChainedFixupEntry *new_arr = realloc(result->fixups,
                                              new_capacity * sizeof(ChainedFixupEntry));
        if (!new_arr) {
            return false;
        }
        result->fixups = new_arr;
        result->fixup_capacity = new_capacity;
    }

    result->fixups[result->fixup_count] = *entry;
    result->fixup_count++;

    if (entry->is_bind) {
        result->bind_count++;
    } else {
        result->rebase_count++;
    }

    return true;
}

// Safely read bytes from the fixups data blob with bounds checking.
static bool safe_read(const uint8_t *data, uint32_t data_size,
                      uint32_t offset, void *dest, uint32_t count) {
    if (offset > data_size || count > data_size - offset) {
        return false;
    }
    memcpy(dest, data + offset, count);
    return true;
}

// Read a null-terminated string from the data blob.
// Returns the string length (excluding null), or 0 on failure.
static uint32_t safe_read_string(const uint8_t *data, uint32_t data_size,
                                  uint32_t offset, char *dest, uint32_t dest_size) {
    if (offset >= data_size || dest_size == 0) {
        dest[0] = '\0';
        return 0;
    }

    uint32_t max_len = data_size - offset;
    if (max_len > dest_size - 1) {
        max_len = dest_size - 1;
    }

    uint32_t i = 0;
    while (i < max_len && data[offset + i] != '\0') {
        dest[i] = (char)data[offset + i];
        i++;
    }
    dest[i] = '\0';
    return i;
}

#pragma mark - Import Parsing

// Parse the imports table based on the import format.
static bool parse_imports(const uint8_t *data, uint32_t data_size,
                          uint32_t imports_offset, uint32_t imports_count,
                          uint32_t imports_format, uint32_t symbols_offset,
                          ChainedFixupsResult *result) {

    result->imports = calloc(imports_count, sizeof(ChainedImportInfo));
    if (!result->imports) {
        add_chained_warning(result, "Failed to allocate imports array");
        return false;
    }
    result->import_count = imports_count;

    for (uint32_t i = 0; i < imports_count; i++) {
        ChainedImportInfo *imp = &result->imports[i];

        switch (imports_format) {
            case DYLD_CHAINED_IMPORT: {
                // Each entry is 4 bytes packed:
                //   bits  0-7:  lib_ordinal (int8_t, sign-extended)
                //   bit   8:    weak_import
                //   bits  9-31: name_offset (23 bits)
                uint32_t raw;
                uint32_t entry_offset = imports_offset + (i * 4);
                if (!safe_read(data, data_size, entry_offset, &raw, 4)) {
                    add_chained_warning(result, "Import entry read out of bounds");
                    return false;
                }

                imp->lib_ordinal = (int8_t)(raw & 0xFF);
                imp->is_weak     = (raw >> 8) & 1;
                uint32_t name_off = (raw >> 9) & 0x7FFFFF;
                imp->addend      = 0;

                safe_read_string(data, data_size,
                                 symbols_offset + name_off,
                                 imp->name, sizeof(imp->name));
                break;
            }

            case DYLD_CHAINED_IMPORT_ADDEND: {
                // Each entry is 8 bytes:
                //   4 bytes: same packed format as DYLD_CHAINED_IMPORT
                //   4 bytes: int32_t addend
                uint32_t raw;
                int32_t addend;
                uint32_t entry_offset = imports_offset + (i * 8);
                if (!safe_read(data, data_size, entry_offset, &raw, 4)) {
                    add_chained_warning(result, "Import entry read out of bounds");
                    return false;
                }
                if (!safe_read(data, data_size, entry_offset + 4, &addend, 4)) {
                    add_chained_warning(result, "Import addend read out of bounds");
                    return false;
                }

                imp->lib_ordinal = (int8_t)(raw & 0xFF);
                imp->is_weak     = (raw >> 8) & 1;
                uint32_t name_off = (raw >> 9) & 0x7FFFFF;
                imp->addend      = addend;

                safe_read_string(data, data_size,
                                 symbols_offset + name_off,
                                 imp->name, sizeof(imp->name));
                break;
            }

            case DYLD_CHAINED_IMPORT_ADDEND64: {
                // Each entry is 16 bytes:
                //   8 bytes packed:
                //     bits  0-15:  lib_ordinal (int16_t, sign-extended)
                //     bit   16:    weak_import
                //     bits  17-31: reserved (15 bits)
                //     bits  32-63: name_offset (32 bits)
                //   8 bytes: uint64_t addend
                uint64_t raw;
                uint64_t addend;
                uint32_t entry_offset = imports_offset + (i * 16);
                if (!safe_read(data, data_size, entry_offset, &raw, 8)) {
                    add_chained_warning(result, "Import64 entry read out of bounds");
                    return false;
                }
                if (!safe_read(data, data_size, entry_offset + 8, &addend, 8)) {
                    add_chained_warning(result, "Import64 addend read out of bounds");
                    return false;
                }

                imp->lib_ordinal = (int16_t)(raw & 0xFFFF);
                imp->is_weak     = (raw >> 16) & 1;
                uint32_t name_off = (uint32_t)((raw >> 32) & 0xFFFFFFFF);
                imp->addend      = (int64_t)addend;

                safe_read_string(data, data_size,
                                 symbols_offset + name_off,
                                 imp->name, sizeof(imp->name));
                break;
            }

            default:
                add_chained_warning(result, "Unknown chained import format");
                return false;
        }
    }

    return true;
}

#pragma mark - Chain Walking

// Walk a single fixup chain on a page for DYLD_CHAINED_PTR_64 / DYLD_CHAINED_PTR_64_OFFSET.
//
// 64-bit pointer layout (both PTR_64 and PTR_64_OFFSET):
//   Bind:
//     bit  63:     1 (bind flag)
//     bits 62-52:  reserved
//     bits 51-50:  (part of next, see below)
//     bits 51-62:  next (12 bits) — delta / 4 to next fixup; 0 = end
//     bits 24-31:  addend (8 bits, sign-extended)
//     bits  0-23:  ordinal (24 bits)
//
//   Rebase:
//     bit  63:     0 (rebase flag)
//     bits 62-52:  reserved / next overlap
//     bits 51-62:  next (12 bits)
//     bits 36-43:  high8 — top byte of target (TBI on arm64)
//     bits  0-35:  target (36 bits)
//       PTR_64: absolute VM address
//       PTR_64_OFFSET: offset from mach_header to target
//
// Note: the "next" field occupies bits 51-62 (12 bits). Stride is 4 bytes.
static void walk_chain_ptr64(const uint8_t *data, uint32_t data_size,
                             uint32_t seg_file_offset, uint64_t seg_vm_addr,
                             uint16_t pointer_format,
                             uint32_t page_offset, uint16_t page_size,
                             ChainedFixupsResult *result) {

    uint32_t offset_in_page = page_offset;

    while (true) {
        uint32_t file_offset = seg_file_offset + offset_in_page;
        uint64_t raw;
        if (!safe_read(data, data_size, file_offset, &raw, 8)) {
            add_chained_warning(result, "Chain walk read out of bounds (ptr64)");
            return;
        }

        // Extract the next delta: bits 51-62 (12 bits)
        uint32_t next = (uint32_t)((raw >> 51) & 0xFFF);

        ChainedFixupEntry entry;
        memset(&entry, 0, sizeof(entry));
        entry.address = seg_vm_addr + offset_in_page;

        // bit 63: 1 = bind, 0 = rebase
        if (raw & ((uint64_t)1 << 63)) {
            // Bind
            entry.is_bind = true;
            entry.bind_ordinal = (uint32_t)(raw & 0xFFFFFF);       // bits 0-23
            int8_t addend_raw = (int8_t)((raw >> 24) & 0xFF);      // bits 24-31, sign-extended
            entry.addend = addend_raw;

            // Resolve symbol from imports table
            if (entry.bind_ordinal < result->import_count) {
                ChainedImportInfo *imp = &result->imports[entry.bind_ordinal];
                strncpy(entry.symbol_name, imp->name, 255);
                entry.symbol_name[255] = '\0';
                entry.lib_ordinal = imp->lib_ordinal;
                entry.is_weak = imp->is_weak;
                if (entry.addend == 0) {
                    entry.addend = (int64_t)imp->addend;
                }
            }
        } else {
            // Rebase
            entry.is_bind = false;
            uint64_t target = raw & 0xFFFFFFFFFULL;                // bits 0-35
            uint8_t high8 = (uint8_t)((raw >> 36) & 0xFF);         // bits 36-43

            if (pointer_format == DYLD_CHAINED_PTR_64_OFFSET) {
                // target is an offset from mach_header
                entry.rebase_target = target | ((uint64_t)high8 << 56);
            } else {
                // target is absolute VM address
                entry.rebase_target = target | ((uint64_t)high8 << 56);
            }
        }

        if (!add_fixup_entry(result, &entry)) {
            add_chained_warning(result, "Fixup limit reached or allocation failure");
            return;
        }

        if (next == 0) {
            break;  // End of chain
        }

        // Stride is 4 bytes for PTR_64 / PTR_64_OFFSET
        offset_in_page += next * 4;

        // Safety: don't walk past one page boundary
        if (offset_in_page >= (uint32_t)page_size * 2) {
            add_chained_warning(result, "Chain walked past page boundary (ptr64)");
            return;
        }
    }
}

// Walk a single fixup chain for ARM64E variants.
//
// ARM64E pointer layout (DYLD_CHAINED_PTR_ARM64E_USERLAND / ARM64E_USERLAND24 / ARM64E):
//   Bind:
//     bit  62:     1 (bind flag)
//     bits 51-61:  next (11 bits) — delta / 8 to next fixup; 0 = end
//     For ARM64E_USERLAND24:
//       bits 0-23:  ordinal (24 bits)
//     For ARM64E / ARM64E_USERLAND:
//       bits 0-19:  ordinal (20 bits)
//     bits 32-50:  addend (19 bits for userland variants)
//
//   Rebase:
//     bit  62:     0 (rebase flag)
//     bits 51-61:  next (11 bits)
//     For ARM64E_USERLAND / ARM64E_USERLAND24:
//       bits 0-31:  target (32 bits, offset from mach_header)
//       bits 32-42: high8 in some sub-formats
//     For ARM64E:
//       bits 0-42:  target (43 bits)
//       bit  63:    top-bit (TBI)
//
// Note: stride is 8 bytes for all ARM64E formats.
static void walk_chain_arm64e(const uint8_t *data, uint32_t data_size,
                              uint32_t seg_file_offset, uint64_t seg_vm_addr,
                              uint16_t pointer_format,
                              uint32_t page_offset, uint16_t page_size,
                              ChainedFixupsResult *result) {

    uint32_t offset_in_page = page_offset;

    while (true) {
        uint32_t file_offset = seg_file_offset + offset_in_page;
        uint64_t raw;
        if (!safe_read(data, data_size, file_offset, &raw, 8)) {
            add_chained_warning(result, "Chain walk read out of bounds (arm64e)");
            return;
        }

        // Extract the next delta: bits 51-61 (11 bits)
        uint32_t next = (uint32_t)((raw >> 51) & 0x7FF);

        ChainedFixupEntry entry;
        memset(&entry, 0, sizeof(entry));
        entry.address = seg_vm_addr + offset_in_page;

        // bit 62: 1 = bind, 0 = rebase
        if (raw & ((uint64_t)1 << 62)) {
            // Bind
            entry.is_bind = true;

            if (pointer_format == DYLD_CHAINED_PTR_ARM64E_USERLAND24) {
                entry.bind_ordinal = (uint32_t)(raw & 0xFFFFFF);   // bits 0-23
            } else {
                entry.bind_ordinal = (uint32_t)(raw & 0xFFFFF);    // bits 0-19
            }

            // Addend: bits 32-50 (19 bits) for userland variants
            if (pointer_format == DYLD_CHAINED_PTR_ARM64E_USERLAND ||
                pointer_format == DYLD_CHAINED_PTR_ARM64E_USERLAND24) {
                int64_t addend_raw = (int64_t)((raw >> 32) & 0x7FFFF);
                // Sign-extend from 19 bits
                if (addend_raw & 0x40000) {
                    addend_raw |= ~0x7FFFFLL;
                }
                entry.addend = addend_raw;
            }

            // Resolve symbol from imports table
            if (entry.bind_ordinal < result->import_count) {
                ChainedImportInfo *imp = &result->imports[entry.bind_ordinal];
                strncpy(entry.symbol_name, imp->name, 255);
                entry.symbol_name[255] = '\0';
                entry.lib_ordinal = imp->lib_ordinal;
                entry.is_weak = imp->is_weak;
            }
        } else {
            // Rebase
            entry.is_bind = false;

            if (pointer_format == DYLD_CHAINED_PTR_ARM64E_USERLAND ||
                pointer_format == DYLD_CHAINED_PTR_ARM64E_USERLAND24) {
                // target is bits 0-31 (offset from mach_header)
                uint64_t target = raw & 0xFFFFFFFF;
                uint8_t high8 = (uint8_t)((raw >> 32) & 0xFF);
                entry.rebase_target = target | ((uint64_t)high8 << 56);
            } else {
                // ARM64E (non-userland): target is bits 0-42
                uint64_t target = raw & 0x7FFFFFFFFFFULL;
                bool top_bit = (raw >> 63) & 1;
                if (top_bit) {
                    entry.rebase_target = target | 0xFF00000000000000ULL;
                } else {
                    entry.rebase_target = target;
                }
            }
        }

        if (!add_fixup_entry(result, &entry)) {
            add_chained_warning(result, "Fixup limit reached or allocation failure");
            return;
        }

        if (next == 0) {
            break;  // End of chain
        }

        // Stride is 8 bytes for ARM64E formats
        offset_in_page += next * 8;

        // Safety: don't walk past page boundary
        if (offset_in_page >= (uint32_t)page_size * 2) {
            add_chained_warning(result, "Chain walked past page boundary (arm64e)");
            return;
        }
    }
}

#pragma mark - Segment/Page Walking

// Walk all chains in a single segment.
static void walk_segment_chains(const uint8_t *data, uint32_t data_size,
                                uint32_t seg_starts_offset,
                                ChainedFixupsResult *result) {

    // Read dyld_chained_starts_in_segment header fields
    uint32_t seg_size;
    if (!safe_read(data, data_size, seg_starts_offset, &seg_size, 4)) {
        add_chained_warning(result, "Cannot read segment starts size");
        return;
    }

    // Validate the size is at least the fixed header (22 bytes)
    if (seg_size < 22) {
        add_chained_warning(result, "Segment starts struct too small");
        return;
    }

    uint16_t page_size;
    uint16_t pointer_format;
    uint64_t segment_offset;
    uint16_t page_count;

    if (!safe_read(data, data_size, seg_starts_offset + 4, &page_size, 2))       return;
    if (!safe_read(data, data_size, seg_starts_offset + 6, &pointer_format, 2))  return;
    if (!safe_read(data, data_size, seg_starts_offset + 8, &segment_offset, 8))  return;
    // max_valid_pointer at offset +16, skip
    if (!safe_read(data, data_size, seg_starts_offset + 20, &page_count, 2))     return;

    if (page_size == 0) {
        return;
    }

    // Record pointer format (use the first non-zero one we see)
    if (result->pointer_format == 0) {
        result->pointer_format = pointer_format;
    }

    // The page_start array begins at seg_starts_offset + 22
    uint32_t page_starts_array_offset = seg_starts_offset + 22;

    // Compute the segment's file offset from the segment_offset field.
    // segment_offset is the VM offset of the segment from the mach_header.
    // We need to find the corresponding file offset from ctx's segments.
    // However, we're working with the raw data blob here and don't have
    // direct access to segment file offsets. The segment_offset field
    // is a byte offset within the file for the segment data, so we use
    // it to locate fixup pointers relative to the data blob start.
    //
    // IMPORTANT: The chain pointers live in the actual segment data in
    // the file, NOT in the fixups data blob. But since we read the
    // entire file into our data buffer from the MachOContext, the
    // segment_offset is usable as a file offset relative to file start.
    // We store it as-is and the walk functions use it as a file-relative offset.

    for (uint16_t page_idx = 0; page_idx < page_count; page_idx++) {
        uint16_t page_start;
        uint32_t ps_offset = page_starts_array_offset + (page_idx * 2);
        if (!safe_read(data, data_size, ps_offset, &page_start, 2)) {
            add_chained_warning(result, "Page start read out of bounds");
            return;
        }

        // DYLD_CHAINED_PTR_START_NONE means no fixups on this page
        if (page_start == DYLD_CHAINED_PTR_START_NONE) {
            continue;
        }

        // Multi-start pages (rare, used in some 32-bit formats)
        if (page_start & DYLD_CHAINED_PTR_START_MULTI) {
            // Skip multi-start pages for now; add a warning
            add_chained_warning(result, "Multi-start page encountered (unsupported)");
            continue;
        }

        // Compute the file offset for this page's chain start.
        // segment_offset is relative to the start of the file.
        uint32_t page_file_offset = (uint32_t)segment_offset + (page_idx * page_size);
        uint32_t chain_start_in_page = page_start;

        // Dispatch to the correct chain walker based on pointer format
        switch (pointer_format) {
            case DYLD_CHAINED_PTR_64:
            case DYLD_CHAINED_PTR_64_OFFSET:
                walk_chain_ptr64(data, data_size,
                                 page_file_offset, segment_offset + (page_idx * page_size),
                                 pointer_format,
                                 chain_start_in_page, page_size,
                                 result);
                break;

            case DYLD_CHAINED_PTR_ARM64E:
            case DYLD_CHAINED_PTR_ARM64E_USERLAND:
            case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
                walk_chain_arm64e(data, data_size,
                                  page_file_offset, segment_offset + (page_idx * page_size),
                                  pointer_format,
                                  chain_start_in_page, page_size,
                                  result);
                break;

            default:
                add_chained_warning(result, "Unsupported chained pointer format");
                return;
        }
    }
}

#pragma mark - Public API

ChainedFixupsResult* chained_fixups_parse(MachOContext *ctx) {
    if (!ctx || !ctx->has_chained_fixups) {
        return NULL;
    }

    if (ctx->chained_fixups_size == 0 || ctx->chained_fixups_offset == 0) {
        return NULL;
    }

    // Validate that the fixups data is within file bounds
    if ((uint64_t)ctx->chained_fixups_offset + ctx->chained_fixups_size > (uint64_t)ctx->file_size) {
        return NULL;
    }

    // Allocate result
    ChainedFixupsResult *result = calloc(1, sizeof(ChainedFixupsResult));
    if (!result) {
        return NULL;
    }

    // Allocate initial fixups array
    result->fixups = calloc(INITIAL_FIXUP_CAPACITY, sizeof(ChainedFixupEntry));
    if (!result->fixups) {
        free(result);
        return NULL;
    }
    result->fixup_capacity = INITIAL_FIXUP_CAPACITY;

    // Read the entire fixups data blob from the file
    uint32_t blob_size = ctx->chained_fixups_size;
    uint8_t *blob = malloc(blob_size);
    if (!blob) {
        chained_fixups_free(result);
        return NULL;
    }

    if (fseek(ctx->file, ctx->chained_fixups_offset, SEEK_SET) != 0) {
        free(blob);
        chained_fixups_free(result);
        return NULL;
    }

    if (fread(blob, 1, blob_size, ctx->file) != blob_size) {
        free(blob);
        chained_fixups_free(result);
        return NULL;
    }

    // Parse the fixups header
    dyld_chained_fixups_header_t header;
    if (!safe_read(blob, blob_size, 0, &header, sizeof(header))) {
        add_chained_warning(result, "Fixups header read failed");
        free(blob);
        return result;
    }

    result->fixups_version = header.fixups_version;
    result->imports_format = header.imports_format;
    result->symbols_format = header.symbols_format;

    // Validate version
    if (header.fixups_version != 0) {
        add_chained_warning(result, "Unsupported chained fixups version (expected 0)");
        free(blob);
        return result;
    }

    // Parse imports table
    if (header.imports_count > 0) {
        if (header.imports_offset >= blob_size || header.symbols_offset >= blob_size) {
            add_chained_warning(result, "Imports or symbols offset out of bounds");
            free(blob);
            return result;
        }

        if (!parse_imports(blob, blob_size,
                           header.imports_offset, header.imports_count,
                           header.imports_format, header.symbols_offset,
                           result)) {
            // Warning already added inside parse_imports
            free(blob);
            return result;
        }
    }

    // Parse starts_in_image to find segment chain starts
    if (header.starts_offset == 0 || header.starts_offset >= blob_size) {
        add_chained_warning(result, "Invalid starts_offset");
        free(blob);
        return result;
    }

    // Read seg_count from dyld_chained_starts_in_image
    uint32_t seg_count;
    if (!safe_read(blob, blob_size, header.starts_offset, &seg_count, 4)) {
        add_chained_warning(result, "Cannot read seg_count from starts_in_image");
        free(blob);
        return result;
    }

    result->segment_count = seg_count;

    // Validate seg_count is reasonable
    if (seg_count > MAX_SEGMENTS) {
        add_chained_warning(result, "Segment count exceeds maximum");
        free(blob);
        return result;
    }

    // Read the per-segment offset array (seg_count uint32_t values after seg_count field)
    uint32_t seg_offsets_base = header.starts_offset + 4;

    // Also read the entire file into memory for chain walking, since the actual
    // fixup pointers live in segment data, not in the fixups blob.
    uint8_t *file_data = malloc(ctx->file_size);
    if (!file_data) {
        add_chained_warning(result, "Failed to allocate file buffer for chain walking");
        free(blob);
        return result;
    }

    if (fseek(ctx->file, 0, SEEK_SET) != 0) {
        free(file_data);
        free(blob);
        return result;
    }

    if (fread(file_data, 1, ctx->file_size, ctx->file) != (size_t)ctx->file_size) {
        add_chained_warning(result, "Failed to read file data for chain walking");
        free(file_data);
        free(blob);
        return result;
    }

    for (uint32_t seg_idx = 0; seg_idx < seg_count; seg_idx++) {
        uint32_t seg_info_offset;
        uint32_t off_pos = seg_offsets_base + (seg_idx * 4);
        if (!safe_read(blob, blob_size, off_pos, &seg_info_offset, 4)) {
            add_chained_warning(result, "Segment offset array read out of bounds");
            break;
        }

        // Offset of 0 means this segment has no fixups
        if (seg_info_offset == 0) {
            continue;
        }

        // The segment info offset is relative to the start of the fixups blob
        uint32_t abs_seg_offset = header.starts_offset + seg_info_offset;
        if (abs_seg_offset >= blob_size) {
            add_chained_warning(result, "Segment starts offset out of bounds");
            continue;
        }

        // Read the segment starts header to get segment_offset (file offset of segment)
        // We need to read the segment starts from the blob, but walk chains in file_data
        // because the actual pointer values live in the segment data.

        // First, read the key fields from the segment starts in the blob
        uint16_t page_size_val, ptr_fmt, page_count_val;
        uint64_t seg_offset_val;

        if (!safe_read(blob, blob_size, abs_seg_offset + 4, &page_size_val, 2))   continue;
        if (!safe_read(blob, blob_size, abs_seg_offset + 6, &ptr_fmt, 2))         continue;
        if (!safe_read(blob, blob_size, abs_seg_offset + 8, &seg_offset_val, 8))  continue;
        if (!safe_read(blob, blob_size, abs_seg_offset + 20, &page_count_val, 2)) continue;

        if (page_size_val == 0 || page_count_val == 0) {
            continue;
        }

        if (result->pointer_format == 0) {
            result->pointer_format = ptr_fmt;
        }

        // Find the corresponding segment in the MachOContext to get the file offset
        uint32_t seg_file_offset = 0;
        uint64_t seg_vm_addr = 0;
        bool found_seg = false;

        for (uint32_t s = 0; s < ctx->segment_count; s++) {
            if (ctx->segments[s].fileoff == seg_offset_val ||
                ctx->segments[s].vmaddr == seg_offset_val) {
                seg_file_offset = (uint32_t)ctx->segments[s].fileoff;
                seg_vm_addr = ctx->segments[s].vmaddr;
                found_seg = true;
                break;
            }
        }

        // If we can't match a segment, try using seg_idx to index into segments
        if (!found_seg && seg_idx < ctx->segment_count) {
            seg_file_offset = (uint32_t)ctx->segments[seg_idx].fileoff;
            seg_vm_addr = ctx->segments[seg_idx].vmaddr;
            found_seg = true;
        }

        if (!found_seg) {
            add_chained_warning(result, "Could not resolve segment for chain walking");
            continue;
        }

        // Walk page starts
        uint32_t page_starts_array = abs_seg_offset + 22;

        for (uint16_t page_idx = 0; page_idx < page_count_val; page_idx++) {
            uint16_t page_start;
            uint32_t ps_off = page_starts_array + (page_idx * 2);
            if (!safe_read(blob, blob_size, ps_off, &page_start, 2)) {
                add_chained_warning(result, "Page start read out of bounds");
                break;
            }

            if (page_start == DYLD_CHAINED_PTR_START_NONE) {
                continue;
            }

            if (page_start & DYLD_CHAINED_PTR_START_MULTI) {
                add_chained_warning(result, "Multi-start page encountered (unsupported)");
                continue;
            }

            // File offset for this page
            uint32_t page_file_off = seg_file_offset + (page_idx * page_size_val);
            // VM address for this page
            uint64_t page_vm_addr = seg_vm_addr + (page_idx * page_size_val);

            // Walk the chain using file_data (the full file)
            switch (ptr_fmt) {
                case DYLD_CHAINED_PTR_64:
                case DYLD_CHAINED_PTR_64_OFFSET:
                    walk_chain_ptr64(file_data, (uint32_t)ctx->file_size,
                                     page_file_off, page_vm_addr,
                                     ptr_fmt,
                                     page_start, page_size_val,
                                     result);
                    break;

                case DYLD_CHAINED_PTR_ARM64E:
                case DYLD_CHAINED_PTR_ARM64E_USERLAND:
                case DYLD_CHAINED_PTR_ARM64E_USERLAND24:
                    walk_chain_arm64e(file_data, (uint32_t)ctx->file_size,
                                      page_file_off, page_vm_addr,
                                      ptr_fmt,
                                      page_start, page_size_val,
                                      result);
                    break;

                default:
                    add_chained_warning(result, "Unsupported chained pointer format for walking");
                    break;
            }
        }
    }

    free(file_data);
    free(blob);
    return result;
}

void chained_fixups_free(ChainedFixupsResult *result) {
    if (!result) {
        return;
    }
    if (result->imports) {
        free(result->imports);
        result->imports = NULL;
    }
    if (result->fixups) {
        free(result->fixups);
        result->fixups = NULL;
    }
    free(result);
}

const char* chained_pointer_format_string(uint16_t format) {
    switch (format) {
        case DYLD_CHAINED_PTR_ARM64E:              return "ARM64E";
        case DYLD_CHAINED_PTR_64:                   return "PTR_64";
        case DYLD_CHAINED_PTR_32:                   return "PTR_32";
        case DYLD_CHAINED_PTR_32_CACHE:             return "PTR_32_CACHE";
        case DYLD_CHAINED_PTR_32_FIRMWARE:          return "PTR_32_FIRMWARE";
        case DYLD_CHAINED_PTR_64_OFFSET:            return "PTR_64_OFFSET";
        case DYLD_CHAINED_PTR_ARM64E_KERNEL:        return "ARM64E_KERNEL";
        case DYLD_CHAINED_PTR_64_KERNEL_CACHE:      return "PTR_64_KERNEL_CACHE";
        case DYLD_CHAINED_PTR_ARM64E_USERLAND:      return "ARM64E_USERLAND";
        case DYLD_CHAINED_PTR_ARM64E_FIRMWARE:      return "ARM64E_FIRMWARE";
        case DYLD_CHAINED_PTR_X86_64_KERNEL_CACHE:  return "X86_64_KERNEL_CACHE";
        case DYLD_CHAINED_PTR_ARM64E_USERLAND24:    return "ARM64E_USERLAND24";
        default:                                     return "UNKNOWN";
    }
}

const char* chained_import_format_string(uint32_t format) {
    switch (format) {
        case DYLD_CHAINED_IMPORT:           return "DYLD_CHAINED_IMPORT";
        case DYLD_CHAINED_IMPORT_ADDEND:    return "DYLD_CHAINED_IMPORT_ADDEND";
        case DYLD_CHAINED_IMPORT_ADDEND64:  return "DYLD_CHAINED_IMPORT_ADDEND64";
        default:                             return "UNKNOWN";
    }
}
