# Nekularity status

English | [简体中文](STATUS.md)

Updated 2026-10-30.

## Host signatures cross-checked

All 21 `CoreHost` methods were compared against the Swift host implementation in Core's `apple/CoreSmoke`, which CI really compiles and runs: methods returning an object import as `(params…, error: NSErrorPointer) -> String`, while `void`/`Bool` methods import as `throws`. So `http(_:error:) -> String`, `saveData(_:dataKey:valueJSON:) throws`, `writeClipboard(_:) throws` and `readClipboard(_:) -> String` are the shapes Nekularity already uses. Matching signatures is not compiling, though — the real type check still waits for `swift build` on the Mac.

Every Kit member the UI calls was checked the same way: `library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`, `core.search / searchOptions / explore / explorePages`, `shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`, `searches.add`, `store.loadSetting / saveSetting` all exist with matching parameters.

## Written (not compiled)

| Part | Contents |
|---|---|
| Core wrapper | `CoreClient`: async/await API that passes task cancellation to Core; `CoreHost`: implements every host interface Core needs; search calls `search.load` with the defaults Core reports for each filter group |
| JSON | A small `JSONValue` parser and `OrderedJSONDecoder` that keep key order and number text |
| Networking | `URLSessionTransport`: cookies isolated per source, including cookies set on redirect hops |
| Cookies | `CookieJars`: host-only and domain cookies, paths, Secure, expiry; persistent cookies saved to a file |
| Human verification | `VerificationSession`: a WKWebView loads the challenge, passes by Core's done rule, and hands back cookies and the User-Agent |
| Storage | `SourceStore`: source data, settings and plugin records kept as written; logged in follows the official rule (an `account` value exists) |
| Images | `ImageLoader`: requests through each source's `onImageLoad`/`onThumbnailLoad`, downsampled and cached |
| Screens | Sources (indexes, install from URL, update, enable, delete), search, details (grouped chapters), reader (vertical scroll, previous/next chapter), source-driven toasts, dialogs, input, choices and loading |
| Source settings | `CoreClient.settings(key:)` reads Core's `settings` declaration; a source's detail screen opens a settings screen that draws each by type (picker, toggle, text field) and stores the value as `JSONValue` in that source's store, so numbers and booleans survive; an input's `validator` runs as a regular expression, and a callback is shown as an in-source action |
| Shelf | `ShelfStore` keeps reading history (one row per comic with its chapter, page and percentage) and favourite folders; opening a chapter records it, and the shelf screen can continue, forget, move between folders and create/rename/delete folders; `shelf.json` has the same shape as the desktop client's |
| Search history | `SearchHistoryStore` keeps the last 30 keywords, newest first, with case-insensitive repeats collapsed, and can merge a backup's `searchHistory`; `searches.json` matches the desktop client |
| Browsing | `CoreClient.explorePages` and `explore` cover the four browse kinds (single page with parts, multi-page list, mixed, multi-part page); `BrowseView` switches between browses with chips, pins section headers, pages, and refreshes by pulling |

## Not verified

- **Compilation**: `scripts/verify-ios.sh` runs the checks in order on macOS (docs, `check-swift`, `swift test`, the app build). Without XcodeGen it falls back to building the Kit for iOS and type checking the screens with `swiftc -typecheck`, which still catches mistakes in the screens. The code has not actually been run on macOS yet, but every change goes through `scripts/check-swift.sh` (a tree-sitter parse: it catches syntax errors, not type errors). It calls Core the same way as the Core repository's `apple/CoreSmoke`, which passes on CI; `BrowseView` is new and uncompiled too. When the sources travel to a Mac as base64 segments, `scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK WORKDIR [clean]` does the whole check in one command: segment md5s, join, decode, archive md5, unpack, `.swift` count, xcframework copy, `swift build`; a trailing `clean` removes the unpacked tree, the joined file and the archive after reporting, leaving the machine as found.
- The unit tests in `swift test` (JSON, cookies, storage) have not run either.
- Running on a device, with real comic sources.

## Next

1. Publish the repository or build on a Mac, fix compile errors, run `swift test`.
2. Run the main path with a real comic source.
3. The shelf (reading history and favourites) is not built yet; the desktop client's `internal/shelf` and its `.venera` history/favourite import show the way.
4. Compile `BrowseView` and the search-option call on a Mac and fix what it reports.
4. Phase two: favourites and history, `.venera` backup import, video sources.
