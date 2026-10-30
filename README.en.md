# Nekularity

English | [简体中文](README.md)

A comic client for iOS/iPadOS with a SwiftUI interface (video comes later), licensed GPL-3.0-or-later. Its logic comes from [VeneraCat Core](https://github.com/laincat/VeneraCat-Core), which is compatible with Venera comic-source scripts and their indexes.

## Status

The main path is **add a comic source → search or browse → open a comic → read it → keep it on the shelf**. There is also a separate "AI providers" tab that runs Magpie provider plugin packages: installing (a folder or a `.zip`/`.tar.gz`), sign-in, usage, model lists, chat, check-in and the plugin's own switches. The two are unrelated — different packages, accounts and cookies, and AI credentials go to the Keychain only.

One real verification on macOS 27 / Xcode 27 / Swift 6.4: `swift build`, `swift test` (**119 tests / 27 suites**), Kit and App Swift 6 type checks and the iOS module all pass with 0 errors and 0 warnings; the Core surface check is 18/18; `swift test --filter Magpie` runs 61 tests. What was **not** run: an `xcodebuild` archive and signing, and there is no iOS Simulator runtime. See [docs/STATUS.en.md](docs/STATUS.en.md), which also records what that verification does not cover. Every change still goes through `scripts/check-swift.sh`, which parses all Swift files.

Using it: on the "AI providers" tab tap "Install package" and pick either an extracted folder or the `.zip`/`.tar.gz` you downloaded. The plugin declares how it signs in — a device code means opening the page it names and typing the code, an API key means filling in a form in the app (password fields are not shown in clear). After signing in you can read usage, fetch the model list, and pick a model on the chat screen. The stop button cancels the **request inside Core**, not just the view.

**Which AI provider packages install, up front:** of the community repository's 36 packages, the ones that actually run today are the original Copilot and `cloudflare-workers-ai`; most of the rest need Node built-ins and are refused with the reason named.

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

## On a machine without Xcode

`scripts/check-swift.sh` only parses, so any machine can run it: `python3 scripts/check-swift.py` (no Xcode needed; it catches unclosed strings and brackets).

The Core surface can be checked here too: `scripts/check-surface-offline.sh` generates Core's ObjC header with gobind and runs the same selector list the Mac uses, in about ten seconds. It reads the **header**, not memory — a selector typed wrongly in the list used to surface only after a transfer.

The client repository is not public, so Swift sources still have to travel to a second Mac; Core does not — it is public on GitHub, and `git clone` plus `scripts/mac-verify.sh` rebuilds it there. For the Swift sources, base64 segments with a checksum per segment remain more reliable than resending the archive (these tools stay for machines without network):

```sh
scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]
```

It checks every segment's md5, joins and decodes, checks the archive's md5 and byte count, unpacks, counts `.swift` files, drops the xcframework in and runs `swift build`, printing one `PASS`/`FAIL` line per step. A trailing `clean` removes the unpacked tree, the joined file and the archive after reporting, leaving the machine as found. It uses `md5` rather than `shasum` because `md5` needs no extra permission on a locked-down machine.

`scripts/make-bundle.sh OUTDIR [CHUNK]` produces the segmented bundle: every `.swift` under `Package.swift`, `Sources/`, `App/` and `Tests/` is added in sorted path order with mtime and ownership zeroed, packed into a ~47 KB archive, then split into base64 segments of `CHUNK` characters (default 1650), printing the archive md5 plus each segment's md5 and tail. The same tree always yields byte-identical output, so the checksums can be compared out of band.

A change to a few files does not need the whole bundle again: `scripts/make-delta.sh SINCE OUTDIR [CHUNK]` takes the `.swift` files that differ from a revision, packs them the same way into `delta.tar.gz`, and extracting it over the old tree updates those files in place. Segments default to 1548 characters, and the archive md5 plus each segment md5 are printed. Checked byte for byte against the hand-written packing command.

## Licence

GPL-3.0-or-later; see [LICENSE](LICENSE).
