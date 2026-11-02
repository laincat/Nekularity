# Handoff for external conditions

[简体中文](HANDOFF.md) | English

Updated 2026-11-03. Only work that needs a device, an account, credentials or a publication destination appears here, together with what to record. Engineering still in progress is in [STATUS](STATUS.en.md).

## 1. One on-device iOS acceptance run

1. Subscribe AltStore / SideStore to `https://raw.githubusercontent.com/laincat/AltStore/main/apps.json` and install **0.2.9 (build 11)**; the build is unsigned, and the sideloading tool signs it on your machine.
2. After the first launch, confirm 我的 shows 0.2.9/11 and record the device model, iOS version and install method. Devices below iOS 26 cannot install it (minimum 26.0); record that failure separately, it is not a defect.
3. Record every item as device + version + action + expected + observed, with a screenshot where possible. **Do not** treat simulator results as evidence for this section.

## 2. Mobile actions and their criteria

**Downloads and Live Activity**: install a working comic source, open any comic's detail page and download one chapter; expect progress on the lock screen and in the Dynamic Island, changing to a finished state that does not linger.

**Offline reading**: after the download completes, enable airplane mode and open the chapter from 我的 → 下载; expect every page to turn without a network error. This is the promise of a download; the simulator covers it with `testDownloadedChapterReadsWithNoServer`, and a device still needs its own look.

**Playback, subtitles and resume**: open the 视频 tab's online source, search an entry and play episode 1; expect picture and sound (record the mute switch state), subtitle options for English/Chinese/Off, and a resume from the same position after leaving and returning. Record **picture-in-picture and background audio** separately: whether audio continues on the desktop and whether a PiP button appears.

**Retry after failure**: make a chapter download fail (for example by dropping the network mid-way), confirm the screen reports the failure, then retry and see it complete. The retry entry has no automated coverage, so only a device closes this one.

## 3. Accounts and media servers

**Bangumi**: sign in from 我的, open a show with airing information and confirm the calendar shows real data rather than an empty list.

**TMDB**: enter an API key and confirm the detail page shows a Chinese overview and cover; an invalid key must produce a readable error rather than an endless spinner.

**Standard AI**: enter an OpenAI- or Anthropic-compatible endpoint and key in AI, send one sentence; expect an answer and a working cancel. **Streaming** is not network streaming today: Core reports `stream: false` and returns the whole body, which the record has to say rather than calling it a stream.

**Magpie plugin**: install and sign in to a provider plugin, confirm the model catalog lists models, chat works and cancel works; refresh credentials, restart the app and confirm the session survives.

**Media servers**: provide a reachable Jellyfin / Emby / Plex with an account and confirm the server summary, library list and playback URL. Without a server this stays unverified; do not substitute fake data.

## 4. Signing, notarisation and publication

**iOS signed installs**: the IPA is unsigned. A directly installable signed build needs an Apple Developer account and provisioning profiles; until then the sideloading tool signs for the user.

**macOS distribution**: `scripts/package-macos.sh` produces an **ad-hoc signed** `.app` that only guarantees running on the machine that built it. Opening it elsewhere needs a Developer ID signature and notarisation, both of which need an account and credentials.

**Windows distribution**: the package is unsigned, so SmartScreen warns on first run; removing that needs a code-signing certificate.

**Nekophage remote**: the repository has no remote and local packages are not published anywhere. Public release needs a decision about where (GitHub Releases, an own site, or not at all), and that decision is yours.

## 5. What is already done without external conditions

The 0.2.9 release and AltStore subscription are verified; download isolation, retry, delete/clear races and manifest-versus-disk honesty all have unit regressions; the twelve desktop window probes pass at the latest commit; the macOS reading mainline and the ad-hoc bundle are verified; NSIS install and uninstall were checked on 0.2.7. Details and log paths are in [STATUS](STATUS.en.md) and [UNVERIFIED](UNVERIFIED.en.md).
