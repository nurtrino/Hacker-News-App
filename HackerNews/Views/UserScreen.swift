import SwiftUI

/// A user profile plus their recent submissions.
struct UserScreen: View {
    let username: String
    @Binding var path: NavigationPath

    @StateObject private var model = UserModel()

    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    var body: some View {
        List {
            Section {
                switch model.phase {
                case .loading where model.user == nil:
                    LoadingStateView()
                        .frame(height: 120)
                        .listRowSeparator(.hidden)
                case .failed(let message):
                    ErrorStateView(message: message) { model.load(username: username) }
                        .frame(height: 200)
                        .listRowSeparator(.hidden)
                default:
                    if let user = model.user {
                        profile(user)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if model.user != nil {
                Section {
                    if model.submissions.isEmpty {
                        Text(model.scope == .comments ? "No comments found." : "No stories found.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(model.submissions) { item in
                        Button {
                            if settings.markStoriesRead { library.markRead(item.id) }
                            path.append(Route.story(item))
                        } label: {
                            StoryRow(
                                item: item,
                                isRead: library.isRead(item.id),
                                showsSnippet: model.scope == .comments
                            )
                        }
                        .buttonStyle(.plain)
                        .storyRowActions(for: item)
                    }
                } header: {
                    Picker("Kind", selection: $model.scope) {
                        Text("Stories").tag(SearchScope.stories)
                        Text("Comments").tag(SearchScope.comments)
                    }
                    .pickerStyle(.segmented)
                    .textCase(nil)
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        opener.open(profileURL)
                    } label: {
                        Label("Open on Hacker News", systemImage: "network")
                    }
                    ShareLink(item: profileURL) {
                        Label("Share Profile", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task(id: username) { await model.load(username: username) }
        .onChange(of: model.scope) { _ in model.loadSubmissions(username: username) }
    }

    private var profileURL: URL {
        URL(string: "https://news.ycombinator.com/user?id=\(username)")!
    }

    @ViewBuilder
    private func profile(_ user: HNUser) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                SourceBadge(label: String(user.id.prefix(1)).uppercased(), seed: user.id, size: 52)

                VStack(alignment: .leading, spacing: 4) {
                    Text(user.id)
                        .font(.title3.weight(.bold))
                    if let created = user.created {
                        Text("Joined \(created.mediumDate)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                StatTile(value: user.karma.abbreviated, label: "karma")
                if let created = user.created {
                    StatTile(value: yearsOn(created), label: "on HN")
                }
            }

            if let about = user.about, !about.isEmpty {
                RichText(html: about, font: .callout)
            }
        }
        .padding(.vertical, 6)
    }

    private func yearsOn(_ created: Date) -> String {
        let years = Date().timeIntervalSince(created) / 31_536_000
        return years < 1 ? "<1y" : String(format: "%.0fy", years)
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundColor(.hnOrange)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 68)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

@MainActor
private final class UserModel: ObservableObject {
    @Published private(set) var user: HNUser?
    @Published private(set) var submissions: [Item] = []
    @Published private(set) var phase: LoadPhase = .idle
    @Published var scope: SearchScope = .stories

    private var loadedFor: String?
    private var task: Task<Void, Never>?

    func load(username: String) {
        guard loadedFor != username || phase.errorMessage != nil else { return }
        loadedFor = username
        phase = .loading
        task?.cancel()

        task = Task {
            do {
                user = try await HNAPI.shared.user(username)
                guard !Task.isCancelled else { return }
                phase = .loaded
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed((error as? HNError)?.errorDescription ?? error.localizedDescription)
                return
            }
            await fetchSubmissions(username: username)
        }
    }

    func loadSubmissions(username: String) {
        Task { await fetchSubmissions(username: username) }
    }

    private func fetchSubmissions(username: String) async {
        submissions = []
        guard let results = try? await AlgoliaAPI.shared.submissions(by: username, scope: scope) else {
            return
        }
        guard !Task.isCancelled else { return }
        submissions = results.items
    }
}
