import Foundation

enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case stories, comments, ask, show

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stories: return "Stories"
        case .comments: return "Comments"
        case .ask: return "Ask HN"
        case .show: return "Show HN"
        }
    }

    var tag: String {
        switch self {
        case .stories: return "story"
        case .comments: return "comment"
        case .ask: return "ask_hn"
        case .show: return "show_hn"
        }
    }
}

enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case relevance, date

    var id: String { rawValue }
    var title: String { self == .relevance ? "Relevance" : "Newest" }
    var path: String { self == .relevance ? "search" : "search_by_date" }
}

enum SearchPeriod: String, CaseIterable, Identifiable, Sendable {
    case allTime, day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .allTime: return "All time"
        case .day: return "Past 24h"
        case .week: return "Past week"
        case .month: return "Past month"
        case .year: return "Past year"
        }
    }

    /// Seconds of look-back, or nil for no time filter.
    var window: TimeInterval? {
        switch self {
        case .allTime: return nil
        case .day: return 86_400
        case .week: return 7 * 86_400
        case .month: return 30 * 86_400
        case .year: return 365 * 86_400
        }
    }
}

struct SearchResults: Sendable {
    var items: [Item] = []
    var page = 0
    var totalPages = 0
    var totalHits = 0

    var hasMore: Bool { page + 1 < totalPages }
}

/// Client for HN Search (the Algolia-backed index at hn.algolia.com).
///
/// Two jobs: full-text search, and pulling an entire comment tree in a single
/// request. The latter is why threads open fast — walking the Firebase API
/// would need one request per comment.
actor AlgoliaAPI {
    static let shared = AlgoliaAPI()

    private let base = URL(string: "https://hn.algolia.com/api/v1")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 45
        config.waitsForConnectivity = true
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "hn-search"
        )
        session = URLSession(configuration: config)
    }

    // MARK: - Search

    func search(
        query: String,
        scope: SearchScope,
        sort: SearchSort,
        period: SearchPeriod,
        page: Int = 0,
        hitsPerPage: Int = 30
    ) async throws -> SearchResults {
        var components = URLComponents(
            url: base.appendingPathComponent(sort.path),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "tags", value: scope.tag),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: String(hitsPerPage)),
        ]
        if let window = period.window {
            let cutoff = Int(Date().addingTimeInterval(-window).timeIntervalSince1970)
            queryItems.append(URLQueryItem(name: "numericFilters", value: "created_at_i>\(cutoff)"))
        }
        components.queryItems = queryItems

        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return SearchResults(
            items: response.hits.compactMap { $0.asItem },
            page: response.page,
            totalPages: response.nbPages,
            totalHits: response.nbHits
        )
    }

    /// Stories or comments submitted by one account, newest first.
    func submissions(by author: String, scope: SearchScope, page: Int = 0) async throws -> SearchResults {
        var components = URLComponents(
            url: base.appendingPathComponent("search_by_date"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "author_\(author),\(scope.tag)"),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "hitsPerPage", value: "30"),
        ]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return SearchResults(
            items: response.hits.compactMap { $0.asItem },
            page: response.page,
            totalPages: response.nbPages,
            totalHits: response.nbHits
        )
    }

    // MARK: - Threads

    /// The whole comment tree for a story in one request, already flattened
    /// into reading order.
    func thread(for id: Int) async throws -> (story: Item?, comments: [CommentNode]) {
        let url = base.appendingPathComponent("items/\(id)")
        let data = try await get(url)
        let root = try JSONDecoder().decode(ThreadNode.self, from: data)

        var flat: [CommentNode] = []
        flatten(root.children, depth: 0, into: &flat)
        return (root.asStory, flat.withDescendantCounts())
    }

    private func flatten(_ nodes: [ThreadNode], depth: Int, into out: inout [CommentNode]) {
        for node in nodes {
            let text = node.text ?? ""
            let isDeleted = node.author == nil && text.isEmpty
            // Deleted comments with no surviving replies add nothing; deleted
            // comments that still have replies are kept as placeholders so the
            // thread doesn't lose its shape.
            if isDeleted && node.children.isEmpty { continue }
            out.append(
                CommentNode(
                    id: node.id,
                    parent: node.parentID,
                    author: node.author,
                    html: text,
                    time: node.createdAt.map { Date(timeIntervalSince1970: $0) },
                    depth: depth,
                    isDeleted: isDeleted
                )
            )
            flatten(node.children, depth: depth + 1, into: &out)
        }
    }

    // MARK: - Plumbing

    private func get(_ url: URL) async throws -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HNError.badStatus(http.statusCode)
            }
            return data
        } catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw HNError.offline
        }
    }
}

// MARK: - Wire format

private struct SearchResponse: Decodable {
    var hits: [SearchHit] = []
    var page = 0
    var nbPages = 0
    var nbHits = 0

    private enum CodingKeys: String, CodingKey { case hits, page, nbPages, nbHits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hits = c.lenient([SearchHit].self, .hits) ?? []
        page = c.lenient(Int.self, .page) ?? 0
        nbPages = c.lenient(Int.self, .nbPages) ?? 0
        nbHits = c.lenient(Int.self, .nbHits) ?? 0
    }
}

private struct SearchHit: Decodable {
    var objectID: String = ""
    var title: String?
    var url: String?
    var author: String?
    var points: Int?
    var numComments: Int?
    var createdAt: Double?
    var storyText: String?
    var commentText: String?
    var storyTitle: String?
    var storyID: Int?
    var parentID: Int?
    var tags: [String] = []

    private enum CodingKeys: String, CodingKey {
        case objectID, title, url, author, points
        case numComments = "num_comments"
        case createdAt = "created_at_i"
        case storyText = "story_text"
        case commentText = "comment_text"
        case storyTitle = "story_title"
        case storyID = "story_id"
        case parentID = "parent_id"
        case tags = "_tags"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        objectID = c.lenient(String.self, .objectID) ?? ""
        title = c.lenient(String.self, .title)
        url = c.lenient(String.self, .url)
        author = c.lenient(String.self, .author)
        points = c.lenient(Int.self, .points)
        numComments = c.lenient(Int.self, .numComments)
        createdAt = c.lenient(Double.self, .createdAt)
        storyText = c.lenient(String.self, .storyText)
        commentText = c.lenient(String.self, .commentText)
        storyTitle = c.lenient(String.self, .storyTitle)
        storyID = c.lenient(Int.self, .storyID)
        parentID = c.lenient(Int.self, .parentID)
        tags = c.lenient([String].self, .tags) ?? []
    }

    var asItem: Item? {
        guard let id = Int(objectID) else { return nil }
        let isComment = tags.contains("comment")
        return Item(
            id: id,
            kind: isComment ? .comment : (tags.contains("job") ? .job : .story),
            by: author,
            time: createdAt.map { Date(timeIntervalSince1970: $0) },
            text: storyText ?? commentText,
            parent: parentID,
            url: url,
            score: points,
            title: title,
            descendants: numComments,
            storyTitle: storyTitle,
            storyID: storyID
        )
    }
}

private struct ThreadNode: Decodable {
    var id: Int = 0
    var type: String?
    var author: String?
    var title: String?
    var url: String?
    var text: String?
    var points: Int?
    var parentID: Int?
    var createdAt: Double?
    var children: [ThreadNode] = []

    private enum CodingKeys: String, CodingKey {
        case id, type, author, title, url, text, points, children
        case parentID = "parent_id"
        case createdAt = "created_at_i"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(Int.self, .id) ?? 0
        type = c.lenient(String.self, .type)
        author = c.lenient(String.self, .author)
        title = c.lenient(String.self, .title)
        url = c.lenient(String.self, .url)
        text = c.lenient(String.self, .text)
        points = c.lenient(Int.self, .points)
        parentID = c.lenient(Int.self, .parentID)
        createdAt = c.lenient(Double.self, .createdAt)
        children = c.lenient([ThreadNode].self, .children) ?? []
    }

    /// The root node doubles as the story record, which lets a deep link open
    /// a thread without a second round trip.
    var asStory: Item? {
        guard id > 0, type != "comment" else { return nil }
        return Item(
            id: id,
            kind: ItemKind.parse(type),
            by: author,
            time: createdAt.map { Date(timeIntervalSince1970: $0) },
            text: text,
            url: url,
            score: points,
            title: title
        )
    }
}
