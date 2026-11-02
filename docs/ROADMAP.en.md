# Roadmap for the three projects

[简体中文](ROADMAP.md) | English

Updated 2026-11-02. Covers Nekularity, Nekophage and VeneraCat Core. Work through the order below one item at a time. When an item requires a device, account or server, record the missing condition and continue with the next independent item. One release does not complete the roadmap.

## Assessment and baseline

| Project | Current facts | Main gaps |
|---|---|---|
| Nekularity | SwiftUI + NekularityKit + gomobile Core; AltStore has 0.2.6 (build 8); App/Widget, IPA HTTP 200/size and subscription are verified | Theme HTTPS UI, three-column widths, device/background behavior and accounts remain unverified |
| Nekophage | MyGo native window + WebView reader; Windows evidence covers real sources, decoded images, shelf and the installed Magpie gateway | Local HLS/MP4 decoding/resume, source installation/restoration, read cancellation and AAC audio decoding verified on both HLS.js and native MP4 paths; Windows has a 0.2.1 portable ZIP and per-user installer; the current macOS pin and actual audible output remain; no Git remote |
| VeneraCat Core | Shared comic, video, backup and AI protocol logic; clients own networking and platform facilities | A few JS engine compatibility limits and ongoing client contracts; Sender has no production caller |

Evidence is recorded per commit and execution channel; this does not claim a fresh run of every test in all three projects. Both clients' `scripts/core-version` files contain `214e7782190d47c1f4bcdc9a95fb3a517072cc85`; the Core repository HEAD is `c3a7dd8`. Do not describe a pin and repository HEAD as the same version.

Nekularity full UI validation commit `8acbb78`: an Orca Worker built, installed and ran the complete suite on one dedicated simulator: **19/19 PASS,0 FAIL,0 SKIP**. Long-press entry and resize persistence passed. A later Orca Worker separately verified drag/relaunch on App `7586982` and cross-checked preferences; original test commit `33be2af` is on the remote validation branch and integrated into main as `9b2b3e6`, with the same test file that ran on the Mac; two/four-column light/dark captures exist; five end-of-scroll captures on `211cd64` confirm unobstructed footers with about 21–43 pt clearance, requiring no extra bottom margin. Three columns remain unverified. `0.2.6` (build 8) is released: CI `41431641042`, the 29,361,985-byte IPA, App/Widget versions, HTTP 200 and AltStore subscription are verified.

## Priorities and acceptance

| Order | Goal | Acceptance |
|---|---|---|
| P0-1 | Close the current iOS regression round (complete:8acbb78,19/19) | Receive the full `c259f3f` UI result, fix real failures and retest; report total/PASS/FAIL/SKIP; bring the Chinese and English STATUS and UNVERIFIED current, keeping historical results as history |
| P0-2 | Release a test build containing the fixes (complete:0.2.6/build 8) | After regression, prepare 0.2.6 or the next unused version; align app and widget versions; pass CI unit tests, device build, UI test compilation and packaging; verify IPA metadata/extensions and HTTP 200/size, then update and verify the AltStore subscription entry |
| P1-1 | Finish Discover and theme UI validation | Long press enters arranging; drag order and small/medium sizes persist; HTTPS theme installation and errors work; inspect light/dark and narrow/wide screenshots, distinguishing simulated widths from real folding devices |
| P1-2 | Complete download and playback device validation | Download start/end Live Activity on lock screen and Dynamic Island; offline reading; playback/subtitles/resume/PiP/background audio; record version, device, actions and results. Start with local media and fixtures where accounts are unnecessary |
| P1-3 | Exercise both iOS AI paths for real | Standard API and Magpie plugins each cover models, answers, cancellation and persisted credential refresh; only a chunk arriving before request completion counts as network streaming; record whole-response behavior honestly and identify missing real accounts |
| P2-1 | Desktop reading performance and cancellation | Replaced searches/browse/details cancel their requests; shared cover downloads have bounded concurrency and a byte-based cache budget; slow responses demonstrate old requests stop while current results remain correct; run relevant race tests. **Local engineering acceptance complete**: search/browse/detail cancellation, four image slots and 32/128 MiB cache budgets; full race/vet checks passed. See Nekophage STATUS |
| P2-2 | Desktop delivery and macOS usability | On the current pin run macOS search → details → reading → persisted progress; produce a Windows package that starts. **Windows portable package complete**: `0.2.0` (`7dc3051`) with the new video entry, and `0.1.0` (`dbbaf0a`) as the first acceptance; extraction checks, actual main-window startup and close passed; current macOS execution and platform packaging remain pending. Keep artifacts local without a remote; Linux comes later |
| P3-1 | Real shared Core compatibility gaps | Reproduce remaining register-limit and frozen-atob failures minimally, then choose an upstream fix or an explicit limitation; distinguish failed sites from client defects; functional Core releases update both client pins and contracts |
| P3-2 | Desktop video minimal loop | **Local fixture loop accepted** (Nekophage `78ee0e1`): actual Windows WebView HLS.js/fMP4/byte ranges/Referer/Cookie/frame readback, plus native MP4. The page's pause event persists progress; a fresh disk read and Continue Watching really restore fractional seconds. Synthetic progress injection is removed and failing probes exit nonzero. `30d460f` additionally completes kind selection, file/URL installation and persistence in normal source management: actual Windows native windows install two video sources, both remain selectable after process exit/restart, and playback restored from GUI-installed records passes HLS decoding/resume. Race cases cover kind collisions, disabled replacement and disk restoration. `0d8ce15` adds separate cancellable generations for search/pagination, details and play preparation. Controller cases with real Core/JS/slow HTTP verify replacement/provider-switch/closure cancellation, successful next reads, rejected late results and retained pagination queries; the Windows HLS window still actually decodes and resumes. List/detail loading state is separate, and an active media session survives search-window closure. Audio now uses an actual decoded-byte criterion: the manifest-declaration check from `8f1d812` is retired because a fixture can falsely claim AAC. The HLS.js path reads `18537` bytes and the native MP4 path `17802`; both video-only controls read 0 and fail the probe (`e27d5f7`, `9e2bdda`). This is still not audible output. **Unverified**: subtitles, PiP, macOS and live sites; DRM/sniffing/DASH explicitly return unsupported errors. The new fixes are not in the old `7dc3051` portable package |
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
