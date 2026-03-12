#include "SwiftMetadata.h"
#include "MachOHeader.h"
#include <stdlib.h>
#include <string.h>

// MARK: - Constants

#define MAX_SWIFT_TYPES       4096
#define MAX_SWIFT_CONFORMANCES 4096
#define MAX_SWIFT_FIELDS      8192
#define MAX_NAME_LENGTH       512
#define MAX_RELATIVE_PTRS     8192

// Swift type context descriptor flags
#define SWIFT_KIND_MASK       0x1F
#define SWIFT_GENERIC_FLAG    (1u << 7)

// Swift type context descriptor kind values
#define SWIFT_CTX_CLASS       16
#define SWIFT_CTX_STRUCT      17
#define SWIFT_CTX_ENUM        18

// Swift field descriptor kind values
#define SWIFT_FIELD_STRUCT    1
#define SWIFT_FIELD_CLASS     2
#define SWIFT_FIELD_ENUM      3
#define SWIFT_FIELD_PROTOCOL  5

// MARK: - Internal Helpers

typedef struct {
    FILE *file;
    const SectionInfo *sections;
    uint32_t sectionCount;
    uint64_t fileSize;
    bool is64Bit;
} SwiftParseContext;

static bool safe_seek(SwiftParseContext *ctx, uint64_t offset) {
    if (offset >= ctx->fileSize) return false;
    return fseek(ctx->file, (long)offset, SEEK_SET) == 0;
}

static bool safe_read(SwiftParseContext *ctx, void *buf, size_t size, uint64_t offset) {
    if (offset + size > ctx->fileSize) return false;
    if (!safe_seek(ctx, offset)) return false;
    return fread(buf, 1, size, ctx->file) == size;
}

static int32_t read_relative_ptr(SwiftParseContext *ctx, uint64_t offset) {
    int32_t value = 0;
    if (!safe_read(ctx, &value, sizeof(int32_t), offset)) return 0;
    return value;
}

static uint32_t read_uint32(SwiftParseContext *ctx, uint64_t offset) {
    uint32_t value = 0;
    if (!safe_read(ctx, &value, sizeof(uint32_t), offset)) return 0;
    return value;
}

// Resolve a relative pointer: the target address is (pointer_file_offset + relative_offset)
static uint64_t resolve_relative(uint64_t pointerOffset, int32_t relativeValue) {
    if (relativeValue == 0) return 0;
    return (uint64_t)((int64_t)pointerOffset + (int64_t)relativeValue);
}

// Read a null-terminated C string from a file offset, with bounds checking
static char *read_cstring(SwiftParseContext *ctx, uint64_t offset) {
    if (offset == 0 || offset >= ctx->fileSize) return NULL;
    if (!safe_seek(ctx, offset)) return NULL;

    char buf[MAX_NAME_LENGTH];
    size_t i = 0;
    while (i < MAX_NAME_LENGTH - 1) {
        int ch = fgetc(ctx->file);
        if (ch == EOF || ch == 0) break;
        buf[i++] = (char)ch;
    }
    buf[i] = '\0';

    if (i == 0) return NULL;

    char *result = malloc(i + 1);
    if (!result) return NULL;
    memcpy(result, buf, i + 1);
    return result;
}

static char *safe_strdup(const char *s) {
    if (!s) return NULL;
    size_t len = strlen(s);
    char *dup = malloc(len + 1);
    if (!dup) return NULL;
    memcpy(dup, s, len + 1);
    return dup;
}

// Find a specific section by name across all segments
static const SectionInfo *find_section(SwiftParseContext *ctx, const char *sectname) {
    for (uint32_t i = 0; i < ctx->sectionCount; i++) {
        if (strncmp(ctx->sections[i].sectname, sectname, 16) == 0) {
            return &ctx->sections[i];
        }
    }
    return NULL;
}

static SwiftTypeKind context_kind_to_type_kind(uint32_t contextKind) {
    switch (contextKind) {
        case SWIFT_CTX_CLASS:  return SWIFT_TYPE_CLASS;
        case SWIFT_CTX_STRUCT: return SWIFT_TYPE_STRUCT;
        case SWIFT_CTX_ENUM:   return SWIFT_TYPE_ENUM;
        default:               return SWIFT_TYPE_STRUCT;
    }
}

// MARK: - Type Descriptor Parsing (__swift5_types)

static uint32_t parse_type_descriptors(SwiftParseContext *ctx,
                                        SwiftTypeDescriptor *types,
                                        uint32_t maxTypes) {
    const SectionInfo *sect = find_section(ctx, "__swift5_types");
    if (!sect || sect->size == 0) return 0;

    // The section contains an array of relative pointers to type context descriptors
    uint32_t entryCount = (uint32_t)(sect->size / sizeof(int32_t));
    if (entryCount > MAX_RELATIVE_PTRS) entryCount = MAX_RELATIVE_PTRS;

    uint32_t typeIdx = 0;

    for (uint32_t i = 0; i < entryCount && typeIdx < maxTypes; i++) {
        uint64_t ptrOffset = sect->offset + (uint64_t)(i * sizeof(int32_t));
        int32_t relValue = read_relative_ptr(ctx, ptrOffset);
        if (relValue == 0) continue;

        uint64_t descriptorOffset = resolve_relative(ptrOffset, relValue);
        if (descriptorOffset == 0 || descriptorOffset + 20 > ctx->fileSize) continue;

        // Type context descriptor layout:
        //   +0:  uint32_t flags
        //   +4:  int32_t  parent (relative pointer)
        //   +8:  int32_t  name (relative pointer to C string)
        //   +12: int32_t  accessFunction (relative pointer)
        //   +16: int32_t  fieldDescriptor (relative pointer)

        uint32_t flags = read_uint32(ctx, descriptorOffset);
        uint32_t contextKind = flags & SWIFT_KIND_MASK;

        // Only handle class/struct/enum descriptors (kinds 16, 17, 18)
        if (contextKind != SWIFT_CTX_CLASS &&
            contextKind != SWIFT_CTX_STRUCT &&
            contextKind != SWIFT_CTX_ENUM) {
            continue;
        }

        // Read name relative pointer at +8
        int32_t nameRel = read_relative_ptr(ctx, descriptorOffset + 8);
        uint64_t nameOffset = resolve_relative(descriptorOffset + 8, nameRel);

        char *name = read_cstring(ctx, nameOffset);
        if (!name) continue;

        SwiftTypeDescriptor *td = &types[typeIdx];
        td->name = name;
        td->mangledName = safe_strdup(name);
        td->kind = context_kind_to_type_kind(contextKind);
        td->address = descriptorOffset;
        td->flags = flags;
        td->isGeneric = (flags & SWIFT_GENERIC_FLAG) != 0;

        // For classes, check for VTable: if class has additional data after
        // the base descriptor, it may contain a VTable descriptor
        td->hasVTable = false;
        if (contextKind == SWIFT_CTX_CLASS) {
            // Bit 15 of flags indicates has VTable
            td->hasVTable = (flags & (1u << 15)) != 0;
        }

        // Read field count from type-specific fields
        // For struct/enum: after base descriptor (+20), there are numFields (uint32_t)
        // and fieldOffsetVectorOffset (uint32_t)
        td->fieldCount = 0;
        if (contextKind == SWIFT_CTX_STRUCT || contextKind == SWIFT_CTX_ENUM) {
            if (descriptorOffset + 24 < ctx->fileSize) {
                td->fieldCount = read_uint32(ctx, descriptorOffset + 20);
                // Sanity check
                if (td->fieldCount > 10000) td->fieldCount = 0;
            }
        } else if (contextKind == SWIFT_CTX_CLASS) {
            // Class layout has more fields; numImmediateMembers at +28 for non-generic
            if (descriptorOffset + 40 < ctx->fileSize) {
                // +20: superclassType (int32_t relative)
                // +24: negative size / metadata bounds (depends on version)
                // +28: number of immediate members or fields
                uint32_t numFields = read_uint32(ctx, descriptorOffset + 32);
                if (numFields <= 10000) {
                    td->fieldCount = numFields;
                }
            }
        }

        typeIdx++;
    }

    return typeIdx;
}

// MARK: - Protocol Conformance Parsing (__swift5_proto)

static uint32_t parse_protocol_conformances(SwiftParseContext *ctx,
                                              SwiftProtocolConformance *conformances,
                                              uint32_t maxConformances) {
    const SectionInfo *sect = find_section(ctx, "__swift5_proto");
    if (!sect || sect->size == 0) return 0;

    // The section contains an array of relative pointers to conformance descriptors
    uint32_t entryCount = (uint32_t)(sect->size / sizeof(int32_t));
    if (entryCount > MAX_RELATIVE_PTRS) entryCount = MAX_RELATIVE_PTRS;

    uint32_t confIdx = 0;

    for (uint32_t i = 0; i < entryCount && confIdx < maxConformances; i++) {
        uint64_t ptrOffset = sect->offset + (uint64_t)(i * sizeof(int32_t));
        int32_t relValue = read_relative_ptr(ctx, ptrOffset);
        if (relValue == 0) continue;

        uint64_t descOffset = resolve_relative(ptrOffset, relValue);
        if (descOffset == 0 || descOffset + 16 > ctx->fileSize) continue;

        // Protocol conformance descriptor layout:
        //   +0:  int32_t  protocolDescriptor (relative pointer, possibly indirect)
        //   +4:  int32_t  nominalTypeDescriptor (relative pointer)
        //   +8:  int32_t  protocolWitnessTable (relative pointer)
        //   +12: uint32_t conformanceFlags

        // Try to read protocol name via protocol descriptor
        int32_t protoRel = read_relative_ptr(ctx, descOffset);
        uint64_t protoDescAddr = resolve_relative(descOffset, protoRel);

        char *protocolName = NULL;
        if (protoDescAddr != 0 && protoDescAddr + 12 < ctx->fileSize) {
            // Protocol descriptor layout:
            //   +0: uint32_t flags
            //   +4: int32_t parent (relative)
            //   +8: int32_t name (relative)
            int32_t protoNameRel = read_relative_ptr(ctx, protoDescAddr + 8);
            uint64_t protoNameOffset = resolve_relative(protoDescAddr + 8, protoNameRel);
            protocolName = read_cstring(ctx, protoNameOffset);
        }

        // Read conforming type via nominal type descriptor
        int32_t typeRel = read_relative_ptr(ctx, descOffset + 4);
        // The type reference may be direct or indirect depending on bits in the flags
        uint32_t confFlags = read_uint32(ctx, descOffset + 12);
        uint32_t typeRefKind = (confFlags >> 3) & 0x7;

        char *typeName = NULL;
        if (typeRel != 0) {
            uint64_t typeDescAddr = resolve_relative(descOffset + 4, typeRel);
            if (typeDescAddr != 0 && typeDescAddr + 12 < ctx->fileSize) {
                if (typeRefKind == 0) {
                    // Direct reference to a type context descriptor
                    // Name is at +8 from the type descriptor
                    int32_t nameRel = read_relative_ptr(ctx, typeDescAddr + 8);
                    uint64_t nameOff = resolve_relative(typeDescAddr + 8, nameRel);
                    typeName = read_cstring(ctx, nameOff);
                } else {
                    // Indirect or other reference kinds - try reading as string
                    typeName = read_cstring(ctx, typeDescAddr);
                }
            }
        }

        // Only record if we got at least one name
        if (!protocolName && !typeName) continue;

        SwiftProtocolConformance *pc = &conformances[confIdx];
        pc->typeName = typeName ? typeName : safe_strdup("<unknown>");
        pc->protocolName = protocolName ? protocolName : safe_strdup("<unknown>");
        pc->address = descOffset;

        confIdx++;
    }

    return confIdx;
}

// MARK: - Field Descriptor Parsing (__swift5_fieldmd)

static uint32_t parse_field_descriptors(SwiftParseContext *ctx,
                                         SwiftFieldDescriptor *fields,
                                         uint32_t maxFields) {
    const SectionInfo *sect = find_section(ctx, "__swift5_fieldmd");
    if (!sect || sect->size == 0) return 0;

    // The section contains an array of relative pointers to field descriptors
    uint32_t entryCount = (uint32_t)(sect->size / sizeof(int32_t));
    if (entryCount > MAX_RELATIVE_PTRS) entryCount = MAX_RELATIVE_PTRS;

    uint32_t fieldIdx = 0;

    for (uint32_t i = 0; i < entryCount && fieldIdx < maxFields; i++) {
        uint64_t ptrOffset = sect->offset + (uint64_t)(i * sizeof(int32_t));
        int32_t relValue = read_relative_ptr(ctx, ptrOffset);
        if (relValue == 0) continue;

        uint64_t descOffset = resolve_relative(ptrOffset, relValue);
        if (descOffset == 0 || descOffset + 16 > ctx->fileSize) continue;

        // Field descriptor layout:
        //   +0:  int32_t  mangledTypeName (relative pointer)
        //   +4:  int32_t  superclass (relative pointer)
        //   +8:  uint16_t kind
        //   +10: uint16_t fieldRecordSize
        //   +12: uint32_t numFields
        //   Then followed by numFields field records

        // Read the owning type name
        int32_t ownerNameRel = read_relative_ptr(ctx, descOffset);
        uint64_t ownerNameOffset = resolve_relative(descOffset, ownerNameRel);
        char *ownerName = read_cstring(ctx, ownerNameOffset);

        uint32_t numFields = read_uint32(ctx, descOffset + 12);
        if (numFields > 1000) numFields = 1000; // sanity cap

        uint16_t fieldRecordSize = 0;
        if (descOffset + 12 <= ctx->fileSize) {
            safe_read(ctx, &fieldRecordSize, sizeof(uint16_t), descOffset + 10);
        }
        if (fieldRecordSize == 0) fieldRecordSize = 12; // default: 3 x int32_t

        uint64_t recordBase = descOffset + 16;

        for (uint32_t f = 0; f < numFields && fieldIdx < maxFields; f++) {
            uint64_t recordOffset = recordBase + (uint64_t)(f * fieldRecordSize);
            if (recordOffset + 12 > ctx->fileSize) break;

            // Field record layout:
            //   +0: uint32_t flags
            //   +4: int32_t  mangledTypeName (relative pointer)
            //   +8: int32_t  fieldName (relative pointer)

            uint32_t fieldFlags = read_uint32(ctx, recordOffset);
            bool isMutable = (fieldFlags & 0x2) != 0;
            bool isIndirect = (fieldFlags & 0x1) != 0;

            int32_t typeNameRel = read_relative_ptr(ctx, recordOffset + 4);
            uint64_t typeNameOff = resolve_relative(recordOffset + 4, typeNameRel);

            int32_t fieldNameRel = read_relative_ptr(ctx, recordOffset + 8);
            uint64_t fieldNameOff = resolve_relative(recordOffset + 8, fieldNameRel);

            char *fieldName = read_cstring(ctx, fieldNameOff);
            if (!fieldName) continue;

            char *fieldTypeName = read_cstring(ctx, typeNameOff);

            SwiftFieldDescriptor *fd = &fields[fieldIdx];
            fd->name = fieldName;
            fd->typeName = fieldTypeName ? fieldTypeName : safe_strdup("<unknown>");
            fd->ownerName = ownerName ? safe_strdup(ownerName) : safe_strdup("<unknown>");
            fd->isMutable = isMutable;
            fd->isIndirect = isIndirect;

            fieldIdx++;
        }

        free(ownerName);
    }

    return fieldIdx;
}

// MARK: - Public API

SwiftMetadataResult *swift_metadata_parse(FILE *file,
                                           const void *sections,
                                           uint32_t sectionCount,
                                           uint64_t fileSize,
                                           bool is64Bit) {
    if (!file || !sections || sectionCount == 0 || fileSize == 0) return NULL;

    SwiftParseContext ctx;
    ctx.file = file;
    ctx.sections = (const SectionInfo *)sections;
    ctx.sectionCount = sectionCount;
    ctx.fileSize = fileSize;
    ctx.is64Bit = is64Bit;

    // Check if any Swift metadata sections exist
    bool hasSwift = (find_section(&ctx, "__swift5_types") != NULL ||
                     find_section(&ctx, "__swift5_proto") != NULL ||
                     find_section(&ctx, "__swift5_fieldmd") != NULL);

    SwiftMetadataResult *result = calloc(1, sizeof(SwiftMetadataResult));
    if (!result) return NULL;

    result->hasSwiftMetadata = hasSwift;
    if (!hasSwift) return result;

    // Allocate working arrays
    SwiftTypeDescriptor *types = calloc(MAX_SWIFT_TYPES, sizeof(SwiftTypeDescriptor));
    SwiftProtocolConformance *conformances = calloc(MAX_SWIFT_CONFORMANCES, sizeof(SwiftProtocolConformance));
    SwiftFieldDescriptor *fields = calloc(MAX_SWIFT_FIELDS, sizeof(SwiftFieldDescriptor));

    if (!types || !conformances || !fields) {
        free(types);
        free(conformances);
        free(fields);
        free(result);
        return NULL;
    }

    // Parse each section
    uint32_t typeCount = parse_type_descriptors(&ctx, types, MAX_SWIFT_TYPES);
    uint32_t conformanceCount = parse_protocol_conformances(&ctx, conformances, MAX_SWIFT_CONFORMANCES);
    uint32_t fieldCount = parse_field_descriptors(&ctx, fields, MAX_SWIFT_FIELDS);

    // Copy results into right-sized arrays
    if (typeCount > 0) {
        result->types = calloc(typeCount, sizeof(SwiftTypeDescriptor));
        if (result->types) {
            memcpy(result->types, types, typeCount * sizeof(SwiftTypeDescriptor));
            result->typeCount = typeCount;
        }
    }

    if (conformanceCount > 0) {
        result->conformances = calloc(conformanceCount, sizeof(SwiftProtocolConformance));
        if (result->conformances) {
            memcpy(result->conformances, conformances, conformanceCount * sizeof(SwiftProtocolConformance));
            result->conformanceCount = conformanceCount;
        }
    }

    if (fieldCount > 0) {
        result->fields = calloc(fieldCount, sizeof(SwiftFieldDescriptor));
        if (result->fields) {
            memcpy(result->fields, fields, fieldCount * sizeof(SwiftFieldDescriptor));
            result->fieldCount = fieldCount;
        }
    }

    // Tally type counts
    for (uint32_t i = 0; i < result->typeCount; i++) {
        switch (result->types[i].kind) {
            case SWIFT_TYPE_CLASS:    result->totalClasses++;   break;
            case SWIFT_TYPE_STRUCT:   result->totalStructs++;   break;
            case SWIFT_TYPE_ENUM:     result->totalEnums++;     break;
            case SWIFT_TYPE_PROTOCOL: result->totalProtocols++; break;
        }
    }

    // Free working arrays (the string pointers have been shallow-copied)
    free(types);
    free(conformances);
    free(fields);

    return result;
}

void swift_metadata_free(SwiftMetadataResult *result) {
    if (!result) return;

    for (uint32_t i = 0; i < result->typeCount; i++) {
        free(result->types[i].name);
        free(result->types[i].mangledName);
    }
    free(result->types);

    for (uint32_t i = 0; i < result->conformanceCount; i++) {
        free(result->conformances[i].typeName);
        free(result->conformances[i].protocolName);
    }
    free(result->conformances);

    for (uint32_t i = 0; i < result->fieldCount; i++) {
        free(result->fields[i].name);
        free(result->fields[i].typeName);
        free(result->fields[i].ownerName);
    }
    free(result->fields);

    free(result);
}

const char *swift_type_kind_string(SwiftTypeKind kind) {
    switch (kind) {
        case SWIFT_TYPE_CLASS:    return "Class";
        case SWIFT_TYPE_STRUCT:   return "Struct";
        case SWIFT_TYPE_ENUM:     return "Enum";
        case SWIFT_TYPE_PROTOCOL: return "Protocol";
        default:                  return "Unknown";
    }
}
