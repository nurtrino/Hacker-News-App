import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Codable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum TextSize: String, CaseIterable, Identifiable, Codable {
    case system, small, medium, large, extraLarge

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    /// nil means "respect whatever the user set system-wide".
    var dynamicTypeSize: DynamicTypeSize? {
        switch self {
        case .system: return nil
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .extraLarge: return .xxLarge
        }
    }
}

enum LinkTarget: String, CaseIterable, Identifiable, Codable {
    case inApp, safari

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inApp: return "In-App Browser"
        case .safari: return "Safari"
        }
    }
}

enum StoryTapAction: String, CaseIterable, Identifiable, Codable {
    case comments, link

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comments: return "Open Comments"
        case .link: return "Open Article"
        }
    }
}

/// User preferences, persisted to `UserDefaults`.
///
/// Deliberately not `@AppStorage`: those property wrappers don't publish
/// changes when they live inside an `ObservableObject`, which is exactly where
/// these need to be.
@MainActor
final class AppSettings: ObservableObject {
    @Published var appearance: AppearanceMode { didSet { store(appearance.rawValue, "appearance") } }
    @Published var textSize: TextSize { didSet { store(textSize.rawValue, "textSize") } }
    @Published var linkTarget: LinkTarget { didSet { store(linkTarget.rawValue, "linkTarget") } }
    @Published var storyTap: StoryTapAction { didSet { store(storyTap.rawValue, "storyTap") } }
    @Published var defaultFeed: Feed { didSet { store(defaultFeed.rawValue, "defaultFeed") } }
    @Published var useReaderMode: Bool { didSet { store(useReaderMode, "useReaderMode") } }
    @Published var markStoriesRead: Bool { didSet { store(markStoriesRead, "markStoriesRead") } }
    @Published var dimReadStories: Bool { didSet { store(dimReadStories, "dimReadStories") } }
    @Published var showSourceBadges: Bool { didSet { store(showSourceBadges, "showSourceBadges") } }
    @Published var autoCollapseDeepThreads: Bool { didSet { store(autoCollapseDeepThreads, "autoCollapse") } }
    @Published var hapticsEnabled: Bool {
        didSet {
            store(hapticsEnabled, "hapticsEnabled")
            Haptics.isEnabled = hapticsEnabled
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        textSize = TextSize(rawValue: defaults.string(forKey: "textSize") ?? "") ?? .system
        linkTarget = LinkTarget(rawValue: defaults.string(forKey: "linkTarget") ?? "") ?? .inApp
        storyTap = StoryTapAction(rawValue: defaults.string(forKey: "storyTap") ?? "") ?? .comments
        defaultFeed = Feed(rawValue: defaults.string(forKey: "defaultFeed") ?? "") ?? .top
        useReaderMode = defaults.object(forKey: "useReaderMode") as? Bool ?? false
        markStoriesRead = defaults.object(forKey: "markStoriesRead") as? Bool ?? true
        dimReadStories = defaults.object(forKey: "dimReadStories") as? Bool ?? true
        showSourceBadges = defaults.object(forKey: "showSourceBadges") as? Bool ?? true
        autoCollapseDeepThreads = defaults.object(forKey: "autoCollapse") as? Bool ?? false
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true

        Haptics.isEnabled = hapticsEnabled
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
