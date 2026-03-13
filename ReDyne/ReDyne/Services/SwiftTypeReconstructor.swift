import Foundation

// MARK: - Reconstructed Swift Type Definition

/// Represents a fully reconstructed Swift nominal type with fields, conformances,
/// and a formatted pseudocode definition string.
struct ReconstructedSwiftType {
    let name: String
    let moduleName: String
    let kind: SwiftTypeKind
    let kindString: String
    let address: UInt64
    let isGeneric: Bool
    let hasVTable: Bool
    let flags: UInt32
    let fields: [ReconstructedField]
    let conformances: [String]
    let definition: String

    var fieldCount: Int { fields.count }
    var conformanceCount: Int { conformances.count }

    /// SF Symbol name for the type kind.
    var kindIcon: String {
        switch kind {
        case .init(rawValue: 0): return "cube.box.fill"         // class
        case .init(rawValue: 1): return "shippingbox.fill"      // struct
        case .init(rawValue: 2): return "list.bullet.rectangle" // enum
        case .init(rawValue: 3): return "doc.plaintext"         // protocol
        default:                 return "questionmark.diamond"
        }
    }

    /// Human-readable kind label.
    var kindLabel: String {
        switch kind {
        case .init(rawValue: 0): return "class"
        case .init(rawValue: 1): return "struct"
        case .init(rawValue: 2): return "enum"
        case .init(rawValue: 3): return "protocol"
        default:                 return "type"
        }
    }
}

/// A single field within a reconstructed type.
struct ReconstructedField {
    let name: String
    let typeName: String
    let demangledTypeName: String
    let isMutable: Bool
    let isIndirect: Bool
}

// MARK: - Swift Type Reconstructor Service

/// Reconstructs Swift nominal type definitions from parsed Swift metadata.
/// Takes a `SwiftMetadataAnalysis` (produced by `SwiftMetadataService`) and
/// optional symbol table data, then rebuilds struct/class/enum definitions
/// with fields, protocol conformances, and formatted Swift-like pseudocode.
final class SwiftTypeReconstructor {

    // MARK: - Helpers

    /// Convert a kindString (e.g. "class", "struct", "enum", "protocol") to SwiftTypeKind.
    static func swiftTypeKind(from kindString: String) -> SwiftTypeKind {
        switch kindString.lowercased() {
        case "class":    return SWIFT_TYPE_CLASS
        case "struct":   return SWIFT_TYPE_STRUCT
        case "enum":     return SWIFT_TYPE_ENUM
        case "protocol": return SWIFT_TYPE_PROTOCOL
        default:         return SWIFT_TYPE_CLASS
        }
    }

    // MARK: - Public API

    /// Reconstruct all types from a metadata analysis result.
    /// - Parameters:
    ///   - analysis: The parsed Swift metadata from `SwiftMetadataService`.
    ///   - symbols: Optional array of symbol models for additional context.
    /// - Returns: An array of reconstructed Swift type definitions.
    static func reconstruct(from analysis: SwiftMetadataAnalysis,
                            symbols: [SymbolModel]? = nil) -> [ReconstructedSwiftType] {
        // Build lookup tables
        let fieldsByOwner = buildFieldMap(analysis.fields as? [SwiftFieldInfo] ?? [])
        let conformancesByType = buildConformanceMap(analysis.conformances as? [SwiftConformanceInfo] ?? [])

        guard let types = analysis.types as? [SwiftTypeInfo] else { return [] }

        var results: [ReconstructedSwiftType] = []
        results.reserveCapacity(types.count)

        for typeInfo in types {
            let typeName = typeInfo.name
            let moduleName = extractModuleName(from: typeInfo.mangledName)

            // Gather fields for this type
            let rawFields = fieldsByOwner[typeName] ?? []
            let reconstructedFields = rawFields.map { field -> ReconstructedField in
                let demangled = demangleFieldType(field.typeName)
                return ReconstructedField(
                    name: field.name,
                    typeName: field.typeName,
                    demangledTypeName: demangled,
                    isMutable: field.isMutable,
                    isIndirect: field.isIndirect
                )
            }

            // Gather conformances
            let conformanceNames = conformancesByType[typeName] ?? []

            // Derive SwiftTypeKind from the kindString
            let typeKind = SwiftTypeReconstructor.swiftTypeKind(from: typeInfo.kindString)

            // Build the definition string
            let definition = buildDefinition(
                name: typeName,
                kind: typeKind,
                isGeneric: typeInfo.isGeneric,
                hasVTable: typeInfo.hasVTable,
                fields: reconstructedFields,
                conformances: conformanceNames
            )

            let reconstructed = ReconstructedSwiftType(
                name: typeName,
                moduleName: moduleName,
                kind: typeKind,
                kindString: typeInfo.kindString,
                address: typeInfo.address,
                isGeneric: typeInfo.isGeneric,
                hasVTable: typeInfo.hasVTable,
                flags: typeInfo.flags,
                fields: reconstructedFields,
                conformances: conformanceNames,
                definition: definition
            )
            results.append(reconstructed)
        }

        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Field Map

    private static func buildFieldMap(_ fields: [SwiftFieldInfo]) -> [String: [SwiftFieldInfo]] {
        var map: [String: [SwiftFieldInfo]] = [:]
        for field in fields {
            let owner = cleanOwnerName(field.ownerName)
            map[owner, default: []].append(field)
        }
        return map
    }

    // MARK: - Conformance Map

    private static func buildConformanceMap(_ conformances: [SwiftConformanceInfo]) -> [String: [String]] {
        var map: [String: [String]] = [:]
        for conf in conformances {
            let typeName = cleanOwnerName(conf.typeName)
            let protoName = conf.protocolName
            if !protoName.isEmpty && protoName != "<unknown>" {
                map[typeName, default: []].append(protoName)
            }
        }
        return map
    }

    // MARK: - Name Cleaning

    /// Strip mangling prefixes and module qualifiers from an owner name so it
    /// matches the plain type name stored in `SwiftTypeInfo.name`.
    private static func cleanOwnerName(_ raw: String) -> String {
        // Try demangling first
        let demangled = SwiftDemangler.demangle(raw)
        if demangled != raw {
            // Extract last component (type name without module prefix)
            if let lastDot = demangled.lastIndex(of: ".") {
                return String(demangled[demangled.index(after: lastDot)...])
            }
            return demangled
        }
        // Fallback: return as-is
        return raw
    }

    /// Try to extract the module name from a mangled name.
    private static func extractModuleName(from mangledName: String) -> String {
        let demangled = SwiftDemangler.demangle(mangledName)
        if demangled != mangledName, let dotIndex = demangled.firstIndex(of: ".") {
            return String(demangled[demangled.startIndex..<dotIndex])
        }
        return ""
    }

    // MARK: - Type Demangling

    /// Demangle a field type name and apply Swift sugar for common generics.
    private static func demangleFieldType(_ rawType: String) -> String {
        guard !rawType.isEmpty, rawType != "<unknown>" else { return rawType }

        // Try the Swift demangler
        let demangled = SwiftDemangler.demangle(rawType)
        let result = (demangled != rawType) ? demangled : rawType

        return applySugar(result)
    }

    /// Apply Swift syntactic sugar for Optional, Array, and Dictionary types.
    private static func applySugar(_ typeName: String) -> String {
        var name = typeName

        // Swift.Optional<X> -> X?
        if let range = name.range(of: "Swift.Optional<") {
            let inner = name[range.upperBound...]
            if let closing = inner.lastIndex(of: ">") {
                let wrapped = String(inner[inner.startIndex..<closing])
                name = applySugar(wrapped) + "?"
            }
        }

        // Swift.Array<X> -> [X]
        if let range = name.range(of: "Swift.Array<") {
            let inner = name[range.upperBound...]
            if let closing = inner.lastIndex(of: ">") {
                let element = String(inner[inner.startIndex..<closing])
                name = "[" + applySugar(element) + "]"
            }
        }

        // Swift.Dictionary<K, V> -> [K: V]
        if let range = name.range(of: "Swift.Dictionary<") {
            let inner = name[range.upperBound...]
            if let closing = inner.lastIndex(of: ">") {
                let params = String(inner[inner.startIndex..<closing])
                // Split on first ", "
                if let commaRange = params.range(of: ", ") {
                    let key = applySugar(String(params[params.startIndex..<commaRange.lowerBound]))
                    let value = applySugar(String(params[commaRange.upperBound...]))
                    name = "[" + key + ": " + value + "]"
                }
            }
        }

        // Strip "Swift." prefix for standard library types
        if name.hasPrefix("Swift.") {
            let stripped = String(name.dropFirst(6))
            let stdlibTypes: Set<String> = [
                "Int", "UInt", "Int8", "Int16", "Int32", "Int64",
                "UInt8", "UInt16", "UInt32", "UInt64",
                "Float", "Double", "Bool", "String",
                "Character", "Void", "Never", "Any", "AnyObject",
                "Error", "Codable", "Hashable", "Equatable",
                "Comparable", "CustomStringConvertible",
                "Identifiable", "Sendable"
            ]
            if stdlibTypes.contains(stripped) || stripped.hasSuffix("?") || stripped.hasPrefix("[") {
                name = stripped
            }
        }

        return name
    }

    // MARK: - Definition Builder

    /// Build a formatted Swift-like pseudocode string for a reconstructed type.
    private static func buildDefinition(name: String,
                                        kind: SwiftTypeKind,
                                        isGeneric: Bool,
                                        hasVTable: Bool,
                                        fields: [ReconstructedField],
                                        conformances: [String]) -> String {
        var lines: [String] = []

        // Comment header
        lines.append("// Reconstructed from Swift metadata")
        if hasVTable {
            lines.append("// Has VTable (virtual dispatch)")
        }

        // Type declaration line
        let keyword: String
        switch kind {
        case .init(rawValue: 0): keyword = "class"
        case .init(rawValue: 1): keyword = "struct"
        case .init(rawValue: 2): keyword = "enum"
        case .init(rawValue: 3): keyword = "protocol"
        default:                 keyword = "/* unknown */ struct"
        }

        var declarationLine = keyword + " " + name
        if isGeneric {
            declarationLine += "<T>"
        }

        if !conformances.isEmpty {
            declarationLine += ": " + conformances.joined(separator: ", ")
        }

        declarationLine += " {"
        lines.append(declarationLine)

        // Fields / cases
        if fields.isEmpty {
            lines.append("    // No field descriptors found")
        } else {
            let isEnum = (kind == .init(rawValue: 2))
            for field in fields {
                let typePart = field.demangledTypeName
                if isEnum {
                    if field.isIndirect {
                        lines.append("    indirect case \(field.name)(\(typePart))")
                    } else if typePart.isEmpty || typePart == "<unknown>" {
                        lines.append("    case \(field.name)")
                    } else {
                        lines.append("    case \(field.name)(\(typePart))")
                    }
                } else {
                    let letVar = field.isMutable ? "var" : "let"
                    let displayType = typePart.isEmpty ? "<unknown>" : typePart
                    lines.append("    \(letVar) \(field.name): \(displayType)")
                }
            }
        }

        lines.append("}")

        return lines.joined(separator: "\n")
    }
}
