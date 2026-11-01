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

## Scope problems do not show up locally

`check-swift.py` parses and runs a few textual rules; it **does no scope or type checking**. Using an `@Environment` value like `library` or an `@State` value like `model` inside a different type is perfectly valid syntax and only fails when the Mac compiles it — which happened this round: a helper ended up inside `SearchModel`, which has no `library`.

It was tried as a rule and rejected: the heuristic reported 12 candidates across the repository and **every one was a false positive** (parameters and locals that share the name). The workable substitute is to count by hand after touching a view: wherever `model.` or `library.` is used, does that type declare it?

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
## A test can be wrong the same way the code is

Restoring a backup's cookies wrote them into the partition named by the bare source key, while
every request reads `"comic:<key>"`. The cookies landed where nothing would ever read them and the
import summary claimed "N sign-ins restored". **The test asserted the same wrong assumption**
(`partition: "mini"`), so it passed.

That is not the same as "uncovered code": coverage, syntax checks and the cases themselves were all
fine — the case was confirming a misunderstanding. What catches it:

- check a **fact source outside the code** (here, the key the transport actually uses) instead of
  trusting the implementation;
- make the wrong call impossible (`restore(source:)` adds the prefix) instead of relying on "remember
  the helper";
- have the regression case assert **the right place has it and the wrong place does not** — a case
  that only asserts presence passes under a different wrong assumption too.

## Interface cases touch no network, images included

The interface cases run against the repository's own test source (`UITests/Fixtures/callback_probe.js`), which answers search, details, chapters, comments and favourites itself. **The reader needs images, and images used to need a site** — they no longer do: the test runner and the app are two processes on the same simulator and **share loopback**, so `UITests/LocalImageServer.swift` starts an HTTP server in the runner that answers with one PNG, and the fixture's chapter points at `http://127.0.0.1:18731/page.png`.

Three things to keep in mind:

- **That port is only alive inside the runner.** Reading the chapter anywhere else yields `images=1 decoded=0` (measured with the desktop `cmd/readercheck`), which is why no desktop probe opens a chapter of this source.
- The PNG is **drawn at runtime**, not pasted as base64. A hand-typed blob that fails to decode looks exactly like a client bug.
- The test target inherits `SWIFT_STRICT_CONCURRENCY: complete`, so that server has to deal with Sendable itself: `NWListener`'s handlers are `@Sendable`, and mutating a captured `var` or capturing a non-Sendable `self` inside them is a compile error. It now uses `@unchecked Sendable` (every stored property is a `let`) plus a locked `Signal` to carry the start result.

Pick a criterion that can fail, too: the reader greys out 收藏本页 while it has no pages, so "the button became enabled" is what proves an image arrived; "the reader opened" proves nothing.

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

## A whole-tree run has to build the app

Without XcodeGen, `verify-ios.sh` falls back to building the Kit with SwiftPM and **never builds the app
bundle** — so `Info.plist`, `excludes` and ATS, which only take effect in the resource phase, are all
unverified while the output still says `EXIT=0`.

When that step matters, take the binary from the release page rather than installing Homebrew:

```sh
mkdir -p /tmp/xcg && cd /tmp/xcg
curl -fsSL -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
unzip -o -q xcodegen.zip
PATH="$(dirname $(find /tmp/xcg -name xcodegen -type f | head -1)):$PATH" sh scripts/verify-ats.sh
```

`/tmp/xcg` is a temporary directory: delete it to revert. That is easier to undo than `brew install` and
leaves the system alone.

## Getting the code to a verification machine

That machine may be a Mac that **has no credentials for this repository**. In order:

1. Clone when you can — a public repository needs no credentials, a **private one does**, and verification machines usually lack them;
2. When you cannot clone, build a whole payload with `scripts/make-payload.sh` and put it in a **secret gist** for the machine to `curl`. Do not push hundreds of base64 segments through a conversation: equal-length rewrites and shifted segment numbers are hard to notice there;
3. When both sides have a copy, send only the patch from `scripts/make-patch.sh`.

**Ship a whole tree with `scripts/make-tree-transfer.sh`**: `make-transfer.sh` packs only the files it is named, so `make-transfer.sh OUT /tmp/seed.json` sends a package holding a seed and nothing else — and the verification machine then goes looking for a tree that never arrived. The new script always ships the repository, and **before printing anything** it clones the bundle it just built to confirm the HEAD and the file count:

```
sh scripts/make-tree-transfer.sh /tmp/nk /path/to/seed-ios9.json
tree <sha> (141 files) / bundle md5 / b64 md5 / and a message block to paste
```

That comes from a real loss: the machine unpacked the package, found only a seed, and — since a payload has no `.git` — could not fetch the tree itself. **Paste the block the script printed; do not retype it**: of the three transfer failures in this round, two came from me writing hashes or paths by hand, and a block produced by the script cannot disagree with itself. Edit the prose around it, copy the commands and hashes whole.

The script now **uploads the seed too** when one is given, printing its raw URL and both hashes: a message that named a seed and its md5 but no address left the other machine waiting, and `check-seed.sh` compares seed against tree — it cannot fetch the seed for the receiver.

**Run one case**: `NK_UI_ONLY=testReaderDrawsTheChaptersPage` adds `-only-testing:` to `xcodebuild`. A dozen cases take minutes, and when one of them fails there is no reason to re-run the ones that passed — the gate's label says which case ran.

**The device's seed is never overwritten silently**: `scripts/seed-simulator.sh` stops when the device already holds a *different* seed, on purpose — otherwise one verification pass would quietly change someone's data. So either send a seed that matches the device or pass `NK_UI_SEED_REPLACE=1` explicitly. Note that `check-seed.sh` compares "seed against tree"; it cannot say what is on the device. Only the verification machine can see that, so leave that check to it.

**Check the seed before sending it**: `sh scripts/check-seed.sh /tmp/seed.json` compares the seed's `callback_probe` body with `UITests/Fixtures/callback_probe.js` (line endings aside) and verifies the seed's own sha256. The seed is built by the desktop's `cmd/seedgen` but travels as a separate file with a separate md5 — there has been a case where the seed was built before a fixture edit, the case ran against yesterday's script, and the failure pointed at the client.

Ship a whole tree with `scripts/make-tree-transfer.sh` — a git bundle, so the clone **has `.git`** and `check-tree.sh` reports a real commit. `make-transfer.sh` packs only the files it is named, so `make-transfer.sh OUT /tmp/seed.json` ships a seed and nothing else. Both read every hash from the files and print a block that can be pasted as-is (`GH_CREATE_GIST=1` also creates the gist and fills in the raw URL) — **if a message contains a hash, a person should not be typing it**. **Delete the gist as soon as the other machine has the code** (`gh gist delete <id>`): a secret gist is unlisted, but anyone holding the link can read it. macOS `base64` takes no positional argument: `base64 -D -i p.b64 -o p.tar.gz`. With no tree-sitter installed, or only the system Python 3.9, `check-swift.py` **no longer skips as a whole**: the syntax parse needs a parser, but the rules are plain text, so a missing parser downgrades it to the rules and it reports 0/1; `verify-ios.sh` labels that row `PASS python3 scripts/check-swift.py (rules only: no parser here)`. **Do not read that downgrade as a full pass** — nothing was parsed; to parse, install tree-sitter on that machine.
