import SwiftUI

struct SavedScreen: View {
    @State private var path = NavigationPath()
    @State private var filter = ""
    @State private var showingClearConfirmation = false

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    private var visible: [Item] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return library.saved }
        return library.saved.filter {
            $0.displayTitle.lowercased().contains(query)
                || ($0.host?.lowercased().contains(query) ?? false)
                || ($0.by?.lowercased().contains(query) ?? false)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if library.saved.isEmpty {
                    EmptyStateView(
                        systemImage: "bookmark",
                        title: "Nothing saved",
                        message: "Swipe right on any story, or use the Save action, to keep it here for later."
                    )
                } else if visible.isEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: "No matches",
                        message: "None of your saved stories match “\(filter)”."
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $filter, prompt: "Filter saved stories")
            .toolbar {
                if !library.saved.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(role: .destructive) {
                            showingClearConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                }
            }
            .confirmationDialog(
                "Remove all saved stories?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Remove All", role: .destructive) {
                    library.clearSaved()
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
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

    private var list: some View {
        List {
            ForEach(visible) { item in
                Button {
                    if settings.markStoriesRead { library.markRead(item.id) }
                    path.append(Route.story(item))
                } label: {
                    StoryRow(item: item, isRead: library.isRead(item.id))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        library.removeSaved(ids: [item.id])
                        Haptics.tap()
                    } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
                .contextMenu {
                    if let link = item.link {
                        Button {
                            opener.open(link)
                        } label: {
                            Label("Open Article", systemImage: "safari")
                        }
                    }
                    ShareLink(item: item.primaryURL) {
                        Label("Share Link", systemImage: "square.and.arrow.up")
                    }
                    Button(role: .destructive) {
                        library.removeSaved(ids: [item.id])
                    } label: {
                        Label("Remove", systemImage: "bookmark.slash")
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}
