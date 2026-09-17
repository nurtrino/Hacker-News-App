import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var opener: LinkOpener

    @State private var tab: Tab = .stories

    enum Tab: Hashable {
        case stories, lobsters, search, saved, settings
    }

    var body: some View {
        TabView(selection: tabBinding) {
            FeedScreen()
                .tabItem { Label("Stories", systemImage: "newspaper") }
                .tag(Tab.stories)

            LobstersScreen()
                .tabItem { Label("Lobsters", systemImage: "fish") }
                .tag(Tab.lobsters)

            SearchScreen()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
                .tag(Tab.search)

            SavedScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }
                .tag(Tab.saved)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .tint(.hnOrange)
        .inAppBrowser($opener.presented)
        .preferredColorScheme(settings.appearance.colorScheme)
        .modifier(TextSizeOverride(size: settings.textSize))
    }

    private var tabBinding: Binding<Tab> {
        Binding(
            get: { tab },
            set: { newValue in
                if newValue != tab { Haptics.select() }
                tab = newValue
            }
        )
    }
}

/// Applies the Settings text-size override, or gets out of the way entirely
/// when it's set to "System".
private struct TextSizeOverride: ViewModifier {
    let size: TextSize

    @ViewBuilder
    func body(content: Content) -> some View {
        if let override = size.dynamicTypeSize {
            content.dynamicTypeSize(override)
        } else {
            content
        }
    }
}
