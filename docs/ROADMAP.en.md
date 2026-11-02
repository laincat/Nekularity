# Roadmap

[简体中文](ROADMAP.md) | English

Updated 2026-11-01. This file keeps **what is to be done and what counts as done** in one place, so each round does not have to re-derive it from a conversation. The parentheses mark verification state, not effort.

## Done, with evidence

| Item | Acceptance | State |
|---|---|---|
| Core and its two clients | A Core release pins both clients, and the three-platform plus Apple CI all pass | Done, Core `214e778` |
| The reading path | Multi-source search, browse, details with grouped chapters, two reader layouts, progress written back | 13 simulator cases passed |
| Source abilities | Install/update/enable/remove, settings, callbacks, logs, web login, source favourites | Simulator cases plus desktop probes |
| Backup | `.venera` import and export, including per-source cookies | Unit tests and real backup files |
| Themes | A theme is one JSON; only follow-the-system ships, the rest are imported | Unit tests (compile pending) |
| Downloads | Chapter bytes on disk, readable with no network, manifest stores relative paths | Case pending |
| Video | Source search → details → play, decoded by AetherEngine, headers carried | Cases pending |
| The Pixiv plugin | Five rankings, search, details and pages work anonymously; images need the Referer | Verified on the desktop against the live site |
| Multi-account | Each environment owns sources, cookies, AI sign-ins, shelf and downloads | Unit tests (compile pending) |

## Goals, in priority order

| Goal | Why first | Acceptance |
|---|---|---|
| G1 Compile the current tree and run every interface case | Six changes have never been compiled on a Mac (themes, downloads, the four-section rebuild, the look, environments) | **Done (`9b48b56`)**: the build succeeds, `swift test` is 371 / 71 / 0, all **16 of 16** interface cases pass, and `verify-ios.sh` is green twice |
| G2 Settle the look | It is glass cards and a floating bar now, but nobody has seen it render | Four screenshots each in light and dark, no overlap, clipping or unreadable contrast |
| G3 Try the Pixiv login for real | Bookmark and following sections cannot be verified without an account | After signing in, 关注的新作 and 我的收藏 both show content, and still do after a relaunch |
| G4 One history for reading and watching | ~~The calendar only knew about reading~~ Written, awaiting a compile | Watching a video writes the same history, and the calendar and statistics include it |
| G5 Media servers (Jellyfin/Emby/Plex) | ~~None of it~~ Jellyfin and Emby connect, browse, play and **write progress back to the server**; Plex is implemented as a video source (parsing fixture-tested, requests need a server) | Add a server → browse a library → play an item → progress written back (needs a real server to try) |
| G6 One entry for servers and local files | ~~资源库 was a placeholder~~ One searchable list, grouped by origin | Servers and local video appear in one list, searchable |
| G7 Playback experience | ~~Cue drawing missing~~ Speed, subtitle tracks, remembered position, PiP on both routes and a text-cue overlay are done; bitmap cues are left to the software route's own compositing | Speed, subtitle track choice, remembered position, picture in picture |
| G8 Calendar and reminders | ~~No air dates~~ TMDB supplies the date and reminders are wired (permission and delivery need a device) | A working reading calendar; items with air dates carrying reminders (done) |
| G9 Trakt and TMDB metadata | ~~Needs an account and an API key~~ TMDB is wired (poster, synopsis, upcoming); Trakt and account history sync are not | Once connected, history syncs and posters and synopses appear (needs a real key) |
| G10 Danmaku and intro skipping | ~~Depends on a danmaku source~~ Local danmaku files and a marked opening are done; Core has **no danmaku API at all** (checked), so online danmaku would need a third-party service | A chosen source plays with a danmaku track (local files work), and an intro range can be skipped (works) |
| G11 Batch source update and check | ~~one at a time~~ the batch update existed, but its replace branch never ran — it looked for `already installed` while Core says `key(...) already exists` — so every update of an installed source failed | **Done (`21ad88e`)**: either wording is read, and tests cover the skip, update and failure paths plus the wording itself |
| G12 Local comics | ~~None~~ Folder and cbz/zip import, paging, remembered page and removal are done | Import a folder or a zip/cbz and read it |
| G13 Tag translation and rating | ~~Translation~~ ~~Rating blocked on Core~~ Both done: translated tags and the source's own rating | Tags show a translation; a rating appears where the source offers one |
| G14 Real device and real account | Only simulator evidence exists; a diagnostics page now makes the evidence copyable | A device install, a real sign-in, and lock-screen and background behaviour all recorded (**needs you to install and sign in**) |

## Not doing, deferred, and the evidence for each

This section exists because I wrote "not possible" three times when the truth was "I did not look" — rating, Plex and software-route PiP, each overturned by reading one file. So every conclusion here says **what was checked**, and "not verified" where nothing was.

| Item | Conclusion | Evidence (what was checked) |
|---|---|---|
| Pixiv OAuth (the app API) | Not doing it; the web login is used | Measured 2026-11-01: `app-api.pixiv.net/v1/illust/ranking` answers **HTTP 400** without a bearer; `www.pixiv.net/ajax/user/self` answers **HTTP 200** with a null `userData` when anonymous |
| An online danmaku source | Not doing it; local files only | `grep -ril danmaku --include=*.go` over all of Core returns **nothing**; neither the comic runtime nor the video contract has a danmaku interface |
| The rest of G7: drawing subtitle cues | **Possible, not done** (not blocked) | AetherEngine 7.53.1 publishes `$subtitleCues` with `.text`, `.richText` and `.image` bodies, which is enough to draw an overlay |
| Linux and the web client | Deferred | **Not verified**: Core's non-Apple build and an interface approach have not been assessed |
| Bringing the desktop to parity | Deferred | **Not verified**: Nekophage's current state was not rechecked (last record is the reading path only) |

## What counts as a round of progress

A round needs at least one **verifiable** thing: a build passing, cases passing, real data from a real site, or an acceptance criterion in this file being met. Writing code alone does not count, and neither does rewriting documentation.
