import SwiftUI

/// Owns the app-lifetime objects. They're separate `ObservableObject`s so a
/// change to one doesn't invalidate views observing another.
@MainActor
final class AppModel: ObservableObject {
    let settings: AppSettings
    let library: LibraryStore
    let feeds: FeedStores
    let lobsters: LobstersFeedStores
    let opener: LinkOpener

    init() {
        let settings = AppSettings()
        self.settings = settings
        library = LibraryStore()
        feeds = FeedStores()
        lobsters = LobstersFeedStores()
        opener = LinkOpener(settings: settings)
    }
}

@main
struct HackerNewsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model.settings)
                .environmentObject(model.library)
                .environmentObject(model.feeds)
                .environmentObject(model.lobsters)
                .environmentObject(model.opener)
        }
        .onChange(of: scenePhase) { phase in
            // Persist immediately rather than waiting out the debounce, since
            // the app may not get another chance.
            if phase != .active { model.library.flush() }
        }
    }
}
