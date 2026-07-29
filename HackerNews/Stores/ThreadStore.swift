import Foundation

/// Loads and manages one story's comment thread.
///
/// The whole tree comes from HN Search in a single request. That index lags
/// live posts by a few minutes, so anything it can't answer for falls back to
/// walking the Firebase API level by level.
@MainActor
final class ThreadStore: ObservableObject {
    @Published private(set) var story: Item
    @Published private(set) var nodes: [CommentNode] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published private(set) var collapsed: Set<Int> = []

    private var loadTask: Task<Void, Never>?
    private let maxFallbackDepth = 8

    init(story: Item) {
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

        // Fill in fields a search result or saved copy may be missing.
        if force || story.kids.isEmpty {
            if let fresh = await HNAPI.shared.item(story.id, force: force) {
                story = merge(fresh, into: story)
            }
        }

        guard !Task.isCancelled else { return }

        if let comments = await searchIndexThread(), !comments.isEmpty || story.kids.isEmpty {
            guard !Task.isCancelled else { return }
            apply(comments, autoCollapseDeep: autoCollapseDeep)
            return
        }

        let comments = await firebaseThread()
        guard !Task.isCancelled else { return }

        if comments.isEmpty && !story.kids.isEmpty {
            phase = .failed("Couldn't load the discussion.")
        } else {
            apply(comments, autoCollapseDeep: autoCollapseDeep)
        }
    }

    private func apply(_ comments: [CommentNode], autoCollapseDeep: Bool) {
        nodes = comments
        if autoCollapseDeep {
            collapsed = Set(
                comments.filter { $0.depth >= 2 && $0.descendantCount > 0 }.map(\.id)
            )
        }
        phase = .loaded
    }

    private func searchIndexThread() async -> [CommentNode]? {
        guard let result = try? await AlgoliaAPI.shared.thread(for: story.id) else { return nil }
        if let indexed = result.story {
            story = merge(indexed, into: story)
        }
        return result.comments
    }

    /// Level-by-level walk of the official API, used when search hasn't
    /// indexed the story yet.
    private func firebaseThread() async -> [CommentNode] {
        let comments = await children(of: story.kids, depth: 0)
        return comments.withDescendantCounts()
    }

    private func children(of ids: [Int], depth: Int) async -> [CommentNode] {
        guard !ids.isEmpty, depth <= maxFallbackDepth else { return [] }

        let items = await HNAPI.shared.items(ids)
        var result: [CommentNode] = []

        for item in items {
            let isDeleted = item.deleted || ((item.text ?? "").isEmpty && item.by == nil)
            if isDeleted && item.kids.isEmpty { continue }

            result.append(
                CommentNode(
                    id: item.id,
                    parent: item.parent,
                    author: item.by,
                    html: item.text ?? "",
                    time: item.time,
                    depth: depth,
                    isDeleted: isDeleted
                )
            )

            if !item.kids.isEmpty {
                result += await children(of: item.kids, depth: depth + 1)
            }
        }

        return result
    }

    /// Search hits carry points and titles but no `kids`; the Firebase record
    /// carries `kids` but search is fresher on scores. Take the best of both.
    private func merge(_ incoming: Item, into existing: Item) -> Item {
        var merged = existing
        if let title = incoming.title, !title.isEmpty { merged.title = title }
        if let url = incoming.url, !url.isEmpty { merged.url = url }
        if let text = incoming.text, !text.isEmpty { merged.text = text }
        if let by = incoming.by { merged.by = by }
        if let time = incoming.time { merged.time = time }
        if let score = incoming.score { merged.score = score }
        if let descendants = incoming.descendants { merged.descendants = descendants }
        if !incoming.kids.isEmpty { merged.kids = incoming.kids }
        if incoming.kind != .unknown { merged.kind = incoming.kind }
        merged.deleted = incoming.deleted || existing.deleted
        merged.dead = incoming.dead || existing.dead
        return merged
    }
}
