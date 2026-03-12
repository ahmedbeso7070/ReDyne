import UIKit

// MARK: - Call Graph Data Model

private struct CallGraphNode {
    let id: String              // unique key (address hex string)
    let name: String            // display name (demangled preferred)
    let address: UInt64
    var callers: Set<String>    // ids of nodes that call this one
    var callees: Set<String>    // ids of nodes this one calls
    var layer: Int = 0
    var position: CGPoint = .zero
    var nodeType: CallGraphNodeType = .normal
}

private enum CallGraphNodeType {
    case normal
    case entryPoint
    case dangerous
    case external

    var color: UIColor {
        switch self {
        case .normal:     return UIColor.systemBlue
        case .entryPoint: return UIColor.systemGreen
        case .dangerous:  return UIColor.systemRed
        case .external:   return UIColor.systemGray
        }
    }
}

// MARK: - Call Graph Drawing View

private class CallGraphView: UIView {

    var nodes: [String: CallGraphNode] = [:]
    var orderedNodeIDs: [String] = []
    var onNodeTapped: ((CallGraphNode) -> Void)?

    private let nodeWidth: CGFloat = 160
    private let nodeHeight: CGFloat = 40
    private let horizontalSpacing: CGFloat = 40
    private let verticalSpacing: CGFloat = 70

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        for id in orderedNodeIDs {
            guard let node = nodes[id] else { continue }
            let rect = nodeRect(for: node)
            if rect.contains(point) {
                onNodeTapped?(node)
                return
            }
        }
    }

    private func nodeRect(for node: CallGraphNode) -> CGRect {
        return CGRect(
            x: node.position.x - nodeWidth / 2,
            y: node.position.y - nodeHeight / 2,
            width: nodeWidth,
            height: nodeHeight
        )
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        // Draw edges first (behind nodes)
        for id in orderedNodeIDs {
            guard let node = nodes[id] else { continue }
            for calleeID in node.callees {
                guard let callee = nodes[calleeID] else { continue }
                drawEdge(ctx: ctx, from: node, to: callee)
            }
        }

        // Draw nodes
        for id in orderedNodeIDs {
            guard let node = nodes[id] else { continue }
            drawNode(ctx: ctx, node: node)
        }
    }

    private func drawEdge(ctx: CGContext, from: CallGraphNode, to: CallGraphNode) {
        let startY = from.position.y + nodeHeight / 2
        let endY = to.position.y - nodeHeight / 2

        let startPoint = CGPoint(x: from.position.x, y: startY)
        let endPoint = CGPoint(x: to.position.x, y: endY)

        ctx.saveGState()
        ctx.setStrokeColor(UIColor.secondaryLabel.cgColor)
        ctx.setLineWidth(1.5)

        let path = CGMutablePath()
        path.move(to: startPoint)

        // Use a cubic bezier for smoother curves
        let midY = (startPoint.y + endPoint.y) / 2
        let cp1 = CGPoint(x: startPoint.x, y: midY)
        let cp2 = CGPoint(x: endPoint.x, y: midY)
        path.addCurve(to: endPoint, control1: cp1, control2: cp2)

        ctx.addPath(path)
        ctx.strokePath()

        // Draw arrowhead
        let arrowSize: CGFloat = 8
        let angle = atan2(endPoint.y - cp2.y, endPoint.x - cp2.x)
        let arrowP1 = CGPoint(
            x: endPoint.x - arrowSize * cos(angle - .pi / 6),
            y: endPoint.y - arrowSize * sin(angle - .pi / 6)
        )
        let arrowP2 = CGPoint(
            x: endPoint.x - arrowSize * cos(angle + .pi / 6),
            y: endPoint.y - arrowSize * sin(angle + .pi / 6)
        )

        ctx.setFillColor(UIColor.secondaryLabel.cgColor)
        ctx.move(to: endPoint)
        ctx.addLine(to: arrowP1)
        ctx.addLine(to: arrowP2)
        ctx.closePath()
        ctx.fillPath()

        ctx.restoreGState()
    }

    private func drawNode(ctx: CGContext, node: CallGraphNode) {
        let rect = nodeRect(for: node)
        let cornerRadius: CGFloat = 10
        let roundedPath = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)

        // Fill
        ctx.saveGState()
        ctx.setFillColor(node.nodeType.color.withAlphaComponent(0.15).cgColor)
        ctx.addPath(roundedPath.cgPath)
        ctx.fillPath()

        // Border
        ctx.setStrokeColor(node.nodeType.color.cgColor)
        ctx.setLineWidth(2.0)
        ctx.addPath(roundedPath.cgPath)
        ctx.strokePath()
        ctx.restoreGState()

        // Text
        let displayName = truncatedName(node.name, maxWidth: nodeWidth - 16)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.label
        ]
        let attrString = NSAttributedString(string: displayName, attributes: attributes)
        let textSize = attrString.size()
        let textOrigin = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        attrString.draw(at: textOrigin)
    }

    private func truncatedName(_ name: String, maxWidth: CGFloat) -> String {
        let font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        var result = name
        while result.count > 4 {
            let size = (result as NSString).size(withAttributes: attributes)
            if size.width <= maxWidth { break }
            result = String(result.dropLast(2)) + "..."
            // After appending ellipsis, trim further if still too wide
            if result.count <= 6 { break }
        }
        return result
    }

    func computeLayout() {
        guard !orderedNodeIDs.isEmpty else { return }

        // Assign layers via BFS from roots
        var visited = Set<String>()
        var queue: [String] = []

        // Find root nodes: nodes with no callers (or entry points)
        let roots = orderedNodeIDs.filter { id in
            guard let node = nodes[id] else { return false }
            return node.callers.isEmpty || node.nodeType == .entryPoint
        }

        if roots.isEmpty {
            // Fallback: pick the first node
            if let first = orderedNodeIDs.first {
                queue.append(first)
                nodes[first]?.layer = 0
                visited.insert(first)
            }
        } else {
            for root in roots {
                queue.append(root)
                nodes[root]?.layer = 0
                visited.insert(root)
            }
        }

        // BFS to assign layers
        var head = 0
        while head < queue.count {
            let currentID = queue[head]
            head += 1
            guard let current = nodes[currentID] else { continue }
            for calleeID in current.callees {
                guard nodes[calleeID] != nil else { continue }
                if !visited.contains(calleeID) {
                    visited.insert(calleeID)
                    nodes[calleeID]?.layer = current.layer + 1
                    queue.append(calleeID)
                } else if let existingLayer = nodes[calleeID]?.layer, existingLayer <= current.layer {
                    // Already visited with a shallower or equal layer; keep the deeper assignment
                    // to avoid cycles pushing things too far, leave as-is
                }
            }
        }

        // Handle disconnected nodes
        for id in orderedNodeIDs where !visited.contains(id) {
            nodes[id]?.layer = 0
            visited.insert(id)
        }

        // Group by layer
        var layers: [Int: [String]] = [:]
        for id in orderedNodeIDs {
            guard let node = nodes[id] else { continue }
            layers[node.layer, default: []].append(id)
        }

        let maxLayer = layers.keys.max() ?? 0
        let padding: CGFloat = 40

        // Position nodes
        var maxX: CGFloat = 0
        for layer in 0...maxLayer {
            guard let ids = layers[layer] else { continue }
            let y = padding + CGFloat(layer) * (nodeHeight + verticalSpacing)
            let totalWidth = CGFloat(ids.count) * nodeWidth + CGFloat(max(ids.count - 1, 0)) * horizontalSpacing
            let startX = padding + totalWidth / 2

            for (i, id) in ids.enumerated() {
                let x = startX - totalWidth / 2 + CGFloat(i) * (nodeWidth + horizontalSpacing) + nodeWidth / 2
                nodes[id]?.position = CGPoint(x: x, y: y)
                maxX = max(maxX, x + nodeWidth / 2 + padding)
            }
        }

        let maxY = padding + CGFloat(maxLayer + 1) * (nodeHeight + verticalSpacing) + padding
        let totalWidth = max(maxX, UIScreen.main.bounds.width)
        frame = CGRect(x: 0, y: 0, width: totalWidth, height: maxY)
    }
}

// MARK: - Call Graph View Controller

class CallGraphViewController: UIViewController {

    // MARK: - Properties

    private let xrefAnalysis: Any?
    private let functions: [FunctionModel]
    private let symbols: [SymbolModel]

    private var allNodes: [String: CallGraphNode] = [:]
    private var displayedNodes: [String: CallGraphNode] = [:]
    private var focusedNodeID: String?

    private let scrollView = UIScrollView()
    private let graphView = CallGraphView()
    private var currentScale: CGFloat = 1.0

    private let dangerousAPINames: Set<String> = [
        "_system", "_popen", "_exec", "_execl", "_execlp", "_execle",
        "_execv", "_execvp", "_dlopen", "_dlsym", "_fork",
        "_gets", "_sprintf", "_strcpy", "_strcat", "_scanf",
        "_NSLog", "_CC_MD5", "_CC_SHA1"
    ]

    // MARK: - Initialization

    init(xrefAnalysis: Any?, functions: [FunctionModel], symbols: [SymbolModel]) {
        self.xrefAnalysis = xrefAnalysis
        self.functions = functions
        self.symbols = symbols
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Call Graph"
        view.backgroundColor = Constants.Colors.primaryBackground
        setupUI()
        buildGraph()
        showFunctionPicker()
    }

    // MARK: - UI Setup

    private func setupUI() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.1
        scrollView.maximumZoomScale = 3.0
        scrollView.bouncesZoom = true
        view.addSubview(scrollView)

        scrollView.addSubview(graphView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        scrollView.addGestureRecognizer(pinch)

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            style: .plain,
            target: self,
            action: #selector(showFunctionPicker)
        )

        graphView.onNodeTapped = { [weak self] node in
            self?.showNodeDetail(node)
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        // UIScrollView handles pinch zoom via delegate viewForZooming
    }

    // MARK: - Graph Building

    private func buildGraph() {
        guard let xrefResult = xrefAnalysis as? XrefAnalysisResult else { return }

        // Build a set of known external/undefined symbols for classification
        let externalSymbolNames = Set(symbols.filter { !$0.isDefined }.map { $0.name })
        let functionAddresses = Set(functions.map { $0.startAddress })

        // Build nodes from functions
        for function in functions {
            let key = String(format: "0x%llX", function.startAddress)
            let displayName = function.demangledName ?? function.name
            var nodeType: CallGraphNodeType = .normal

            if dangerousAPINames.contains(function.name) {
                nodeType = .dangerous
            }

            allNodes[key] = CallGraphNode(
                id: key,
                name: displayName,
                address: function.startAddress,
                callers: [],
                callees: [],
                nodeType: nodeType
            )
        }

        // Process call xrefs to build edges
        let callXrefs = xrefResult.allXrefs.filter { $0.xrefType == .call }

        for xref in callXrefs {
            // Find the caller function (the function containing fromAddress)
            let callerFunc = functions.first { fn in
                xref.fromAddress >= fn.startAddress && xref.fromAddress < fn.endAddress
            }
            guard let callerFunc = callerFunc else { continue }

            let callerKey = String(format: "0x%llX", callerFunc.startAddress)
            let calleeKey = String(format: "0x%llX", xref.toAddress)

            // Ensure callee node exists; create if it's an external/stub target
            if allNodes[calleeKey] == nil {
                let calleeName = xref.toSymbol.isEmpty
                    ? String(format: "sub_%llX", xref.toAddress)
                    : xref.toSymbol
                let isExternal = externalSymbolNames.contains(calleeName) || !functionAddresses.contains(xref.toAddress)
                let isDangerous = dangerousAPINames.contains(calleeName)
                let nodeType: CallGraphNodeType = isDangerous ? .dangerous : (isExternal ? .external : .normal)

                allNodes[calleeKey] = CallGraphNode(
                    id: calleeKey,
                    name: calleeName,
                    address: xref.toAddress,
                    callers: [],
                    callees: [],
                    nodeType: nodeType
                )
            }

            // Skip self-calls
            if callerKey == calleeKey { continue }

            allNodes[callerKey]?.callees.insert(calleeKey)
            allNodes[calleeKey]?.callers.insert(callerKey)
        }

        // Mark entry points: nodes with no callers among internal functions
        for (key, node) in allNodes {
            if node.callers.isEmpty && node.nodeType == .normal && !node.callees.isEmpty {
                allNodes[key]?.nodeType = .entryPoint
            }
        }
    }

    // MARK: - Subgraph Display

    private func displaySubgraph(centeredOn nodeID: String, maxDepth: Int = 3) {
        focusedNodeID = nodeID
        displayedNodes.removeAll()

        guard let rootNode = allNodes[nodeID] else { return }

        // BFS outward from root in both directions up to maxDepth
        var visited = Set<String>()
        var queue: [(String, Int)] = [(nodeID, 0)]
        visited.insert(nodeID)

        while !queue.isEmpty {
            let (currentID, depth) = queue.removeFirst()
            guard let node = allNodes[currentID] else { continue }

            // Filter the node to only include edges that exist in our subgraph
            displayedNodes[currentID] = node

            if depth < maxDepth {
                // Follow callees
                for calleeID in node.callees {
                    if !visited.contains(calleeID), allNodes[calleeID] != nil {
                        visited.insert(calleeID)
                        queue.append((calleeID, depth + 1))
                    }
                }
                // Follow callers
                for callerID in node.callers {
                    if !visited.contains(callerID), allNodes[callerID] != nil {
                        visited.insert(callerID)
                        queue.append((callerID, depth + 1))
                    }
                }
            }
        }

        // Prune edges to only those within the displayed set
        for (key, var node) in displayedNodes {
            node.callees = node.callees.filter { displayedNodes[$0] != nil }
            node.callers = node.callers.filter { displayedNodes[$0] != nil }
            displayedNodes[key] = node
        }

        renderGraph()
    }

    private func renderGraph() {
        graphView.nodes = displayedNodes
        graphView.orderedNodeIDs = Array(displayedNodes.keys).sorted()
        graphView.computeLayout()

        scrollView.contentSize = graphView.frame.size
        graphView.setNeedsDisplay()

        // Scroll to focused node if visible
        if let focusID = focusedNodeID, let node = graphView.nodes[focusID] {
            let visibleRect = CGRect(
                x: node.position.x - view.bounds.width / 2,
                y: node.position.y - view.bounds.height / 2,
                width: view.bounds.width,
                height: view.bounds.height
            )
            scrollView.scrollRectToVisible(visibleRect, animated: false)
        }
    }

    // MARK: - Function Picker

    @objc private func showFunctionPicker() {
        // Collect functions that have call relationships
        let connectedFunctions = functions.filter { fn in
            let key = String(format: "0x%llX", fn.startAddress)
            guard let node = allNodes[key] else { return false }
            return !node.callees.isEmpty || !node.callers.isEmpty
        }

        let sortedFunctions = connectedFunctions.sorted { a, b in
            let keyA = String(format: "0x%llX", a.startAddress)
            let keyB = String(format: "0x%llX", b.startAddress)
            let countA = (allNodes[keyA]?.callees.count ?? 0) + (allNodes[keyA]?.callers.count ?? 0)
            let countB = (allNodes[keyB]?.callees.count ?? 0) + (allNodes[keyB]?.callers.count ?? 0)
            return countA > countB
        }

        let displayList = Array(sortedFunctions.prefix(200))

        let alert = UIAlertController(title: "Select Function", message: "Choose a function to visualize its call graph.", preferredStyle: .actionSheet)

        for fn in displayList.prefix(20) {
            let name = fn.demangledName ?? fn.name
            let key = String(format: "0x%llX", fn.startAddress)
            let callees = allNodes[key]?.callees.count ?? 0
            let callers = allNodes[key]?.callers.count ?? 0
            let label = "\(name) (\(callers) in, \(callees) out)"
            alert.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                self?.displaySubgraph(centeredOn: key)
            })
        }

        if displayList.count > 20 {
            alert.addAction(UIAlertAction(title: "Search All Functions...", style: .default) { [weak self] _ in
                self?.showFunctionSearch(functions: displayList)
            })
        }

        if displayList.isEmpty {
            alert.message = "No functions with call relationships found. Ensure xref analysis has been performed."
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }

        present(alert, animated: true)
    }

    private func showFunctionSearch(functions: [FunctionModel]) {
        let searchAlert = UIAlertController(title: "Search Function", message: nil, preferredStyle: .alert)
        searchAlert.addTextField { textField in
            textField.placeholder = "Function name..."
            textField.autocapitalizationType = .none
        }
        searchAlert.addAction(UIAlertAction(title: "Search", style: .default) { [weak self] _ in
            guard let query = searchAlert.textFields?.first?.text?.lowercased(), !query.isEmpty else { return }
            let matches = functions.filter {
                ($0.demangledName ?? $0.name).lowercased().contains(query)
            }
            if let first = matches.first {
                let key = String(format: "0x%llX", first.startAddress)
                self?.displaySubgraph(centeredOn: key)
            } else {
                let noResult = UIAlertController(title: "Not Found", message: "No function matching '\(query)'.", preferredStyle: .alert)
                noResult.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(noResult, animated: true)
            }
        })
        searchAlert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(searchAlert, animated: true)
    }

    // MARK: - Node Detail

    private func showNodeDetail(_ node: CallGraphNode) {
        let alert = UIAlertController(
            title: node.name,
            message: buildNodeDetailMessage(node),
            preferredStyle: .alert
        )

        // Navigate into callees
        if !node.callees.isEmpty {
            alert.addAction(UIAlertAction(title: "Focus on this function", style: .default) { [weak self] _ in
                self?.displaySubgraph(centeredOn: node.id)
            })
        }

        alert.addAction(UIAlertAction(title: "Dismiss", style: .cancel))
        present(alert, animated: true)
    }

    private func buildNodeDetailMessage(_ node: CallGraphNode) -> String {
        var lines: [String] = []
        lines.append("Address: \(Constants.formatAddress(node.address))")

        let typeDesc: String
        switch node.nodeType {
        case .normal:     typeDesc = "Normal"
        case .entryPoint: typeDesc = "Entry Point"
        case .dangerous:  typeDesc = "Dangerous API"
        case .external:   typeDesc = "External/Imported"
        }
        lines.append("Type: \(typeDesc)")
        lines.append("")

        if !node.callers.isEmpty {
            lines.append("Called by (\(node.callers.count)):")
            for callerID in node.callers.sorted().prefix(8) {
                let name = displayedNodes[callerID]?.name ?? allNodes[callerID]?.name ?? callerID
                lines.append("  \(name)")
            }
            if node.callers.count > 8 {
                lines.append("  ... and \(node.callers.count - 8) more")
            }
        }

        if !node.callees.isEmpty {
            lines.append("")
            lines.append("Calls (\(node.callees.count)):")
            for calleeID in node.callees.sorted().prefix(8) {
                let name = displayedNodes[calleeID]?.name ?? allNodes[calleeID]?.name ?? calleeID
                lines.append("  \(name)")
            }
            if node.callees.count > 8 {
                lines.append("  ... and \(node.callees.count - 8) more")
            }
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: - UIScrollViewDelegate

extension CallGraphViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return graphView
    }
}
