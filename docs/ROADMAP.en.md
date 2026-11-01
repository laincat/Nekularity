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
| G5 Media servers (Jellyfin/Emby/Plex) | This is the reference app's core, and we have none of it | Add a server → browse a library → play an item → progress written back |
| G6 One entry for servers and local files | 资源库 is a placeholder today | Servers and local video appear in one list, searchable |
| G7 Playback experience | AetherEngine already supports it; the screen does not use it yet | Speed, subtitle track choice, remembered position, picture in picture |
| G8 Airing calendar and reminders | The reference app's signature | Items with air dates appear in the calendar and can carry a reminder |
| G9 Trakt and TMDB metadata | Needs an account and an API key | Once connected, history syncs and posters and synopses appear |
| G10 Danmaku and intro skipping | Depends on a danmaku source; the largest piece | A chosen source plays with a danmaku track, and an intro range can be skipped |
| G11 Batch source update | Today only one source at a time | One action checks every source and lists what can be updated |
| G12 Local comics | The original Venera has it; we do not | Import a folder or a zip/cbz and read it |
| G13 Tag translation and rating | Present upstream, missing here | Tags show a translation for the language, and rating works where the source supports it |
| G14 Real device and real account | Only simulator evidence exists | A device install, a real sign-in, and lock-screen and background behaviour all recorded |

## Not doing, or needs a decision first

| Item | State |
|---|---|
| Pixiv OAuth (the app API) | Needs a client credential; in a plugin that is a published credential, and natively it is a second account architecture. The web login is used instead |
| Linux and the web client | After iOS, macOS and Windows are done |
| Bringing the desktop to parity | The desktop has the reading path only; video and the media library have not started |

## What counts as a round of progress

A round needs at least one **verifiable** thing: a build passing, cases passing, real data from a real site, or an acceptance criterion in this file being met. Writing code alone does not count, and neither does rewriting documentation.
