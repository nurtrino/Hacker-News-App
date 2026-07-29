import Foundation

/// The six story lists the Firebase API exposes.
enum Feed: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case top, new, best, ask, show, job

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: return "Top"
        case .new: return "New"
        case .best: return "Best"
        case .ask: return "Ask HN"
        case .show: return "Show HN"
        case .job: return "Jobs"
        }
    }

    /// Shown as the navigation title, where there's room for a longer name.
    var longTitle: String {
        switch self {
        case .top: return "Top Stories"
        case .new: return "New Stories"
        case .best: return "Best Stories"
        case .ask: return "Ask HN"
        case .show: return "Show HN"
        case .job: return "Jobs"
        }
    }

    var systemImage: String {
        switch self {
        case .top: return "flame"
        case .new: return "clock"
        case .best: return "star"
        case .ask: return "questionmark.bubble"
        case .show: return "sparkles"
        case .job: return "briefcase"
        }
    }

    /// The endpoint path segment, e.g. `topstories`.
    var endpoint: String {
        switch self {
        case .top: return "topstories"
        case .new: return "newstories"
        case .best: return "beststories"
        case .ask: return "askstories"
        case .show: return "showstories"
        case .job: return "jobstories"
        }
    }

    /// Rank numbers only make sense for the ordered lists.
    var showsRank: Bool {
        switch self {
        case .top, .best: return true
        case .new, .ask, .show, .job: return false
        }
    }
}
