//
//  ShareViewController.swift
//  ReDyn-Share
//
//  Created by Morris Richman on 3/21/26.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "Preparing file…"
        label.textAlignment = .center
        label.textColor = .label
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.numberOfLines = 0
        return label
    }()

    private let spinner: UIActivityIndicatorView = {
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        return spinner
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(spinner)
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
        ])

        handleIncomingFile()
    }

    // MARK: - File Handling

    private func handleIncomingFile() {
        guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else {
            completeWithError("No items received.")
            return
        }

        for item in extensionItems {
            guard let attachments = item.attachments else { continue }

            for provider in attachments {
                // Try to load as a file URL first
                if provider.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.completeWithError("Failed to load file: \(error.localizedDescription)")
                                return
                            }
                            self?.processLoadedItem(item)
                        }
                    }
                    return
                } else if provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                    provider.loadItem(forTypeIdentifier: UTType.item.identifier, options: nil) { [weak self] item, error in
                        DispatchQueue.main.async {
                            if let error = error {
                                self?.completeWithError("Failed to load file: \(error.localizedDescription)")
                                return
                            }
                            self?.processLoadedItem(item)
                        }
                    }
                    return
                }
            }
        }

        completeWithError("No compatible file found.")
    }

    private func processLoadedItem(_ item: NSSecureCoding?) {
        if let url = item as? URL {
            copyAndOpenFile(from: url)
        } else if let data = item as? Data {
            saveDataAndOpen(data, filename: "shared_binary")
        } else {
            completeWithError("Unsupported file format.")
        }
    }

    private func copyAndOpenFile(from sourceURL: URL) {
        let sharedContainer = getSharedContainerURL()
        let filename = sourceURL.lastPathComponent
        let destinationURL = sharedContainer.appendingPathComponent(filename)

        do {
            // Ensure shared directory exists
            try FileManager.default.createDirectory(at: sharedContainer, withIntermediateDirectories: true)

            // Remove any existing file at the destination
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            // Copy the shared file
            _ = sourceURL.startAccessingSecurityScopedResource()
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            sourceURL.stopAccessingSecurityScopedResource()

            // Open the main app
            openMainApp(with: filename)
        } catch {
            completeWithError("Failed to copy file: \(error.localizedDescription)")
        }
    }

    private func saveDataAndOpen(_ data: Data, filename: String) {
        let sharedContainer = getSharedContainerURL()
        let destinationURL = sharedContainer.appendingPathComponent(filename)

        do {
            try FileManager.default.createDirectory(at: sharedContainer, withIntermediateDirectories: true)

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try data.write(to: destinationURL)
            openMainApp(with: filename)
        } catch {
            completeWithError("Failed to save file: \(error.localizedDescription)")
        }
    }

    // MARK: - Shared Container

    private func getSharedContainerURL() -> URL {
        // Try App Group container first
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.jian.ReDyne") {
            return containerURL.appendingPathComponent("SharedFiles", isDirectory: true)
        }

        // Fallback to temp directory
        return FileManager.default.temporaryDirectory.appendingPathComponent("ReDyneShared", isDirectory: true)
    }

    // MARK: - Open Main App

    private func openMainApp(with filename: String) {
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? filename
        guard let url = URL(string: "redyne://open?file=\(encodedFilename)") else {
            completeWithError("Failed to create URL.")
            return
        }

        // Use the responder chain to open the URL
        var responder: UIResponder? = self
        while let nextResponder = responder?.next {
            if let application = nextResponder as? UIApplication {
                application.open(url, options: [:]) { [weak self] success in
                    if success {
                        self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                    } else {
                        self?.completeWithError("Could not open ReDyne.")
                    }
                }
                return
            }
            responder = nextResponder
        }

        // Fallback: use openURL via selector for extensions
        let selector = NSSelectorFromString("openURL:")
        responder = self
        while let nextResponder = responder?.next {
            if nextResponder.responds(to: selector) {
                nextResponder.perform(selector, with: url)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
                }
                return
            }
            responder = nextResponder
        }

        completeWithError("Could not open ReDyne app.")
    }

    // MARK: - Completion

    private func completeWithError(_ message: String) {
        statusLabel.text = "❌ \(message)"
        spinner.stopAnimating()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: NSError(
                domain: "com.jian.ReDyne.Share",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message]
            ))
        }
    }
}
