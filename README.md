# Special Projects

Self-contained iOS apps, each with its own Xcode project and a GitHub Actions
workflow that builds an **unsigned** `.ipa` on a macOS runner — so you can get
an installable build without owning a Mac, then sign it yourself.

| Project | What it is | Docs | CI |
| --- | --- | --- | --- |
| [`HackerNews`](HackerNews/) | Native SwiftUI client for news.ycombinator.com — feeds, threaded comments, search, saved stories | [README](HackerNews/README.md) | [`build-hackernews-ipa.yml`](.github/workflows/build-hackernews-ipa.yml) |
| [`AdFreeTube`](AdFreeTube/) | Ad-free YouTube client — the real site in a `WKWebView` with network- and page-level ad blocking | [README](AdFreeTube/README.md) | [`build-ipa.yml`](.github/workflows/build-ipa.yml) |

## Getting a build

Each workflow runs on pushes to its project's dev branch, and on demand from
the **Actions** tab → pick the workflow → **Run workflow**. Download the
artifact it uploads, unzip it, and sign the `.ipa` with your own certificate
(Signulous, ESign, Sideloadly, `codesign`, …).

No signing secrets are stored in CI — the builds are unsigned on purpose.
