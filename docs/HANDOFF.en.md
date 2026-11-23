# External-condition handoff checklist

[简体中文](HANDOFF.md) | English

This page covers manual verification steps that require a physical device, live accounts or external servers. Current engineering evidence lives in [STATUS.en.md](STATUS.en.md) and the full unverified boundary table lives in [UNVERIFIED.en.md](UNVERIFIED.en.md).

## 1. Confirm the build under test

1. Verify which build you are installing: the latest public release is `v0.4.9` / build `31` (`01016b5`, Core `2bafd88`). To test changes after `0.4.9` (such as default-HTTPS ATS or subsequent refactors), re-sign and install the unsigned IPA from that commit's CI run rather than testing new fixes on an older package.
2. Existing loopback fixtures serve same-host processes only and cannot be reached directly from a physical phone via `127.0.0.1`; use reachable media or local imports on hardware instead of altering VPN, routing or firewall settings.

## 2. Physical-device actions and pass criteria

| Item | Action and required observation |
|---|---|
| Signed install and cold launch | Install, launch, view/add a source, kill and relaunch the app, and confirm profile data and settings persist |
| Video resume and subtitles | Play a subtitled video longer than 10 s past 7 s, close and reopen it, and confirm playback resumes and subtitle switching/off is visibly rendered |
| PiP, background and lock screen | Start PiP and confirm active playback in the window; switch to Home Screen and lock screen, verify continuity and clean return to the app |
| Physical speaker output | Play media with a real audio track and confirm audible output and volume/route changes |
| Download Live Activity | Trigger a download and a failure-then-retry flow; observe lock-screen and Dynamic Island updates and dismissal after recovery |

## 3. Live accounts and deferred services

- **Standard AI**: the screen **already uses streaming** with early header-level rejection (`b81b52d` / CI `42193319262`). Verify model listing, incremental streaming, `max_tokens` truncation notice, cancellation and Keychain restore after relaunch against a real OpenAI/Anthropic-compatible endpoint; confirm server-side stop from provider logs or usage rather than button state alone.
- **Magpie provider packages**: install a user-supplied or template provider package and verify sign-in, refresh, catalogue, streaming first token, cancellation and relaunch restore without logging credentials.
- **Deferred services**: Bangumi, TMDB, Pixiv and Jellyfin/Emby/Plex require real accounts or servers; deferred plugin features such as online danmaku are not release blockers for this phase.
