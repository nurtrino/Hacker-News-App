import Foundation

/// Debounced, paginated full-text search over HN.
@MainActor
final class SearchStore: ObservableObject {
    @Published var query = ""
    @Published var scope: SearchScope = .stories { didSet { rerunIfNeeded(oldValue != scope) } }
    @Published var sort: SearchSort = .relevance { didSet { rerunIfNeeded(oldValue != sort) } }
    @Published var period: SearchPeriod = .allTime { didSet { rerunIfNeeded(oldValue != period) } }

    @Published private(set) var results: [Item] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var totalHits = 0
    @Published private(set) var recentSearches: [String] = []

    private var page = 0
    private var totalPages = 0
    private var searchTask: Task<Void, Never>?
    private let recentsKey = "recentSearches"
    private let recentsLimit = 12

    init() {
        recentSearches = UserDefaults.standard.stringArray(forKey: recentsKey) ?? []
    }

    var canLoadMore: Bool { page + 1 < totalPages }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Running searches

    /// Called on every keystroke; waits for a pause before hitting the network.
    func queryChanged() {
        searchTask?.cancel()

        guard !trimmedQuery.isEmpty else {
            results = []
            totalHits = 0
            phase = .idle
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await run(reset: true)
        }
    }

    /// Explicit submit (return key or tapping a recent search) skips the debounce.
    func submit() {
        searchTask?.cancel()
        guard !trimmedQuery.isEmpty else { return }
        rememberSearch(trimmedQuery)
        searchTask = Task { await run(reset: true) }
    }

    func loadMore() {
        guard canLoadMore, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        Task { await run(reset: false) }
    }

    func clear() {
        searchTask?.cancel()
        query = ""
        results = []
        totalHits = 0
        phase = .idle
    }

    private func rerunIfNeeded(_ changed: Bool) {
        guard changed, !trimmedQuery.isEmpty else { return }
        searchTask?.cancel()
        searchTask = Task { await run(reset: true) }
    }

    private func run(reset: Bool) async {
        let text = trimmedQuery
        guard !text.isEmpty else { return }

        if reset {
            page = 0
            phase = .loading
        }

        do {
            let nextPage = reset ? 0 : page + 1
            let response = try await AlgoliaAPI.shared.search(
                query: text,
                scope: scope,
                sort: sort,
                period: period,
                page: nextPage
            )
            guard !Task.isCancelled, text == trimmedQuery else { return }

            page = response.page
            totalPages = response.totalPages
            totalHits = response.totalHits
            results = reset ? response.items : results + response.items
            phase = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if reset { results = [] }
            phase = .failed((error as? HNError)?.errorDescription ?? error.localizedDescription)
        }
        isLoadingMore = false
    }

    // MARK: - Recent searches

    private func rememberSearch(_ text: String) {
        var recents = recentSearches.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        recents.insert(text, at: 0)
        if recents.count > recentsLimit { recents.removeLast(recents.count - recentsLimit) }
        recentSearches = recents
        UserDefaults.standard.set(recents, forKey: recentsKey)
    }

    func removeRecent(_ text: String) {
        recentSearches.removeAll { $0 == text }
        UserDefaults.standard.set(recentSearches, forKey: recentsKey)
    }

    func clearRecents() {
        recentSearches = []
        UserDefaults.standard.set([String](), forKey: recentsKey)
    }
}
