import Foundation

/// Saved stories and read-state, persisted as JSON in Application Support.
///
/// Both lists are small (saved posts are user-curated, read ids are capped) so
/// they're kept fully in memory and written back asynchronously on change.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var saved: [Item] = []
    @Published private(set) var readIDs: Set<Int> = []

    /// Read ids are kept newest-first so the cap trims the oldest.
    private var readOrder: [Int] = []
    private let readCap = 5_000

    private let directory: URL
    private var writeTask: Task<Void, Never>?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("HackerNews", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: - Saved stories

    func isSaved(_ id: Int) -> Bool {
        saved.contains { $0.id == id }
    }

    /// Returns true if the item ended up saved.
    @discardableResult
    func toggleSave(_ item: Item) -> Bool {
        if let index = saved.firstIndex(where: { $0.id == item.id }) {
            saved.remove(at: index)
            scheduleWrite()
            return false
        }
        saved.insert(item, at: 0)
        scheduleWrite()
        return true
    }

    func removeSaved(ids: Set<Int>) {
        guard !ids.isEmpty else { return }
        saved.removeAll { ids.contains($0.id) }
        scheduleWrite()
    }

    func removeSaved(atOffsets offsets: IndexSet) {
        saved.remove(atOffsets: offsets)
        scheduleWrite()
    }

    func clearSaved() {
        saved.removeAll()
        scheduleWrite()
    }

    /// Keeps a saved copy in sync once the full item has been fetched (score
    /// and comment counts move after saving).
    func refreshSaved(with item: Item) {
        guard let index = saved.firstIndex(where: { $0.id == item.id }) else { return }
        saved[index] = item
        scheduleWrite()
    }

    // MARK: - Read state

    func isRead(_ id: Int) -> Bool { readIDs.contains(id) }

    func markRead(_ id: Int) {
        guard !readIDs.contains(id) else { return }
        readIDs.insert(id)
        readOrder.insert(id, at: 0)
        if readOrder.count > readCap {
            let dropped = readOrder[readCap...]
            readIDs.subtract(dropped)
            readOrder.removeLast(readOrder.count - readCap)
        }
        scheduleWrite()
    }

    func clearReadState() {
        readIDs.removeAll()
        readOrder.removeAll()
        scheduleWrite()
    }

    // MARK: - Persistence

    private var savedURL: URL { directory.appendingPathComponent("saved.json") }
    private var readURL: URL { directory.appendingPathComponent("read.json") }

    private func load() {
        if let data = try? Data(contentsOf: savedURL),
           let items = try? JSONDecoder().decode([Item].self, from: data) {
            saved = items
        }
        if let data = try? Data(contentsOf: readURL),
           let ids = try? JSONDecoder().decode([Int].self, from: data) {
            readOrder = ids
            readIDs = Set(ids)
        }
    }

    /// Coalesces bursts of changes (marking a screen of stories read) into one
    /// disk write.
    private func scheduleWrite() {
        writeTask?.cancel()
        let savedSnapshot = saved
        let readSnapshot = readOrder
        let savedURL = self.savedURL
        let readURL = self.readURL

        writeTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await Task.detached(priority: .utility) {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(savedSnapshot) {
                    try? data.write(to: savedURL, options: .atomic)
                }
                if let data = try? encoder.encode(readSnapshot) {
                    try? data.write(to: readURL, options: .atomic)
                }
            }.value
        }
    }

    /// Called when the app backgrounds, so nothing is lost to a pending delay.
    func flush() {
        writeTask?.cancel()
        let savedSnapshot = saved
        let readSnapshot = readOrder
        let encoder = JSONEncoder()
        if let data = try? encoder.encode(savedSnapshot) {
            try? data.write(to: savedURL, options: .atomic)
        }
        if let data = try? encoder.encode(readSnapshot) {
            try? data.write(to: readURL, options: .atomic)
        }
    }
}
