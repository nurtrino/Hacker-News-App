# Hacker News for Android

A native Jetpack Compose client for
[news.ycombinator.com](https://news.ycombinator.com), and a direct port of the
iOS app in this repo. Requires Android 8.0 (API 26) or later.

Reads from the same two public APIs as the iOS build:

- **[Firebase HN API](https://github.com/HackerNews/API)** — story lists, items,
  user profiles.
- **[HN Search](https://hn.algolia.com/api)** (Algolia) — full-text search, and
  pulling an entire comment tree in a single request.

## Shared with iOS

This isn't a wrapper or a cross-platform runtime — it's a port. The models,
both API clients, the comment HTML parser and the thread-flattening logic are
the same algorithms written twice, so behaviour matches:

| Concern | iOS | Android |
| --- | --- | --- |
| Models | `Models/Item.swift` | `model/Models.kt` |
| Firebase client | `Networking/HNAPI.swift` (actor) | `net/HnApi.kt` (object + `Semaphore`) |
| Search / threads | `Networking/AlgoliaAPI.swift` | `net/AlgoliaApi.kt` |
| Comment HTML | `Support/HNHTML.swift` | `text/HnHtml.kt` |
| Response cache | `URLCache`, 128 MB | OkHttp `Cache`, 128 MB |
| In-app browser | `SFSafariViewController` | Custom Tabs |
| UI | SwiftUI | Compose + Material 3 |

## What it does

Six feeds (Top, New, Best, Ask, Show, Jobs) with per-feed paginated state, so
switching keeps position and cache. Comment threads arrive whole from the
search index — with a level-by-level Firebase fallback for posts too new to be
indexed — and collapse per subtree with a `+N` badge and a coloured rail per
depth. Full-text search over stories or comments with sort, time-range filters
and recent searches. Saved stories and read state persisted to disk. User
profiles with their recent stories or comments. Settings for theme, text size,
default feed, tap behaviour, link target, auto-collapse and source badges.

A separate **Lobsters** tab reads [lobste.rs](https://lobste.rs) via its JSON
endpoints — Active by default, plus Hottest and Newest — with tags on each
row and the story's own `.json` feeding the same collapsible comment view.
Lobsters posts are marked read but aren't saveable, and authors open on the
site.

## Layout

```
HackerNewsAndroid/
  settings.gradle.kts
  build.gradle.kts
  app/
    build.gradle.kts
    src/main/
      AndroidManifest.xml
      java/com/nurtrino/hackernews/
        MainActivity.kt        Activity, nav graph, bottom bar
        model/Models.kt        Item, HnUser, CommentNode, Feed, Forum, LoadPhase
        model/Lobsters.kt      Lobsters feeds, story, id folding, HTML shim
        net/
          Http.kt              Shared OkHttp client + disk cache
          HnApi.kt             Firebase client, memoised, bounded concurrency
          AlgoliaApi.kt        Search + whole-thread fetch
          LobstersApi.kt       lobste.rs JSON: lists + whole threads
        text/HnHtml.kt         HN's HTML subset → renderable blocks
        data/
          Settings.kt          Preferences, SharedPreferences-backed
          Library.kt           Saved stories + read state, JSON on disk
          ViewModels.kt        Feed / thread / search / user state
          LobstersViewModels.kt Lobsters feed pagination + thread state
        ui/
          Theme.kt             Palette, type scale, thread colours
          Common.kt            Link routing, formatting, shared composables
          RichText.kt          Renders parsed comment bodies
          StoryRow.kt          Shared story row + long-press menu
          CommentRow.kt        Depth rails, collapse, header
          FeedScreen.kt  StoryScreen.kt  SearchScreen.kt
          LobstersScreen.kt  LobstersStoryScreen.kt
          SavedScreen.kt SettingsScreen.kt UserScreen.kt
      res/                     Adaptive icon, themes, strings
```

## Installing

Every green build publishes the APK into the shared release:

<https://github.com/nurtrino/Hacker-News-App/releases/tag/latest>

Download `HackerNews.apk` and open it. Android will ask you to allow installs
from whichever app you downloaded it with — that's a one-time per-app setting
under **Settings → Apps → Special access → Install unknown apps**.

### Signing

The release build is signed with the CI **debug key** by default, which is
enough to install but means an *update* may ask you to uninstall the previous
build first (Android refuses to replace an APK signed with a different key).

For stable updates, add these repository secrets and the workflow picks them up
automatically:

| Secret | Meaning |
| --- | --- |
| `KEYSTORE_BASE64` | `base64 -w0 release.jks` |
| `KEYSTORE_PASSWORD` | Keystore password |
| `KEY_ALIAS` | Key alias inside the keystore |
| `KEY_PASSWORD` | Key password |

Generate one with:

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias hackernews
```

### Building locally

```bash
cd HackerNewsAndroid
./gradlew :app:assembleRelease     # or: gradle :app:assembleRelease
# app/build/outputs/apk/release/app-release.apk
```

Needs JDK 17 and the Android SDK (compileSdk 35). The project has no Gradle
wrapper checked in; CI provisions Gradle 8.11.1 via `gradle/actions/setup-gradle`.

## Notes

- **Read-only.** HN has no public write API, so there's no voting, commenting
  or login. Menus link out to the real site for anything needing an account.
- **Search lags.** The Algolia index takes a few minutes to pick up brand-new
  posts; the app falls back to walking the Firebase API when a thread isn't
  indexed yet.
- **Storage.** Saved stories and read state live in the app's `files/library/`.
  HTTP responses are cached by OkHttp in `cache/http` (128 MB), cleared from
  Settings.
- Unofficial and unaffiliated with Y Combinator or Lobsters.
