import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var opener: LinkOpener

    @State private var cacheCleared = false
    @State private var showingClearReadConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Theme", selection: $settings.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Text Size", selection: $settings.textSize) {
                        ForEach(TextSize.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Source Badges", isOn: $settings.showSourceBadges)
                }

                Section {
                    Picker("Default Feed", selection: $settings.defaultFeed) {
                        ForEach(Feed.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                    Picker("Tapping a Story", selection: $settings.storyTap) {
                        ForEach(StoryTapAction.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Mark Stories as Read", isOn: $settings.markStoriesRead)
                    Toggle("Dim Read Stories", isOn: $settings.dimReadStories)
                        .disabled(!settings.markStoriesRead)
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Read stories are tracked on this device only.")
                }

                Section {
                    Picker("Open Links In", selection: $settings.linkTarget) {
                        ForEach(LinkTarget.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Use Reader When Available", isOn: $settings.useReaderMode)
                        .disabled(settings.linkTarget != .inApp)
                } header: {
                    Text("Links")
                } footer: {
                    Text("Reader mode strips page furniture when Safari can parse the article.")
                }

                Section {
                    Toggle("Auto-Collapse Deep Replies", isOn: $settings.autoCollapseDeepThreads)
                    Toggle("Haptic Feedback", isOn: $settings.hapticsEnabled)
                } header: {
                    Text("Discussions")
                } footer: {
                    Text("Auto-collapse folds replies below the second level when a thread opens.")
                }

                Section("Storage") {
                    LabeledContent("Saved Stories", value: "\(library.saved.count)")
                    LabeledContent("Stories Marked Read", value: "\(library.readIDs.count)")

                    Button {
                        showingClearReadConfirmation = true
                    } label: {
                        Text("Clear Read History")
                    }
                    .disabled(library.readIDs.isEmpty)

                    Button {
                        Task {
                            await HNAPI.shared.clearCache()
                            await LobstersAPI.shared.clearCache()
                            RichTextCache.shared.clear()
                            cacheCleared = true
                            Haptics.success()
                        }
                    } label: {
                        Text(cacheCleared ? "Cache Cleared" : "Clear Network Cache")
                    }
                    .disabled(cacheCleared)
                }

                Section {
                    Button {
                        opener.open(URL(string: "https://news.ycombinator.com")!)
                    } label: {
                        Label("Hacker News", systemImage: "network")
                    }
                    Button {
                        opener.open(URL(string: "https://news.ycombinator.com/newsguidelines.html")!)
                    } label: {
                        Label("Community Guidelines", systemImage: "text.book.closed")
                    }
                    Button {
                        opener.open(URL(string: "https://github.com/HackerNews/API")!)
                    } label: {
                        Label("Official HN API", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                } header: {
                    Text("About")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(appName) \(appVersion)")
                        Text("An unofficial reader built on the public Hacker News API and HN Search. Not affiliated with Y Combinator.")
                    }
                    .padding(.top, 4)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Clear read history?",
                isPresented: $showingClearReadConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    library.clearReadState()
                    Haptics.warning()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Hacker News"
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }
}
