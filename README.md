# Hacker News

A native Hacker News client for **iOS** and **Android**, built on the two
public HN APIs — Firebase for feeds, items and profiles; HN Search (Algolia)
for full-text search and for pulling a whole comment tree in one request.

No third-party runtime dependencies, no accounts, no analytics.

| | Source | Docs | CI |
| --- | --- | --- | --- |
| **iOS 16+** | [`HackerNews/`](HackerNews/) · SwiftUI | [README](HackerNews/README.md) | [`build-hackernews-ipa.yml`](.github/workflows/build-hackernews-ipa.yml) |
| **Android 8+** | [`HackerNewsAndroid/`](HackerNewsAndroid/) · Kotlin + Compose | [README](HackerNewsAndroid/README.md) | [`build-hackernews-apk.yml`](.github/workflows/build-hackernews-apk.yml) |

Both share the same design: the models, both API clients, the comment HTML
parser and the thread-flattening logic are the same algorithms in each
language. Only the UI layer differs.

## Download

Every green build publishes both artifacts into one rolling release:

**<https://github.com/nurtrino/Special-Projects/releases/tag/latest>**

- `HackerNews.apk` — signed and installable as-is. Allow installs from your
  browser or file manager the first time.
- `HackerNews-unsigned.ipa` — unsigned on purpose, so no signing secrets live
  in CI. Sign it with your own certificate (Signulous, ESign, Sideloadly,
  `codesign`) and install.

Bundle / application id is `com.nurtrino.hackernews` on both platforms, and
neither build requests any entitlements or permissions beyond network access.

## Building

Neither project needs anything checked out beyond this repo. The workflows run
on every push to the dev branch, or on demand from the **Actions** tab. See
each project's README for local build instructions.

Unofficial and unaffiliated with Y Combinator.
