# Nekularity status

English | [简体中文](STATUS.md)

Updated 2026-10-31.

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
| Screens | Sources (indexes, install from URL, update, enable, delete), search (recent keywords can be tapped again, removed one by one or cleared; scope is "current source" or "every source", and the merged mode takes each source's first page, at most three at a time, merges them in install order and labels each card, switching the picker when you open another source's comic; under a single source a filter row shows the groups the source declares and searching again after a change, while a merged search still uses each source's defaults; every search carries a generation number so a late answer from an older search cannot write into the screen of a newer one), details (grouped chapters, with the chapter reading stopped on marked "读到"), reader (one of two layouts — a vertical strip or one page per screen, the paged one with a left-to-right or right-to-left direction — previous/next chapter, and it writes the current page and percentage back to the shelf, reopening the same chapter at the page it stopped on, and an optional auto-continue that is off by default, only fires once the end of the chapter has really been scrolled to, and only appears in the vertical layout: paged mode is a `TabView`, which builds its neighbours ahead, so there is no trustworthy "nearly at the end" signal and guessing would be worse than hiding it), source-driven toasts, dialogs, input, choices and loading |
| Source settings | `CoreClient.settings(key:)` reads Core's `settings` declaration; a source's detail screen opens a settings screen that draws each by type (picker, toggle, text field) and stores the value as `JSONValue` in that source's store, so numbers and booleans survive; an input's `validator` runs as a regular expression, and a callback is shown as an in-source action |
| Shelf | `ShelfStore` keeps reading history (one row per comic with its chapter, page and percentage) and favourite folders; opening a chapter records it, and the shelf screen can continue, forget, move between folders and create/rename/delete folders; `shelf.json` has the same shape as the desktop client's |
| Standard AI screen | "AI 供应商" opens "标准接口": choose OpenAI Chat/Responses or Anthropic Messages, set a custom API root, model and token limit; the key goes to the Keychain per vendor and does not travel in a backup; the screen lists the model catalog and sends one conversation. A reply arrives **whole**, and the screen says "流式尚未接通" instead of pretending otherwise. Core provides `BuildAIRequest`/`BuildAIModelsRequest`/`SendAIRequest`, entirely separate from Magpie packages |
| Search history | `SearchHistoryStore` keeps the last 30 keywords, newest first, with case-insensitive repeats collapsed, and can merge a backup's `searchHistory`; `searches.json` matches the desktop client |
| Kept pictures | `ShelfStore.pictures`: the reader's "收藏本页" stores the page under the source, comic, chapter, page number and image address, one row per address, newest first, with a thumbnail, a tap that opens the comic, and a swipe to remove. Keys match the desktop `shelf.json` (`comicId`, `chapterId`) and an empty list is left out; a backup restore turns the official `episodes[].imageFavorites[]` into these rows |
| Backup contract | Running Core's `Plan` over the three real `.venera` files pinned every field: history is `{sourceKey,id,type,title,subtitle,time(ms),ep,page,readEpisode[],maxPage,chapterGroup}`; folders are `{name,order,items[]}` and an item's `time` is a string; a kept picture is `{id,sourceKey,title,author,time,maxPage,episodes[{eid,ep,epName,imageFavorites[{page,imageKey,eid,ep}]}],other}`; a source is `{key,script?,data?}`; `pending` and `settings` also appear. `BackupPicture` now matches that shape (pages nested under `episodes[].imageFavorites[]`), so a restore really writes kept pages |
| Backup import | goes through Core's `planBackup` (Core unwinds the archive, reads the sqlite tables and resolves type hashes); `BackupImporter` installs the listed sources, merges history and favourite folders, and merges search history. Device settings and cookies are not applied over this device, and kept pages are written to the picture shelf; the result reports new rows, rows already there, and rows skipped. |
| Patch making | `scripts/make-patch.sh BASE OUT FILE...` diffs the copy the other machine holds against this one, then applies that patch to a scratch copy here and compares md5 per file. Describing "delete these lines, keep one blank line" in prose did not converge twice; a patch proven to reproduce the bytes does not need a third round |
| Transfer manifest | `scripts/make-payload.sh OUTDIR FILE...` prints the archive size and md5, the md5 of each file after unpacking, and the per-segment md5s — one block to paste. It exists because a message once paired a correct archive md5 with the md5 of an older copy of a file, so the receiver would have rejected good data for the wrong reason. **One rule added 2026-11-01**: the script now reads the bytes with `git cat-file blob` instead of copying the working tree. On Windows `core.autocrlf=true` makes the working tree CRLF while the object is LF (the repository says `* text=auto eol=lf`), so a plain `cp` sent CRLF to the receiver: the md5 never matched what was computed from the repository, and the CRLF `scripts/check-core-surface.sh` would not even run on the Mac (`set: -: invalid option`). That wasted one transfer round, so the fix lives in the script rather than in someone's memory |
| Surface without a Mac | `scripts/check-surface-offline.sh` generates the ObjC header with gobind on Windows and runs the same selector list the Mac check uses: 9.7 seconds, 18/18. That check used to be possible only after an xcframework existed, by which point a mismatch had already cost a transfer. It also settled the list itself: a no-argument method generates `auth:`, `models:` and `savedAuth:`, not `…WithError:` |
| Static check (test doubles) | `check-swift.py` checks that `Tests/` doubles conforming to `MagpieRunner.Core` have every method. When the protocol gains one, the gap is silent on Windows and a `swift test` compile error on the Mac — a whole validation round. Verified against a copy with the stub removed: it reports `RefusingCore lacks readPackageArchive` |
| Browsing | `CoreClient.explorePages` and `explore` cover the four browse kinds (single page with parts, multi-page list, mixed, multi-part page); `BrowseView` switches between browses with chips, pins section headers, pages, and refreshes by pulling |

## Not verified

**This change has been through a real Xcode build** (2026-10-31, the same Mac): XcodeGen came from the release page binary (2.46.0, in `/tmp/xcg`, **no Homebrew and not on the system PATH**), `xcodegen generate` → `xcodebuild -scheme Nekularity build` reported `BUILD SUCCEEDED`, and the built `Nekularity.app/Info.plist` carries `NSAllowsArbitraryLoads = true`; `-showBuildSettings` echoes `INFOPLIST_FILE = App/Info.plist` and `GENERATE_INFOPLIST_FILE = NO`, with zero `Copy Bundle Resources` complaints, so `excludes: [Info.plist]` works. `scripts/verify-ats.sh` runs this chain and is part of `verify-ios.sh`, so every whole-tree run now really builds the app instead of falling back to type checking.
- **A real iPhone**: nothing has run on one. **The simulator does run** (2026-11-01, first time): it installs, launches, draws its interface, does not crash, reports zero Core framework load failures, and reaches the interface in about 0.7 s — see "Running on a simulator for the first time" above. That was an empty container, though, so the main path (install a source, search, details, read, shelf) has not been walked on a device yet.
- **Signing and archiving**: `xcodebuild -scheme Nekularity` uses generic/platform=iOS and does not sign; `** BUILD SUCCEEDED **` proves it compiles, not that it installs. XcodeGen is absent, so there is no `.xcodeproj` and no app bundle either.
- **A real vendor account**: Magpie's sign-in, model list, usage, streaming and cancellation have only been exercised against local fake services and canned answers; no real vendor account has completed authorization on a device.
- **Real comic sources**: the desktop's `TestLiveSource` covers these outside the repository (see Nekophage); the iOS side has no equivalent.

## Next

1. The compile and test stage is settled: on macOS, in Swift 6 mode, the tree passes all five checks — `swift build`, `swift test` (49), `-typecheck`, the iOS `-emit-module`, and the App `-typecheck` in two consecutive rounds, including the multi-source search and kept-page chapter jump. Later changes keep going through the same loop, so no package piles up unseen by a compiler.
2. Run the main path with a real source on the simulator that is now available (install, search, details, read, shelf). Launching is already proven; this step is about actually using it.
3. Backup import is wired and was checked against the real `.venera` field shapes; the next step is running it once on a simulator and checking the counts.
4. Video sources and playback still wait on a product decision; the old global cookie jar is now restored into per-source partitions (see the cookie section on this page).
5. ~~Installing an iOS simulator runtime~~ **done** (2026-11-01): two iOS 27.2 runtimes, 12 devices available, and the App installed and launched on an iPhone 18 Pro simulator.
6. AI comes after the reading path: on iOS the plan is the **Magpie plugin system** — running
   Magpie's original provider packages, with accounts and runtime separate from comic sources.
   Desktop does no AI work.

## Magpie provider plugins (the Nekularity side)

**What installs, stated first.** Of the community repository's 36 packages, only two provider
plugins actually run on this system today: the original `@magpie-community/opencode-copilot-auth`
0.1.0 and `cloudflare-workers-ai` 0.0.4. Most of the rest need `node:fs`/`node:crypto`/
`child_process`, or ship a TypeScript entry, and are refused at load with the reason named —
not a blank screen, and not "installed but useless". So "Magpie compatible" here means the
package format and runtime contract are compatible, not that every community package installs.

Core already does the hard part: package snapshot and module resolution, a `fetch` /
`Headers` / `URL` / `ReadableStream` runtime, device-code sign-in, refresh write-back,
usage and model lists, streamed chunks, one event model over three wire dialects, and
"never retry once output started". All of that is covered by Go tests, including the
original Copilot package against a fake service.

This repository has only the client layer so far. **The 2026-10-31 run passes in full**, on
macOS 27 / Xcode 27 / Swift 6.4:

| Check | Result |
|---|---|
| `scripts/check-core-surface.sh` | PASS — all 18 `MobileMagpie` methods |
| `swift build` | PASS, 0 errors, 0 warnings |
| `swift test` | **PASS — 119 tests / 27 suites** |
| Kit `-typecheck -swift-version 6` (arm64-macos26.0) | PASS, 0 errors, 0 warnings |
| iOS `-emit-module -parse-as-library -swift-version 6` (iPhoneOS 27.1) | PASS |
| App `-typecheck -swift-version 6` | PASS |
| `swift test --filter Magpie` | **PASS — 61 tests / 16 suites** |

Static counts agree with the run: `@Test` 119, `@Suite` 27, `.swift` 56 (28 Kit, 14 App, 11 Tests
and `Package.swift`).

**Code added after that run has now been verified too**: on 2026-10-31 the same five checks ran on the
Mac mini (macOS 27.0.1 / Xcode 27.1 / Swift 6.4) and every one exited 0: `swift build` with 0 errors and
0 warnings, `swift test` **129 tests in 27 suites passed**, Kit and App `-typecheck` clean, iOS
`-emit-module` clean; `check-core-surface` 18/18; `swift test --filter Magpie` **71 tests in 16 suites**;
and `check-tree` printed `swift=56 tests=129 suites=27 shape=8457d8e43ce3d36849577f4cdcc07a92079b4015`,
the same shape this repository prints. **Still unverified**: an `xcodebuild` archive and signing, an iOS
Simulator runtime (absent on that machine), a real device and a real vendor account.
**The whole-tree runner now completes in one command**: `scripts/verify-ios.sh` on macOS ends with `EXIT=0`, in this order — surface, Core pin, docs, syntax, `swift test`, `xcodebuild` (iOS, unsigned) and App `-typecheck`. The syntax line reads `SKIP`, not `FAIL`: no tree-sitter (exit 2) or a grammar version that will not load (exit 3) both mean "this machine cannot run it", while a developer running `scripts/check-swift.sh` still fails hard. Both exit paths were exercised on the Mac. That run: `swift test` 130 tests in 27 suites, App type-check with 0 errors and 0 warnings (the tree has since grown to 134).

**Two known-harmless build messages** (for later comparison, not regressions): `xcodebuild` always prints `warning: Metadata extraction skipped, no AppIntents.framework dependency found`, and one line beginning with `error:` is actually the CoreSimulator version notice (`iOSSimulator: CoreSimulator is out of date … Simulator device support disabled`) — not a compile error, since `** BUILD SUCCEEDED **` is still printed. `swift test` reports 0 warnings. A `warning:` outside these two is a new problem and should be pinned down.

**Latest whole-tree run (2026-11-01, same Mac mini, including the search generations and the pin move)** — *note: these are that machine's tree numbers; this repository reports 182/34 for the same state, and the entry below explains why*: 70 Swift files, **196 tests in 35 suites**, `shape=e18d20cb0465bbbaa651d9634b1d0a8a31dde9db`. `sh scripts/fetch-core.sh` built Core `6e07429` from GitHub (`gofmt` / `go vet` / `go test` all pass, 22 packages), then bound the framework and checked every file's SHA256 (23 files, 0 mismatches); `check-core-surface.sh` reports **19 Magpie methods + 3 standard AI methods**, and the new framework shows `streamOpen:` / `streamNext:` / `streamClose:` and `MobileNewMagpieWithStream`; `check-core-pin` **ok (6e0742996007)**; `PATH=/tmp/xcg/xcodegen/bin:$PATH sh scripts/verify-ios.sh` **EXIT=0**; `swift test` **196 tests / 35 suites, 0 warnings**; `xcodebuild generic/platform=iOS` **BUILD SUCCEEDED, 0 errors** (one pre-existing AppIntents notice; the product is newer than the framework, so it used the new one); `check-partitions` / `check-docs` / `verify-ats` all pass. **Negative check**: putting `469edfcb48ec…` back into `scripts/core-version` makes `check-core-pin.sh` exit 1 and name the mismatch; putting it back to `6e07429` makes it exit 0.

This run also produced the **first evidence of a simulator runtime**: two iOS 27.2 runtimes, 12 devices available (including a booted `iPhone 18 Pro`), and `xcodebuild -showsdks` listing iOS SDK 27.2.

### What the chunked transport actually does (2026-11-01)

The iOS `URLSessionTransport.sendStreaming` reuses the same request path as `send` (same cookies, cancellation, size limit and redirect policy) and only hands the body over **as it arrives**. `CoreStreamHost` implements Core's `MobileHostStream` protocol and passes it along.

**One measured constraint worth knowing**: **Foundation merges adjacent `URLProtocol` pieces smaller than about 256 bytes** before the delegate sees them. Measured on the Mac:

```text
16 B × 3   → 1 chunk
64 B × 3   → 1 chunk
256 B × 3  → 2 chunks
1024 B × 3 → 3 chunks
8192 B × 3 → 3 chunks, first at 5 ms, middle at 315 ms, last at 618 ms
```

So a test double that wants to prove "pieces arrive one at a time" must use pieces of 1024 bytes or more; smaller ones measure Foundation's merging, not our streaming. The real-server timestamps (5 ms / 315 ms / 618 ms) are the actual evidence that the body is handed over as it arrives.

**Names come from the generated Objective-C header, not from guessing**: the second parameter of `MobileNewMagpieWithStream(_ host:, _ stream:)` has **no label**, because the Objective-C prototype gives it no name. I wrote `stream:` first and only changed it after the Mac reported `extraneous argument label 'stream:' in call`.

### Open: the local tree and the verified tree do not match (found 2026-11-01)

The same `scripts/check-tree.sh` reports different numbers on the two machines:

| State | The verifying Mac's tree | This repository |
|---|---|---|
| Standard API plus search generations, before the chunked transport | `swift=70  tests=196  suites=35` `shape=e18d20cb…` | `swift=69  tests=182  suites=34` `shape=4c01f2bb…` (commit `0ae0579`) |

**Same suite count, ten more tests**, so it is not a whole missing test file but ten extra `@Test` in a file both sides have.

My reading, still to be confirmed: the earlier round of iOS network and lifecycle fixes (URLSession delegate keep-alive, the pre-cancel race, the cross-origin `X-Api-Key` leak, shared-task cancellation in ImageLoader, persisting refreshed credentials, the Magpie signOut runner cache, `MagpieUsage` null tolerance, the sign-in timeout) **landed only in the verification machine's isolated directory and never came back to the repository** — the iOS repository is private, that machine cannot fetch it, and the transfers at the time were piecemeal gists.

**The per-file `@Test` list has been requested.** Once it arrives I will diff it line by line, bring whatever source and tests are missing back into the repository, and send one complete package; until then no more piecemeal patches go on top. **So the 196/35 and 192/34 figures above are the numbers of that machine's tree, not of this repository** — the difference itself is what this entry records.

### Running on a simulator for the first time (2026-11-01)

This is the first evidence that the App installs, launches and shows an interface on a device — not that it compiles:

```text
iPhone 18 Pro (1E57B720-…) already booted; bootstatus -b → rc=0
simulator build rebuilt → BUILD SUCCEEDED (build/verify only had Debug-iphoneos, which cannot be installed on a simulator)
simctl install → rc=0, 1s
simctl launch  → rc=0, PID 78149, 165 ms round trip
screenshot → /tmp/nk/logs/audit-docs/app.png
process alive → UIKitApplication:com.laincat.nekularity
crash check → 272 log lines with no crash/fatal/signal/exception/abort; no Nekularity .ips in DiagnosticReports
Core framework load failures → 0 (grep for VeneraCatCore|dyld|Library not loaded|image not found|Go runtime|MobileNew found nothing)
startup → first line 19:13:52.835 → interface ready 19:13:53.538, about 0.7 s
```

**What the screenshot shows**: the title "搜索", a search field with the placeholder "关键词", an empty-state illustration with "没有可用的漫画源" and "先在“漫画源”里添加并启用一个源。", and five tabs (搜索 / 浏览 / 书架 / 漫画源 / AI 供应商) with 搜索 selected. This is a **fresh container** after the pin change, so an empty source list is expected rather than a load failure — the same log reports zero Core framework load failures.

**The boundary of this evidence**: it shows the App installs, launches, draws its interface, does not crash, and loads the Core framework. Real provider sign-in (Magpie / OpenAI / Anthropic) still has no credentials, live streaming is still not connected, and nothing has run on a real device.

**Measured evidence for the Core deadlock fix**: `go test -race -run 'Reply|Chat' ./magpieplugin/` inside `build/core` passes the six buffer tests and the three chat tests — `TestReplyBufferWriteDoesNotWaitForAReader` is exactly the fixed behaviour: the writer does not wait for the reader.

Earlier run (2026-11-01 morning, superseded by the paragraph above): 68 Swift files, **192 tests in 34 suites**, `shape=e2d55356aabdec360928addd42a3f9e6e7fbcab5`. `swift test` all green (the 11 new standard AI tests all really ran), `xcodebuild -scheme Nekularity` (generic/platform=iOS, unsigned) **BUILD SUCCEEDED** (0 errors, one pre-existing AppIntents notice), `scripts/verify-ios.sh` **EXIT=0**, `scripts/check-core-surface.sh` **19 Magpie methods + 3 standard AI methods** (negative: a header without the three standard AI selectors exits 1), `check-core-pin` `6e0742996007`, `check-partitions`, `check-docs` and `verify-ats` all pass, and `scripts/check-tree.sh` reports the same shape. That run covered the standard API screen (`App/StandardAIView.swift`, `Sources/NekularityKit/AI/`), the three standard AI calls in `CoreClient`, and the three new selectors in `check-core-surface.sh`.

The four changes made on the Mac were compile problems, not behaviour problems: `StandardAISettingsStore` became `@unchecked Sendable` (`UserDefaults` is not itself `Sendable` and Swift 6 refuses to synthesise it, while its documentation guarantees thread safety); two optional pattern matches in `StandardAI.swift` were wrong (`case .object(let x)? = a non-optional`); `Section("协议") { } footer: { }` has no such SwiftUI overload and became `Section { } header: { } footer: { }`; and `#expect(try …)` does not handle `throws` inside the macro, so the test itself became `throws` with `try` moved out. **The words "streaming is not connected yet" are kept unchanged.**

One normalisation happened when the package was landed: nine files arrived with CRLF and were turned into LF. Two pieces of evidence for this: the repository's `.gitattributes` says `* text=auto eol=lf`, so CRLF is rewritten on commit and the md5 drifts at once; and the CRLF `scripts/check-core-surface.sh` does not even run (`set: -: invalid option`, the `
` is read as a flag). Apart from the line endings the files are byte for byte the ones received, checked one by one.

Earlier run (2026-10-31, superseded by the paragraph above): 63 Swift files, **164 tests in 32 suites**, `shape=82fa2813dd9f4a8b397f263c1f7093a0d0294003`; `swift build` with 0 errors and 0 warnings, `swift test` all green, `swift test --filter Magpie` **76 tests in 16 suites**, Kit and App `-typecheck -swift-version 6` both clean, and `xcodebuild -scheme Nekularity` (generic/platform=iOS, unsigned) **BUILD SUCCEEDED**. That run covered `CoreVersion.swift`, the footer `buildLine`, and `theCoreVersionIsShortButIdentifiable`. The one step that could not run is `check-swift.py`: that machine has only the system Python 3.9 and cannot install the `tree-sitter>=0.24` that grammar version 15 needs. It now exits 3 to mean "this machine cannot run the check", and `verify-ios.sh` records that as SKIP rather than FAIL — the steps after it compile with the real Swift compiler.
describes the tree on the Mac; whether the two trees match file for file is settled by md5, not by shape — and
that was done: thirteen Magpie sources plus the test file were compared one by one, ending with
`MagpieAccounts.swift` `3ec891ff…`, `MagpiePackageStore.swift` `c0530a35…` and `MagpieRunnerTests.swift`
`489dcf21…` all identical, with the other eleven already the same.

The framework's macOS deployment target is settled too: Core builds with `gomobile -macosversion=26.0`, matching `Package.swift`'s macOS 26, so the sixteen link-time `was built for newer macOS version` warnings are gone — reproduced with the committed script and no local edits.

The round before this one was compile-green and test-red: the same tree had zero compile
errors while `swift test` found four assertion failures — a `null` modalities array that would
not decode, an install path that did not check the provider a plugin declares (which would
file its sign-in against another account), and a sign-in loop that treated "empty/null" as
waiting in one branch and as failure in another (the root cause being that `JSONSerialization`
rejects a bare top-level `null` by default). Two timeouts followed, for sign-in and for a
reply: anywhere the code can wait for ever, both a test and a user will hit it.

**The verification environment can be rebuilt on demand** (confirmed 2026-10-31): that macOS
machine can `git clone` the public Core repository (`github.com/laincat/VeneraCat-Core`) directly,
has Go 1.27.3, and builds `gomobile` from the tool dependencies in `go.mod` with `go build`, so
nothing global has to be installed. Re-verifying is now a clone plus `scripts/mac-verify.sh`
rather than depending on someone still having a copy.

The edges of that verification, stated rather than glossed over:

- Check ⑤ runs `swiftc -typecheck -swift-version 6` over `App/*.swift` against the module
  emitted from `NekularityKit`, which is the Swift 6 compile check an Xcode project would do.
  A real `xcodebuild` archive and signing were **not** run (and that machine has no iOS
  Simulator runtime; installing one is a system-level action that needs approval).
- The verified tree has no `project.yml`. It is XcodeGen input: it takes part in neither
  `swift build`/`swift test` nor the type checks above.
- `manifest.sh` agrees file by file (68 files that compile or are tested), and so does the
  `check-tree.sh` digest.

The section below is the first round, from 2026-10-30, which was compiled on
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
| `MagpieAccounts` | The provider list and its runners: `install(folder:)` never asks the user for a provider id — the plugin reports `auth.provider`. Core compiles the package before anything is stored, so a refused package leaves no half-installed row. Runners **and the declared spec** are cached per provider: evaluating a package starts a JavaScript runtime, and a ten-provider list should not start ten of them on every refresh (a test pins "three refreshes, one load"). Removal clears both |
 The provider list and its runners: `install(folder:)` never asks the user for a provider id — the plugin reports `auth.provider` and the folder name is only a provisional key. Core compiles the package before anything is stored, so a refused package leaves no half-installed row. Runners are cached per provider (loading compiles the package, and rebuilding on every tap would make the list feel broken) and closed on removal or sign-out |
| File manifest | `scripts/manifest.sh` prints `md5  path` for every source, script and doc; diffing two manifests says **which files differ**. A delta must not be assembled from a commit diffstat — that is how `MagpieRunner.swift` and `MagpieAuthSpec.swift` were missed |
| Tree identity | `scripts/check-tree.sh` prints one line: commit, dirty or not, `.swift` count, `@Test`/`@Suite` counts, and a digest over per-file test counts. Comparing that line between two machines is enough — equal digests mean the same tests live in the same files. Totals alone are not enough: twice now a tree matched on totals and was missing files |
| Delta bundle | `scripts/make-delta.sh SINCE OUTDIR [CHUNK]`; with `DELTA_SKIP_TESTS=1` it leaves `Tests/` out — that file is the largest in the tree, and a few added tests travel cheaper as text |
| Transfer triage | `scripts/split-part.sh PARTS_FILE` splits one base64 segment in two and prints each half with its md5. We have seen an equal-length rewrite: the length and the archive size matched while the content did not. The whole-archive md5 then says *that* it is broken but not *where*; per-segment md5 locates it, and two shorter halves usually survive |
| Core version | `scripts/core-version` pins a commit (`6e0742996007e0246e1c56a14a09546325bb3e96`), not `main`. Pinning to `main` meant the same Nekularity commit could be built against two different Cores on two days — reproducible for the client only, not for what it stands on. Changing Core means changing that line and saying why here. **Every pinned commit is green on Core's CI in all four jobs** (three Go platforms plus Apple's xcframework with two Swift smoke tests). Every whole-tree run builds the framework from scratch with `scripts/fetch-core.sh`. **The four CI jobs of `6e07429` are green** (three Go platforms plus Apple's xcframework with two Swift smoke tests), checked on 2026-11-01: run `41194668348`.

**iOS is wired up too (2026-11-01)**: `ImageRequest` now carries `handle` and `callbacks`, and `ImageLoader` tries at most four addresses per image: a body that is an error page is a failed load when `onLoadFailed` exists, a body with `onResponse` goes through the source before decoding, and a body that will not decode asks for the next mirror too. Each address is re-normalised per partition and re-checked for http(s). Same rules as the desktop client; the difference is that iOS decodes locally with ImageIO while desktop hands the bytes to a WebView. **Not compiled or run on the Mac yet** (three new cases cover the handle parsing, a config without one, and the error-page check).

**Why the pin moved to `69ed1f9` on 2026-11-01**: Core gained support for an image config's callbacks — besides an address and headers, `comic.onImageLoad` may carry `onResponse`, `modifyImage` and `onLoadFailed`, three functions that cannot cross into JSON, so a client only ever received the first four fields. Core now keeps those functions in the source's runtime under a handle, and a host can hand the body to `onResponse` or ask for the next mirror. **iOS has not adopted the three methods yet**, so for iOS this pin moves the protocol without changing behaviour; the desktop client has not either. What it changes is the shape of the problem: sources with encrypted images are no longer "Core cannot do this" but "the client has not wired it up".

**Why the pin moved to `d98e505` on 2026-11-01**: Core fixed two things in how a source's search arguments are read — an option's "`value-text`" form allows an empty left side (`-<none>` means "no value", not that literal string), and a multi-select filter group's value is a JSON array (`SearchOptionGroup.DefaultValues`). Both used to paste `undefined` or `-<none>` into a source's search request. **iOS has adopted both**: a multi-select group now goes out as a JSON array, and the filter menu toggles such a group value by value and shows how many are chosen; a source that declares only `search.loadNext` is paged through its cursor (null to start, the token handed back untouched, an empty token ending it). A source that declares both still pages by number, matching the desktop client — `lanraragi`'s `loadNext` only maps the token back onto a page. The multi-select step was verified on the Mac and merged into `main` (206 tests / 38 suites, iOS `BUILD SUCCEEDED`); the paging rules of the cursor step are a `SearchPaging` value type with five cases, the desktop side has live evidence (`ehentai`: page 1 25 comics, page 2 25 comics, 0 shared), and the iOS side is still being re-checked on the Mac.

**Why the pin moved to `cc63215` on 2026-11-01**: that Core added `Core.NormalizeURL` — a source sometimes writes an image address as `//images.example.com/1.jpg`, with no scheme, and RFC 3986 says such an address inherits the scheme of the page, which for a reader is the one that source last used. The desktop remembers the scheme per partition and the iOS client remembers it in `URLSessionTransport`; both use Core's one rule. **This does not weaken the rules**: `file://`, `javascript:` and `ftp://` are never rewritten, the filled URL still has to be http(s), and a URL that is not scheme-relative is not touched. The selector count goes from 19 + 3 to 19 + 3 + 1 (`normalizeURL:`).

**Why the pin moved to `6e07429` on 2026-11-01**: that Core adds the three standard AI entry points (`BuildAIRequest` / `BuildAIModelsRequest` / `SendAIRequest`) and the optional chunked transport (`HostStream`), and it fixes a deadlock in the package bridge — the package pushed to `__magpieChatPush` from inside its own hook while the reader stopped at the end marker, so the writer waited for a reader that had gone. The new Core adds the `MobileHostStream` protocol and `MobileNewMagpieWithStream`, so the selector count goes from 19 Magpie methods to 19 plus 3 standard AI; `check-core-surface.sh` follows.
| Checker | `scripts/check-core-surface.sh` checks, before a build, that the framework in `Vendor/` really exposes the 18 `MobileMagpie` methods this client calls — the exact trap that bit once (source called `chatStart`, the framework did not have it). It names what is missing and points at `scripts/fetch-core.sh`. The list uses **Objective-C selectors** (`cancelSignIn:`), not Swift's imported `cancelSign(in:)` |
| Checker (Swift) | `scripts/check-swift.py` now also catches one class of "parses here, fails on the Mac": a file naming a generated `Mobile*` type without `import VeneraCatCore`. It was added after the Mac reported exactly that about `CoreMagpie.swift`, which is invisible from Windows |
| Plugin options | `MagpieOptionStore` keeps the user's choices keyed `provider|option` (a small readable file, so a bad value can be seen rather than guessed), and `resolve` joins the plugin's declarations with those choices — **a switch nobody touched keeps the plugin's own default**. The UI writes a change to disk and pushes it to the package at once; changing only the screen would look applied while the next request, the one that reads it, still sees the old value. A missing store is reported instead of silently dropped |
| Checker | `MagpieRunner.setOptions` hands the user's choices to Core, keyed `provider|option`: one table holds every plugin's switches, and a key without the provider would leak across accounts. The switch list in the UI is not written yet |
| `MagpieCheckin` | The check-in button and its answer. The vocabulary is fixed (claimed/done/ineligible/inactive/captcha/failed), so the screen never parses a vendor's sentence; `captcha` sends the user to the vendor's own app because **nothing here solves captchas**, and `done` counts as success rather than failure. Its alert has its own title so a result does not read as an error |
| `MagpieModel` | The models the vendor lists — id, display name, context and output limits, modalities. The chat screen offers them first; when a vendor lists nothing the field falls back to typing a name and says why, rather than an empty menu that reads as "this provider has no models" |
| `MagpieUsage` | The normalised usage shape from Core. **No share means no bar** — the vendor's own words are shown instead ("No allowance reported"), because drawing 0% would tell the user there is plenty left when the truth is that this vendor does not say. With a share it draws one and keeps an overspend past 100% |
| `MagpieUsageView` | The usage screen: plan, account, each window, reset time, pull to refresh; a wallet window shows its figure rather than a ratio |
| `MagpieChat` | A reader for one turn: Core only answers when asked (gomobile cannot push), so this wraps it in an `AsyncThrowingStream` a view can `for try await`. Leaving the screen or stopping cancels **the request in Core**, instead of leaving it running against the vendor. Events carry text, reasoning, done (with the token counts as written) and errors |
| `MagpieChatView` | The conversation screen: model name, input, the reply as it arrives, and a stop button. Deliberately only a reply reader — **no tool calls and no multi-turn agent loop**, since writing one would imply those exist |
| `MagpieProvidersView` | The "AI providers" tab: installed packages with their versions and sign-in state, buttons to sign in, sign out, remove, and install from a folder. Entirely separate from comic sources: different packages, different accounts, different cookies |
| Cost of a list | The declaration is recorded at install time (`MagpiePackage.specJSON`), so refreshing the providers tab no longer starts a JavaScript runtime per package; a package installed before that is evaluated once. A test lists providers through a second view whose factory throws if it is ever called |
| Archive install | The install screen now takes an **extracted folder** or a downloaded `.zip`/`.tar.gz`: Core's `readPackageArchive` does the expanding (one enclosing directory stripped, symlinks and `../` refused, the same limits) and the client stores the table Core produced. Expanding uses a temporary Core that is closed afterwards, so an install leaves no runtime behind |
| `MagpiePackageReader` | Reads a package from a folder the user picks: files keyed by package-relative path, symlinks refused (a package is plain files), and 8 MiB per file, 32 MiB total, 1024 files — the same limits Core enforces, checked here first so a stray video is refused instead of copied. No `package.json` means "not a plugin"; a manifest that names no entry (`exports["./server"]`, `main`, `index.*`) does not count either, which is Magpie's own rule |
| `MagpiePackageStore` | Installed packages, one per provider: files kept as **original base64** in one JSON document, with the package's own `name`/`version` for the list. Installing again replaces the old copy instead of stacking; anything without a `package.json` is refused outright, since such a package only fails later, at load time, with a vaguer reason. The index is written to a temporary file and moved into place: a crash mid-write must not make the whole list — and with it every installed package — unreadable. Unpacking is not here: this takes an already unpacked file table, which Core validates again |
| `MagpieSignInView` | The SwiftUI screen, for both kinds of sign-in: **device code** (code shown and copyable, page opened, wait, cancel) and **API key** (a form built from the `prompts` the plugin declares, password fields as `SecureField`). A key settles inside `authorize`, so there is no "I'm done" button that would do nothing. It uses that vendor's own authorization on this device, never a comic source's, and shares no cookie jar with one |
| `MagpieRunner` | Installs a package (path to bytes, base64 to Core), hands over the stored sign-in, runs an export, **stores whatever the package saved afterwards** (otherwise a refresh is lost and the next launch is signed out), and on sign-out closes the instance and deletes the entry. Installation takes an already unpacked file table: unpacking belongs to Core, and this layer trusts no path Core did not validate |

`MagpieRunner.Core` is a protocol rather than the generated `MobileMagpie` directly, so the
orchestration is testable against `StubMagpieCore` without an xcframework. Seven new cases
cover the base64 round trip, no sign-in sent when none is stored, refresh write-back, an empty
write-back not overwriting, sign-out, a failed install, and exact number text surviving.

The real `MobileMagpie` adapter is in place, and `MagpieAccounts` keeps one runner plus one
cached declaration per provider. **One honest boundary:** the host protocol has no streaming
method and gomobile is pull-based, so on iOS a reply arrives **whole** — `MagpieChat` is written
as an event stream and the view renders incrementally, but the first batch of events usually
carries all of it. Real incremental output needs a streaming callback on the host protocol,
which is a change to Core's API, so it is not decided here.
7. One item needs a decision: App Transport Security. Many comic sources serve images over `http://`, and ATS refuses cleartext by default. The desktop client gets away with it because Go's `net/http` does not apply ATS; the app either allows arbitrary loads (cleartext everywhere) or carves out exceptions per host — a security trade-off, so it is not decided here.

## Waiting on a decision

Five questions are product or security calls rather than engineering: the ATS policy, migrating
cookies from the global jar into per-source partitions, the video playback architecture, whether
reference provider packages ship with Core, and one end-to-end run with a real account. Each is on
Core's [docs/OPEN-QUESTIONS.en.md](https://github.com/laincat/VeneraCat-Core/blob/main/docs/OPEN-QUESTIONS.en.md) with the current
state, the options and what staying open costs — not copied here, so the two cannot drift apart.
