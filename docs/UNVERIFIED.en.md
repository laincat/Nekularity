# What is not verified yet

[简体中文](UNVERIFIED.md) | English

**Download archive isolation and retry pass unit regression**: `2d9f555` passes 2/2 and 398/398 on macOS, `7550c12` adds 4/4 new cases with 402/402, and `920b94a` passes 6/6 write-path cases across four runs with 404/404, `b3860ea` passes 7/7 across four runs with 405/405, `afe1259` passes 8/8 across four runs with 406/406, and `9f15203` passes 9/9 across four runs with 407/407 in the full suite. Coverage is temporary directories, manifests and injected closures only; devices, the downloads screen and live networks remain unverified, the UI entry for retrying a failed chapter now has simulator coverage (two consecutive runs at `6037f6a`, both from a dirty starting point with the chapter already downloaded, both passing), but it only lasts for the current run: `DownloadStore.failures` is not written to disk and `Failure` holds the fetch closure of that attempt, so a relaunch drops the entry and the user has to start again from the detail page. Retrying across launches needs a default fetcher on `retry`; that is not implemented yet. The functional limits are part of the record: an interrupted chapter restarts from page 1 (there is no resume), queued work does not survive an app restart, and downloads in the background or with the screen locked, including the Live Activity, are unverified; partial folders nothing refers to after a reopen are deleted rather than resumed.

**Interface changes executed; visual matrix deferred**: `5f15769` builds App/UITests on a Mac and passes the complete UI suite 26/26; `81eb017` builds and passes three targeted interaction cases, though its full suite was not run. Light/dark narrow/wide captures, correctly oriented three-column captures, Dynamic Type and Reduce Motion remain unverified, and the large-text truncation issue is known and unfixed; these are the visual items the user asked to defer. The 24/24 and release evidence below belong to earlier commits and stay separate from this round.

Updated 2026-11-02. The latest full Mac UI regression is `5d9a5a1dfd5ce0e9d58fead6371d5cc4b3f842c4`: an Orca Worker uninstalled the app, reinstalled and reseeded the same dedicated simulator, confirmed Themes was empty before launch, and executed **24 cases / PASS 24 / FAIL 0 / SKIP 0** (`/tmp/nk-ui-full-5d9a5a1.log`). All three theme-link cases and the three-column case passed; the earlier 19/19 at `8acbb78` is historical. Long-press entry and resize persistence after relaunch are verified. An earlier Orca Worker separately passed the drag/relaunch case on App `7586982` and cross-checked `homeBlocksV2`; this was not another full-suite execution. Original test commit `33be2af` is on the remote validation branch and integrated into main as `9b2b3e6`; the test file matches the Mac-executed version, and Windows only adds Swift parsing. Eight light/dark discovery/settings captures cover iPhone 402 pt/two columns and iPad 1032 pt/four columns. Five later end-of-scroll captures on `211cd64` confirm that footers do not intersect the pill (about 21–43 pt clearance), with no need for extra bottom margin. Later `5d7022d` established three-column geometry at 874 pt landscape content width; rotated captures and dark-mode top clipping still need another capture. The iPhone bottom captures cannot simultaneously show the TMDB note, which has scrolled to the top. Theme HTTPS install/select/relaunch and invalid JSON passed at `5d7022d`; plaintext HTTP refusal passed separately on App `a526add`. Mac Theme unit tests executed 8/8 at `9005dca` and 12/12 at `6bb7933`. At `9f7840f`, Theme tests execute 12/12 with 0.015 s refusal, while the full UI run did not pass. The Worker originally reported 24 cases / PASS 22 / FAIL 2 / SKIP 0, but listed two assertions in only one failing method; failed-case totals still need reconciliation. The theme-test order dependency is fixed in `5d9a5a1`, whose full 24/24 receipt has arrived. Release CI `41465697611` for 0.2.7/build 9 passed: the IPA downloads with HTTP 200, 29,368,112 bytes and SHA-256 `182f62cf2aea32d6b8183effd0f0f31aede1deeab4270ce02d22b6a12bc8b7f3`; the packaged App/Widget are both 0.2.7/9 and contain the theme HTTPS rejection text. AltStore workflow `41471135708` moved the stable track and first flat entry to 0.2.7/9, with the icon at 200 and ranged IPA at 206. The IPA is unsigned, so signed installation, on-device launch and this version's on-device interface remain unverified; the older release's checks are not reused. Results from different commits do not form one run. Devices/background behavior and real accounts remain unverified. Release build `41431641042` for `0.2.6` (build 8) is green; the downloaded IPA is 29,361,985 bytes with matching App/Widget versions and HTTP 200, and both the AltStore repository and subscription list that version. CI unit tests and simulator UI execution are separate evidence; old-version test counts are not reused as current results.

One measured fact belongs next to that, so "above the floor" is not the whole story: the contrast of each accent against the text colour it selects is `#3482FF` 3.63:1, `#6BA4FF` 8.38:1 (dark text) and `#0A84FF` 3.65:1. All clear the 3:1 floor the code uses for large text, but the first and third are below WCAG AA's 4.5:1 for body text — an existing palette decision, not changed here, recorded so the numbers are not lost.

The contrast criterion for the three accents still comes from `accentTextFollowsTheAccent` and the code; the general light/dark layout captures do not separately measure contrast for all three accents. The three shipped accents resolve to white text on `#3482FF`, dark text on `#6BA4FF`, and white text on `#0A84FF`.

Earlier evidence: **this tree compiles.** GitHub Actions run `41316459367` (commit `71c8c97`) built the pinned Core, ran the four repository checks, generated the project, compiled the app with `xcodebuild` on macOS, and produced an unsigned IPA (18.9 MB). The worry that the commits after `b9fdf3c` had never seen a compiler is now settled.

Compiling is not behaving. CI runs `swift test`, but only compiles the iPhone interface cases; the Mac Orca Worker executes them on a simulator. Real devices, accounts and servers remain separate gaps below.

## External fixture for the theme-link UI cases

The three cases in `UITests/ZZThemeLinkTests.swift` need local fixture servers on `127.0.0.1:18791` (valid and invalid JSON) and `127.0.0.1:18792` (plaintext HTTP), plus a test CA trusted by that simulator. Those fixtures are not in the repository, so the cases `XCTSkip` when the ports are not listening rather than reporting a missing fixture as a product defect.

Evidence provenance: run on 2026-11-02 by an Orca Worker on the dedicated simulator `0A67B65C-9EB9-4504-B7C6-7A8EC74DA1A0` with App `a526add`; UI test commit `aeead82` was cherry-picked as `3167a5e`. HTTP case: the alert names `https`, the test theme never appears in the list, the plaintext server receives 0 requests, and the Themes directory gains no file. HTTPS install/select/relaunch and the invalid-JSON error path are earlier passes on the same fixture. The earlier CA lasted two days; the new CA for the latest full `5d9a5a1` run lasts one day, expires around 2026-11-03 and remains in the dedicated simulator trust store. Temporary services and themes from that run are removed; later reruns need a rebuilt fixture and valid CA, and missing/expired fixtures cannot count as passes.

## What the build proved

| Item | Evidence |
|---|---|
| The kit and the app compile against the real iOS SDK | The "Build unsigned device app" step of run `41316459367` succeeded |
| The IPA packaging path works | "Package unsigned IPA" and the artifact upload succeeded in the same run |
| The repository checks pass on macOS too | The same run's check step: `check-docs`, `check-partitions`, `check-core-pin`, `check-kit-core-calls`, `check-swift` (152 files really parsed, tree-sitter installed) |
| The Core pin is reproducible | The same run fetched and built Core at `214e7782190d` first |

The first real compile found four errors that no static check of mine could see, all now fixed: `ComicDetails`' rating fields decoded into `Comic` (**which would have failed every details screen**), a static method on a `@MainActor` class called from a nonisolated context, two `status == errSecSuccess || errSecItemNotFound` comparisons that treat `OSStatus` as `Bool`, and then twelve interface errors in the app target (a style ternary, `Environment` argument order, optional chaining, the PiP content source and its cross-thread snapshot).

## Still unverified

| Commit | What changed | Where it stands | What is left |
|---|---|---|---|
| Truncation notice | Reads `outcome` from Core's events and shows "hit the length limit" in the chat screen | **Compiled and tested** (build `381f2a6` is green) | Make a model answer to its max_tokens and see the notice appear |
| Bangumi support | Account, five collection states, episodes, weekly calendar, reminder join | **Compiled and tested** (`v0.2.0` build is green, 359 tests) | Connect a real token on a device |
| `33c5c7a` | `seed-simulator.sh` writes into the environment actually in use | Script-level, not compiled | Whether a seeded run really shows the five sources |
| cue overlay | Text cues drawn from `$subtitleCues`, following `clock.$sourceTime` | Compiles | One subtitle-bearing source played, cues appearing in time |
| software-route PiP | `AVPictureInPictureSampleBufferPlaybackDelegate` | Compiles; the content source is now built from a layer, and the two synchronous answers live in a lock-guarded snapshot | One software-decoded title (VP9/AV1) going into PiP on a device |
| `198d1ad` | Airing reminders: kit planning plus `UNUserNotificationCenter` | Compiles | On a device, turn it on and check the count; the seven planning tests |
| `43decff` | Plex video source and Node fixture tests | `node plugins/plex.test.mjs` passes its five cases | Installed as a source and loaded once by Core's own runtime |
| `ab1ebbb` | Details read and show `stars`/`likesCount`/`isLiked` | Compiles (the fields moved from `Comic` to `ComicDetails`) | A rating number visible on a details screen from a live source |
| `a4ead24` | Closing the player writes the position back to the server | Compiles | Play one server item and close it; the three write-back tests |
| `0031190` `40e0962` | The release workflow is back in the repo; version 0.2.0 | **Verified**: a manual trigger now builds and uploads | Only a tag takes the release branch, and none has been pushed |
| `27dd92c` | Three home cards; reading lists filter out videos | Compiles | Rendering the home screen; the two `HomeLayout` tests |
| `467b9c5` `4db8265` | Duplicate zip page names, danmaku row identity, integer timestamps | Compiles, low risk | The matching unit tests |
| `017522b` | Server paging and a 30 s timeout | Compiles | Whether the media library lists anything (needs a real server) |
| `7787b3b` | `PlaybackProgress` consolidates the arithmetic | Compiles (this was the biggest worry, now ruled out) | Durations and resume position on three screens |
| `a693a63` | Zip CRC checking | Compiles | The four import tests |
| `6ffe7d7` | `VideoPlayerView` argument order | Compiles | The player screen as it actually draws |
| `4b80a57` | Import moved off the main actor, `importComic` is async | Compiles | Import a folder and a `.cbz` |
| `e460fba` | Unreadable files are copied aside | Compiles | Break a store file and check the copy is left behind |
| `6d7dc5d` | The migration crash window | Compiles | The three upgrade tests; one real upgrade on a device |

## Needs real conditions

| Item | What is missing |
|---|---|
| Media server connect, browse, play, progress write-back | A Jellyfin/Emby address and account |
| 即将播出 | A TMDB key |
| Pixiv following and bookmarks after signing in | A real Pixiv account |
| Picture in Picture, lock-screen playback, notifications firing | A real device |
| Local videos and imported comics | Files on a real device |

## Checking this list itself

```sh
git log --oneline b9fdf3c..HEAD
```

Every commit that **touched code or scripts** should appear in the table; pure documentation commits are not listed because they do not compile. Writing this file is how `a4ead24` (progress write-back) was found missing from it — the list drifts, so it has to be checkable in one command.

## How to run it

```sh
sh scripts/fetch-core.sh
NK_UI_TESTS=1 NK_UI_SEED=/tmp/seed.json NK_UI_SEED_REPLACE=1 sh scripts/verify-ios.sh
```

CI now runs `swift test --no-parallel --verbose`; `xcodebuild build-for-testing` still only compiles interface cases. Execute UI cases with `test-without-building` on the Mac, reporting the commit, total, failures and skips while keeping full logs. New cases require rebuilding the test target; old products cannot validate new source.
