# Still unverified boundaries

[简体中文](UNVERIFIED.md) | English

This page lists only the hardware, runtime, real-account and live-site boundaries that remain **unverified**. Behaviour already proven by CI unit tests or simulator UI tests is tracked in [STATUS.en.md](STATUS.en.md), and external device handoff steps live in [HANDOFF.en.md](HANDOFF.en.md).

## Real device and OS runtime boundaries

| Item | Existing engineering evidence | Still missing |
|---|---|---|
| Signed install and device launch | Unsigned IPA archive and simulator runs (CI `42743715195`) | Signed install on physical hardware, first launch and upgrade migration |
| Actual iOS 26 runtime | Primarily exercised on CI simulator / Xcode 27 runtimes | Verification on physical iOS 26 hardware |
| Background / lock-screen playback and PiP | Simulator loopback playback and resume; simulator reports `AVPictureInPictureController.isPictureInPictureSupported() == false`, so the PiP button never renders | Starting PiP on a real device, backgrounding/locking, and software-decode (VP9/AV1) PiP |
| Subtitles on AirPlay / external displays | In-simulator AVPlayer subtitle rendering, switching and off | Physical AirPlay and external display verification |
| Physical speaker audio | HLS fixtures have no audio track and only prove video clock advancement | Real audio-bearing media heard through device speakers/headphones |
| Download Live Activity hardware rendering | Kit state-machine tests and simulator failure-retry UI (`42545229418`) | Lock-screen / Dynamic Island presentation on hardware, background updates, denied permission and dismissal after retry |
| Notification permission and airing reminders | Kit scheduling tests and compilation | Real notification delivery after granting permission on a device |

## Live network, accounts and deferred services

| Item | Existing engineering evidence | Still missing |
|---|---|---|
| Public HTTP source compatibility | `CleartextPolicy` unit tests, `lrr.tvc-16.science` exception and loopback UI | Real feedback from user-installed public HTTP sources under default-HTTPS ATS |
| Real Standard AI endpoints | Simulator streaming output, cancel and 401 header rejection (`ZZStandardAIStreamTests`) | Live OpenAI / Anthropic streaming, `max_tokens` truncation notice, server-side stop confirmation and credential restore after relaunch |
| Real Magpie provider accounts | Local loopback HTTP fixture and mock-credential tests | User-authorized provider sign-in, token refresh, quota behaviour and relaunch restore |
| Media servers and external services | Model decoding, write-back logic and unit tests | Live Jellyfin / Emby / Plex server browse, playback and progress write-back; Bangumi token; TMDB key; Pixiv sign-in |
| Local file import and large-shelf device feel | Kit import / CRC / corrupt-store rescue unit tests | Physical-device `.cbz` / folder / video import and long-term large-shelf responsiveness |

## How to rerun engineering checks

On a machine with macOS, Xcode, Go and XcodeGen:

```sh
sh scripts/fetch-core.sh
sh scripts/verify-ios.sh
```

Pass `NK_UI_TESTS=1` to run the simulator UI suite as well (optionally with `NK_UI_SEED`, `NK_UI_SEED_REPLACE=1` and `NK_UI_ONLY`), or dispatch `.github/workflows/ios-release.yml` with `ui_tests` enabled. Report the commit hash, pass/fail/skip counts and device boundary; never treat simulator passes as physical-device sign-off.
