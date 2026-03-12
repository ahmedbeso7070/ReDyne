import UIKit

/// A first-launch onboarding experience with a page-based layout.
/// Shown modally on first launch; sets `hasCompletedOnboarding` in UserDefaults when dismissed.
class OnboardingViewController: UIViewController {

    // MARK: - Callback

    /// Called when the user finishes onboarding. The Bool indicates whether
    /// the user tapped "Try Sample Binary" (true) or "Get Started" (false).
    var onComplete: ((Bool) -> Void)?

    // MARK: - UI Elements

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.bounces = false
        return sv
    }()

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.translatesAutoresizingMaskIntoConstraints = false
        pc.numberOfPages = 3
        pc.currentPage = 0
        pc.currentPageIndicatorTintColor = Constants.Colors.accentColor
        pc.pageIndicatorTintColor = Constants.Colors.accentColor.withAlphaComponent(0.3)
        return pc
    }()

    private let nextButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Next"
        config.baseBackgroundColor = Constants.Colors.accentColor
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 32, bottom: 14, trailing: 32)
        let button = UIButton(configuration: config, primaryAction: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    // MARK: - Page Data

    private struct PageData {
        let symbolName: String
        let title: String
        let body: NSAttributedString
    }

    private var pages: [PageData] = []

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Constants.Colors.primaryBackground
        buildPageData()
        setupLayout()
        setupActions()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
    }

    // MARK: - Page Content

    private func buildPageData() {
        // Page 1: Welcome
        let welcomeBody = NSAttributedString(
            string: "A professional Mach-O binary analysis suite for iOS",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        // Page 2: Features
        let featureItems = [
            "Disassembly & pseudocode",
            "Security posture analysis",
            "Cross-reference navigation",
            "Swift & ObjC metadata parsing"
        ]
        let bulletString = NSMutableAttributedString()
        for (index, item) in featureItems.enumerated() {
            let line = "\u{2022}  \(item)"
            bulletString.append(NSAttributedString(
                string: line,
                attributes: [
                    .font: UIFont.preferredFont(forTextStyle: .body),
                    .foregroundColor: UIColor.secondaryLabel
                ]
            ))
            if index < featureItems.count - 1 {
                bulletString.append(NSAttributedString(string: "\n\n"))
            }
        }

        // Page 3: Getting Started
        let gettingStartedBody = NSAttributedString(
            string: "Tap the + button to import a Mach-O binary from Files, or use the sample binary to explore.",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.secondaryLabel
            ]
        )

        pages = [
            PageData(symbolName: "cpu", title: "Welcome to ReDyne", body: welcomeBody),
            PageData(symbolName: "magnifyingglass.circle", title: "Powerful Analysis", body: bulletString),
            PageData(symbolName: "doc.badge.plus", title: "Open a Binary", body: gettingStartedBody)
        ]
    }

    // MARK: - Layout

    private func setupLayout() {
        view.addSubview(scrollView)
        view.addSubview(pageControl)
        view.addSubview(nextButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -Constants.UI.standardSpacing),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -Constants.UI.standardSpacing),

            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Constants.UI.standardSpacing),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])

        scrollView.delegate = self
    }

    private func layoutPages() {
        // Remove existing page views before re-laying out
        scrollView.subviews.forEach { $0.removeFromSuperview() }

        let pageWidth = scrollView.bounds.width
        let pageHeight = scrollView.bounds.height

        guard pageWidth > 0, pageHeight > 0 else { return }

        scrollView.contentSize = CGSize(width: pageWidth * CGFloat(pages.count), height: pageHeight)

        for (index, page) in pages.enumerated() {
            let container = UIView(frame: CGRect(
                x: pageWidth * CGFloat(index),
                y: 0,
                width: pageWidth,
                height: pageHeight
            ))
            scrollView.addSubview(container)

            // SF Symbol
            let imageView = UIImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.tintColor = Constants.Colors.accentColor
            let symbolConfig = UIImage.SymbolConfiguration(pointSize: 64, weight: .light)
            imageView.image = UIImage(systemName: page.symbolName, withConfiguration: symbolConfig)

            // Title
            let titleLabel = UILabel()
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.text = page.title
            titleLabel.font = UIFont.systemFont(ofSize: Constants.UI.largeTitleFontSize, weight: .bold)
            titleLabel.textColor = .label
            titleLabel.textAlignment = .center
            titleLabel.numberOfLines = 0

            // Body
            let bodyLabel = UILabel()
            bodyLabel.translatesAutoresizingMaskIntoConstraints = false
            bodyLabel.attributedText = page.body
            bodyLabel.textAlignment = .center
            bodyLabel.numberOfLines = 0

            container.addSubview(imageView)
            container.addSubview(titleLabel)
            container.addSubview(bodyLabel)

            let horizontalInset: CGFloat = 32

            NSLayoutConstraint.activate([
                imageView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                imageView.bottomAnchor.constraint(equalTo: titleLabel.topAnchor, constant: -24),
                imageView.widthAnchor.constraint(equalToConstant: 80),
                imageView.heightAnchor.constraint(equalToConstant: 80),

                titleLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -20),
                titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: horizontalInset),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -horizontalInset),

                bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
                bodyLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: horizontalInset),
                bodyLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -horizontalInset)
            ])

            // Page 3: add two action buttons instead of relying on the global next button
            if index == pages.count - 1 {
                let sampleButton = makePillButton(title: "Try Sample Binary", filled: false)
                sampleButton.addTarget(self, action: #selector(trySampleTapped), for: .touchUpInside)

                let getStartedButton = makePillButton(title: "Get Started", filled: true)
                getStartedButton.addTarget(self, action: #selector(getStartedTapped), for: .touchUpInside)

                let stack = UIStackView(arrangedSubviews: [sampleButton, getStartedButton])
                stack.translatesAutoresizingMaskIntoConstraints = false
                stack.axis = .vertical
                stack.spacing = 12
                stack.alignment = .fill
                container.addSubview(stack)

                NSLayoutConstraint.activate([
                    stack.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 32),
                    stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                    stack.widthAnchor.constraint(equalToConstant: 220)
                ])
            }
        }

        updateButtonForCurrentPage()
    }

    // MARK: - Helpers

    private func makePillButton(title: String, filled: Bool) -> UIButton {
        var config: UIButton.Configuration
        if filled {
            config = .filled()
            config.baseBackgroundColor = Constants.Colors.accentColor
            config.baseForegroundColor = .white
        } else {
            config = .tinted()
            config.baseBackgroundColor = Constants.Colors.accentColor.withAlphaComponent(0.12)
            config.baseForegroundColor = Constants.Colors.accentColor
        }
        config.title = title
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)

        let button = UIButton(configuration: config, primaryAction: nil)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    // MARK: - Actions

    private func setupActions() {
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
    }

    @objc private func nextTapped() {
        let currentPage = pageControl.currentPage
        if currentPage < pages.count - 1 {
            let nextPage = currentPage + 1
            let offsetX = scrollView.bounds.width * CGFloat(nextPage)
            scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
            pageControl.currentPage = nextPage
            updateButtonForCurrentPage()
        }
    }

    @objc private func pageControlChanged() {
        let page = pageControl.currentPage
        let offsetX = scrollView.bounds.width * CGFloat(page)
        scrollView.setContentOffset(CGPoint(x: offsetX, y: 0), animated: true)
        updateButtonForCurrentPage()
    }

    @objc private func trySampleTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(true)
        }
    }

    @objc private func getStartedTapped() {
        dismiss(animated: true) { [weak self] in
            self?.onComplete?(false)
        }
    }

    private func updateButtonForCurrentPage() {
        let isLastPage = pageControl.currentPage == pages.count - 1
        // Hide the global "Next" button on the last page where we show inline buttons
        UIView.animate(withDuration: Constants.UI.animationDuration) {
            self.nextButton.alpha = isLastPage ? 0 : 1
        }
        nextButton.isUserInteractionEnabled = !isLastPage
    }
}

// MARK: - UIScrollViewDelegate

extension OnboardingViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.bounds.width > 0 else { return }
        let page = Int(round(scrollView.contentOffset.x / scrollView.bounds.width))
        let clampedPage = max(0, min(page, pages.count - 1))
        if pageControl.currentPage != clampedPage {
            pageControl.currentPage = clampedPage
            updateButtonForCurrentPage()
        }
    }
}
