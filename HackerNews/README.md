# Hacker News for iOS

A native SwiftUI client for [news.ycombinator.com](https://news.ycombinator.com).
No third-party dependencies, no scraping, no analytics, no accounts — it reads
from the two public HN APIs and nothing else.

- **[Firebase HN API](https://github.com/HackerNews/API)** — story lists, items,
  user profiles.
- **[HN Search](https://hn.algolia.com/api)** (Algolia) — full-text search, and
  pulling an entire comment tree in a single request.

Requires iOS 16.0 or later. iPhone and iPad.

## What it does

**Feeds** — Top, New, Best, Ask HN, Show HN and Jobs, each with its own
scroll position and cache. Pull to refresh, infinite scroll, rank numbers on
the ordered lists.

**Discussions** — the whole comment tree arrives in one request, so threads
open in about as long as one round trip. Comments are indented with a coloured
rail per level, collapse by tapping the header (with a `+N` badge showing how
many replies are folded away), and there's a collapse-all / expand-all toggle.
Deleted-but-answered comments stay as placeholders so the thread keeps its
shape.

**Comment rendering** — HN's HTML is parsed by a purpose-built parser
(`Support/HNHTML.swift`), not by handing it to WebKit. That means real
paragraph breaks, italics, tappable links, horizontally scrollable `<pre><code>`
blocks, correct entity decoding, and no main-thread stalls. Parsed bodies are
memoised so scrolling and collapsing stay smooth in long threads.

**Search** — stories or comments, sorted by relevance or date, filtered to the
past day/week/month/year, with recent searches kept. Comment hits show a
snippet and navigate to the story they belong to.

**Saved & read state** — swipe right on any story to save it; saved copies are
kept on disk and refresh their score when you open them. Stories you've opened
are marked read and dimmed. Both are local to the device.

**Profiles** — karma, join date, the `about` blurb, and a switcher between the
account's recent stories and comments.

**Everything else** — light/dark/system theme, a text-size override,
in-app browser vs Safari (with an optional Reader-mode default), a choice of
what tapping a story does, haptics, per-row share/copy/open context menus, full
VoiceOver labels and Dynamic Type support.

## Layout

```
HackerNews.xcodeproj            Xcode project (objectVersion 56, Xcode 14+)
HackerNews/
  HackerNewsApp.swift           App entry; owns the app-lifetime stores
  Models/
    Item.swift                  Story/comment/job/poll, lenient decoding
    Feed.swift                  The six story lists
    HNUser.swift                Account profile
    CommentNode.swift           Flattened, depth-tagged comment
  Networking/
    HNAPI.swift                 Firebase client: actor, memoised, de-duplicated
    AlgoliaAPI.swift            Search + whole-thread fetch
  Stores/
    AppSettings.swift           Preferences, persisted to UserDefaults
    FeedStore.swift             One paginated story list (+ the registry)
    ThreadStore.swift           Thread loading, flattening, collapse state
    SearchStore.swift           Debounced, paginated search
    LibraryStore.swift          Saved stories + read state, persisted to disk
  Support/
    HNHTML.swift                HN's HTML subset → renderable blocks
    Formatting.swift            Compact ages, abbreviated counts
    Theme.swift                 Palette and thread metrics
    Haptics.swift               Feedback, muted from one place
  Views/
    RootView.swift              Tab bar, theme and text-size overrides
    FeedScreen.swift            Feed switcher + story list
    StoryScreen.swift           Story header + comments
    CommentRow.swift            Depth rails, collapse, context menu
    StoryRow.swift              Shared story row + swipe/long-press actions
    SearchScreen.swift          Search, filters, recents
    SavedScreen.swift           Saved stories
    SettingsScreen.swift        Preferences
    UserScreen.swift            Profile + submissions
    RichText.swift              Renders parsed comment bodies (memoised)
    SafariView.swift            SFSafariViewController + the link router
    Components.swift            Empty/error/loading states, chips, badges
  Assets.xcassets               App icon + accent colour
  Info.plist
```

## Getting an IPA without a Mac

`.github/workflows/build-hackernews-ipa.yml` builds an **unsigned** `.ipa` on a
GitHub-hosted macOS runner and publishes it, alongside the Android APK, into a
single rolling release:

<https://github.com/nurtrino/Hacker-News-App/releases/tag/latest>

Grab `HackerNews-unsigned.ipa` from there — it's a bare `.ipa`, not wrapped in
a zip, so it downloads cleanly in mobile Safari. The same file is also attached
to each run as a workflow artifact if you'd rather go through the Actions tab.

No signing secrets are stored in CI — it builds unsigned on purpose, so you can
sign it yourself.

### Signing with Signulous

1. Download `HackerNews-unsigned.ipa` from the release above.
2. Upload it to Signulous and sign it with your certificate.
3. Install the signed IPA from the link Signulous gives you.

The bundle identifier ships as `com.nurtrino.hackernews`. No entitlements are
required — the app has no App Groups, push, iCloud or keychain access, so a
plain development or ad-hoc certificate is enough.

### If you do have a Mac

```bash
open HackerNews.xcodeproj
# Target → Signing & Capabilities → pick your Team and a unique bundle id
# Product → Archive → Distribute App
```

Or from the command line:

```bash
xcodebuild -project HackerNews.xcodeproj -scheme HackerNews \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/HackerNews.app Payload/
ditto -c -k --sequesterRsrc --keepParent Payload HackerNews-unsigned.ipa
```

## Notes

- **Read-only.** HN has no public write API, so there's no voting, commenting or
  login. The context menus link out to the real site for anything that needs an
  account.
- **Search lags.** The Algolia index takes a few minutes to pick up brand-new
  posts. When a thread isn't indexed yet the app falls back to walking the
  Firebase API level by level, so very new stories still load — just slower.
- **Storage.** Saved stories and read state live in
  `Application Support/HackerNews/`. Network responses are cached by
  `URLCache` (128 MB on disk for the API, 64 MB for search); both are cleared
  from Settings.
- Unofficial and unaffiliated with Y Combinator.
