import Foundation

enum HNError: LocalizedError {
    case badStatus(Int)
    case notFound
    case offline

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): return "The server returned status \(code)."
        case .notFound: return "That item no longer exists."
        case .offline: return "You appear to be offline."
        }
    }
}

/// Client for the official Firebase Hacker News API.
///
/// Individual items are memoised in-process and de-duplicated while in flight,
/// which matters a lot: a 500-comment thread would otherwise re-request the
/// same parents on every collapse/expand round trip.
actor HNAPI {
    static let shared = HNAPI()

    private let base = URL(string: "https://hacker-news.firebaseio.com/v0")!
    private let session: URLSession
    private var cache: [Int: Item] = [:]
    private var inFlight: [Int: Task<Item?, Never>] = [:]

    /// How many item requests to keep in the air at once. HN's CDN is happy
    /// with far more, but this keeps the device's socket pool sane.
    private let maxConcurrency = 12

    init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .useProtocolCachePolicy
        config.timeoutIntervalForRequest = 20
        // Ride out brief drop-outs, but don't hang forever in airplane mode.
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 45
        config.urlCache = URLCache(
            memoryCapacity: 16 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "hn-api"
        )
        session = URLSession(configuration: config)
    }

    // MARK: - Story lists

    func ids(for feed: Feed, force: Bool = false) async throws -> [Int] {
        let url = base.appendingPathComponent("\(feed.endpoint).json")
        let data = try await get(url, force: force)
        return (try? JSONDecoder().decode([Int].self, from: data)) ?? []
    }

    // MARK: - Items

    func item(_ id: Int, force: Bool = false) async -> Item? {
        if !force, let cached = cache[id] { return cached }
        if let running = inFlight[id] { return await running.value }

        let task = Task<Item?, Never> { [base] in
            let url = base.appendingPathComponent("item/\(id).json")
            guard let data = try? await self.get(url, force: force) else { return nil }
            return Self.decodeItem(data)
        }
        inFlight[id] = task
        let result = await task.value
        inFlight[id] = nil
        if let result { cache[id] = result }
        return result
    }

    /// Fetches many items concurrently and returns them in the requested
    /// order, dropping any that failed or were deleted upstream.
    func items(_ ids: [Int], force: Bool = false) async -> [Item] {
        guard !ids.isEmpty else { return [] }
        var results = [Int: Item](minimumCapacity: ids.count)

        await withTaskGroup(of: (Int, Item?).self) { group in
            var next = 0
            let inFlightLimit = Swift.min(maxConcurrency, ids.count)

            for _ in 0..<inFlightLimit {
                let index = next
                next += 1
                group.addTask { (index, await self.item(ids[index], force: force)) }
            }

            while let (index, item) = await group.next() {
                if let item { results[index] = item }
                if next < ids.count {
                    let index = next
                    next += 1
                    group.addTask { (index, await self.item(ids[index], force: force)) }
                }
            }
        }

        return ids.indices.compactMap { results[$0] }
    }

    // MARK: - Users

    func user(_ name: String) async throws -> HNUser? {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        let url = base.appendingPathComponent("user/\(encoded).json")
        let data = try await get(url, force: false)
        guard !Self.isNull(data) else { throw HNError.notFound }
        return try? JSONDecoder().decode(HNUser.self, from: data)
    }

    // MARK: - Cache control

    func clearCache() {
        cache.removeAll()
        session.configuration.urlCache?.removeAllCachedResponses()
    }

    // MARK: - Plumbing

    private func get(_ url: URL, force: Bool) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw HNError.badStatus(http.statusCode)
            }
            return data
        } catch let error as URLError
            where error.code == .notConnectedToInternet || error.code == .networkConnectionLost {
            throw HNError.offline
        }
    }

    private static func isNull(_ data: Data) -> Bool {
        let trimmed = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed == "null"
    }

    private static func decodeItem(_ data: Data) -> Item? {
        guard !isNull(data) else { return nil }
        return try? JSONDecoder().decode(Item.self, from: data)
    }
}
