import Foundation

// MARK: - C Function Declarations

/// Swift runtime demangling function
@_silgen_name("swift_demangle")
private func _swift_demangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ mangledNameLength: Int,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ outputBufferSize: UnsafeMutablePointer<Int>?,
    _ flags: UInt32
) -> UnsafeMutablePointer<CChar>?

/// C++ ABI demangling function
@_silgen_name("__cxa_demangle")
private func cxa_demangle(
    _ mangledName: UnsafePointer<CChar>?,
    _ outputBuffer: UnsafeMutablePointer<CChar>?,
    _ length: UnsafeMutablePointer<Int>?,
    _ status: UnsafeMutablePointer<Int32>?
) -> UnsafeMutablePointer<CChar>?

// MARK: - SwiftDemangler

/// Service for demangling Swift and C++ symbol names from Mach-O binaries.
/// Uses the Swift runtime's built-in `swift_demangle` and libc's `__cxa_demangle`.
final class SwiftDemangler {

    // MARK: - Swift Mangled Name Prefixes

    private static let swiftPrefixes: [String] = [
        "$s", "$S",       // Modern Swift mangling
        "_$s", "_$S",     // With leading underscore
        "_T0",            // Swift 4+ mangling
        "_Tt",            // ObjC-style Swift type metadata
        "_TF", "_TW", "_TC", "_TV", "_TS"  // Legacy Swift mangling
    ]

    // MARK: - Public API

    /// Demangle a single symbol name.
    /// Returns the demangled name, or the original if demangling fails or the symbol is not mangled.
    static func demangle(_ name: String) -> String {
        guard !name.isEmpty else { return name }

        // Check for Swift mangled names
        if isSwiftMangled(name) {
            if let demangled = demangleSwift(name) {
                return demangled
            }
        }

        // Check for C++ mangled names (_Z or __Z prefix)
        if isCppMangled(name) {
            if let demangled = demangleCpp(name) {
                return demangled
            }
        }

        return name
    }

    /// Demangle all symbols in an array in place.
    static func demangleSymbols(_ symbols: [SymbolModel]) {
        for symbol in symbols {
            symbol.demangledName = demangle(symbol.name)
        }
    }

    // MARK: - Detection

    private static func isSwiftMangled(_ name: String) -> Bool {
        for prefix in swiftPrefixes {
            if name.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    private static func isCppMangled(_ name: String) -> Bool {
        return name.hasPrefix("_Z") || name.hasPrefix("__Z")
    }

    // MARK: - Demangling Implementations

    private static func demangleSwift(_ name: String) -> String? {
        return name.withCString { cString in
            let length = strlen(cString)
            guard let result = _swift_demangle(cString, length, nil, nil, 0) else {
                return nil
            }
            let demangled = String(cString: result)
            free(result)
            // Only return if actually different from input
            guard demangled != name else { return nil }
            return demangled
        }
    }

    private static func demangleCpp(_ name: String) -> String? {
        return name.withCString { cString in
            var status: Int32 = 0
            guard let result = cxa_demangle(cString, nil, nil, &status) else {
                return nil
            }
            guard status == 0 else {
                free(result)
                return nil
            }
            let demangled = String(cString: result)
            free(result)
            guard demangled != name else { return nil }
            return demangled
        }
    }
}
