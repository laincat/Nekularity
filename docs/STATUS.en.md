# Nekularity status

English | [简体中文](STATUS.md)

**Targeted iOS Magpie UI passed (2026-11-04)**: Orca Worker passed 1/1 in 78.729 seconds on dedicated simulator 72DFD602-9D8E-40BB-8F96-DA3668ABE7C7, based on d3672a8/Core 3be57b5. The missing sign-in button came from Keychain -34018 in an unsigned test build; CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- fixed that condition. A subsequent product defect saved successful sign-in credentials without binding the current Core, so models used default port 18797 instead of entered 52970. The fix calls core.setAuth after saving immediate/polled success. Both real-Core binding regressions failed on old code; the fix passed 15/15 related Mac tests plus App/UITests compilation. Actual UI sign-in, models, visible first text before tail release, stopping request 3 with peer_closed, and App relaunch retaining auth and completing 第一段 第二段🐾 all pass with refresh count one. Product SHA-256 7b54e432e5d4fa37fa4e359c53f078a125078310aaf4e8ee17638e1d1328bd8b exactly matches the Lead candidate; regression-source transfer is pending. Evidence under `/tmp/nk-d367-acceptance/ios-diagnostic/`: binding-fixed.log, ui-binding-fixed.log, ui-binding-fixed.xcresult, events.jsonl; Lead receipt: `E:/Temp/nk-magpie-binding/receipt.json`. This validates simulator-App auth persistence, not host Keychain or physical devices. Only package records were preloaded, so UI package import is not established. Earlier failure logs remain; the existing d367 CI artifact excludes this later fix.

**New-pin Mac real-HTTP integration (2026-11-03)**: Orca Worker mac-validate-2 passed 1 test/1 suite at Nekularity `d3672a8`/Core `3be57b5` through real URLSessionTransport→CoreHost/CoreStreamHost→gomobile CoreMagpie→loopback HTTP. Models, first text “第一段 ” before tail release, peer_closed for cancelled request ID 3, exact SavedAuth file persistence and a rebuilt instance completing “第一段 第二段🐾” all pass. Refresh count stayed one; four provider requests were authorized without Cookie. The SDK was built from a clean exact-pin Core checkout; macOS slice SHA-256: 24c00ca89b47cd80529063924f56d6a39f5304481174dca12712d0115e71f366.

Focused log: `/tmp/nk-d367-acceptance/evidence/acceptance-test-02.log`; events: `events-final.json`; SDK provenance: `sdk-identity.log`; Lead receipt: `E:/Temp/nk-3be-candidates/mac-http-acceptance.json`. The first attempt only failed to compile test code because Swift 6 forbids Thread.isMainThread in an async context; the corrected test passed with no product Sources/ changes. Optional 503, full Kit, App build, iOS UI and Keychain were not run in this round. CI 41661859155 has now succeeded at exact d3672a8: Core build, executed Kit tests, App/UITests compilation and IPA packaging pass. Download verification on 2026-11-04 found an unsigned IPA of 29,455,876 bytes, SHA-256 7590d8ebcdf67b4fed8bd191e187f0337ba144cde6baf7f5fe033229fcd4f77c. App/Widget are both 0.3.2/14 with minimum iOS 26.0, and the App binary contains Core pin 3be57b5. Artifact digest and both ZIP CRCs pass; receipt/log: `E:/Temp/nk-ios-d367-ci/receipt.json`, `verify.log`. UI tests were compiled, not executed in this CI; publishing was skipped and AltStore was not updated. This does not establish device or iOS UI acceptance.

## Core 3be57b5 consumer candidate (2026-11-03)

Branch `update/core-3be57b5` starts from current main and updates scripts/core-version and CoreVersion.swift to published `3be57b5ceb848bb9623c090abc463764add14de4`. Core functional source `6129f59` passed all four jobs in CI `41631619233`; publication folded history without changing its tree. Windows pin/Swift parsing/Kit method-name contract checks pass, which does not establish Mac compilation. This branch now includes Swift response-metadata and chunk forwarding: product files match tested 77c2c6; the real-SSE test Git blob SHA-256 is a53f3bdabed91f1812282d7c7502541a96142f32f32ebb0bf4013bfe63a68e01, identical to the file with which the Orca Worker passed 428 tests/79 suites at Core 4f213ff. That old-pin result does not accept this Core 3be57b5 combination; the Mac result above now confirms an actual URLSession→Core Magpie→HTTP round trip; branch CI and IPA verification pass; targeted Magpie UI passes after the sign-in binding fix as scoped above. scripts/fixtures/magpie-http is copied from main 62cfde6 for host fixture use only. The standard AI screen still returns whole replies. Candidate `ea87eb5` passed Mac CI `41638119772`, including Kit tests and App/UI-test compilation. The unsigned IPA digest, both ZIP CRCs, App/Widget 0.3.2/14 and Core marker were verified; receipt `E:/Temp/nk-3be-candidates/ios-ipa-receipt.json`. UI/devices remain untested and main remains pinned to `4f213ff`. Logs: `E:/Temp/nk-3be-candidates/ios-*.log`.

**Desktop main integration (2026-11-03)**: the earlier confusion between Nekophage's working branch and main has been corrected. Before integration, actual main was `28be4bd`/Core `214e778`; inspection log `E:/Temp/core-magpie-first-chunk-evidence/desktop-main-ref.log`. The `fix/subtitle-record-cap` branch has now fast-forwarded actual main to `67fc877`, pinned to `4f213ff`, with the source branch retained. WebView probe isolation was ported and accidentally tracked Python bytecode removed. Seven checks and isolated Windows reading pass: two decoded pages, double-page layout, 55% progress and reopening at 1200, with only the current chapter's storage key. Receipt `E:/Temp/nk-desktop-integration/receipt.json`. The `a079ce7`/Core `b55c1a4` Windows package remains a separate candidate, pending new-pin macOS consumer acceptance. Nekularity main remains pinned to `4f213ff`.

Updated 2026-11-03.

## Core main b55c1a4, integrated build fix and next consumer pins (2026-11-03)

Cancellation fix `696a504` passed all three Go platforms and the Apple job in CI `41606605713`; artifact logs confirm eight CoreSmoke tests each on macOS/iOS Simulator. The downloaded SDK is 72,763,815 bytes, SHA-256 `2253fcac9be9c68859a022abee489b6ddef304f7a26a760cef8252cfeb53f593`, with verified CRC, three slice kinds and headers (`E:/Temp/core-696-apple/receipt.json`). The SDK embeds no Git revision; CI/artifact HEAD and digest establish attribution. Following Core's history-folding convention, main is now `b55c1a488746efc1454e4f4781e4e83dc577d187`. The full tree is unchanged by folding, and functional source matches tested `696a504`, differing only in evidence documentation. Log `E:/Temp/nk-magpie-loopback/squash-publish.log`.

Actual loopback acceptance also passes: after cancellation the server observes closed connections for public mobile API response-header waiting, chunk waiting and whole-response reading; the same runner then completes another answer. Old `2c9c83b` does not close the connection after cancellation. Logs `E:/Temp/nk-magpie-loopback/cancel-fixed.log`, `cancel-old-negative.log`. This uses a Go HTTP client, not Swift URLSession or UI. A separate failure is reproducible with `REQUIRE_PLUGIN_FIRST_CHUNK=1`: ChatNext text times out while the server has sent the first piece but holds the remainder; see `first-text-limitation-b55.log` in that directory. Plugin fetch waits for DoStream completion, so transport chunks are not incremental UI delivery.

Old-pin consumer candidate `af48d65` passed all of CI `41607054742`, including Kit, device App, UITests compilation and IPA packaging. The diagnostic artifact's generated project has no serve.py resource entries and retains clip.mp4. The actual IPA is 29,436,243 bytes, SHA-256 `1f4586d96bc9754f6161432df30d548e4e2ba161d5028ea0849b55941eb254c0`, with valid CRC; App/Widget both report 0.3.2/14 and minimum iOS 26.0, and the App binary contains Core `2c9c83b`. This is a branch validation package, without publication, AltStore update or UI-suite execution. Receipt `E:/Temp/nk-ios-core-2c9-ci/ipa-receipt.json`. Resource exclusions and build diagnostics are separately integrated into main; the two staged files match tested `af48d65` byte-for-byte (worktree line endings differ), without upgrading main's pin.

Both new consumer branches are `update/core-b55c1a4`: Nekularity `b39e6b0` passed CI `41612614917`: Kit tests, App/UITests compilation and IPA packaging. The actual IPA is 29,441,095 bytes, SHA-256 `860c8cf01a8031097e5d321f7c13ffb5ac176d22c9b1a615b2859e5ae61aba7e`; CRC/download digest pass, App/Widget both report 0.3.2/14 and minimum iOS 26.0, and the App binary contains the b55c1a4 pin. Receipt `E:/Temp/nk-ios-core-b55-ci/receipt.json`; no UI execution, publication or AltStore update. Desktop advanced from `e21b04c` to `a079ce7` after isolating development-probe WebView storage; seven checks pass. Its Windows installed package passed native search → HLS/captions → cross-process resume at 2.977162 seconds, authentication/exact Range and normal close/uninstall. Receipt `E:/Temp/nk-b55-candidates/installed-media-587be532/receipt.json`. New-pin macOS consumer acceptance remains pending. Receipt `E:/Temp/nk-b55-candidates/candidates.json`; check/version logs are in the same directory. Both consumer main pins remain `4f213ff`; old-pin window/UI evidence is not reused for the new candidates.

## Consumer compilation candidate for the new Core pin (2026-11-03)

Initial candidate `0ea786f` omitted the accepted HTTP-error fix. Integrating main `bf9d93d` in isolated worktree `E:/Temp/nk-ios-core-2c9` produced `5bc5b674d1477ac311a0470338e185e769fd1291`. Functional source differs from that main only at the two pin locations, `scripts/core-version` and `CoreVersion.pinned`, plus candidate status documentation. Windows documentation, Swift parsing, pin and Kit→Core call-contract checks pass. The contract check initially exited 3 because the isolated directory had no adjacent Core source; pointing `NK_CORE_SRC` at the clean `2c9c83b` worktree passed. This is not Mac compilation evidence.

The GitHub plugin dispatched branch workflow `41599831561`; its receipt verifies HEAD `5bc5b67` and event `workflow_dispatch`. It will run Kit tests, compile App and UITests, and produce an unsigned IPA. The branch does not satisfy the publication step's tag condition and will not create a release or update AltStore. Commit/local-check logs are under `E:/Temp/nk-ios-core-2c9-ci/`, and the CI receipt is `build/receipts/core-2c9-consumer-runs.json`. This remains a pending candidate, without claiming CI completion or UI acceptance. Address experiment `ad8e191` remains with the existing Orca Worker for independent retesting and is not integrated here.

## Magpie chat cancellation only stopped the handle (2026-11-03)

A real gap at `2c9c83b`: `Magpie.ChatCancel` removed the conversation handle and cancelled the chat's own context, while `Instance.Chat` issued requests under the instance context. After cancelling, a blocked whole-response `Host.HTTP`, `StreamOpen` or `StreamNext` kept running. The existing `TestMagpieChatCancelEndsIt` only checked that the handle disappeared, so it could not prove the request was closed.

The final candidate on isolated branch `fix/magpie-chat-cancel` is `696a5049a372e22ca0e639c103258bf38cfffb55`; CI `41606605713` has started at that verified HEAD, with results pending. It starts from public-entry negative regressions. `mobile/magpie_chat_cancel_test.go` uses Core's own `openai-compatible` template and the real `mobile` API, with hosts blocking in HTTP or `StreamOpen`; before the fix neither received `CancelHTTP`/`StreamClose` (`E:/Temp/nk-magpie-cancel-evidence/before.log`). The fix:

- Each chat owns its runtime. `ChatCancel` cancels its context and closes that instance instead of relying on the shared instance context. The shared instance still serves `Models`, sign-in and usage.
- A refreshed credential is written back to `Magpie.auth`, so the independent chat's next `auth.get`, later chats and existing model/sign-in hooks all see it; the provider bound to the runtime must still match.
- Instance creation builds without holding the lock and rechecks `closed` plus any existing instance on registration, so only one shared instance is retained after concurrent creation and nothing is registered after close. `ChatStart` registers its handle before launching the goroutine so `Close` can see and stop it, and event writes respect cancellation instead of blocking on an unread channel.

Five targeted race cases pass afterwards. `mobile/magpie_chat_lifecycle_test.go` covers cancelling one chat without stopping another, later chats continuing, an existing model hook reusing the refreshed credential (refresh happens once), and a blocked `StreamNext` being closed (logs `focused-after.log`, `chat-lifecycle-fixed-host.log`). That covers all three blocking stages plus refresh and isolation against the real package template. The supplementary case first failed because its host compared `Authorization` case-sensitively; the host now follows HTTP header semantics and the original failure log `chat-lifecycle.log` is kept.

The full `go vet ./...` and `go test -race -count=1 -json ./...` with real package fixtures pass: 22 packages, 559 PASS / 0 FAIL / 1 SKIP at top level (`race.log`, `race-summary.json`; the SKIP is `TestRealSourceWnacg` with `VC_WNACG_JS` unset, not a pass). The execution channel is Windows with fake hosts and local third-party package fixtures, not iOS UI, devices or a real vendor, and no client pin changed.

## The new-pin branch CI passes only up to the App build (2026-11-03)

Branch workflow `41599831561` at `5bc5b674d1477ac311a0470338e185e769fd1291` has a terminal **failure**. Checkout, Go, XcodeGen, pinned Core build, repository checks, Kit tests, project generation and the unsigned device App build passed; the failing step is “Compile the interface tests” with exit code 65, which skipped IPA packaging and artifact upload. The publication step did not run because this is not a tag.

Whole-job log download was refused by the GitHub plugin's address safety check (not bypassed). Check-run annotations only mention Node 20 deprecation, exit code 65, a missing Go cache and macOS queueing, with no compiler error line. The failure point is therefore the UITests `xcodebuild build-for-testing` step, but **the specific compile error is unknown**: it cannot be attributed to candidate code, test sources or the CI environment. Kit tests and the device App build passed, so Kit and App compilation are not the failure.

This candidate does not meet the “regression passes before release” condition; main and published packages still use `4f213ff`. Subsequent source review found both `Fixtures/theme/serve.py` and `Fixtures/standard-ai/serve.py` under the recursive UITests source entry. XcodeGen defaults `.py` to resources, giving them the same flat output name. Candidate `af48d652f260b4a8e58e0f6b86c4237d6717ce3c` excludes these host scripts while retaining `clip.mp4`, and preserves the UITests build log, xcresult and generated project as an artifact with pipefail retaining the actual exit code. YAML/document checks pass; log `E:/Temp/nk-ios-core-2c9-ci/resource-fix-checks.log`. New CI `41607054742` has started at that verified HEAD, without claiming the original exit-65 cause is proven by logs or the new compilation has passed.

## Core pin tooling preserves historical evidence (2026-11-03)

The old `set-core-pin.sh` globally replaced the old Core hash in both STATUS files, making prior test records appear to have used the new Core. A temporary repository reproduced both incorrect rewrites; log `E:/Temp/nk-pin-evidence-before.log`. The script now changes only `scripts/core-version` and `CoreVersion.pinned`, reuses `check-core-pin.sh`, and leaves historical documents intact. New candidates and acceptance records should be added explicitly through `update-pair.py`. Regression checks preserve document bytes and Swift line endings, prove repeated updates are idempotent, pass `--check` and reject invalid input without writes; log `E:/Temp/nk-pin-evidence-after.log`. This tooling fix does not upgrade the client pin itself.
## Standard-interface HTTP error fix integrated (2026-11-03)

The reply-error fix at `bb77b5d` is integrated into main through `9af6148`: `StandardAI.reply` previously treated HTTP 401/503 and provider errors inside HTTP 200 as ordinary assistant replies; it now throws `StandardAIError`. The Orca Worker passed `swift build --build-tests`, four targeted cases and the full **425 tests / 78 suites** on Mac. Restoring the old implementation made two error cases fail. Mac evidence is under `/tmp/nk-ai-http-evidence/`, including `full-swift-test.log` and `negctl-filter.log`. The four tests use real Core/URLSessionTransport with URLProtocol replacing the network, covering success across three protocols, credential headers, disabled cookies, HTTP/in-band errors and catalogs. Each request owns a host and temporary store without Keychain access. This establishes Kit regression coverage, not the standard-interface HTTP/UI flow, and is absent from published v0.3.2.

`UITests/Fixtures/standard-ai/serve.py` is a loopback-only whole-response HTTP fixture with normal/held bodies, HTTP 401/503 and in-band errors. Windows has exercised actual catalogs, all three replies, errors, TCP peer closure and body release; logs `E:/Temp/nk-ai-fixture/verification.log`, `events.jsonl`. Logs omit credentials and prompt bodies. This implements neither streaming nor credential refresh and does not establish Swift-client/UI acceptance. UI automation still needs isolated test settings and Keychain namespaces.

## Standard-interface address entry disagrees with the request path (2026-11-03)

The Orca Worker receipt for `44786f2` reports successful Kit/App/UITests compilation, five failed input checks and zero fixture requests; Mac logs are under `/tmp/nk-fix-evidence/`. Subsequent `ad8e19143bc346d09bbd6211bfce374cb6815611` also passed `swift build --build-tests` (13.95 seconds) and App/UITests compilation. The Worker reports five application-view passes for typing, clear-and-paste, rewriting, slow entry and relaunch read-back, while offline plist JSON reads all lack one `/`. These are different observations; whether the disagreement originates in the app, preference reading or the test driver is unresolved. They do not establish cfprefsd as the cause or justify discarding the disk observation.

Model listing still fails at `ad8e191`: the screen displays target `http://127.0.0.1:63640/v1`, but listing after saving a fake key reports `aiapi: the API root has no host`, with zero fixture requests. Three-protocol replies, cancellation/peer_closed, 401 and fake-key catalog access after relaunch remain unaccepted. Mac evidence under `/tmp/nk-fix2-evidence/` includes `build-tests.log`, `app-build4.log`, five `url*.log`/xcresults and `full.log`/`full.xcresult`; temporary driver SHA-256 is `28ba5e27ba723a4d80ea6361913188acb6a0afc2ed94f59429b43d519e7c4f5c`. Acceptance is limited to display/clear/relaunch behavior reported by that driver, not correct request configuration.

On Windows the Lead exercised public `mobile.Core.BuildAIModelsRequest` from the same `4f213ff` source in 18 combinations (three protocols × three address forms × plain/escaped-slash JSON). Complete addresses always construct the correct `/models`; `http:/127.0.0.1:63640/v1` reproduces `no host` exactly; `/v1` instead reports `must be http or https`. Log `E:/Temp/nk-ai-root-diagnostic/core-4f-boundary.log`; temporary reproduction source `main.go` is in the same directory. This verifies the Go construction boundary, not the Apple bridge or UI.

Neither a per-keystroke save/redraw race nor the button taking a shortest intermediate snapshot has been directly measured. Next, inspect the temporary driver's input, clearing and relaunch flow on the same dedicated simulator and compare UTF-8 bytes of field text, addressDraft, config/snapshot and baseUrl in wireJSON to find the first divergence. Record only the local fake address, never keys or complete config JSON; do not inject preferences or relax URL validation to obtain a pass.

## Standard-interface cancellation fix integrated (2026-11-03)

Main incorporates the three Swift files from `77b969f`, byte-identical to the Mac-tested code; other integration differences are documentation only. The Orca Worker passed `swift build --build-tests` (14.79 seconds), **421 tests / 77 suites**, and five targeted regressions at that commit. App + UITests then passed `xcodebuild build-for-testing`, with explicit compile records for `App/StandardAIView.swift` and `StandardAIRequest.swift`. The existing generated project was reused; `project.yml` matches `9498b4c`, without claiming a fresh XcodeGen run.

Catalog and reply requests now share an owned cancellable task. Stop, protocol/address changes, key updates and disappearance cancel the actual operation; late results cannot overwrite a replacement. Negative controls are qualified: removing only the success guard still passes 5/5 because generation checks remain; removing both the guard and cancellation's generation advance fails the late-answer assertion, while removing generation commit validation fails two replacement cases. Restoration leaves a zero-byte diff and passes five cases again. Logs under `/tmp/nk-77b-evidence/`: `build-tests.log`, `swift-test.log`, `app-build.log`, `build-evidence.log`, `diag2-filter.log`, `diag3-filter.log`, `filter-restored.log`.

This is Kit execution and App compilation evidence, without a real HTTP/UI loop on the standard-interface screen or real accounts. The fix is absent from published `v0.3.2`; that release's 416/76 and full UI 27/0/0 retain their original commit attribution rather than becoming current-main UI results. The standard path still returns whole responses.

## 0.3.2/build 14 published and verified

Tag `v0.3.2` points at `76a1ccd68b4834d169e58610a339322e1c7e29b4`, differing from tested `9498b4c` only in acceptance documentation. Release CI `41578147149` reports success on all 13 steps: Build pinned Core, Check the tree, the kit's unit tests, Generate project, Build unsigned device app, Compile the interface tests, Package unsigned IPA, upload-artifact and Publish IPA, across 04:26:35–04:50:49 UTC. The GitHub plugin refused to download the whole job log (its address safety check resolved to a private/internal address); that was not bypassed, so CI conclusions here rest on job/step API states rather than log text.

Release asset check (direct download, `E:/Temp/nk-ios-032-release/ipa-verification.log`): HTTP 200, **29,418,522 bytes**, SHA-256 `f59afe889def90131a8994a59a92571b6acc823679431d37c16c032f29bc8737`, matching the recorded asset size and digest; the zip passes CRC; `Payload/Nekularity.app/Info.plist` and `NekularityWidgets.appex/Info.plist` both report **0.3.2/14, minimum iOS 26.0**; the app binary carries Core pin `4f213ffbd51cfa22ef032a4279a04efb71b36283` and no longer contains the old `8e14aade75f5`. Receipt `E:/Temp/nk-ios-032-release/ipa-receipt.json`. The package is unsigned, so signed installation and devices stay outside this check.

AltStore workflow `41582051344` (manual `update-source.yml`) succeeds end to end; `apps.json` at commit `468761a5d267292d5742aa11de676e6052fb917c` lists Nekularity at **0.3.2/14** in both the stable track and the first flat version, 29,418,522 bytes, with download and icon on `v0.3.2`; a ranged IPA request returns 206 with `Content-Range: bytes 0-1023/29418522`, and the icon answers HTTP 200 (443,517 bytes, `image/png`). The cnb.cool mirror and the `releases/download/latest` entry already serve 0.3.2; `raw.githubusercontent.com` returned 0.3.1 on the first check and served 0.3.2 about twelve minutes later, which is same-host CDN caching rather than a repository mismatch (all three entries now read 0.3.2). Evidence: `E:/Temp/nk-ios-032-release/altstore-after.json`, `apps-468761a.json`.

## 0.3.2/build 14 combined-tree acceptance

The combined tree `9498b4c7c80ce6e4edcdf5c0b5e9afc5c065d4bd` is accepted on the Mac through Orca Worker `mac-validate-2` and integrated into main: Core `4f213ff`, archive release and strict local-search regression pass at the same commit. `swift build --build-tests` passes in 14.30 seconds, `swift test` passes **416 tests in 76 suites**, and one complete UI execution produces **27 PASS / 0 FAIL / 0 SKIP** in 722.577 seconds: 23 main, three theme and one three-column cases, confirmed by the xcresult summary. Logs under `/tmp/nk-949-evidence/`: `build-tests.log`, `swift-test.log`, `app-build.log`, `full-ui.log`, `counts.log`, `xcresult-summary.json`. This is one combined-tree run rather than an aggregation of the separate branch results below.

The built simulator App/Widget both report **0.3.2/14, minimum iOS 26.0**, with bundle IDs `com.laincat.nekularity` and `com.laincat.nekularity.widgets`. `xcodegen generate` could not run because the command is missing on that Mac. The Worker reused the existing generated project and changed only eight version-setting values; App/UITests compilation and runtime checks passed. Release CI has since regenerated from `project.yml`, built device Release and packaged the IPA; download, size, packaged versions, Core pin and AltStore are all verified in the section above. Release commit `76a1ccd` differs from tested `9498b4c` only in acceptance documentation; subsequent main adds the standard-interface cancellation fix, whose evidence is recorded separately above.

Actual Core HEAD/pin is `4f213ffbd51cfa22ef032a4279a04efb71b36283`; Vendor matches the original 98e output tree digest (`83158a56862851cac804695c720c3a14ea553f1efdb9c17e2461d81cf456efbb`). macOS slice SHA-256 `69284254554cbec08a35860a8cb50c86a439c030a26dd0e1fd65343ade6b4840`, simulator slice `ca54af50dad6e26d1b0931c6627ec8611df45942b2630594a0717e77312d76bf`; full record `/tmp/nk-949-evidence/vendor-sha256.log`. The theme service reused the existing CA without adding/removing trust entries: four HTTPS requests including preflight, zero HTTP requests. The three old CAs remain absent; retained `C0E33FBD155EF2C9…` expires 2026-12-03 02:52:02 GMT. Services are stopped and the certificate directory retained.

The Orca Worker reconciled the old `1888cd3` full UI logs: **27 PASS / 0 FAIL / 0 SKIP**, 722.784 seconds, comprising 23 main-class cases, three theme cases and one three-column case. The xcresult summary agrees: total 27/passed 27/failed 0/skipped 0. Logs: `/tmp/nk-1888-evidence/full-ui.log`, `counts.log`, `xcresult-summary.json`. A separate theme 3/3 run at the same commit remains separate, not added to 27. The earlier 23/4 at `95818c5` is historical rather than the latest full regression.

At `ed09c82`, `swift build --build-tests` passes in 14.87 seconds, the complete **416 tests/76 suites** pass, and sharing 3/3 plus download-write 14/14 pass. Temporarily restoring the strong capture fails the two archive/loader-release assertions as expected; restoration passes with a zero-byte diff. Both download UI cases pass without skips: failure retry in 50.642 seconds and offline reading without a server in 36.928 seconds. Evidence under `/tmp/nk-ed09-evidence/`: `build-tests.log`, `full-swift-test.log`, `negctl-test.log`, `negctl-restored-test.log`, `downloads-ui.log`.

At `61197f8`, Core `4f213ff` passes the Swift build in 14.62 seconds and App/UITests compilation. Valid-fixture search passes in 24.823 seconds; deliberately throwing a fixture search error exits 65 and FAILS in 80.121 seconds with `Callback Probe is local and must return Probe Comic`, without SKIP or environment/build errors. The restored seed matches the original valid seed byte-for-byte, the case passes again in 23.027 seconds and the worktree is clean. Logs: `/tmp/nk-611-evidence/valid.log`, `negctl.log`, `fixture-search-failure-tree.txt`, `restored.log`. This verifies correction of the old site-limitation skip condition.

CA state is reconciled by fingerprint: the three old CAs (SHA-256 prefixes `3D1895C2E4984B91`, `FBCE77CD0660BC0E`, `38C95A8619A02359`) are absent from this dedicated simulator's active trustd store. `simctl keychain reset` did not remove them and is not evidence of successful cleanup. The current store contains five system roots plus the new `1888cd3` CA (prefix `C0E33FBD155EF2C9`, expiring 2026-12-03), so it is not described as free of test CAs. Removing the old CAs made the request fail with zero fixture requests; log `/tmp/nk-theme-after-removal.log`, original store backup `/tmp/nk-truststore-backup-102519.sqlite3`. The combined regression reused this valid certificate without resetting or editing the trust database.

## Mac acceptance of Core pin `4f213ff`

Orca Worker `mac-validate-2` reran `scripts/fetch-core.sh` at branch commit `98e2e76f16c42b097a263cd6f0d1227708da8440`. The generated xcframework and `build/core` HEAD match `scripts/core-version`/`CoreVersion.pinned`: `4f213ffbd51cfa22ef032a4279a04efb71b36283`. `swift build --build-tests` passes in 15.68 seconds, `swift test` passes **415 tests in 76 suites**, and `xcodebuild build-for-testing` passes. The count is 415 rather than 416 because this branch does not include the download lifetime test from `ed09c82`; that fix is not accepted by this result.

After rebuilding the five-source seed with `make-seed.py` and checking it with `check-seed.sh`, four simulator cases pass without skips: `testSearchReachesDetailWithTags` 23.090 seconds, `testCategoryPageListsItsPartsAndComics` 27.658 seconds, `testBrowseLoadsSections` 25.720 seconds, and `testVideoPlaysTheSourcesClip` 29.073 seconds. Logs under `/tmp/nk-98e-evidence/`: `fetch-core.log`, `build-tests.log`, `full-swift-test.log`, `app-build.log` and `core-ui.log`. The tested commit is `98e2e76`; integration differs from it only in documentation. These four cases do not replace the full 27-case regression or device/account validation. Published 0.3.1 still contains pin `8e14aad`; no new release was made.

The Worker also invoked `URL`/`URLSearchParams` from a temporary fixture: the new Core passes in 22.561 seconds; the original fixture passes on old `8e14aad` in 21.983 seconds, but adding the URL call is reported as `XCTSkip` with “network or site limit” by the search guard in 112.395 seconds. This is a test defect that treats a local regression as a site problem, not compatibility success on old Core. Logs: `/tmp/nk-98e-evidence/urlprobe-4f213ff.log`, `plainprobe-8e14aad.log` and `urlprobe-8e14aad.log`. The probe was restored, Core/Vendor returned to `4f213ff`, the worktree is clean, and the restored search passes in 21.623 seconds. The search skip condition will be fixed separately without changing these counts.

## Host signatures cross-checked

All 21 `CoreHost` methods were compared against the Swift host implementation in Core's `apple/CoreSmoke`, which CI really compiles and runs: methods returning an object import as `(params…, error: NSErrorPointer) -> String`, while `void`/`Bool` methods import as `throws`. So `http(_:error:) -> String`, `saveData(_:dataKey:valueJSON:) throws`, `writeClipboard(_:) throws` and `readClipboard(_:) -> String` are the shapes Nekularity already uses. Matching signatures is not compiling, though — the real type check still waits for `swift build` on the Mac.

Every Kit member the UI calls was checked the same way: `library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`, `core.search / searchOptions / explore / explorePages`, `shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`, `searches.add`, `store.loadSetting / saveSetting` all exist with matching parameters.
| Video | A video provider is a Core plugin (`video-js`, a Kazumi rule, or a builtin source); the client only plays it. `CoreClient.videoSearch/videoDetails/videoPlay`; the 视频 tab picks a provider, searches and pages; the detail screen groups episodes by the lines a site mirrors; picking an episode asks the provider for an address and hands it to **AetherEngine** with the `Referer`/`User-Agent` the origin requires (AetherEngine is an app-target dependency only, so `swift test` never pulls binary frameworks). An answer that only offers a page to sniff is reported as not implemented rather than shown as a black screen. **Not compiled yet, and never run on a device or against a real video source.** |
| Downloads | `DownloadStore` keeps a chapter's original bytes under `Downloads/<source>/<comic hash>/<chapter hash>/<page>.img` with a `manifest.json`; the addresses come from Core's `chapterImages`, and the bytes are fetched by `ImageLoader.raw`, which uses the same request rules and the same `onResponse` rewrite as the reader. `ImageLoader` asks the store before the network, so a downloaded chapter reads with no connection and the reader itself knows nothing about downloads. Long-press a chapter to keep it, the detail toolbar keeps the whole comic, and the shelf opens a 下载 screen showing the size and offering deletion; a row there opens the chapter directly, which with no network is the only way in — asking the source for a chapter list would mean asking the network to prove the network is unnecessary. **Not compiled on a Mac yet.** |
| Themes | A theme is **data, not code**: one JSON of accent, background, surface, corner radius and an optional forced scheme. Only follow-the-system ships (the two Miuix palettes were removed as unused); a user installs another by importing a JSON file, kept at `Themes/<id>.json`, with the id sanitised so it cannot escape the directory, and installing never changes the current choice. Settings picks a theme, shows download storage, and names the app and Core versions. It is applied once in the root view (`.tint` + `preferredColorScheme`) rather than per screen, because per screen is how a theme ends up looking half applied. **Not compiled on a Mac yet.** |
| On-device video library | The 视频 tab is split into **本机 / 在线源**. On the device side, `VideoLibraryStore` **copies** an imported video into `Media/Videos` (no security-scoped bookmark: a bookmark into another app's container stops working when that app moves or replaces the file, and "my video vanished" is worse than spending the disk twice), keeps its duration and playback position, and offers 继续观看 only for something watched past 30 seconds and not finished. The player resumes with `AetherEngine.load(url:startPosition:)` and writes the position back when it closes, and a file deleted behind the app's back does not stay listed. **Not compiled on a Mac yet.** |
| Home blocks | Two kinds: **built-in templates** (继续阅读, 收藏, 最近搜索, 已下载, 本机视频, 视频源) and **source sections** — the recommendations, rankings and categories a source declares in `explore`, placed on the home screen and fetched through the same call 浏览 uses. The layout is a masonry grid (`MasonryLayout`, shortest column) whose **column count follows the available width**: two under 560, three under 900, four above — folding screens, split view and iPad all differ there, and a device name does not. Arranging works like a widget board: **long press** a card to enter it and the card wobbles, drag it onto another to take that place, and a 小/中 menu sets how many columns it spans (medium is a full row only on a two-column board). Taps inside a card do not navigate while arranging. **CI compiles it; the interactions have not been performed on a device.** |
| Dynamic Island | A downloading chapter becomes a Live Activity: three layouts designed separately — a ring and a percentage when compact, the ring alone at minimal size where digits are unreadable, and a title only when expanded. One chapter at a time, and a chapter already shown keeps the island until it ends rather than letting a second download rewrite the text. The wording and arithmetic live in the kit's `DownloadProgressText`, where macOS tests can reach them; ActivityKit is only in the app and the widget extension. `Activity` is not marked `Sendable`, so crossing isolation needs `@preconcurrency`. **It compiles; it has never appeared on a device.** |
| Library hub | Besides the media-server placeholder and the module counts, 资源库 now has four entries: **全源搜索** (opens search already scoped to 全部源), **书库** (shelf and favourites), **视频** (sources and on-device), **下载**. They live here rather than in the tab bar because the bar holds four, and a fifth folds the last one into 更多. **Not compiled on a Mac yet.** |
| Pixiv plugin | `sources/pixiv.js` is an ordinary JS comic-source plugin over pixiv's **anonymous** surfaces: rankings (`ranking.php?format=json`, daily/weekly/monthly/rookie/original), search (`/ajax/search/artworks`), a work (`/ajax/illust/{id}`) and its pages (`/ajax/illust/{id}/pages`). It deliberately does not touch `app-api`, which answers 400 without an OAuth bearer — a plugin should not hold a client credential, so bookmarks and follows are out of scope. Two measured lessons are in the comments: with a mobile UA, `ranking.php` answers HTML **even with `Accept: application/json`**, so the ranking leg needs a desktop UA; and `i.pximg.net` answers 403 without `Referer: https://www.pixiv.net/`, so `onImageLoad` always sends it. Verified on the desktop against the live site: 60 search results, details, 18 pages in 164 ms, five rankings with 250 entries, and tag taps reaching the source's search. On 2026-11-01 it was also run through **Core's JS engine against the live site** (`go run ./cmd/pixivprobe plugins/pixiv.js`: 60 results in 0.3–0.8 s), which shows the runtime path works and not only the desktop client. |
| Look | A shared surface built to the reference app's shape: `DesignSystem` (gradient canvas, `.glassCard()`, `Pill` buttons, `SectionHeader` with a chevron, `PosterTile` with the 看到 mm:ss strip and a progress bar, `StatValue` big numbers), plus a **floating capsule tab bar with its own round search button** — a stock `TabView` cannot draw that. Card radius and accent come from the chosen theme. Liquid Glass is used only on the navigation layer: the floating bar and its search orb share one `GlassEffectContainer`, capsule controls use `glassEffect`, and content cards stay solid — glass on content refracts against itself and costs contrast. Motion follows three rules: transform and opacity only, 0.2–0.35 s, and Reduce Motion is honoured; the selection pill moves with one `matchedGeometryEffect`. **CI compiles it; light and dark and folding shapes have not been looked at.** |
| Multi-account (environments) | `ProfileStore`: each environment owns `sources.json`, `cookies.json`, `shelf.json`, `searches.json`, `Magpie/`, `Downloads/` and `Media/` under `Profiles/<id>`; themes stay global because a look is not an account. Switching **rebuilds Core**, since Core is built from that environment's source records and cookie jar — anything less would be a cosmetic switch. AI sign-ins are Keychain entries per environment, with the first environment keeping the original service name so an upgrade does not silently sign the user out. Files from an install that predates environments move into the first one. Reached from the environment bar on 我的 and 设置 → 环境. **Not compiled on a Mac yet.** |
| Watch history | Watching writes into the same history as reading, so the calendar, the heat map and the day's counts all include it; a video row does not pose as a comic (no detail route that would open nothing), and an unknown length leaves the percentage empty rather than inventing one. Rewatching an episode only moves it to the front. | Unit tests (compile pending) |
| Batch source update | One action in the 漫画源 menu updates every source that has a URL, and one alert reports three outcomes separately: updated (name and old → new version), already current, and failed with the reason. A source installed from pasted text has nowhere to update from, so it is skipped rather than counted as a failure — that is a fact about how it was installed, not a fault in the source. | Unit tests for the summary; the fetching is unverified |
| Media servers | Jellyfin and Emby: address, account and password connect in one step; the token goes to the Keychain per environment and the server record holds no token. It lists libraries and items (runtime, year, synopsis, poster, watched position) and plays on demand, and watching still writes to the same history. A self-signed certificate is waved through **only for a local address**; a public host gets no exception. On the **native** path Plex speaks another API (XML with an `X-Plex-Token`), so the native client refuses it with a reason instead of sending a broken request.
**The route is not closed, though**: Core's video source API (`search.load` / `video.loadInfo` / `loadPlay`, with arbitrary headers) is enough to express Plex as **a
video source**, with no native code at all. Recording it earlier as "another API, so not possible" was the same mistake as the rating one — treating the interface
layer as the capability layer. There is no Plex server to test against, so it is not written. **Not yet tried against a real server.** | 11 unit tests over a fake transport |
| One media library | 资源库 → 媒体库 merges local files and every server's items into one list, searchable by **title and series**, with a continue-watching section and grouping by origin (local first, since it plays without a network). A server that cannot be reached affects only its own group instead of hiding the rest. | 5 unit tests over merging, searching, resuming and grouping |
| Playback experience | Speed (0.5–2×, against the engine's own cap), a **subtitle track menu** with an explicit off choice and labels that use the language rather than six rows all reading 字幕, **Picture in Picture** on the native route, and **remembered position**: this environment resumes where it stopped, while "finished" and "two seconds in" are not positions. The server's own position and this device's are both considered and the later one wins, so watching on the phone is not undone by a stale server position. PiP shows a button only where the engine publishes an `AVPlayer`; the software route is not wired. | 1 unit test for the resume rule; PiP needs a device |
| Reading calendar | 我的 → 阅读日历: a month grid shaded by how much happened each day, and tapping a day lists what was read or watched (comic rows open the details, video rows show progress). It shows the current streak, the total entries and how many days have any; months page; 今天 returns to the current month. **There are no airing reminders**, and that is a data fact: a comic source reports chapters that already exist with no broadcast date, and a media server reports episodes it holds. Inventing an "upcoming" list is not acceptable, so reminders wait for the metadata source in G9. | 5 unit tests for grid alignment, per-day selection, counting and streaks |
| Bangumi | The account side of watching shows: paste a personal token (Keychain, per-environment service name), read the five collection states, change state and a 0–10 rating, mark episodes watched, search anime by keyword, and the **weekly calendar** (public data, no sign-in). Divided with TMDB: one knows when western shows air, the other has the Chinese title and the episode list, and reminders merge both into one plan. The token uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`; no OAuth, because a client secret in an app bundle is not a secret. **Compiled and tested**; never connected to a real account on a device. See [BANGUMI](BANGUMI.en.md). | 18 unit tests (fake transport) |
| Metadata (TMDB) | A TMDB key or v4 token goes in 设置 (Keychain, per environment) and is **verified at save time**, so the app says whether it can find shows instead of failing silently later. When the media hub loads a server it matches series names against TMDB (at most six per load, cached ones are skipped), and the calendar shows 即将播出 with a note that the date comes from TMDB. A v3 key travels in the query and a v4 token in the Authorization header, detected rather than asked about; dates parse in UTC so an evening broadcast is not moved to another day by a time zone. **Needs a real TMDB key to try**; without one everything else works and the upcoming section is simply absent. | 9 unit tests over a fake transport |
| Danmaku and intro skipping | Danmaku comes from a **local file** (bilibili XML or DanDanPlay JSON) and needs no account. The player can toggle, load and clear it, and draws only the last four seconds with a cap on how many lines, because filtering the whole list every frame is how a phone drops frames. Intro detection is deliberately **not automatic**: openings differ in length per show and a wrong guess cuts the first line of dialogue, so the user marks the opening once per show (default 90 s) and later episodes offer 跳过片头; marks persist and are keyed by show. Online danmaku sources need a third-party account and are not wired. | 7 unit tests for parsing, the time window, tolerance, marks and persistence |
| Local comics | 资源库 → 本地漫画 imports an image folder or a `.cbz`/`.zip`; pages are ordered naturally (1, 2, 10 rather than 1, 10, 2), the reader pages horizontally and remembers the page it stopped on, and removing a comic removes its files. The archive is unpacked here: `ZipReader` reads the central directory and supports the two methods a comic uses (stored and deflate), while `__MACOSX`, dotfiles and non-images are not pages. It is deliberately not part of 漫画源: a local comic has no script, no network and no id a source could agree on. | 7 unit tests for both methods, filtering, ordering, import and removal |
| Tag translation | About seventy common English tags have Chinese names in a local table (no network); case, spacing and underscores are normalised. **A tag with no entry is shown exactly as written** — a wrong translation is worse than none, because it is an assertion about the content. The user can correct any tag, and a correction overrides the built-in table and persists. Tapping a tag still sends **the source's own spelling**; the translation is only for the reader. **Rating is not done**: Core has no rating capability at all (neither `mobile` nor `comic/js`), which is not something a client can add — it needs a Core binding and both clients re-pinned. | 4 unit tests |
| Diagnostics page | 设置 → 自检 reports version, Core, system and device; the environment (name, count, directory); sources (total, enabled comics, enabled video, restore failures); credentials as **presence only, never content**; content counts; and capabilities (PiP, whether background audio is declared, network policy), with one button that copies it as plain text. The point is that verifying a device stops being "install it and send me a screenshot" and becomes a block of checkable facts. The report contains no token, cookie or password. | 3 unit tests for format, failure counting and absence of secrets |
| Progress write-back | When a server item finishes (the player closes), the position goes back to the server through `/Users/{id}/Items/{item}/UserData` in 100 ns ticks, and local history keeps its own copy. The reason: the server is what the user's **other devices** read, so a position that exists only on this phone makes "continue watching" wrong elsewhere. A failed write does not interrupt playback, but it is reported rather than swallowed. | 3 unit tests for ticks, a missing user id and a rejection |
| Home cards | Three new blocks: **继续观看** (videos watched partway, with a progress bar), **即将播出** (when a TMDB date exists) and **本地漫画**. An arrangement saved by an older version keeps its order — new templates are appended — and a block the user had **hidden** is not switched back on. This also fixes a real bug introduced with watch history: 继续阅读 on the home screen and in the shelf handed video entries to a comic route, opening a comic that does not exist; both now filter on `isVideo`. | 7 unit tests, including the migration and the hidden-stays-hidden rule |
| Paging a big library | Listing server items is paged (200 a page, 600 at most) and stops on `TotalRecordCount`; a server that lies about the total ends at the first short page instead of looping. Requests now time out after 30 s, because an unresponsive NAS should fail rather than leave a screen spinning. | 2 unit tests for the two-page walk and the short-page stop |
| One progress rule | Ticks conversion, the 0–1 fraction, the 0–100 percent, the "resumable" test and the clock used to exist in four places — `MediaItem`, `ShelfHistory`, `VideoLibraryStore` and three screen-local `clock` functions — each doing its own arithmetic. There is one `PlaybackProgress` now, with table-driven tests for clamping, unknown lengths, NaN and infinity, rounding and formatting. One stricter decision came with it: **an unknown length is not resumable**, because finished and barely-started cannot be told apart. | Table-driven tests plus an assertion of the resume rule |
| Archive checksums | `ZipReader` verifies CRC32 (the standard table, pinned with the canonical `123456789 → 0xCBF43926` vector). A mismatch is reported as a damaged file instead of being decoded into a half-garbled page, which looks like a reader bug rather than a bad file. An archive written as a stream records a zero checksum, and that is skipped — the format allows it, so it is not an error. | 2 new tests: the vector, and damage detection including a flipped payload byte |
| Importing without freezing | Unpacking and writing moved to `Task.detached`; the main actor only appends to the list. A big archive shows 正在导入… instead of freezing, and progress is kept apart from the result alert — an in-progress message shown in an alert and then rewritten is a progress report nobody can read. | The four import tests are async now |
| A bad file does not eat data | When a store cannot read its own file it first **copies** it to `name.unreadable-<stamp>.json` and carries on. The reason is specific: the failure that loses data is not the read, it is the **next save** — recording a page, importing a comic, running one search — which writes the empty in-memory list over the file. What a user sees is "the upgrade lost my shelf", and the data was destroyed by a save rather than by a decode. The original stays where it was, so a later version or a hand repair can still read it. Covers the shelf, local videos, search history, the download manifest, local comics, media servers, intro marks, the glossary and the metadata cache. | 4 unit tests, including "a file that was never there is not corruption" |
| The migration crash window | A crash between moving the old data into `Profiles/<id>` and writing `profiles.json` made the next launch create a **new** default environment with a new id, leaving the moved data in a directory nothing pointed at — the same outcome as deleting it. Now the manifest is written before the files move, and a `Profiles/` directory with no manifest is **adopted** (the most recently modified one) with any files still at the root folded back into it. | 3 end-to-end upgrade tests: everything moves, a second environment steals nothing, an interrupted migration is adopted |
| Verification tooling fix | `seed-simulator.sh` wrote `<support>/plugins.json`, the pre-environment location. On a device that already has `profiles.json` the migration never runs again, so the seed landed where nothing reads it and the run reported "no sources". It now resolves the environment actually in use (the one holding `plugins.json`, else the newest) before writing. | `sh -n` syntax check; a real write needs a simulator |
| Docs against code | Each of the fifteen "implemented" claims in STATUS was matched to a symbol (all present), then each of thirteen features was checked for an **interface entry point** (all reachable); the interface suite is still sixteen cases; and no public type is unused by both the app and the tests (the twenty-nine matches are data models used inside the kit). Nothing needed changing — which is itself the evidence this round produced. | Read-only audit, no code changes |
| Rating displayed | The details screen shows the source's own score as five stars plus the number, with the like count and an already-liked mark. **No score means no stars**, because five empty stars claim a rating of zero. A score written as text is read as well (sources that scrape a page send strings), and an integer is a rating. **This corrects an earlier claim**: rating was recorded as blocked on a Core capability, but Core has sent `stars`, `likesCount` and `isLiked` in details from the start — the client model was dropping them, so no Core change and no release are needed. | 3 unit tests: a number, a string, and absence alongside an integer |
| Plex as a video source | `plugins/plex.js` implements Plex as **a video source** rather than a second native interface: XML parsing, the token as a query parameter, milliseconds to seconds, only film and show libraries (a music library listed there would offer things it cannot play), and the first `<Part>` as the playable path. **There is no Plex server here**, so only the parsing is verified: `node plugins/plex.test.mjs` passes five checks, including that regex punctuation inside an attribute is read literally. The requests are unverified. | 5 Node fixture checks |
| Airing reminders | When TMDB has an air date, 设置 can turn on a system notification for **9am on the air day**. Not the broadcast time: that is in the server's time zone and this device does not know it, so a date is honest where a time would be a guess. One reminder per show, soonest first, at most twenty (iOS caps pending requests); a date that has passed is not scheduled, because it could only fire at once and that reads as a bug; a resync cancels the extras before adding, and every identifier carries an `airing:` prefix so cancelling cannot reach a notification this app did not schedule. The planning is in the kit with 7 unit tests. | 7 unit tests; permission and delivery need a real device |
| Picture in Picture on both routes | The native route uses an `AVPlayer`; the software route uses `softwarePiPSource`'s `AVSampleBufferDisplayLayer` with `AVPictureInPictureSampleBufferPlaybackDelegate` (play/pause, the timeline, and skipping). The timeline and paused state are **refreshed into snapshots on the main actor** and the delegate answers from those, because `assumeIsolated` would trap if its thread assumption were ever wrong — and a slightly stale snapshot is all the window needs. | Needs a device; the software route only appears for a software-decoded source such as VP9 or AV1 |
| Subtitle overlay and the playback clock | Text cues are drawn from the engine's `$subtitleCues` (plain and rich text both come through `cue.text`); bitmap cues are **deliberately not drawn** here, because the software route already composites them into the frames it renders and a bad image draw is worse than none. This also fixed a real defect: the overlay read `position`, which only changed when the engine published a state change, so **danmaku and subtitles did not advance while playing**. Both follow `clock.$sourceTime` (~10 Hz) now, and the position reported on close reads `$currentTime` instead of stopping at the last state change. | Needs a device or a software-decoded source to verify |
| Engine signature self-check | All **28 AetherEngine symbols** the app touches were matched against the 7.53.1 sources: the throwing initialiser, the `load` signature, the public `LoadOptions(httpHeaders:)`, the transport calls, `setRate`/`maxSupportedRate`, `state`'s `case error(String)`, subtitle tracks and `subtitleCues`, `currentAVPlayer`, `softwarePiPSource`'s `layer`/`timeRange`/`setPlaying`/`skip`, `SubtitleCue.startTime`/`text`, and `AetherPlayerSurface(engine:)`. **Every one is present.** This cannot replace a build — Apple SDK signatures and SwiftUI constraints still need the compiler — but it rules out remembering the engine API wrong. | 28 symbols checked, none missing |

## Download archive isolation (2026-11-03, commit `2d9f555`)

The offline image index used only source + chapter + image address, with no comic id: two comics in one source that reuse a chapter id and an image address could receive each other's bytes, and deleting one chapter could drop the other's index entry. The key now includes source, comic, chapter and address across write, read, delete and reload; only reader pages are archived, so cover/thumbnail requests no longer match page bytes.

Mac unit runs by commit: `2317ea7` (regression case only) failed 2/2 with 6 assertion failures; `380bf89` (index fix) left 1 case failing, full suite 397 PASS / 1 FAIL; `2d9f555` (thumbnail guard) passes the targeted 2/2 and the full **398 / 398 PASS, 0 FAIL, 0 SKIP**. Environment: macOS 27.0.1 arm64, Swift 6.4.2, Xcode 27.2, reusing the same Core pin artifacts; logs under `/tmp/nk-dl-isolation-evidence/`. This covers temporary-directory and manifest unit regressions only, not devices, the downloads screen or network flows.

The manifest also stops claiming a chapter is downloaded on its own: files can be cleared by the system, skipped by a backup, or deleted outside the app. `9f15203` checks that each chapter's folder still exists after loading the manifest and drops the records that do not — neither the storage screen nor the reader treats it as local content, and the user can download it again. Nine write-path cases pass four consecutive runs and the full suite is **407 / 407 PASS**, logs under `/tmp/nk-dl-missing-evidence/`.

Partial folders are cleaned up too: a write killed by a crash or a dead battery leaves a folder no manifest record points at, and the storage screen only lists chapters, so that space could never be reclaimed. `afe1259` sweeps unreferenced chapter folders after loading the manifest in `init`, and drops comic folders the sweep leaves empty; the case finishes a chapter, plants a partial folder by hand and checks only the latter goes. Eight write-path cases pass four consecutive runs and the full suite is **406 / 406 PASS**, logs under `/tmp/nk-dl-sweep-evidence/`.

A downloaded chapter is not fetched again: `download()` used the in-memory `progress` map to decide a chapter was finished, and after a restart that map is empty, so the whole chapter was fetched a second time. It now checks the chapter record from the manifest before the failure-retry check; the `b3860ea` case counts fetches to prove neither the same session nor a fresh store makes a new request, seven write-path cases pass four consecutive runs and the full suite is **405 / 405 PASS**, logs under `/tmp/nk-dl-skip-evidence/`.

The concurrent delete and clear-storage entries were closed on 2026-11-03: `remove` used to return early when a chapter had no record yet, so deleting a chapter while it downloaded never invalidated the attempt, and `removeAll` walked only completed chapters, letting in-flight and queued downloads write themselves back after the user cleared storage. Invalidation now happens before the record lookup, and clearing covers the queue and running attempts. The regression case at `0049da3` failed four assertions on a Mac, which is exactly the first gap; after `920b94a` the six write-path cases pass four consecutive runs, the full suite is **404 / 404 PASS** and isolation stays 2/2, with logs under `/tmp/nk-dl-clear-evidence/`.

The retry/testability change is verified at `7550c12`: failed or deleted downloads can be requested again, the write path takes an injected fetch closure instead of requiring Core, the four new write-path cases pass, archive isolation remains 2/2, and the full suite is **402 / 402 PASS**. Logs are under `/tmp/nk-dl-retry-evidence/`. The two runs belong to different commits, so their numbers are not combined into one figure.

## Native navigation and consistent content surfaces (run on Mac; visual matrix deferred)

On a Mac, `5f15769` builds App and UITests and passes a complete formal UI suite: **26 cases / PASS 26 / FAIL 0 / SKIP 0** (`/tmp/nk-native-5f15769-evidence/full-ui.log`). This one complete execution covers native tabs, editing state surviving a section switch, Library module entries and the existing theme/discovery cases.

The later routing/reading fixes are verified separately at `81eb017`: its build passes, and `testLibraryModuleLinksOpenTheirPages`, `testReaderDrawsTheChaptersPage` plus temporary interaction probes (local/online reader return, Library and Discovery video entries) pass (`/tmp/nk-reader-81eb017-evidence/`). That commit's full suite was not run, so the three targeted cases are not a full-suite pass.

Following the user's request to prioritize underlying work, the light/dark narrow/wide and three-column capture matrix, Dynamic Type and Reduce Motion checks are deferred and incomplete; the known large-text truncation issue remains unfixed. The earlier full 24/24 at `5d9a5a1` stays separate from both rounds.

Following the user's report of a fragmented iOS interface, root navigation now uses system `TabView` with the system search role instead of a custom bar that conditionally replaces sections. TabView owns section lifetimes. Discovery, Mine, Library, Settings and Search share a page floor; content cards use theme surfaces or system grouped surfaces. Duplicate card padding and the custom bar's fixed 76 pt bottom spacing are removed, and the toolbar edit button returns to system styling. Theme background/surface tokens now affect these pages. The batch also fixes tilted cards outside editing/with Reduce Motion and cancelled cover tasks writing stale results. Library's comic/video source cards now open their pages; the server summary reflects configured records rather than always claiming no connection or missing implementation.

Existing UI cases now find native tab controls; new cases check editing discovery, visiting Settings and returning with editing intact, and opening both Library module links. Both rounds have now built and executed on a Mac (see the start of this section); no new release includes the batch yet. iOS 27 appearance and Liquid Glass rendering on a real iPhone remain unverified, and using system APIs does not establish on-device appearance.

## What a Mac has already run

**Latest full regression (2026-11-02, commit `5d9a5a1dfd5ce0e9d58fead6371d5cc4b3f842c4`, Orca Worker / Mac simulator)**: on the dedicated iPhone 17 Pro, the old app was uninstalled, reinstalled, launched to create an isolated profile and reseeded; Themes was empty before launch. The complete UI suite returned **24 cases / PASS 24 / FAIL 0 / SKIP 0** (`/tmp/nk-ui-full-5d9a5a1.log`). Invalid-theme selection preservation, HTTPS install/select/relaunch and HTTP refusal all passed, as did three-column geometry. The invalid-theme case installs its own baseline. Temporary services/themes are removed; the new CA lasts one day, expires around 2026-11-03 and remains in the dedicated simulator trust store. This is one complete execution, not an aggregation of earlier cases; devices, background behavior, real accounts and full three-column visuals remain unverified.

**The skipped video UI case runs on its own (2026-11-03, `95818c5` build)**: the cause was a seed without a video source. Seeding the repository's `UITests/Fixtures/video_probe.js` alongside the others (`--replace`, `plugins.json` 131,692 bytes, five sources, `video_probe` with `type = video-js`, `check-seed.sh` reporting `callback_probe matches … 5 source(s) seeded`) makes `testVideoPlaysTheSourcesClip` **pass in 29.600 s**, `Executed 1 test, with 0 failures`, along `在线源 → video.source → Video Probe → search probe → Probe Clip → Episode 1 → player`. This is a **targeted re-confirmation**, not a full-suite rerun: the 23 passed / 4 skipped result still belongs to the `95818c5` suite, and the next full run should read 24 passed / 3 skipped. One caveat, recorded as it is: the seed reused the one generated on 2026-11-01 with `seedgen` (each body checked byte-for-byte against the repository fixture) rather than being regenerated in this round.

**The theme-link fixture is in the repository with targeted execution evidence**: an Orca Worker ran `sh scripts/theme-fixture.sh 0A67B65C-9EB9-4504-B7C6-7A8EC74DA1A0` in the Mac worktree at `17ba4c5`: HTTPS install/select/relaunch, invalid JSON preserving selection and plaintext HTTP rejection **passed 3/3 with no skips** (`/tmp/nk-theme-fixture-run3.log`), using the 0.3.1 app build. The script serves loopback HTTPS on 18791 and HTTP on 18792, generates a 30-day CA and leaf at runtime, trusts it only in the chosen simulator, leaves the host keychain alone and never calls `simctl keychain reset`; certificates and private keys are not committed. That run recorded valid/invalid JSON requests and zero plaintext requests. This targeted result remains separate from the 27-case full suite; they do not form one 27/27 run.

`scripts/make-seed.py` (`65f086c`) rebuilds bodies, kinds and SHA-256 from repository comic/video fixtures while carrying real-site records from an old seed. With a freshly generated five-source seed the Worker separately passed the video case in **28.276 s** (`/tmp/nk-video-rebuilt-seed.log`). Local review additionally corrected the theme script failure path (`set -e` previously skipped the fingerprint receipt) and preserved CRLF bytes in the generator. Local checks exercise real TLS preflight and exit codes 0/42 using simulator and Xcode stubs; they are not iOS UI execution evidence.

**The full UI suite after the release (2026-11-03, `95818c5`)**: from a clean start (uninstall, reinstall, seed; img=0, `failures.json`=0, `manifest.json`=0, `plugins.json` 129,992 bytes, `check-seed.sh` reports `callback_probe matches` with 4 sources, port 18731 free) it ran **27 tests: 23 passed, 4 skipped, 0 failed** in 617 s (`/tmp/nk-95818c5-ui-fullsuite.log`). Groups: `NekularityUITests` 23 (22 passed, 1 skipped), `ZZThemeLinkTests` 3 (all skipped), `ZZThreeColumnTests` 1 (passed) — the full suite is 23+3+1, not 23.

All four skips are preconditions rather than failures: the video case found no video source among the four seeded ones (`the 视频 tab has no source picker`), and the three theme-link cases need an HTTPS/HTTP fixture outside the repository plus a test CA trusted in the simulator (`theme fixture is not listening on 127.0.0.1:[18791, 18792]`). UNVERIFIED already says a missing fixture or an expired certificate must not be recorded as a pass, so they stay skipped rather than being faked.

The same round captured **eight light/dark × narrow/wide screenshots** (iPhone 17 Pro 1206×2622, iPad Pro 13-inch portrait 1032×1376 pt) in `/tmp/nk-shots-95818c5/`; the iPad dark settings page shows 版本 0.3.1 at the bottom, matching the release. Two details are worth the record: iPadOS draws the five entries as plain buttons in a top bar, so the throwaway capture case failed on `tabBars` there and passed once it fell back to a label lookup; and the two devices are not showing the same content — the iPhone kept the state the suite left behind (it has reading history) while the iPad's older seed was replaced, so its discovery page shows the empty modules.

**`0.3.1` build `13` published and verified (2026-11-03)**: a failed download now **survives a relaunch** — the request and the reason go into `failures.json`, the row is still listed under "没有下载完成" after a restart, retrying uses the `fallbackFetch` the app installs, and a failure row can be swiped away on its own instead of clearing the library. `CoreError.readable` is idempotent too, so a message that was written down and read back does not turn into 源返回错误:源返回错误:. Tag `v0.3.1` points at `a6e4ad6`; the tested code is `76dba85` plus that prefix fix. Release CI `41539849288` passed with `Test run with 415 tests in 76 suites passed`. The release asset answers HTTP 200 and is **29,416,931 bytes**, SHA-256 `af5cc588c970e796f971b21777724362c9beac53fcd91f66e805fddafa162ecf`; unpacked, both bundles are `0.3.1`/`13` with minimum OS 26.0 and the app binary carries the pin `8e14aade75f5`. AltStore's `update-source` workflow `41543336622` succeeded, and `apps.json` lists `0.3.1`/`13` in both the stable track and the first flat version with size 29,416,931 bytes and download and icon on `v0.3.1`; the icon answers HTTP 200 (443,517 bytes) and a ranged IPA request returns 206 with 1024 bytes. The package is unsigned, so signed installation and devices remain outside this check.

**`0.3.0` build `12` published and verified (2026-11-03)**: a failed download no longer disappears — the chapter stays in the downloads screen under "没有下载完成", can be retried there, and its row on the detail page carries a warning — and the release also carries the network error attribution (a dead network is no longer reported as the source failing), the accent contrast assertion, and Core `8e14aad` (async rejections keep their error name). Tag `v0.3.0` points at `df11f01`, which differs from the tested `6037f6a` only in version metadata, the Core pin and docs. Release CI `41525488814` passed, and its log reads `Test run with 411 tests in 76 suites passed`. Downloading the release asset gives HTTP 200 and **29,393,130 bytes**, SHA-256 `8100da3764346d13f53321562e26b53336273c52e9b50d171a0d6a2395284e36`; unpacked, both `Nekularity.app` and `NekularityWidgets.appex` are `0.3.0`/`12` with minimum OS 26.0, and the app binary contains the pin `8e14aade75f563a95f50d4ec80be27bae0d02c63`. AltStore's `update-source` workflow `41535603457` succeeded, and `apps.json` lists `0.3.0`/`12` in both the stable track and the first flat version with size 29,393,130 bytes and download and icon on `v0.3.0`; the icon answers HTTP 200 (443,517 bytes) and a ranged IPA request returns 206 with 1024 bytes. It had to be dispatched by hand: the schedule is every fifteen minutes, yet nothing ran for over two hours after 0.2.9, so a release cannot rely on the cron. The package is unsigned, so signed installation and on-device behaviour remain outside this check.

**`0.2.9` build `11` published and verified (2026-11-03)**: this release carries the manifest-versus-disk fix (`9f15203`): a chapter whose folder is gone stops counting as downloaded, and both the downloads screen and the reader trust the disk. Tag `v0.2.9` points at `3bad666`, which differs from the tested code only in version metadata and docs. Release CI `41501079841` passed. Downloading the release asset gives HTTP 200 and **29,370,355 bytes**, SHA-256 `2076378ee48080f5922143b9a07fb9b62edab338587aea4439c5af6b028a5952`; unpacked, both `Nekularity.app` and `NekularityWidgets.appex` are `0.2.9`/`11` with minimum OS 26.0. AltStore's `update-source` workflow `41506082352` succeeded, and `apps.json` lists `0.2.9`/`11` in both the stable track and the first flat version with size 29,370,355 bytes and download and icon on `v0.2.9`; the icon answers HTTP 200 (443,517 bytes) and a ranged IPA request returns 206 with 1024 bytes. The package is unsigned, so signed installation and on-device behaviour remain outside this check.

**`0.2.8` build `10` published and verified (2026-11-03)**: this release carries the four download fixes (archive isolation by comic and source, retry after failure or deletion, the delete/clear-storage races, no refetch of finished chapters, and the sweep of partial folders). Tag `v0.2.8` points at `fbab48a`; the app, kit, UITests, widgets, Live target, `Package.swift` and Core pin (`214e7782`) match the tested code, with only version metadata and docs differing. Release CI `41490389867` passed (pinned Core build, kit unit tests, device build, UI test compilation, packaging, upload and publish all succeeded). Downloading the release asset gives HTTP 200 and **29,370,482 bytes**, SHA-256 `392c5d7a9d8e73f060ee04b8f4c7ca35966188b16d299a4122aeea00afe80159`; unpacked, both `Nekularity.app` and `NekularityWidgets.appex` are `0.2.8`/`10` with minimum OS 26.0. AltStore's `update-source` workflow `41495855498` succeeded, and `apps.json` lists `0.2.8`/`10` in both the stable track and the first flat version, with size 29,370,482 bytes, the download URL on `v0.2.8` and the icon on `v0.2.8`; the icon answers HTTP 200 (443,517 bytes) and a ranged IPA request follows the redirect to 206 with 1024 bytes. The package is unsigned, so signed installation and device behaviour are outside this check.

**`0.2.7` build `9` published and verified (2026-11-02)**: App/Widget report `0.2.7`/`9`; tag `v0.2.7` points to `90b98b07d3a07df1630379263bd976924bf70260`, whose App, kit, UITests, Widgets, Live, Package.swift and Core-pin sources match tested `5d9a5a1` — only version metadata and documentation differ. Release CI `41465697611` passed. Downloading the release asset returned HTTP 200 with **29,368,112 bytes** and SHA-256 `182f62cf2aea32d6b8183effd0f0f31aede1deeab4270ce02d22b6a12bc8b7f3`; the unpacked `Nekularity.app` is `0.2.7`/`9`, `NekularityWidgets.appex` is `0.2.7`/`9`, and the minimum OS is 26.0. The app executable contains the theme-link HTTPS rejection text, so this round's theme fix is in the package. AltStore's `update-source` workflow `41471135708` succeeded; `apps.json` lists `0.2.7`/`9` at 29,368,112 bytes in both the stable track and the first flat entry, with the icon pointing at `v0.2.7`; the icon returns HTTP 200 and a ranged IPA request returns 206. The package is unsigned; signing and on-device behavior are outside this verification.

**Subsequent full execution (2026-11-02, commit `9f7840f`, Orca Worker / Mac simulator, not passing)**: Theme unit tests pass 12/12 and plaintext-redirect refusal finishes in 0.015 s (`/tmp/nk-theme-9f7840f.log`). The UI receipt originally reported 24 cases / PASS 22 / FAIL 2 / SKIP 0 (`/tmp/nk-ui-full-9f7840f.log`), but its failure details name only two assertions in `testHTTPSInvalidThemeShowsErrorAndPreservesSelection`, with no second failing method. Failed-case and failed-assertion counts therefore still require reconciliation against the case list. This case demonstrably depends on a theme left by another test and passes alone after a successful install; `5d9a5a1` makes it install/select its own baseline, and the corrected full run at `5d9a5a1` now passes 24/24 from a clean container, as recorded above. `ZZThreeColumnTests` passes 1/1. An isolated rerun does not establish a full-suite pass.

**Historical full regression (2026-11-02, commit `8acbb7841509ffa637a1392d88d439d5f1e9aaa1`, Orca Worker / Mac simulator)**: the test target built and installed on the same dedicated iPhone 17 Pro; the complete UI suite returned **19 cases / PASS 19 / FAIL 0 / SKIP 0**, log `/tmp/nk-ui-full-8acbb78.log`. Long-press handle entry, changing a size then terminating/relaunching to read it back, the edit-button entry and update-all all executed successfully. This does not establish drag ordering, real-device Live Activities, background playback or real accounts.

**Drag and relaunch persistence (2026-11-02, Orca Worker / Mac simulator, target commit `7586982`)**: a new `testBoardDragOrderSurvivesRelaunch` passed on the dedicated iPhone 17 Pro (`/tmp/nk-drag-final.log`). The first implementation read the order through **duplicated identifiers** — each card's title and arrow carried `home.card.*` — so "move the first two" acted on one card and the assertion passed vacuously. After de-duplicating by first occurrence the result is meaningful: before `history, favorites, …`, after moving it to second place `favorites, history, …`, and after terminate/launch still `favorites, history, …`. Reading the app's preferences after shutdown cross-checks it: `homeBlocksV2` really is `['favorites','history',…]`, so this is not a visual reorder; the case moves the card back at the end. **The new drag case's first implementation passed vacuously by comparing one card with itself**; it was de-duplicated and rerun. This does not invalidate other cases in the earlier full suite.

The drag case was imported from the Mac's Git bundle with its 2,169 bytes and SHA-256 checked. Remote `validate/discover-drag-7586982` retains original commit `33be2af3767a02e438eaacef7405262015652e80`; main integrates it as `9b2b3e621219db4ee9dea3308d85af0a114eb5e7`. Author and Assisted-by are preserved, and the main test-file blob exactly matches the Mac-tested version. Windows `check-swift.sh` parsing passes; no UI ran on Windows. The 19/19 result is historical; the latest fully passing suite is the independent 24/24 execution at `5d9a5a1` above, not an aggregation of isolated cases.

**Three columns and theme HTTPS (2026-11-02, Orca Worker / Mac simulator, commit `5d7022d`)**: on an iPhone in landscape the scroll content was measured at **874 pt**; with the first three cards temporarily set to small, their de-duplicated titles sat at about **101, 347 and 590 pt**, three distinct columns. `testLandscapeBoardHasThreeColumns` passed in light and dark, and the layout and portrait orientation were restored afterwards. **This establishes that three columns occur**, but the captures are saved rotated and the dark one is partly clipped by the navigation area, so text legibility, truncation and the full visual layout still need another capture.

Theme HTTPS: a valid fixture theme landed in `Themes/p1-https-proof.json` and stayed selected after relaunch; invalid JSON showed "the data could not be read because it is not in the correct format" and kept the previous theme. **The negative case found a real defect**: an `http://` theme was actually downloaded and installed — the settings screen only checked `scheme?.hasPrefix("http")`, and `ThemeStore.install(from:)` validated the body but not the scheme. Fixed in `0e40eeb`: `ThemeSource.validate` requires exactly `https` with a non-empty host and runs in the shared install path before `fetch`; the screen now only checks link shape and shows the specific refusal. A kit test covers http, uppercase HTTP, file, hostless https and schemeless input and asserts the fetcher never runs. An Orca Worker subsequently verified HTTP refusal separately on App `a526add`: the alert requires an https address, the theme never enters the list, the HTTP server receives 0 requests, and the Themes directory gains no file (`/tmp/nk-p2-http-test.log`). The first unit-test build failed because it mutated captured `fetched`; after `9005dca` fixed it, the Mac executed 8/8 PASS (`/tmp/nk-theme-filter.log`). With redirect/404/size tests in `6bb7933`, the Mac executed 12/12 PASS, 0 FAIL, 0 SKIP (`/tmp/nk-theme-6bb7933.log`). That round's plaintext redirect case took about 21 seconds; `9f7840f` cancels immediately and asserts under five seconds. Its Mac Theme tests now pass 12/12 with 0.015 s refusal; the full UI did not pass and its counting discrepancy is recorded above. The corrected `5d9a5a1` full 24/24 receipt is now recorded above. These individual results are not added to the older full 19/19 result.

**Eight simulator captures (2026-11-02, App 0.2.6 / commit `7586982`)**: iPhone 17 Pro (402 pt wide) showing two discovery columns and iPad Pro 13-inch (1032 pt) showing four, each in light and dark for both discovery and settings. No horizontal overflow, truncated titles or overlapping controls were visible, and card text was readable in both appearances. **Three columns (560–899 pt) has no matching device or split-view scenario this round and is unverified.**

**Clearance at the end of scrolling (2026-11-02, Orca Worker / Mac simulator, App `211cd64`)**: build-for-testing and both iPhone/iPad installations passed. The worker swiped until the footer's coordinates remained unchanged twice, then inspected five captures: light/dark settings on iPhone and iPad, plus dark discovery on iPhone. Settings' 关于, version `0.2.6` and Core row, and discovery's final 视频源 card, are completely above the floating pill. The iPhone settings Core text ends near 748 pt and the pill starts near 774 pt (26 pt clearance); discovery content ends near 731 pt (43 pt); iPad settings Core text ends near 1264 pt and the pill starts near 1285 pt (21 pt). None of the five captures shows horizontal overflow or truncated titles; there is no evidence that more bottom margin is needed. Captures and logs: `/tmp/nk-bottom-211cd64/`. The iPad TMDB note is fully visible; on iPhone at the bottom it has scrolled behind the top navigation bar, so the bottom capture cannot establish that it is simultaneously fully visible. This receipt covers these simulator scenarios, not every layout or physical device.

Historical regression: missing seed data caused many skips on `c259f3f`; a fixed UUID and complete comic/video fixtures brought `2cf44e4` to 18/19 with no skips and long-press entry as the sole failure. `0f2a5a2` still failed; `8acbb78` removed `.draggable` before arranging and passed the full suite. Results from different commits were not combined into one full-suite pass.

**The `v0.2.6` release build (2026-11-02, commit `75869826c890a9e1e0208aa2b05b576f11394623`, run `41431641042`)**: **every step succeeded** on the macOS runner (build the pinned Core, tree check, kit unit tests, generate the project, unsigned device build, compile the interface tests, package the IPA, publish the asset). Release `v0.2.6` is published; `Nekularity.ipa` is **29,361,985 bytes**, `curl -L` returns **HTTP 200** with that same size, SHA-256 `c25a35851a8310a593bcac89f3d2205c7c8cdc6a2b349ad484dc70498c729ae2`. Unpacked and inspected: `Nekularity.app` is **`0.2.6` (build 8)**, `com.laincat.nekularity`, minimum iOS 26.0, and `PlugIns/NekularityWidgets.appex` is also **`0.2.6` (build 8)**, with the AppIcon files present. The interface evidence for this build comes from the same sources' full suite on `8acbb78` (19/19); the release build itself compiled and packaged but did not re-run the interface tests on a simulator. The AltStore source's `apps.json` is updated to **`0.2.6` (build 8)** with matching size, download URL, `minOSVersion` 26.0 and `releaseTag`, an icon pointing at the `v0.2.6` AppIcon, and the subscription entry `releases/download/latest/apps.json` returns **HTTP 200** with the same version.

**The `v0.2.5` release build (2026-11-02, commit `7a00580`, run 83)**: **all twelve steps green** on the GitHub Actions macOS runner — build the pinned Core, the tree check, the kit's unit tests, generate the project, the unsigned device build, compile the interface tests, package the IPA, publish the release asset. The `Nekularity.ipa` asset is **29,359,908 bytes**, `curl -L` returns **HTTP 200** with that same size, and the AltStore source's `apps.json` now lists **`0.2.5` (build 7)**; the subscription entry point `releases/download/latest/apps.json` also returns **HTTP 200** with the matching version.

That round proves "it compiles, it packages, it downloads, the source points at the right version". It does **not** mean the interface cases passed: this pipeline only **compiles** them (`xcodebuild build-for-testing`), it never runs them. Update-all, the Discover board, Liquid Glass and the Live Activity still rest on older or no device evidence.

**Historical round (2026-11-01, tree `67c501a`, Core pin `d81445f`)**: `scripts/verify-ios.sh` **EXIT=0**, **all thirteen UI cases PASS (0 FAIL / 0 SKIP)**; `swift test` **229 tests / 43 suites passed**, `check-seed.sh` confirmed the seed matches the repository fixture, and the unsigned app build, build-for-testing and install all passed. This round added **the category page**: it asserts the choices, the results, and that switching a value really changes the **selected** state; the shelf case now asserts the 书架 header first — both so an assertion cannot pass because the element was already on the previous screen.

**The accessibility tree found two real defects (2026-11-01, tree `9e8f84c`)**: after several rounds of failing interface cases, the tree the test exports on SKIP/FAIL is what located the problems — in the client, not in the test.
- **The search tab had no input field on iOS 27.** The tree shows a navigation bar with the two pickers and the title, a content area with 最近搜索, and nothing that accepts typing, so `.searchable` was drawing no field on this layout and a person could not enter a keyword at all. The screen now carries its own `TextField` (`search.field`) and submits through `onSubmit`.
- **The callback button could be seen but not pressed.** The tree shows `setting.callback.run` present and enabled, yet no busy state, dialog or answer ever followed; `LabeledContent` was giving the button a hit area that does not take a press. It is a plain `HStack` with `contentShape` now, and the identifier is unchanged.

Both are a reminder to fetch the tree before deciding whether a failing case is the client or the test — I read the first few rounds as test bugs and paid three extra runs for it.

**The simulator UI tests ran for the first time (2026-11-01, tree `177f69e`)**: all four seeded sources reached the device (`Callback Probe` appeared in the app's source list and the test opened its settings), `swift test` reported **229 tests / 43 suites passed**, the unsigned iOS build and `xcodebuild build-for-testing` both succeeded, and the UI cases came out **4 PASS / 1 FAIL / 1 SKIP**. The passes were the tabs, the seeded sources, the in-page login sheet and the browse screen; the callback case failed because **my assertion was wrong**: that fixture's callback shows its dialog immediately, and presenting a sheet takes the settings screen out of the accessibility tree, so waiting specifically for the busy marker could never succeed — it did not mean the press failed to arrive. It now counts the busy marker, the source's dialog or the inline answer as proof, and attaches the whole tree when none appears. The skip is search: on iOS 27 `.searchable` is not exposed as `searchFields`, so it is looked for by placeholder and by toolbar button, and the tree is attached when it still cannot be found.

**The UI tests no longer depend on an outside site (2026-11-01, tree `6a1df9f`)**: the callback case used to press `wnacg`'s refresh button, but `wnacg`'s `init` fetches its domain list over the network first, so on a machine that cannot reach that host the button never got to run and the test measured the site rather than the client. It now presses a button on a source in the repository, `UITests/Fixtures/callback_probe.js`, which has no network at all: its callback shows its own dialog and returns a string, so a failure can only be the client's. That source was first checked against the desktop Core (`cbprobe` answered `ANSWER callback_probe.run 0s "ran"`), and the same round moved the search field lookup from "must be a `searchFields` element" to finding it by its placeholder, `关键词`. One more real trap was the seed: `verify-ios.sh` called the seeding script without `--replace`, so a device that already held an older seed answered "existing source store preserved" and exited 2 while the tests went on running against the **old** seed. `NK_UI_SEED_REPLACE=1` now allows the overwrite, and the default stays conservative.

`check-swift.py` also gained a local rule: an `NSPredicate` stored in a variable and then passed to `matching` is reported. That is exactly the shape that broke `build-for-testing` on the Mac (`NSPredicate` is not `Sendable`, so handing it across isolation is a data-race diagnostic under Swift 6), and the interface tests are the only files the Windows machine never type-checks. The rule was checked the other way round: putting the stored predicate back makes it report `stores NSPredicate probe and passes it to matching`. Two more rules watch the interface tests: one requires every identifier a test asks for to exist in `App`/`Sources` (a typo is not a compile error — it makes a case wait out its timeout and report "missing", which reads like a broken client), and one refuses the `label.length` predicate that XCTest rejects. that runs past its line — the same kind of Mac-only surprise, produced by writing a real newline where `
` was meant; putting one back makes it report `line 186 ends inside a string literal`.

Before that, the same verifier **FAILED** on tree `1d41c57`: `swift test` force-unwrapped `nil` at `WebviewLoginCookieTests.swift:17` and died of signal 5, which took the whole bundle down before the app build was reached. The fixture built cookies with `HTTPCookie(properties:)!`, an initializer that returns `nil` when the properties are incomplete, so one case that should have failed crashed everything instead. The fix adds `.originURL`, replaces the force unwrap with `#require`, and drops the cookie-with-no-domain case from the Swift suite — Apple gives no way to build one there, and the desktop Go test covers that branch.

**Evidence boundary**: these two rounds prove compilation, unit tests and the app build; simulator interaction, devices and real accounts are still unverified.

On 2026-10-30 one real run happened on macOS 27 / Xcode 27 / Swift 6.4, with no global tools installed:

- Core was built from GitHub into `VeneraCatCore.xcframework` (96M, slices for ios-arm64, the simulator and macOS); `gofmt`, `go vet`, `go test -race` and `gomobile bind` all passed.
- `swiftc -typecheck -swift-version 6` over the 13 files in `Sources/NekularityKit` produced exactly one error: `JSONValue.swift` had an `array` accessor on `OrderedObject` copied over from the enum (`case .array(let a) = self` cannot match a struct). That accessor is gone; the other twelve files, the Core import, Swift 6 language mode and concurrency isolation reported nothing.
- The ten files in `App/` were checked afterwards: `-emit-module` for `NekularityKit` under the iPhoneOS 27.1 SDK (0 errors), then `swiftc -typecheck` over `App/*.swift` with the same SDK. That produced exactly **one error**: `ForEach(shelf.recentHistory())` in `ShelfView.swift` took the `Identifiable` overload, and `ShelfHistory` does not declare that protocol. The fix is not to declare it — its `id` is only the comic id and carries no source, so two sources can collide — but to give `ShelfHistory` a `key` (`source + "/" + id`) and pass `id: \.key`; the same risk in `ForEach(folder.items)` was fixed the same way.
- So the Kit side is **0 errors, 0 warnings**, while the App side is waiting for one re-run after that single fix.

## Written

| Part | Contents |
|---|---|
| Error text | Core reports in English and the interface is Chinese: `CoreError.readable` turns the usual failures (cancel, missing source, not installed, timeout, human verification, no permission) into Chinese sentences, and prefixes anything else with "源返回错误:" while keeping Core's original words, so a reader never sees a bare English sentence and a bug report still has the detail |
| Core wrapper | `CoreClient`: async/await API that passes task cancellation to Core; `CoreHost`: implements every host interface Core needs; search calls `search.load` with the defaults Core reports for each filter group |
| JSON | A small `JSONValue` parser and `OrderedJSONDecoder` that keep key order and number text |
| Networking | `URLSessionTransport`: cookies isolated per source, including cookies set on redirect hops |
| Cookies | `CookieJars`: host-only and domain cookies, paths, Secure, expiry; persistent cookies saved to a file |
| Human verification | `VerificationSession`: a WKWebView loads the challenge, passes by Core's done rule, and hands back cookies and the User-Agent |
| Storage | `SourceStore`: source data, settings and plugin records kept as written; logged in follows the official rule (an `account` value exists) |
| Images | `ImageLoader`: requests through each source's `onImageLoad`/`onThumbnailLoad`, downsampled and cached |
| Screens | Sources (indexes, install from URL, update, enable, delete), search (recent keywords can be tapped again, removed one by one or cleared; scope is "current source" or "every source", and the merged mode takes each source's first page, at most three at a time, merges them in install order and labels each card, switching the picker when you open another source's comic; under a single source a filter row shows the groups the source declares and searching again after a change, while a merged search still uses each source's defaults; every search carries a generation number so a late answer from an older search cannot write into the screen of a newer one), details (grouped chapters, with the chapter reading stopped on marked "读到"), reader (one of two layouts — a vertical strip or one page per screen, the paged one with a left-to-right or right-to-left direction — previous/next chapter, and it writes the current page and percentage back to the shelf, reopening the same chapter at the page it stopped on, and an optional auto-continue that is off by default, only fires once the end of the chapter has really been scrolled to, and only appears in the vertical layout: paged mode is a `TabView`, which builds its neighbours ahead, so there is no trustworthy "nearly at the end" signal and guessing would be worse than hiding it), source-driven toasts, dialogs, input, choices and loading |
| Source settings | `CoreClient.settings(key:)` reads Core's `settings` declaration; a source's detail screen opens a settings screen that draws each by type (picker, toggle, text field) and stores the value as `JSONValue` in that source's store, so numbers and booleans survive; an input's `validator` runs as a regular expression, and a callback is shown as an in-source action |
| Shelf | `ShelfStore` keeps reading history (one row per comic with its chapter, page and percentage) and favourite folders; opening a chapter records it, and the shelf screen can continue, forget, move between folders and create/rename/delete folders; `shelf.json` has the same shape as the desktop client's |
| Standard AI screen | "AI 供应商" opens "标准接口": choose OpenAI Chat/Responses or Anthropic Messages, set a custom API root, model and token limit; the key goes to the Keychain per vendor and does not travel in a backup; the screen lists the model catalog and sends one conversation. A reply arrives **whole**, and the screen says "流式尚未接通" instead of pretending otherwise. Core provides `BuildAIRequest`/`BuildAIModelsRequest`/`SendAIRequest`, entirely separate from Magpie packages |
| Search history | `SearchHistoryStore` keeps the last 30 keywords, newest first, with case-insensitive repeats collapsed, and can merge a backup's `searchHistory`; `searches.json` matches the desktop client |
| Kept pictures | `ShelfStore.pictures`: the reader's "收藏本页" stores the page under the source, comic, chapter, page number and image address, one row per address, newest first, with a thumbnail, a tap that opens the comic, and a swipe to remove. Keys match the desktop `shelf.json` (`comicId`, `chapterId`) and an empty list is left out; a backup restore turns the official `episodes[].imageFavorites[]` into these rows |
| Backup contract | Running Core's `Plan` over the three real `.venera` files pinned every field: history is `{sourceKey,id,type,title,subtitle,time(ms),ep,page,readEpisode[],maxPage,chapterGroup}`; folders are `{name,order,items[]}` and an item's `time` is a string; a kept picture is `{id,sourceKey,title,author,time,maxPage,episodes[{eid,ep,epName,imageFavorites[{page,imageKey,eid,ep}]}],other}`; a source is `{key,script?,data?}`; `pending` and `settings` also appear. `BackupPicture` now matches that shape (pages nested under `episodes[].imageFavorites[]`), so a restore really writes kept pages |
| Backup import | goes through Core's `planBackup` (Core unwinds the archive, reads the sqlite tables and resolves type hashes); `BackupImporter` installs the listed sources, merges history and favourite folders, and merges search history. Device settings and cookies are not applied over this device, and kept pages are written to the picture shelf; the result reports new rows, rows already there, and rows skipped. |
| Patch making | `scripts/make-patch.sh BASE OUT FILE...` diffs the copy the other machine holds against this one, then applies that patch to a scratch copy here and compares md5 per file. Describing "delete these lines, keep one blank line" in prose did not converge twice; a patch proven to reproduce the bytes does not need a third round |
| Transfer manifest | `scripts/make-payload.sh OUTDIR FILE...` prints the archive size and md5, the md5 of each file after unpacking, and the per-segment md5s — one block to paste. It exists because a message once paired a correct archive md5 with the md5 of an older copy of a file, so the receiver would have rejected good data for the wrong reason. **One rule added 2026-11-01**: the script now reads the bytes with `git cat-file blob` instead of copying the working tree. On Windows `core.autocrlf=true` makes the working tree CRLF while the object is LF (the repository says `* text=auto eol=lf`), so a plain `cp` sent CRLF to the receiver: the md5 never matched what was computed from the repository, and the CRLF `scripts/check-core-surface.sh` would not even run on the Mac (`set: -: invalid option`). That wasted one transfer round, so the fix lives in the script rather than in someone's memory |
| Surface without a Mac | `scripts/check-surface-offline.sh` generates the ObjC header with gobind on Windows and runs the same selector list the Mac check uses: 9.7 seconds, 18/18. That check used to be possible only after an xcframework existed, by which point a mismatch had already cost a transfer. It also settled the list itself: a no-argument method generates `auth:`, `models:` and `savedAuth:`, not `…WithError:` |
| Static check (test doubles) | `check-swift.py` checks that `Tests/` doubles conforming to `MagpieRunner.Core` have every method. When the protocol gains one, the gap is silent on Windows and a `swift test` compile error on the Mac — a whole validation round. Verified against a copy with the stub removed: it reports `RefusingCore lacks readPackageArchive` |
| Browsing | `CoreClient.explorePages` and `explore` cover the four browse kinds (single page with parts, multi-page list, mixed, multi-part page); `BrowseView` switches between browses with chips, pins section headers, pages, and refreshes by pulling |

## All eight cases pass (2026-11-01, tree `38d3822`, Core `d81445f`)

Stage 13: **exit code 0, eight interface cases all PASS, nothing failed and nothing skipped**. This is the first run where the suite passed as a whole, including the two added this round — **two-section browse** (the chip row, the first section's comics, and that switching really changes the list) and **the comment thread** (the entry appears only when the source declares it, and the thread carries its author and body).

```
check-core-pin: ok (d81445fbcf04)
swift test: 229 tests / 43 suites passed
unsigned app build, build-for-testing, simctl install, seed write, test-without-building  all passed
UI: 8 PASS / 0 FAIL / 0 SKIP
```

Interface evidence: five captures — browse, the callback dialog, the comment thread, comic details, the web login sheet.

**The line is unchanged**: browse, comments and callback pass against the repository's own test source; the login case only proves the sheet opens, and **no real account was ever submitted**. A device, a real account and background playback still have no evidence.

## The first loopback server was stopped by Swift 6 concurrency (2026-11-01)

The reader case's first version **failed to compile** on the verification machine, and not in the test logic: `SWIFT_STRICT_CONCURRENCY: complete` is a **global** setting in this project, so the test target inherits it, and that meant

- mutating a captured local `var failure` inside `NWListener`'s `@Sendable` handler — a concurrent mutation;
- capturing a non-`Sendable` `self` across the handler — a non-Sendable escape.

The fix puts the responsibility on the class: `@unchecked Sendable` (every stored property is a `let`) plus a locked `Signal` that carries the start result, with no weak self captured across a handler.

**Why this is worth writing down**: "strict concurrency on the verification machine" is not theoretical — the first attempt was stopped by it, at compile time rather than at runtime. I had changed it locally while self-reviewing after dispatch, but the machine ran the tree it had already received, so the failure really happened.

## The downgrade was measured on the verification machine (2026-11-01, tree `b5ec30b`)

The section above was only simulated locally with `--no-parser`. This round ran it on the Mac itself:

```text
check-swift: tree-sitter is not installed, so files are not parsed for syntax; the rule checks still run.
  python3 -m pip install tree-sitter tree-sitter-swift
check-swift: 95 files checked by the rules only
exit 0

check-docs: ok
exit 0

python3 -c 'import tree_sitter, tree_sitter_swift'
exit 1 (ModuleNotFoundError: No module named 'tree_sitter')
```

**The boundary still needs saying**: on that machine **the rules ran and the syntax parse did not**. Syntax errors are caught there by the real compiler (`swift build` / `xcodebuild`), so nothing is left uncovered; to parse as well, install tree-sitter on that machine — an environment choice, not a code problem.

From the next round `verify-ios.sh` shows `PASS python3 scripts/check-swift.py (rules only: no parser here)` for that row instead of a SKIP.

## `check-swift.py` no longer skips on the Mac (2026-11-01)

Every gate run on the Mac carried one SKIP: `check-swift.py` exited 3 because that machine has no Python tree-sitter. That left the check not running on **the one machine that can actually compile the tree**.

Only the syntax parse needs tree-sitter; the rules (must import `VeneraCatCore` / `NekularityKit`, duplicate test names, unterminated strings, unknown identifiers, predicate shapes) are all plain text. So a missing parser now downgrades to the rules and says so, rather than exiting:

```
check-swift.py --quiet --no-parser     → exit 0 (rules run, parsing skipped)
```

Negative validation: a temporary file naming `MobileCore` without the import made `--no-parser` report `names MobileCore but does not import VeneraCatCore` and exit 1; removing it returned to 0.

### Every assertion has to be asked: is it also true on the previous screen?

Auditing my own cases turned up two assertions that would **pass for the wrong reason**:

- After switching a category value, the case only asserted "the comic is still there" — it was already on screen, so `waitForExistence` returned at once. It now waits for **the tapped chip to become the selected one**.
- After switching to the shelf tab, the case only asserted "the comic's title is there" — but **the detail page's title is the same string**, so a tab switch that did nothing would still pass. It now asserts `navigationBars["书架"]` first, then the shelf's own progress line (`Chapter 1 … 第 1 页`).

The rule: **if the asserted element is also on the screen before the action, the assertion cannot show the action happened.** Checked case by case, the rest only hold on the target screen — comment body, favourites list, section chips, the `callback_probe · probe` title.

## What each of the thirteen interface cases proves (2026-11-01)

With this many cases, "it ran" is easy to hear as "it is all verified". This table says what each one rests on, and whether it proves the client or a site.

| Case | What it proves | Depends on |
|---|---|---|
| `testTabsExist` | the four tabs are there | nothing |
| `testSeededSourcesAppear` | the seed reached the device and parsed; includes the test source, without which the callback and tag cases skip for no good reason | the seed |
| `testSourceOffersInPageLogin` | a source that declares web login opens its login sheet | the seed (no login is submitted) |
| `testCallbackSettingRuns` | a source's own button can be pressed and its answer reaches the screen | the test source |
| `testSearchReachesDetailWithTags` | search → results → detail, with tags and chapters drawn | the test source |
| `testTagTapOpensTheSourcesRule` | a tag tap follows the source's rule rather than a guess by the client | the test source |
| `testBrowseLoadsSections` | the section chips, the first section's comics, and that switching changes the list | the test source (two sections) |
| `testCommentsShowTheSourcesThread` | the comments entry appears only when the source declares it, and the thread shows its author and body | the test source |
| `testSearchHistorySurvivesRelaunch` | a searched word is still there after the app is closed and opened again (writing and reading that file back is the app's job, and a unit test cannot show it) | the test source |
| `testSourceFavoritesShowWhatTheSourceKeeps` | the favourites a source keeps are listed (they live in a **top-level** `favorites` block, not inside `comic`; putting them in the wrong place yields an empty page rather than an error) | the test source |
| `testReaderDrawsTheChaptersPage` | the chapter's image really decodes into a page (the criterion is 收藏本页 going from disabled to enabled, not "the reader opened") | the test source plus the loopback server in the test runner |
| `testReadingPutsTheComicOnTheShelf` | after reading, the shelf remembers the comic (the reader writes progress and the shelf reads it back; a unit test cannot show that) | the same |
| `testCategoryPageListsItsPartsAndComics` | the category page offers both the choices and the results, and switching a value really changes the **selected** state (`category` and `categoryComics` are two halves of one contract; doing only the first draws choosers that never load anything) | the test source (declares `category`) |

**Not one of them uses a real site.** They prove the client presents what a source declares; whether real sites search, log in and browse is what the desktop's live sweep and live tests are for. A device, a real account and background playback still have no evidence at all.

That line is not modesty: stage 12 is the example. The browse case failed and looked like the client drawing no sections; tracing it showed the test demanded an element the client deliberately does not draw for a single-section source. **A wrong assertion and a wrong implementation look identical on a screen**, so every case has to name the design decision it rests on.

## Core's Apple CI is now third-party evidence (2026-11-01, commit `d81445f`)

"the xcframework builds and the Swift smoke tests pass" used to rest on this machine and on the Mac worker. GitHub has now run it on its own macOS 26 / Xcode 26.6 runner: four jobs green, and the log was read rather than the colour:

```
RESULT gofmt=ok / vet=ok / test=ok / bind=ok
RESULT bind_seconds=347
RESULT xcframework_total=101M
RESULT slice_ios-arm64_x86_64-simulator= 40M / slice_ios-arm64= 21M / slice_macos-arm64_x86_64= 40M
RESULT device_binary_stripped= 21M / device_binary_gzip=7.5M
Swift smoke (macOS) 8 passed; Swift smoke (iOS simulator) 8 passed, ** TEST SUCCEEDED **
```

So Core's Apple surface is not "it compiles on my machine": an environment I do not control reproduces it.

## The whole gate exited 0 for the first time (2026-11-01, tree `848d748`, Core `d81445f`)

`sh scripts/verify-ios.sh` passed as a whole: seven interface cases **6 PASS / 1 SKIP / 0 FAIL**, `check-core-pin: ok (d81445fbcf04)`, Core re-fetched at the new pin and the framework rebuilt, `swift test` 229 / 43.

The six passes cover the source-capability line: tabs, seeded sources, the in-page login sheet, **a setting callback** (dialog plus the inline answer `ran`), **search to detail** (with tags and chapters) and **a tag tap** (`callback_probe · probe`).

**The evidence boundary matters**: search-to-detail and the tag case both use the repository's own Probe source and touch no network. So this round proves the client *presents* those capabilities, and says nothing about whether a real site's search, login or browse work — that is what the desktop's live sweep and live tests are for.

The browse case skipped for a reason in the tests rather than the app: the app remembers the selected source, the tag case had switched to the Probe source, and the browse case inherited it while that source had no category entry. Fixed in the same round: `chooseSource` makes each case state the source it needs, the Probe source gained an `explore` section, and the browse case now asserts a section and its comic.

## How far the interface tests have got (2026-11-01, tree `79a5dbb`)

Seven cases, **6 PASS / 1 FAIL**, and for the first time the source capabilities themselves are proven on a simulator: tabs, seeded sources, the in-page login sheet, **a setting callback** (the `Probe Result` dialog and the inline answer `ran`), the browse screen, and **a tag tap** (the `callback_probe · probe` sheet).

What did not pass is search-to-detail: the tree exported at failure clearly holds `detail.comments`, the tags and chapters, yet the assertion said the controls never appeared. The cause is `element()` walking every descendant of the app, where a single evaluation can take longer than the timeout it was given — so an element on screen is reported missing. It now asks the cheap, type-scoped queries first (buttons, staticTexts, cells), waits for `detail.comments` or one cell, and attaches `detail-tree` when neither appears.

The same round published Core as the single commit `d81445f` and moved both pins; a distinguishing experiment also corrected a claim: **`mobile.CallSettingCallback` serves iOS only**, the desktop goes through its own `internal/core`, so "Core is fixed, both clients are fine" was wrong and is withdrawn.

## What each claim rests on (2026-11-01)

"Passing" means different things at different levels, so the current claims are listed by the evidence behind them. The point is to keep a compile from being read as a run.

| Claim | Level of evidence | Note |
|---|---|---|
| Core surface and Kit calls agree | Static, plus a Mac compile | `check-kit-core-calls.py`, `check-core-surface.sh`, and `swift build`/`swift test` actually running on the Mac |
| Unit tests pass | A Mac run | `swift test` 229 tests / 43 suites, executed inside `verify-ios.sh` |
| The app builds | A Mac run | Unsigned `xcodebuild build` and `build-for-testing` both succeeded |
| The seed reaches the device | A Mac run | 127,249 bytes written, the device file md5 matches the seed, four records parse |
| Tabs, seeded sources, login sheet, browse screen | Simulator interaction | UI cases passed, with captures and a recording |
| The search field works | **Verified (simulator)** | `.searchable` drew no field here at all, which the tree proved; the screen's own field takes a query and the case walks through to a detail page |
| The callback button can be pressed | **Verified (simulator)** | The button was visible with a hit area that took no press; after the `HStack` row both the dialog and the inline answer `ran` were observed |
| Tags can be tapped | **Verified (simulator)** | The other place the same container swallowed presses; tapping `probe` produced `callback_probe · probe` |
| Browse sections | **Fixed, awaiting a run** | The case used to skip because it inherited a source with no categories; each case now names its source and the Probe source has an `explore` section |
| Devices, real accounts, background lock | Nothing | No evidence at all |

## Not verified

**This change has been through a real Xcode build** (2026-10-31, the same Mac): XcodeGen came from the release page binary (2.46.0, in `/tmp/xcg`, **no Homebrew and not on the system PATH**), `xcodegen generate` → `xcodebuild -scheme Nekularity build` reported `BUILD SUCCEEDED`, and the built `Nekularity.app/Info.plist` carries `NSAllowsArbitraryLoads = true`; `-showBuildSettings` echoes `INFOPLIST_FILE = App/Info.plist` and `GENERATE_INFOPLIST_FILE = NO`, with zero `Copy Bundle Resources` complaints, so `excludes: [Info.plist]` works. `scripts/verify-ats.sh` runs this chain and is part of `verify-ios.sh`, so every whole-tree run now really builds the app instead of falling back to type checking.
- **A real iPhone**: nothing has run on one. On the simulator the whole main path works — tabs, an installed source, search to detail, tags, browse sections, comments, favourites, a callback, search history across a relaunch, and **reading plus the shelf afterwards**, twelve cases. A device, a real account and background playback still have no evidence.
- **Signing and archiving**: XcodeGen is part of the gate now (`xcodegen generate` runs every time) and `xcodebuild` produces an **unsigned `Nekularity.app`** on generic/platform=iOS; `build-for-testing` passes too. Signing, archiving and installing on a device have not been done: `** BUILD SUCCEEDED **` proves it compiles and packages, not that it installs.
- **A real vendor account**: Magpie's sign-in, model list, usage, streaming and cancellation have only been exercised against local fake services and canned answers; no real vendor account has completed authorization on a device.
- **Real comic sources**: the desktop's `TestLiveSource` covers these outside the repository (see Nekophage); the iOS side has no equivalent.

## Next

1. The compile and test stage is settled: on macOS, in Swift 6 mode, the tree passes all five checks — `swift build`, `swift test` (49), `-typecheck`, the iOS `-emit-module`, and the App `-typecheck` in two consecutive rounds, including the multi-source search and kept-page chapter jump. Later changes keep going through the same loop, so no package piles up unseen by a compiler.
2. Run the main path with a real source on the simulator that is now available (install, search, details, read, shelf). Launching is already proven; this step is about actually using it.
3. Backup import is wired and was checked against the real `.venera` field shapes; the next step is running it once on a simulator and checking the counts.
4. Video sources and playback still wait on a product decision; the old global cookie jar is now restored into per-source partitions (see the cookie section on this page).
5. ~~Installing an iOS simulator runtime~~ **done** (2026-11-01): two iOS 27.2 runtimes, 12 devices available, and the App installed and launched on an iPhone 18 Pro simulator.
6. AI comes after the reading path: on iOS the plan is the **Magpie plugin system** — running
   Magpie's original provider packages, with accounts and runtime separate from comic sources.
   Desktop does no AI work.

## Magpie provider plugins (the Nekularity side)

**What installs, stated first.** Of the community repository's 36 packages, only two provider
plugins actually run on this system today: the original `@magpie-community/opencode-copilot-auth`
0.1.0 and `cloudflare-workers-ai` 0.0.4. Most of the rest need `node:fs`/`node:crypto`/
`child_process`, or ship a TypeScript entry, and are refused at load with the reason named —
not a blank screen, and not "installed but useless". So "Magpie compatible" here means the
package format and runtime contract are compatible, not that every community package installs.

Core already does the hard part: package snapshot and module resolution, a `fetch` /
`Headers` / `URL` / `ReadableStream` runtime, device-code sign-in, refresh write-back,
usage and model lists, streamed chunks, one event model over three wire dialects, and
"never retry once output started". All of that is covered by Go tests, including the
original Copilot package against a fake service.

This repository has only the client layer so far. **The 2026-10-31 run passes in full**, on
macOS 27 / Xcode 27 / Swift 6.4:

| Check | Result |
|---|---|
| `scripts/check-core-surface.sh` | PASS — all 18 `MobileMagpie` methods |
| `swift build` | PASS, 0 errors, 0 warnings |
| `swift test` | **PASS — 119 tests / 27 suites** |
| Kit `-typecheck -swift-version 6` (arm64-macos26.0) | PASS, 0 errors, 0 warnings |
| iOS `-emit-module -parse-as-library -swift-version 6` (iPhoneOS 27.1) | PASS |
| App `-typecheck -swift-version 6` | PASS |
| `swift test --filter Magpie` | **PASS — 61 tests / 16 suites** |

Static counts agree with the run: `@Test` 119, `@Suite` 27, `.swift` 56 (28 Kit, 14 App, 11 Tests
and `Package.swift`).

**Code added after that run has now been verified too**: on 2026-10-31 the same five checks ran on the
Mac mini (macOS 27.0.1 / Xcode 27.1 / Swift 6.4) and every one exited 0: `swift build` with 0 errors and
0 warnings, `swift test` **129 tests in 27 suites passed**, Kit and App `-typecheck` clean, iOS
`-emit-module` clean; `check-core-surface` 18/18; `swift test --filter Magpie` **71 tests in 16 suites**;
and `check-tree` printed `swift=56 tests=129 suites=27 shape=8457d8e43ce3d36849577f4cdcc07a92079b4015`,
the same shape this repository prints. **Still unverified**: an `xcodebuild` archive and signing, an iOS
Simulator runtime (absent on that machine), a real device and a real vendor account.
**The whole-tree runner now completes in one command**: `scripts/verify-ios.sh` on macOS ends with `EXIT=0`, in this order — surface, Core pin, docs, syntax, `swift test`, `xcodebuild` (iOS, unsigned) and App `-typecheck`. The syntax line reads `SKIP`, not `FAIL`: no tree-sitter (exit 2) or a grammar version that will not load (exit 3) both mean "this machine cannot run it", while a developer running `scripts/check-swift.sh` still fails hard. Both exit paths were exercised on the Mac. That run: `swift test` 130 tests in 27 suites, App type-check with 0 errors and 0 warnings (the tree has since grown to 134).

**Two known-harmless build messages** (for later comparison, not regressions): `xcodebuild` always prints `warning: Metadata extraction skipped, no AppIntents.framework dependency found`, and one line beginning with `error:` is actually the CoreSimulator version notice (`iOSSimulator: CoreSimulator is out of date … Simulator device support disabled`) — not a compile error, since `** BUILD SUCCEEDED **` is still printed. `swift test` reports 0 warnings. A `warning:` outside these two is a new problem and should be pinned down.

**Latest whole-tree run (2026-11-01, same Mac mini, including the search generations and the pin move)** — *note: these are that machine's tree numbers; this repository reports 182/34 for the same state, and the entry below explains why*: 70 Swift files, **196 tests in 35 suites**, `shape=e18d20cb0465bbbaa651d9634b1d0a8a31dde9db`. `sh scripts/fetch-core.sh` built Core `6e07429` from GitHub (`gofmt` / `go vet` / `go test` all pass, 22 packages), then bound the framework and checked every file's SHA256 (23 files, 0 mismatches); `check-core-surface.sh` reports **19 Magpie methods + 3 standard AI methods**, and the new framework shows `streamOpen:` / `streamNext:` / `streamClose:` and `MobileNewMagpieWithStream`; `check-core-pin` **ok (6e0742996007)**; `PATH=/tmp/xcg/xcodegen/bin:$PATH sh scripts/verify-ios.sh` **EXIT=0**; `swift test` **196 tests / 35 suites, 0 warnings**; `xcodebuild generic/platform=iOS` **BUILD SUCCEEDED, 0 errors** (one pre-existing AppIntents notice; the product is newer than the framework, so it used the new one); `check-partitions` / `check-docs` / `verify-ats` all pass. **Negative check**: putting `469edfcb48ec…` back into `scripts/core-version` makes `check-core-pin.sh` exit 1 and name the mismatch; putting it back to `6e07429` makes it exit 0.

This run also produced the **first evidence of a simulator runtime**: two iOS 27.2 runtimes, 12 devices available (including a booted `iPhone 18 Pro`), and `xcodebuild -showsdks` listing iOS SDK 27.2.

### What the chunked transport actually does (2026-11-01)

The iOS `URLSessionTransport.sendStreaming` reuses the same request path as `send` (same cookies, cancellation, size limit and redirect policy) and only hands the body over **as it arrives**. `CoreStreamHost` implements Core's `MobileHostStream` protocol and passes it along.

**One measured constraint worth knowing**: **Foundation merges adjacent `URLProtocol` pieces smaller than about 256 bytes** before the delegate sees them. Measured on the Mac:

```text
16 B × 3   → 1 chunk
64 B × 3   → 1 chunk
256 B × 3  → 2 chunks
1024 B × 3 → 3 chunks
8192 B × 3 → 3 chunks, first at 5 ms, middle at 315 ms, last at 618 ms
```

So a test double that wants to prove "pieces arrive one at a time" must use pieces of 1024 bytes or more; smaller ones measure Foundation's merging, not our streaming. The real-server timestamps (5 ms / 315 ms / 618 ms) are the actual evidence that the body is handed over as it arrives.

**Names come from the generated Objective-C header, not from guessing**: the second parameter of `MobileNewMagpieWithStream(_ host:, _ stream:)` has **no label**, because the Objective-C prototype gives it no name. I wrote `stream:` first and only changed it after the Mac reported `extraneous argument label 'stream:' in call`.

### Open: the local tree and the verified tree do not match (found 2026-11-01)

The same `scripts/check-tree.sh` reports different numbers on the two machines:

| State | The verifying Mac's tree | This repository |
|---|---|---|
| Standard API plus search generations, before the chunked transport | `swift=70  tests=196  suites=35` `shape=e18d20cb…` | `swift=69  tests=182  suites=34` `shape=4c01f2bb…` (commit `0ae0579`) |

**Same suite count, ten more tests**, so it is not a whole missing test file but ten extra `@Test` in a file both sides have.

My reading, still to be confirmed: the earlier round of iOS network and lifecycle fixes (URLSession delegate keep-alive, the pre-cancel race, the cross-origin `X-Api-Key` leak, shared-task cancellation in ImageLoader, persisting refreshed credentials, the Magpie signOut runner cache, `MagpieUsage` null tolerance, the sign-in timeout) **landed only in the verification machine's isolated directory and never came back to the repository** — the iOS repository is private, that machine cannot fetch it, and the transfers at the time were piecemeal gists.

**The per-file `@Test` list has been requested.** Once it arrives I will diff it line by line, bring whatever source and tests are missing back into the repository, and send one complete package; until then no more piecemeal patches go on top. **So the 196/35 and 192/34 figures above are the numbers of that machine's tree, not of this repository** — the difference itself is what this entry records.

### Running on a simulator for the first time (2026-11-01)

This is the first evidence that the App installs, launches and shows an interface on a device — not that it compiles:

```text
iPhone 18 Pro (1E57B720-…) already booted; bootstatus -b → rc=0
simulator build rebuilt → BUILD SUCCEEDED (build/verify only had Debug-iphoneos, which cannot be installed on a simulator)
simctl install → rc=0, 1s
simctl launch  → rc=0, PID 78149, 165 ms round trip
screenshot → /tmp/nk/logs/audit-docs/app.png
process alive → UIKitApplication:com.laincat.nekularity
crash check → 272 log lines with no crash/fatal/signal/exception/abort; no Nekularity .ips in DiagnosticReports
Core framework load failures → 0 (grep for VeneraCatCore|dyld|Library not loaded|image not found|Go runtime|MobileNew found nothing)
startup → first line 19:13:52.835 → interface ready 19:13:53.538, about 0.7 s
```

**What the screenshot shows**: the title "搜索", a search field with the placeholder "关键词", an empty-state illustration with "没有可用的漫画源" and "先在“漫画源”里添加并启用一个源。", and five tabs (搜索 / 浏览 / 书架 / 漫画源 / AI 供应商) with 搜索 selected. This is a **fresh container** after the pin change, so an empty source list is expected rather than a load failure — the same log reports zero Core framework load failures.

**The boundary of this evidence**: it shows the App installs, launches, draws its interface, does not crash, and loads the Core framework. Real provider sign-in (Magpie / OpenAI / Anthropic) still has no credentials, live streaming is still not connected, and nothing has run on a real device.

**Measured evidence for the Core deadlock fix**: `go test -race -run 'Reply|Chat' ./magpieplugin/` inside `build/core` passes the six buffer tests and the three chat tests — `TestReplyBufferWriteDoesNotWaitForAReader` is exactly the fixed behaviour: the writer does not wait for the reader.

Earlier run (2026-11-01 morning, superseded by the paragraph above): 68 Swift files, **192 tests in 34 suites**, `shape=e2d55356aabdec360928addd42a3f9e6e7fbcab5`. `swift test` all green (the 11 new standard AI tests all really ran), `xcodebuild -scheme Nekularity` (generic/platform=iOS, unsigned) **BUILD SUCCEEDED** (0 errors, one pre-existing AppIntents notice), `scripts/verify-ios.sh` **EXIT=0**, `scripts/check-core-surface.sh` **19 Magpie methods + 3 standard AI methods** (negative: a header without the three standard AI selectors exits 1), `check-core-pin` `6e0742996007`, `check-partitions`, `check-docs` and `verify-ats` all pass, and `scripts/check-tree.sh` reports the same shape. That run covered the standard API screen (`App/StandardAIView.swift`, `Sources/NekularityKit/AI/`), the three standard AI calls in `CoreClient`, and the three new selectors in `check-core-surface.sh`.

The four changes made on the Mac were compile problems, not behaviour problems: `StandardAISettingsStore` became `@unchecked Sendable` (`UserDefaults` is not itself `Sendable` and Swift 6 refuses to synthesise it, while its documentation guarantees thread safety); two optional pattern matches in `StandardAI.swift` were wrong (`case .object(let x)? = a non-optional`); `Section("协议") { } footer: { }` has no such SwiftUI overload and became `Section { } header: { } footer: { }`; and `#expect(try …)` does not handle `throws` inside the macro, so the test itself became `throws` with `try` moved out. **The words "streaming is not connected yet" are kept unchanged.**

One normalisation happened when the package was landed: nine files arrived with CRLF and were turned into LF. Two pieces of evidence for this: the repository's `.gitattributes` says `* text=auto eol=lf`, so CRLF is rewritten on commit and the md5 drifts at once; and the CRLF `scripts/check-core-surface.sh` does not even run (`set: -: invalid option`, the `
` is read as a flag). Apart from the line endings the files are byte for byte the ones received, checked one by one.

Earlier run (2026-10-31, superseded by the paragraph above): 63 Swift files, **164 tests in 32 suites**, `shape=82fa2813dd9f4a8b397f263c1f7093a0d0294003`; `swift build` with 0 errors and 0 warnings, `swift test` all green, `swift test --filter Magpie` **76 tests in 16 suites**, Kit and App `-typecheck -swift-version 6` both clean, and `xcodebuild -scheme Nekularity` (generic/platform=iOS, unsigned) **BUILD SUCCEEDED**. That run covered `CoreVersion.swift`, the footer `buildLine`, and `theCoreVersionIsShortButIdentifiable`. The one step that could not run is `check-swift.py`: that machine has only the system Python 3.9 and cannot install the `tree-sitter>=0.24` that grammar version 15 needs. It now exits 3 to mean "this machine cannot run the check", and `verify-ios.sh` records that as SKIP rather than FAIL — the steps after it compile with the real Swift compiler.
describes the tree on the Mac; whether the two trees match file for file is settled by md5, not by shape — and
that was done: thirteen Magpie sources plus the test file were compared one by one, ending with
`MagpieAccounts.swift` `3ec891ff…`, `MagpiePackageStore.swift` `c0530a35…` and `MagpieRunnerTests.swift`
`489dcf21…` all identical, with the other eleven already the same.

The framework's macOS deployment target is settled too: Core builds with `gomobile -macosversion=26.0`, matching `Package.swift`'s macOS 26, so the sixteen link-time `was built for newer macOS version` warnings are gone — reproduced with the committed script and no local edits.

The round before this one was compile-green and test-red: the same tree had zero compile
errors while `swift test` found four assertion failures — a `null` modalities array that would
not decode, an install path that did not check the provider a plugin declares (which would
file its sign-in against another account), and a sign-in loop that treated "empty/null" as
waiting in one branch and as failure in another (the root cause being that `JSONSerialization`
rejects a bare top-level `null` by default). Two timeouts followed, for sign-in and for a
reply: anywhere the code can wait for ever, both a test and a user will hit it.

**The verification environment can be rebuilt on demand** (confirmed 2026-10-31): that macOS
machine can `git clone` the public Core repository (`github.com/laincat/VeneraCat-Core`) directly,
has Go 1.27.3, and builds `gomobile` from the tool dependencies in `go.mod` with `go build`, so
nothing global has to be installed. Re-verifying is now a clone plus `scripts/mac-verify.sh`
rather than depending on someone still having a copy.

The edges of that verification, stated rather than glossed over:

- Check ⑤ runs `swiftc -typecheck -swift-version 6` over `App/*.swift` against the module
  emitted from `NekularityKit`, which is the Swift 6 compile check an Xcode project would do.
  A real `xcodebuild` archive and signing were **not** run (and that machine has no iOS
  Simulator runtime; installing one is a system-level action that needs approval).
- The verified tree has no `project.yml`. It is XcodeGen input: it takes part in neither
  `swift build`/`swift test` nor the type checks above.
- `manifest.sh` agrees file by file (68 files that compile or are tested), and so does the
  `check-tree.sh` digest.

The section below is the first round, from 2026-10-30, which was compiled on
macOS 27 / Xcode 27 / Swift 6.4 and passed all five checks:

```
① Kit swift build                     PASS  0 error 0 warning
② Kit swift test                      PASS  65 tests / 13 suites (was 58 / 11; +7 and +2)
③ Kit -typecheck -swift-version 6     PASS  0 error 0 warning
④ iOS Kit -emit-module                PASS
⑤ App -typecheck -swift-version 6     PASS
swift test --filter Magpie            7 tests / 2 suites, all executed
```

The first real compile of this layer produced no error and no warning. The file counts matched
too: Sources 16→18, Tests 9→10, total 36→38.

| Part | What it does |
|---|---|
| `MagpieAuthStore` | Keeps each provider's sign-in separately, as the **original JSON text**, not a parsed dictionary: the package writes and reads it back itself, and re-encoding reorders keys and turns `9007199254740993` into a float. `MemoryMagpieAuthStore` is for tests; `KeychainMagpieAuthStore` uses `kSecClassGenericPassword` per provider with `AfterFirstUnlock` — a refresh may run while the phone is locked, and a sign-in that cannot be read then is a package that quietly stops working |
| `CoreMagpie` | The real bridge: implements `MagpieRunner.Core` and hands JSON to the generated `MobileMagpie`. The signatures are transcribed, not guessed — `gobind -lang=objc` produced `- (BOOL)loadPackage:(NSString*)filesJSON error:(NSError**)`, `- (NSString*)call:(NSString*)export argJSON:(NSString*)error:`, `savedAuth:`, `setAuth:authJSON:`, `close` and `MobileNewMagpie(id<MobileHost>)`. Its tests drive a small offline package through the real Go runtime, so no 21-method host stub is needed |
| `MagpieSignIn` | One sign-in's wait and its cancellation: `start` reports the page and code, `waitForResult` waits on the package's callback (the package polls itself), and cancelling stops both the wait and the callback still polling the vendor. A success is stored in **Magpie's own shape** — `{type:"oauth",refresh}` or `{type:"api",key}` — rather than the package's answer verbatim |
| `MagpieAccounts` | The provider list and its runners: `install(folder:)` never asks the user for a provider id — the plugin reports `auth.provider`. Core compiles the package before anything is stored, so a refused package leaves no half-installed row. Runners **and the declared spec** are cached per provider: evaluating a package starts a JavaScript runtime, and a ten-provider list should not start ten of them on every refresh (a test pins "three refreshes, one load"). Removal clears both |
 The provider list and its runners: `install(folder:)` never asks the user for a provider id — the plugin reports `auth.provider` and the folder name is only a provisional key. Core compiles the package before anything is stored, so a refused package leaves no half-installed row. Runners are cached per provider (loading compiles the package, and rebuilding on every tap would make the list feel broken) and closed on removal or sign-out |
| File manifest | `scripts/manifest.sh` prints `md5  path` for every source, script and doc; diffing two manifests says **which files differ**. A delta must not be assembled from a commit diffstat — that is how `MagpieRunner.swift` and `MagpieAuthSpec.swift` were missed |
| Tree identity | `scripts/check-tree.sh` prints one line: commit, dirty or not, `.swift` count, `@Test`/`@Suite` counts, and a digest over per-file test counts. Comparing that line between two machines is enough — equal digests mean the same tests live in the same files. Totals alone are not enough: twice now a tree matched on totals and was missing files |
| Delta bundle | `scripts/make-delta.sh SINCE OUTDIR [CHUNK]`; with `DELTA_SKIP_TESTS=1` it leaves `Tests/` out — that file is the largest in the tree, and a few added tests travel cheaper as text |
| Transfer triage | `scripts/split-part.sh PARTS_FILE` splits one base64 segment in two and prints each half with its md5. We have seen an equal-length rewrite: the length and the archive size matched while the content did not. The whole-archive md5 then says *that* it is broken but not *where*; per-segment md5 locates it, and two shorter halves usually survive |
| Core version | `scripts/core-version` pins a commit (`6e0742996007e0246e1c56a14a09546325bb3e96`), not `main`. Pinning to `main` meant the same Nekularity commit could be built against two different Cores on two days — reproducible for the client only, not for what it stands on. Changing Core means changing that line and saying why here. **Every pinned commit is green on Core's CI in all four jobs** (three Go platforms plus Apple's xcframework with two Swift smoke tests). Every whole-tree run builds the framework from scratch with `scripts/fetch-core.sh`. **The four CI jobs of `6e07429` are green** (three Go platforms plus Apple's xcframework with two Swift smoke tests), checked on 2026-11-01: run `41194668348`.

**iOS is wired up too, and checked on the Mac (2026-11-01)**: `ImageRequest` carries `handle` and `callbacks`, and `ImageLoader` tries at most four addresses per image: a body that is an error page is a failed load when `onLoadFailed` exists, a body with `onResponse` goes through the source before decoding, and a body that will not decode asks for the next mirror too. Each address is re-normalised per partition.

That round on the Mac also fixed three things **that cannot be seen from Windows**: the request id passed to `fetch` has to be `Int64` (the caller and the transport layer both use `Int64`, so `Int` did not compile); **a failed download stayed in the in-flight table** — after one failure every later request for that image got the same failed task at once, so the image could not load again for the life of the process (now both paths clear, and only when the entry is still this download's); and **the comment claimed `file://`, `javascript:` and `ftp://` were refused while the code only did `URL(string:)`** — a `file:` address really was handed to URLSession to read local disk, and is now refused. The last two were verified in reverse on an isolated copy: with the fixes removed, the `file:` address reached the transport and the second request reused the old `image HTTP 500`.

Verification: `swift test` 214 tests / 40 suites, including the three new `ImageConfigTests`; `verify-ios.sh` EXIT=0 with `BUILD SUCCEEDED`; tree `77/214/40`, shape `85dd5c3a…`; Core pin `69ed1f9`. **Still unverified**: the image path on a real device, including a real source's `onResponse` rewrite and mirror fallback — what exists is compilation, unit tests, an App build and local probes.

**A cover skips the pixel script and the mirror fallback too (2026-11-01)**: `onThumbnailLoad` is documented as ignoring `modifyImage` and `onLoadFailed`, so `thumbnailRequest` drops both after parsing — **`onResponse` stays**, because a scrambled cover still has to be made readable. One case pins that trade-off. The same change also fixes a constant written wrong in the previous version: `24 << 20` is 25,165,824, which does not match the 3000×8000 boundary the case assumes; it is `24_000_000` now.

**The pixel round-trip is capped by what a phone will grant (2026-11-01)**: the memory of that path was measured on the Mac — pixels go to Core as RGBA and come back as base64, so one pass peaks at about `w·h·4 × 2.7`, which at a 64M-pixel cap reaches 850 MB–1.1 GB. iOS now caps it at **24M pixels**: a common long strip of 1080×16384 (17.7M, about 190 MB) still fits, and a larger picture is passed through unmodified rather than pushing the process toward its memory limit for the sake of one script. The decision is `ImageLoader.pixelPassFits(_:_:)`, compared in division form so `Int.max` cannot overflow the product; one case covers the boundary and the overflow.

**Why the pin moved again to `eb982d6` on 2026-11-01**: iOS has no JavaScript of its own, so Core exposes `modifyImage(key, script, width, height, rgbaB64)` over gomobile, answering `{width,height,rgba}`. `ImageLoader` hands over the decoded pixels and rebuilds a `CGImage` from the result; pixels travel as straight RGBA in sRGB, a picture over the **client cap** is passed through rather than failing the page (64M then, tightened to 24M below), and a script that produces no image reports the failure and lets the mirror fallback run. **Compiled on the Mac and passing 216 tests plus the iOS build** (`26cb282`), but nothing on a device yet.

**Why the pin moved to `69ed1f9` on 2026-11-01**: Core gained support for an image config's callbacks — besides an address and headers, `comic.onImageLoad` may carry `onResponse`, `modifyImage` and `onLoadFailed`, three functions that cannot cross into JSON, so a client only ever received the first four fields. Core now keeps those functions in the source's runtime under a handle, and a host can hand the body to `onResponse` or ask for the next mirror. **iOS has not adopted the three methods yet**, so for iOS this pin moves the protocol without changing behaviour; the desktop client has not either. What it changes is the shape of the problem: sources with encrypted images are no longer "Core cannot do this" but "the client has not wired it up".

**Why the pin moved to `d98e505` on 2026-11-01**: Core fixed two things in how a source's search arguments are read — an option's "`value-text`" form allows an empty left side (`-<none>` means "no value", not that literal string), and a multi-select filter group's value is a JSON array (`SearchOptionGroup.DefaultValues`). Both used to paste `undefined` or `-<none>` into a source's search request. **iOS has adopted both**: a multi-select group now goes out as a JSON array, and the filter menu toggles such a group value by value and shows how many are chosen; a source that declares only `search.loadNext` is paged through its cursor (null to start, the token handed back untouched, an empty token ending it). A source that declares both still pages by number, matching the desktop client — `lanraragi`'s `loadNext` only maps the token back onto a page. The multi-select step was verified on the Mac and merged into `main` (206 tests / 38 suites, iOS `BUILD SUCCEEDED`); the paging rules of the cursor step are a `SearchPaging` value type with five cases, the desktop side has live evidence (`ehentai`: page 1 25 comics, page 2 25 comics, 0 shared), and the iOS side is still being re-checked on the Mac.

**Why the pin moved to `cc63215` on 2026-11-01**: that Core added `Core.NormalizeURL` — a source sometimes writes an image address as `//images.example.com/1.jpg`, with no scheme, and RFC 3986 says such an address inherits the scheme of the page, which for a reader is the one that source last used. The desktop remembers the scheme per partition and the iOS client remembers it in `URLSessionTransport`; both use Core's one rule. **This does not weaken the rules**: `file://`, `javascript:` and `ftp://` are never rewritten, the filled URL still has to be http(s), and a URL that is not scheme-relative is not touched. The selector count goes from 19 + 3 to 19 + 3 + 1 (`normalizeURL:`).

**Why the pin moved to `6e07429` on 2026-11-01**: that Core adds the three standard AI entry points (`BuildAIRequest` / `BuildAIModelsRequest` / `SendAIRequest`) and the optional chunked transport (`HostStream`), and it fixes a deadlock in the package bridge — the package pushed to `__magpieChatPush` from inside its own hook while the reader stopped at the end marker, so the writer waited for a reader that had gone. The new Core adds the `MobileHostStream` protocol and `MobileNewMagpieWithStream`, so the selector count goes from 19 Magpie methods to 19 plus 3 standard AI; `check-core-surface.sh` follows.
| Checker | `scripts/check-core-surface.sh` checks, before a build, that the framework in `Vendor/` really exposes the 18 `MobileMagpie` methods this client calls — the exact trap that bit once (source called `chatStart`, the framework did not have it). It names what is missing and points at `scripts/fetch-core.sh`. The list uses **Objective-C selectors** (`cancelSignIn:`), not Swift's imported `cancelSign(in:)` |
| Checker (Swift) | `scripts/check-swift.py` now also catches one class of "parses here, fails on the Mac": a file naming a generated `Mobile*` type without `import VeneraCatCore`. It was added after the Mac reported exactly that about `CoreMagpie.swift`, which is invisible from Windows |
| Plugin options | `MagpieOptionStore` keeps the user's choices keyed `provider|option` (a small readable file, so a bad value can be seen rather than guessed), and `resolve` joins the plugin's declarations with those choices — **a switch nobody touched keeps the plugin's own default**. The UI writes a change to disk and pushes it to the package at once; changing only the screen would look applied while the next request, the one that reads it, still sees the old value. A missing store is reported instead of silently dropped |
| Checker | `MagpieRunner.setOptions` hands the user's choices to Core, keyed `provider|option`: one table holds every plugin's switches, and a key without the provider would leak across accounts. The switch list in the UI is not written yet |
| `MagpieCheckin` | The check-in button and its answer. The vocabulary is fixed (claimed/done/ineligible/inactive/captcha/failed), so the screen never parses a vendor's sentence; `captcha` sends the user to the vendor's own app because **nothing here solves captchas**, and `done` counts as success rather than failure. Its alert has its own title so a result does not read as an error |
| `MagpieModel` | The models the vendor lists — id, display name, context and output limits, modalities. The chat screen offers them first; when a vendor lists nothing the field falls back to typing a name and says why, rather than an empty menu that reads as "this provider has no models" |
| `MagpieUsage` | The normalised usage shape from Core. **No share means no bar** — the vendor's own words are shown instead ("No allowance reported"), because drawing 0% would tell the user there is plenty left when the truth is that this vendor does not say. With a share it draws one and keeps an overspend past 100% |
| `MagpieUsageView` | The usage screen: plan, account, each window, reset time, pull to refresh; a wallet window shows its figure rather than a ratio |
| `MagpieChat` | A reader for one turn: Core only answers when asked (gomobile cannot push), so this wraps it in an `AsyncThrowingStream` a view can `for try await`. Leaving the screen or stopping cancels **the request in Core**, instead of leaving it running against the vendor. Events carry text, reasoning, done (with the token counts as written) and errors |
| `MagpieChatView` | The conversation screen: model name, input, the reply as it arrives, and a stop button. Deliberately only a reply reader — **no tool calls and no multi-turn agent loop**, since writing one would imply those exist |
| `MagpieProvidersView` | The "AI providers" tab: installed packages with their versions and sign-in state, buttons to sign in, sign out, remove, and install from a folder. Entirely separate from comic sources: different packages, different accounts, different cookies |
| Cost of a list | The declaration is recorded at install time (`MagpiePackage.specJSON`), so refreshing the providers tab no longer starts a JavaScript runtime per package; a package installed before that is evaluated once. A test lists providers through a second view whose factory throws if it is ever called |
| Archive install | The install screen now takes an **extracted folder** or a downloaded `.zip`/`.tar.gz`: Core's `readPackageArchive` does the expanding (one enclosing directory stripped, symlinks and `../` refused, the same limits) and the client stores the table Core produced. Expanding uses a temporary Core that is closed afterwards, so an install leaves no runtime behind |
| `MagpiePackageReader` | Reads a package from a folder the user picks: files keyed by package-relative path, symlinks refused (a package is plain files), and 8 MiB per file, 32 MiB total, 1024 files — the same limits Core enforces, checked here first so a stray video is refused instead of copied. No `package.json` means "not a plugin"; a manifest that names no entry (`exports["./server"]`, `main`, `index.*`) does not count either, which is Magpie's own rule |
| `MagpiePackageStore` | Installed packages, one per provider: files kept as **original base64** in one JSON document, with the package's own `name`/`version` for the list. Installing again replaces the old copy instead of stacking; anything without a `package.json` is refused outright, since such a package only fails later, at load time, with a vaguer reason. The index is written to a temporary file and moved into place: a crash mid-write must not make the whole list — and with it every installed package — unreadable. Unpacking is not here: this takes an already unpacked file table, which Core validates again |
| `MagpieSignInView` | The SwiftUI screen, for both kinds of sign-in: **device code** (code shown and copyable, page opened, wait, cancel) and **API key** (a form built from the `prompts` the plugin declares, password fields as `SecureField`). A key settles inside `authorize`, so there is no "I'm done" button that would do nothing. It uses that vendor's own authorization on this device, never a comic source's, and shares no cookie jar with one |
| `MagpieRunner` | Installs a package (path to bytes, base64 to Core), hands over the stored sign-in, runs an export, **stores whatever the package saved afterwards** (otherwise a refresh is lost and the next launch is signed out), and on sign-out closes the instance and deletes the entry. Installation takes an already unpacked file table: unpacking belongs to Core, and this layer trusts no path Core did not validate |

`MagpieRunner.Core` is a protocol rather than the generated `MobileMagpie` directly, so the
orchestration is testable against `StubMagpieCore` without an xcframework. Seven new cases
cover the base64 round trip, no sign-in sent when none is stored, refresh write-back, an empty
write-back not overwriting, sign-out, a failed install, and exact number text surviving.

The real `MobileMagpie` adapter is in place, and `MagpieAccounts` keeps one runner plus one
cached declaration per provider. **One honest boundary:** the host protocol has no streaming
method and gomobile is pull-based, so on iOS a reply arrives **whole** — `MagpieChat` is written
as an event stream and the view renders incrementally, but the first batch of events usually
carries all of it. Real incremental output needs a streaming callback on the host protocol,
which is a change to Core's API, so it is not decided here.
7. One item needs a decision: App Transport Security. Many comic sources serve images over `http://`, and ATS refuses cleartext by default. The desktop client gets away with it because Go's `net/http` does not apply ATS; the app either allows arbitrary loads (cleartext everywhere) or carves out exceptions per host — a security trade-off, so it is not decided here.

## Waiting on a decision

Five questions are product or security calls rather than engineering: the ATS policy, migrating
cookies from the global jar into per-source partitions, the video playback architecture, whether
reference provider packages ship with Core, and one end-to-end run with a real account. Each is on
Core's [docs/OPEN-QUESTIONS.en.md](https://github.com/laincat/VeneraCat-Core/blob/main/docs/OPEN-QUESTIONS.en.md) with the current
state, the options and what staying open costs — not copied here, so the two cannot drift apart.

## iOS can read one level of replies too (2026-11-01, pin `cf9eb9b`)

After the desktop turned "N replies" into a button, iOS follows: tapping the count re-reads that level with `replyTo`, with 回复 X 的评论 and 返回全部评论 above it; going back passes an empty string, which the kit sends as `null` because a source tests for null.

**Not verified**: a reply level usually needs a login on a real source, so this is still syntax and key checks rather than live evidence.

## Voting on a comment works on iOS too (2026-11-01, pin `cf9eb9b`)

The desktop gained the vote and iOS did not. This round adds it:

- **Core**: `LikeComicComment(callID, key, comicID, subID, commentID, isLike)` — the same contract as the desktop, and **`false` takes the vote back** rather than being a second function.
- **Kit**: `likeComment(...)`, with `CommentSupport.like` deciding whether the control appears at all.
- **Interface**: each comment carries 赞 / 取消赞; the page is read again afterwards because a source may only report the new score on the next read, and the button is disabled while the vote is in flight.

**What the live check covers**: `ccc` and `zaimanhua` do declare `likeComment`, but their threads need a login, so the iOS side is still syntax, call-name and key checks — voting end to end needs a real account and a device.

## iOS opens a pasted link too (2026-11-01, pin `c414709`)

The previous round was the desktop only. This one brings the same ability to the phone:

- **Core**: `LinkDomains`, `LinkToID` and `OpenLink`. `comic.link` is an object, so it is read with `Runtime.Value` — calling it only answers "source does not define this function". When no source claims the address the target comes back empty, **which is not an error**, and the client falls back to a keyword search.
- **Kit**: `openLink(_:)`, `linkDomains(key:)` and `LinkTarget`; `looksLikeLink` lives in the kit's `LinkDetection` because it is pure logic worth testing, and a copy inside the app target is invisible to the tests.
- **Interface**: a search submission checks for an address first: recognised by a source, it **opens the comic**; otherwise it searches as before. Keywords with a dot — `12.5`, `v1.2` — are not mistaken for addresses, or every search would spend a round of source calls.

The key gate now compares `LinkTarget` (fourteen payloads).

**Not verified**: iOS is still syntax, call-name and key checks; no Mac build, no device.

## Tags are tappable on iOS now (2026-11-01, pin `0c721f3`)

The gap recorded above is closed: a tag in the details view is no longer plain text.

- **Kit**: `clickTag(key:namespace:tag:)` returns a `TagAction` (action / keyword / param); an empty action means the source has no opinion, **not a failure**.
- **Interface**: a tag is a button when the source declares `onClickTag`, and stays text when it does not. "search" opens `SourceSearchSheet` (one source's results, with numbered and cursor paging, each row opening the comic); "category" opens the category page **with the parameter the source named selected**; anything else says plainly that the source did not say what the tag means.
- **Parameter lookup**: `CategoryPart.param(forValueAt:)` and `CategoryModel.paramTarget` repeat the loader's own rule (per-value parameter, then `groupParam`, then the value).

**A silent hole found while checking**: `ComicDetails.subId` was declared but **never in `CodingKeys` and never decoded**, so every comment thread looked its comic up by an empty string. The decode is in place, with a test that a numeric sub id still travels as text.

**Not verified**: still syntax, call-name and key checks; no Mac build, no device.

## Pin `0c721f3`: Core answers what a tapped tag means; iOS does not ask yet (2026-11-01)

Core gained `ClickTag`, which hands a client the source's own meaning for a tag — a search keyword, a category parameter, or an empty action for "no opinion". **iOS only moves its pin this round**: tags are still plain text there and a tap does nothing. The desktop now opens the category tab on the parameter the source names.

## iOS has a comment thread too (2026-11-01, pin `8c5d0de`)

The desktop gained comments and iOS did not. This round adds it:

- **Core**: `CommentSupport(key)` reports which of load/send/like the source declares; `ComicComments(...)` normalises the thread into `{comments, maxPage}` — a numeric id or score stays readable text, a string reply count becomes a number, and a comment without an id is still a comment; `SendComicComment(...)`. The shapes are named types so the key gate can compare them.
- **Kit**: `commentSupport` / `comments` / `sendComment`, and `ComicComment` gives an id-less comment a stable `identity`, which a list needs to tell two rows apart.
- **Interface**: `ComicCommentsView` — list, pages, reply, send, refresh; `ComicDetailView` shows 评论 only when the source declares comments (`commentSupport` is read with the details, not in the view body). `ComicDetails` carries `subId`.

The key gate now compares `ComicComment`, `CommentSupport` and `TagAction` (thirteen payloads), verified negatively: renaming `replyCount` to `replyTotal` in Swift makes it name the key and exit 1.

**Not verified**: the iOS side is still syntax, call-name and key checks; no Mac build, no device.

## The iOS browse page uses Core's shared implementation now (2026-11-01, pin `c855fd3`)

The gap recorded in the previous section is closed: browse **shape normalisation** (the four types and the `load`/`loadNext` fallback) moved into Core's `comic/js`, and both the desktop and iOS call it instead of building `explore[i].load` themselves.

- **Core**: `js.Runtime.Explore` normalises the four shapes and handles cursors; `mobile.ComicExplore(callID, key, index, page, cursor)` hands it to the phone. Both have tests (shapes, cursor fallback, an index past the end).
- **Kit**: `explore(key:index:page:cursor:)` goes through `comicExplore` rather than building the path; `ExploreResult.next` carries the cursor back.
- **Interface**: a cursor browse shows 第 N 批 instead of inventing a page count, and 上一页 is hidden there — the source only hands out the next token, and going back would need history this does not keep.

**Not verified**: the iOS side is still syntax and key checks only; no Mac build, no device.

## On iOS the browse page is still broken for cursor sources (2026-11-01, pin `110b0d8`)

The desktop sweep found all three of `ehentai`'s browses unusable — it declares only `loadNext(next)` and the client only called `load`. Core's part is fixed (a UI call with no result no longer fails without a handler).

**iOS only moves its pin this round**: `CoreClient.explore` builds `explore[i].load` itself and never goes through Core's cursor fallback, so a source like `ehentai` still fails there. That is a known gap, not something fixed.

## The iOS panel would have been empty in the same situation (2026-11-01, pin `7019844`)

After the desktop started recording Core's own failures, the same check on iOS found that mobile's `CallComic` **recorded nothing either**. The most ordinary failure — a site answering 403 — would have left the iOS panel as empty as the desktop one was before the fix.

- `CallComic` now records the source key, the call path and the cause when the source is unknown or the call fails, the same shape the desktop writes.
- Verified negatively: turning that `if err != nil` into `if false` makes the test fail immediately, and restoring it passes.

## iOS has a source log panel too (2026-11-01, pin `02edab3`)

The previous section said iOS's log panel was not written; this round adds it:

- **Core**: `LogLines()` returns the last 400 lines as JSON (source key and a millisecond timestamp), `ClearLogLines()` empties them. An empty buffer is `[]` rather than `null`, because the client decodes an array and `null` is not one. The host still receives every line, so existing console output loses nothing.
- **Kit**: `logLines()` / `clearLogLines()`, plus `SourceLogEntry`.
- **Interface**: 源日志 in the sources menu opens a list (time, source key, title, text; errors red, warnings orange) with 复制全部 for a report, 清空, and pull to refresh.

Two capability paths were added to the gate, and `mobile.LogEntry ↔ SourceLogEntry` joined the key check (ten payloads now); the negative run renames `time` to `when` in Swift and the gate names the key and exits 1.

## Pin `ab719fb`: Core tags a source's log lines with the source (2026-11-01)

Core gains an optional `Services.LogSource` (with the source key) and keeps the last 400 lines for a client to show; the desktop has a 源日志 panel. **iOS only moves its pin this round — its log panel is not written**, so the same lines still go to the console there.

## Pin `a93ac09`: base64 tolerates transport artefacts (2026-11-01)

Core now drops a UTF-8 BOM and ASCII whitespace before decoding base64. It was triggered by a real source's domain-list endpoint starting to answer with a BOM, which crashed its init on `null.length` before its own fallback list could run. iOS only moves its pin.

## The key check now covers the restore plan (2026-11-01)

The importer only started reading `entry.data` this round: if Core spelled a key differently from Swift, the result would be the same bug being fixed — writing nothing, silently. `check-json-keys.py` gains `backup.Plan ↔ BackupPlan` and `backup.SourceRestore ↔ BackupSource`, and now compares 9 payloads.

The negative check was run: renaming `data` in the Swift model makes the gate report "BackupSource reads \"sourceDataRenamed\", which Core's SourceRestore never sends" and exit 1; restoring the name returns it to ok.

## Pin `9013ca5`: an export can no longer be written into something unreadable (2026-11-01)

Core's writer checked the script's size and not `comic_source/<key>.data`, while the reader caps every `comic_source/` file at 16 MiB. The writer now holds the same cap and refuses, naming the source. iOS only moves its pin here; no interface change.

## The iOS import never wrote a source's data at all (2026-11-01)

After fixing `.data` on the desktop, checking iOS turned up something worse: **`BackupImporter` never read `entry.data`** — an imported source got its script and lost its data and settings, with no notice. The desktop, at least, wrote the data.

Now:

- **Import**: once a source installs, `restoreValues` splits its values by the keys the source declares under `settings` — declared ones go to the settings bucket, the rest to data. **A source that fails to install writes nothing**: guessing a bucket means putting a token in the settings panel.
- **Export**: `SourceStore.allValues(key:)` merges both buckets into the single object the archive asks for, with data winning a name clash.
- The import summary gained 源数据 N 项 so success is not reported as nothing.

A test pins `allValues`: settings keys appear, and a data key overrides a settings key of the same name.

## The export carries each source's own data (2026-11-01, pin `e46c8f9`)

The first version exported only the script, so a restored source came back logged out and unsure which domain it was on. The format also holds `comic_source/<key>.data`.

- Core cannot enumerate the host's store, so `ExportBackup` takes a `sourceDataJSON` shaped `{"<key>": {"<name>": <value>}}`.
- The kit's `exportBackup(searchHistory:sourceKeys:)` collects it per source through `SourceStore.allData(key:)`, which returns that source's whole data object as JSON text (`{}` when it stored nothing).
- The screen passes `library.comicSources.map(\.key)`.

A test pins `allData`'s shape: key order, the big integer `12345678901234567890` kept exact, and `{}` for a source with no data.

**Per-source settings still do not travel** — a separate bucket here, and merging it would make the importer file settings as data.

## iOS exports backups too (2026-11-01, pin `36707d5`)

The previous section said iOS's export screen was not written; this round adds it:

- **Core**: `ExportBackup(historyJSON)`, which returns **base64 rather than `[]byte`** — every method here crosses the bridge as a string, so the Swift binding shape is known, while a `[]byte` return would be a shape nothing on this machine can confirm. The client decodes it back to `Data`.
- **Kit**: `exportBackup(searchHistory:)` takes any `Sequence<String>` and turns Core's base64 into `Data`; anything that is not base64 is an error rather than an empty file.
- **Interface**: the sources screen's import menu gains 导出备份: it takes the installed sources plus this device's search history (**reversed**, to match the archive's oldest-first order), writes `nekularity-<timestamp>.venera` to the temporary directory, and offers the share sheet (Files, mail, whatever is installed).

Core's tests cover the round trip: read the export back with Core's own reader, check the source key and script text arrive, the history keeps its order, the archive holds **no** `cookie.db`, and history that is not an array is an error.

## Core can write a .venera backup now; the pin follows (2026-11-01, pin `ffdfbe7`)

Core gained `backup.Write` (sources plus `appdata.json`, fixed key order, two exports byte-identical), and the desktop has an export button. **iOS only moved its pin this round — its export screen is not written yet**, and that is the whole of the iOS side here.

## Checking that the keys the kit decodes are keys Core sends (2026-11-01)

The same failure kept returning: Core renames or drops a field, the client decodes the payload without complaint, the field is always `nil`, and the screen simply shows less. Nothing reports it.

`scripts/check-json-keys.py` covers that: it compares, per type, a Go struct's `json` tags in Core against the `CodingKeys` of the matching Swift type (or, without one, its **own** stored properties). It checks the dangerous direction only — a key the kit reads that Core never sends.

Writing the check hit three traps, all fixed:

- The first version scanned files for `CodingKeys` and picked up a **nested** type's keys, reporting a comic's `id`/`tags` as category-page keys: 41 false problems.
- The second fell back to property names and counted **computed** properties (`id`, `isRandom`, `isMultiSelect`).
- The third still counted **nested struct** members (`SourceSetting.Option.value`); it now takes only depth-one stored properties.

All 7 payloads agree now. Checked negatively: renaming `groupParam` to `groupParamRenamed` made it report `CategoryPart reads "groupParamRenamed", which Core's CategoryPart never sends` and exit 1; restoring returned `ok`. It runs from `verify-ios.sh`, skipping when Core is unavailable.

**Boundary**: it compares only the 7 pairs in its table, and only names — not types. A comic's own `tags`/`chapters` come from the source script, not from Core, so they are out of scope.

## Arity audit: 34 sources compared one by one (2026-11-01)

The `favoriteId` bug last round was "the source declares four arguments and we passed three", failing silently, so this round compared the same thing everywhere: every method we call was extracted from the 34 official sources and matched against what the client passes.

| Method | What the sources declare | The client |
| --- | --- | --- |
| `comic.loadEp` | all 34: `(comicId, epId)` | 2 |
| `comic.loadInfo` | `(id)` | 1 |
| `search.load` | `(keyword, options, page)` ×30, `(keyword, _, page)` ×2 | 3 |
| `categoryComics.load` | `(category, param, options, page)` ×26, `(category, params, options, page)` ×4 | 4 |
| `explore[i].load` | `(page)` or `()` | 1 |
| `favorites.loadComics` | `(page, folder)` ×13, `(page)` ×1 | 2 |
| `favorites.addOrDelFavorite` | 3 or 4 arguments | 4 (fixed last round) |

Two that looked suspicious and are **not** problems:

- `categoryComics.load(category, params, …)` only **spells it in the plural**: the source does `params.split('@')`, so a single string is right (`baihehui`, `goda`, `mh1234`, `mh18`).
- `ehentai`'s `onImageLoad(image, comicId, epId, nl)` — the fourth argument is a token the **source generates and passes back only through its own retry closure**; `undefined` on the first call is correct, and the retry runs through the source's own `onLoadFailed`.

The iOS category options also gained **multi-select** now (values travel as a JSON array string, as in search). To be clear: **no** official source uses `multi-select` in `categoryComics.optionList` — both occurrences are in `search.optionList`, which both clients already handled. So this is defensive, not a fix, and is recorded as such.

## Removal needs the source's own handle (2026-11-01)

The same fix as the desktop: iOS carries `favoriteId` now. Both `Comic` and `ComicDetails` decode it, and `setFavorite` always passes the fourth argument — the handle when there is one, `null` otherwise.

Worth recording why: wnacg's delete URL is `users-fav_del-id-${favoriteId}.html`, so without the handle the request went to `del-id-undefined` and **answered 200 with the source reporting success** — it looked removed and was not. That class of failure is much harder to notice than an error.

## Favorite to the source: the details page can add and remove (2026-11-01)

Matching the desktop: the details page carries 收藏到源 beside the local shelf. A source with several folders gets a picker, the button reads 已在源收藏 when the comic is already in the chosen one and removes it when pressed again, and whatever the source throws is shown as written. Two lists, two controls.

A source with only a folder toggle and no list (`ehentai`) does not appear here — there would be nowhere to see the comic afterwards. A single-folder source is passed `nil`, not an empty string.

The kit gained `setFavorite(key:comicID:folder:adding:)`, and `scripts/check-capabilities.sh` now guards that path too.

## Checking off-machine that every Core method the kit calls exists (2026-11-01)

There is no Mac here, and the `MobileCore` bridge only exists once `fetch-core.sh` has built it there — so a Swift file naming `core.categoryComics(...)` when no such method exists gives **no feedback at all** until the Mac.

`scripts/check-kit-core-calls.py` closes that gap: it parses the method names gomobile exports from Core's `mobile/*.go` (`func (c *Core)` and `func (m *Magpie)`), parses the methods this kit declares (since `core` may also be a `CoreClient`), and checks every `core.xxx(` call against that set. Exit code 3 when no Core checkout is available, which `verify-ios.sh` treats as a skip.

It compares **names, not signatures**, so argument types still need the Mac. It does catch what actually happens: a method that was never added, or was renamed. Checked negatively: renaming `hasComic` to `hasComicGone` and `categoryComics` to `categoryComicsTypo` each made the script name the file, line and call and exit 1; restoring returned `ok (69 calls against 277 known names)`.

## "The source declares it, the client ignores it" is a gate now (2026-11-01)

The same kind of problem kept coming up: a source declares a capability in its script (`category`, `ranking`, `account`, `favorites`, `translation`) and the client cannot read it, with **an empty screen or an English key** as the only symptom. Each one had to be found by reading the contracts again by eye.

Both repositories now have `scripts/check-capabilities.sh`, which lists — per capability — the Core/Kit entry point and the interface entry point, matched as **fixed strings** (so a rename cannot keep passing on a shared prefix), and fails when any one of those paths disappears. On iOS it runs from `scripts/verify-ios.sh` (the Mac step); on the desktop from `scripts/check.sh`.

Checked negatively: renaming `favoritesView`, renaming `"favorites.loadComics"` and renaming `accountSection` each made the script name the missing capability and exit non-zero; restoring them returned `ok`.

It only guarantees the **path still exists**, not that the behaviour is right — that still needs the live tests and captures.

## A source's own favorites: both clients now (2026-11-01, pin `f8ec81a`)

A `favorites` block holds the favorites the source keeps **on its own side**, which is a different thing from the local shelf. The three measured shapes differ: `nhentai` has one folder, a list and no folder list; `ehentai` has folders and a folder list but **no list function**; `wnacg` has all three.

- **Core**: a new `Value` reads **data** (`favorites.multiFolder` is data, while `Call` invokes functions), and gomobile gains `ComicValue`.
- **Kit**: `FavoritesSupport{supported,multiFolder,folders,canLoad}` follows from the declared paths plus `multiFolder`; `favoriteFolders` / `favoriteComics` pass what the source expects (a single-folder source gets **no** folder id).
- **Interface**: the source's detail page grows a 源收藏 entry. A source that can list shows its folders and list; one like `ehentai` that only has folders says "这个源没有提供收藏列表" and **never calls a function that does not exist**; a missing session shows the **source's own words** and a retry.

## Interface text follows the source's own table (2026-11-01, pin `239221b`)

A source may keep its interface text in a `translation` table and write only a key in a setting (`title: "domain"`). iOS reads that table too now: `CoreClient.translations(key:)` returns the mapping for the device's locale, and the settings screen resolves titles through `model.title(setting)`, falling back to the key. Cookie field names are not translated — those are cookie names.

## Source accounts: both clients now (2026-11-01, pin `8d2e9db`)

Fifteen official sources declare an `account`, in **three** different styles: password, in-page login, and cookie fields. The desktop draws a panel per declaration (the table and measurements are in that repository's `docs/STATUS.md`); iOS has it now too:

- **Kit**: `AccountStyles{password,webview,cookies,logout}` comes from `accountStyles(key:)`, which asks Core once per style with `hasComic` instead of guessing; `accountCookieFields` uses a new Core bridge entry, because the cookie names are **data** that `CallComic` cannot reach; `loginAccount` / `loginWithCookies` / `logoutAccount` run through the existing `CallComic`.
- **Interface**: the source settings screen grows an 账号 section — account, password, 登录 and 登出 for the password style; one field per declared cookie name plus 校验并保存, letting the source's own `validate` decide; the source's error text is shown as written; a source that only offered in-page login (`nhentai`) could only say iOS 端暂不支持 at the time — **that was fixed later**, see the in-page login section below. A source that needs no account grows no section at all.

Core published `8d2e9db` (the `AccountCookieFields` bridge entry) and the pin follows — Core keeps a single-commit history, so an old pin is replaced rather than kept.

## The ranking page is wired up too (2026-11-01, pin `c22a944`)

A source's `enableRankingPage` with `categoryComics.ranking` is **a separate entry** — nine official sources declare one, and neither client read it. The kit's `CategoryPage.ranking` now carries a flat option list (`RankingOption{value,label}`), `CoreClient.rankingComics` calls `categoryComics.ranking.load`, and the category screen grows a 排行 row that reuses the same list and pager (`rankOption` records whether the list came from the ranking, a dimension or a random search).

Core published `c22a944` this round and the pin moved off `26dc9a7` — **Core keeps a single-commit history, so an old pin is replaced rather than kept**, and leaving it behind points at a commit that no longer exists.

## Category browsing: wired up, not yet run on a Mac (2026-11-01, pin `26dc9a7`)

The desktop could read a source's category page for a while; iOS could not, because the bridge had no entry for it. Three layers were added:

- **Core**: `mobile.Core.Category` returns `{"title","parts":[...],"options":[...]}` — the same shape as `SearchOptions`, so a client reuses its filter code — and `mobile.Core.CategoryComics` loads one page, cancellable by `callID`. A source without a category page answers `{}` rather than failing. Core is published and both clients' pins moved with it.
- **Kit**: `CategoryPage`/`CategoryPart` and `CoreClient.categoryPage` / `categoryComics`. What a value maps to is decided here, in the order per-value parameter, then the dimension's `groupParam`, then the value itself.
- **App**: in the 浏览 tab a source that declares a category page grows a 分类 chip; inside, each dimension is a row of values, an option reloads the list, and pages work. A `random` dimension is a 随机一个标签 button that searches for **one** value — **it is never loaded as a category, and never joins several tags**: the source's `randomNumber` is "how many comics to show at the same time", while a comic search reads several tags as all of them, which on the live `nhentai` answered nothing at ten tags and was refused at twenty.

`scripts/check-swift.py` parses all 79 files, and that round also fixed a gate that had been **failing on main all along**: `MagpieUsage` has a property named `each`, which tree-sitter reads as the parameter-pack keyword, so `each = try …` looked like a syntax error. The checker now treats `each` as an identifier (parameter packs do not appear in this codebase), taking the gate from "1 problem" back to "79 files parse".

**Boundary**: `swift build`, the unit tests and an App build have not run on a Mac yet, so this shows the syntax parses and the logic follows Core's contract — not that it compiles. The category page and the random search on a device are unverified.

**In-page login and the source API level: the app could install no official source, and its login buttons did nothing (2026-11-01, pin `9701b58`)**: both were fixed this round, and both were reproduced before being changed.

1. **Source API level**: the client reported its **own** version `0.1.0` as the source API level, while every official source declares `minAppVersion = "1.0.0"` or higher, so Core refused all of them — `js: invalid source: minAppVersion 1.0.0 is required` — and the source list was permanently empty. The desktop client had already separated the two (`internal/sourceapi.Level = 1.6.3`); iOS now does too, with the level in the kit as `SourceAPI.level` and three tests pinning the behaviour: the reported level installs an official source, the app's own version does not, and a source that asks for `9.0.0` is still refused, so the level is a bounded claim rather than a bypass.

2. **In-page login**: `nhentai`, `ehentai`, `ccc`, `mycomic` and `manga_dex` declare `account.loginWithWebview`, whose two callbacks are functions and cannot cross the language boundary, so Core names them with a handle. iOS gains `WebviewLoginSession` (a non-persistent WKWebView, so it cannot see another source's session) and `WebviewLoginView`: after every navigation it asks the source's own `checkStatus(url, title)`, and once that agrees it imports only the **login site's** cookies (starting and finishing host alike) into the source's partition and runs `onLoginSuccess`.

The same round fixed two things beside it: the logout button sat inside the password branch, so a source that only logs in on its page could not log out; and a `type: "callback"` setting said "a source-side action the client does not support", where it now draws the source's own `buttonText` and runs it.

Verification boundary: this Swift code has no compiler on the machine it was written on, so only syntax, Core call names and JSON keys were checked offline; compiling, unit tests and simulator runs happen on the Mac and are recorded separately.
