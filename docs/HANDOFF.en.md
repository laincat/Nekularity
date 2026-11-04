# Handoff for external conditions

[简体中文](HANDOFF.md) | English

Updated 2026-11-04. These items need the user's device, account or publication choice. Orca Worker accepted targeted download identity, accessibility layout and HLS Chinese/English/off behavior; three tested product repairs are in main fda33d1. Swipe/button exit persistence and page reopening with thirty-second HLS both pass targeted acceptance on the dedicated simulator; cross-process, background and physical-device behavior remain outside that scope. Engineering records are in [STATUS](STATUS.en.md) and [UNVERIFIED](UNVERIFIED.en.md).

## 1. Choose the correct build first

| Build | Status and use |
|---|---|
| Historical `v0.3.2` / build 14 / Core 4f213ff | Older release; it does not establish later Core 3be behavior or the Magpie sign-in binding fix |
| Candidate 3574346 / 0.3.2 build 14 / Core 3be57b5 | Unsigned IPA identity verified; product/test sources integrated at main 6eab317. It shares the public version number but is a different package and lacks later download/layout/gesture fixes |
| Historical 0.3.3 / build 15 / Core 3be57b5 | 736e364; older public build without the 0.3.4 image-integrity fixes |
| Published 0.3.4 / build 16 / Core 3be57b5 | 66454e8; CI, public IPA and all three AltStore endpoints accepted, 29,459,904 bytes; exact files accepted by Mac 436/81 and targeted UI 2/2 integrated |

The subscription entry is `https://raw.githubusercontent.com/laincat/AltStore/main/apps.json`. Check the actual subscribed version before installation. The public IPA copy and receipt are at `E:/Code/deliveries/2026-11-04-nekularity-034/README.en.md`; Windows artifacts remain at `E:/Code/deliveries/2026-11-04-image-mirror-fix/README.en.md`, and the updated ten/thirty-second local fixture is at `E:/Code/deliveries/2026-11-04-hls30/README.md`.

Minimum device OS is iOS 26.0. Signing is completed by the user's chosen sideloading tool or signing flow, with account authorization entered in its native interface. Record device model, OS, App version/build, Core pin, installation method, action, expected result and observed result. Simulator acceptance does not replace device evidence.

## 2. Device actions and required observations

| Item | Action and required observation |
|---|---|
| Downloads and Live Activity | Download one chapter of an authorized comic and observe start, progress and completion. Record lock-screen display, Dynamic Island on supported models and whether it remains after completion |
| Offline reading and download retry | Open a completed chapter from Downloads without network and turn pages. Separately make a test download fail; confirm the reason, retry after relaunch and removal of the failure after success |
| Playback/subtitles/resume | Use authorized captioned media or a local clip. Confirm picture, actual subtitle text and off state. Exit separately with the button and swipe gesture, recording persisted and reopened positions. The gesture fix requires the package containing it |
| PiP, background and lock screen | Start PiP on a supported playback route and confirm the window actually plays. Observe or listen after switching to Home and locking, then return. A button alone is not PiP acceptance; simulator results do not replace system transitions |
| Audible speakers | Use media known to contain audio and record volume/output device and sound actually heard. The HLS subtitle fixture has no audio, and decoded-audio counts do not establish human hearing |

Existing loopback fixtures are available only to processes on the same computer. A Windows 127.0.0.1 service cannot be used directly by another Mac or physical device. Device tests should use authorized reachable media or local imports; VPN, routing and firewall settings are not changed to bridge them.

## 3. Real accounts and deferred services

**Standard AI**: in the final accepted package, configure the user's chosen OpenAI/Anthropic-compatible endpoint and model. Verify models, a short answer, cancellation and credential persistence after relaunch. Standard AI UI currently returns whole responses; Core streaming support does not mean this page is wired for streaming. Whether a real service stops generation requires service or usage evidence, not only a local button state.

**Magpie**: sign in to a user-authorized real provider plugin and verify its catalog, first text, cancellation and supported credential refresh/relaunch behavior. Local fake credentials and the dedicated-simulator loop have separate evidence; they do not accept real accounts, quotas or billing. Credentials are not written to the repository or logs.

**Deferred items**: real Bangumi, TMDB, Pixiv and Jellyfin/Emby/Plex services require their accounts/servers. Trakt, online danmaku, production tooling and Linux remain deferred. These added capabilities are not automatic release prerequisites, and unimplemented capabilities are not attributed merely to a missing account.

## 4. Desktop external conditions

**macOS distribution**: the current c545212 0.2.7 arm64 package has verified version, archive round trip and ad-hoc signatures. Receipt: `/tmp/nk-c545-acceptance/packages/receipt.json`. Those checks do not establish Gatekeeper acceptance or behavior on another machine. Developer ID signing/notarization waits for the user's choice of that distribution method and the corresponding signing conditions; it has not been performed.

**Windows distribution**: current 0db2ead installation/uninstallation and data preservation, native search, English subtitles and prior 3.03-second restoration passed; the video crop matches the prior saved position pixel for pixel. Its foreground subtitle switch/off click was refused by USER_INPUT_ACTIVE and not sent, so new selection or cross-process off restoration are not accepted. Normal window closure is also not accepted for this run, whose cleanup terminated the process. Earlier c545212 normal closure keeps its commit attribution. The package has no publisher code signature. Local installation does not cover download reputation or publisher experience on target systems and cannot predict whether any individual machine will show a prompt.

**Windows foreground condition**: an idle Windows desktop, or user operation of the current test package, is needed for subtitle switch/off, normal exit and relaunch verification. Keep isolated test data and local fixtures; no real account is needed. Current-package evidence: `E:/Temp/nk-0db-installed-media/run-a7f2d847/receipt.json`.

**Nekophage publication destination**: the repository has no remote. Windows artifacts are in the local delivery directory and the Mac artifact remains on Laincat-Mini; no source or package was publicly uploaded. Public release waits for a user-selected destination, while local engineering acceptance can proceed independently.

## 5. Boundaries of existing engineering evidence

The complete iOS UI result **27 PASS / 0 FAIL / 0 SKIP** belongs to 9498b4c/Core 4f213ff, with 416 tests/76 suites. The earlier 23/4 skipped-test record is not the current baseline. Core 3be combination 3574346 has separate CI/IPA evidence, and its two signed-simulator AI loops have separate receipts. Three theme-link cases and eight light/dark portrait/landscape empty-state screenshots are recorded. Later targeted acceptance covers the single-column accessibility repair, reachable discovery/settings endpoints, ordinary two-column order and distinct same-title download entries after deletion; tested sources are integrated into main. Thirty-second HLS passed both exits and seven-second restoration. Twelve populated covers passed light/dark × portrait/landscape, and two dark labels measured 4.665:1 contrast. Offline-page positive/negative cases and serial negative→positive isolation also pass; exact tested files were integrated at a7b5fbd. Release 0.3.4 additionally contains the four hash-matched image-integrity files: Mac 436 tests/81 suites, targeted retry/offline UI 2/2, and accepted public CI/IPA/all three AltStore endpoints. See STATUS; historical full-suite counts are unchanged.

The current desktop pin is Core 3be57b5. c545212 has separate evidence for Windows installation/startup/exit, Mac player race tests, two-process saved-off restoration, Mac archive/signature and isolated native window closure. One AX click closed the window and PID78539 exited0; receipt: `E:/Temp/nk-c545-mac-transfer/normal-close-accepted.json`. Older full media/reading results retain their own commit attribution. Core GBK regression PR #3 passed three-platform Go, xcframework build and macOS/iOS simulator Swift smoke. With user approval its exact tree was integrated into single-commit main c0f0dfa and the PR closed. Only tests/documentation changed; functional release and client pins remain unchanged.
