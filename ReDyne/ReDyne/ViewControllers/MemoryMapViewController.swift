import UIKit

class MemoryMapViewController: UIViewController {
    
    // MARK: - Properties

    private let allSegments: [SegmentModel]
    private let allSections: [SectionModel]
    private var filteredSegments: [SegmentModel]
    private var filteredSections: [SectionModel]
    private let fileSize: UInt64
    private let baseAddress: UInt64

    // Protection flag filter state: nil means no filter active, value means require that flag
    private var filterRead: Bool = false
    private var filterWrite: Bool = false
    private var filterExecute: Bool = false
    
    // MARK: - UI Elements
    
    private let scrollView: UIScrollView = {
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = true
        scroll.alwaysBounceVertical = true
        return scroll
    }()
    
    private let contentStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.distribution = .fill
        return stack
    }()
    
    private let headerLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 24, weight: .bold)
        label.text = "Memory Map"
        return label
    }()
    
    private let statsLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 14)
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        return label
    }()
    
    private lazy var memoryMapView: MemoryMapView = {
        let view = MemoryMapView(segments: filteredSegments, sections: filteredSections, fileSize: fileSize, baseAddress: baseAddress)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.delegate = self
        return view
    }()
    
    private let filterStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .horizontal
        stack.spacing = 10
        stack.alignment = .center
        stack.distribution = .fill
        return stack
    }()

    private lazy var filterReadButton: UIButton = createFilterButton(title: "R (Read)", tag: 0)
    private lazy var filterWriteButton: UIButton = createFilterButton(title: "W (Write)", tag: 1)
    private lazy var filterExecuteButton: UIButton = createFilterButton(title: "X (Execute)", tag: 2)

    private let legendStack: UIStackView = {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .fill
        return stack
    }()
    
    // MARK: - Initialization
    
    init(segments: [SegmentModel], sections: [SectionModel], fileSize: UInt64, baseAddress: UInt64) {
        self.allSegments = segments
        self.allSections = sections
        self.filteredSegments = segments
        self.filteredSections = sections
        self.fileSize = fileSize
        self.baseAddress = baseAddress
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "Memory Map"
        view.backgroundColor = Constants.Colors.primaryBackground
        
        setupUI()
        populateStats()
        setupLegend()
        
        // Export button
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "square.and.arrow.up"),
            style: .plain,
            target: self,
            action: #selector(exportMap)
        )
    }
    
    // MARK: - Setup
    
    private func setupUI() {
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        // Build filter bar
        let filterLabel = UILabel()
        filterLabel.font = .systemFont(ofSize: 14, weight: .medium)
        filterLabel.text = "Filter:"
        filterLabel.textColor = .secondaryLabel
        filterLabel.setContentHuggingPriority(.required, for: .horizontal)

        filterStack.addArrangedSubview(filterLabel)
        filterStack.addArrangedSubview(filterReadButton)
        filterStack.addArrangedSubview(filterWriteButton)
        filterStack.addArrangedSubview(filterExecuteButton)
        filterStack.addArrangedSubview(UIView()) // spacer

        contentStack.addArrangedSubview(headerLabel)
        contentStack.addArrangedSubview(statsLabel)
        contentStack.addArrangedSubview(filterStack)
        contentStack.addArrangedSubview(memoryMapView)
        contentStack.addArrangedSubview(createSeparator())
        contentStack.addArrangedSubview(createLegendHeader())
        contentStack.addArrangedSubview(legendStack)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 20),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -20),
            
            memoryMapView.heightAnchor.constraint(equalToConstant: 400)
        ])
    }
    
    private func populateStats() {
        let totalSize = allSegments.reduce(0) { $0 + $1.vmSize }

        // Filter segments by protection flags (initprot from Mach-O segment commands)
        // VM_PROT_EXECUTE = 0x04, VM_PROT_WRITE = 0x02, VM_PROT_READ = 0x01
        let executableSegments = allSegments.filter { ($0.initProt & 0x04) != 0 }
        let writableSegments = allSegments.filter { ($0.initProt & 0x02) != 0 }
        let readOnlySegments = allSegments.filter { ($0.initProt & 0x02) == 0 && ($0.initProt & 0x01) != 0 }

        // Count sections belonging to executable/writable segments
        let executableSectionCount = allSections.filter { section in
            executableSegments.contains(where: { $0.name == section.segmentName })
        }.count
        let writableSectionCount = allSections.filter { section in
            writableSegments.contains(where: { $0.name == section.segmentName })
        }.count

        // Detect RWX segments (security concern)
        let rwxSegments = allSegments.filter { ($0.initProt & 0x07) == 0x07 }

        var statsText = """
        Total VM Size: \(formatBytes(totalSize))
        File Size: \(formatBytes(fileSize))
        Base Address: 0x\(String(format: "%llX", baseAddress))
        Segments: \(allSegments.count)
        Executable Segments: \(executableSegments.count)
        Writable Segments: \(writableSegments.count)
        Read-only Segments: \(readOnlySegments.count)
        Executable Sections: \(executableSectionCount)
        Writable Sections: \(writableSectionCount)
        """

        if !rwxSegments.isEmpty {
            let names = rwxSegments.map { $0.name }.joined(separator: ", ")
            statsText += "\n⚠ RWX Segments: \(names)"
        }

        statsLabel.text = statsText
    }
    
    private func setupLegend() {
        let categories: [(String, UIColor, String)] = [
            ("__TEXT", MemoryMapView.Colors.text, "Code & Read-only data"),
            ("__DATA", MemoryMapView.Colors.data, "Writable data"),
            ("__LINKEDIT", MemoryMapView.Colors.linkedit, "Linking information"),
            ("__OBJC", MemoryMapView.Colors.objc, "Objective-C runtime"),
            ("Other", MemoryMapView.Colors.other, "Other segments")
        ]
        
        for (name, color, description) in categories {
            let legendItem = createLegendItem(name: name, color: color, description: description)
            legendStack.addArrangedSubview(legendItem)
        }
    }
    
    private func createLegendHeader() -> UILabel {
        let label = UILabel()
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.text = "Legend"
        return label
    }
    
    private func createLegendItem(name: String, color: UIColor, description: String) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        
        let colorBox = UIView()
        colorBox.translatesAutoresizingMaskIntoConstraints = false
        colorBox.backgroundColor = color
        colorBox.layer.cornerRadius = 4
        colorBox.layer.borderWidth = 1
        colorBox.layer.borderColor = UIColor.separator.cgColor
        
        let nameLabel = UILabel()
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        nameLabel.text = name
        
        let descLabel = UILabel()
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        descLabel.font = .systemFont(ofSize: 13)
        descLabel.textColor = .secondaryLabel
        descLabel.text = description
        
        container.addSubview(colorBox)
        container.addSubview(nameLabel)
        container.addSubview(descLabel)
        
        NSLayoutConstraint.activate([
            colorBox.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            colorBox.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            colorBox.widthAnchor.constraint(equalToConstant: 24),
            colorBox.heightAnchor.constraint(equalToConstant: 24),
            
            nameLabel.leadingAnchor.constraint(equalTo: colorBox.trailingAnchor, constant: 12),
            nameLabel.topAnchor.constraint(equalTo: container.topAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 120),
            
            descLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            descLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            descLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            
            container.heightAnchor.constraint(equalToConstant: 32)
        ])
        
        return container
    }
    
    private func createSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }
    
    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    // MARK: - Filtering

    private func createFilterButton(title: String, tag: Int) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.buttonSize = .small
        config.cornerStyle = .capsule
        config.baseBackgroundColor = .systemGray
        config.baseForegroundColor = .label

        let button = UIButton(configuration: config)
        button.tag = tag
        button.addTarget(self, action: #selector(filterButtonTapped(_:)), for: .touchUpInside)
        return button
    }

    @objc private func filterButtonTapped(_ sender: UIButton) {
        switch sender.tag {
        case 0: filterRead.toggle()
        case 1: filterWrite.toggle()
        case 2: filterExecute.toggle()
        default: break
        }
        updateFilterButtonAppearance(sender)
        applyProtectionFilter()
    }

    private func updateFilterButtonAppearance(_ button: UIButton) {
        let isActive: Bool
        switch button.tag {
        case 0: isActive = filterRead
        case 1: isActive = filterWrite
        case 2: isActive = filterExecute
        default: return
        }

        let tintColor: UIColor = isActive ? .systemBlue : .systemGray
        var config = button.configuration ?? .tinted()
        config.baseBackgroundColor = tintColor
        config.baseForegroundColor = isActive ? .white : .label
        button.configuration = config
    }

    private func applyProtectionFilter() {
        // Build required protection mask from active filters
        var requiredMask: UInt32 = 0
        if filterRead { requiredMask |= 0x01 }
        if filterWrite { requiredMask |= 0x02 }
        if filterExecute { requiredMask |= 0x04 }

        if requiredMask == 0 {
            // No filter active: show all
            filteredSegments = allSegments
            filteredSections = allSections
        } else {
            // Show only segments whose initProt contains ALL required flags
            filteredSegments = allSegments.filter { ($0.initProt & requiredMask) == requiredMask }

            // Show sections belonging to the filtered segments
            let filteredSegmentNames = Set(filteredSegments.map { $0.name })
            filteredSections = allSections.filter { filteredSegmentNames.contains($0.segmentName) }
        }

        memoryMapView.updateSegments(filteredSegments, sections: filteredSections)

        // Rebuild base stats, then append filter summary if active
        populateStats()
        if requiredMask != 0 {
            let count = filteredSegments.count
            let totalSize = filteredSegments.reduce(0) { $0 + $1.vmSize }
            let sectionCount = filteredSections.count
            statsLabel.text = (statsLabel.text ?? "") + "\n\nShowing: \(count) segment\(count == 1 ? "" : "s"), \(sectionCount) section\(sectionCount == 1 ? "" : "s") (\(formatBytes(totalSize)))"
        }
    }

    // MARK: - Actions

    @objc private func exportMap() {
        // Render the memory map to an image
        let renderer = UIGraphicsImageRenderer(bounds: memoryMapView.bounds)
        let image = renderer.image { ctx in
            memoryMapView.layer.render(in: ctx.cgContext)
        }
        
        let activityVC = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        if let popover = activityVC.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItem
        }
        
        present(activityVC, animated: true)
    }
}

// MARK: - MemoryMapViewDelegate

extension MemoryMapViewController: MemoryMapViewDelegate {
    func memoryMapView(_ view: MemoryMapView, didSelectSegment segment: SegmentModel) {
        let alert = UIAlertController(
            title: segment.name,
            message: segmentDetailText(segment),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    private func segmentDetailText(_ segment: SegmentModel) -> String {
        let segmentSections = allSections.filter { $0.segmentName == segment.name }
        
        var details = """
        VM Address: 0x\(String(format: "%llX", segment.vmAddress))
        VM Size: \(formatBytes(segment.vmSize))
        File Offset: 0x\(String(format: "%llX", segment.fileOffset))
        File Size: \(formatBytes(segment.fileSize))
        Protection: \(segment.protection)
        
        Sections: \(segmentSections.count)
        """
        
        if !segmentSections.isEmpty {
            details += "\n\nSections:\n"
            for section in segmentSections {
                details += "• \(section.sectionName) (\(formatBytes(section.size)))\n"
            }
        }
        
        return details
    }
}

