import SwiftUI

extension Color {
    /// Y Combinator orange, #FF6600.
    static let hnOrange = Color(red: 1.0, green: 0.4, blue: 0.0)

    /// Palette used for thread depth bars and source monograms. Chosen to stay
    /// legible against both the light and dark system backgrounds.
    static let threadPalette: [Color] = [
        .hnOrange,
        Color(red: 0.30, green: 0.62, blue: 0.92),
        Color(red: 0.36, green: 0.74, blue: 0.48),
        Color(red: 0.85, green: 0.44, blue: 0.72),
        Color(red: 0.60, green: 0.52, blue: 0.92),
        Color(red: 0.94, green: 0.72, blue: 0.24),
        Color(red: 0.40, green: 0.78, blue: 0.78),
    ]

    static func threadColor(depth: Int) -> Color {
        threadPalette[abs(depth) % threadPalette.count]
    }

    /// Stable colour for a string, so a given domain always looks the same.
    static func stableColor(for string: String) -> Color {
        var hash: UInt64 = 5_381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        return threadPalette[Int(hash % UInt64(threadPalette.count))]
    }
}

enum Metrics {
    static let rowSpacing: CGFloat = 6
    static let threadBarWidth: CGFloat = 2
    static let threadIndent: CGFloat = 11
    /// Beyond this the indentation eats the screen, so depth stops widening.
    static let maxIndentDepth = 8
}
