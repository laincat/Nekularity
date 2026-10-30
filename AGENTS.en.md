# Nekularity development notes

English | [简体中文](AGENTS.md)

For people and AI assistants working on the code. Read before changing it.

## Principles

- Logic belongs in VeneraCat Core. The client provides the interface, networking, WebViews, the player and storage; new logic goes into Core first.
- Screens only call `CoreClient` and never use the `Mobile*` types gomobile generates.
- Never call Core on the main thread. gomobile methods block; `CoreClient` runs them in the background.
- Each source's cookies and login state are isolated: cookies are kept per `partition` given by Core, never in `HTTPCookieStorage.shared`, and human verification uses a non-persistent WebView data store.
- JSON keeps key order and number text: decode Core results with `OrderedJSONDecoder` or `JSONValue.parse`, never through `JSONSerialization` or Double.
- Do not copy code from AGPL projects (Animeko, AnimeFlow) or unlicensed ones (AniCh). Do not add third-party credentials, accounts or site keys.

## Repository conventions

- The root holds only files that tools or conventions require there.
- Every `.md` exists in Chinese (`X.md`) and English (`X.en.md`), linked to each other at the top. Change both together. `scripts/check-docs.sh` checks the pairs and the root.
- `Vendor/` holds the built Core and is not committed.
- **Do not mix gomobile's two import shapes.** A method returning `NSString*` keeps its
  `NSError**` parameter (`magpie.call(export, argJSON:, error: $0)`); one returning `BOOL`
  is imported as **`throws` returning `Void`** — the success flag becomes the throw, so
  there is no `error:` parameter and no `Bool` to test (`try magpie.loadPackage(json)`, with
  a `do/catch` when a localised message is wanted). The importer also **splits a selector at
  its preposition**, so `cancelSignIn:error:` is `cancelSign(in:)` — do not copy the header name. Writing the wrong one is only found by a compiler
  on a Mac.

## Checks

```sh
scripts/check-docs.sh
scripts/check-swift.sh     # parses every Swift file for syntax errors; no macOS needed
scripts/verify-ios.sh [xcframework]   # macOS: docs, syntax, swift test, app build or type check
swift test                 # macOS, after scripts/fetch-core.sh
```

`check-swift.sh` only parses. Names, protocols and platform APIs still need
`swift build` or CI. Its tree-sitter grammar trails Swift 6 slightly; the
tokens blanked before parsing are listed in `scripts/check-swift.py`.

## Change one thing, then read the whole function

When you change a field's optionality, a method's access level, or move code into
another suite, read every use of it in the same function and type in one pass. These
mistakes are legal syntax, `check-swift` cannot see them, and they only fail on macOS:

- `if let` or `?.` on a local that is already non-optional
- a `private` member called from a test (tests use `@testable import`, which sees
  internal but not private)
- a test placed in a suite other than the one holding the helper it calls

Two of these are checked automatically now: a `Tests/` double conforming to
`MagpieRunner.Core` missing a method, and a file that names a generated `Mobile*` type
without `import VeneraCatCore` (both in `check-swift.py`).
