# Nekularity architecture

English | [简体中文](ARCHITECTURE.md)

Date: 2026-10-30.

## Goal

A native client for iOS/iPadOS 26 and later, with a SwiftUI interface. Business logic lives in [VeneraCat Core](https://github.com/laincat/VeneraCat-Core); the client provides the interface, networking, WebViews, the player and storage.

The first phase builds one path: **install a comic source → search → open a comic → read its images**.

## Layers

```
App/                        SwiftUI screens (depend only on NekularityKit)
│   NekularityApp           start-up, dependency wiring
│   PromptCenter            source-driven toasts, dialogs, input, choices, loading, verification
│   SourcesView / SearchView / ComicDetailView / ReaderView
Sources/NekularityKit/      no UI; testable with swift test
├─ Core/       CoreClient (async wrapper), CoreHost (implements MobileHostProtocol),
│              Models, JSONValue, OrderedJSONDecoder
├─ Platform/   URLSessionTransport, CookieJars, VerificationSession (WKWebView)
├─ Storage/    SourceStore: source data, settings, plugin records
└─ Library/    SourceLibrary (installs and indexes), ImageLoader
```

Rules:

- Screens only call `CoreClient` and never touch the types gomobile generates.
- gomobile methods block, so `CoreClient` always runs them in the background and exposes them to the interface as `async`; Core is never called on the main thread.
- `URLSessionTransport` sends the requests and keeps a separate cookie store for each `partition` Core gives, so sources never share login state.
- When Core asks for human verification, `WebViewVerifier` opens the page in a `WKWebView`, waits until the challenge markers are gone and `cf_clearance` is set, and returns the WebView's User-Agent to Core.

## Dependencies

- `VeneraCatCore.xcframework`: built by `scripts/fetch-core.sh`, which runs `scripts/mac-verify.sh` in the Core repository, and placed in `Vendor/`; it is not committed.
- No other third-party dependencies.

## Verification

The code in this phase has not been compiled on macOS yet. It calls Core the same way as `apple/CoreSmoke` in the Core repository, which passes on CI (`MobileNew`, `MobileHostProtocol`, and methods with an `error: NSErrorPointer` parameter).
