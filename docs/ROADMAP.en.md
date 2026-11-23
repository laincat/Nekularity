# Roadmap and active decisions

[简体中文](ROADMAP.md) | English

This page keeps only active product and architecture decisions, the current execution order and stopping rules. Per-release logs live in Git history and [STATUS.en.md](STATUS.en.md).

## Active architecture and product decisions

- **Business logic lives in VeneraCat Core**: source execution, backup schemas and cross-platform protocols stay in Core, while Nekularity owns SwiftUI screens, networking, WebView, playback and platform storage. Since `e353650`, the client tracks upstream Core `main`.
- **HTTPS by default and strict isolation**: ATS keeps `NSAllowsArbitraryLoads` off and allows HTTP only for local networking and explicitly declared official source hosts; cookies stay isolated per partition, AI/service secrets stay in Keychain, and backup cookie restore requires explicit user confirmation.
- **Full UI/UX rewrite ahead**: do not spend effort polishing legacy SwiftUI visuals or layouts; focus on Kit/App boundary cleanup, correctness fixes and network/storage overhead so the upcoming UI consumes clean Kit entry points.
- **Plugins and distribution**: online danmaku and optional external services follow the plugin/deferred direction; iOS supports both sideloading (AltStore) and future App Store distribution (with legal review of the LGPL exception before App Store submission).

## Current execution order

| Wave | Goal | Acceptance criteria |
|---|---|---|
| Wave 2B (current) | Local Nekularity slimming, redundant gate and duplicate media cleanup, source install/settings boundary consolidation, and Cookie/streaming/shelf overhead fixes | Windows syntax and bilingual doc checks pass; Apple CI Kit unit tests, App build and targeted regressions pass after merge |
| Wave 3 | Cross-repo consolidation with VeneraCat Core and Sources: move favourites/account/challenge rules and Magpie entry resolution into Core, align `plugins/plex.js` | Cross-platform contract tests pass and merge cleanly |
| UI rewrite | Rebuild iOS/iPadOS UI and UX on top of the clean Kit boundary | Full simulator suite and physical-device sign-off pass |

## Work requiring external conditions

- Physical-device signed install, background/lock-screen playback, PiP, hardware ActivityKit, physical speakers, real accounts and live public sites (see [UNVERIFIED.en.md](UNVERIFIED.en.md) and [HANDOFF.en.md](HANDOFF.en.md)).
- Legal confirmation of the LGPL exception before formal App Store / DRM distribution.

## Execution and stopping rules

- Fix real correctness, persistence consistency and memory/IO overhead before cross-repo contract deduplication.
- Never fabricate macOS or physical-device results; always state the exact scope actually verified.
