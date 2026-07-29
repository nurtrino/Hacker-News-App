import Foundation

/// The kind of object the HN API returned. Unknown values become `.unknown`
/// rather than failing the whole item.
enum ItemKind: String, Codable, Hashable, Sendable {
    case story, comment, job, poll, pollopt, unknown

    static func parse(_ raw: String?) -> ItemKind {
        guard let raw else { return .story }
        return ItemKind(rawValue: raw) ?? .unknown
    }
}

/// Forgiving accessors: the Firebase API omits keys entirely for missing
/// values and occasionally returns `null` for keys it does include, so a
/// failed decode of one field should never take down the whole item.
extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

/// A single Hacker News object (story, comment, job, poll).
struct Item: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    var kind: ItemKind = .story
    var deleted = false
    var dead = false
    var by: String?
    var time: Date?
    var text: String?
    var parent: Int?
    var kids: [Int] = []
    var url: String?
    var score: Int?
    var title: String?
    var descendants: Int?

    /// Set when the item came from a search index that already knew its parent
    /// story — used to label comment hits.
    var storyTitle: String?
    var storyID: Int?

    init(
        id: Int,
        kind: ItemKind = .story,
        deleted: Bool = false,
        dead: Bool = false,
        by: String? = nil,
        time: Date? = nil,
        text: String? = nil,
        parent: Int? = nil,
        kids: [Int] = [],
        url: String? = nil,
        score: Int? = nil,
        title: String? = nil,
        descendants: Int? = nil,
        storyTitle: String? = nil,
        storyID: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.deleted = deleted
        self.dead = dead
        self.by = by
        self.time = time
        self.text = text
        self.parent = parent
        self.kids = kids
        self.url = url
        self.score = score
        self.title = title
        self.descendants = descendants
        self.storyTitle = storyTitle
        self.storyID = storyID
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, deleted, dead, by, time, text, parent, kids, url, score
        case title, descendants, storyTitle, storyID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = ItemKind.parse(c.lenient(String.self, .type))
        deleted = c.lenient(Bool.self, .deleted) ?? false
        dead = c.lenient(Bool.self, .dead) ?? false
        by = c.lenient(String.self, .by)
        if let epoch = c.lenient(Double.self, .time) {
            time = Date(timeIntervalSince1970: epoch)
        }
        text = c.lenient(String.self, .text)
        parent = c.lenient(Int.self, .parent)
        kids = c.lenient([Int].self, .kids) ?? []
        url = c.lenient(String.self, .url)
        score = c.lenient(Int.self, .score)
        title = c.lenient(String.self, .title)
        descendants = c.lenient(Int.self, .descendants)
        storyTitle = c.lenient(String.self, .storyTitle)
        storyID = c.lenient(Int.self, .storyID)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind.rawValue, forKey: .type)
        if deleted { try c.encode(true, forKey: .deleted) }
        if dead { try c.encode(true, forKey: .dead) }
        try c.encodeIfPresent(by, forKey: .by)
        try c.encodeIfPresent(time?.timeIntervalSince1970, forKey: .time)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encodeIfPresent(parent, forKey: .parent)
        if !kids.isEmpty { try c.encode(kids, forKey: .kids) }
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(score, forKey: .score)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(descendants, forKey: .descendants)
        try c.encodeIfPresent(storyTitle, forKey: .storyTitle)
        try c.encodeIfPresent(storyID, forKey: .storyID)
    }
}

extension Item {
    /// Story titles are always present in practice, but jobs and dead posts
    /// occasionally arrive without one.
    var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let storyTitle, !storyTitle.isEmpty { return storyTitle }
        return "(untitled)"
    }

    var author: String { by ?? "unknown" }

    /// The external article link, if this story points off-site.
    var link: URL? {
        guard let url, !url.isEmpty, let parsed = URL(string: url), parsed.scheme != nil else {
            return nil
        }
        return parsed
    }

    /// The canonical `news.ycombinator.com` page for this item.
    var hnURL: URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }

    /// Where the story goes when tapped — the article for link posts, the
    /// discussion for text posts.
    var primaryURL: URL { link ?? hnURL }

    /// `example.com` for `https://www.example.com/a/b`.
    var host: String? {
        guard let host = link?.host, !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var commentCount: Int { descendants ?? 0 }

    var isTextPost: Bool { link == nil }

    var isAsk: Bool { displayTitle.lowercased().hasPrefix("ask hn") }
    var isShow: Bool { displayTitle.lowercased().hasPrefix("show hn") }

    /// Single character for the row's monogram badge.
    var sourceLabel: String {
        if let host, let first = host.first { return String(first).uppercased() }
        if kind == .job { return "J" }
        if isAsk { return "A" }
        if isShow { return "S" }
        return "Y"
    }
}
