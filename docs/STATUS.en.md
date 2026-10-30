# Nekularity status

English | [简体中文](STATUS.md)

Updated 2026-10-30.

## Host signatures cross-checked

All 21 `CoreHost` methods were compared against the Swift host implementation in Core's `apple/CoreSmoke`, which CI really compiles and runs: methods returning an object import as `(params…, error: NSErrorPointer) -> String`, while `void`/`Bool` methods import as `throws`. So `http(_:error:) -> String`, `saveData(_:dataKey:valueJSON:) throws`, `writeClipboard(_:) throws` and `readClipboard(_:) -> String` are the shapes Nekularity already uses. Matching signatures is not compiling, though — the real type check still waits for `swift build` on the Mac.

Every Kit member the UI calls was checked the same way: `library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`, `core.search / searchOptions / explore / explorePages`, `shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`, `searches.add`, `store.loadSetting / saveSetting` all exist with matching parameters.

## What a Mac has already run

On 2026-10-30 one real run happened on macOS 27 / Xcode 27 / Swift 6.4, with no global tools installed:

- Core was built from GitHub into `VeneraCatCore.xcframework` (96M, slices for ios-arm64, the simulator and macOS); `gofmt`, `go vet`, `go test -race` and `gomobile bind` all passed.
- `swiftc -typecheck -swift-version 6` over the 13 files in `Sources/NekularityKit` produced exactly one error: `JSONValue.swift` had an `array` accessor on `OrderedObject` copied over from the enum (`case .array(let a) = self` cannot match a struct). That accessor is gone; the other twelve files, the Core import, Swift 6 language mode and concurrency isolation reported nothing.
- The ten files in `App/` were checked afterwards: `-emit-module` for `NekularityKit` under the iPhoneOS 27.1 SDK (0 errors), then `swiftc -typecheck` over `App/*.swift` with the same SDK. That produced exactly **one error**: `ForEach(shelf.recentHistory())` in `ShelfView.swift` took the `Identifiable` overload, and `ShelfHistory` does not declare that protocol. The fix is not to declare it — its `id` is only the comic id and carries no source, so two sources can collide — but to give `ShelfHistory` a `key` (`source + "/" + id`) and pass `id: \.key`; the same risk in `ForEach(folder.items)` was fixed the same way.
- So the Kit side is **0 errors, 0 warnings**, while the App side is waiting for one re-run after that single fix.

## Written

| Part | Contents |
|---|---|
| Core wrapper | `CoreClient`: async/await API that passes task cancellation to Core; `CoreHost`: implements every host interface Core needs; search calls `search.load` with the defaults Core reports for each filter group |
| JSON | A small `JSONValue` parser and `OrderedJSONDecoder` that keep key order and number text |
| Networking | `URLSessionTransport`: cookies isolated per source, including cookies set on redirect hops |
| Cookies | `CookieJars`: host-only and domain cookies, paths, Secure, expiry; persistent cookies saved to a file |
| Human verification | `VerificationSession`: a WKWebView loads the challenge, passes by Core's done rule, and hands back cookies and the User-Agent |
| Storage | `SourceStore`: source data, settings and plugin records kept as written; logged in follows the official rule (an `account` value exists) |
| Images | `ImageLoader`: requests through each source's `onImageLoad`/`onThumbnailLoad`, downsampled and cached |
| Screens | Sources (indexes, install from URL, update, enable, delete), search (recent keywords can be tapped again, removed one by one or cleared; scope is "current source" or "every source", and the merged mode takes each source's first page, at most three at a time, merges them in install order and labels each card, switching the picker when you open another source's comic), details (grouped chapters), reader (vertical scroll, previous/next chapter, and it writes the current page and percentage back to the shelf), source-driven toasts, dialogs, input, choices and loading |
| Source settings | `CoreClient.settings(key:)` reads Core's `settings` declaration; a source's detail screen opens a settings screen that draws each by type (picker, toggle, text field) and stores the value as `JSONValue` in that source's store, so numbers and booleans survive; an input's `validator` runs as a regular expression, and a callback is shown as an in-source action |
| Shelf | `ShelfStore` keeps reading history (one row per comic with its chapter, page and percentage) and favourite folders; opening a chapter records it, and the shelf screen can continue, forget, move between folders and create/rename/delete folders; `shelf.json` has the same shape as the desktop client's |
| Search history | `SearchHistoryStore` keeps the last 30 keywords, newest first, with case-insensitive repeats collapsed, and can merge a backup's `searchHistory`; `searches.json` matches the desktop client |
| Kept pictures | `ShelfStore.pictures`: the reader's "收藏本页" stores the page under the source, comic, chapter, page number and image address, one row per address, newest first, with a thumbnail, a tap that opens the comic, and a swipe to remove. Keys match the desktop `shelf.json` (`comicId`, `chapterId`) and an empty list is left out; a backup restore turns the official `episodes[].imageFavorites[]` into these rows |
| Backup contract | Running Core's `Plan` over the three real `.venera` files pinned every field: history is `{sourceKey,id,type,title,subtitle,time(ms),ep,page,readEpisode[],maxPage,chapterGroup}`; folders are `{name,order,items[]}` and an item's `time` is a string; a kept picture is `{id,sourceKey,title,author,time,maxPage,episodes[{eid,ep,epName,imageFavorites[{page,imageKey,eid,ep}]}],other}`; a source is `{key,script?,data?}`; `pending` and `settings` also appear. `BackupPicture` now matches that shape (pages nested under `episodes[].imageFavorites[]`), so a restore really writes kept pages |
| Backup import | goes through Core's `planBackup` (Core unwinds the archive, reads the sqlite tables and resolves type hashes); `BackupImporter` installs the listed sources, merges history and favourite folders, and merges search history. Device settings and cookies are not applied over this device, and kept pages are written to the picture shelf; the result reports new rows, rows already there, and rows skipped. |
| Browsing | `CoreClient.explorePages` and `explore` cover the four browse kinds (single page with parts, multi-page list, mixed, multi-part page); `BrowseView` switches between browses with chips, pins section headers, pages, and refreshes by pulling |

## Not verified

- **Compilation**: `scripts/verify-ios.sh` runs the checks in order on macOS (docs, `check-swift`, `swift test`, the app build). Without XcodeGen it falls back to building the Kit for iOS and type checking the screens with `swiftc -typecheck`, which still catches mistakes in the screens. The code has not been run on a device or a simulator yet, but it does compile on macOS: the Kit builds with `swift build` in Swift 6 mode and `swiftc -emit-module` produces the iOS module. The App type check first hit a type-check timeout in `ShelfView`, which also hid a real mistake (`folderNames` used as a property); splitting that into `@ViewBuilder` helpers then exposed an unwrapped optional (`chapterID` in `ReaderView`). Both are fixed, and the whole tree now passes on macOS in Swift 6 mode: Kit `swift build` 0 errors 0 warnings, Kit `-typecheck` 0/0, the iOS `-emit-module` succeeds, and the App `-typecheck` reports 0 errors 0 warnings. Every change still goes through `scripts/check-swift.sh` (a tree-sitter parse: it catches syntax errors, not type errors). It calls Core the same way as the Core repository's `apple/CoreSmoke`, which passes on CI; `BrowseView` passed the same type check. When the sources travel to a Mac as base64 segments, `scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]` does the whole check in one command: join the segments, decode, check the archive size and md5, unpack, count the `.swift` files, copy the xcframework, `swift build` on macOS, `swiftc -emit-module` the Kit for iOS, then `swiftc -typecheck` the App against that module — all three in `-swift-version 6`, matching `Package.swift` and `project.yml`, because a Swift 5 type check accepts code the real build rejects; a trailing `clean` removes the unpacked tree, the joined file and the archive after reporting, leaving the machine as found.
- The unit tests in `swift test` (JSON, cookies, storage) have not run either.
- Running on a device, with real comic sources.

## Next

1. Close out the App-level check: this round fixes the optional unwrap in `ReaderView` (a single-chapter comic has no `chapterID`), then reruns `swiftc -typecheck -swift-version 6`; four checks green finishes the compile stage.
2. Launch the app once a simulator runtime is available, and run the main path with a real source (install, search, details, read, shelf).
3. Backup import is wired and was checked against the real `.venera` field shapes; the next step is running it once on a simulator and checking the counts.
4. Two items wait on product decisions: video sources and playback; mapping an old global cookie jar onto per-source partitions.
5. Two items need system-level approval: installing an iOS simulator runtime, and installing XcodeGen on the Mac to produce an `.xcodeproj`.
6. One item needs a decision: App Transport Security. Many comic sources serve images over `http://`, and ATS refuses cleartext by default. The desktop client gets away with it because Go's `net/http` does not apply ATS; the app either allows arbitrary loads (cleartext everywhere) or carves out exceptions per host — a security trade-off, so it is not decided here.
