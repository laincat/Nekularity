# Code audit and cleanup

English | [简体中文](CODE-AUDIT.md)

## Scope and baseline

Baseline: Nekularity `b294f04`, Core pin `469edfcb48ec9564dca086a232a7b64e46fd0a9b`. Lead reviewed boundaries, persistence, lifecycle and bridging. An Orca Worker reviews networking, caching, cancellation and Magpie in an isolated Mac directory and validates the patched tree. Windows syntax checks do not establish Swift 6 type correctness or an App build.

## Local fixes in this pass

| Problem | Change | Regression/verification |
|---|---|---|
| `signOut` closed Core directly without setting the runner's closed flag | Call the idempotent `close()` path | New case checks sign-out, explicit close and deinit close Core once in total |
| Core retains Host, which strongly held its Core callback handle | Make `CoreHost.core` weak | Requires Mac Swift 6 and lifecycle validation; no peak-memory measurement claimed |
| Valid JSON with a non-object root, malformed fields or read errors could become empty state | Only a missing file is a new source; other errors throw and preserve the original | New cases cover damaged text, null, arrays, malformed data and writable null objects |

Core also fixes cancellation before call registration and post-close call lifetimes in this pass. iOS needs a framework rebuilt from the patched source, not an old pinned artifact.

## Architecture and dependencies

SwiftUI App → NekularityKit → CoreClient/CoreMagpie → gomobile Core. Clients own system capabilities: URLSession sends requests, Keychain stores AI credentials, CookieJars isolates sources, ImageIO downsamples images and WKWebView handles verification. Package.swift adds no third-party Swift package; VeneraCatCore is a local binaryTarget. XcodeGen is a build tool rather than an App runtime dependency.

`ImageLoader` already has size-specific cache keys, request coalescing, ImageIO downsampling and an NSCache cost limit of 128 MiB. That is a cache eviction hint, not a hard memory ceiling for the entire process.

## Remaining improvements and missing capabilities

- `URLSessionTransport` checks size only after the whole body arrives, so it cannot prevent oversized buffering. Bound bytes at the delegate/chunk layer alongside real streaming.
- `cancel(id:)` can run before URLSession task registration. The current test deliberately waits 50ms before cancelling and does not cover this order. Preserve pending cancellation or register a cancellable task object.
- Cross-origin redirects need explicit removal of custom provider authentication headers rather than relying solely on Foundation's `Authorization` policy.
- `ImageLoader`'s shared inFlight Task does not automatically stop when one waiter cancels. Multiple waiters need reference counting or a deliberate cache/prefetch policy, not unconditional cancellation of shared work.
- Check refreshed-auth persistence separately for models, usage and chat; a generic call saving auth is insufficient evidence for all paths.
- Standard AI construction and whole-body execution exist in gomobile, but the client UI does not use them yet. Real network streaming and real-account evidence remain missing.

## Verification boundary

Patched-file hashes, shape, test/suite counts and `xcodebuild` results must refer to the same tree. The Mac's old 173-test routing prototype is not merged and is not this baseline. The three-project visualization lives at `Nekophage/docs/analysis/architecture-audit.html` in the shared workspace.
