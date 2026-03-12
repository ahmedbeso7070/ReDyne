#ifndef SwiftMetadata_h
#define SwiftMetadata_h

#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Swift 5 Type Descriptor Kinds

typedef enum {
    SWIFT_TYPE_CLASS = 0,
    SWIFT_TYPE_STRUCT = 1,
    SWIFT_TYPE_ENUM = 2,
    SWIFT_TYPE_PROTOCOL = 3,
} SwiftTypeKind;

// MARK: - Parsed Swift Type Descriptor

typedef struct {
    char *name;              // Type name (demangled if possible)
    char *mangledName;       // Original mangled name
    SwiftTypeKind kind;
    uint64_t address;        // Address in binary
    uint32_t fieldCount;     // Number of fields/stored properties
    uint32_t flags;
    bool isGeneric;
    bool hasVTable;
} SwiftTypeDescriptor;

// MARK: - Parsed Swift Protocol Conformance

typedef struct {
    char *typeName;          // Conforming type name
    char *protocolName;      // Protocol name
    uint64_t address;
} SwiftProtocolConformance;

// MARK: - Parsed Swift Field Descriptor

typedef struct {
    char *name;              // Field name
    char *typeName;          // Field type (mangled)
    char *ownerName;         // Owning type name
    bool isMutable;          // var vs let
    bool isIndirect;         // Indirect enum case
} SwiftFieldDescriptor;

// MARK: - Complete Swift Metadata Analysis Result

typedef struct {
    SwiftTypeDescriptor *types;
    uint32_t typeCount;

    SwiftProtocolConformance *conformances;
    uint32_t conformanceCount;

    SwiftFieldDescriptor *fields;
    uint32_t fieldCount;

    uint32_t totalClasses;
    uint32_t totalStructs;
    uint32_t totalEnums;
    uint32_t totalProtocols;

    bool hasSwiftMetadata;
} SwiftMetadataResult;

// MARK: - Public Functions

// Parse Swift metadata from a Mach-O binary.
// file: opened FILE* positioned at start
// sections: array of SectionInfo from MachO parser
// sectionCount: number of sections
// fileSize: total file size for bounds checking
// is64Bit: whether the binary is 64-bit
SwiftMetadataResult *swift_metadata_parse(FILE *file,
                                           const void *sections,
                                           uint32_t sectionCount,
                                           uint64_t fileSize,
                                           bool is64Bit);

void swift_metadata_free(SwiftMetadataResult *result);

const char *swift_type_kind_string(SwiftTypeKind kind);

#ifdef __cplusplus
}
#endif

#endif
