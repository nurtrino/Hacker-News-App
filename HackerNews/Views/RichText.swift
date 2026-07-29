import SwiftUI

/// Memoises parsed comment bodies. Threads re-render constantly while
/// scrolling and collapsing, and re-parsing a long comment every pass is the
/// difference between a smooth list and a stuttery one.
@MainActor
final class RichTextCache {
    static let shared = RichTextCache()

    private final class Entry {
        let html: String
        let blocks: [RichBlock]
        init(html: String, blocks: [RichBlock]) {
            self.html = html
            self.blocks = blocks
        }
    }

    private let storage = NSCache<NSNumber, Entry>()

    private init() {
        storage.countLimit = 800
    }

    func blocks(for html: String) -> [RichBlock] {
        let key = NSNumber(value: html.hashValue)
        if let entry = storage.object(forKey: key), entry.html == html {
            return entry.blocks
        }
        let blocks = HNHTML.parse(html)
        storage.setObject(Entry(html: html, blocks: blocks), forKey: key)
        return blocks
    }

    func clear() {
        storage.removeAllObjects()
    }
}

/// Renders a Hacker News HTML body: paragraphs with inline links and emphasis,
/// plus horizontally scrollable code blocks.
struct RichText: View {
    let html: String
    var font: Font = .body
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(RichTextCache.shared.blocks(for: html).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    Text(text)
                        .font(font)
                        .foregroundColor(color)
                        .tint(.hnOrange)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .code(let code):
                    CodeBlock(code: code)
                }
            }
        }
        .textSelection(.enabled)
    }
}

private struct CodeBlock: View {
    let code: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(code)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.primary)
                .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
