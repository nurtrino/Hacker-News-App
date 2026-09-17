import SwiftUI

/// Destinations pushed inside the Lobsters tab. Kept separate from `Route`
/// so the Hacker News stacks don't have to know about a second site.
enum LobstersRoute: Hashable {
    case story(LobstersStory)
}

/// The Lobsters tab: a feed switcher plus the selected lobste.rs story list.
struct LobstersScreen: View {
    @EnvironmentObject private var feeds: LobstersFeedStores
    @EnvironmentObject private var opener: LinkOpener

    @State private var feed: LobstersFeed = .active
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            LobstersFeedList(store: feeds.store(for: feed), path: $path)
                .navigationTitle(feed.longTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        feedMenu
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            opener.open(feed.webURL)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel("Open on Lobsters")
                    }
                }
                .navigationDestination(for: LobstersRoute.self) { route in
                    switch route {
                    case .story(let story):
                        LobstersStoryScreen(story: story, path: $path)
                    }
                }
        }
    }

    private var feedMenu: some View {
        Menu {
            Picker("Feed", selection: feedBinding) {
                ForEach(LobstersFeed.allCases) { candidate in
                    Label(candidate.title, systemImage: candidate.systemImage).tag(candidate)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: feed.systemImage)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel("Choose feed, currently \(feed.title)")
    }

    private var feedBinding: Binding<LobstersFeed> {
        Binding(
            get: { feed },
            set: { newValue in
                guard newValue != feed else { return }
                Haptics.select()
                feed = newValue
            }
        )
    }
}

/// The story list itself, split out so the switcher can swap stores without
/// rebuilding the navigation stack.
struct LobstersFeedList: View {
    @ObservedObject var store: LobstersFeedStore
    @Binding var path: NavigationPath

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    var body: some View {
        Group {
            if store.isEmpty, store.phase.isLoading {
                LoadingStateView(label: "Loading \(store.feed.title.lowercased()) stories…")
            } else if store.isEmpty, let message = store.phase.errorMessage {
                ErrorStateView(message: message) { store.retry() }
            } else if store.isEmpty, store.phase == .loaded {
                EmptyStateView(
                    systemImage: "tray",
                    title: "Nothing here yet",
                    message: "This feed came back empty. Pull to refresh."
                )
            } else {
                list
            }
        }
        // Keyed on the feed: switching swaps in a different store but leaves
        // this view's identity alone, so an unkeyed .task would never re-run.
        .task(id: store.feed) { store.loadIfNeeded() }
        .refreshable { await store.refresh() }
    }

    private var list: some View {
        List {
            ForEach(store.items) { story in
                Button {
                    open(story)
                } label: {
                    LobstersStoryRow(story: story, isRead: library.isRead(story.numericID))
                }
                .buttonStyle(.plain)
                .lobstersStoryActions(for: story)
            }

            if store.canLoadMore {
                LoadMoreRow { store.loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func open(_ story: LobstersStory) {
        if settings.markStoriesRead { library.markRead(story.numericID) }
        switch settings.storyTap {
        case .comments:
            path.append(LobstersRoute.story(story))
        case .link:
            opener.open(story.primaryURL)
        }
    }
}

/// One lobste.rs story in a list.
struct LobstersStoryRow: View {
    let story: LobstersStory
    var isRead = false

    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            if settings.showSourceBadges {
                SourceBadge(label: story.sourceLabel, seed: story.host ?? "lobsters")
                    .padding(.top, 1)
            }

            VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                Text(story.title)
                    .font(.callout.weight(.semibold))
                    .foregroundColor(titleColor)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let host = story.host {
                    HStack(spacing: 3) {
                        Image(systemName: "link")
                            .font(.system(size: 9))
                        Text(host)
                            .font(.caption)
                            .lineLimit(1)
                    }
                    .foregroundColor(.hnOrange)
                }

                if !story.tags.isEmpty {
                    LobstersTagRow(tags: story.tags)
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
            MetaLabel(systemImage: "arrowtriangle.up.fill", text: story.score.abbreviated)
            MetaLabel(systemImage: "bubble.left", text: story.commentCount.abbreviated)
            if let submitter = story.submitter {
                MetaLabel(systemImage: "person", text: submitter)
                    .lineLimit(1)
            }
            if let time = story.createdAt {
                MetaLabel(systemImage: "clock", text: time.shortAge)
            }
        }
        .lineLimit(1)
    }

    private var titleColor: Color {
        (isRead && settings.dimReadStories) ? .secondary : .primary
    }

    private var accessibilityLabel: String {
        var parts = [story.title]
        if let host = story.host { parts.append("from \(host)") }
        parts.append("\(story.score) points")
        parts.append(story.commentCount.pluralized("comment"))
        if let submitter = story.submitter { parts.append("by \(submitter)") }
        if let time = story.createdAt { parts.append(time.longAge) }
        if !story.tags.isEmpty { parts.append("tagged " + story.tags.joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

/// Lobsters' tags, as small capsules. Long tag lists wrap onto a second line
/// rather than getting truncated.
struct LobstersTagRow: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(tags.prefix(5), id: \.self) { tag in
                Text(tag)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.stableColor(for: tag).opacity(0.14)))
                    .foregroundColor(Color.stableColor(for: tag))
            }
            if tags.count > 5 {
                Text("+\(tags.count - 5)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityHidden(true)
    }
}

/// Swipe actions and the long-press menu for a Lobsters story. There's no
/// save here — the saved list is keyed on Hacker News items.
struct LobstersStoryActions: ViewModifier {
    let story: LobstersStory

    @EnvironmentObject private var opener: LinkOpener

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                ShareLink(item: story.primaryURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .tint(.blue)

                if story.link != nil {
                    Button {
                        opener.open(story.primaryURL)
                    } label: {
                        Label("Open", systemImage: "safari")
                    }
                    .tint(.gray)
                }
            }
            .contextMenu {
                if let link = story.link {
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
                    opener.open(story.lobstersURL)
                } label: {
                    Label("Open on Lobsters", systemImage: "safari")
                }

                ShareLink(item: story.primaryURL) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: story.lobstersURL) {
                    Label("Share Discussion", systemImage: "square.and.arrow.up.on.square")
                }

                Divider()

                Button {
                    UIPasteboard.general.string = story.primaryURL.absoluteString
                    Haptics.tap()
                } label: {
                    Label("Copy Link", systemImage: "doc.on.doc")
                }
            }
    }
}

extension View {
    func lobstersStoryActions(for story: LobstersStory) -> some View {
        modifier(LobstersStoryActions(story: story))
    }
}
