import Foundation

@objc class CFGAnalyzer: NSObject {

    /// Maximum number of functions to eagerly analyze during initial pass.
    /// Beyond this, CFGs should be generated on-demand per function.
    private static let eagerAnalysisLimit = 500

    @objc static func analyze(functions: [FunctionModel]) -> CFGAnalysisResult {
        var functionCFGs: [FunctionCFG] = []

        let limit = min(functions.count, eagerAnalysisLimit)
        for index in 0..<limit {
            let function = functions[index]
            if let cfg = analyzeFunctionCFG(function) {
                functionCFGs.append(cfg)
            }
        }

        let result = CFGAnalysisResult(functionCFGs: functionCFGs)
        return result
    }

    /// Analyze a single function's CFG on demand (no limit).
    @objc static func analyzeFunction(_ function: FunctionModel) -> FunctionCFG? {
        return analyzeFunctionCFG(function)
    }

    private static func analyzeFunctionCFG(_ function: FunctionModel) -> FunctionCFG? {
        guard let instructions = function.instructions as? [InstructionModel], !instructions.isEmpty else { return nil }

        var nodes: [CFGNode] = []
        var edges: [CFGEdge] = []
        var nodeID = 0
        var currentBlock: [InstructionModel] = []
        var blockStarts: Set<UInt64> = [function.startAddress]

        for inst in instructions {
            if inst.hasBranch {
                if inst.hasBranchTarget {
                    blockStarts.insert(inst.branchTarget)
                }
            }
        }

        for inst in instructions {
            currentBlock.append(inst)

            let isBlockEnd = inst.category.contains("Branch") ||
                           inst.mnemonic.uppercased().contains("RET") ||
                           blockStarts.contains(inst.address + 4)

            if isBlockEnd && !currentBlock.isEmpty {
                let startAddr = currentBlock.first!.address
                let endAddr = currentBlock.last!.address
                let instStrings = currentBlock.map { $0.mnemonic }

                let node = CFGNode(
                    id: nodeID,
                    startAddress: startAddr,
                    endAddress: endAddr,
                    instructions: instStrings
                )

                if nodeID == 0 {
                    node.nodeType = .entry
                }
                if currentBlock.last?.mnemonic.uppercased().contains("RET") == true {
                    node.nodeType = .exit
                }
                if currentBlock.last?.mnemonic.uppercased().hasPrefix("B.") == true {
                    node.nodeType = .conditional
                }

                nodes.append(node)
                nodeID += 1
                currentBlock = []
            }
        }

        // Handle remaining instructions not terminated by a branch
        if !currentBlock.isEmpty {
            let startAddr = currentBlock.first!.address
            let endAddr = currentBlock.last!.address
            let instStrings = currentBlock.map { $0.mnemonic }

            let node = CFGNode(
                id: nodeID,
                startAddress: startAddr,
                endAddress: endAddr,
                instructions: instStrings
            )
            if nodeID == 0 {
                node.nodeType = .entry
            }
            nodes.append(node)
            nodeID += 1
        }

        if nodes.count > 1 {
            var addressToNodeID: [UInt64: Int] = [:]
            for (idx, node) in nodes.enumerated() {
                addressToNodeID[node.startAddress] = idx
            }

            for i in 0..<nodes.count {
                let node = nodes[i]
                let lastInst = instructions.first(where: { $0.address == node.endAddress })

                guard let lastInst = lastInst else { continue }

                let mnemonic = lastInst.mnemonic.uppercased()

                if mnemonic == "RET" {
                    continue
                }
                else if mnemonic == "B" {
                    if lastInst.hasBranchTarget, let targetID = addressToNodeID[lastInst.branchTarget] {
                        let edge = CFGEdge(from: i, to: targetID, edgeType: .normal)
                        edges.append(edge)
                    }
                }
                else if mnemonic.hasPrefix("B.") {
                    if lastInst.hasBranchTarget, let targetID = addressToNodeID[lastInst.branchTarget] {
                        let branchEdge = CFGEdge(from: i, to: targetID, edgeType: .trueBranch)
                        edges.append(branchEdge)
                    }
                    if i + 1 < nodes.count {
                        let fallThroughEdge = CFGEdge(from: i, to: i + 1, edgeType: .falseBranch)
                        edges.append(fallThroughEdge)
                    }
                }
                else if mnemonic == "CBZ" || mnemonic == "CBNZ" || mnemonic == "TBZ" || mnemonic == "TBNZ" {
                    if lastInst.hasBranchTarget, let targetID = addressToNodeID[lastInst.branchTarget] {
                        let branchEdge = CFGEdge(from: i, to: targetID, edgeType: .trueBranch)
                        edges.append(branchEdge)
                    }
                    if i + 1 < nodes.count {
                        let fallThroughEdge = CFGEdge(from: i, to: i + 1, edgeType: .falseBranch)
                        edges.append(fallThroughEdge)
                    }
                }
                else if mnemonic == "BL" || mnemonic == "BLR" {
                    if i + 1 < nodes.count {
                        let callEdge = CFGEdge(from: i, to: i + 1, edgeType: .normal)
                        edges.append(callEdge)
                    }
                }
                else if mnemonic.contains("BR") && !mnemonic.contains("BRK") {
                    continue
                }
                else {
                    if i + 1 < nodes.count {
                        let edge = CFGEdge(from: i, to: i + 1, edgeType: .normal)
                        edges.append(edge)
                    }
                }
            }
        }

        return FunctionCFG(
            functionName: function.name,
            functionAddress: function.startAddress,
            nodes: nodes,
            edges: edges
        )
    }
}
