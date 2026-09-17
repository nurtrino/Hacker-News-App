import Foundation

/// Client for lobste.rs's JSON endpoints.
///
/// Lobsters has no separate API host: every HTML page has a `.json` twin,
/// and a story's JSON carries its whole comment tree, already thread-sorted.
actor LobstersAPI {
    static let shared = LobstersAPI()

    private let base = "https://lobste.rs"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 45
        // Lobsters asks automated clients to identify themselves.
        config.httpAdditionalHeaders = [
            "User-Agent": "HackerNewsApp/1.0 (+https://github.com/nurtrino/Hacker-News-App)",
            "Accept": "application/json",
        ]
        config.urlCache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "lobsters-api"
        )
        session = URLSession(configuration: config)
    }

    // MARK: - Story lists

    /// One page (about 25 stories) of a feed. An empty array means the list
    /// has run out.
    func stories(in feed: LobstersFeed, page: Int = 1, force: Bool = false) async throws -> [LobstersStory] {
        let data = try await get(feed.path(page: page), force: force)
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { LobstersStory(json: $0) }
    }

    // MARK: - Threads

    /// The story record plus its flattened discussion, in one request.
    func thread(_ shortID: String, force: Bool = false) async throws -> LobstersThread {
        let encoded = shortID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? shortID
        let data = try await get("/s/\(encoded).json", force: force)
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HNError.notFound
        }
        let comments = (json["comments"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
        return LobstersThread(story: LobstersStory(json: json), comments: LobstersHTML.nodes(from: comments))
    }

    // MARK: - Cache control

    func clearCache() {
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    // MARK: - Plumbing

    private func get(_ path: String, force: Bool) async throws -> Data {
        guard let url = URL(string: base + path) else { throw HNError.notFound }
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 { throw HNError.notFound }
                if !(200..<300).contains(http.statusCode) { throw HNError.badStatus(http.statusCode) }
            }
            return data
        } catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw HNError.offline
        }
    }
}
