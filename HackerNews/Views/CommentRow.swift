import SwiftUI

/// One comment in a thread, indented by depth with a coloured rail per level.
struct CommentRow: View {
    let node: CommentNode
    let isCollapsed: Bool
    let isOriginalPoster: Bool
    @Binding var path: NavigationPath
    let onToggle: () -> Void

    @EnvironmentObject private var opener: LinkOpener

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            rails

            VStack(alignment: .leading, spacing: 6) {
                header

                if !isCollapsed {
                    if node.isDeleted {
                        Text("[deleted]")
                            .font(.callout.italic())
                            .foregroundColor(.secondary)
                    } else {
                        RichText(html: node.html, font: .callout)
                    }
                }
            }
            .padding(.leading, node.depth > 0 ? 8 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .contextMenu { menu }
        .environment(\.openURL, OpenURLAction { url in
            opener.open(url)
            return .handled
        })
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isCollapsed ? "Expand thread" : "Collapse thread", onToggle)
    }

    /// One rail per ancestor level, so it's obvious how deep a reply sits.
    private var rails: some View {
        HStack(spacing: 0) {
            ForEach(0..<min(node.depth, Metrics.maxIndentDepth), id: \.self) { level in
                Rectangle()
                    .fill(Color.threadColor(depth: level).opacity(0.55))
                    .frame(width: Metrics.threadBarWidth)
                    .frame(maxHeight: .infinity)
                    .padding(.trailing, Metrics.threadIndent - Metrics.threadBarWidth)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                openAuthor()
            } label: {
                Text(node.author ?? "unknown")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isOriginalPoster ? .hnOrange : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(node.author == nil)

            if isOriginalPoster {
                Text("OP")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.hnOrange.opacity(0.18)))
                    .foregroundColor(.hnOrange)
            }

            if let time = node.time {
                Text(time.shortAge)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            if isCollapsed, node.descendantCount > 0 {
                Text("+\(node.descendantCount)")
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundColor(.secondary)
            }

            Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary.opacity(0.6))
        }
        // Only the header toggles the thread — the body has to stay tappable
        // for the links inside it.
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    @ViewBuilder
    private var menu: some View {
        Button {
            onToggle()
        } label: {
            Label(
                isCollapsed ? "Expand Thread" : "Collapse Thread",
                systemImage: isCollapsed ? "chevron.down" : "chevron.right"
            )
        }

        if let author = node.author {
            Button {
                openAuthor()
            } label: {
                Label("View \(author)", systemImage: "person")
            }
        }

        Button {
            UIPasteboard.general.string = HNHTML.plainText(node.html)
            Haptics.tap()
        } label: {
            Label("Copy Text", systemImage: "doc.on.doc")
        }

        ShareLink(item: commentURL) {
            Label("Share Comment", systemImage: "square.and.arrow.up")
        }

        Button {
            opener.open(commentURL)
        } label: {
            Label("Open on \(node.forum.name)", systemImage: "network")
        }
    }

    private var commentURL: URL { node.webURL }

    /// HN authors get the in-app profile; other sites open the profile page
    /// in the browser, since there's no matching screen for them.
    private func openAuthor() {
        guard let author = node.author else { return }
        switch node.forum {
        case .hackerNews:
            path.append(Route.user(author))
        case .lobsters:
            if let url = node.authorURL { opener.open(url) }
        }
    }
}
