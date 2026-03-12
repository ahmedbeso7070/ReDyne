# ReDyne

<div align="center">

**A Production-Grade iOS Decompiler & Reverse Engineering Suite**

[![Platform](https://img.shields.io/badge/platform-iOS%2016.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

*Deep Mach-O analysis, ARM64 disassembly, security posture analysis, control flow graphs, and 15+ advanced reverse engineering tools — all native on iOS.*

[Features](#features) • [Installation](#installation) • [Usage](#usage) • [Architecture](#architecture) • [Contributing](#contributing)

</div>

---

## Overview

ReDyne is a comprehensive, native iOS application for reverse engineering and analyzing Mach-O binaries (dylibs, frameworks, executables). Built from the ground up with production-grade C/Objective-C/Swift, it brings desktop-class binary analysis capabilities to iOS devices.

### Why ReDyne?

- **Production-Grade**: ~38,100 LOC, zero build errors, zero warnings
- **Native iOS**: Optimized for iPhone and iPad with adaptive layouts
- **High Performance**: C-based parsing engines with bounds-checked, hardened parsers
- **Comprehensive**: 15+ analysis modules covering every aspect of Mach-O binaries
- **Modern Binary Support**: Full iOS 15+ chained fixups, Swift metadata, ARM64e
- **Security Analysis**: Binary security posture with 18 inspection rules
- **Visual Analysis**: Interactive control flow graphs, call graphs, hex viewer
- **Professional Reports**: HTML report generation with CSS styling

---

## Features

### Mach-O Binary Analysis
- **Universal Binary Support**: Automatic fat/thin binary detection
- **Multi-Architecture**: ARM64, ARM64e, x86_64 support
- **Complete Load Commands**: LC_MAIN, LC_FUNCTION_STARTS, LC_BUILD_VERSION, LC_SOURCE_VERSION, LC_RPATH, LC_DYLD_CHAINED_FIXUPS, LC_VERSION_MIN_*, and 30+ more
- **Segments & Sections**: Detailed analysis with protection flags, size, and offset mapping
- **Parse Warning System**: Non-fatal issues reported without crashing
- **Bounds Checking**: All parsers hardened against malformed input

### Disassembly Engine
- **ARM64 Disassembler**: Production-grade decoder with 100+ instruction types
  - Data Processing (ADD, SUB, MOV, MOVZ, MOVN, MOVK)
  - Load/Store (LDR, STR, LDP, STP, LDUR, STUR)
  - Branches (B, BL, BR, BLR, RET, B.cond, CBZ, CBNZ, TBZ, TBNZ)
  - Logical, Multiply/Divide, Compare, Shift, SIMD/FP, System instructions
- **100K Instruction Display**: Paginated for large binaries
- **Branch Detection**: Automatic identification of control flow changes
- **Cross-View Navigation**: Tap any address to jump to disassembly, hex, or symbol

### Swift & C++ Symbol Demangling
- **Swift Runtime Demangling**: Uses `swift_demangle` for `$s`, `_$s`, `_T0`, `_Tt` prefixed symbols
- **C++ Demangling**: Uses `__cxa_demangle` for `_Z` prefixed symbols
- **Searchable**: Both mangled and demangled names are searchable
- **Applied Everywhere**: Symbols, functions, cross-references, pseudocode

### Security Posture Analysis
- **Binary Hardening Checks**: PIE, ARC, stack canaries, NX heap/stack, code signing, encryption
- **Dangerous API Detection**: system, popen, dlopen, exec*, fork, ptrace, task_for_pid
- **Insecure Function Detection**: gets, strcpy, strcat, sprintf, scanf, alloca
- **Dangerous Entitlements**: get-task-allow, task_for_pid-allow, private APIs
- **Posture Rating**: Good / Fair / Concerning / Poor with severity breakdown
- **Rule-Based Inspection**: 18 built-in rules across security, quality, compatibility, performance

### Cross-Reference Analysis
- **Call Graphs**: Visual function call relationship graphs with Core Graphics rendering
- **Jump Analysis**: Branch target tracking and following
- **Data References**: Symbol and address resolution
- **Symbolic Execution**: ADRP+ADD pattern recognition
- **Interactive Navigation**: Tap any xref to jump to source or target

### Control Flow Graphs (CFG)
- **Hierarchical Layout**: BFS-based level assignment
- **Basic Block Analysis**: Automatic BB detection and splitting
- **Edge Classification**: True/false branches, loop-backs, calls, returns
- **Interactive Visualization**: Pinch-to-zoom, pan, auto-fit
- **Color-Coded**: Entry (blue), exit (red), conditional (orange)

### Swift Metadata Parsing
- **Type Descriptors**: Parse `__swift5_types` for classes, structs, enums
- **Protocol Conformances**: Parse `__swift5_proto` for protocol relationships
- **Field Descriptors**: Parse `__swift5_fieldmd` for stored properties
- **Relative Pointer Resolution**: Proper Swift 5 relative pointer following

### Hex Viewer
- **Standard Layout**: Offset | 16 hex bytes (8+8 columns) | ASCII
- **Virtual Scrolling**: Handles files of any size efficiently
- **Section Color Coding**: Different background tints per section
- **Go to Offset**: Jump to any hex or decimal offset
- **Null Byte Dimming**: Visual distinction for zero bytes

### LC_DYLD_CHAINED_FIXUPS
- **Modern iOS 15+ Support**: Full chained fixups parsing
- **All Pointer Formats**: ARM64E, PTR_64, PTR_64_OFFSET variants
- **Import Parsing**: DYLD_CHAINED_IMPORT, ADDEND, ADDEND64 formats
- **Chain Walking**: Segment/page traversal with bounds checking

### Objective-C Runtime
- **Class Extraction**: Parse `__objc_classlist` sections
- **Method Discovery**: Instance and class methods
- **Property Analysis**: @property declarations with type encoding
- **Instance Variables**: ivar layouts
- **Categories & Protocols**: Full metadata extraction

### Import/Export Tables
- **Dyld Bind Info**: All 12 bind opcodes with ULEB128 decoding
- **Export Trie**: Recursive traversal with depth limiting
- **Chained Fixups Integration**: Modern binaries automatically use chained fixups
- **Library Dependencies**: Full dylib dependency tree with versions
- **100K Import/Export Capacity**: Handles large commercial binaries

### Code Signature Inspector
- **SuperBlob Parsing**: Proper blob index structure
- **CodeDirectory**: CDHash, Team ID, Signing ID
- **Entitlements**: XML parsing and formatting
- **Signature Type**: Ad-hoc vs full signing detection

### Binary Patching
- **Patch Sets**: Organize patches into named sets with versioning
- **Patch Templates**: Built-in templates for common operations (SSL pinning bypass, jailbreak detection, NOP insertion)
- **Verification**: Validate original bytes before applying patches
- **Audit Log**: Full history of all patch operations
- **Import/Export**: Share patch sets as JSON

### Pattern Scanner
- **Hex Pattern Search**: Search for byte sequences with `??` wildcards
- **ASCII String Search**: Auto-convert quoted strings to hex
- **Built-in Presets**: MH_MAGIC, NOP sled, RET, BRK patterns
- **Efficient Scanning**: FileHandle-based chunked search
- **Jump to Results**: Tap any match to view in hex viewer

### Global Search
- **Unified Search**: Symbols, strings, functions, classes, methods, imports, exports, sections, segments
- **Debounced Input**: 300ms delay for responsive search
- **Grouped Results**: Results organized by category with match counts
- **Navigation**: Tap any result to jump to its detail view

### Analysis Dashboard
- **Binary Summary Card**: File name, architecture, platform, UUID, entry point, PIE status
- **Statistics Grid**: Symbols, strings, instructions, functions, imports/exports, ObjC classes
- **Security Overview**: Posture rating, severity breakdown, dangerous API count
- **Quick Actions**: One-tap navigation to any analysis section

### Address Converter
- **Bidirectional Conversion**: File offset to VM address and vice versa
- **Section Resolution**: Shows segment, section, and protection flags
- **Nearest Symbol Lookup**: Finds closest symbol with offset delta
- **Quick Navigation**: Jump to hex viewer or disassembly from result

### Bookmarks & Annotations
- **Persistent Bookmarks**: Color-coded bookmarks at any address
- **Annotations**: Text comments at specific addresses
- **Per-Binary Storage**: Keyed by binary UUID
- **Quick Add**: Add from disassembly or symbol views

### Report Generation
- **Professional HTML Reports**: CSS-styled with print media queries
- **Complete Analysis**: All sections from binary overview to symbol tables
- **Share Integration**: Email, AirDrop, save to Files, print
- **Security Assessment**: Color-coded severity indicators

### iPad Support
- **Adaptive Sidebar**: 260pt sidebar navigation on regular-width devices
- **Synchronized Selection**: Sidebar and segmented control stay in sync
- **Full-Width Detail**: Content fills remaining space

### Binary Comparison
- **Symbol Diff**: Added, removed, and modified symbols
- **ObjC Class Diff**: Class additions, removals, method count changes
- **Security Comparison**: Posture regression detection
- **Import/Export Diff**: New and removed dependencies
- **Segment Size Comparison**: Size changes with delta indicators

### Export Formats
- **TXT**: Clean, readable text format
- **JSON**: Structured JSON with full metadata
- **HTML**: Styled HTML with syntax highlighting
- **PDF**: Multi-page PDF with professional typography
- **Analysis Report**: Comprehensive HTML report with all analysis data
- **Share Sheet**: Native iOS sharing integration

---

## Architecture

### Technology Stack

```
┌─────────────────────────────────────────────────────┐
│                    UI Layer (Swift/UIKit)           │
│  28 ViewControllers • Adaptive iPad Layout          │
│  Dashboard • Search • HexViewer • CallGraph • CFG   │
├─────────────────────────────────────────────────────┤
│                  Services Layer (Swift)             │
│  16 Services • Demangling • CFG • Xref • Reports    │
│  BookmarkStore • InspectionRules • PatchService     │
├─────────────────────────────────────────────────────┤
│               Bridge Layer (Objective-C)            │
│  BinaryParserService • DisassemblerService          │
│  ObjCParserBridge • EnhancedFilePicker              │
├─────────────────────────────────────────────────────┤
│               Core Parsing Layer (C)                │
│  15 Modules • Bounds-Checked • Warning System       │
│  MachOHeader • DisassemblyEngine • SymbolTable      │
│  DyldInfo • ChainedFixups • SecurityAnalyzer        │
│  ObjCParser • SwiftMetadata • PseudocodeGenerator   │
│  ControlFlowGraph • CodeSignature • StringExtractor │
└─────────────────────────────────────────────────────┘
```

**Core Parsing (C) — 15 modules**
- `MachOHeader.c` — Mach-O header/command parsing with 30+ LC_* types
- `DisassemblyEngine.c` — ARM64 instruction decoding (100+ types)
- `SymbolTable.c` — Symbol table parsing with 500K cap
- `DyldInfo.c` — Dyld bind/rebase/export with depth-limited recursion
- `ChainedFixups.c` — iOS 15+ chained fixups (ARM64E, PTR_64)
- `SecurityAnalyzer.c` — Binary security posture analysis
- `SwiftMetadata.c` — Swift 5 type/protocol/field metadata
- `ObjCParser.c` — Objective-C runtime analysis
- `CodeSignature.c` — Code signature and entitlements
- `ControlFlowGraph.c` — CFG construction and optimization
- `PseudocodeGenerator.c` — High-level code reconstruction
- `StringExtractor.c` — C-string and CFString extraction
- `ARM64InstructionDecoder.c` — Instruction set decoder
- `RelocationInfo.c` — Relocation data parsing
- `ClassDumpC.c` — Objective-C class dumping

**Services (Swift) — 16 services**
- `SwiftDemangler.swift` — Swift/C++ symbol demangling
- `SecurityPostureService.swift` — Security analysis bridge
- `SwiftMetadataService.swift` — Swift metadata bridge
- `CFGAnalyzer.swift` — Control flow graph analysis
- `XrefAnalyzer.swift` — Cross-reference analysis
- `ImportExportAnalyzer.swift` — Import/export with chained fixups
- `BookmarkStore.swift` — Persistent bookmarks/annotations
- `InspectionRuleEngine.swift` — 18-rule binary inspection
- `ReportGenerator.swift` — HTML report generation
- `ExportService.swift` — Multi-format data export
- `BinaryPatchService.swift` — Patch set management
- `BinaryPatchEngine.swift` — Patch application engine

### Design Principles

- **Hardened Parsers**: All C code has bounds checking, fread validation, safety caps
- **Zero Trust Input**: Every file offset validated before reading
- **Graceful Degradation**: Parse failures generate warnings, not crashes
- **Memory Safety**: Proper ownership contracts across C/ObjC/Swift boundaries
- **Accessibility**: Dynamic Type, VoiceOver labels, accessibility traits

---

## Requirements

- **iOS**: 16.0 or later
- **Device**: iPhone or iPad
- **Storage**: ~50 MB app + space for analyzed files
- **Architectures**: ARM64 (device), x86_64 (simulator)

---

## Installation

### Building from Source

1. **Clone the Repository**
   ```bash
   git clone https://github.com/speedyfriend433/ReDyne.git
   cd ReDyne
   ```

2. **Open in Xcode**
   ```bash
   open ReDyne.xcodeproj
   ```

3. **Configure Signing**
   - Select your development team in Xcode
   - Update bundle identifier if needed

4. **Build and Run**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

### Requirements for Building
- Xcode 15.0+
- macOS 14.0+ (Sonoma)
- Active Apple account (for device testing)

---

## Usage

### Quick Start

1. **Launch ReDyne** on your iOS device
2. **Tap "Select Mach-O File"** to open the file picker (first launch shows onboarding)
3. **Choose a dylib/framework** to analyze
4. **Wait for analysis** — the pipeline processes 10+ stages with progress reporting
5. **Explore the Dashboard** — at-a-glance summary with stats, security, and quick actions
6. **Deep Dive** into any section: Symbols, Strings, Disassembly, Functions

### Analysis Tabs
- **Symbols**: Full symbol table with demangled names, filterable and searchable
- **Strings**: Extracted from `__cstring`, `__cfstring`, `__objc_methnames`, and more
- **Disassembly**: Annotated ARM64 instructions with branch following
- **Functions**: Detected function boundaries with pseudocode

### Advanced Analysis (15 tools)

Access via the ellipsis menu:

| Tool | Description |
|------|-------------|
| Cross-References | Function calls and references with navigation |
| ObjC Classes | Objective-C runtime classes, methods, properties |
| Imports/Exports | Imported and exported symbols with library info |
| Dependencies | Linked libraries with versions |
| Code Signature | Code signing details and entitlements |
| Control Flow Graphs | Visual CFG with zoom and pan |
| Call Graph | Function call relationship visualization |
| Memory Map | Visual segment/section layout with R/W/X filtering |
| Pseudocode | High-level code reconstruction |
| Security Posture | PIE, ARC, canaries, NX, dangerous APIs |
| Binary Patching | Apply and manage binary patches |
| Hex Viewer | Raw binary viewer with section colors |
| Address Converter | File offset / VM address resolver |
| Pattern Scanner | Byte pattern search with wildcards |
| Binary Inspection | 18-rule automated quality/security check |

### Cross-View Navigation
- **Symbol to Disassembly**: Tap a symbol, choose "View in Disassembly"
- **Follow Branches**: Tap a branch instruction to jump to its target
- **Xref Navigation**: Jump to source or target of any cross-reference
- **Hex View**: View any address in the hex viewer
- **Bookmarks**: Save addresses for quick return

### Global Search
Tap the magnifying glass to search across all analysis data — symbols, strings, functions, classes, methods, imports, exports, sections, and segments.

### Export & Reports
- Tap the share button to export as TXT, JSON, HTML, or PDF
- Choose "Analysis Report" for a comprehensive HTML report
- Share via AirDrop, Messages, Mail, or save to Files

---

## Statistics

**Codebase:**
- ~38,100 lines of C/Objective-C/Swift
- 15 C parsing modules
- 16 Swift service modules
- 28 view controllers
- 15 analysis types
- 100+ ARM64 instruction types
- 18 inspection rules

**Capabilities:**
- Analyze binaries up to 500MB
- Display 100,000+ disassembled instructions
- Parse 100,000+ imports/exports
- Demangle Swift and C++ symbols in real-time
- Generate professional HTML analysis reports
- Persistent bookmarks and annotations per binary

---

## Roadmap

**Completed:**
- [x] Mach-O parsing with 30+ load commands
- [x] ARM64 disassembly (100+ instruction types)
- [x] Swift symbol demangling
- [x] LC_DYLD_CHAINED_FIXUPS (iOS 15+)
- [x] Security posture analysis
- [x] Swift metadata parsing
- [x] Hex viewer
- [x] Bookmarks and annotations
- [x] Global search
- [x] Analysis dashboard
- [x] Cross-view navigation
- [x] iPad sidebar layout
- [x] Address converter
- [x] Pattern scanner
- [x] Call graph visualization
- [x] Rule-based inspection
- [x] HTML report generation
- [x] Binary comparison (ObjC, security, imports, segments)
- [x] Onboarding experience
- [x] Accessibility (Dynamic Type, VoiceOver)
- [x] Binary patching with templates
- [x] Pseudocode generation

**Remaining:**
- [ ] Test binary corpus and golden tests
- [ ] Performance benchmarks and CI regression checks
- [ ] Capstone integration evaluation
- [ ] Swift type reconstruction
- [ ] Plugin architecture

---

## Screenshots

<img width="1179" height="2556" alt="image" src="https://github.com/user-attachments/assets/d9d80e82-0a6f-4412-b61b-e066e43df0b4" />
<img width="1179" height="2556" alt="image" src="https://github.com/user-attachments/assets/693c8c4c-c51b-404e-af6d-621b9101e84e" />

---

## Known Issues

- Some complex ObjC runtime structures not yet parsed (categories, deep hierarchy)
- x86_64 disassembly coverage is partial (ARM64 prioritized)
- Class dump ~60% complete (category merging, protocol conformance remain)
- Type reconstruction ~50% complete

See [Issues](https://github.com/speedyfriend433/ReDyne/issues) for full list.

---

## Contributing

Contributions are welcome! Here's how you can help:

### Bug Reports
- Use GitHub Issues
- Include iOS version, device model
- Provide sample binary (if possible)
- Describe expected vs actual behavior

### Pull Requests
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Code Style
- C code: bounds-checked, RAII, clear ownership, `safe_strncpy` patterns
- Swift: camelCase, protocol-oriented, Constants.Colors for theming
- Accessibility: VoiceOver labels on all interactive elements
- No force-unwraps in production code paths

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2026 speedyfriend433

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## Author

**speedyfriend433**
- GitHub: [@speedyfriend433](https://github.com/speedyfriend433)
- Email: speedyfriend433@gmail.com

---

## Acknowledgments

- **ARM Architecture Reference Manual** — Instruction encoding specifications
- **Apple Mach-O Documentation** — File format details
- **iOS Developer Community** — Testing and feedback
- **Open Source Contributors** — Issue reports and PRs

---

<div align="center">

**Star this repo if you find it useful!**

Made with care for the iOS reverse engineering community

</div>
