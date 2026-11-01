# What is not verified yet

[简体中文](UNVERIFIED.md) | English

Updated 2026-11-01. The last tree that was **fully run on a Mac** is `b9fdf3c` (app built, 16 interface cases, `swift test`). Everything after it has only had the static parse check (`scripts/check-swift.py`) and the test sources themselves — it has not been compiled.

The point of this file: **do not treat those changes as verified.** The table is ordered by how they could break, so a Mac run can start at the top.

## Ordered by risk

| Commit | What changed | How it could break | Look first at |
|---|---|---|---|
| `33c5c7a` | `seed-simulator.sh` writes into the environment actually in use | If the resolution is wrong the seed lands where nothing reads it, which looks like "no sources" | Whether a seeded run really shows the five sources |
| `198d1ad` | Airing reminders: kit planning plus `UNUserNotificationCenter` | The notification API and its permission flow only a device can verify; a `UNCalendarNotificationTrigger` with missing date parts silently never fires | On a device, turn it on and check the count; the seven planning tests |
| `43decff` | Plex video source and Node fixture tests | Never loaded by Core's runtime; a wrong `VideoSource` contract only shows up once installed | Install `plugins/plex.js` as a source; `node plugins/plex.test.mjs` |
| `ab1ebbb` | Details read and show `stars`/`likesCount`/`isLiked` | New `ComicDetails` fields and a view row; a decoding mistake fails the whole details screen | The details screen; the three rating tests |
| `a4ead24` | Closing the player writes the position back to the server | The write runs in the sheet's dismissal closure; a wrong shape there crashes on close | Play one server item and close it; the three write-back tests |
| `0031190` `40e0962` | The release workflow is back in the repo; version 0.2.0 | A wrong script path in the job only shows up on CI | Not checkable locally; needs a tag or a manual trigger |
| `27dd92c` | Three home cards; reading lists filter out videos | A missing case in the home template switch, or a broken layout | Rendering the home screen; the two new `HomeLayout` tests |
| `467b9c5` `4db8265` | Duplicate zip page names, danmaku row identity, integer timestamps | Unit-test level only, low risk | `LocalComic` and `Danmaku` tests |
| `017522b` | Server paging and a 30 s timeout | A wrong query build would empty the media library | Whether the media library lists anything (needs a real server) |
| `7787b3b` | `PlaybackProgress` consolidates the arithmetic | Wide type-level change, the likeliest compile failure | The whole kit compiling; durations on three screens |
| `a693a63` | Zip CRC checking | If the checksums the tests build are wrong, every import test goes red | The four import tests |
| `6ffe7d7` | `VideoPlayerView` argument order | One four-site compile error was found and fixed; a similar order bug could remain | The app compiling |
| `4b80a57` | Import moved off the main actor, `importComic` is async | A call site missing `await` is a compile error | `LocalComicsView`, and the four import tests, now `async` |
| `e460fba` | Unreadable files are copied aside | Nine stores each gained a line; one may name the wrong variable | Each store's `load()` |
| `6d7dc5d` | The migration crash window | Adoption picks the most recently modified directory; that assumption needs a real device | The three upgrade tests; an actual upgrade on a device |

## Needs real conditions

| Item | What is missing |
|---|---|
| Media server connect, browse, play, progress write-back | A Jellyfin/Emby address and account |
| 即将播出 | A TMDB key |
| Pixiv following and bookmarks after signing in | A real Pixiv account |
| Picture in Picture, lock-screen playback | A real device |
| Local videos and imported comics | Files on a real device |

## Checking this list itself

```sh
git log --oneline b9fdf3c..HEAD
```

Every commit above that **touched code or scripts** should appear in the table; pure documentation commits are not listed because they do not compile. Writing this file is how `a4ead24` (progress write-back) was found missing from it — the list drifts, so it has to be checkable in one command.

## How to run it

```sh
sh scripts/fetch-core.sh
NK_UI_TESTS=1 NK_UI_SEED=/tmp/seed.json NK_UI_SEED_REPLACE=1 sh scripts/verify-ios.sh
```

The expected `swift test` count grows with the commits: the last confirmed number was 249 / 48 (before `b9fdf3c`). Count the tests added since rather than checking a remembered number against it.
