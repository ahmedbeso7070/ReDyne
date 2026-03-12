import Foundation

// MARK: - Swift Metadata Models

@objc class SwiftTypeInfo: NSObject {
    @objc let name: String
    @objc let mangledName: String
    @objc let kindString: String
    @objc let address: UInt64
    @objc let fieldCount: UInt32
    @objc let flags: UInt32
    @objc let isGeneric: Bool
    @objc let hasVTable: Bool

    init(name: String, mangledName: String, kindString: String, address: UInt64,
         fieldCount: UInt32, flags: UInt32, isGeneric: Bool, hasVTable: Bool) {
        self.name = name
        self.mangledName = mangledName
        self.kindString = kindString
        self.address = address
        self.fieldCount = fieldCount
        self.flags = flags
        self.isGeneric = isGeneric
        self.hasVTable = hasVTable
    }
}

@objc class SwiftConformanceInfo: NSObject {
    @objc let typeName: String
    @objc let protocolName: String
    @objc let address: UInt64

    init(typeName: String, protocolName: String, address: UInt64) {
        self.typeName = typeName
        self.protocolName = protocolName
        self.address = address
    }
}

@objc class SwiftFieldInfo: NSObject {
    @objc let name: String
    @objc let typeName: String
    @objc let ownerName: String
    @objc let isMutable: Bool
    @objc let isIndirect: Bool

    init(name: String, typeName: String, ownerName: String, isMutable: Bool, isIndirect: Bool) {
        self.name = name
        self.typeName = typeName
        self.ownerName = ownerName
        self.isMutable = isMutable
        self.isIndirect = isIndirect
    }
}

@objc class SwiftMetadataAnalysis: NSObject {
    @objc let types: [SwiftTypeInfo]
    @objc let conformances: [SwiftConformanceInfo]
    @objc let fields: [SwiftFieldInfo]

    @objc let totalClasses: UInt32
    @objc let totalStructs: UInt32
    @objc let totalEnums: UInt32
    @objc let totalProtocols: UInt32
    @objc let totalConformances: UInt32
    @objc let totalFields: UInt32

    @objc let hasSwiftMetadata: Bool

    init(types: [SwiftTypeInfo], conformances: [SwiftConformanceInfo], fields: [SwiftFieldInfo],
         totalClasses: UInt32, totalStructs: UInt32, totalEnums: UInt32,
         totalProtocols: UInt32, totalConformances: UInt32, totalFields: UInt32,
         hasSwiftMetadata: Bool) {
        self.types = types
        self.conformances = conformances
        self.fields = fields
        self.totalClasses = totalClasses
        self.totalStructs = totalStructs
        self.totalEnums = totalEnums
        self.totalProtocols = totalProtocols
        self.totalConformances = totalConformances
        self.totalFields = totalFields
        self.hasSwiftMetadata = hasSwiftMetadata
    }
}

// MARK: - Swift Metadata Service

@objc class SwiftMetadataService: NSObject {

    /// Parse Swift metadata from a Mach-O binary at the given path.
    /// Uses the DecompiledOutput sections to locate __swift5_* sections,
    /// then calls the C parser to extract type descriptors, conformances, and fields.
    @objc static func parseSwiftMetadata(atPath filePath: String, sections: [SectionModel], is64Bit: Bool) -> SwiftMetadataAnalysis? {
        guard !filePath.isEmpty else { return nil }

        // Open the file
        guard let file = fopen(filePath, "rb") else { return nil }
        defer { fclose(file) }

        // Get file size
        fseek(file, 0, SEEK_END)
        let fileSize = UInt64(ftell(file))
        fseek(file, 0, SEEK_SET)

        guard fileSize > 0 else { return nil }

        // Convert SectionModel array to C SectionInfo array
        var sectionInfos = sections.map { section -> SectionInfo in
            var info = SectionInfo()

            // Copy section name (up to 16 chars)
            let sectNameBytes = Array(section.sectionName.utf8.prefix(15))
            withUnsafeMutableBytes(of: &info.sectname) { buf in
                for i in 0..<min(sectNameBytes.count, 15) {
                    buf[i] = sectNameBytes[i]
                }
                // Null terminate
                for i in sectNameBytes.count..<16 {
                    buf[i] = 0
                }
            }

            // Copy segment name (up to 16 chars)
            let segNameBytes = Array(section.segmentName.utf8.prefix(15))
            withUnsafeMutableBytes(of: &info.segname) { buf in
                for i in 0..<min(segNameBytes.count, 15) {
                    buf[i] = segNameBytes[i]
                }
                for i in segNameBytes.count..<16 {
                    buf[i] = 0
                }
            }

            info.addr = section.address
            info.size = section.size
            info.offset = section.offset
            info.align = 0
            info.reloff = 0
            info.nreloc = 0
            info.flags = 0

            return info
        }

        // Call the C parser
        let sectionCount = UInt32(sectionInfos.count)
        let resultPtr: UnsafeMutablePointer<SwiftMetadataResult>? = sectionInfos.withUnsafeMutableBufferPointer { buf in
            guard let baseAddress = buf.baseAddress else { return nil }
            return swift_metadata_parse(file, baseAddress, sectionCount, fileSize, is64Bit)
        }

        guard let resultPtr = resultPtr else { return nil }
        defer { swift_metadata_free(resultPtr) }

        let result = resultPtr.pointee

        // Convert types
        var types: [SwiftTypeInfo] = []
        if let cTypes = result.types {
            for i in 0..<Int(result.typeCount) {
                let td = cTypes[i]
                let name = td.name != nil ? String(cString: td.name) : "<unknown>"
                let mangledName = td.mangledName != nil ? String(cString: td.mangledName) : ""
                let kindStr = String(cString: swift_type_kind_string(td.kind))

                types.append(SwiftTypeInfo(
                    name: name,
                    mangledName: mangledName,
                    kindString: kindStr,
                    address: td.address,
                    fieldCount: td.fieldCount,
                    flags: td.flags,
                    isGeneric: td.isGeneric,
                    hasVTable: td.hasVTable
                ))
            }
        }

        // Convert conformances
        var conformances: [SwiftConformanceInfo] = []
        if let cConf = result.conformances {
            for i in 0..<Int(result.conformanceCount) {
                let pc = cConf[i]
                let typeName = pc.typeName != nil ? String(cString: pc.typeName) : "<unknown>"
                let protoName = pc.protocolName != nil ? String(cString: pc.protocolName) : "<unknown>"

                conformances.append(SwiftConformanceInfo(
                    typeName: typeName,
                    protocolName: protoName,
                    address: pc.address
                ))
            }
        }

        // Convert fields
        var fields: [SwiftFieldInfo] = []
        if let cFields = result.fields {
            for i in 0..<Int(result.fieldCount) {
                let fd = cFields[i]
                let name = fd.name != nil ? String(cString: fd.name) : "<unknown>"
                let typeName = fd.typeName != nil ? String(cString: fd.typeName) : "<unknown>"
                let ownerName = fd.ownerName != nil ? String(cString: fd.ownerName) : "<unknown>"

                fields.append(SwiftFieldInfo(
                    name: name,
                    typeName: typeName,
                    ownerName: ownerName,
                    isMutable: fd.isMutable,
                    isIndirect: fd.isIndirect
                ))
            }
        }

        return SwiftMetadataAnalysis(
            types: types,
            conformances: conformances,
            fields: fields,
            totalClasses: result.totalClasses,
            totalStructs: result.totalStructs,
            totalEnums: result.totalEnums,
            totalProtocols: result.totalProtocols,
            totalConformances: result.conformanceCount,
            totalFields: result.fieldCount,
            hasSwiftMetadata: result.hasSwiftMetadata
        )
    }
}
