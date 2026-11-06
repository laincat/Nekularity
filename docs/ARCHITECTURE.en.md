# Nekularity architecture

English | [简体中文](ARCHITECTURE.md)

Date: 2026-10-30. See [CODE-AUDIT.en.md](CODE-AUDIT.en.md) for this audit and cleanup.

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
├─ AI/         StandardAI: the built-in OpenAI/Anthropic protocols (key in the Keychain), separate from Magpie packages
├─ Storage/    SourceStore: source data, settings, plugin records
└─ Library/    SourceLibrary (installs and indexes), ImageLoader
```

Rules:

- Screens only call `CoreClient` and never touch the types gomobile generates.
- gomobile methods block, so `CoreClient` always runs them in the background and exposes them to the interface as `async`; Core is never called on the main thread.
- `URLSessionTransport` sends the requests and keeps a separate cookie store for each `partition` Core gives, so sources never share login state.
- When Core asks for human verification, `WebViewVerifier` opens the page in a `WKWebView`, waits until the challenge markers are gone and `cf_clearance` is set, and returns the WebView's User-Agent to Core.
- `.venera` backups are not parsed here. Core's `mobile.Core.ReadBackup(path, tempDir, knownKeysJSON)` and `PlanBackup(path, tempDir, knownKeysJSON, selectionJSON)` already unwind the archive, its sqlite tables and the type hashes, returning JSON with `history`, `folders`, `imageFavorites`, `searchHistory`, `sources` and `settingKeys`; the client only has to land that JSON in `ShelfStore` and `SearchHistoryStore` (both already have `merge`) and install the listed `sources` through the normal path. Both clients then share one parser instead of each growing its own zip/sqlite logic.

## Layers of the Magpie plugin system

The iOS **Magpie plugin system is integrated into the app and runs independently**. It is separate from the comic-source `plugin.Registry` and shares no registry with it. It requires neither a desktop Magpie installation nor a desktop gateway or Bun process. Desktop Nekophage initially connects to a locally installed Magpie through a separate integration path.

The current target is **built-in OpenAI Chat/Responses and Anthropic Messages standard APIs in Core, with other providers, routing, usage and content masking supplied through installed Magpie plugins**. Core retains protocols, streaming/cancellation, the plugin host, events and strategy execution. Business policies must not become mandatory hard-coded scheduling for standard calls. See Core's [boundary assessment](https://github.com/laincat/VeneraCat-Core/blob/main/docs/AI-CORE-BOUNDARY.en.md).

Status correction2026-11-04: independent standard API entry points,three-protocol Core/gomobile paths and iOS fixture flows are implemented with distinct evidence; provider-plugin foundations also have targeted coverage. Generic strategy/middleware and full Magpie capabilities remain incomplete; magpierouting is still a prototype. The standard AI page presents whole responses,not verified incremental UI streaming:


```
Core (package magpieplugin)  reads a package, validates paths and sizes, starts one
│                            JavaScript runtime per account, implements fetch/Headers/
│                            URL/AbortSignal/ReadableStream, and decodes SSE into
│                            EventText/EventReasoning/EventEnd/EventError.
│                            Core opens no connections: the client injects them.
NekularityKit/Magpie/
├─ CoreMagpie                a thin wrapper over the gomobile MobileMagpie
├─ MagpieAccounts            one runner and one cached declaration per provider
├─ MagpieRunner              install, sign-in, usage, models, chat, check-in, options
├─ MagpieAuthStore(Keychain) credentials stored as the exact text given, not re-encoded
├─ MagpiePackageStore        one package per provider, replaced on reinstall, atomic index;
│                            a package arrives as an extracted folder or a zip/tar.gz
├─ MagpieSignIn              device-code/callback polling, cancel, timeout
├─ MagpieChat                events as AsyncThrowingStream; stopping cancels the request
└─ MagpieOptionStore         the switches a package declares, keyed provider|option
App/                         the "AI providers" tab, sign-in, usage and options screens
```

Rules:

- **Credentials stay on the client.** Core receives strings from `client.auth.get/set`; it
  persists nothing itself and never carries a value across provider ids. The client writes
  to the Keychain per provider.
- **Extraction belongs to Core.** `ReadArchive` unpacks zip and tar.gz, strips one enclosing
  directory, refuses symlinks and traversal, and applies the same limits a folder install gets;
  the client only stores the table Core produced instead of growing a second extractor.
- **A package's requests go through its own loader/fetch.** Core does not reimplement a
  vendor's refresh or sign-in, or every new provider would mean changing Core.
- **Chat is pulled, not pushed.** gomobile cannot call back from Go into Swift, so `chatNext`
  polls; closing a runner cancels the conversations it started rather than writing into a
  channel nobody reads.
- **Not reported is not zero.** A missing usage share is `null` and draws no 0% bar; a vendor
  refusing a request is an error, not an empty list.
- **No retry after output starts.** Once text has been sent the endpoint is locked, so a
  fallback cannot duplicate a paragraph; failures before any output may move on.
- **Unsupported dependencies fail loudly.** Node built-ins, npm dependencies and CLI calls
  report `ErrUnsupportedModule` or a capability error instead of a hollow stub.
- **Timeouts.** Sign-in and replies are both bounded, because a package that only ever says
  "nothing yet" must not leave the screen spinning.

## Dependencies

- `VeneraCatCore.xcframework`: built by `scripts/fetch-core.sh`, which runs `scripts/mac-verify.sh` in the Core repository, and placed in `Vendor/`; it is not committed.
- `AetherEngine 7.58.0`: the Swift package pinned exactly in project.yml and already used by the App.
- See the[ecosystem survey](../../VeneraCat%20Sources/docs/ECOSYSTEM.en.md) for future editor/plugin SDK reuse;candidates are not automatically production dependencies.

## Verification

The early uncompiled-on-macOS statement is obsolete. Files corresponding to0.3.4/16 have Mac436 tests/81 suites,device/simulator compilation and targeted UI2/2 evidence; public CI/IPA/AltStore were verified separately. See STATUS for exact revisions and scope. Subsequent transport-lifetime changes require their own evidence.
