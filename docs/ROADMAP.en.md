# Roadmap for the three projects

[简体中文](ROADMAP.md) | English

Updated 2026-11-02. Covers Nekularity, Nekophage and VeneraCat Core. Work through the order below one item at a time. When an item requires a device, account or server, record the missing condition and continue with the next independent item. One release does not complete the roadmap.

## Assessment and baseline

| Project | Current facts | Main gaps |
|---|---|---|
| Nekularity | SwiftUI + NekularityKit + gomobile Core; AltStore has 0.2.5 (build 7), with an HTTP 200 IPA download | Later Discover identifier and size-selection fixes are not included in 0.2.5 |
| Nekophage | MyGo native window + WebView reader; Windows evidence covers real sources, decoded images, shelf and the installed Magpie gateway | Desktop video is not connected; search/browse/detail cancellation and image budgets passed local race tests; no Git remote |
| VeneraCat Core | Shared comic, video, backup and AI protocol logic; clients own networking and platform facilities | A few JS engine compatibility limits and ongoing client contracts; Sender has no production caller |

This review checked code and existing receipts; it did not rerun every test in all three projects. All three local worktrees were clean at the start. Both clients' `scripts/core-version` files contain `214e7782190d47c1f4bcdc9a95fb3a517072cc85`; the Core repository HEAD is `c3a7dd8`. Do not describe a pin and repository HEAD as the same version.

Nekularity code baseline `c259f3f`: an Orca Worker built it on the Mac and passed the arranging case (24.6 seconds, no skip); update-all passed on `fd1cef0`. With a fixed UUID and complete comic/video seed, the full `2cf44e4` suite returned 19 cases / PASS 18 / FAIL 1 / SKIP 0. Long-press entry was the sole failure. The `0f2a5a2` entry change is with the Orca Worker for targeted retesting; no result has arrived. Results from different commits cannot be combined into a full-suite pass.

## Priorities and acceptance

| Order | Goal | Acceptance |
|---|---|---|
| P0-1 | Close the current iOS regression round | Receive the full `c259f3f` UI result, fix real failures and retest; report total/PASS/FAIL/SKIP; bring the Chinese and English STATUS and UNVERIFIED current, keeping historical results as history |
| P0-2 | Release a test build containing the fixes | After regression, prepare 0.2.6 or the next unused version; align app and widget versions; pass CI unit tests, device build, UI test compilation and packaging; verify IPA metadata/extensions and HTTP 200/size, then update and verify the AltStore subscription entry |
| P1-1 | Finish Discover and theme UI validation | Long press enters arranging; drag order and small/medium sizes persist; HTTPS theme installation and errors work; inspect light/dark and narrow/wide screenshots, distinguishing simulated widths from real folding devices |
| P1-2 | Complete download and playback device validation | Download start/end Live Activity on lock screen and Dynamic Island; offline reading; playback/subtitles/resume/PiP/background audio; record version, device, actions and results. Start with local media and fixtures where accounts are unnecessary |
| P1-3 | Exercise both iOS AI paths for real | Standard API and Magpie plugins each cover models, answers, cancellation and persisted credential refresh; only a chunk arriving before request completion counts as network streaming; record whole-response behavior honestly and identify missing real accounts |
| P2-1 | Desktop reading performance and cancellation | Replaced searches/browse/details cancel their requests; shared cover downloads have bounded concurrency and a byte-based cache budget; slow responses demonstrate old requests stop while current results remain correct; run relevant race tests |
| P2-2 | Desktop delivery and macOS usability | On the current pin run macOS search → details → reading → persisted progress; produce a Windows package that starts and installable artifacts. With no remote, keep artifacts local until a publishing destination is needed; Linux comes later |
| P3-1 | Real shared Core compatibility gaps | Reproduce remaining register-limit and frozen-atob failures minimally, then choose an upstream fix or an explicit limitation; distinguish failed sites from client defects; functional Core releases update both client pins and contracts |
| P3-2 | Minimal desktop video path | First evaluate reusing WebView and a media proxy; establish platform HLS, Range and header support, then implement search → details → playback → progress; explain unsupported DRM/sniffing rather than showing a black screen |
| P4 | Accounts and extended capabilities | Connect Jellyfin/Emby/Plex, Bangumi, TMDB and Pixiv accounts individually; then assess Trakt sync, online danmaku and the studio. Never classify an unimplemented feature as merely waiting for credentials |

## Work requiring external conditions

| Item | Dependency | Handling |
|---|---|---|
| Dynamic Island, background behavior, notifications and physical gestures | Suitable iPhone and user device actions | Supply an AltStore test build and short steps; await observed results |
| Bangumi, provider and Pixiv sign-in | An authorized real account | Connect when needed; keep credentials out of repositories and logs |
| Media servers and TMDB | Reachable services and credentials | Advance independent work; fake transport is not real-service evidence |
| Public desktop distribution | Nekophage has no remote | Prepare a runnable package first; do not silently create a public repository |

## Old tasks not to repeat

Code review confirms that iOS already has chunk-level body limits, early cancellation registration and cross-origin credential-header removal; ImageLoader tracks shared waiters; standard AI settings and UI are connected; Magpie uses `MobileNewMagpieWithStream`. Do not queue these again as unimplemented. Fix observed failures instead. Keep `magpieplugin.Sender` documented as a library interface without a production caller; do not wire it into desktop Magpie just to justify its existence.

A missing `accessibilityIdentifier` does not mean a missing VoiceOver label. The Discover tree contained labels while the ancestor overwrote identifiers. This demonstrates an automation-addressing defect; it does not establish VoiceOver usability either way.

## Execution and stopping rules

Each round must complete a concrete action with evidence: fix a reproduced defect, run relevant cases, verify real UI or deliver an installable build. Rereading old logs, repeatedly querying unchanged CI or rewriting documentation is not a new engineering completion. Use appropriate validation without adding unnecessary checkers.

The existing Orca Worker owns Mac tests; the Lead owns analysis, implementation, contracts and release integration. Do not duplicate the same test run. Keep full logs in files and report only command/result/path, plus the most relevant error line on failure.

The current phase covers the independently verifiable work in P0 through P3 under available conditions; hand off externally dependent items separately. Declare the phase complete only after each acceptance criterion is resolved, never just because one release shipped. P4 product additions are deferred and do not silently expand this phase.
