import SwiftUI

/// A story and its discussion.
struct StoryScreen: View {
    @StateObject private var store: ThreadStore
    @Binding var path: NavigationPath

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    init(story: Item, path: Binding<NavigationPath>) {
        _store = StateObject(wrappedValue: ThreadStore(story: story))
        _path = path
    }

    var body: some View {
        List {
            Section {
                StoryHeader(story: store.story, path: $path)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowSeparator(.hidden)
            }

            Section {
                switch store.phase {
                case .loading where store.nodes.isEmpty:
                    LoadingStateView(label: "Loading discussion…")
                        .frame(height: 160)
                        .listRowSeparator(.hidden)
                case .failed(let message):
                    ErrorStateView(message: message) {
                        store.retry(autoCollapseDeep: settings.autoCollapseDeepThreads)
                    }
                    .frame(height: 220)
                    .listRowSeparator(.hidden)
                default:
                    if store.nodes.isEmpty {
                        EmptyStateView(
                            systemImage: "bubble.left",
                            title: "No comments yet",
                            message: "Be the first — open this story on Hacker News to reply."
                        )
                        .frame(height: 200)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(store.visibleNodes) { node in
                            CommentRow(
                                node: node,
                                isCollapsed: store.isCollapsed(node.id),
                                isOriginalPoster: node.author != nil && node.author == store.story.by,
                                path: $path
                            ) {
                                withAnimation(.easeOut(duration: 0.18)) {
                                    store.toggleCollapse(node)
                                }
                                Haptics.tap()
                            }
                            .listRowInsets(
                                EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14)
                            )
                        }
                    }
                }
            } header: {
                if !store.nodes.isEmpty {
                    commentsHeader
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(store.nodes.isEmpty ? "Discussion" : store.totalComments.pluralized("comment"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task { store.loadIfNeeded(autoCollapseDeep: settings.autoCollapseDeepThreads) }
        .refreshable { await store.refresh(autoCollapseDeep: settings.autoCollapseDeepThreads) }
        .onChange(of: store.story) { updated in
            library.refreshSaved(with: updated)
        }
    }

    private var commentsHeader: some View {
        HStack {
            Text(store.totalComments.pluralized("comment").uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Spacer()
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    if store.isFullyCollapsed { store.expandAll() } else { store.collapseAll() }
                }
                Haptics.tap()
            } label: {
                Label(
                    store.isFullyCollapsed ? "Expand All" : "Collapse All",
                    systemImage: store.isFullyCollapsed
                        ? "arrow.down.left.and.arrow.up.right"
                        : "arrow.up.right.and.arrow.down.left"
                )
                .font(.caption2)
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.plain)
            .foregroundColor(.hnOrange)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                if let link = store.story.link {
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
                    opener.open(store.story.hnURL)
                } label: {
                    Label("Open on Hacker News", systemImage: "network")
                }

                Button {
                    if library.toggleSave(store.story) { Haptics.success() } else { Haptics.tap() }
                } label: {
                    Label(
                        library.isSaved(store.story.id) ? "Remove from Saved" : "Save Story",
                        systemImage: library.isSaved(store.story.id) ? "bookmark.slash" : "bookmark"
                    )
                }

                Divider()

                ShareLink(item: store.story.primaryURL) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: store.story.hnURL) {
                    Label("Share Discussion", systemImage: "square.and.arrow.up.on.square")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

/// The story card that sits above the comments.
private struct StoryHeader: View {
    let story: Item
    @Binding var path: NavigationPath

    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                opener.open(story.primaryURL)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(story.displayTitle)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if let host = story.host {
                        HStack(spacing: 4) {
                            Image(systemName: "safari")
                                .font(.caption2)
                            Text(host)
                                .font(.footnote)
                            Image(systemName: "arrow.up.forward")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundColor(.hnOrange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            byline

            if let text = story.text, !text.isEmpty {
                RichText(html: text, font: .callout)
                    .padding(.top, 2)
            }

            actionBar
        }
    }

    private var byline: some View {
        HStack(spacing: 12) {
            if let score = story.score {
                MetaLabel(
                    systemImage: "arrowtriangle.up.fill",
                    text: score.pluralized("point"),
                    tint: .hnOrange
                )
            }
            Button {
                path.append(Route.user(story.author))
            } label: {
                MetaLabel(systemImage: "person", text: story.author)
            }
            .buttonStyle(.plain)

            if let time = story.time {
                MetaLabel(systemImage: "clock", text: time.shortAge)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if story.link != nil {
                ActionButton(title: "Read", systemImage: "doc.plaintext") {
                    opener.openInApp(story.primaryURL, readerMode: true)
                }
            }
            ActionButton(
                title: library.isSaved(story.id) ? "Saved" : "Save",
                systemImage: library.isSaved(story.id) ? "bookmark.fill" : "bookmark",
                isActive: library.isSaved(story.id)
            ) {
                if library.toggleSave(story) { Haptics.success() } else { Haptics.tap() }
            }
            ShareLink(item: story.primaryURL) {
                ActionButtonLabel(title: "Share", systemImage: "square.and.arrow.up", isActive: false)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let systemImage: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionButtonLabel(title: title, systemImage: systemImage, isActive: isActive)
        }
        .buttonStyle(.plain)
    }
}

private struct ActionButtonLabel: View {
    let title: String
    let systemImage: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(
            Capsule().fill(
                isActive
                    ? Color.hnOrange.opacity(0.16)
                    : Color(uiColor: .secondarySystemBackground)
            )
        )
        .foregroundColor(isActive ? .hnOrange : .primary)
    }
}
