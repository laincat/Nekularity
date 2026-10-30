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
| Error text | Core reports in English and the interface is Chinese: `CoreError.readable` turns the usual failures (cancel, missing source, not installed, timeout, human verification, no permission) into Chinese sentences, and prefixes anything else with "源返回错误:" while keeping Core's original words, so a reader never sees a bare English sentence and a bug report still has the detail |
| Core wrapper | `CoreClient`: async/await API that passes task cancellation to Core; `CoreHost`: implements every host interface Core needs; search calls `search.load` with the defaults Core reports for each filter group |
| JSON | A small `JSONValue` parser and `OrderedJSONDecoder` that keep key order and number text |
| Networking | `URLSessionTransport`: cookies isolated per source, including cookies set on redirect hops |
| Cookies | `CookieJars`: host-only and domain cookies, paths, Secure, expiry; persistent cookies saved to a file |
| Human verification | `VerificationSession`: a WKWebView loads the challenge, passes by Core's done rule, and hands back cookies and the User-Agent |
| Storage | `SourceStore`: source data, settings and plugin records kept as written; logged in follows the official rule (an `account` value exists) |
| Images | `ImageLoader`: requests through each source's `onImageLoad`/`onThumbnailLoad`, downsampled and cached |
| Screens | Sources (indexes, install from URL, update, enable, delete), search (recent keywords can be tapped again, removed one by one or cleared; scope is "current source" or "every source", and the merged mode takes each source's first page, at most three at a time, merges them in install order and labels each card, switching the picker when you open another source's comic), details (grouped chapters, with the chapter reading stopped on marked "读到"), reader (one of two layouts — a vertical strip or one page per screen, the paged one with a left-to-right or right-to-left direction — previous/next chapter, and it writes the current page and percentage back to the shelf, reopening the same chapter at the page it stopped on, and an optional auto-continue that is off by default, only fires once the end of the chapter has really been scrolled to, and only appears in the vertical layout: paged mode is a `TabView`, which builds its neighbours ahead, so there is no trustworthy "nearly at the end" signal and guessing would be worse than hiding it), source-driven toasts, dialogs, input, choices and loading |
| Source settings | `CoreClient.settings(key:)` reads Core's `settings` declaration; a source's detail screen opens a settings screen that draws each by type (picker, toggle, text field) and stores the value as `JSONValue` in that source's store, so numbers and booleans survive; an input's `validator` runs as a regular expression, and a callback is shown as an in-source action |
| Shelf | `ShelfStore` keeps reading history (one row per comic with its chapter, page and percentage) and favourite folders; opening a chapter records it, and the shelf screen can continue, forget, move between folders and create/rename/delete folders; `shelf.json` has the same shape as the desktop client's |
| Search history | `SearchHistoryStore` keeps the last 30 keywords, newest first, with case-insensitive repeats collapsed, and can merge a backup's `searchHistory`; `searches.json` matches the desktop client |
| Kept pictures | `ShelfStore.pictures`: the reader's "收藏本页" stores the page under the source, comic, chapter, page number and image address, one row per address, newest first, with a thumbnail, a tap that opens the comic, and a swipe to remove. Keys match the desktop `shelf.json` (`comicId`, `chapterId`) and an empty list is left out; a backup restore turns the official `episodes[].imageFavorites[]` into these rows |
| Backup contract | Running Core's `Plan` over the three real `.venera` files pinned every field: history is `{sourceKey,id,type,title,subtitle,time(ms),ep,page,readEpisode[],maxPage,chapterGroup}`; folders are `{name,order,items[]}` and an item's `time` is a string; a kept picture is `{id,sourceKey,title,author,time,maxPage,episodes[{eid,ep,epName,imageFavorites[{page,imageKey,eid,ep}]}],other}`; a source is `{key,script?,data?}`; `pending` and `settings` also appear. `BackupPicture` now matches that shape (pages nested under `episodes[].imageFavorites[]`), so a restore really writes kept pages |
| Backup import | goes through Core's `planBackup` (Core unwinds the archive, reads the sqlite tables and resolves type hashes); `BackupImporter` installs the listed sources, merges history and favourite folders, and merges search history. Device settings and cookies are not applied over this device, and kept pages are written to the picture shelf; the result reports new rows, rows already there, and rows skipped. |
| Browsing | `CoreClient.explorePages` and `explore` cover the four browse kinds (single page with parts, multi-page list, mixed, multi-part page); `BrowseView` switches between browses with chips, pins section headers, pages, and refreshes by pulling |

## Not verified

- **Compilation**: `scripts/verify-ios.sh` runs the checks in order on macOS (docs, `check-swift`, `swift test`, the app build). Without XcodeGen it falls back to building the Kit for iOS and type checking the screens with `swiftc -typecheck`, which still catches mistakes in the screens. The code has not been run on a device or a simulator yet, but it does compile on macOS: the Kit builds with `swift build` in Swift 6 mode and `swiftc -emit-module` produces the iOS module. The App type check first hit a type-check timeout in `ShelfView`, which also hid a real mistake (`folderNames` used as a property); splitting that into `@ViewBuilder` helpers then exposed an unwrapped optional (`chapterID` in `ReaderView`). Both are fixed, and the whole tree now passes on macOS in Swift 6 mode: Kit `swift build` 0 errors 0 warnings, Kit `-typecheck` 0/0, the iOS `-emit-module` succeeds, and the App `-typecheck` reports 0 errors 0 warnings. Every change still goes through `scripts/check-swift.sh` (a tree-sitter parse: it catches syntax errors, not type errors). It calls Core the same way as the Core repository's `apple/CoreSmoke`, which passes on CI; `BrowseView` passed the same type check. When the sources travel to a Mac as base64 segments, `scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]` does the whole check in one command: join the segments, decode, check the archive size and md5, unpack, count the `.swift` files, copy the xcframework, `swift build` on macOS, `swift test` for the Kit's unit tests, `swiftc -emit-module` the Kit for iOS, then `swiftc -typecheck` the App against that module — all three in `-swift-version 6`, matching `Package.swift` and `project.yml`, because a Swift 5 type check accepts code the real build rejects; a trailing `clean` removes the unpacked tree, the joined file and the archive after reporting, leaving the machine as found.
- `swift test` now runs on macOS: **58 tests in 11 suites pass**. It earned its place in the five checks by failing first: `BackupImporter.keptPages(from:)` sat on a `@MainActor` type, so a nonisolated test could not call it; making it `nonisolated` (it only reads the plan and returns values) let the target compile, which then exposed `SearchHistoryStore.merge` inserting imported queries reversed and ahead of the local ones (it appends in order now). Both are fixed. Later additions tightened the net: `ReaderNavigationTests`, which exist because the movement rules moved out of the view into the Kit, and the shelf's two destructive operations (forgetting a history entry, forgetting a kept page).
- Running on a device, with real comic sources.

## Next

1. The compile and test stage is settled: on macOS, in Swift 6 mode, the tree passes all five checks — `swift build`, `swift test` (49), `-typecheck`, the iOS `-emit-module`, and the App `-typecheck` in two consecutive rounds, including the multi-source search and kept-page chapter jump. Later changes keep going through the same loop, so no package piles up unseen by a compiler.
2. Launch the app once a simulator runtime is available, and run the main path with a real source (install, search, details, read, shelf).
3. Backup import is wired and was checked against the real `.venera` field shapes; the next step is running it once on a simulator and checking the counts.
4. Two items wait on product decisions: video sources and playback; mapping an old global cookie jar onto per-source partitions.
5. Two items need system-level approval: installing an iOS simulator runtime, and installing XcodeGen on the Mac to produce an `.xcodeproj`.
6. AI comes after the reading path: on iOS the plan is the **Magpie plugin system** — running
   Magpie's original provider packages, with accounts and runtime separate from comic sources.
   Desktop does no AI work.

## Magpie provider plugins (the Nekularity side)

Core already does the hard part: package snapshot and module resolution, a `fetch` /
`Headers` / `URL` / `ReadableStream` runtime, device-code sign-in, refresh write-back,
usage and model lists, streamed chunks, one event model over three wire dialects, and
"never retry once output started". All of that is covered by Go tests, including the
original Copilot package against a fake service.

This repository has only the client layer so far. On 2026-10-30 it was actually compiled on
macOS 27 / Xcode 27 / Swift 6.4 and passed all five checks:

```
① Kit swift build                     PASS  0 error 0 warning
② Kit swift test                      PASS  65 tests / 13 suites (was 58 / 11; +7 and +2)
③ Kit -typecheck -swift-version 6     PASS  0 error 0 warning
④ iOS Kit -emit-module                PASS
⑤ App -typecheck -swift-version 6     PASS
swift test --filter Magpie            7 tests / 2 suites, all executed
```

The first real compile of this layer produced no error and no warning. The file counts matched
too: Sources 16→18, Tests 9→10, total 36→38.

| Part | What it does |
|---|---|
| `MagpieAuthStore` | Keeps each provider's sign-in separately, as the **original JSON text**, not a parsed dictionary: the package writes and reads it back itself, and re-encoding reorders keys and turns `9007199254740993` into a float. `MemoryMagpieAuthStore` is for tests; `KeychainMagpieAuthStore` uses `kSecClassGenericPassword` per provider with `AfterFirstUnlock` — a refresh may run while the phone is locked, and a sign-in that cannot be read then is a package that quietly stops working |
| `CoreMagpie` | The real bridge: implements `MagpieRunner.Core` and hands JSON to the generated `MobileMagpie`. The signatures are transcribed, not guessed — `gobind -lang=objc` produced `- (BOOL)loadPackage:(NSString*)filesJSON error:(NSError**)`, `- (NSString*)call:(NSString*)export argJSON:(NSString*)error:`, `savedAuth:`, `setAuth:authJSON:`, `close` and `MobileNewMagpie(id<MobileHost>)`. Its tests drive a small offline package through the real Go runtime, so no 21-method host stub is needed |
| `MagpieSignIn` | One sign-in's wait and its cancellation: `start` reports the page and code, `waitForResult` waits on the package's callback (the package polls itself), and cancelling stops both the wait and the callback still polling the vendor. A success is stored in **Magpie's own shape** — `{type:"oauth",refresh}` or `{type:"api",key}` — rather than the package's answer verbatim |
| `MagpieAccounts` | The provider list and its runners: `install(folder:)` never asks the user for a provider id — the plugin reports `auth.provider` and the folder name is only a provisional key. Core compiles the package before anything is stored, so a refused package leaves no half-installed row. Runners are cached per provider (loading compiles the package, and rebuilding on every tap would make the list feel broken) and closed on removal or sign-out |
| `MagpieModel` | The models the vendor lists — id, display name, context and output limits, modalities. The chat screen offers them first; when a vendor lists nothing the field falls back to typing a name and says why, rather than an empty menu that reads as "this provider has no models" |
| `MagpieUsage` | The normalised usage shape from Core. **No share means no bar** — the vendor's own words are shown instead ("No allowance reported"), because drawing 0% would tell the user there is plenty left when the truth is that this vendor does not say. With a share it draws one and keeps an overspend past 100% |
| `MagpieUsageView` | The usage screen: plan, account, each window, reset time, pull to refresh; a wallet window shows its figure rather than a ratio |
| `MagpieChat` | A reader for one turn: Core only answers when asked (gomobile cannot push), so this wraps it in an `AsyncThrowingStream` a view can `for try await`. Leaving the screen or stopping cancels **the request in Core**, instead of leaving it running against the vendor. Events carry text, reasoning, done (with the token counts as written) and errors |
| `MagpieChatView` | The conversation screen: model name, input, the reply as it arrives, and a stop button. Deliberately only a reply reader — **no tool calls and no multi-turn agent loop**, since writing one would imply those exist |
| `MagpieProvidersView` | The "AI providers" tab: installed packages with their versions and sign-in state, buttons to sign in, sign out, remove, and install from a folder. Entirely separate from comic sources: different packages, different accounts, different cookies |
| `MagpiePackageReader` | Reads a package from a folder the user picks: files keyed by package-relative path, symlinks refused (a package is plain files), and 8 MiB per file, 32 MiB total, 1024 files — the same limits Core enforces, checked here first so a stray video is refused instead of copied. No `package.json` means "not a plugin"; a manifest that names no entry (`exports["./server"]`, `main`, `index.*`) does not count either, which is Magpie's own rule |
| `MagpiePackageStore` | Installed packages, one per provider: files kept as **original base64** in one JSON document, with the package's own `name`/`version` for the list. Installing again replaces the old copy instead of stacking; anything without a `package.json` is refused outright, since such a package only fails later, at load time, with a vaguer reason. The index is written to a temporary file and moved into place: a crash mid-write must not make the whole list — and with it every installed package — unreadable. Unpacking is not here: this takes an already unpacked file table, which Core validates again |
| `MagpieSignInView` | The SwiftUI screen: the methods the plugin declares, the code (copyable), opening the page, waiting, cancelling. It uses that vendor's own authorization on this device, never a comic source's, and shares no cookie jar with one |
| `MagpieRunner` | Installs a package (path to bytes, base64 to Core), hands over the stored sign-in, runs an export, **stores whatever the package saved afterwards** (otherwise a refresh is lost and the next launch is signed out), and on sign-out closes the instance and deletes the entry. Installation takes an already unpacked file table: unpacking belongs to Core, and this layer trusts no path Core did not validate |

`MagpieRunner.Core` is a protocol rather than the generated `MobileMagpie` directly, so the
orchestration is testable against `StubMagpieCore` without an xcframework. Seven new cases
cover the base64 round trip, no sign-in sent when none is stored, refresh write-back, an empty
write-back not overwriting, sign-out, a failed install, and exact number text surviving.

Still missing: the real `MobileMagpie` adapter (written once the bindings are generated on the
Mac — signatures are not guessed), the package installation screen (zip), the device-code
sign-in screen with cancellation, and model selection with streaming display.
7. One item needs a decision: App Transport Security. Many comic sources serve images over `http://`, and ATS refuses cleartext by default. The desktop client gets away with it because Go's `net/http` does not apply ATS; the app either allows arbitrary loads (cleartext everywhere) or carves out exceptions per host — a security trade-off, so it is not decided here.
