import Foundation

// MARK: - Binary Patch

struct BinaryPatch: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String?
    var severity: Severity
    var fileOffset: UInt64
    var virtualAddress: UInt64
    var originalBytes: Data
    var patchedBytes: Data
    var enabled: Bool
    var status: Status
    var createdAt: Date
    var updatedAt: Date
    var checksum: String
    var notes: String?
    var verificationMessage: String?
    var expectedUUID: UUID?
    var expectedArchitecture: String?
    var tags: [String]

    enum Status: String, Codable {
        case draft
        case ready
        case pending
        case applied
        case verified
        case failed
        case reverted
    }

    enum Severity: String, Codable {
        case info
        case low
        case medium
        case high
        case critical
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        severity: Severity = .medium,
        status: Status = .draft,
        enabled: Bool = true,
        virtualAddress: UInt64 = 0,
        fileOffset: UInt64,
        originalBytes: Data,
        patchedBytes: Data,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        checksum: String = "",
        notes: String? = nil,
        expectedUUID: UUID? = nil,
        expectedArchitecture: String? = nil,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.severity = severity
        self.status = status
        self.enabled = enabled
        self.virtualAddress = virtualAddress
        self.fileOffset = fileOffset
        self.originalBytes = originalBytes
        self.patchedBytes = patchedBytes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.checksum = checksum
        self.notes = notes
        self.verificationMessage = nil
        self.expectedUUID = expectedUUID
        self.expectedArchitecture = expectedArchitecture
        self.tags = tags
    }
}

// MARK: - Binary Patch Set

struct BinaryPatchSet: Codable, Identifiable {
    let id: UUID
    var name: String
    var description: String?
    var author: String?
    var patches: [BinaryPatch]
    var auditLog: [BinaryPatchAuditEntry]
    var status: Status
    var updatedAt: Date
    var targetPath: String?
    var targetUUID: UUID?
    var targetArchitecture: String?
    var tags: [String]

    var version: String

    enum Status: String, Codable {
        case draft
        case ready
        case applied
        case verified
        case failed
        case archived
    }

    var enabledPatchCount: Int {
        patches.filter { $0.enabled }.count
    }

    var patchCount: Int {
        patches.count
    }

    init(
        id: UUID = UUID(),
        name: String,
        description: String? = nil,
        author: String? = nil,
        patches: [BinaryPatch] = [],
        targetPath: String? = nil,
        targetUUID: UUID? = nil,
        targetArchitecture: String? = nil,
        tags: [String] = [],
        version: String = "1.0"
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.author = author
        self.patches = patches
        self.auditLog = []
        self.status = .draft
        self.updatedAt = Date()
        self.targetPath = targetPath
        self.targetUUID = targetUUID
        self.targetArchitecture = targetArchitecture
        self.tags = tags
        self.version = version
    }
}

// MARK: - Audit Entry

struct BinaryPatchAuditEntry: Codable {
    let timestamp: Date
    let user: String?
    let event: EventType
    let patchID: UUID?
    let details: String
    let metadata: [String: String]

    enum EventType: String, Codable {
        case created
        case updated
        case deleted
        case applied
        case reverted
        case verified
    }
}

// MARK: - Patch Template

struct PatchTemplate {
    let name: String
    let description: String
    let category: Category
    let difficulty: Difficulty
    let icon: String
    let author: String?
    let tags: [String]
    let instructions: [String]

    enum Category: String, CaseIterable {
        case security = "Security"
        case debugging = "Debugging"
        case tweaking = "Tweaking"
        case analysis = "Analysis"
        case restoration = "Restoration"

        var icon: String {
            switch self {
            case .security: return "shield.checkered"
            case .debugging: return "ladybug"
            case .tweaking: return "slider.horizontal.3"
            case .analysis: return "magnifyingglass.circle"
            case .restoration: return "arrow.counterclockwise"
            }
        }
    }

    enum Difficulty: String, Codable {
        case beginner = "Beginner"
        case intermediate = "Intermediate"
        case advanced = "Advanced"
        case expert = "Expert"
    }
}

// MARK: - Template Instruction

struct TemplateInstruction {
    let step: Int
    let title: String
    let detail: String
}

// MARK: - Patch Template Library

final class PatchTemplateLibrary {
    static let shared = PatchTemplateLibrary()

    let templates: [PatchTemplate]

    private init() {
        templates = [
            PatchTemplate(
                name: "Disable SSL Pinning",
                description: "Bypasses certificate pinning for network debugging.",
                category: .debugging,
                difficulty: .intermediate,
                icon: "lock.open",
                author: "ReDyne",
                tags: ["ssl", "network", "debugging"],
                instructions: [
                    "Locate the SSL pinning validation function",
                    "Find the branch instruction that checks the certificate",
                    "Replace the conditional branch with a NOP or unconditional branch to the success path"
                ]
            ),
            PatchTemplate(
                name: "Bypass Jailbreak Detection",
                description: "Disables common jailbreak detection checks.",
                category: .security,
                difficulty: .intermediate,
                icon: "shield.slash",
                author: "ReDyne",
                tags: ["jailbreak", "security", "bypass"],
                instructions: [
                    "Search for file existence checks (/Applications/Cydia.app, etc.)",
                    "Locate the detection function's return instruction",
                    "Patch to always return false/0"
                ]
            ),
            PatchTemplate(
                name: "Enable Debug Logging",
                description: "Re-enables disabled debug logging statements.",
                category: .debugging,
                difficulty: .beginner,
                icon: "text.alignleft",
                author: "ReDyne",
                tags: ["logging", "debug"],
                instructions: [
                    "Find the logging configuration function",
                    "Locate the log level comparison",
                    "Set the minimum log level to verbose/debug"
                ]
            ),
            PatchTemplate(
                name: "Remove Encryption Check",
                description: "Bypasses binary encryption validation for analysis.",
                category: .analysis,
                difficulty: .advanced,
                icon: "lock.shield",
                author: "ReDyne",
                tags: ["encryption", "fairplay", "analysis"],
                instructions: [
                    "Locate the LC_ENCRYPTION_INFO load command",
                    "Set cryptid field to 0",
                    "Verify the binary loads correctly"
                ]
            ),
            PatchTemplate(
                name: "NOP Function Call",
                description: "Replaces a function call with NOP instructions (ARM64).",
                category: .tweaking,
                difficulty: .beginner,
                icon: "xmark.circle",
                author: "ReDyne",
                tags: ["nop", "arm64", "basic"],
                instructions: [
                    "Navigate to the BL/BLR instruction you want to remove",
                    "Note the 4-byte instruction at that offset",
                    "Replace with NOP: 1F 20 03 D5"
                ]
            ),
            PatchTemplate(
                name: "Force Function Return Value",
                description: "Forces a function to always return a specific value (ARM64).",
                category: .tweaking,
                difficulty: .intermediate,
                icon: "arrow.uturn.left",
                author: "ReDyne",
                tags: ["return", "arm64", "patch"],
                instructions: [
                    "Find the target function's entry point",
                    "Replace the first instructions with: MOV W0, #value; RET",
                    "For return true: 20 00 80 52 C0 03 5F D6",
                    "For return false: 00 00 80 52 C0 03 5F D6"
                ]
            ),
            PatchTemplate(
                name: "Restore Original Bytes",
                description: "Reverts a previously applied patch to original bytes.",
                category: .restoration,
                difficulty: .beginner,
                icon: "arrow.counterclockwise",
                author: "ReDyne",
                tags: ["restore", "revert", "undo"],
                instructions: [
                    "Identify the patch to revert from the patch audit log",
                    "Verify the current bytes match the patched bytes",
                    "Write the original bytes back to the file offset"
                ]
            )
        ]
    }

    func templates(for category: PatchTemplate.Category) -> [PatchTemplate] {
        templates.filter { $0.category == category }
    }

    func search(query: String) -> [PatchTemplate] {
        let lowered = query.lowercased()
        return templates.filter {
            $0.name.lowercased().contains(lowered) ||
            $0.description.lowercased().contains(lowered) ||
            $0.tags.contains { $0.lowercased().contains(lowered) }
        }
    }
}

// MARK: - MachO Utilities

enum MachOUtilities {
    static func uuidForBinary(at path: String) throws -> UUID {
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "MachOUtilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }

        var errorMsg = [CChar](repeating: 0, count: 256)
        guard let ctx = macho_open(path, &errorMsg) else {
            throw NSError(domain: "MachOUtilities", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not a valid Mach-O"])
        }
        defer { macho_close(ctx) }

        macho_parse_load_commands(ctx)

        let uuidBytes = withUnsafePointer(to: ctx.pointee.uuid) { ptr -> [UInt8] in
            let raw = UnsafeRawPointer(ptr)
            return Array(UnsafeBufferPointer(start: raw.assumingMemoryBound(to: UInt8.self), count: 16))
        }

        guard uuidBytes.contains(where: { $0 != 0 }) else {
            throw NSError(domain: "MachOUtilities", code: 4, userInfo: [NSLocalizedDescriptionKey: "No UUID found"])
        }

        let uuidString = String(format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
                                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15])
        guard let uuid = UUID(uuidString: uuidString) else {
            throw NSError(domain: "MachOUtilities", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID"])
        }
        return uuid
    }

    static func checksumForBinary(at path: String) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "MachOUtilities", code: 1, userInfo: [NSLocalizedDescriptionKey: "File not found"])
        }

        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw NSError(domain: "MachOUtilities", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot open file"])
        }
        defer { handle.closeFile() }

        let data = handle.readData(ofLength: 1024)
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(format: "%016llX", hash)
    }

    static func architectureForBinary(at path: String) throws -> String {
        var errorMsg = [CChar](repeating: 0, count: 256)
        guard let ctx = macho_open(path, &errorMsg) else {
            throw NSError(domain: "MachOUtilities", code: 3, userInfo: [NSLocalizedDescriptionKey: "Not a valid Mach-O"])
        }
        defer { macho_close(ctx) }

        let cpuType = ctx.pointee.header.cputype
        let cpuSubtype = ctx.pointee.header.cpusubtype

        switch cpuType {
        case 0x0100000C: // CPU_TYPE_ARM64
            if cpuSubtype == 2 { return "ARM64e" }
            return "ARM64"
        case 12: // CPU_TYPE_ARM
            return "ARM"
        case 0x01000007: // CPU_TYPE_X86_64
            return "X86_64"
        case 7: // CPU_TYPE_I386
            return "i386"
        default:
            return "Unknown (\(cpuType))"
        }
    }
}
