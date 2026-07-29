import SwiftUI

struct SearchScreen: View {
    @StateObject private var store = SearchStore()
    @State private var path = NavigationPath()

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationTitle("Search")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $store.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search Hacker News"
                )
                .onChange(of: store.query) { _ in store.queryChanged() }
                .onSubmit(of: .search) { store.submit() }
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

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            filters

            switch store.phase {
            case .idle:
                recents
            case .loading where store.results.isEmpty:
                LoadingStateView()
            case .failed(let message):
                ErrorStateView(message: message) { store.submit() }
            default:
                if store.results.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No results",
                        message: "Nothing matched “\(store.trimmedQuery)”. Try a different term or widen the time range."
                    )
                } else {
                    results
                }
            }
        }
    }

    private var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SearchScope.allCases) { scope in
                        FilterChip(title: scope.title, isSelected: store.scope == scope) {
                            Haptics.select()
                            store.scope = scope
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                Menu {
                    Picker("Sort", selection: $store.sort) {
                        ForEach(SearchSort.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    filterLabel("arrow.up.arrow.down", store.sort.title)
                }

                Menu {
                    Picker("Period", selection: $store.period) {
                        ForEach(SearchPeriod.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    filterLabel("calendar", store.period.title)
                }

                Spacer()

                if store.phase == .loaded, store.totalHits > 0 {
                    Text("\(store.totalHits.abbreviated) hits")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
        .background(Color(uiColor: .systemBackground))
    }

    private func filterLabel(_ systemImage: String, _ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
            Text(title)
                .font(.caption)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
        }
        .foregroundColor(.hnOrange)
    }

    private var results: some View {
        List {
            ForEach(store.results) { item in
                Button {
                    open(item)
                } label: {
                    StoryRow(
                        item: item,
                        isRead: library.isRead(item.id),
                        showsSnippet: store.scope == .comments
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

    @ViewBuilder
    private var recents: some View {
        if store.recentSearches.isEmpty {
            EmptyStateView(
                systemImage: "magnifyingglass",
                title: "Search Hacker News",
                message: "Stories and comments, all the way back to 2006."
            )
        } else {
            List {
                Section {
                    ForEach(store.recentSearches, id: \.self) { text in
                        Button {
                            store.query = text
                            store.submit()
                        } label: {
                            HStack {
                                Image(systemName: "clock.arrow.circlepath")
                                    .foregroundColor(.secondary)
                                Text(text)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                store.removeRecent(text)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("RECENT")
                        Spacer()
                        Button("Clear") { store.clearRecents() }
                            .font(.caption)
                            .foregroundColor(.hnOrange)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func open(_ item: Item) {
        if settings.markStoriesRead { library.markRead(item.id) }
        // A comment hit navigates to the story it belongs to.
        if item.kind == .comment, let storyID = item.storyID {
            path.append(Route.story(Item(id: storyID, title: item.storyTitle)))
        } else {
            path.append(Route.story(item))
        }
    }
}
