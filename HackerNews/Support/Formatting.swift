import Foundation

extension Date {
    /// Compact age string in HN's own idiom: `5m`, `3h`, `2d`, `4mo`, `2y`.
    var shortAge: String {
        let seconds = max(0, Date().timeIntervalSince(self))
        switch seconds {
        case ..<60: return "\(Int(seconds))s"
        case ..<3_600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3_600))h"
        case ..<2_592_000: return "\(Int(seconds / 86_400))d"
        case ..<31_536_000: return "\(Int(seconds / 2_592_000))mo"
        default: return "\(Int(seconds / 31_536_000))y"
        }
    }

    /// Spelled-out age for accessibility labels and detail headers.
    var longAge: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    var mediumDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }
}

extension Int {
    /// `1234` → `1.2k`, `1_200_000` → `1.2M`.
    var abbreviated: String {
        switch self {
        case ..<1_000:
            return String(self)
        case ..<1_000_000:
            let value = Double(self) / 1_000
            return value < 10
                ? String(format: "%.1fk", value)
                : String(format: "%.0fk", value)
        default:
            let value = Double(self) / 1_000_000
            return String(format: "%.1fM", value)
        }
    }

    func pluralized(_ singular: String, _ plural: String? = nil) -> String {
        self == 1 ? "\(self) \(singular)" : "\(self) \(plural ?? singular + "s")"
    }
}
