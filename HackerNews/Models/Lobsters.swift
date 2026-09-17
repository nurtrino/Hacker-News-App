import Foundation

/// The story lists lobste.rs exposes as JSON.
enum LobstersFeed: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case active, hottest, newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .active: return "Active"
        case .hottest: return "Hottest"
        case .newest: return "Newest"
        }
    }

    var longTitle: String {
        switch self {
        case .active: return "Lobsters · Active"
        case .hottest: return "Lobsters · Hottest"
        case .newest: return "Lobsters · Newest"
        }
    }

    var systemImage: String {
        switch self {
        case .active: return "bubble.left.and.bubble.right"
        case .hottest: return "flame"
        case .newest: return "clock"
        }
    }

    /// Path (without host) of the JSON list for a 1-based page. The first
    /// page has its own short route; later pages use the `/page/N` form.
    func path(page: Int) -> String {
        switch self {
        case .active: return page <= 1 ? "/active.json" : "/active/page/\(page).json"
        case .newest: return page <= 1 ? "/newest.json" : "/newest/page/\(page).json"
        case .hottest: return page <= 1 ? "/hottest.json" : "/page/\(page).json"
        }
    }

    /// The equivalent web page, for "open on Lobsters".
    var webURL: URL {
        switch self {
        case .active: return URL(string: "https://lobste.rs/active")!
        case .hottest: return URL(string: "https://lobste.rs")!
        case .newest: return URL(string: "https://lobste.rs/newest")!
        }
    }
}

/// One lobste.rs submission, as returned by the list and story endpoints.
struct LobstersStory: Identifiable, Hashable, Sendable {
    /// Lobsters' own identifier, e.g. `lzgsvb`.
    let shortID: String
    var title: String
    /// External link; empty or missing for text posts.
    var url: String?
    var score: Int
    var commentCount: Int
    /// Text-post body as HTML.
    var descriptionHTML: String?
    /// The discussion page on lobste.rs (with the title slug).
    var commentsURL: String?
    var submitter: String?
    var tags: [String]
    var createdAt: Date?

    var id: String { shortID }

    /// Parses one story object. Every field but the id is optional, and a
    /// wrongly-typed field is treated as missing rather than failing the row.
    init?(json: [String: Any]) {
        guard let shortID = json["short_id"] as? String, !shortID.isEmpty else { return nil }
        self.shortID = shortID
        title = (json["title"] as? String) ?? "(untitled)"
        url = (json["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        score = LobstersJSON.int(json["score"]) ?? 0
        commentCount = LobstersJSON.int(json["comment_count"]) ?? 0
        descriptionHTML = (json["description"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        commentsURL = json["comments_url"] as? String
        submitter = LobstersJSON.username(json["submitter_user"])
        tags = (json["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
        createdAt = LobstersJSON.date(json["created_at"])
    }
}

extension LobstersStory {
    /// Stable integer used for read-state, which is keyed by `Int` because
    /// Hacker News ids are.
    var numericID: Int { LobstersID.number(for: shortID) }

    var author: String { submitter ?? "unknown" }

    /// The external article link, if this story points off-site.
    var link: URL? {
        guard let url, let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return parsed
    }

    /// The canonical discussion page.
    var lobstersURL: URL {
        if let commentsURL, let parsed = URL(string: commentsURL) { return parsed }
        return URL(string: "https://lobste.rs/s/\(shortID)")!
    }

    /// Where the story goes when tapped — the article for link posts, the
    /// discussion for text posts.
    var primaryURL: URL { link ?? lobstersURL }

    /// `example.com` for `https://www.example.com/a/b`.
    var host: String? {
        guard let host = link?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var isTextPost: Bool { link == nil }

    /// Single character for the row's monogram badge.
    var sourceLabel: String {
        if let host, let first = host.first { return String(first).uppercased() }
        return "L"
    }
}

/// A story and its already-flattened discussion.
struct LobstersThread: Sendable {
    var story: LobstersStory?
    var comments: [CommentNode]
}

// MARK: - Helpers

/// Lobsters ids are short strings; the rest of the app keys things on `Int`.
enum LobstersID {
    /// FNV-1a, folded into a positive `Int` with bit 40 forced on so it can
    /// never collide with a Hacker News id in the shared read-state list.
    static func number(for shortID: String) -> Int {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in shortID.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let folded = (hash | (1 << 40)) & 0x7fff_ffff_ffff_ffff
        return Int(truncatingIfNeeded: folded)
    }
}

enum LobstersJSON {
    static func int(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? Double { return Int(number) }
        if let text = value as? String { return Int(text) }
        return nil
    }

    /// Newer API versions send a bare username; older ones an object.
    static func username(_ value: Any?) -> String? {
        if let name = value as? String { return name.isEmpty ? nil : name }
        if let object = value as? [String: Any], let name = object["username"] as? String {
            return name.isEmpty ? nil : name
        }
        return nil
    }

    /// `2024-05-01T10:23:45.000-05:00`, with or without the fraction.
    static func date(_ value: Any?) -> Date? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}

/// Lobsters renders Markdown, so its HTML uses a few block tags HN never
/// emits. Rewrite those into the `<p>`/`<b>`/`<i>` subset the shared parser
/// understands rather than teaching it a second dialect.
enum LobstersHTML {
    static func normalize(_ html: String) -> String {
        guard html.contains("<") else { return html }
        var output = html
        let rules: [(String, String)] = [
            ("<blockquote>", "<p><i>"),
            ("</blockquote>", "</i><p>"),
            ("<li>", "<p>• "),
            ("</li>", ""),
            ("<h1>", "<p><b>"), ("</h1>", "</b><p>"),
            ("<h2>", "<p><b>"), ("</h2>", "</b><p>"),
            ("<h3>", "<p><b>"), ("</h3>", "</b><p>"),
            ("<h4>", "<p><b>"), ("</h4>", "</b><p>"),
            ("<h5>", "<p><b>"), ("</h5>", "</b><p>"),
            ("<h6>", "<p><b>"), ("</h6>", "</b><p>"),
            ("<hr>", "<p>"), ("<hr/>", "<p>"), ("<hr />", "<p>"),
        ]
        for (from, to) in rules {
            output = output.replacingOccurrences(of: from, with: to, options: [.caseInsensitive])
        }
        return output
    }

    /// Flattens the `comments` array of a story response into reading order.
    ///
    /// Lobsters already returns comments thread-sorted, each with its parent
    /// id, so depth comes from the parent's depth rather than a tree walk.
    static func nodes(from comments: [[String: Any]]) -> [CommentNode] {
        var depthByID: [String: Int] = [:]
        var result: [CommentNode] = []
        result.reserveCapacity(comments.count)

        for json in comments {
            guard let shortID = json["short_id"] as? String, !shortID.isEmpty else { continue }
            let parentID = (json["parent_comment"] as? String).flatMap { $0.isEmpty ? nil : $0 }

            let depth: Int
            if let parentID, let parentDepth = depthByID[parentID] {
                depth = parentDepth + 1
            } else if let explicit = LobstersJSON.int(json["depth"]) {
                depth = max(0, explicit)
            } else if let indent = LobstersJSON.int(json["indent_level"]) {
                depth = max(0, indent - 1)
            } else {
                depth = 0
            }
            depthByID[shortID] = depth

            let html = (json["comment"] as? String) ?? ""
            let author = LobstersJSON.username(json["commenting_user"])
            let isDeleted = ((json["is_deleted"] as? Bool) ?? false) || (html.isEmpty && author == nil)
            let permalink = (json["url"] as? String).flatMap { URL(string: $0) }
                ?? URL(string: "https://lobste.rs/c/\(shortID)")

            result.append(
                CommentNode(
                    id: LobstersID.number(for: shortID),
                    parent: parentID.map(LobstersID.number(for:)),
                    author: author,
                    html: normalize(html),
                    time: LobstersJSON.date(json["created_at"]),
                    depth: depth,
                    isDeleted: isDeleted,
                    forum: .lobsters,
                    permalink: permalink
                )
            )
        }

        // A deleted comment with no surviving replies adds nothing; one that
        // still has replies stays as a placeholder so the thread keeps shape.
        var kept: [CommentNode] = []
        kept.reserveCapacity(result.count)
        for (index, node) in result.enumerated() {
            let hasReplies = index + 1 < result.count && result[index + 1].depth > node.depth
            if node.isDeleted && !hasReplies { continue }
            kept.append(node)
        }
        return kept.withDescendantCounts()
    }
}
