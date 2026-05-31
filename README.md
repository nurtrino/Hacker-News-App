# AdFreeTube

A stable, ad-free YouTube client for iOS.

Rather than reimplementing YouTube's private API (which breaks constantly and
gets clients banned), AdFreeTube wraps the **real YouTube website** in a native
`WKWebView` and strips ads at two layers:

1. **Network layer** — a compiled `WKContentRuleList`
   (`AdFreeTube/Resources/blockerList.json`) blocks ad / tracking domains and
   ad-serving URL paths before they ever load.
2. **Page layer** — an injected `MutationObserver`
   (`AdFreeTube/Resources/inject.js`) auto-clicks **Skip Ad**, fast-forwards
   unskippable in-stream ads to their end, and removes ad/promoted DOM nodes.
   Cosmetic CSS (`AdFreeTube/Resources/cosmetic.css`) hides the static ad
   surfaces (masthead, in-feed, companion slots).

Because it depends on **no third-party servers** (no Invidious/Piped instance
to go down), it keeps working as long as youtube.com itself works.

## Features

- Full YouTube site — search, subscriptions, sign-in, comments, playlists.
- Pre-roll / mid-roll video ads skipped automatically.
- Banner, in-feed, masthead, and overlay ads removed.
- **Background audio** and **Picture-in-Picture** (audio keeps playing with the
  screen locked once PiP is active).
- Inline & fullscreen playback, AirPlay, back/forward/home/reload toolbar,
  edge-swipe navigation.
- iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`), iOS 16+.

## Project layout

```
AdFreeTube.xcodeproj          Xcode project (objectVersion 56, Xcode 14+)
AdFreeTube/
  AdFreeTubeApp.swift         App entry; configures the audio session
  ContentView.swift           Web view + navigation toolbar
  WebView.swift               WKWebView wrapper (UIViewRepresentable) + coordinator
  ContentBlockerStore.swift   Compiles the rule list, loads injected JS/CSS
  AudioSessionManager.swift   AVAudioSession (.playback) for background audio
  Info.plist                  UIBackgroundModes=audio, orientations, ATS
  Assets.xcassets             AppIcon (add your 1024² art) + AccentColor
  Resources/
    blockerList.json          Network-layer ad/tracker block rules
    inject.js                 In-stream ad skipper / DOM cleaner
    cosmetic.css              Static ad-surface hiding
```

## Build & sign the IPA

You said you'll handle signing — here's the quickest path to an IPA.

### Option A — Xcode GUI
1. `open AdFreeTube.xcodeproj`
2. Select the **AdFreeTube** target → **Signing & Capabilities** → pick your
   Team and set a unique **Bundle Identifier** (default is `com.adfreetube.app`).
3. **Product → Archive**, then **Distribute App** to export a signed `.ipa`.

### Option B — Command line
```bash
# Archive (set your team + a unique bundle id)
xcodebuild -project AdFreeTube.xcodeproj \
  -scheme AdFreeTube \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/AdFreeTube.xcarchive \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.adfreetube \
  archive

# Export the signed IPA (provide an ExportOptions.plist for your method)
xcodebuild -exportArchive \
  -archivePath build/AdFreeTube.xcarchive \
  -exportPath build/ipa \
  -exportOptionsPlist ExportOptions.plist
```

A minimal `ExportOptions.plist` for ad-hoc / development signing:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>development</string>
  <key>teamID</key><string>YOUR_TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
```

### Unsigned IPA (sign it yourself afterward)
If you prefer to build unsigned and sign with your own tooling:
```bash
xcodebuild -project AdFreeTube.xcodeproj -scheme AdFreeTube \
  -configuration Release -sdk iphoneos -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build
mkdir -p Payload && cp -R build/Build/Products/Release-iphoneos/AdFreeTube.app Payload/
zip -r AdFreeTube-unsigned.ipa Payload
```

## Notes & tuning

- **App icon:** drop a 1024×1024 PNG into
  `AdFreeTube/Assets.xcassets/AppIcon.appiconset` (and reference it in that
  folder's `Contents.json`) before shipping.
- **Ad selectors drift.** YouTube changes class names periodically. If an ad
  type slips through, update the selectors in `inject.js` / `cosmetic.css` —
  no native code changes needed.
- **What network blocking can't do:** in-stream video ads come from the same
  `googlevideo.com` hosts as the real video, so they can't be URL-blocked —
  that's exactly why `inject.js` exists to skip them in the player.
- **Background audio** requires PiP to be engaged for *video*; pure audio keeps
  playing once a media element is active (`UIBackgroundModes = audio`).
- This is a personal-use client. It is not affiliated with or endorsed by
  YouTube/Google.
