import SwiftUI

/// The Stories tab: a feed switcher plus the currently selected story list.
struct FeedScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var feeds: FeedStores

    @State private var selected: Feed?
    @State private var path = NavigationPath()

    /// Until the user picks one, the feed follows the Settings default.
    private var feed: Feed { selected ?? settings.defaultFeed }

    var body: some View {
        NavigationStack(path: $path) {
            FeedList(store: feeds.store(for: feed), path: $path)
                .navigationTitle(feed.longTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        feedMenu(current: feed)
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .story(let item):
                        StoryScreen(story: item, path: $path)
                    case .user(let name):
                        UserScreen(username: name, path: $path)
                    }
                }
        }
    }

    private func feedMenu(current: Feed) -> some View {
        Menu {
            Picker("Feed", selection: feedBinding(current: current)) {
                ForEach(Feed.allCases) { feed in
                    Label(feed.title, systemImage: feed.systemImage).tag(feed)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: current.systemImage)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
            }
        }
        .accessibilityLabel("Choose feed, currently \(current.title)")
    }

    private func feedBinding(current: Feed) -> Binding<Feed> {
        Binding(
            get: { current },
            set: { newValue in
                guard newValue != current else { return }
                Haptics.select()
                selected = newValue
            }
        )
    }
}

/// The story list itself. Split out so the feed switcher can swap stores
/// without rebuilding the navigation stack.
struct FeedList: View {
    @ObservedObject var store: FeedStore
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
        .task { store.loadIfNeeded() }
        .refreshable { await store.refresh() }
    }

    private var list: some View {
        List {
            ForEach(Array(store.items.enumerated()), id: \.element.id) { index, item in
                Button {
                    open(item)
                } label: {
                    StoryRow(
                        item: item,
                        rank: store.feed.showsRank ? index + 1 : nil,
                        isRead: library.isRead(item.id)
                    )
                }
                .buttonStyle(.plain)
                .storyRowActions(for: item)
            }

            if store.canLoadMore {
                LoadMoreRow { store.loadMore() }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private func open(_ item: Item) {
        if settings.markStoriesRead { library.markRead(item.id) }
        switch settings.storyTap {
        case .comments:
            path.append(Route.story(item))
        case .link:
            opener.open(item.primaryURL)
        }
    }
}
