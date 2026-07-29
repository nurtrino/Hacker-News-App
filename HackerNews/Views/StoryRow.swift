import SwiftUI

/// Destinations pushed onto a `NavigationStack`.
enum Route: Hashable {
    case story(Item)
    case user(String)
}

/// One story in a list. Shared by the feeds, search results and saved items so
/// they all read the same way.
struct StoryRow: View {
    let item: Item
    var rank: Int?
    var isRead = false
    var showsSnippet = false

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            if let rank {
                Text("\(rank)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(minWidth: 20, alignment: .trailing)
                    .padding(.top, 3)
            } else if settings.showSourceBadges {
                SourceBadge(label: item.sourceLabel, seed: item.host ?? "ycombinator")
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text(item.displayTitle)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(titleColor)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let host = item.host {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text(host)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.hnOrange)
                }

                if showsSnippet, let text = item.text, !text.isEmpty {
                    Text(HNHTML.snippet(text, limit: 160))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                metadata
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var metadata: some View {
        HStack(spacing: 10) {
            if let score = item.score {
                MetaLabel(systemImage: "arrowtriangle.up.fill", text: score.abbreviated)
            }
            if item.kind != .job {
                MetaLabel(systemImage: "bubble.left", text: item.commentCount.abbreviated)
            }
            if let by = item.by {
                MetaLabel(systemImage: "person", text: by)
                    .lineLimit(1)
            }
            if let time = item.time {
                MetaLabel(systemImage: "clock", text: time.shortAge)
            }
            if library.isSaved(item.id) {
                Image(systemName: "bookmark.fill")
                    .font(.caption2)
                    .foregroundColor(.hnOrange)
            }
        }
        .lineLimit(1)
    }

    private var titleColor: Color {
        (isRead && settings.dimReadStories) ? .secondary : .primary
    }

    private var accessibilityLabel: String {
        var parts = [item.displayTitle]
        if let host = item.host { parts.append("from \(host)") }
        if let score = item.score { parts.append("\(score) points") }
        parts.append(item.commentCount.pluralized("comment"))
        if let by = item.by { parts.append("by \(by)") }
        if let time = item.time { parts.append(time.longAge) }
        return parts.joined(separator: ", ")
    }
}

/// Swipe actions and the long-press menu, factored out so every list that
/// shows a `StoryRow` behaves identically.
struct StoryRowActions: ViewModifier {
    let item: Item

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    if library.toggleSave(item) { Haptics.success() } else { Haptics.tap() }
                } label: {
                    Label(
                        library.isSaved(item.id) ? "Unsave" : "Save",
                        systemImage: library.isSaved(item.id) ? "bookmark.slash" : "bookmark"
                    )
                }
                .tint(.hnOrange)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                ShareLink(item: item.primaryURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)

                if item.link != nil {
                    Button {
                        opener.open(item.primaryURL)
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    .tint(.gray)
                }
            }
            .contextMenu {
                if let link = item.link {
                    Button {
                        opener.open(link)
                    } label: {
                        Label("Open Article", systemImage: "safari")
                    }
                    Button {
                        opener.openInApp(link, readerMode: true)
                    } label: {
                        Label("Open in Reader", systemImage: "doc.plaintext")
                    }
                }

                Button {
                    opener.open(item.hnURL)
                } label: {
                    Label("Open on Hacker News", systemImage: "safari")
                }

                Button {
                    if library.toggleSave(item) { Haptics.success() } else { Haptics.tap() }
                } label: {
                    Label(
                        library.isSaved(item.id) ? "Remove from Saved" : "Save Story",
                        systemImage: library.isSaved(item.id) ? "bookmark.slash" : "bookmark"
                    )
                }

                ShareLink(item: item.primaryURL) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: item.hnURL) {
                    Label("Share Discussion", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    UIPasteboard.general.string = item.primaryURL.absoluteString
                    Haptics.tap()
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            }
    }
}

extension View {
    func storyRowActions(for item: Item) -> some View {
        modifier(StoryRowActions(item: item))
    }
}
