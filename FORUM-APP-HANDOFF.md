# Handoff: turning a forum website into native iOS + Android apps

Notes from building a read-only native client for a threaded-discussion site,
twice (SwiftUI and Jetpack Compose), from a Linux container with no Mac, no
Xcode, no Android Studio, and no Swift or Kotlin toolchain — CI was the only
compiler.

Written to be reused for a **different forum**. Nothing below is specific to
one site; where a decision depends on the forum's API shape, that's called out.

---

## 1. Scope the API before designing anything

Answer these first. They determine most of the architecture.

| Question | Why it matters |
| --- | --- |
| Is there an official read API? | If not, you're scraping, and everything below gets harder and more fragile. |
| Is there a **second**, search-oriented index? | Often the only way to get a whole comment tree in one request. Huge. |
| Can you get a thread in one call, or one call per comment? | Decides whether threads open in 300 ms or 30 s. |
| Is there a write API? | Usually no. Then the app is **read-only** — decide that up front, don't bolt it on. |
| Are there rate limits / auth requirements? | Changes the caching and concurrency design. |

**The single highest-leverage finding on the last project:** the forum had two
APIs — a canonical item API (one object per request) and a search index. The
search index could return an *entire* comment tree in a single request. Threads
went from N requests to 1.

The catch: search indexes lag. Brand-new posts aren't indexed for minutes. So:

```
try the index (1 request)
  → if it returns nothing AND the item claims to have replies
      → fall back to walking the canonical API level by level
```

Build both paths. The fallback is slower but keeps new content working.

---

## 2. Architecture that ported cleanly

Layers, in dependency order. The first four are **pure logic and ported almost
line-for-line** between Swift and Kotlin; only the last is written twice in
earnest.

```
model/     Item, User, CommentNode, Feed enum, LoadPhase enum
net/       Canonical API client, search client, shared HTTP + cache
text/      Comment HTML → renderable blocks   ← most intricate, most reusable
data/      Stores: feeds, thread, search, settings, saved/read state
ui/        SwiftUI / Compose screens          ← the only genuinely platform half
```

Keep `text/` free of any platform import (no SwiftUI, no Compose, no Android
`Context`). It's the part most likely to have bugs and the part you can
actually test in isolation.

### Model decisions worth copying

- **One `Item` type** for stories/comments/jobs/polls rather than a hierarchy.
  Forums blur these constantly and a sum type creates casting noise everywhere.
- **Lenient decoding.** APIs omit keys entirely for missing values *and* send
  `null` for keys they do include. A single unexpected field must never kill
  the whole object. Write a `lenient(...)` helper and use it for every field
  but the id.
- **Unknown enum cases decode to `.unknown`**, never throw.

---

## 3. The comment-thread design (most important structural choice)

**Flatten the reply tree into a depth-tagged array in reading order.** Do not
keep a recursive tree in the view layer.

```
[ (id, depth: 0), (id, depth: 1), (id, depth: 2), (id, depth: 1), (id, depth: 0), … ]
```

Everything falls out of this:

- **Collapse a subtree** = skip the following run of nodes whose depth is
  greater than the collapsed node's. One linear pass, no tree mutation.
- **Descendant count** (`+12` badge on a collapsed comment) = one pass with a
  stack of open ancestors:
  ```
  for i in indices:
      while stack.last.depth >= node[i].depth: stack.pop()
      for idx in stack: counts[idx] += 1
      stack.push(i)
  ```
- **Rendering** = a flat list, which both platforms' recycling lists want anyway.
  A recursive view tree kills scroll performance on long threads.
- **Indentation** = N coloured rails from the depth. Cap the depth used for
  indentation (~8) or deep threads squeeze the text to nothing.

Keep **deleted-but-answered** comments as placeholders. Dropping them reparents
their replies and silently corrupts the thread shape. Drop only deleted nodes
with no surviving children.

---

## 4. Rendering forum HTML — do not use the platform HTML renderer

Forums emit a tiny HTML subset (typically unclosed `<p>`, `<i>`/`<b>`,
`<a href>`, `<pre><code>`, and character entities). Every platform option is
wrong for it:

| Option | Why not |
| --- | --- |
| `WKWebView` / `WebView` per comment | Enormous, janky in a list, unstyleable |
| `NSAttributedString(data:documentType:.html)` | Pulls in WebKit, blocks the main thread, loses code blocks |
| `Html.fromHtml` | Loses code blocks, no control over link handling |

**Write a ~250-line parser.** It's less work than fighting any of the above.

Design it to emit **blocks**, not one string:

```
Paragraph(text, spans[])   // spans carry italic / bold / link-url + range
Code(text)                 // rendered monospaced in a horizontal scroller
```

A single attributed string can't represent a code block that scrolls
independently, which is why block output matters.

### Parser gotchas, all of which cost real time

- **A stray `<` in prose is not a tag.** `a < b and c > d` — a naive scanner
  finds the next `>` and swallows everything between. Require the character
  after `<` to be a letter or `/`, else treat it as literal text. *This bug
  shipped and was only caught by tests.*
- **Entities**: handle named, decimal `&#8212;` and hex `&#x27;`. Bound the
  lookahead (~12 chars) so a bare `&` in prose doesn't eat the rest of the line.
- **Decode entities inside `href` too**, then **allow only `http`/`https`** —
  a comment body is untrusted input.
- **Trim paragraph whitespace and shift the span offsets with it**, or your
  italic/link ranges drift by the number of trimmed leading spaces.
- **Track link/emphasis as a stack**, not a boolean; nesting happens.
- **Memoise parse results** keyed on the raw HTML. Threads re-render constantly
  while scrolling and collapsing; re-parsing every pass is the difference
  between smooth and stuttery.

### Test the parser even when you can't compile

The parser is the same algorithm in both languages. Transliterate it into a
scripting language and assert against **real markup pulled from the forum**:

- entities decode, including numeric
- an italic span covers exactly the intended word (check offsets, not just text)
- a link's range covers the anchor text and its URL is entity-decoded
- code blocks survive with their internal `&lt;` decoded
- `javascript:` hrefs produce no link
- stray `<` and `>` survive as text
- whitespace-only paragraphs are dropped and spans still line up

~20 assertions. This caught a genuine bug present in **both** ports.

---

## 5. Networking

- **Memoise items in-process** and **de-duplicate in-flight requests** by id.
  Without this, collapse/expand and pagination re-request the same parents
  endlessly.
- **Bounded concurrency** (~12) for batch fetches — a semaphore or a task group
  with a sliding window. Unbounded fan-out on a 500-item list will exhaust the
  socket pool.
- **Return batches in the requested order**, not completion order.
- **Disk-backed HTTP cache**: `URLCache` (iOS) / OkHttp `Cache` (Android),
  ~128 MB. Free offline-ish behaviour and much faster relaunch.
- **Force-refresh path** that bypasses the cache, for pull-to-refresh.
- Map transport errors to **one user-facing sentence**, decided in the network
  layer, not the view.

---

## 6. Platform pitfalls that actually cost build cycles

### SwiftUI

- **`.task` without `id:` never re-runs.** If a parent swaps in a different
  observed object at the same position in the hierarchy, the view's *identity*
  is unchanged, so `.task` does not fire again. Symptom: switching tabs/feeds
  shows a blank list forever, but pull-to-refresh works.
  → `.task(id: store.someKey) { … }`. **This shipped as a user-visible bug.**
- `.task` / `.refreshable` closures **do inherit main-actor isolation** in
  practice. Don't add speculative `await` to sync `@MainActor` calls inside
  them — the compiler flags it as redundant.
- **`@AppStorage` does not publish changes when it lives inside an
  `ObservableObject`.** Use plain `UserDefaults` + `@Published` + `didSet`.
- **`ViewModifier.body(content:)` is not implicitly `@ViewBuilder`.** Branching
  in it needs an explicit `@ViewBuilder`.
- **Don't nest `Button`s inside a list row that also navigates** — the row
  swallows the taps. Make secondary actions swipe actions or context menus.
- In a comment row, make **only the header** toggle collapse. A tap gesture on
  the whole row competes with the links inside the body.
- Property observers **don't fire during `init`** — convenient for loading
  persisted settings without redundant writes.

### Kotlin / Compose

- **`fun setX(...)` collides with the generated JVM setter of a property `x`**
  → `Platform declaration clash`. Name explicit setters `updateX`. *One
  mistake, 26 errors.*
- **`TextUnit.isUnspecified` is a top-level extension**, not a member; needs an
  explicit import. Same trap for several other Compose helpers.
- **`combinedClickable`** (long-press) is experimental →
  `@OptIn(ExperimentalFoundationApi::class)`.
- **`android:Theme.Material.DayNight` does not exist.** Platform styles only
  have `Theme.Material` (dark) and `Theme.Material.Light`. Use a light parent
  plus a `values-night/` override.
- **Stick to `material-icons-core`.** The extended set adds megabytes; the core
  set covers a reader app if you're willing to substitute.
- `LaunchedEffect(key)` is **keyed by construction**, so Compose doesn't have
  SwiftUI's stale-`.task` trap. Reads are per-key.
- Compose state in view models (`mutableStateOf` / `mutableStateListOf`)
  recomposes without any Flow plumbing. Mutate it from the main thread only.

### App icons — the two platforms want opposite things

Given one square source image:

- **iOS**: 1024×1024, **RGB with no alpha** (alpha is rejected), and
  **full-bleed** — iOS applies its own superellipse mask, so artwork with its
  own rounded corners shows dark wedges outside the mask. If the source is
  pre-rounded, **flood-fill the corners** from outside with the background
  colour (a brightness threshold leaves a visible antialiased ring; a flood
  fill from the corners follows the real edge).
- **Android**: adaptive icon = solid background layer + **transparent
  foreground** PNG (432×432 works). The safe zone is the **centre ~66%** —
  anything outside can be masked off. Check the glyph's bounding box fits, and
  recentre it if the source art was optically offset.
- Extracting a light glyph off a saturated background: **per-pixel channel
  minimum** makes a decent alpha channel (white → 255, saturated colour → 0)
  and preserves antialiased edges.
- **Sample the real accent colour out of the icon** rather than assuming the
  brand hex. It was several shades off from the obvious guess.

---

## 7. Shipping without a Mac (or any local toolchain)

### iOS

- GitHub Actions `macos-*` runner, `xcodebuild` with
  `CODE_SIGNING_ALLOWED=NO`, zip `Payload/YourApp.app` with
  `ditto -c -k --sequesterRsrc --keepParent` → **unsigned `.ipa`**.
- No certificates or secrets in CI. Sign externally (a signing service, or
  `codesign` if you have a Mac later).
- **A hand-written `project.pbxproj` works fine.** Generate it with a script
  and assert that (a) every listed source exists on disk and (b) every `.swift`
  on disk is listed — a missing file fails at link time with a confusing error.
- Keep the scheme in `xcshareddata/xcschemes/` or `-scheme` won't resolve.

### Android

- `actions/setup-java` (17) + `android-actions/setup-android` +
  `gradle/actions/setup-gradle` with an explicit `gradle-version`. **No Gradle
  wrapper needs to be committed** if CI provisions Gradle.
- Ship a **release build signed with the debug key when no keystore is
  configured**, so a fresh clone with zero secrets still produces something
  installable:
  ```
  signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
  ```
- ⚠️ **CI runners are fresh VMs, so the debug keystore is regenerated per run.**
  Android refuses to update an app whose signing key changed, so every update
  becomes uninstall-then-reinstall (losing local data). For anything you'll
  actually use over time, add a real keystore via secrets from day one.

### Distribution

- **Publish release assets, not workflow artifacts.** Artifacts are wrapped in
  an extra `.zip` and can't be downloaded from the GitHub mobile app at all. A
  release asset is the bare file at a stable URL.
- One **rolling release** holding both platforms' binaries. With two workflows
  racing to publish, make it idempotent:
  ```
  gh release view "$TAG" >/dev/null 2>&1 || gh release create "$TAG" … || true
  gh release upload "$TAG" <asset> --clobber
  ```
- For update tracking on Android, an app that watches a repo's releases
  (Obtainium and similar) turns the rolling release into an update channel —
  but only if the signing key is stable (see above).

---

## 8. Working without a compiler

This dominated the schedule; plan for it.

- **CI is your compiler.** Each round trip is 1–6 minutes. Expect several.
- **Errors arrive in phases.** Android order is roughly: manifest → resource
  linking → Kotlin compile → dex/package. A green resource step tells you
  **nothing** about whether the code compiles. "It got further this time" is
  the real progress signal.
- **Fix by class, not by instance.** When 26 errors share one root cause, fix
  the cause and grep for the pattern everywhere before pushing.
- **Before pushing, cheaply check what you can locally:** bracket/paren balance
  per file, every file declares a package/module, no placeholder syntax, YAML
  parses, referenced resources exist, every source file is in the build.
- **Prefer conservative APIs.** Every experimental or bleeding-edge API is a
  possible build failure you can't check. Deprecated-but-stable beats new.
- **Verify outcomes against the API, not the job status.** A green job doesn't
  prove the asset changed — check the uploaded asset's size, SHA and timestamp.
- **Compiling is not running.** Both apps built and packaged cleanly and still
  had a user-visible bug on first launch. Say so plainly rather than implying
  the thing is verified.

---

## 9. Product decisions that held up

- **Read-only, stated up front.** No write API means no voting/replying; link
  out to the site for anything needing an account. Trying to fake it is worse
  than omitting it.
- **One store per feed**, kept alive for the app's lifetime, so switching tabs
  preserves scroll position and cache instead of refetching.
- **Saved items and read state on disk, local only.** Cap the read-id list
  (~5k, newest first) and debounce writes (~400 ms) so marking a screenful of
  items read is one write. Flush on background.
- **Paginate from an id list.** Many forum APIs hand back hundreds of ids and
  nothing else; hold the list, hydrate ~25 at a time.
- **Settings worth having:** theme, text size, default feed, what tapping a row
  does (article vs comments), in-app browser vs system browser, auto-collapse
  deep replies, mark-as-read.
- **Empty / error / loading states for every screen**, with a retry that
  actually re-runs the request. Easy to skip, immediately obvious when missing.

---

## 10. Suggested build order for the next forum

1. Probe the API by hand. Confirm whether a whole thread can be fetched in one
   request. **This shapes everything.**
2. Models + lenient decoding.
3. Network clients: memoised, de-duplicated, bounded concurrency, disk cache.
4. HTML parser **plus its test suite**, in a scripting language first if you
   can't compile.
5. Thread flattening + collapse + descendant counts.
6. Stores/view models: feed pagination, thread, search, settings, library.
7. CI that produces an installable artifact — **do this before the UI is
   finished**, so the first build failure arrives while there are 500 lines to
   search, not 3,000.
8. UI screens.
9. Icons, both platforms, from one source image.
10. Run it. Fix what only shows up at runtime.
