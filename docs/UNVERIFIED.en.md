# What is not verified yet

[简体中文](UNVERIFIED.md) | English

Updated 2026-11-01. The last tree that was **fully run on a Mac** is `b9fdf3c` (app built, 16 interface cases, `swift test`). Everything after it has only had the static parse check (`scripts/check-swift.py`) and the test sources themselves — it has not been compiled.

The point of this file: **do not treat those changes as verified.** The table is ordered by how they could break, so a Mac run can start at the top.

## Ordered by risk

| Commit | What changed | How it could break | Look first at |
|---|---|---|---|
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

## How to run it

```sh
sh scripts/fetch-core.sh
NK_UI_TESTS=1 NK_UI_SEED=/tmp/seed.json NK_UI_SEED_REPLACE=1 sh scripts/verify-ios.sh
```

The expected `swift test` count grows with the commits: the last confirmed number was 249 / 48 (before `b9fdf3c`). Count the tests added since rather than checking a remembered number against it.
