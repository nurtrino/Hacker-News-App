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
    /// Raw HN comment HTML — rendered lazily by `RichText`.
    let html: String
    let time: Date?
    let depth: Int
    let isDeleted: Bool
    /// Number of descendants below this node (filled in after flattening).
    var descendantCount: Int = 0

    var isTopLevel: Bool { depth == 0 }
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
