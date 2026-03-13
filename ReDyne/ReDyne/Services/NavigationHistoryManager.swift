import Foundation

// MARK: - Navigation Entry

/// Represents a single navigation action that can be replayed via back/forward traversal.
enum NavigationEntry: Equatable {
    /// User switched to one of the 5 main sections (0 = Info, 1 = Symbols, 2 = Strings, 3 = Code, 4 = Functions).
    case section(index: Int)

    /// User jumped to a disassembly address.
    case disassembly(address: UInt64)

    /// User navigated to a symbol by name.
    case symbol(name: String)

    /// User opened the hex viewer at a given file offset.
    case hexView(offset: UInt64)
}

// MARK: - NavigationHistoryManager

/// Maintains a bounded back/forward navigation stack, similar to a web browser.
///
/// Usage:
/// - Call `push(entry:)` every time the user performs a navigation action.
/// - Call `goBack()` / `goForward()` to traverse the history.
/// - Pushing a new entry while the cursor is not at the end of the stack discards the forward history.
final class NavigationHistoryManager {

    // MARK: - Configuration

    /// Maximum number of entries retained in the history stack.
    static let maxDepth = 50

    // MARK: - State

    /// The ordered list of navigation entries.
    private(set) var entries: [NavigationEntry] = []

    /// Points to the *current* position in `entries`.
    /// A value of -1 means no history has been recorded yet.
    private(set) var currentIndex: Int = -1

    /// `true` when we are replaying an entry (back/forward) so that `push` is suppressed.
    private var isReplaying = false

    // MARK: - Public API

    /// Whether there is at least one entry behind the current position.
    var canGoBack: Bool {
        return currentIndex > 0
    }

    /// Whether there is at least one entry ahead of the current position.
    var canGoForward: Bool {
        return currentIndex < entries.count - 1
    }

    /// Records a new navigation entry.
    ///
    /// - If the user has gone back and then performs a new navigation, the forward history is discarded.
    /// - Consecutive duplicate entries are coalesced (not added twice in a row).
    /// - The stack is trimmed from the front when it exceeds `maxDepth`.
    func push(entry: NavigationEntry) {
        // Don't record while replaying back/forward.
        guard !isReplaying else { return }

        // Coalesce consecutive identical entries.
        if currentIndex >= 0, currentIndex < entries.count, entries[currentIndex] == entry {
            return
        }

        // Discard forward history.
        if currentIndex < entries.count - 1 {
            entries.removeSubrange((currentIndex + 1)...)
        }

        entries.append(entry)
        currentIndex = entries.count - 1

        // Enforce max depth by trimming the oldest entries.
        if entries.count > NavigationHistoryManager.maxDepth {
            let overflow = entries.count - NavigationHistoryManager.maxDepth
            entries.removeFirst(overflow)
            currentIndex -= overflow
        }
    }

    /// Moves one step back in the history and returns the entry to navigate to.
    /// Returns `nil` if there is no previous entry.
    func goBack() -> NavigationEntry? {
        guard canGoBack else { return nil }
        currentIndex -= 1
        return entries[currentIndex]
    }

    /// Moves one step forward in the history and returns the entry to navigate to.
    /// Returns `nil` if there is no next entry.
    func goForward() -> NavigationEntry? {
        guard canGoForward else { return nil }
        currentIndex += 1
        return entries[currentIndex]
    }

    /// Executes `body` while suppressing `push(entry:)` calls.
    /// Use this when replaying a history entry to avoid polluting the stack.
    func performWithoutRecording(_ body: () -> Void) {
        isReplaying = true
        body()
        isReplaying = false
    }

    /// Removes all history entries and resets the cursor.
    func clear() {
        entries.removeAll()
        currentIndex = -1
    }
}
