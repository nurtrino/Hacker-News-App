import Foundation

/// One comment, already flattened out of the reply tree.
///
/// Threads are stored as a flat, depth-tagged array in reading order. That
/// keeps the list diffable and makes collapsing a subtree a matter of skipping
/// the run of following nodes whose depth is greater than the collapsed one's.
struct CommentNode: Identifiable, Hashable, Sendable {
    let id: Int
    let parent: Int?
    let author: String?
    /// Raw comment HTML — rendered lazily by `RichText`.
    let html: String
    let time: Date?
    let depth: Int
    let isDeleted: Bool
    /// Number of descendants below this node (filled in after flattening).
    var descendantCount: Int = 0
    /// Which site the comment came from; decides where "open on…" links go.
    var forum: Forum = .hackerNews
    /// The comment's own page, for sites whose URLs aren't derivable from `id`.
    var permalink: URL?

    var isTopLevel: Bool { depth == 0 }

    /// The comment's web page.
    var webURL: URL {
        permalink ?? URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }

    /// The author's profile page on the comment's site.
    var authorURL: URL? {
        guard let author else { return nil }
        return forum.profileURL(for: author)
    }
}

/// The sites the app reads from.
enum Forum: Hashable, Sendable {
    case hackerNews
    case lobsters

    var name: String {
        switch self {
        case .hackerNews: return "Hacker News"
        case .lobsters: return "Lobsters"
        }
    }

    func profileURL(for username: String) -> URL? {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        switch self {
        case .hackerNews: return URL(string: "https://news.ycombinator.com/user?id=\(encoded)")
        case .lobsters: return URL(string: "https://lobste.rs/~\(encoded)")
        }
    }
}

extension Array where Element == CommentNode {
    /// Fills in `descendantCount` for every node in one pass, using a stack of
    /// the currently-open ancestors.
    func withDescendantCounts() -> [CommentNode] {
        var result = self
        var ancestors: [Int] = []
        for i in result.indices {
            while let top = ancestors.last, result[top].depth >= result[i].depth {
                ancestors.removeLast()
            }
            for idx in ancestors { result[idx].descendantCount += 1 }
            ancestors.append(i)
        }
        return result
    }
}
