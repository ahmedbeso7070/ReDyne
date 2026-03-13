import Foundation

/// Service that reconstructs Swift nominal types from Mach-O metadata sections
/// and symbol table information. Combines multiple data sources:
///   - SwiftMetadata.c parsed `__swift5_types`, `__swift5_proto`, `__swift5_fieldmd`
///   - Symbol table type descriptors
///   - ObjC runtime class info (for mixed Swift/ObjC types)
///   - Demangled symbol names for type signatures
final class TypeReconstructionService {

    // MARK: - Public API

    /// Reconstruct types from all available analysis data.
    static func reconstruct(
        symbols: [SymbolModel],
        functions: [FunctionModel],
        swiftMetadata: SwiftMetadataAnalysis?,
        objcClasses: [String]?
    ) -> TypeReconstructionResults {

        var reconstructedTypes = [ReconstructedType]()

        // 1. Reconstruct from Swift metadata type descriptors
        if let metadata = swiftMetadata {
            let swiftTypes = reconstructFromSwiftMetadata(metadata)
            reconstructedTypes.append(contentsOf: swiftTypes)
        }

        // 2. Reconstruct from symbol table patterns
        let symbolTypes = reconstructFromSymbols(symbols)
        reconstructedTypes.append(contentsOf: symbolTypes)

        // 3. Infer types from ObjC class names
        if let objcNames = objcClasses {
            let objcTypes = reconstructFromObjCClasses(objcNames, symbols: symbols)
            reconstructedTypes.append(contentsOf: objcTypes)
        }

        // 4. Attach methods from function symbols
        attachMethods(to: &reconstructedTypes, functions: functions, symbols: symbols)

        // Deduplicate by name
        var seen = Set<String>()
        reconstructedTypes = reconstructedTypes.filter { type in
            if seen.contains(type.name) { return false }
            seen.insert(type.name)
            return true
        }

        let stats = TypeStatistics(types: reconstructedTypes)

        return TypeReconstructionResults(
            types: reconstructedTypes,
            statistics: stats,
            metadata: TypeMetadata()
        )
    }

    // MARK: - Swift Metadata Reconstruction

    private static func reconstructFromSwiftMetadata(_ metadata: SwiftMetadataAnalysis) -> [ReconstructedType] {
        var types = [ReconstructedType]()

        for typeInfo in metadata.types {
            let category = categoryFromSwiftKind(typeInfo.kindString)
            let type = ReconstructedType(
                name: typeInfo.name,
                category: category,
                size: 0,
                alignment: 8, // Default arm64 alignment
                virtualAddress: typeInfo.address,
                fileOffset: 0,
                confidence: 0.9,
                source: .runtimeMetadata
            )
            types.append(type)
        }

        // Add protocol conformance info as protocol types
        for conformance in metadata.conformances {
            if !types.contains(where: { $0.name == conformance.protocolName }) {
                let protoType = ReconstructedType(
                    name: conformance.protocolName,
                    category: .protocol,
                    size: 0,
                    alignment: 0,
                    virtualAddress: conformance.address,
                    fileOffset: 0,
                    confidence: 0.7,
                    source: .runtimeMetadata
                )
                types.append(protoType)
            }
        }

        return types
    }

    private static func categoryFromSwiftKind(_ kind: String) -> TypeCategory {
        switch kind.lowercased() {
        case "struct":    return .struct
        case "class":     return .class
        case "enum":      return .enum
        case "protocol":  return .protocol
        default:          return .unknown
        }
    }

    // MARK: - Symbol-Based Reconstruction

    private static func reconstructFromSymbols(_ symbols: [SymbolModel]) -> [ReconstructedType] {
        var types = [ReconstructedType]()
        var processedNames = Set<String>()

        for symbol in symbols {
            let displayName = symbol.demangledName ?? symbol.name

            // Type metadata accessor pattern: "type metadata accessor for <TypeName>"
            if displayName.contains("type metadata accessor for ") {
                let typeName = displayName
                    .replacingOccurrences(of: "type metadata accessor for ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                guard !typeName.isEmpty, !processedNames.contains(typeName) else { continue }
                processedNames.insert(typeName)

                let type = ReconstructedType(
                    name: typeName,
                    category: inferCategory(from: typeName, symbol: symbol),
                    size: 0,
                    alignment: 8,
                    virtualAddress: symbol.address,
                    fileOffset: 0,
                    confidence: 0.8,
                    source: .symbolTable
                )
                types.append(type)
            }

            // Nominal type descriptor pattern: "nominal type descriptor for <TypeName>"
            if displayName.contains("nominal type descriptor for ") {
                let typeName = displayName
                    .replacingOccurrences(of: "nominal type descriptor for ", with: "")
                    .trimmingCharacters(in: .whitespaces)

                guard !typeName.isEmpty, !processedNames.contains(typeName) else { continue }
                processedNames.insert(typeName)

                let type = ReconstructedType(
                    name: typeName,
                    category: inferCategory(from: typeName, symbol: symbol),
                    size: 0,
                    alignment: 8,
                    virtualAddress: symbol.address,
                    fileOffset: 0,
                    confidence: 0.85,
                    source: .symbolTable
                )
                types.append(type)
            }

            // Protocol witness table pattern
            if displayName.contains("protocol witness table for ") {
                if let range = displayName.range(of: " : ") {
                    let protocolName = String(displayName[range.upperBound...])
                        .trimmingCharacters(in: .whitespaces)
                    if !protocolName.isEmpty, !processedNames.contains(protocolName) {
                        processedNames.insert(protocolName)
                        let type = ReconstructedType(
                            name: protocolName,
                            category: .protocol,
                            size: 0,
                            alignment: 0,
                            virtualAddress: symbol.address,
                            fileOffset: 0,
                            confidence: 0.6,
                            source: .symbolTable
                        )
                        types.append(type)
                    }
                }
            }
        }

        return types
    }

    private static func inferCategory(from name: String, symbol: SymbolModel) -> TypeCategory {
        // Heuristic: if the demangled name pattern suggests a specific kind
        let demangled = symbol.demangledName ?? symbol.name

        if demangled.contains(".Type") || demangled.contains("Protocol") {
            return .protocol
        }

        // Default to class for ObjC-originated, struct for Swift-originated
        if symbol.name.hasPrefix("_OBJC_CLASS_$") || symbol.name.hasPrefix("_OBJC_METACLASS_$") {
            return .class
        }

        return .struct // Default for Swift types
    }

    // MARK: - ObjC Class Reconstruction

    private static func reconstructFromObjCClasses(_ classNames: [String], symbols: [SymbolModel]) -> [ReconstructedType] {
        return classNames.compactMap { name in
            guard !name.isEmpty else { return nil }

            // Find the symbol address for this class
            let classSymbolName = "_OBJC_CLASS_$_\(name)"
            let address = symbols.first { $0.name == classSymbolName }?.address ?? 0

            return ReconstructedType(
                name: name,
                category: .class,
                size: 0,
                alignment: 8,
                virtualAddress: address,
                fileOffset: 0,
                confidence: 0.95,
                source: .runtimeMetadata
            )
        }
    }

    // MARK: - Method Attachment

    private static func attachMethods(
        to types: inout [ReconstructedType],
        functions: [FunctionModel],
        symbols: [SymbolModel]
    ) {
        // Build a map of type name -> index for fast lookup
        var typeIndexMap = [String: Int]()
        for (index, type) in types.enumerated() {
            typeIndexMap[type.name] = index
        }

        for function in functions {
            let displayName = function.demangledName ?? function.name

            // Match "TypeName.methodName" patterns in demangled names
            // e.g. "MyApp.ViewController.viewDidLoad() -> ()"
            let components = displayName.split(separator: ".")
            guard components.count >= 2 else { continue }

            // Try progressively longer prefixes as the type name
            for splitAt in 1..<components.count {
                let potentialType = components[0..<splitAt].joined(separator: ".")
                if let typeIndex = typeIndexMap[potentialType] {
                    let methodName = components[splitAt...].joined(separator: ".")
                    let method = TypeMethod(
                        name: methodName,
                        signature: displayName,
                        returnType: "Void",
                        parameters: [],
                        virtualAddress: function.startAddress
                    )
                    types[typeIndex].methods.append(method)
                    break
                }
            }
        }
    }
}
