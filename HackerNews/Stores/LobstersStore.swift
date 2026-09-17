import Foundation

/// One paginated lobste.rs story list.
///
/// Unlike the Firebase feeds there's no id list to hydrate: each page comes
/// back fully populated, so the store just walks page numbers until a page
/// comes back empty.
@MainActor
final class LobstersFeedStore: ObservableObject {
    let feed: LobstersFeed

    @Published private(set) var items: [LobstersStory] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var lastUpdated: Date?

    private var page = 1
    /// Lobsters' own lists stop well before this; it's a guard against
    /// paging forever on a feed that never returns an empty page.
    private let maxPages = 20
    private var loadTask: Task<Void, Never>?

    init(feed: LobstersFeed) {
        self.feed = feed
    }

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
        let nextPage = page + 1
        Task {
            let fetched = (try? await LobstersAPI.shared.stories(in: feed, page: nextPage)) ?? []
            guard !Task.isCancelled else {
                isLoadingMore = false
                return
            }
            append(fetched)
            page = nextPage
            canLoadMore = !fetched.isEmpty && nextPage < maxPages
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
            let fetched = try await LobstersAPI.shared.stories(in: feed, page: 1, force: force)
            guard !Task.isCancelled else { return }

            items = fetched
            page = 1
            canLoadMore = !fetched.isEmpty
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

    /// The active list reorders between pages, so a story can show up on two
    /// consecutive pages. Drop the repeats rather than showing them twice.
    private func append(_ fetched: [LobstersStory]) {
        var seen = Set(items.map(\.shortID))
        for story in fetched where !seen.contains(story.shortID) {
            seen.insert(story.shortID)
            items.append(story)
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

/// Keeps one `LobstersFeedStore` alive per feed so switching keeps scroll
/// position and cache.
@MainActor
final class LobstersFeedStores: ObservableObject {
    private var stores: [LobstersFeed: LobstersFeedStore] = [:]

    func store(for feed: LobstersFeed) -> LobstersFeedStore {
        if let existing = stores[feed] { return existing }
        let created = LobstersFeedStore(feed: feed)
        stores[feed] = created
        return created
    }
}

/// Loads and manages one Lobsters story's comment thread.
///
/// The story endpoint returns the whole discussion, thread-sorted, so there's
/// no index-vs-canonical dance here — one request, then collapse state.
@MainActor
final class LobstersThreadStore: ObservableObject {
    @Published private(set) var story: LobstersStory
    @Published private(set) var nodes: [CommentNode] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var collapsed: Set<Int> = []

    private var loadTask: Task<Void, Never>?

    init(story: LobstersStory) {
        self.story = story
    }

    /// Comments with collapsed subtrees skipped.
    var visibleNodes: [CommentNode] {
        guard !collapsed.isEmpty else { return nodes }

        var result: [CommentNode] = []
        result.reserveCapacity(nodes.count)
        var skipBelowDepth: Int?

        for node in nodes {
            if let depth = skipBelowDepth {
                if node.depth > depth { continue }
                skipBelowDepth = nil
            }
            result.append(node)
            if collapsed.contains(node.id) { skipBelowDepth = node.depth }
        }
        return result
    }

    var totalComments: Int { nodes.count }

    func isCollapsed(_ id: Int) -> Bool { collapsed.contains(id) }

    func toggleCollapse(_ node: CommentNode) {
        if collapsed.contains(node.id) {
            collapsed.remove(node.id)
        } else {
            collapsed.insert(node.id)
        }
    }

    func collapseAll() {
        collapsed = Set(nodes.filter { $0.isTopLevel && $0.descendantCount > 0 }.map(\.id))
    }

    func expandAll() {
        collapsed.removeAll()
    }

    var isFullyCollapsed: Bool {
        !nodes.isEmpty && nodes.filter(\.isTopLevel).allSatisfy {
            $0.descendantCount == 0 || collapsed.contains($0.id)
        }
    }

    // MARK: - Loading

    func loadIfNeeded(autoCollapseDeep: Bool) {
        guard nodes.isEmpty, phase != .loading else { return }
        start(force: false, autoCollapseDeep: autoCollapseDeep)
    }

    func refresh(autoCollapseDeep: Bool) async {
        loadTask?.cancel()
        await load(force: true, autoCollapseDeep: autoCollapseDeep)
    }

    func retry(autoCollapseDeep: Bool) {
        start(force: true, autoCollapseDeep: autoCollapseDeep)
    }

    private func start(force: Bool, autoCollapseDeep: Bool) {
        loadTask?.cancel()
        loadTask = Task { await load(force: force, autoCollapseDeep: autoCollapseDeep) }
    }

    private func load(force: Bool, autoCollapseDeep: Bool) async {
        if nodes.isEmpty { phase = .loading }

        do {
            let thread = try await LobstersAPI.shared.thread(story.shortID, force: force)
            guard !Task.isCancelled else { return }

            if let fresh = thread.story { story = fresh }
            nodes = thread.comments
            if autoCollapseDeep {
                collapsed = Set(
                    thread.comments.filter { $0.depth >= 2 && $0.descendantCount > 0 }.map(\.id)
                )
            }
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if nodes.isEmpty {
                phase = .failed(message(for: error))
            } else {
                phase = .loaded
            }
        }
    }

    private func message(for error: Error) -> String {
        if let hnError = error as? HNError, let description = hnError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
