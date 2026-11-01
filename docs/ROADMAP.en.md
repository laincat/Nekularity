# Roadmap

[简体中文](ROADMAP.md) | English

Updated 2026-11-01. This file keeps **what is to be done and what counts as done** in one place, so each round does not have to re-derive it from a conversation. The parentheses mark verification state, not effort.

## Done, with evidence

| Item | Acceptance | State |
|---|---|---|
| Core and its two clients | A Core release pins both clients, and the three-platform plus Apple CI all pass | Done, Core `8aebced` |
| The reading path | Multi-source search, browse, details with grouped chapters, two reader layouts, progress written back | 13 simulator cases passed |
| Source abilities | Install/update/enable/remove, settings, callbacks, logs, web login, source favourites | Simulator cases plus desktop probes |
| Backup | `.venera` import and export, including per-source cookies | Unit tests and real backup files |
| Themes | A theme is one JSON; system, Miuix and Miuix dark ship, others can be imported | Unit tests (compile pending) |
| Downloads | Chapter bytes on disk, readable with no network, manifest stores relative paths | Case pending |
| Video | Source search → details → play, decoded by AetherEngine, headers carried | Cases pending |
| The Pixiv plugin | Five rankings, search, details and pages work anonymously; images need the Referer | Verified on the desktop against the live site |
| Multi-account | Each environment owns sources, cookies, AI sign-ins, shelf and downloads | Unit tests (compile pending) |

## Goals, in priority order

| Goal | Why first | Acceptance |
|---|---|---|
| G1 Compile the current tree and run every interface case | Six changes have never been compiled on a Mac (themes, downloads, the four-section rebuild, the look, environments) | Build succeeds, all 16 cases pass, `swift test` passes |
| G2 Settle the look | It is glass cards and a floating bar now, but nobody has seen it render | Four screenshots each in light and dark, no overlap, clipping or unreadable contrast |
| G3 Try the Pixiv login for real | Bookmark and following sections cannot be verified without an account | After signing in, 关注的新作 and 我的收藏 both show content, and still do after a relaunch |
| G4 One history for reading and watching | ~~The calendar only knew about reading~~ Written, awaiting a compile | Watching a video writes the same history, and the calendar and statistics include it |
| G5 Media servers (Jellyfin/Emby/Plex) | ~~None of it~~ Jellyfin and Emby connect, browse, play and **write progress back to the server**; Plex is not wired | Add a server → browse a library → play an item → progress written back (needs a real server to try) |
| G6 One entry for servers and local files | ~~资源库 was a placeholder~~ One searchable list, grouped by origin | Servers and local video appear in one list, searchable |
| G7 Playback experience | ~~The screen did not use it~~ Speed, subtitle tracks, remembered position and native PiP are wired; cue **drawing** and software-route PiP are not | Speed, subtitle track choice, remembered position, picture in picture |
| G8 Calendar and reminders | ~~Airing calendar~~ The reading and watching calendar is done; reminders lack the air-date premise and depend on G9 | A reading calendar that works (done); items with air dates carrying reminders (after G9) |
| G9 Trakt and TMDB metadata | ~~Needs an account and an API key~~ TMDB is wired (poster, synopsis, upcoming); Trakt and account history sync are not | Once connected, history syncs and posters and synopses appear (needs a real key) |
| G10 Danmaku and intro skipping | ~~Depends on a danmaku source~~ Local danmaku files and a marked opening are done; online sources need a third-party account | A chosen source plays with a danmaku track (local files work), and an intro range can be skipped (works) |
| G11 Batch source update | ~~One at a time~~ A batch updates and reports the three outcomes separately | One action updates every source with a URL and lists updated, current and failed |
| G12 Local comics | ~~None~~ Folder and cbz/zip import, paging, remembered page and removal are done | Import a folder or a zip/cbz and read it |
| G13 Tag translation and rating | ~~Translation~~ Translation is done; rating is blocked on a Core capability | Tags show a translation (done); rating where the source supports it (Core has no such capability) |
| G14 Real device and real account | Only simulator evidence exists; a diagnostics page now makes the evidence copyable | A device install, a real sign-in, and lock-screen and background behaviour all recorded (**needs you to install and sign in**) |

## Not doing, or needs a decision first

| Item | State |
|---|---|
| Pixiv OAuth (the app API) | Needs a client credential; in a plugin that is a published credential, and natively it is a second account architecture. The web login is used instead |
| Linux and the web client | After iOS, macOS and Windows are done |
| Bringing the desktop to parity | The desktop has the reading path only; video and the media library have not started |

## What counts as a round of progress

A round needs at least one **verifiable** thing: a build passing, cases passing, real data from a real site, or an acceptance criterion in this file being met. Writing code alone does not count, and neither does rewriting documentation.
