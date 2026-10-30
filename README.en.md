# Nekularity

English | [简体中文](README.md)

A comic and video client for iOS/iPadOS with a SwiftUI interface, licensed GPL-3.0-or-later. Its logic comes from [VeneraCat Core](https://github.com/laincat/VeneraCat-Core), which is compatible with Venera comic-source scripts and their indexes.

## Status

The first phase builds one path: **add a comic source → search or browse → open a comic → read it → keep it on the shelf**. The code has not been compiled on macOS yet, but every change goes through `scripts/check-swift.sh`, which parses all Swift files for syntax errors; see [docs/STATUS.en.md](docs/STATUS.en.md).

## Layout

| Directory | Contents |
|---|---|
| `App/` | SwiftUI screens: sources, search, details, reader, source-driven dialogs and human verification |
| `Sources/NekularityKit/` | Everything except the screens: Core wrapper, networking, cookies, storage, image loading |
| `Tests/` | NekularityKit unit tests |
| `docs/` | Architecture and status |
| `scripts/` | Building Core, documentation checks, Swift syntax check |

## Building

Needs macOS, Xcode 26, Go (the version in Core's `go.mod`) and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
scripts/fetch-core.sh            # builds VeneraCatCore.xcframework into Vendor/
swift test                       # NekularityKit unit tests
xcodegen generate                # generates Nekularity.xcodeproj
open Nekularity.xcodeproj
```

`scripts/core-version` names the Core branch, tag or commit to use. A local Core checkout also works: `scripts/fetch-core.sh ../VeneraCat-Core`.

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE).
