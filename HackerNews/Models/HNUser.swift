import Foundation

/// A Hacker News account profile.
struct HNUser: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var created: Date?
    var karma: Int = 0
    var about: String?
    var submitted: [Int] = []

    init(id: String, created: Date? = nil, karma: Int = 0, about: String? = nil, submitted: [Int] = []) {
        self.id = id
        self.created = created
        self.karma = karma
        self.about = about
        self.submitted = submitted
    }

    private enum CodingKeys: String, CodingKey {
        case id, created, karma, about, submitted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let epoch = c.lenient(Double.self, .created) {
            created = Date(timeIntervalSince1970: epoch)
        }
        karma = c.lenient(Int.self, .karma) ?? 0
        about = c.lenient(String.self, .about)
        submitted = c.lenient([Int].self, .submitted) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(created?.timeIntervalSince1970, forKey: .created)
        try c.encode(karma, forKey: .karma)
        try c.encodeIfPresent(about, forKey: .about)
    }

    var profileURL: URL {
        URL(string: "https://news.ycombinator.com/user?id=\(id)")!
    }
}
