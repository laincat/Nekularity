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
- Every `.md` exists in Chinese (`X.md`) and English (`X.en.md`), linked to each other at the top. Change both together, with `scripts/update-pair.py`: it finds every anchor in both files before writing, so one side cannot be left behind. `scripts/check-docs.sh` checks the pairs, the root, and that both sides have the same number of table rows and headings.
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

Three of these are checked automatically now: a `Tests/` double conforming to
`MagpieRunner.Core` missing a method, a file that names a generated `Mobile*` type
without `import VeneraCatCore`, and an `App/` file that names a kit type without
`import NekularityKit` (all in `check-swift.py`; the last two would only fail on the
Mac, which is why catching them on Windows is worth the rule).
## Clear the build products before verifying

Files unpacked from an archive carry an mtime of 0 (1970), so `swift build` treats them as older than what is in `.build` — and **new tests are never compiled while the run looks green**. `touch` the files and `rm -rf .build` first, or trust only a clean build. This is not hypothetical: the tar is built with zeroed mtimes for reproducibility, and this is the price.

## Tests must not share mutable state

Swift Testing runs the tests in a suite **in parallel** by default. A shared static stub table plus a `reset()` at the start of each test means a request can arrive after another test cleared the table; the stub then answers nothing and the failure is `-1004 cannot connect to host`, which reads like a network problem. Two rules: give each test its own host names or keys and **do not clear a global table**; use `.serialized` only when it is genuinely required, and say why.

## Paste a small file instead of linking it

When delivering a **new file** (a script, a plist), `scripts/make-transfer.sh --inline FILE` prints its md5 and its text. This is measured, not theoretical: sending a link in one message and the hashes in another went missing twice. Whole packages still go through a gist (many files, too long to paste), but a few dozen lines do not need that extra uncertainty.

## The pin message is generated too

The pin lives in four places and the other machine checks hashes. Typing those hashes by hand has gone wrong three times, twice by leaving a placeholder. `scripts/make-pin-message.sh` prints the whole block with the values read from the files — the same rule as `make-transfer.sh`: if a message contains a hash, a person should not be typing it.

## The docs on a verification machine may be old

A transfer package often carries only code and tests, so `docs/` on that machine lags behind the repository. Its `check-docs.sh` still runs — it compares pairs and structure — but **its passing is not evidence that the repository's docs are current**; that is settled by the run before pushing.

## Getting the code to a verification machine

That machine may be a Mac that **has no credentials for this repository**. In order:

1. Clone when you can — a public repository needs no credentials, a **private one does**, and verification machines usually lack them;
2. When you cannot clone, build a whole payload with `scripts/make-payload.sh` and put it in a **secret gist** for the machine to `curl`. Do not push hundreds of base64 segments through a conversation: equal-length rewrites and shifted segment numbers are hard to notice there;
3. When both sides have a copy, send only the patch from `scripts/make-patch.sh`.

A payload has **no `.git`**, so on the verification machine `scripts/check-tree.sh` reports `none` for the commit — the four values to compare are `swift`, `tests`, `suites` and `shape`. Check the archive md5 on arrival and stop if it does not match. **A hand-typed md5 in the message is the part that goes wrong** — generate the message with `scripts/make-transfer.sh OUTDIR FILE…`, which reads the archive, base64 and per-file hashes from the files and prints a block that can be pasted as-is (with `GH_CREATE_GIST=1` it also creates the gist and fills in the raw URL). **Delete the gist as soon as the other machine has the code** (`gh gist delete <id>`): a secret gist is unlisted, but anyone holding the link can read it, so it is not a substitute for the repository. The archive is the repository itself (`./App`, `./Sources`, …), so there is no wrapper directory to flatten. macOS `base64` takes no positional argument: `base64 -D -i p.b64 -o p.tar.gz`. With no tree-sitter installed, or with only the system Python 3.9, `check-swift.py` exits **2** or **3** to mean "this machine cannot run it"; `verify-ios.sh` records that as SKIP — an environment limit, not a broken tree. A developer machine running `scripts/check-swift.sh` still fails hard.
