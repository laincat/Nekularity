# What is not verified yet

[简体中文](UNVERIFIED.md) | English

Updated 2026-11-01. **This tree compiles.** GitHub Actions run `41316459367` (commit `71c8c97`) built the pinned Core, ran the four repository checks, generated the project, compiled the app with `xcodebuild` on macOS, and produced an unsigned IPA (18.9 MB). The worry that the commits after `b9fdf3c` had never seen a compiler is now settled.

Compiling is not behaving. The iPhone interface cases and `swift test` still do not run on CI, and a real device and real servers are still missing.

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
| Truncation notice | Reads `outcome` from Core's events and shows "hit the length limit" in the chat screen | Added this round; neither build nor tests have run | Make a model answer to its max_tokens and check the notice; `swift test --filter Magpie` |
| Bangumi support | Account, five collection states, episodes, weekly calendar, reminder join | Added this round; neither the build nor the tests have run yet | Connect a token on a device; `swift test --filter Bangumi` |
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

CI currently builds without running tests: the `xcodebuild` action is `build`. To bring the unit tests in, the workflow needs a `test` step with a simulator destination — that is the next thing to add. The expected `swift test` count grows with the commits: the last confirmed number was 249 / 48 (before `b9fdf3c`). Count the tests added since rather than checking a remembered number against it.
