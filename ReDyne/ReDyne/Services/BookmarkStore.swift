import Foundation

// MARK: - Models

struct Bookmark: Codable, Identifiable {
    let id: UUID
    var address: UInt64
    var label: String
    var color: String  // "red", "blue", "green", "yellow", "purple"
    var dateCreated: Date

    init(address: UInt64, label: String, color: String = "blue", dateCreated: Date = Date()) {
        self.id = UUID()
        self.address = address
        self.label = label
        self.color = color
        self.dateCreated = dateCreated
    }
}

struct Annotation: Codable, Identifiable {
    let id: UUID
    var address: UInt64
    var comment: String
    var dateCreated: Date
    var dateModified: Date

    init(address: UInt64, comment: String, dateCreated: Date = Date()) {
        self.id = UUID()
        self.address = address
        self.comment = comment
        self.dateCreated = dateCreated
        self.dateModified = dateCreated
    }
}

// MARK: - Storage Container

private struct BookmarkData: Codable {
    var bookmarks: [Bookmark]
    var annotations: [Annotation]

    init() {
        self.bookmarks = []
        self.annotations = []
    }
}

// MARK: - BookmarkStore

class BookmarkStore {

    static let shared = BookmarkStore()

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.redyne.bookmarkStore", attributes: .concurrent)

    /// Maximum number of binaries to keep in the in-memory cache.
    private static let maxCacheSize = 20

    /// In-memory cache keyed by binary UUID.
    private var cache: [String: BookmarkData] = [:]

    /// Tracks access order for LRU eviction (most recent at the end).
    private var cacheAccessOrder: [String] = []

    private init() {}

    // MARK: - Bookmarks

    func bookmarks(forBinaryUUID uuid: String) -> [Bookmark] {
        queue.sync {
            return loadData(forBinaryUUID: uuid).bookmarks
        }
    }

    func addBookmark(_ bookmark: Bookmark, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            data.bookmarks.append(bookmark)
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    func removeBookmark(id: UUID, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            data.bookmarks.removeAll { $0.id == id }
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    func updateBookmark(_ bookmark: Bookmark, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            if let index = data.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
                data.bookmarks[index] = bookmark
            }
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    // MARK: - Annotations

    func annotations(forBinaryUUID uuid: String) -> [Annotation] {
        queue.sync {
            return loadData(forBinaryUUID: uuid).annotations
        }
    }

    func addAnnotation(_ annotation: Annotation, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            data.annotations.append(annotation)
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    func removeAnnotation(id: UUID, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            data.annotations.removeAll { $0.id == id }
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    func updateAnnotation(_ annotation: Annotation, forBinaryUUID uuid: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            var data = self.loadData(forBinaryUUID: uuid)
            if let index = data.annotations.firstIndex(where: { $0.id == annotation.id }) {
                data.annotations[index] = annotation
            }
            self.saveData(data, forBinaryUUID: uuid)
        }
    }

    // MARK: - Sorting

    func bookmarksSortedByAddress(forBinaryUUID uuid: String) -> [Bookmark] {
        return bookmarks(forBinaryUUID: uuid).sorted { $0.address < $1.address }
    }

    func bookmarksSortedByDate(forBinaryUUID uuid: String) -> [Bookmark] {
        return bookmarks(forBinaryUUID: uuid).sorted { $0.dateCreated > $1.dateCreated }
    }

    func annotationsSortedByAddress(forBinaryUUID uuid: String) -> [Annotation] {
        return annotations(forBinaryUUID: uuid).sorted { $0.address < $1.address }
    }

    func annotationsSortedByDate(forBinaryUUID uuid: String) -> [Annotation] {
        return annotations(forBinaryUUID: uuid).sorted { $0.dateModified > $1.dateModified }
    }

    // MARK: - Persistence

    private func touchCacheEntry(_ uuid: String) {
        cacheAccessOrder.removeAll { $0 == uuid }
        cacheAccessOrder.append(uuid)
        while cacheAccessOrder.count > BookmarkStore.maxCacheSize {
            let evicted = cacheAccessOrder.removeFirst()
            cache.removeValue(forKey: evicted)
        }
    }

    private func loadData(forBinaryUUID uuid: String) -> BookmarkData {
        if let cached = cache[uuid] {
            touchCacheEntry(uuid)
            return cached
        }

        guard let url = fileURL(forBinaryUUID: uuid),
              fileManager.fileExists(atPath: url.path) else {
            return BookmarkData()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let raw = try Data(contentsOf: url)
            let data = try decoder.decode(BookmarkData.self, from: raw)
            cache[uuid] = data
            touchCacheEntry(uuid)
            return data
        } catch {
            print("BookmarkStore: Failed to load data for \(uuid): \(error)")
            return BookmarkData()
        }
    }

    private func saveData(_ data: BookmarkData, forBinaryUUID uuid: String) {
        cache[uuid] = data
        touchCacheEntry(uuid)

        guard let url = fileURL(forBinaryUUID: uuid) else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let raw = try encoder.encode(data)
            try raw.write(to: url, options: .atomic)
        } catch {
            print("BookmarkStore: Failed to save data for \(uuid): \(error)")
        }
    }

    private func fileURL(forBinaryUUID uuid: String) -> URL? {
        guard let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let redyneDir = documentsDir.appendingPathComponent("ReDyne", isDirectory: true)
        let bookmarksDir = redyneDir.appendingPathComponent("Bookmarks", isDirectory: true)
        try? fileManager.createDirectory(at: bookmarksDir, withIntermediateDirectories: true)

        // Sanitize the UUID string for use as a filename
        let sanitized = uuid.replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return bookmarksDir.appendingPathComponent("\(sanitized).json")
    }
}
