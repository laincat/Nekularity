# Nekularity current status

[简体中文](STATUS.md) | English

This page keeps only the current build, verified behaviour and live evidence pointers. Historical release diaries (0.2.x–0.4.8), old Core pin moves and legacy segmented-transfer notes live in Git history and GitHub Releases. Still-unverified device or account boundaries live in [UNVERIFIED.en.md](UNVERIFIED.en.md), and external handoff steps live in [HANDOFF.en.md](HANDOFF.en.md).

## Current build and baseline

| Item | Current state | Evidence / notes |
|---|---|---|
| Latest public artefact | `v0.4.9` / build `31` (`01016b5`, Core `2bafd88`) | Release CI `42578286568`; IPA 29,963,615 bytes, SHA-256 `b75fa0ea178f7786f3b92e764054172a1255bf38cd17d0a35e17952a0d0be70c`; all three AltStore entries (GitHub Raw / CNB / Release) synced (`42582601315`) |
| Latest full Apple CI run | `9b64e1a` (default-HTTPS ATS + `CleartextPolicy`) | CI `42743715195` **success**: Kit **509 tests / 87 suites**, simulator UI **34 PASS / 0 FAIL / 0 SKIP**, Magpie loopback fixture passed |
| Dependencies and Core tracking | Core pin removed since `e353650` (tracks upstream `main`); player engine `AetherEngine 7.62.0` | The public IPA is still `0.4.9/31`; subsequent changes reach public builds on the next release |
| Licence | LGPL-3.0-or-later with App Store / DRM exception | See root [LICENSE](../LICENSE) and [COPYING](../COPYING) |

## Verified capability map

| Area | Verified behaviour | Evidence pointer |
|---|---|---|
| Manga mainline and isolated storage | Source install/update, paged search, details/ratings, reader decoding and offline chapter reopen, shelf, download retry isolation, backup import/export and partitioned cookies | CI `42743715195` (Kit 509/87, UI 34/0/0) |
| Network policy (ATS) | HTTPS by default (`NSAllowsArbitraryLoads=false`), `NSAllowsLocalNetworking=true`, single host exception for `lrr.tvc-16.science`; `CleartextPolicy` blocks undeclared public HTTP before socket open | Commits `51b9c3d`, `9b64e1a`; CI `42743715195` (11 new unit tests + full UI) |
| Video playback and subtitles | `AetherEngine` clock advancement, source `Referer` forwarding, AVPlayer subtitle rendering/switching/off, 30 s HLS resume near 7 s | CI `42199314431`, `42743715195` (shared fixture `UITests/Fixtures/media/hls-subs/`) |
| Standard AI streaming | OpenAI Chat / Responses and Anthropic Messages stream incrementally with cancel and immediate header-level rejection (401 does not wait for body) | Commit `b81b52d`; CI `42193319262` (`ZZStandardAIStreamTests`) and subsequent full UI runs |
| Magpie native provider packages | Folder/archive install, Keychain credential isolation, device-code/form/API-key sign-in, model catalogue, streaming chat with truncation outcome, real local HTTP loopback acceptance | `CoreMagpieTests`, `scripts/fixtures/magpie-http/run.py`, CI `42743715195` |
| Download Live Activity | Active/failed/retry/dismiss state machine and Live Activity text mapping | Commit `969d2c2`; CI `42545229418` (Kit state-machine tests + simulator retry UI; hardware rendering unverified) |
| Themes and adaptive layout | Local HTTPS theme install and HTTP refusal, iPad wide layout and AX5 accessibility font sizing | `scripts/theme-fixture.sh`, CI `42743715195` (UI 34/0/0) |

## Evidence boundaries and next steps

- Simulator CI passes do not prove signed real-device installation, background/lock-screen playback, PiP, hardware ActivityKit rendering, physical speaker output, real accounts or live third-party sites; see [UNVERIFIED.en.md](UNVERIFIED.en.md).
- Windows development machines validate only documentation hygiene (`scripts/check-docs.sh`) and Swift syntax parsing (`scripts/check-swift.py`); Swift type-checking, `swift test` and App/UI builds are authoritative on macOS / GitHub Actions.
- Current architecture decisions and roadmap live in [ROADMAP.en.md](ROADMAP.en.md).
