import Foundation

@objc class ImportExportAnalyzer: NSObject {
    
    @objc static func analyze(machOContext: OpaquePointer) -> ImportExportAnalysis? {
        let ctx = UnsafeMutablePointer<MachOContext>(machOContext)
        
        
        guard let importListPtr = dyld_parse_imports(ctx) else {

            return nil
        }
        defer { dyld_free_imports(importListPtr) }
        
        let importList = importListPtr.pointee
        var imports: [ImportedSymbol] = []
        
        if importList.import_count > 0, let importsPtr = importList.imports {
            let importsBuffer = UnsafeBufferPointer<ImportInfo>(start: importsPtr, count: Int(importList.import_count))
            for importInfo in importsBuffer {
                if let symbol = convertImport(importInfo) {
                    imports.append(symbol)
                }
            }
        }
        
        // Also parse chained fixups for modern binaries (iOS 15+)
        if ctx.pointee.has_chained_fixups {
            if let chainedResult = chained_fixups_parse(ctx) {
                let result = chainedResult.pointee
                if result.fixup_count > 0, let fixups = result.fixups {
                    for i in 0..<Int(result.fixup_count) {
                        let fixup = fixups[i]
                        if fixup.is_bind {
                            let name = withUnsafePointer(to: fixup.symbol_name) {
                                $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
                            }
                            if !name.isEmpty {
                                let symbol = ImportedSymbol(
                                    name: name,
                                    libraryName: "",
                                    libraryOrdinal: Int(fixup.lib_ordinal),
                                    address: fixup.address,
                                    bindType: .pointer,
                                    isWeak: fixup.is_weak,
                                    addend: fixup.addend
                                )
                                // Only add if not already present from dyld_info parsing
                                if !imports.contains(where: { $0.name == name && $0.address == fixup.address }) {
                                    imports.append(symbol)
                                }
                            }
                        }
                    }
                }
                chained_fixups_free(chainedResult)
            }
        }


        guard let exportListPtr = dyld_parse_exports(ctx) else {
            return nil
        }
        defer { dyld_free_exports(exportListPtr) }
        
        let exportList = exportListPtr.pointee
        var exports: [ExportedSymbol] = []
        
        if exportList.export_count > 0, let exportsPtr = exportList.exports {
            let exportsBuffer = UnsafeBufferPointer<ExportInfo>(start: exportsPtr, count: Int(exportList.export_count))
            for exportInfo in exportsBuffer {
                if let symbol = convertExport(exportInfo) {
                    exports.append(symbol)
                }
            }
        }
        
        
        guard let libraryListPtr = dyld_parse_libraries(ctx) else {
            return nil
        }
        defer { dyld_free_libraries(libraryListPtr) }
        
        let libraryList = libraryListPtr.pointee
        var libraries: [String] = []
        
        if libraryList.library_count > 0, let libraryNamesPtr = libraryList.library_names {
            for i in 0..<Int(libraryList.library_count) {
                if let libNamePtr = libraryNamesPtr[i] {
                    let libName = String(cString: libNamePtr)
                    libraries.append(libName)
                }
            }
        }
        
        
        var dependencyLibraries: [LinkedLibrary] = []
        if libraryList.library_count > 0 {
            for i in 0..<Int(libraryList.library_count) {
                if let libName = libraryList.library_names?[i] {
                    let path = String(cString: libName)
                    let timestamp = libraryList.timestamps?[i] ?? 0
                    let currentVer = libraryList.current_versions?[i] ?? 0
                    let compatVer = libraryList.compatibility_versions?[i] ?? 0
                    
                    let lib = LinkedLibrary(
                        path: path,
                        timestamp: timestamp,
                        currentVersion: currentVer,
                        compatibilityVersion: compatVer
                    )
                    dependencyLibraries.append(lib)
                }
            }
        }
        
        let dependencyAnalysis = DependencyAnalysis(libraries: dependencyLibraries)
        
        let analysis = ImportExportAnalysis(
            imports: imports,
            exports: exports,
            linkedLibraries: libraries,
            dependencyAnalysis: dependencyAnalysis
        )
        
        return analysis
    }
    
    // MARK: - Conversion Helpers
    
    private static func convertImport(_ importInfo: ImportInfo) -> ImportedSymbol? {
        var infoCopy = importInfo
        
        let name = withUnsafePointer(to: &infoCopy.name.0) { String(cString: $0) }
        let libraryName = withUnsafePointer(to: &infoCopy.library_name.0) { String(cString: $0) }
        
        let bindType: BindType
        switch infoCopy.bind_type {
        case 1: bindType = .pointer
        case 2: bindType = .textAbsolute32
        case 3: bindType = .textPCrel32
        default: bindType = .pointer
        }
        
        return ImportedSymbol(
            name: name,
            libraryName: libraryName,
            libraryOrdinal: Int(infoCopy.library_ordinal),
            address: infoCopy.address,
            bindType: bindType,
            isWeak: infoCopy.is_weak,
            addend: infoCopy.addend
        )
    }
    
    private static func convertExport(_ exportInfo: ExportInfo) -> ExportedSymbol? {
        var infoCopy = exportInfo
        
        let name = withUnsafePointer(to: &infoCopy.name.0) { String(cString: $0) }
        let reexportLib = withUnsafePointer(to: &infoCopy.reexport_lib.0) { String(cString: $0) }
        let reexportName = withUnsafePointer(to: &infoCopy.reexport_name.0) { String(cString: $0) }
        
        return ExportedSymbol(
            name: name,
            address: infoCopy.address,
            flags: infoCopy.flags,
            isReexport: infoCopy.is_reexport,
            reexportLibraryName: reexportLib,
            reexportSymbolName: reexportName,
            isWeakDef: infoCopy.is_weak_def,
            isThreadLocal: infoCopy.is_thread_local
        )
    }
}

