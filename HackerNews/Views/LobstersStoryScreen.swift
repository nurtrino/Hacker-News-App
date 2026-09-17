import SwiftUI

/// A lobste.rs story and its discussion.
struct LobstersStoryScreen: View {
    @StateObject private var store: LobstersThreadStore
    @Binding var path: NavigationPath

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var opener: LinkOpener

    init(story: LobstersStory, path: Binding<NavigationPath>) {
        _store = StateObject(wrappedValue: LobstersThreadStore(story: story))
        _path = path
    }

    var body: some View {
        List {
            Section {
                LobstersStoryHeader(story: store.story)
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
                            message: "Be the first — open this story on Lobsters to reply."
                        )
                        .frame(height: 200)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(store.visibleNodes) { node in
                            CommentRow(
                                node: node,
                                isCollapsed: store.isCollapsed(node.id),
                                isOriginalPoster: node.author != nil && node.author == store.story.submitter,
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
                    opener.open(store.story.lobstersURL)
                } label: {
                    Label("Open on Lobsters", systemImage: "network")
                }

                Divider()

                ShareLink(item: store.story.primaryURL) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                ShareLink(item: store.story.lobstersURL) {
                    Label("Share Discussion", systemImage: "square.and.arrow.up.on.square")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

/// The story card that sits above the comments.
private struct LobstersStoryHeader: View {
    let story: LobstersStory

    @EnvironmentObject private var opener: LinkOpener

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                opener.open(story.primaryURL)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(story.title)
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

            if !story.tags.isEmpty {
                LobstersTagRow(tags: story.tags)
            }

            byline

            if let html = story.descriptionHTML {
                RichText(html: LobstersHTML.normalize(html), font: .callout)
                    .padding(.top, 2)
            }

            actionBar
        }
    }

    private var byline: some View {
        HStack(spacing: 12) {
            MetaLabel(
                systemImage: "arrowtriangle.up.fill",
                text: story.score.pluralized("point"),
                tint: .hnOrange
            )
            Button {
                if let url = Forum.lobsters.profileURL(for: story.author) { opener.open(url) }
            } label: {
                MetaLabel(systemImage: "person", text: story.author)
            }
            .buttonStyle(.plain)

            if let time = story.createdAt {
                MetaLabel(systemImage: "clock", text: time.shortAge)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            if story.link != nil {
                LobstersActionButton(title: "Read", systemImage: "doc.plaintext") {
                    opener.openInApp(story.primaryURL, readerMode: true)
                }
            }
            LobstersActionButton(title: "Lobsters", systemImage: "safari") {
                opener.open(story.lobstersURL)
            }
            ShareLink(item: story.primaryURL) {
                LobstersActionButtonLabel(title: "Share", systemImage: "square.and.arrow.up")
            }
            Spacer(minLength: 0)
        }
    }
}

private struct LobstersActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LobstersActionButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }
}

private struct LobstersActionButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(title)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
        .foregroundColor(.primary)
    }
}
