import Foundation

enum LoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case failed(String)

    var isLoading: Bool { self == .loading }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

/// One paginated story list.
///
/// The Firebase API hands back up to 500 ids at once and nothing else, so the
/// store keeps the id list and hydrates it a page at a time.
@MainActor
final class FeedStore: ObservableObject {
    let feed: Feed

    @Published private(set) var items: [Item] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var lastUpdated: Date?

    private var ids: [Int] = []
    private var cursor = 0
    private let pageSize = 25
    private var loadTask: Task<Void, Never>?

    init(feed: Feed) {
        self.feed = feed
    }

    var canLoadMore: Bool { cursor < ids.count }

    var isEmpty: Bool { items.isEmpty }

    /// Called from `.task` — a no-op once the feed has content.
    func loadIfNeeded() {
        guard items.isEmpty, phase != .loading else { return }
        start(force: false)
    }

    /// Pull-to-refresh. Runs to completion so the spinner behaves.
    func refresh() async {
        loadTask?.cancel()
        await reload(force: true)
    }

    func retry() {
        start(force: true)
    }

    func loadMore() {
        guard canLoadMore, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        Task {
            let page = Array(ids[cursor..<min(cursor + pageSize, ids.count)])
            let fetched = await HNAPI.shared.items(page)
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
            cursor += page.count
            items.append(contentsOf: fetched.filter { !$0.deleted })
            isLoadingMore = false
        }
    }

    // MARK: - Internals

    private func start(force: Bool) {
        loadTask?.cancel()
        loadTask = Task { await reload(force: force) }
    }

    private func reload(force: Bool) async {
        if items.isEmpty { phase = .loading }

        do {
            let fetchedIDs = try await HNAPI.shared.ids(for: feed, force: force)
            guard !Task.isCancelled else { return }

            ids = fetchedIDs
            cursor = 0

            let page = Array(ids.prefix(pageSize))
            let fetched = await HNAPI.shared.items(page, force: force)
            guard !Task.isCancelled else { return }

            cursor = page.count
            items = fetched.filter { !$0.deleted }
            lastUpdated = Date()
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if items.isEmpty {
                phase = .failed(message(for: error))
            } else {
                // Keep showing what we have; a failed refresh isn't fatal.
                phase = .loaded
            }
        }
    }

    private func message(for error: Error) -> String {
        if let hnError = error as? HNError, let description = hnError.errorDescription {
            return description
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "You appear to be offline."
        }
        return error.localizedDescription
    }
}

/// Keeps one `FeedStore` alive per feed so switching tabs doesn't throw away
/// scroll position or force a refetch.
@MainActor
final class FeedStores: ObservableObject {
    private var stores: [Feed: FeedStore] = [:]

    func store(for feed: Feed) -> FeedStore {
        if let existing = stores[feed] { return existing }
        let created = FeedStore(feed: feed)
        stores[feed] = created
        return created
    }
}
