import UIKit

class BookmarksViewController: UITableViewController {

    // MARK: - Properties

    weak var navigationDelegate: AnalysisNavigationDelegate?

    private let binaryUUID: String
    private var bookmarks: [Bookmark] = []
    private var annotations: [Annotation] = []

    private let store = BookmarkStore.shared

    // MARK: - Initialization

    init(binaryUUID: String) {
        self.binaryUUID = binaryUUID
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Bookmarks & Annotations"
        view.backgroundColor = Constants.Colors.primaryBackground

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "BookmarkCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "AnnotationCell")

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(dismissView)
        )

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .add,
                target: self,
                action: #selector(addNewBookmark)
            ),
            editButtonItem
        ]

        reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadData()
    }

    // MARK: - Data

    private func reloadData() {
        bookmarks = store.bookmarksSortedByAddress(forBinaryUUID: binaryUUID)
        annotations = store.annotationsSortedByAddress(forBinaryUUID: binaryUUID)
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func dismissView() {
        dismiss(animated: true)
    }

    @objc private func addNewBookmark() {
        let alert = UIAlertController(title: "Add Bookmark", message: "Enter the address (hex) and a label.", preferredStyle: .alert)

        alert.addTextField { textField in
            textField.placeholder = "Address (e.g. 0x100004000)"
            textField.keyboardType = .asciiCapable
            textField.autocapitalizationType = .none
        }

        alert.addTextField { textField in
            textField.placeholder = "Label"
            textField.autocapitalizationType = .sentences
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Add", style: .default) { [weak self] _ in
            guard let self = self,
                  let addressText = alert.textFields?[0].text?.trimmingCharacters(in: .whitespaces),
                  let label = alert.textFields?[1].text?.trimmingCharacters(in: .whitespaces),
                  !label.isEmpty else { return }

            let address = self.parseAddress(addressText)
            let bookmark = Bookmark(address: address, label: label)
            self.store.addBookmark(bookmark, forBinaryUUID: self.binaryUUID)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.reloadData()
            }
        })

        present(alert, animated: true)
    }

    private func parseAddress(_ text: String) -> UInt64 {
        let cleaned = text.hasPrefix("0x") || text.hasPrefix("0X")
            ? String(text.dropFirst(2))
            : text
        return UInt64(cleaned, radix: 16) ?? 0
    }

    // MARK: - Color Helpers

    private func colorForName(_ name: String) -> UIColor {
        switch name.lowercased() {
        case "red":    return .systemRed
        case "blue":   return .systemBlue
        case "green":  return .systemGreen
        case "yellow": return .systemYellow
        case "purple": return .systemPurple
        default:       return .systemBlue
        }
    }

    // MARK: - UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 2
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Bookmarks (\(bookmarks.count))"
        case 1: return "Annotations (\(annotations.count))"
        default: return nil
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return max(bookmarks.count, 1)
        case 1: return max(annotations.count, 1)
        default: return 0
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "BookmarkCell", for: indexPath)
            var content = cell.defaultContentConfiguration()

            if bookmarks.isEmpty {
                content.text = "No bookmarks yet"
                content.textProperties.color = .secondaryLabel
                content.textProperties.font = .systemFont(ofSize: 14)
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                cell.accessoryType = .none
                return cell
            }

            let bookmark = bookmarks[indexPath.row]
            content.text = bookmark.label
            content.textProperties.font = .systemFont(ofSize: 15, weight: .medium)
            content.secondaryText = Constants.formatAddress(bookmark.address)
            content.secondaryTextProperties.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            content.secondaryTextProperties.color = .secondaryLabel

            let dotSize: CGFloat = 12
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: dotSize, height: dotSize))
            let dotImage = renderer.image { ctx in
                let rect = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
                ctx.cgContext.setFillColor(colorForName(bookmark.color).cgColor)
                ctx.cgContext.fillEllipse(in: rect)
            }
            content.image = dotImage

            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
            return cell

        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "AnnotationCell", for: indexPath)
            var content = cell.defaultContentConfiguration()

            if annotations.isEmpty {
                content.text = "No annotations yet"
                content.textProperties.color = .secondaryLabel
                content.textProperties.font = .systemFont(ofSize: 14)
                cell.contentConfiguration = content
                cell.selectionStyle = .none
                cell.accessoryType = .none
                return cell
            }

            let annotation = annotations[indexPath.row]
            content.text = Constants.formatAddress(annotation.address)
            content.textProperties.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            content.secondaryText = annotation.comment
            content.secondaryTextProperties.font = .systemFont(ofSize: 13)
            content.secondaryTextProperties.color = .secondaryLabel
            content.secondaryTextProperties.numberOfLines = 2

            content.image = UIImage(systemName: "note.text")
            content.imageProperties.tintColor = .systemOrange

            cell.contentConfiguration = content
            cell.selectionStyle = .default
            cell.accessoryType = .disclosureIndicator
            return cell

        default:
            return UITableViewCell()
        }
    }

    // MARK: - UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.section {
        case 0:
            guard !bookmarks.isEmpty, indexPath.row < bookmarks.count else { return }
            let bookmark = bookmarks[indexPath.row]
            dismiss(animated: true) { [weak self] in
                self?.navigationDelegate?.navigateToDisassembly(atAddress: bookmark.address)
            }

        case 1:
            guard !annotations.isEmpty, indexPath.row < annotations.count else { return }
            let annotation = annotations[indexPath.row]
            showAnnotationDetail(annotation)

        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        switch indexPath.section {
        case 0: return !bookmarks.isEmpty
        case 1: return !annotations.isEmpty
        default: return false
        }
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }

        switch indexPath.section {
        case 0:
            guard indexPath.row < bookmarks.count else { return }
            let bookmark = bookmarks[indexPath.row]
            store.removeBookmark(id: bookmark.id, forBinaryUUID: binaryUUID)
            bookmarks.remove(at: indexPath.row)
            if bookmarks.isEmpty {
                tableView.reloadSections(IndexSet(integer: 0), with: .automatic)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }

        case 1:
            guard indexPath.row < annotations.count else { return }
            let annotation = annotations[indexPath.row]
            store.removeAnnotation(id: annotation.id, forBinaryUUID: binaryUUID)
            annotations.remove(at: indexPath.row)
            if annotations.isEmpty {
                tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
            } else {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }

        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        switch indexPath.section {
        case 0: return !bookmarks.isEmpty
        case 1: return !annotations.isEmpty
        default: return false
        }
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard sourceIndexPath.section == destinationIndexPath.section else { return }

        switch sourceIndexPath.section {
        case 0:
            let bookmark = bookmarks.remove(at: sourceIndexPath.row)
            bookmarks.insert(bookmark, at: destinationIndexPath.row)
        case 1:
            let annotation = annotations.remove(at: sourceIndexPath.row)
            annotations.insert(annotation, at: destinationIndexPath.row)
        default:
            break
        }
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        if sourceIndexPath.section != proposedDestinationIndexPath.section {
            return sourceIndexPath
        }
        return proposedDestinationIndexPath
    }

    // MARK: - Annotation Detail

    private func showAnnotationDetail(_ annotation: Annotation) {
        let alert = UIAlertController(
            title: Constants.formatAddress(annotation.address),
            message: annotation.comment,
            preferredStyle: .actionSheet
        )

        alert.addAction(UIAlertAction(title: "Go to Address", style: .default) { [weak self] _ in
            self?.dismiss(animated: true) {
                self?.navigationDelegate?.navigateToDisassembly(atAddress: annotation.address)
            }
        })

        alert.addAction(UIAlertAction(title: "Edit Comment", style: .default) { [weak self] _ in
            self?.editAnnotation(annotation)
        })

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(
                row: annotations.firstIndex(where: { $0.id == annotation.id }) ?? 0,
                section: 1
            ))
        }

        present(alert, animated: true)
    }

    private func editAnnotation(_ annotation: Annotation) {
        let alert = UIAlertController(title: "Edit Annotation", message: Constants.formatAddress(annotation.address), preferredStyle: .alert)

        alert.addTextField { textField in
            textField.text = annotation.comment
            textField.placeholder = "Comment"
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self,
                  let comment = alert.textFields?.first?.text?.trimmingCharacters(in: .whitespaces),
                  !comment.isEmpty else { return }

            var updated = annotation
            updated.comment = comment
            updated.dateModified = Date()
            self.store.updateAnnotation(updated, forBinaryUUID: self.binaryUUID)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.reloadData()
            }
        })

        present(alert, animated: true)
    }
}
