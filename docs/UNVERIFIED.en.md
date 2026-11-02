# What is not verified yet

[简体中文](UNVERIFIED.md) | English

Updated 2026-11-02. The published version is `v0.2.5` (build 7, commit `7a00580`): CI ran kit unit tests, the device build, UI test compilation and IPA packaging; the download returned HTTP 200. An Orca Worker on the Mac passed update-all (`fd1cef0`) and arranging (`c259f3f`, 24.6 seconds, no failure or skip). The first full `c259f3f` UI run returned 18 cases / PASS 4 / FAIL 0 / SKIP 14. Seeding then failed because the target simulator had no app installed; the second run returned PASS 3 / FAIL 1 / SKIP 14 (update-all had no add button). This is not a full-suite pass: installation, seed and test must use the same simulator UUID before rerunning. The new long-press and resize-persistence case has not run on the Mac either. The older 374 unit tests and 16/16 UI on `v0.2.3` are historical results, not evidence for this commit.

The accent contrast has **no screenshot behind it**: the evidence is the `accentTextFollowsTheAccent` test and the code, not an observed screen. The three shipped accents resolve to white text on `#3482FF`, dark text on `#6BA4FF`, and white text on `#0A84FF`.

Earlier evidence: **this tree compiles.** GitHub Actions run `41316459367` (commit `71c8c97`) built the pinned Core, ran the four repository checks, generated the project, compiled the app with `xcodebuild` on macOS, and produced an unsigned IPA (18.9 MB). The worry that the commits after `b9fdf3c` had never seen a compiler is now settled.

Compiling is not behaving. CI runs `swift test`, but only compiles the iPhone interface cases; the Mac Orca Worker executes them on a simulator. Real devices, accounts and servers remain separate gaps below.

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
