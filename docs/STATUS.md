[English](STATUS.en.md) · 简体中文












## 0.4.1 / build 23 已发布并核对（2026-11-05）

tag `v0.4.1` → `ede845c`；发布 CI `42103870843` 全绿。

| 项 | 值 |
| --- | --- |
| 公开下载 | **HTTP 200** |
| 大小 | **29,754,414 bytes**，与资产一致 |
| SHA-256 | `6be3769c0a9447100740b6893e3031c07f172580cb46a3c655bfa26b9447bcb5` |
| IPA 内容 | **13 PASS / 0 FAIL**：两层 CRC、单一 app、App `0.4.1`/`23`、最低 26.0、Widget 同为 `0.4.1`/`23`、Core 标记 `1574076` |

AltStore 刷新 run `42107774868` 成功，`apps.json` `7ae8f4a`；三个入口均 `0.4.1 / 23 / 29754414 / 26.0`。Release 说明为中英双语。
## 账号值页的插值曾被写成字面量（`a87f5d9`）

模拟器验收抓到：`ServiceAccountsView.swift` 里 5 处写成了双反斜杠，界面直接把代码显示出来——

- 页脚：`(record.name) 申请了「读取账号值」…`
- 保存提示：`已保存 \(name)`
- 删除提示、无障碍标识同样

已全部改为单反斜杠插值。**并加了一条检查**：`scripts/check-swift.py` 现在把「双反斜杠 + 括号 + 表达式 + 右括号」的形状判为错误；负控故意放回双反斜杠时报 `line 105: interpolation written with two backslashes`，改回后通过。解析器与类型检查都不会报这类问题，只有屏幕会。

CI `42097670057` 全绿，Kit **474 tests / 83 suites / 0 失败**。
## 运行服务时可以选方法、填参数（`ac29460` + `db1` 修复）

原先只能按 `ping`、参数固定 `null`。现在是一个独立的运行面板：

- 方法列表来自服务自己的 `describe()`；没有声明时只有一个 `ping` 作为诚实回退
- 参数是 JSON 文本框，**非 JSON 直接拦下不发送**（本地先校验，不让 Core 去报错）
- 面板里写明这次调用授予的权限，以及「它仍然读不到你保存的账号值以外的任何东西」

CI 第一次是失败的：`App/ServiceRunSheet.swift:22:41: error: extra arguments at positions #1, #2` —— `ServiceMethod` 的成员初始化器是 internal，App 目标造不出 `ping` 回退值。补公开 `init` 后 CI `42093319801` 全绿，Kit **474 tests / 83 suites / 0 失败**。
## 0.4.1 / build 23（2026-11-05）

0.4.0 的账号值界面把插值写成了字面量（页脚显示 `(record.name) 申请了…`、保存提示显示 `已保存 \(name)`）。这一版修掉它，并带上：

- 运行面板：选方法、填 JSON 参数，非 JSON 本地拦下；权限与账号值范围写在面板里
- `check-swift.py` 新增一条规则：双反斜杠插值即报错，防止再犯
- 服务包移除时清 Keychain 账号值与 Core 旧运行时

## 0.4.0 / build 22 已发布并核对（2026-11-05）

tag `v0.4.0` → `12bbb28`；发布 CI `42081589626` 全绿。

| 项 | 值 |
| --- | --- |
| 公开下载 | **HTTP 200** |
| 大小 | **29,758,353 bytes**，与资产一致 |
| SHA-256 | `642feabaea7cec136abe1b69d6760676ade93acd26630a81a01f356172454e26` |
| IPA 内容 | **13 PASS / 0 FAIL**：两层 CRC、单一 app、App `0.4.0`/`22`、最低 iOS 26.0、Widget 同为 `0.4.0`/`22`、二进制含 Core 标记 `1574076` |

AltStore 刷新 run `42088211577` 成功，`apps.json` 提交 `c91a885`；三个入口均为 `0.4.0 / 22 / 29758353 / 26.0`；图标 200 / 443,517 bytes。Release 说明为中英双语。

**一处更正**：打标签前漏跑 `check-core-pin.sh`，说明里先写了 `563f169`，而包内实际是 `1574076`（`563f169` 只是 Core 侧测试与文档提交）。已改文档与 Release 说明，并重跑核对脚本确认二进制里就是 `1574076`。核对脚本第一次报 FAIL 正是因为期望值写成了 `563f169`——这类不一致必须由产物说话。
## 移除服务包时一并清掉账号值与旧运行时（`a47e77f`）

两个真实的遗留问题：

- **Keychain 里留着可用凭据**：包删了，账号值还在，卸载并不能吊销它们。`ServiceAccounts` 增加 `removeAll(service:)`，`ServiceStore.remove` 在 Core 删除成功后调用它；**删除失败时不动**（错误路径上不该顺手清东西）。
- **旧运行时继续服务重装的包**：Core 的 supervisor 按 dataDir 缓存，删除或替换后仍可能把旧代码的运行时给下一次调用。新增 `CoreService.forget(dataDir:)` 调 `MobileServiceRunForget`，删除时一并丢弃。

回归 `removingAPackageForgetsItsAccountValues`：先让删除失败（不存在的包），断言值**仍在**；再显式清一个服务，断言它为空、另一个服务的值不受影响。CI `42075251630` 全绿，Kit **474 tests / 83 suites / 0 失败**。
## iOS 有了服务账号值：Keychain 存，运行时才交给 Core（`ff01dcd`）

上一轮只把契约打通，这一轮补客户端：

- 服务页长按 →「账号值…」→ 录入 `键 / 值`；值存**本环境的 Keychain**（`AfterFirstUnlockThisDeviceOnly`，与 Magpie 登录同一套理由：备份还原到别的设备不该带走可用凭据）
- 列表只显示**键名**与「已保存」，值保存后不再显示；滑动删除
- 只有该包申请了 `secrets` 时，运行时才把值交给 Core；没申请时页面明说「这里保存的值它读不到」
- 交给 Core 的是**这次调用**的完整集合，Core 没有自己的存储，所以没传的键读不到

回归：`aRunPassesOnlyTheStoredAccountValues`（按服务隔离，删除后为空）、`aRunWithoutAccountValuesSendsNone`。CI `42065468307` 全绿，Kit **473 tests / 83 suites / 0 失败**。

**边界**：模拟器/真机上的实机录入与运行待验证；服务包自己声明需要哪些键的机制不存在（Core 只暴露权限），所以键名由使用者决定。
## 服务可以读到客户端给的账号值（pin 跟到 `1574076`）

Core 新增 `ServiceCallWithSecrets`：账号值由客户端在一次调用里传入（`{"key":"value"}`），只在 `secrets` 权限下可达，未提供的键会被指名报错。`CoreService.call` 增加可选 `secrets` 参数，默认空表示不传。

客户端还**没有**录入与保存服务账号值的界面——这一步只把契约接通；`ServiceStore` 目前不传账号值，所以申请 `secrets` 的服务仍会在读值时被指名拒绝。
## 宿主请求形状有了客户端回归（2026-11-05）

服务 fetch 那次失败（请求里没有 `cookies` → `JSONDecoder` 在拨号前抛 `keyNotFound` → 夹具 0 请求）只在模拟器上抓到的，现在有了 Kit 层的钉住用例：

`HostRequestShapeTests.aRequestWithoutCookiesIsStillSent` 在 `127.0.0.1` 起一个真实 TCP 监听，把**省略 `cookies` 和 `bodyBase64`** 的请求原样交给 `CoreHost.http`，断言请求确实发出（服务端计数 1）、状态 200、`bodyBase64` 解出的正文正确。这条同时钉住两件事：协议字段可以省略，以及省略不等于静默失败。

CI `42050804199` 全绿，Kit **471 tests / 83 suites / 0 失败**。
## 服务的网络确实走 App 的传输（Mac，iPhone 17 / iOS 27.2，`641172c`）

`cookies` 契约修好之后复测同一个包：`ping` 里去 `fetch(http://127.0.0.1:18798/proof)`，界面「运行结果」显示 **`{"fetched":"fixture-proof-7K3 来自夹具"}`**，用例 **PASS 52.3 秒**。

关键不是那段字符串，而是夹具侧记到了**一条来自模拟器 App 的请求**：

```
{"t":"2026-11-05T22:26:35","method":"GET","path":"/proof",
 "ua":"Mozilla/5.0 (iPhone; CPU iPhone OS 27_2 like Mac OS X) …Safari/604.1","accept":"*/*"}
```

UA 是 App 的，不是 curl 的，说明服务的 fetch 确实经 `CoreHost` 走到 `URLSessionTransport`，而不是 Core 自己开了连接。截图 `fetch-retest.png`，日志 `/tmp/nk-service-run2/fetch.log`。
## 服务页改按服务自己说的方法运行（2026-11-05）

Core 新增 `mobile.ServiceDescribe`（`83253db`）后，客户端的「运行」不再只会按 `ping`：

- 点「运行」先问服务 `describe()`，确认框里出现的是**它自己列的方法**（`{"name":"sync","title":"同步"}` → 按钮「同步」）
- 没有 `describe` 的服务的回答是空列表，此时仍提供「运行 ping」作为诚实回退，而不是编一个方法
- 描述结果按包 id 归属（`offeredMethods(for:)`），A 的方法不会被显示在 B 上
- 描述在**不授予任何权限**的前提下进行；需要网络才能描述自己的服务会报错，页面随即退回 ping

回归：`adscriptionIsNotOfferedForAnotherPackage` 钉住归属；Core 侧两条（带 `describe` 得到 `sync`/`同步`，不带得到 `[]`）。pin 跟到 `83253db`；CI `42044441869` 全绿，Kit **470 tests / 83 suites / 0 失败**。
## 服务的 fetch 不再在拨号前失败（2026-11-05）

Mac 在模拟器上的一条实测发现：服务的 `ping` 里去 `fetch(http://127.0.0.1:18798/proof)`，界面报 `service: fixture-fetch failed on "ping": Error: 未能读取数据，因为数据丢失。`，而**夹具 0 条请求**——请求从没发出。

原因在两端之间：Core 拼给客户端的请求 JSON 缺 `cookies`（`Host.HTTP` 契约里列了它），Nekularity 的 `WireRequest.cookies` 是非可选 `Bool`，于是 `JSONDecoder` 在拨号前抛 `keyNotFound`。这条同时说明「Core 侧少了字段」和「客户端把契约读得过窄」是两个独立缺陷。

两侧都改：Core 固定带 `"cookies": false`；客户端改为 `Bool?`、缺省按 `false`。回归 `TestAServiceFetchGoesThroughTheClient` 断言该字段存在且为 `false`，负控删掉后失败（`cookies = <nil> (present=false), want false`）。Core pin 跟到 `2d1dd76`。

同一轮里另外三条实测通过：`ping` 直返（`{"from":"fixture-ping","ok":true}`，PASS 52.7s）、坏包文案（`服务包未被接受：service: package has no service.json`）、只申请 `storage` 的包在 `ping` 里 fetch 被指名拒绝（`may not use the network: it did not ask for the "network" permission`）。
## 0.4.0 / build 22（2026-11-05）

服务包从「能装」做到「能用」：

- 服务页：列表、导入（摘要按实际字节）、移除；被拒绝的包说明原因
- 运行：先问 `describe()` 再按服务声明的方法给按钮，没声明才回退 `ping`；权限在运行前确认，Core 取交集
- 账号值：Keychain 存储（`AfterFirstUnlockThisDeviceOnly`）、只显示键名、只在一次调用里交给 Core；卸载包时一并清除，旧运行时也丢弃
- 标准接口一次提问不再画两条回复；包内 Core pin 是 `1574076`（`563f169` 只是 Core 侧的测试与文档提交，不需要跟）

**验证渠道**：服务页的列表/导入/移除/坏包文案/`ping`/`fetch` 经 App 传输在 iPhone 17 / iOS 27.2 上实测通过；`describe()` 方法清单与账号值界面目前只有 CI 证据（Kit 474 tests），真机录入与运行待验。

## 0.3.9 / build 21 已发布并核对（2026-11-05）

tag `v0.3.9` → `44d3845`，发布 CI `42034138520` 全绿。

| 项 | 值 |
| --- | --- |
| 公开下载 | **HTTP 200**（GET 与 HEAD 都是 200） |
| 大小 | **29,694,417 bytes**，与 Release 资产一致 |
| SHA-256 | `ca8bf68c1ceca40ddff8cad0ba82349c3f0f33d8792bdb21b733ad42a90d0067` |
| IPA 内容核对 | **13 PASS / 0 FAIL**：两层 CRC、单一 app、App `0.3.9`/`21`、最低 iOS 26.0、`NekularityWidgets.appex` 同为 `0.3.9`/`21`、二进制含 Core 标记 `998f3b9` |

AltStore 刷新 run `42038005313` 成功，`apps.json` 提交 `f8bf8aa`；三个入口（GitHub Raw、`https://cnb.cool/laincat/AltStore/-/git/raw/main/apps.json`、固定 Release）都是 `0.3.9 / 21 / 29694417 / 26.0`；图标 HTTP 200、443,517 bytes、PNG 1024×1024。Release 说明改写为中英双语。

## 0.3.9 / build 21（2026-11-05）

带上这一轮的全部修复与能力：

- 标准接口的一次提问不再画两条回复（`StandardConversation`，附 5 条单测）
- iOS 有了服务包界面：列表、导入（摘要由客户端对实际字节计算）、移除，被拒绝的包会说明原因
- 服务包可以**运行**：`CoreService.call` 把本机 Host 交给 Core，服务的 fetch 走 App 的传输，权限在运行前由用户确认、由 Core 取交集收窄
- Core pin `0f1e7b8` → `998f3b9`

## 坏包拒绝文案的界面复验（Mac，iPhone 17 / iOS 27.2，`e7c5507`）

走 App 自己的入口导入缺 `service.json` 的包，界面显示红色提示：**`服务包未被接受：service: package has no service.json`**，位于「已安装」上方；列表仍是「还没有服务」，被拒绝的包没有进入列表。用例 `ZZServicesRejectTests` **PASS 34.1 秒**。截图 `rejected-wording.png`，日志 `/tmp/nk-services-ui/run3.log`。

## iOS 能把服务跑起来了（`bef0181`，pin `998f3b9`）

Core 新增 `mobile.ServiceCall` 之后，客户端把最后一段接上：

- `CoreService.call(host:dataDir:id:method:payload:granted:)` 把本机 `CoreHost` 交给 Core，服务的 `fetch` 走 App 自己的传输（Cookie、证书、代理都还是客户端的）
- `ServiceStore.call` 记录一次运行的结果（成功/失败 + 原文），服务页在顶部显示「运行结果」/「运行失败」
- 服务页行上左滑「运行」或长按「运行 ping」；运行前弹确认框列出该包申请的权限，用户确认后才授予，**Core 取交集，授予只能收窄**
- pin 从 `0f1e7b8` 跟到 `998f3b9`（含 `mobile/service_run.go`）

**验证**：CI `42030522124` 全绿，Kit **469 tests / 83 suites / 0 失败**（新增 `Test aRunWithoutAHostSaysSo`：没有宿主时明确说「没有宿主，无法运行服务」而不是假装调用）。

**边界**：模拟器上的实机闭环（装包 → 运行 → 服务 fetch 走 App 传输 → 权限收窄）已在派单中，尚未回传；账号值仍由客户端保存，服务读不到。

## 服务包界面：列表/导入/移除通过，坏包文案缺失已修（2026-11-05）

Mac 在 iPhone 17 / iOS 27.2 上走 App 自己的入口实测（`9eb1f5c`）：

| 项 | 结果 |
| --- | --- |
| 空列表 | PASS，「还没有服务」 |
| 导入（系统文件选择器，Safari 下载的 zip） | PASS，行文本实测「夹具服务、1.0.0、fixture-service、网络（经宿主）」 |
| 移除（左滑 + 确认） | PASS，确认文案「…的代码会从这台设备删除；它保存的账号值不在这里。」，之后回到空列表 |
| 坏包（缺 `service.json`） | **FAIL**：界面没有任何拒绝文案 |

原因是 `ServiceStore` 的 catch 先写 `error`，紧接着 `reload()`，而 `reload()` 的成功分支把 `error` 置回 `nil`——文案被自己的刷新清掉。已改（`e7c5507`）：`install` 与 `remove` 的 catch 在刷新列表时保留原因，Core 的原句「package has no service.json」经界面文案露出为「服务包未被接受：…」。回归 `Test aRejectedPackageKeepsItsReason`（走真实 `install` 路径），CI `42027315970` Kit **468 tests / 83 suites / 0 失败**。

另两条实测事实：Core 的 `idPattern` 不接受下划线，`fixture_service` 这种 id 会被 Core 拒绝；直接把 zip 拷进 `File Provider Storage/Downloads` 不会被 Files 索引，只有经 Safari 下载的才在选择器里可选。

## 重复回复修复的模拟器复验（Mac，2026-11-05）

`d1d989d`（含修复 `0b53d42`）在 iPhone 17 / iOS 27.2 上重跑标准 AI 回环：临时用例 `ZZStandardAINoDuplicateTests` **PASS 39.5 秒**，夹具 `UITests/Fixtures/standard-ai/serve.py`（127.0.0.1:18796）。

| 断言 | 结果 |
| --- | --- |
| 一次提问的助手回复条数 | `first_answers=1` |
| 「整包返回 · 流式尚未接通」标注次数 | `note_count=1` |
| 夹具请求数 | 每问 1 次（两问共 2 次），`authorized=true`、`answered 200` |
| 第二句后的历史顺序 | 「第一句、Fixture Chat answer、第二句、Fixture Chat answer」——问、答、问、答，无重复；首条回答折入历史且不带标注，末条为尾部并带标注 |

截图 `after-first-question.png` / `after-second-question.png`，日志 `/tmp/nk-ios-ipad-type/dup3-ui.log`。

**过程说明（非产品问题）**：第一次运行失败，因为上一轮残留配置写进了字段（地址与模型被追加成重复串），App 如实显示 `接口返回 HTTP 404: unknown fixture root`；`simctl uninstall` 清空后重跑通过。这条同时说明错误信息足够具体，能让人找到原因。

**边界**：临时用例已删除、工程文件已还原、`git status` 干净；真机与真实供应商账号仍未验证。

## iOS 有了服务包列表与导入界面（2026-11-05）

在 `CoreService` 之上加了 `ServiceStore`（Kit）与 `ServicesView`（设置 → 模块与源 → 服务）：

- 列出 Core 记录的服务包：名字、版本、id、申请的权限（译成「网络（经宿主）」「本地小数据」「读取账号值」，未申请则写「不申请任何权限」）
- 「导入服务包」走系统文件选择器，只接受 zip；摘要由客户端对**实际字节**算 SHA-256 后交给 Core，记录里写的是真正装进来的东西
- 滑动移除，带确认文案，说明删的是代码、不是账号值
- 服务包放在本环境目录下的 `Services/`，换环境时随之切换
- Core 的英文错误保留在内部，界面显示「服务包未被接受：…」「无法解析服务清单」

**验证渠道**：CI run `42018200763`（macos-26 / Xcode 26.6）全绿，Kit **467 tests / 83 suites、0 失败**（463 + 新增 4），日志可见 `✔ Test theDigestIsTheSHA256OfTheArchive` 与 `✔ Test anUnreadableListingIsReportedNotShownAsEmpty`。

**边界**：界面只证明能编译、能解析 Core 的形状；**没有在设备或模拟器上真正装过一个服务包**，也没有跑过服务（需要宿主、传输与账号值）。这一层留给下一轮界面实测与运行宿主。

## ④ 的本地媒体与夹具闭环（Mac，2026-11-05）

提交 `3aec689`、Core `0f1e7b8`，iPhone 17 / iOS 27.2。逐条 `-only-testing` 运行，未改产品代码。

| 项 | 结果 |
| --- | --- |
| `testVideoPlaysTheSourcesClip`（回环 clip，校验 Referer / Range / 已解码时长） | **PASS** 29.1s |
| `testDownloadedChapterReadsWithNoServer`（下载后停服仍能读） | **PASS** 52.0s |
| `testDownloadedChapterBadImageFailsThenRetries` | **PASS** 55.5s |
| `testAFailedDownloadCanBeRetriedFromTheDownloadsScreen` | **PASS** 53.0s |
| 标准 AI 回路（临时 UI 用例 + `UITests/Fixtures/standard-ai`） | **PASS** 32.3s，夹具记录 `GET /events` 一次、`answered 200` |
| Magpie 回路（临时 UI 用例 + 本地插件包 + `http://127.0.0.1:18797`） | **PASS** 68.3s，收到「第一段 第二段🐾」，夹具 9 条事件 |
| PiP | **SKIP**：模拟器上 `AVPictureInPictureController.isPictureInPictureSupported()` 为假，按钮根本不渲染（`App/VideoPlayerView.swift:503`），需真机 |
| 后台 | **部分**：`XCUIDevice.press(.home)` 后 `app_state=4`（进程存活）；后台续播与音频输出无法在此环境判定 |

外加一个**真实缺陷**（已修，见上一条）：标准接口一次提问渲染两条相同回复。夹具只收到 1 次请求，证明是客户端渲染重复。

**边界**：证据全部来自 iOS 27.2 模拟器；PiP、后台播放/音频、真机与真实账号仍未验证。临时用例与工程文件已还原，仓库未因这轮改动提交。

## 标准接口的回复不再画两遍（2026-11-05）

Mac 取证发现一个真实缺陷：标准接口问一次，界面出现**两条相同回复**，第二条带着「整包返回 · 流式尚未接通」；夹具只收到 1 次请求，所以是**客户端渲染重复**——`App/StandardAIView.swift` 同时把回复存进 `reply` 又把同一条追加进 `messages`，两处都渲染。

修法是把会话状态收到一个可测的类型里：`StandardConversation`（Kit）。

- `messages` 只放**已结束**的轮次，`pending` 只放**最新那条**回答；同一时刻回答只在一处
- 下一次提问时把 `pending` 折进 `messages` 再发，历史顺序为「问、答、问」
- 失败时只留问题（错误显示在用户真正问过的东西旁边）；中途停止则保留下半截回答，下次提问时折进记录

回归（`StandardConversationTests`，5 条）：回答只画一次、下一次提问带全双方、失败只留问题、停止的回答仍成轮、多轮不重复不串序。

**边界**：这是 Kit 层单测与视图重构；真机/模拟器上重跑该场景要等下一轮 Mac 取证。夹具只收 1 次请求这一点，是 Worker 在模拟器上实测记录的。

## iOS 接上 Core 服务包的五个入口（2026-11-05）

`Sources/NekularityKit/Core/CoreService.swift` 把 Core `mobile` 包的 `ServiceInstall`/`ServiceList`/`ServiceRemove`/`ServiceManifest`/`ServiceSource` 包成 Swift 可用的 `CoreService`，连同 `ServiceRecord`（含 `sha256`、`permissions` 等可选字段）与 `CoreServiceError`。

- 五个调用都走 gomobile 的 `&err` 形式，错误统一转成 `CoreServiceError.core`；Core 的英文原样保留在错误里，界面文案由客户端决定
- JSON 解析失败报 `unreadable("服务清单"/"安装记录"/"服务记录")`，而不是当成"没有安装任何服务"
- 空数组是正常结果（新装机器），不是错误
- `ServiceRecord.installed` 保持 Core 写出的字符串：日期格式由 Core 拥有，客户端不猜

**验证渠道**：CI run `42009395617`（macos-26 / Xcode 26.6）全绿，Kit 测试 **458 tests / 83 suites、0 失败**（原 453 条加新增 5 条），新增用例打印 `✔ Test aServiceListDecodesWhatCoreWrites` 等三条。第一次提交 `Mobile*` 找不到，原因是没有 `import VeneraCatCore`；补上后通过。

**边界**：这一层只证明编译与 JSON 形状正确，**还没有安装界面**，也没有在设备上真正装过一个服务包；运行服务（需要客户端传输与账号值）仍未接。

## CI 与多列拖拽：两种成因都排除后仍失败（2026-11-05）

`testBoardDragOrderSurvivesRelaunch` 在 CI 上持续失败，先后排除了两种成因：

| run | 改动 | 结果 |
| --- | --- | --- |
| `41996867565` | 拖拽前先等「编辑」变成「完成」，确认已进入编排 | 仍失败：顺序不变 |
| `42000191624` | 拖拽改为 `withVelocity: .slow` 并在目标上停留 0.6 秒再松手 | 仍失败：顺序不变 |

两次的断言原文一致：`dragging template:favorites before template:history produced ["template:history", "template:favorites", …]`。也就是说，编排状态已就绪、拖拽也已放慢并停留，runner 上这条拖拽仍然没有触发重排；而同一用例在 Mac 的 iPhone 17 与 iPad 上通过（`7ab77c3`）。因此这**不是时序或速度问题**，更像 runner 的模拟器不把合成拖拽会话交给 SwiftUI 的 `.draggable`/`dropDestination`。结论按渠道差异记录：桌面/CI 上不做 UI 拖拽结论，以 Mac 渠道为准。

两处改动保留在用例里（先等编排状态、慢速并停留），它们让失败信息更明确，也没有放宽断言。

## 主题 HTTPS 安装、长按编排与窄宽屏取证（Mac，2026-11-05）

提交 `a23a513`、Core `0f1e7b8`，设备 iPhone 17 / iOS 27.2 与 iPad Pro 11-inch (M5) / iOS 27.2。**三项全部通过，无真实失败，本轮未改产品代码。**

| 命令 | 结果 |
| --- | --- |
| `sh scripts/theme-fixture.sh <udid>` | **3/3 PASS**（41.2 / 40.1 / 23.4 秒，`Executed 3 tests, with 0 failures`） |
| `xcodebuild … -only-testing:…/testBoardLongPressAndSizeSurviveRelaunch` | **PASS 1/1**（34.4 秒） |
| 窄/宽屏 × 明暗截图 | **16 张**，无裁切、无重叠、无不可读文字 |

主题三条不是跳过：临时 CA（指纹 `18:D2:66…:8F:10`，30 天，只写进该模拟器的 TrustStore）加 18791/18792 夹具服务。服务端实际收到 `18791 GET /valid.json`（预检）、`/valid.json`、`/invalid.json`、`/valid.json`，而 **18792 一条请求都没有**——说明明文 HTTP 被**客户端**拦下，不是服务端没答。

窄/宽屏覆盖 iPhone 竖/横（1206×2622、2622×1206）与 iPad 竖/横（1668×2420、2420×1668）的发现页与设置页，明暗各一组。亮色背景 `[240,240,240]`/`[248,248,248]`、暗色 `[0,0,0]`/`[24,24,24]`；主文字对比度 16.72–19.77:1，无反色。次级文字亮色 3.34:1，是 0.3.7 已记录的系统 `.secondary` 取舍，达大字号阈值、未达 AA 正文，本轮无变化。横屏与 iPad 上 iOS 26 浮动标签栏压住滚动内容最后一行是该控件的正常行为，可滚到其上方。

**过程中发现并已修的测试卫生问题**：iPad 首次截图是单列，排查是上一轮板卡用例把尺寸持久化成了「大」。`testArrangingTheBoardShowsItsControls` 原来只切到「中」而不还原，现在会记录原尺寸并在结束时还原（`restoreBoardSize`，还原失败只打印不断言）；`testBoardLongPressAndSizeSurviveRelaunch` 也接受「大」为起始值，不再因残留状态误报。

**边界**：全部是 iOS 27.2 证据，本机没有 iOS 26 运行时；横屏截图经 `XCUIScreen.main.screenshot()` 导出时内容侧转 90°，坐标级元素测量只在竖屏可靠，横屏结论为整图统计加目视。真机、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号仍未验证。

## iOS 客户端本来就把源指定的 Host 发出去（2026-11-05）

桌面端的 `Host` 缺口修好后（Nekophage `4ec0a90`），iOS 侧需要一个证据说明它是不是也有同样问题。新增 `TransportHostHeaderTests`：在 `127.0.0.1` 起一个只收一次请求的 `NWListener`，把 `Host: mobileapp.example.com` 交给真实的 `URLSessionTransport.send`，读出服务端收到的请求头。

结果：**通过**——服务端看到的就是源指定的主机名（`✔ Test aHostTheSourceNamesReachesTheServer() passed`）。CI run `41986971865` 的 Kit 单测为 **453 tests / 83 suites、0 失败**（原 452 条加这一条）。因此这个缺口只在桌面 transport 上，iOS 不需要改动。

## 0.3.8 / build 20 正式发布（2026-11-05）

tag `v0.3.8` 指向 `fabe86b9a995b82522accc6eed435a2a66381ab4`（`0.3.8 / build 20`），Core `0f1e7b8856b77059c49fad1b12513adae577ca32`。发布 CI `41981571842`（`macos-26` / Xcode 26.6）全绿：Core 构建、`swift test`、设备 App 构建、UI 测试编译、IPA 打包与 tag 发布。

公开 IPA：下载 **HTTP 200**、**29,563,915 字节**、SHA-256 `55dc841b70b1601ec110a92e49b8f9f02f8cf34c04ebe7ebcd657f05fbf4dc72`（与 GitHub 资产大小一致）。IPA 内容核对 13 项全 PASS：两层 ZIP CRC、单一 `Nekularity.app`、App `0.3.8`/`20`、最低 iOS 26.0、`NekularityWidgets.appex` 同为 `0.3.8`/`20`、二进制含完整 Core 标记 `0f1e7b8…`。

AltStore 刷新 run `41985050590` 成功：`apps.json` 提交 `5f611ad`，三个入口——GitHub Raw、CNB 镜像（`/-/git/raw/`）、固定 Release——均为 **0.3.8 / 20 / 29,563,915 字节 / 最低 26.0**，扁平旧字段（`version`/`downloadURL`/`size`）与 `versions[0]` 一并更新；图标 HTTP 200、443,517 字节、PNG 1024×1024 有效。

Release 说明已改写为中英双语并回读一致。**边界**：这一版仍只在模拟器（iPad Pro 11-inch M5 与 iPhone 17，均 iOS 27.2）与 CI 上验证，真机、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号未验证；本机没有 iOS 26 运行时。

## CI 可以跑模拟器 UI 套件（2026-11-05）

`ios-release.yml` 新增两个 `workflow_dispatch` 输入：`ui_tests`（在构建之后真的跑一遍界面套件）与 `ui_only`（只跑指定用例，`XCUITestClass/testMethod`）。发布 tag 的行为不变，默认不跑。

三次实际结果（`ci/ui-tests`）：

| run | 内容 | 结果 |
| --- | --- | --- |
| `41962032877` | 全量套件（未种子） | 失败 2 条：`testBoardDragOrderSurvivesRelaunch`、`testLibraryHubReachesItsEntries` |
| `41969766670` | 上述两条（保留断言文本） | 拿到断言原文 |
| `41974065557` | 修后的 `testLibraryHubReachesItsEntries` | **成功**，1 条按预期跳过 |

断言原文：

- `testLibraryHubReachesItsEntries`：`全源搜索 opened nothing to type in`。原因是客户端**没有可用的漫画源**时,该页面显示「没有可用的漫画源」而不是搜索框——这是无源的空态,不是入口坏了。用例改为识别这一空态并 `XCTSkip`,其余情况仍然 `XCTFail`。
- `testBoardDragOrderSurvivesRelaunch`：`dragging template:favorites before template:history produced ["template:history", "template:favorites", …], expected ["template:favorites", "template:history", …]`。**这是合并 Mac 回传（`7ab77c3`）之前的旧断言**：那次跑的是「整块顺序完全相等」，而多列看板上的拖拽只保证两张卡相对顺序与卡片集合不变。用例已在 `7ab77c3` 改写为 `waitForRelative`；合并后在 main 上重跑（run `41977525948`）**仍然失败**：`dragging template:favorites before template:history produced ["template:history", "template:favorites", …], expected it before template:history`——拖拽在 CI runner 上完全没有改变顺序，而同一用例在 Mac 的 iPad/iPhone 模拟器上通过（`7ab77c3`）。因此不是断言写法问题，而是 CI 侧手势未生效，Mac 与 CI 的差异尚未定位；这条属于长按编排/拖放（③），以 Mac 渠道的结论为准并保持未决。

**边界**：CI 上的 App 没有种子源，需要种子的用例会自行跳过；因此 CI 的「绿」只覆盖不依赖源的部分。真机、真实账号与长按拖拽的真实手势仍未验证。

## 挑战完成规则与查询参数：CI 编译与 Kit 测试（2026-11-05）

`feat/challenge-query`（rebase 后 `6b8eb2a`）合入 main。内容：`Challenge` 解码 `sameHost`；`ChallengeRule` 支持主机条件（空窗口没有 host，未导航就判未通过）；`VerificationSession` 用 `Challenge.url` 的主机作被保护主机，并把 `requiredQueryParams` 的实际值带回；`SourceUI.verify`/`CoreHost.verify` 返回 `VerificationOutcome`（User-Agent + query），过桥字段与 Core `hostBridge.Verify` 的 `sameHost`/`query` 对齐。新增 `ChallengeRuleTests.sameHostRule`。

**验证渠道**：本机没有 Swift 工具链。这一轮由 CI 跑 `ios-release.yml`（run `41958530139`，`macos-26`、Xcode 26.6）：

| 步骤 | 结果 |
| --- | --- |
| `swift test --no-parallel` | 全绿；`ChallengeRule` 套件（含 `sameHostRule`）通过 |
| 生成工程 + 未签名 device 构建 | 通过 |
| 编译 UI 测试目标 | 通过（只编译，不执行） |
| 打包 IPA | 通过 |

**边界**：CI 只证明编译、Kit 单测与构建；模拟器 UI 套件、真机与人机验证站点的真实流程仍未验证。

# Nekularity 状态

[English](STATUS.en.md) | 简体中文

## 模拟器上的 iPad、辅助字号与外观三态（2026-11-05）

主线 `9c73909`（Core pin `0f1e7b8`）在 `scripts/verify-ios.sh` 上 **15 步 PASS / 1 SKIP / 0 FAIL**，SKIP 项是脚本默认不驱动界面（`NK_UI_TESTS=1` 才跑）。界面证据来自三台本机新建的专用模拟器：

- **iPad Pro 11-inch (M5) / iOS 27.2**：完整 UI 套件 **29 例、23 通过、6 跳过、0 失败**（773 秒）。截图覆盖发现、搜索、详情、阅读、设置。跳过项为：需要真实站源 `nhentai`/`Komiic` 的两条、需要本地主题夹具的三条，以及一条三列宽度断言（iPad 上按设计是四列）。
- **iPhone 17 / iOS 27.2，动态字体调到最大（AX5，`accessibility-extra-extra-extra-large`）**：**29 例、20 通过、9 跳过、0 失败**（969 秒）。发现、详情、设置与阅读页均可达，长按章节行弹出的下载动作、资源库两个模块入口、分类页、评论线程都实际操作成功。
- **设置页滚动到「外观」并切换 跟随系统 / 亮 / 暗**：真实滚动到该分区，三态各自立即生效（亮/暗截图背景分别为浅色与黑色，非仅状态栏），选「暗」后重开仍是暗色，最后恢复跟随系统。新增用例 `ZZAppearanceSettingsTests`。

本轮修复的**测试假设缺陷**（不改布局、不改文案）：iPad 的标签栏是顶部普通按钮、不在 `TabBar` 元素内，四处查询只认 `app.tabBars` 导致 iPad 上 26 条用例误报；辅助字号下章节行与资源库行需要先滚动才可点；断言失败时测试服务器端口不释放，导致后续用例级联 `Address already in use`（`defer` 改为 `addTeardownBlock`）；多列看板的拖拽断言改为「两张卡的相对顺序 + 卡片集合不变」；三列宽度断言在四列宽度（iPad）上按设计跳过。

**产品代码一处必要补充**：设置页「外观」原先只有主题列表、没有系统/亮/暗三态控件，`ThemeAppearance` 与渲染映射已在但无入口。本轮在既有 `Section("外观")` 内加了分段控件与 `ThemeStore` 的覆盖值（持久化到 `UserDefaults` 的 `appearance` 键），并加 7 条 Kit 单测：`swift test` 为 **452 tests / 83 suites、0 失败**（新 pin 合并后基线为 445 tests，本条加 7 条）。

范围仅限模拟器。真机安装、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号仍未验证；截图与机器可读汇总在 Mac `/tmp/nk-ios-ipad-type/`。

## 0.3.6 完整 UI 套件（Mac 回传，2026-11-04）

tag `v0.3.6` 的 `9684c108f0ade6490b4209827f0525aed54e0853`（tree `fbcb0a7a…`）在专用 iPhone 17 模拟器上跑完整套件：`xcodebuild test-without-building` 执行 **28 个用例、5 跳过、0 失败**（752 秒）。其中 ZZThemeLinkTests 的 3 条因缺本地主题夹具而跳过，用仓库自带 `scripts/theme-fixture.sh` 起夹具后复跑 **3/3 通过**，合并为 **26 通过 / 2 跳过 / 0 失败**。

剩余 2 条跳过是 `testSeededSourcesAppear` 与 `testSourceOffersInPageLogin`：它们要求真实站源 `nhentai` 与 `Komiic` 的种子，仓库内没有这两个脚本，本机种子只含 `callback_probe`，因此按设计 `XCTSkip`，不是缺陷。

同一组合的 Kit 测试为 Swift Testing **444 tests / 82 suites**、XCTest 段 **31/0**，`scripts/verify-ios.sh` 20 个步骤全部 PASS。

范围：结果属于 Mac 隔离副本与专用模拟器，没有覆盖真机、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号；仓库内没有真实 `nhentai`/`Komiic` 种子。日志在 Mac `/tmp/nk-ios-v036-ui/`（`ui-summary.json`、`verify-ios-ui.log`、`theme-fixture.log`）。

## 失效登录句柄在 iOS 上结束等待（2026-11-04，候选）

Core `b882bf9` 让源在登录期间被更新或删除后的旧句柄返回结构化错误。iOS 的网页登录原先用 `try?` 吞掉 `webviewStatus` 的错误，只会一直轮询；现在仅当错误确认为失效句柄时结束并报错，其他源错误仍然继续等待，避免把“这页不是登录页”当成失败。

新增 Kit 单测覆盖识别、普通错误不误判，以及界面文案不泄漏 Core 英文。pin 已更新到 `b882bf9`。macOS CI 已在提交 `d593b45` 上实际执行这三条用例：Swift Testing 444 tests / 82 suites、XCTest 段 34 tests / 0 failures（原 31 条加新增 3 条）。该改动尚未在模拟器上手动复现，也未涵盖真机。

## 明暗外观实证（0.3.7，Mac 回传，2026-11-04）

在专用模拟器上对 `v0.3.7` 的 App 分别以 `appearance light` 与 `appearance dark` 截取发现页、设置页、阅读页，全部 1206×2622。图像差异是整体换肤而非仅状态栏：发现页 99.89%、设置页 99.65%、阅读页 99.90% 的采样点 RGB 变化超过 0.08；另用 `simctl` 直连路径独立复现发现页，背景色亮 `[248,248,248]` / 暗 `[24,24,24]` 与测试路径一致。

可读性按 AX 树中每个 `StaticText` 的实际 frame 取像素测量（共 58 个元素，剔除 10 个被标签栏遮挡的），用 WCAG 相对亮度计算：**没有任何“深字配深底 / 浅字配浅底”的不可读组合，全部 ≥3.0**。暗色最差 4.61（设置页）、发现 6.16、阅读 5.97。

亮色有系统性偏淡但未到不可读：系统 `.secondary` 灰 `(136,136,136)` 配 `(248,248,248)` 为 **3.34**，分组标题 `(128,128,136)` 配 `(240,240,240)` 为 **3.44**，`#0A84FF` 强调色配白为 **3.63**。这三者都是 Apple 的语义色/系统蓝，不是本项目自定义值；低于 AA 正文 4.5，但高于大字号阈值 3.0，与 iOS 平台本身一致，因此不改色而记录为已知边界。

未取得：设置页滚动到「外观」分组后的截图（临时测试改动未参与重建，产出仍只有三张，属流程遗漏而非报错）、辅助功能大字号、iPad、真机。两次运行之间读过一次章节，导致亮色发现页是空状态而暗色有卡片 —— 那是内容差异，不是外观差异。页面图片本身不随外观重着色（预期行为）。

日志与逐元素测量在 Mac `/tmp/nk-ios-037-visual/`（`visual-summary.json`、`element-contrast.json`）。

## 跟随 Core 0f1e7b8：Cloudflare 完成规则修正（2026-11-04）

Core 主线升到 `0f1e7b8`（tree `80b14e97`）：Cloudflare 完成规则改为「插页标记消失且回到被保护主机」，不等 `/cdn-cgi/challenge-platform/`、也不强制 `cf_clearance`。iOS 只跟随 pin；`feat/challenge-query` 的 Swift 改动已由 CI `41958530139`（macos-26）编译并跑通 Kit 测试后合入 main。

## 跟随 Core 518f446：忙碌的服务不被清扫（2026-11-04）

Core 主线升到 `518f446`（tree `a7f402cb`）：常驻服务记录进行中的调用数，`Sweep` 与 LRU 淘汰跳过忙碌实例。iOS 只跟随 pin；`feat/challenge-query` 的 Swift 改动已由 CI `41958530139`（macos-26）编译并跑通 Kit 测试后合入 main。

## 跟随 Core 971146f：挑战规则整体过桥（2026-11-04）

Core 主线升到 `971146f`（tree `ba7d3620`）：`hostBridge.Verify` 补上 `sameHost`，返回的 clearance 接受 `query`。iOS 的 `Challenge` 因此能真正拿到主机条件；`ChallengeRule`、`VerificationSession`、`VerificationOutcome` 的改动已合入 main（`6b8eb2a`）。

**验证渠道**：本机无 Swift 工具链；编译与 Kit 测试由 CI `41958530139`（`macos-26`，Xcode 26.6）完成——`swift test --no-parallel` 全绿，`ChallengeRule` 套件（含 `sameHostRule`）通过，UI 测试目标只编译未执行。模拟器 UI 套件仍在 Mac Worker 上跑。

## 跟随 Core 7ade130a：验证页不再把 HTML 交给源（2026-11-04）

Core 主线升到 `7ade130a`（tree `790ad465`）：边缘验证页（MangaDex 形态）此前未被识别，HTML 直接交给源导致 `JSON.parse` 失败；现在两种挑战走同一通道，`host.Clearance.Query` 把验证带回的参数交给重试，完成规则支持 `SameHost`。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 的验证流程后续接入该字段。

## 跟随 Core 78826c8：取消会中断脚本（2026-11-04）

Core 主线升到 `78826c8`（tree `1161a5e3`）：`Supervisor` 在调用方取消时也中断运行时，并按原因区分超时与取消；新增按服务的宿主与 `Supervisor.Describe`。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 仍未调用 `service` 入口。

## 跟随 Core 8b82378：服务可说明自己的方法（2026-11-04）

Core 主线升到 `8b82378`（tree `06ac2e3a`）：服务可导出 `describe()` 说明自己能做什么，宿主据此画按钮；桌面面板已用它列出并运行方法。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 仍未调用 `service` 相关入口。

## 跟随 Core d6b9f67：服务包的 iOS 入口已就位（2026-11-04）

Core 主线升到 `d6b9f67`（tree `c1495fdb`）：服务包安装/列表/读取/删除进入 Core，并新增 `mobile` 入口 `ServiceInstall`、`ServiceList`、`ServiceRemove`、`ServiceManifest`、`ServiceSource`（二进制 base64、其余 JSON）。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过。

**iOS 侧尚未调用这些入口**：Swift 包装、安装界面与账号流程都还没写，因此这只是"底层入口就位"，不是 iOS 已支持服务插件。

## 跟随 Core e94b68c：权限拒绝文案（2026-11-04）

Core 主线升到 `e94b68c`（tree `308a3f68`）：权限拒绝区分"服务没申请"与"宿主没授出"，前者指向清单，后者指向宿主的授权决定。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 仍未消费 `service` 包。

## 跟随 Core f349e3d：受控传输桥（2026-11-04）

Core 主线升到 `f349e3d`（tree `1a84c653`）：新增 `service.Bridge`，服务里的 `fetch` 只能走它——只允许 `http`/`https`、每一跳重定向重新校验、单次响应默认 4 MiB、默认不带 Cookie。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 仍未消费 `service` 包。

## 跟随 Core fbbda3f：服务生命周期（2026-11-04）

Core 主线升到 `fbbda3f`（tree `4cd4c8c5`）：`service.Supervisor` 负责按需加载、常驻上限、空闲卸载与单次调用超时（靠中断运行时实现），异步 handler 按 Promise 状态读取或明确拒绝。iOS pin 已跟随，Swift 语法、文档与 pin 检查通过；iOS 仍未消费 `service` 包。

## 跟随 Core d62fbc7：服务包 zip 读取（2026-11-04）

Core 主线升到 `d62fbc7`（tree `84240f87`）：`service` 包新增 `ReadPackageZip`，从 zip 读清单与入口，按实际解压字节兜上限，拒绝 `../`、绝对路径与反斜杠文件名；桌面端已据此实现服务包安装。iOS 端 pin 已跟随，Swift 语法、文档与 pin 检查通过，但尚未消费该能力：iOS 侧的安装、界面与账号流程都还没做。

## 跟随 Core ec57f45：服务运行时与包加载（2026-11-04）

Core 主线升到 `ec57f45`（tree `f382a2d3`）：`service` 包现在能真正运行一个服务——模块导出 `handle(method, payload)`，宿主按方法调用并按权限把住 `fetch`、`storageGet`、`storageSet`、`secret`、`log`；同时新增从磁盘目录读取服务包（清单 + 入口）的加载器。Core CI 41906638143 四作业全部通过。

iOS 端 pin 已更新到 `ec57f45`，Swift 语法、文档与 pin 检查通过。iOS 侧尚未消费 `service` 包，因此这只是 pin 跟随：服务插件在 iOS 的安装、界面与账号流程都还没做。

## 跟随 Core 2380abd：服务清单与权限（2026-11-04）

Core 主线升到 `2380abd`（tree `6be6739f`），新增 `service` 包：校验服务清单并把“服务请求的权限”与“宿主允许的权限”取交集，未知字段与未知权限都拒绝，`entry` 必须是包内相对路径。本轮只做清单与权限，不加载 JavaScript。Core CI 41900200233 四作业全部通过。

两端 pin 均已更新到 `2380abd`：桌面端 `go build` 与七项工程检查通过；iOS 端 Swift 语法、文档与 pin 检查通过。两端都还没有消费 `service` 包，因此这只是 pin 跟随，不代表服务宿主已可用。

## 主题到外观的规则可测（2026-11-04，候选）

之前“主题是否强制明暗”只在 `RootView` 里用一行三元表达式决定，`dark` 为 nil 时跟随系统的含义无法被单测覆盖。现在模型给出三态 `ThemeAppearance`（system/light/dark），视图只负责把它映射成 SwiftUI 的 `ColorScheme`，规则本身由 Kit 单测覆盖：缺省跟随系统、显式 true/false 分别对应暗/亮、内置主题不强制。

这是重构，行为不变。macOS CI 41894996744 已在 `d8471fb` 上实际执行：Swift Testing **447 tests / 83 suites** 通过（原 444/82 加新增 3 条），设备 App 构建、UI 测试编译与 IPA 打包随后全部成功。

## 0.3.7 / build 19 正式发布（2026-11-04）

tag `v0.3.7` 指向 `bf14135384677fb7955d543e3e11cd4e2a5a2376`（tree `b8c2eec0`），Core `b882bf9ebeb339eb596b3ddc59166bb3adfa7ef7`。GitHub Actions 当时官方状态为 degraded，`macos-26` 运行器四次未能分配（三次 ``runner_name`` 为空被取消，最后一次排队逾一小时），因此按发布工作流的同样步骤在 Mac 验证机上构建：8 项仓库检查通过，`swift test` 为 444 tests / 82 suites、XCTest 34/0，设备 App 未签名编译通过后打包。

公开 IPA HTTP200、29,483,547字节，SHA-256 `5ab46820836e5945b9bfbf0e1c0512dda12bac1e3cf4b9834cd5a41450f8a98a` 与 Mac 构建报告及 GitHub 资产摘要三者一致；ZIP CRC、App/Widget0.3.7/19、最低iOS26.0、完整 Core 标记与 23 个 InstallComicEntry 符号通过。

AltStore 刷新41870386695成功，三个入口均 HTTP200 且为0.3.7/19、29,483,547字节、最低26.0；图标 HTTP200 且 PNG 有效。

交付：[0.3.7 IPA 与回执](../../deliveries/2026-11-04-nekularity-037/README.md)。该 IPA 由 Mac 本机构建、没有 CI 证明，与 CI 产物字节不会完全一致。UI 未执行，真机、后台/PiP、实际扬声器与真实账号仍单列。

## 0.3.6 / build 18 正式发布（2026-11-04）

公开tag `v0.3.6` 指向 `9684c108f0ade6490b4209827f0525aed54e0853`，Core `25e5ca35bc18f231c5628ffca7054e6a8b64b5d1`。发布CI41839540774成功，含Core构建、Kit单测、设备App构建、UI测试编译、IPA打包与发布；未执行UI。

公开IPA下载HTTP200、29,485,726字节，SHA-256 `9dfa95840c1b105a7f8ecf0a0aaf4abfaaf363614fbff8509d2c8c61622a0ff0` 与GitHub资产摘要一致；两层ZIP CRC、App/Widget0.3.6/18、最低iOS26.0与完整Core25e5ca3标记通过。双语Release说明已写入并回读一致。

AltStore刷新41843074599成功，GitHub Raw、CNB镜像与固定Release三个入口均HTTP200，旧式字段、扁平列表与stable轨道均为0.3.6/18、29,485,726字节、最低26.0并指向v0.3.6；图标HTTP200且PNG签名有效。

交付：[0.3.6未签名IPA及回执](../../deliveries/2026-11-04-nekularity-036/README.md)。Mac隔离副本的官方组合（客户端107286d，与主线产品代码逐文件一致）为13 tests/4 suites、0失败，索引身份用例实际执行并通过；设备App与UI测试编译通过。UI未执行，真机、后台/PiP、实际扬声器与真实账号仍单列。

## 索引入口进入正式主线与0.3.6候选（2026-11-04）

Core `25e5ca35bc18f231c5628ffca7054e6a8b64b5d1` 已按单提交保树发布main（tree `db28866dfed0d3742e031787f37c26c6226252ed`，父提交 `313951e`，相对上一版只改4个文件：两份STATUS、`mobile/mobile.go`、`mobile/mobile_test.go`）。CI41835537014四作业全部通过：Linux、Windows、macOS Go，以及Apple xcframework加Swift smoke。

iOS主线 `e64847e` 合入索引身份客户端改动，两个权威pin均为 `25e5ca3`。主线产品代码与Mac受测提交 `107286d` 逐文件一致（`Sources`、`App`、`Tests`、`Package.swift`、`project.yml`、`scripts` 差异为空），因此Mac结果按该范围继承。

Mac隔离副本（`/tmp/nk-ios-index-identity/repo`，跟踪文件干净）：`fetch-core.sh` 检出同一提交且Core自身gofmt/vet/race与bind通过；`check-core-pin` 通过；清空`.build`后 `swift test --filter SourceLibrary --no-parallel` 为13个测试/4个套件、0失败，`anIndexEntryCannotRedirectIntoAnotherInstalledSource` 实际执行并通过；`xcodegen generate` 通过；设备App的Release编译exit0；UI测试`build-for-testing` exit0。构建出的`VeneraCatCore.xcframework`在ios-arm64切片头文件中`installComicEntry`出现1次。UI测试只编译未执行。

本轮发布`0.3.6`/build 18，产品代码相对`0.3.5`只有索引入口与pin变化，其余非Markdown差异为`project.yml`的App/Widget版本元数据。

## 索引身份安装候选（2026-11-04，尚未编译）

隔离分支将新索引条目改为调用Core候选 `c5ae195bb525d8e20a1519aa742e4e05f7cf4cd8` 的 `InstallComicEntry`。索引声明key与脚本执行身份不一致时，在发布前拒绝；已存在源保持不变。通用URL安装仍保留重复键更新回退。Windows已通过Core定向和mobile race，但本分支尚未经Mac编译或执行Swift测试，不宣称iOS行为通过。

## Core313951e主线整合与候选IPA验收（2026-11-04）

Core `313951e157a18e524f4c0c80c46d78abee662f2b` 已保留单提交及受测文件树发布main，两端源码主线pin一致；Core CI41814080991的Linux、Windows、macOS Go及Apple SDK/Swift smoke四作业通过。iOS受测提交c751085的CI41815696096成功，实际原始日志为443 tests/82 suites及XCTest31/0，设备App和UI测试编译通过。未签名候选IPA为29,478,302字节，SHA256 `9cebc4f5c07ab2f5de252d70ac446fd52e9e46dbe24880b1541980385e4742bd`；GitHub制品摘要、两层ZIP CRC、App/Widget0.3.5/17、最低26.0及包内完整Core313标记均通过。

主线产品源码与受测c751085一致，仅补充本次文档。Swift业务逻辑未改，仍使用既有重复键文字兼容器，不宣称已消费Go结构化错误对象。UI只编译，没有新增UI/真机结果。公开0.3.5及AltStore仍为此前Coreccb包，候选IPA不替换正式版。回执及原日志：`E:/Temp/nk-313-consumer/ios-accepted.json`、`ios-ci-logs.zip`；交付目录 `E:/Code/deliveries/2026-11-04-core-313951e/`。

## 0.3.5 / build 17 正式发布与订阅验收（2026-11-04）

公开tag `v0.3.5` 指向 `7c0d61bf03b774e804abfd4297e065bcb87a3e65`，Core 为 `ccb626825bc116dad3b3e9a082867fd22c09caf4`。精确发布提交的 CI41791891766 已通过 Core/Kit、设备App构建、UI测试编译、IPA打包和发布；没有执行UI。相对已验收组合bac68cda，非Markdown差异只有project.yml中的App/Widget版本元数据，原443 tests/82 suites及31项XCTest计数仍归该组合原日志。

公开IPA下载HTTP200、29,478,760字节，SHA-256 `34091cbbaa23db16b95f34d1ee86a4909c3b0e99a649216274f6760efcc801bd` 与GitHub资产一致；ZIP CRC、App/Widget0.3.5/17、最低iOS26.0和完整Core标记通过。双语Release说明已写入并认证重读一致。AltStore刷新41797483555成功，GitHub Raw、CNB和固定Release三个入口均HTTP200，旧式字段、扁平列表及stable轨道与新包版本/build/大小/最低系统/地址一致；图标HTTP200并实际解码通过。

交付[0.3.5未签名IPA及回执](../../deliveries/2026-11-04-nekularity-035/README.md)，原始验收记录位于 `E:/Temp/nk-ios-035-evidence/`。本次不增加历史完整UI计数；签名真机、后台/锁屏、Live Activity、PiP、实际扬声器及真实账号仍单列。以下较早条目保留各自执行时的状态与证据范围。

## Core ccb6268 已整合，CI 与候选 IPA 已核验（2026-11-04）

当前iOS主线pin更新为 `ccb626825bc116dad3b3e9a082867fd22c09caf4`。受测组合 `bac68cdad3920ef76b299f59a2a8196e9b518add` 的CI41780802099通过Core构建、Kit单测、设备App构建、UITests编译和IPA打包。下载的原始日志确认Swift Testing为443 tests / 82 suites通过，另有XCTest31项、0失败；UI只编译，没有执行。

候选未签名IPA为29478759字节，SHA-256 `27b901290665bda5731c04ddeb28270a086318f47d6375c0b061762ab1e33d2c`；GitHub artifact摘要、两层ZIP CRC、App/Widget0.3.4/16、最低iOS26.0及Core标识均核验通过。插件下载超时/地址校验失败后，使用同一laincat账号的GitHub CLI取回原日志并续传产物，HTTP206范围及最终artifact摘要一致。回执 `E:/Temp/nk-core-source-release/ios-accepted.json`。

本次整合不修改受测产品/测试源码，后续只有证据文档差异。未创建新发布标签，公开0.3.4/AltStore仍是Core3be57b5版本；不提升历史UI、真机、后台、PiP或真实账号范围。桌面主线仍为3be57b5，ccb候选的Windows消费已过，Mac由既有Orca Worker验证。

## URLSession传输生命周期修复（2026-11-04）

请求失败、超限和取消后统一释放delegate状态；完成后不再派发chunk，预先取消时恢复continuation，并按task身份清理复用ID的映射。Mac Orca Worker在 `66454e86` / Core `3be57b5` 的独立worktree报告：旧实现复现失败、超限泄漏、完成后chunk、取消先于attach挂起及ID复用清理问题；修复后7项生命周期测试、18项transport/streaming测试、完整443 tests / 82 suites和iOS模拟器构建通过，未运行UI。原日志仅存Mac `/tmp/nk-transport-lifecycle/`，不标为本机日志。

Windows已验证传回补丁SHA-256 `7a0ef66d647d01e8161bfd315afc62749aa65808891ca24b462c5271e5603ba6`，整合后的生产文件和测试文件与Mac受测文件逐字节一致；本机Swift语法、文档与Core pin检查通过。现有Core pin未变，未发布新包。日志 `E:/Temp/nk-transport-lifecycle-integration/`。

## 模拟器跨进程进度恢复(Orca Worker回传,2026-11-04)

0.3.4/16、Core 3be57b5的专用模拟器定向测试中,第一App进程2020播放30秒HLS至7.211756秒,暂停并正常关闭播放器页,随后终止App。第二进程2099通过同一视频源的搜索和分集页重新进入,诊断起点7.000000秒,约2.08秒后自动播放至8.342057秒。修正测试PID千位逗号解析后,定向XCTest为1 test/0 failures。测试结束后磁盘历史为7秒/30秒/23%;这不是两次进程之间单独抓取的磁盘快照。

该结果证明上述搜索/分集路径的模拟器跨进程位置恢复,不证明“继续观看/本地条目”直接入口,也不证明真机、后台或PiP。诊断构建临时读取PID、起始位置和时钟;产品源码已还原并重建安装,受测VideoPlayerView.swift还原SHA为0daef0ed11c4cd12e4918ed0f89d30e8066a37c75011974a94f1d76c1fdbff37。原始日志在Mac `/tmp/nk-ios-cross-process-resume-evidence/`,本地 `E:/Temp/nk-ios-034-evidence/cross-process-worker-report.json` 仅是Worker回传记录,不是原日志副本。旧界面直接入口的UI验收按整体UI/UX重写计划后置。

## 0.3.4发布与下载图片完整性修复已验(2026-11-04)

Orca Worker已在ac8e2b6基线/Core3be57b5修复两项实际缺陷:离线字节不再二次执行源的onResponse,解码后的modifyImage仍保留;raw在onResponse后以64像素缩略图验证可解码性,坏字节走既有镜像回退或DownloadStore失败/重试,不形成完成章节。有效PNG/JPEG原字节保持不变。此前已保存的坏章节不自动删除,仍需用户删除后重新下载。

真实Core配合独立URLProtocol的旧实现负向用例为4 tests/7 issues,包含二次转换not an image、200坏字节被接受及镜像未请求。最终新增6条回归通过;Xcode27.2(27B52)/Swift6.4.2完整 `swift test --no-parallel` 为436 tests/81 suites/0 failures。模拟器最终build-for-testing通过,同次串行BadImage→Reads两例均通过(58.922/52.680秒):真实本地HTTP坏图产生重试项,恢复PNG后重试成功,停服再进入下载章节看到实际“第 1 页”Image。初次fixture actor编译错误、“1 页”与实际“1/1”等待错误及端口释放失败均保留,不记为最终产品失败。

原日志仍在Mac `/tmp/nk-ac8-image-integrity/`,最终单测 `swift-test-final.log`、构建 `ui-build-final.log`、UI `ui-targeted2.log`。Windows的 `E:/Temp/nk-ios-034-evidence/mac-image-integrity-report.json` 是Worker回传回执,不冒充已复制原日志。Mac缺tree-sitter只跑173文件规则检查,不算语法解析通过。

Lead已恢复25575字节补丁,SHA256为691086b271d0a46cfc1cc9f11db1ffe8fe5bb961712240fd968f912cec7dee75;四个整合Git文件逐字节SHA均与Mac受测文件一致,回执 `E:/Temp/nk-ios-034-evidence/patch-integrated.json`。App/Widget的0.3.4/16已正式发布,tag指向66454e86f4aa3e1bbba94f64cb29b56783513a82。CI41749091496首次运行成功,公开IPA HTTP200/29,459,904字节、SHA256 c31d240513f2f82d97a507d8255bf586a28a8e518eff03d3a027c16f6571454c,ZIP CRC、两端版本/最低26.0和Core3be标识均通过。AltStore刷新41752744406成功,仓库main e81249d及GitHub Raw/CNB/固定Release三个公开入口都核到0.3.4/16,版本、大小、最低系统和下载地址一致,图标HTTP200且实际解码。交付 `E:/Code/deliveries/2026-11-04-nekularity-034/README.md`,完整回执 `E:/Temp/nk-ios-034-evidence/release-accepted.json` 与 `altstore-accepted.json`。Core pin仍3be57b5。以上不增加历史完整UI27/0/0计数,不包含真机/后台/真实账号。

## Mac包装窗口正常关闭与Core主线复验(2026-11-04)

用户确认Laincat-Mini已解锁后,Orca Worker对已核验c545212/Core3be的0.2.7 arm64包做隔离验收:包SHA bb39921a…、二进制SHA d955c9ab…及ad-hoc严格签名复核通过,以独立 `-data-dir /tmp/nk-c545-close-only/data` 启动PID78539/窗口11481;原生关闭按钮一次AX点击后窗口消失、原进程退出码0,未发终止信号。独立资料目录前后无文件。原始日志 `/tmp/nk-c545-close-only/`,Lead回执 `E:/Temp/nk-c545-mac-transfer/normal-close-accepted.json`。这不代替Gatekeeper/公证、其他机器运行或完整包装媒体流程。

Core单提交主线c0f0dfa的[CI41734985028](https://github.com/laincat/VeneraCat-Core/actions/runs/41734985028)也在该精确SHA完成三平台Go、Apple xcframework及macOS/iOS模拟器Swift冒烟四作业通过,回执 `E:/Temp/core-gbk-differential/main-ci-accepted.json`。本轮Core变动仅测试/文档,两端功能pin仍为3be57b5;不将不同提交的CI执行记录混同。

## Core测试与兼容说明已整合(2026-11-04)

经用户确认,Core main按单初始提交约定更新为c0f0dfa00c8a4daf7ce58fea5b615bc24eab88b7,文件树与通过完整CI41722875239的8922993完全一致,PR #3已关闭。只有测试与文档差异,生产转换实现未变;Nekularity/Nekophage仍使用功能pin3be57b5。保树/远端/两端pin回执 `E:/Temp/core-gbk-differential/main-published.json`。新主线SHA与已有CI受测SHA分别记录,不把旧CI改记为新SHA执行。

## Mac补验终态已收齐(2026-11-04)

Orca Worker用12张本地封面完成浅/深色×竖/横屏四组合:截图实际可见解码封面,长标题省略而不溢出,末项可滚到并进入详情。详情提示“漫画源还未安装”,不宣称完整内容加载。深色设置页“当前环境”和“AI供应商与标准接口”两处字形内部RGB为10/132/255,背景28/28/30,对比度4.6648016304:1;Lead按sRGB公式独立复算一致,仅代表这两处。没有产品修改,证据 `/tmp/nk-cover-visual-evidence/`,回执 `E:/Temp/nk-theme-matrix-review/populated-receipt.json`。初次驱动folder missing失败与后续通过日志均保留。

同一Orca Worker在干净736e364/Core3be的独立检出上完成本机Release App与UITests编译,`swift test --no-parallel`为430 tests/80 suites/0 failures。工具链为Xcode27.2(27B52)、iPhoneOS SDK27.2;tree-sitter因Language15与支持13–14不兼容而跳过,不算解析通过。本机IPA29,457,750字节,SHA a1210ec1db47a6c0c7b33888b27cbe8ada81e894195e71def9ef7ba91182ddeb,与正式CI发布IPA的29,457,850字节/cb1ab0ca…分开。两者均0.3.3/15、最低26.0;本机结果不改写CI或新增UI/真机结论。回执 `E:/Temp/nk-ios-033-evidence/local-mac-build-receipt.json`。

离线页图正常/坏字节/恢复三项也已通过:坏字节负例是XCTAssertFalse通过,不是XCTest红灯。它证明旧工具栏断言仍成立而实际图片谓词不成立。完整patch经压缩传输与SHA核对收回,串行隔离修复后以a7b5fbd整合主线。原完整UI27/0/0不变;各项自有服务/测试资料已清理,不宣称先前fixture CA全被移除。

## 0.3.3/build15 发布与订阅已核验(2026-11-04)

正式tag `v0.3.3` 指向736e3645b8786f75c23845ca928cfde7dbc5072c。CI41720810029第二次尝试成功,实际执行Kit单测、构建设备App、编译UITests并发布IPA;第一次未取得托管macOS runner,零构建步骤,没有伪报为源码失败。公开IPA返回HTTP200、29,457,850字节,SHA-256 cb1ab0ca717b7e0a7181bda12e02f7b09a970974f818d16c84edbf2fe51b3a0d;ZIP CRC通过,App/Widget均0.3.3/15、最低iOS26.0,App含Core3be57b5ceb848bb9623c090abc463764add14de4标识。回执 `E:/Temp/nk-ios-033-evidence/release-accepted.json`,本地副本 `E:/Code/deliveries/2026-11-04-nekularity-033/`。

AltStore首次刷新虽为绿色却仍保留0.3.2。确认生成步骤遗漏GH_TOKEN后,以a516cd2补齐,既有测试/结构检查通过;刷新41731222405成功,产出main6ce4eb68699b15bb218f4e3f699c6c32fc8e5a32。仓库条目、GitHub Raw、CNB镜像、固定Release三个公开入口均实际为0.3.3/15,稳定轨道/扁平版本/旧式version一致,大小29,457,850、最低26.0和IPA地址匹配。公开入口均HTTP200,回执 `E:/Temp/nk-ios-033-evidence/altstore-accepted.json`。刷新日志下载被插件地址校验拦截,根因表述限于已确认配置缺口及修复后实际结果,不补造限流错误。

CI只编译UI;界面验收归属于原Orca Worker的独立结果。断网页图随后已完成正常图片/HTTP200坏图片/恢复图片的定向对照,真实青色图片与AX Image证据通过,产品源码无改动,受测文件已按SHA核对并随a7b5fbd整合。完整UI历史计数不改。真机签名、后台/锁屏、Live Activity、PiP、扬声器及真实账号仍单列外部条件;一次发版不代表全路线图完成。

## 离线页图断言与串行隔离已验证(2026-11-04)

复核发现既有 `testDownloadedChapterReadsWithNoServer` 在停止loopback服务后只等待“收藏本页”按钮存在。ReaderView工具栏在图片尚未解码时也存在,其enabled状态也只反映图片URL列表。因此旧用例通过不能独立证明下载页图已经解码;历史27/0/0计数保留,同名下载条目可进入的结果也不扩称图片呈现通过。

受测修改已整合主线:停服后等待ReaderPage成功CGImage分支暴露的页图元素并附图,坏字节用HTTP200不可解码响应做负例。Orca Worker在专用模拟器实测正例39.920秒通过、负例61.470秒(旧工具栏断言成立而页图谓词8秒内不成立)、恢复图片后40.572秒通过。

随后发现负例留下的坏章节会让紧随其后的正例跳过重新下载:同一次调用串行运行复现FAIL(NekularityUITests.swift:1204,2 tests/1 failure)。正例开始调用既有removeDownloadedProbeChapter清理后再连续运行,两例0失败(63.733秒、53.172秒)。最终两个测试文件与Mac受测SHA逐字节一致,LF换行;产品源码未改,历史完整UI27/0/0计数不变。日志 `/tmp/nk-offline-image-evidence/`,Lead回执 `E:/Temp/nk-offline-image-evidence/mac-receipt.json`。范围仅限模拟器该定向用例,不含真机或完整套件重跑。

## 30秒 HLS 续播定向通过(2026-11-04)

Orca Worker 在专用签名模拟器上用30秒本地素材,真实播放后分别下滑和点关闭按钮。关闭前位置7.24/7.30秒,均落盘7秒/30秒、23%;自动重开时未点暂停、播放或字幕,起点均为7.00秒,早期App/engine/source时钟分别为9.60/9.50秒。两次CoreMedia均记录postSeekPosition 7.000000,经过的约2.5秒包括自动播放和UI采样。临时只读诊断移除后App重新编译安装,最终VideoPlayerView SHA为0daef0ed11c4cd12e4918ed0f89d30e8066a37c75011974a94f1d76c1fdbff37,与先前受测源码一致。素材Git原始主清单为LF/110字节,Windows CRLF副本114字节,其余素材按摘要核对。日志 `/tmp/nk-hls30-resume-evidence/`,回执 `E:/Temp/nk-ios-033-evidence/hls30-mac-receipt.json`。原10秒失败日志仍保留:晚期交互接近片尾可能触发正常重播,本次不据此断言其调用原因。本次通过仅覆盖模拟器页面关闭与重开,不涵盖跨进程、后台或真机。

## Mac定向修复已收回;HLS重开仍需复核(2026-11-04)

Orca Worker完成下载同名分组、辅助字号与HLS字幕三项定向验收。DownloadsView保留源/漫画ID作为分组身份:旧版两条均显示“甲章”,修复后同名条目正确区分,删除一条后另一条仍在并可进入。DiscoverView在辅助字号下显示单列:“收藏”不再逐字换行,发现/设置末端可达底栏上方并操作,普通字号仍为原两列与顺序。HLS实际播放中选择中文/英文均有文字截图,关闭后消失,媒体Referer与Range206正确;不据此推断默认轨自动选择、音频或真机通过。

播放器onDisappear统一进度回写后,手势与按钮均保存seconds=7、percent=70;旧手势未生成shelf.json。此前重开验收仍是FAIL:传入start=7却观察pos=1.5和seek completion target=0。补充日志显示从7s播放约2.7s后暂停,后续选择字幕并再次播放,可能触发10秒片尾的正常重播;根因尚未确认。后续30秒同源夹具的实际初始位置复核已通过,见本页最新记录;不能倒推原10秒调用原因。严格大于5s才可续播的现行规则保留,没有改成从3s也恢复。

三份源码已逐字节收回并整合main,与Mac受测SHA一致。组合App/UITests的Mac增量build-for-testing成功日志 `/tmp/nk-downloads-identity-evidence/ios-build.log`。分别的运行证据位于 `/tmp/nk-downloads-identity-evidence/`、`/tmp/nk-largetext-fix-evidence/`、`/tmp/nk-ios-hls-evidence/`、`/tmp/nk-ios-evidence-resume/`;Lead回执 `E:/Temp/nk-ios-033-evidence/mac-ui-receipt.json`。没有重跑完整UI。删除重复play的实验候选未采用;0.3.3/15仍未发布,恢复已完成定向复核,最终CI/IPA仍待验收。

## 主题矩阵补验:空状态已查看,最大字号布局待修(2026-11-04)

Orca Worker 完成三项主题链接用例,并逐张 read 查看浅/深色 × 竖/横屏的发现页与设置页共8张图及AX树。竖屏 app.frame 为402×874 pt、图1206×2622像素;横屏为874×402 pt、图2622×1206像素。四种状态无空白或方向错误,初次XCTest横屏裁切图未计入。横屏仅为同一iPhone模拟器的更宽视口,不是iPad或折叠设备。证据 `/tmp/nk-theme-matrix-evidence/visual-review.md`,Lead范围回执 `E:/Temp/nk-theme-matrix-review/receipt.json`。

发现页只覆盖空状态:普通字号卡片/双列正常,浅深外观正确;下缘内容位于原生标签栏之后,尚未证明末端内容无法滚动到达。深色设置蓝字偏暗是视觉观察,没有定量对比度结论。最大辅助字号下“收藏”卡片一字一行,需要最小布局修复;设置AI行初始在底栏下方,但 discover.search、discover.browse、settings.ai 均实际点击打开,日志 large-actions.log。因此不把这轮记作全部内容或大字号布局通过。

本轮无产品改动。系统外观和字号已恢复,结束主题跟随系统;起始方向未知,结束为竖屏,测试CA和测试主题保留。待验范围包括最大字号修复、有封面列表和完整滚动末端;已通过的三项链接路径无需重复全套。

## Core 3be57b5 已整合 main,最终组合 CI/IPA 已验收(2026-11-04)

当前 main 的 Core pin 为 `3be57b5ceb848bb9623c090abc463764add14de4`,包含 Swift 流式响应头/分块转发与 Magpie 登录成功后立即绑定 Core 的修复,以及逐字节收回的真实 Core 回归。产品与测试源码保持受测组合 `357434677c7fd389ccc512965027a5e456021658` 一致;仅整合文档并移除临时候选分支的 CI 自动触发。

GitHub Actions `41689864772` 在该精确候选上成功:Core 构建、Kit 单测执行、设备 App 构建、UITests 编译及 IPA 打包上传均通过。下载的未签名 IPA 为29,455,523字节,SHA-256 `e12e8e8f97f2541717fd2f3dded6199bd75e8b2a09d4e8a3bdf1dc3c76214634`;App/Widget 均0.3.2/14、最低iOS26.0,App二进制含预期Core pin。artifact摘要及两层ZIP CRC均通过,回执 `E:/Temp/nk-ios-final-integration/receipt.json`。完整CI日志下载被插件地址校验拒绝,因此只报告步骤结果,不补造测试总数。

CI只编译UI;两条AI真实签名模拟器UI的Orca Worker证据见下方,其受测产品文件与本组合一致。此IPA不是新版本发布,公开v0.3.2/AltStore仍是旧4f213ff包。主题矩阵由原Worker执行,当前桌面Mac包已排队;真机/后台/PiP/Live Activity、真实账号与Mac正常关窗等范围仍未验收。下方历史段落中的main/pin/待验说明保留其当时状态,以本节为当前整合状态。

## 标准 AI 签名模拟器 HTTP/UI 闭环通过(2026-11-04)

Orca Worker 在 d3672a8/3be57b5 加已核对的 Magpie 绑定修复上,仅用专用模拟器72DFD602-9D8E-40BB-8F96-DA3668ABE7C7和fixture-key完成1项/1通过(183.049秒)。Chat/Responses/Messages分别显示预期Fixture回答,界面明确标为整包。UI停止慢回答使同请求22出现peer_closed,无expired;模型目录401精确显示错误,既有Chat答复数量不变(不扩称单独的回答401用例)。App terminate/launch后未输入密钥,仍显示清除密钥,恢复18796/v1基址,请求24/25授权成功。最终请求16–25均授权且无Cookie,证明模拟器App自身Keychain恢复,不是宿主Keychain或真实账号/refresh验证。

前三次失败分别为驱动插入/v1v1、waiting事件误要求mode、401断言误匹配旧历史,修正驱动后通过,标准AI产品源码未改。日志/xcresult/截图在 `/tmp/nk-standardai-acceptance/evidence/`,Lead回执 `E:/Temp/nk-standardai-ui-acceptance/receipt.json`。未重跑完整Kit或Magpie UI;早期ad8地址候选没有并入本次通过组合。MagpieSignInBindingTests.swift已精确收回:2713字节,SHA-256 4ebc5f612ac17b4c5c8d5c74335c356a52984207ef46a832c865f496ca6eef6e,与Mac已通过的两条真实Core绑定回归一致。

**iOS Magpie 定向 UI 已通过(2026-11-04)**:Orca Worker 在 d3672a8/3be57b5 基础上用专用模拟器 72DFD602-9D8E-40BB-8F96-DA3668ABE7C7 完成1项/1通过(78.729秒)。首次无登录按钮来自未签名测试的Keychain -34018,改用 CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- 后读取正常;随后真实产品缺陷是登录仅保存凭据、没有绑定当前Core,导致模型仍访问默认18797而非输入的52970。修复在立即/轮询登录保存成功后调用core.setAuth,旧实现2条绑定回归失败,修复后Mac相关15/15及App/UITests构建通过。UI实际完成登录、模型目录、尾部未释放前显示第一段、停止请求3并获peer_closed、App重启仍已登录且完成第一段 第二段🐾,refresh总数1。产品文件SHA-256 7b54e432e5d4fa37fa4e359c53f078a125078310aaf4e8ee17638e1d1328bd8b 已与Lead候选逐字节核对;两条回归测试源码已按字节/SHA核对并纳入候选。证据 `/tmp/nk-d367-acceptance/ios-diagnostic/` 的 binding-fixed.log、ui-binding-fixed.log、ui-binding-fixed.xcresult、events.jsonl;Lead回执 `E:/Temp/nk-magpie-binding/receipt.json`。这是模拟器App自身认证持久化,不是宿主Keychain或真机;registry仅预置包,不算UI导入包。旧失败日志保留,既有CI d367产物不包含此后续修复。

**新 pin 的 Mac 真 HTTP 组合验收(2026-11-03)**:Orca Worker mac-validate-2 在 Nekularity `d3672a8`/Core `3be57b5` 上,经真实 URLSessionTransport→CoreHost/CoreStreamHost→gomobile CoreMagpie→loopback HTTP 完成 1 test/1 suite。模型目录、尾部释放前首段「第一段 」到达、取消后同一请求 ID 3 的 peer_closed、SavedAuth 原样保存到临时文件并重建实例后完整回答「第一段 第二段🐾」均通过;刷新总数为 1,四个供应商请求均授权且无 Cookie。SDK 来自精确干净 Core 检出,macOS 切片 SHA-256 24c00ca89b47cd80529063924f56d6a39f5304481174dca12712d0115e71f366。

定向日志 `/tmp/nk-d367-acceptance/evidence/acceptance-test-02.log`,事件 `events-final.json`,SDK 来源 `sdk-identity.log`;Lead 汇总 `E:/Temp/nk-3be-candidates/mac-http-acceptance.json`。第一次仅测试代码编译失败(Thread.isMainThread 的 Swift 6 异步上下文限制),修正后通过;产品 Sources/ 无差异。未运行本轮 503、完整 Kit、App 构建、iOS UI 或 Keychain 验收。CI 41661859155 现已在精确 d3672a8 上成功:Core 构建、Kit 单测执行、App 与 UITests 编译、IPA 打包均通过。2026-11-04 下载核对未签名 IPA 29,455,876 bytes,SHA-256 7590d8ebcdf67b4fed8bd191e187f0337ba144cde6baf7f5fe033229fcd4f77c;App/Widget 均为 0.3.2/14,最低 iOS 26.0,App 二进制含 Core 3be57b5 pin。artifact 摘要与两层 ZIP CRC 通过,回执及日志 `E:/Temp/nk-ios-d367-ci/receipt.json`、`verify.log`。UI 在该 CI 中仅编译,未执行;发布步骤跳过,未更新 AltStore,不代表真机或 iOS 界面已验。

## Core 3be57b5 消费端候选(2026-11-03)

本分支 `update/core-3be57b5` 从当前 main 建立,将 scripts/core-version 与 CoreVersion.swift 同步到已发布 `3be57b5ceb848bb9623c090abc463764add14de4`。Core 的功能源码 `6129f59` 已过 CI `41631619233` 四个作业,发布收拢前后完整 tree 一致。Windows pin/Swift 解析/Kit 调用名称契约检查通过,不等于 Mac 编译。本分支现接入 Swift 响应元数据与分块转发实现:产品文件与已受测 77c2c6 一致,真实 SSE 测试的 Git blob SHA-256 为 a53f3bdabed91f1812282d7c7502541a96142f32f32ebb0bf4013bfe63a68e01,与 Orca Worker 在 Core 4f213ff 上通过 428 tests/79 suites 的文件一致。该旧 pin 结果不能替代本次 Core 3be57b5 组合验收;真实 URLSession→Core Magpie→HTTP 闭环已由本页顶部的 Mac 定向结果确认,分支 CI 与 IPA 已通过核对;加入登录绑定修复后的 Magpie 定向 UI 已通过,见页首分范围记录。scripts/fixtures/magpie-http 同步自 main 62cfde6,仅供主机夹具使用。标准 AI 页面仍整包。候选 `ea87eb5` 的 Mac CI `41638119772` 完成 Kit 单测及 App/UI 测试编译;未签名 IPA 已核验摘要、双层 ZIP CRC、App/Widget 0.3.2/14 和 Core marker,回执 `E:/Temp/nk-3be-candidates/ios-ipa-receipt.json`。UI/真机未执行,main pin 保持 `4f213ff`。日志 `E:/Temp/nk-3be-candidates/ios-*.log`。

**Magpie 本地 HTTP 夹具(2026-11-03)**:新增 `scripts/fixtures/magpie-http/`，包括仅绑定 127.0.0.1 的服务与可导入供应商包；支持模型目录、假凭据刷新、可扣住后半段的 SSE、指定请求释放、对端关闭和 HTTP 503。Lead 使用发布 Core `3be57b5` 的公开 mobile Magpie API 经真实 HTTP 验证：首段先于正文完成、取消令服务端观察到 peer_closed、SavedAuth 文件保存后重建实例继续可用且刷新次数保持一次、Unicode 回答与错误传播均通过。包内文件也经 ReadPackageArchive/LoadPackage/Auth 核对。日志与 ZIP 在 `E:/Temp/nk-magpie-http-evidence/`，使用方法见 [夹具说明](../scripts/fixtures/magpie-http/README.md)。这是 Windows Go 宿主的接口验收，不是 Swift URLSession、Keychain、App 重启或 iOS UI 通过；main pin 仍为 4f213ff，后续客户端需自行保存刷新结果并真实重启读取。

**Core 发布与消费端候选更新(2026-11-03)**:Core main 已发布 `3be57b5`,功能源码与通过 CI `41631619233` 四个作业的 `6129f59` 相同,保树收拢回执见 `E:/Temp/core-stream-release/publish-receipt.json`。新的独立 pin 候选为 Nekularity `ea87eb5` 与 Nekophage `f7b99d1`,均指向 3be57b5;桌面七项检查与实际二进制版本核对通过,iOS 候选 `ea87eb5` 的 Mac CI `41638119772` 通过 Kit 单测、App 与 UI 测试编译;下载的未签名 IPA 的 SHA-256、ZIP CRC、App/Widget 0.3.2/14、最低 iOS 26.0 和 Core marker 已核对,UI 未执行。Swift 提前响应头候选 `65eba9f` 的 CI `41635149850` 在 Kit 单测失败;后续 `77c2c6` 的 Mac 定向三项断言也失败,首个结束原因正在诊断,尚未并入新 pin 候选。Core 可在响应头提前交付的宿主上增量返回文字,但旧客户端宿主仍延后,标准 AI 页面仍整包;新 pin 的窗口、Mac 消费端、UI 与真机结果不能借用旧版本。两端 main pin 均保持 4f213ff。

**桌面主线整合(2026-11-03)**:先前把 Nekophage 工作分支称作 main 的口径已更正;整合前真正 main 为 `28be4bd`/Core `214e778`,核对日志 `E:/Temp/core-magpie-first-chunk-evidence/desktop-main-ref.log`。现已将 `fix/subtitle-record-cap` 快进整合为真正 main 的 `67fc877`,pin 为 `4f213ff`,原分支保留;同时带回 WebView 探针隔离修复并移除误入版本控制的 Python 缓存。七项检查与 Windows 隔离阅读回归通过:两页解码、双页、55% 进度、重开恢复 1200,仅有本次章节存储键。回执 `E:/Temp/nk-desktop-integration/receipt.json`。`a079ce7`/Core `b55c1a4` 的 Windows 包仍属于独立候选,新 pin 的 macOS 消费端尚未验收;Nekularity main 仍 pin `4f213ff`。

更新:2026-11-03。

## Core 主线 b55c1a4、编译修复整合与下一 pin(2026-11-03)

Core 取消修复 `696a504` 的三个 Go 平台与 Apple job 全过(CI `41606605713`),产物日志确认 macOS/iOS 模拟器 CoreSmoke 各 8 例通过。下载 SDK 72,763,815 字节,SHA-256 `2253fcac9be9c68859a022abee489b6ddef304f7a26a760cef8252cfeb53f593`,CRC/三类切片/头文件核对通过(`E:/Temp/core-696-apple/receipt.json`)。SDK 不嵌 Git revision,归属由 CI/artifact HEAD 和摘要证明,不声称二进制含提交号。按 Core 仓库约定整合并收拢历史后,主线为 `b55c1a488746efc1454e4f4781e4e83dc577d187`;完整 tree 在收拢前后相同,与受测 `696a504` 的功能源码一致,仅证据文档不同。日志 `E:/Temp/nk-magpie-loopback/squash-publish.log`。

真实 loopback 补验也通过:公开 mobile API 的响应头等待、分块等待和整包读取均在取消后被服务器观察到连接关闭,之后同一 runner 能完成新回答。旧 `2c9c83b` 对照不能在取消后关闭连接。日志 `E:/Temp/nk-magpie-loopback/cancel-fixed.log`、`cancel-old-negative.log`。这是 Go HTTP 客户端,不是 Swift URLSession 或 UI。另一个未通过项已明确复现:设置 `REQUIRE_PLUGIN_FIRST_CHUNK=1` 后,服务器已发送首段但扣住后续正文时,`ChatNext` 文本超时;同目录 `first-text-limitation-b55.log`。插件 fetch 等待 DoStream 完成才返回,所以不能把传输分块当成界面增量交付。

旧 pin 客户端候选 `af48d65` 的 CI `41607054742` 已全部通过,包括 Kit、设备 App、UITests 编译和 IPA 打包。诊断 artifact 中生成的工程没有 `serve.py in Resources`,仍有 `clip.mp4 in Resources`。实际 IPA 29,436,243 字节,SHA-256 `1f4586d96bc9754f6161432df30d548e4e2ba161d5028ea0849b55941eb254c0`,CRC 通过;App/Widget 均为 0.3.2/14、最低 iOS 26.0,App 二进制含 Core `2c9c83b`。它只是分支验证包,未发布或更新 AltStore,也未运行 UI 套件。回执 `E:/Temp/nk-ios-core-2c9-ci/ipa-receipt.json`。资源排除与构建诊断配置已单独整合到 main,Git 暂存内容与受测 `af48d65` 两文件逐字相同(工作区行尾不同),不借此升级 main pin。

两端新候选均为 `update/core-b55c1a4`:Nekularity `b39e6b0` 的 CI `41612614917` 已成功,Kit 测试、App 与 UITests 编译、IPA 打包通过;实际 IPA 29,441,095 字节,SHA-256 `860c8cf01a8031097e5d321f7c13ffb5ac176d22c9b1a615b2859e5ae61aba7e`,CRC/下载摘要通过,App/Widget 均 0.3.2/14、最低 iOS 26.0,App 二进制含 b55c1a4 pin。回执 `E:/Temp/nk-ios-core-b55-ci/receipt.json`;未执行 UI、未发布或更新 AltStore。桌面从 `e21b04c` 修正开发探针 WebView 隔离后形成 `a079ce7`,七项检查通过;同提交 Windows 安装包已完成原生搜索→HLS/字幕→跨进程恢复 2.977162 秒、鉴权/精确 Range 与正常关闭卸载,回执 `E:/Temp/nk-b55-candidates/installed-media-587be532/receipt.json`。macOS 新 pin 消费端仍待验收。回执 `E:/Temp/nk-b55-candidates/candidates.json`,检查与版本日志在同目录。两端 main pin 仍为 `4f213ff`,不把旧 pin 的窗口或 UI 结果复用到新候选。

## 新 Core pin 的客户端编译候选(2026-11-03)

初始候选 `0ea786f` 尚未包含已验的 HTTP 错误修复;在隔离工作树 `E:/Temp/nk-ios-core-2c9` 整合 main `bf9d93d` 后得到 `5bc5b674d1477ac311a0470338e185e769fd1291`。与该 main 相比,功能源码只有 `scripts/core-version` 与 `CoreVersion.pinned` 两处 pin 差异,另有候选状态文档。Windows 文档检查、Swift 解析、pin 检查与 Kit→Core 调用契约检查通过;契约检查初次因隔离目录旁没有 Core 源码退出 3,指定 `NK_CORE_SRC` 到干净的 `2c9c83b` 工作树后通过,不属于 Mac 编译证据。

通过 GitHub 插件触发分支工作流 `41599831561`,回执确认 HEAD 为 `5bc5b67`、event 为 `workflow_dispatch`;将运行 Kit 单测、App 和 UITests 编译并生成未签名 IPA。该分支不满足发布步骤的 tag 条件,不会创建 release 或更新 AltStore。提交与本地检查日志在 `E:/Temp/nk-ios-core-2c9-ci/`,CI 回执 `build/receipts/core-2c9-consumer-runs.json`。本条仍是待验候选,不声称 CI 完成或 UI 通过;地址实验 `ad8e191` 保留给现有 Orca Worker 独立复测,未合入此候选。

## Magpie 聊天取消只停了句柄(2026-11-03)

`2c9c83b` 上的真实缺口:`Magpie.ChatCancel` 只删掉会话句柄并取消聊天自己的上下文,而 `Instance.Chat` 发请求时用的是实例上下文。因此取消之后,阻塞中的整包 `Host.HTTP`、`StreamOpen` 与 `StreamNext` 都不会停止。原有 `TestMagpieChatCancelEndsIt` 只检查句柄消失,证明不了请求被关。

隔离分支 `fix/magpie-chat-cancel` 的最终候选为 `696a5049a372e22ca0e639c103258bf38cfffb55`,CI `41606605713` 已核对该 HEAD 并启动,结果待验。先写公开入口的负向回归:`mobile/magpie_chat_cancel_test.go` 用 Core 自己的 `openai-compatible` 模板和真实 `mobile` API,让宿主阻塞在 HTTP 或 `StreamOpen`,确认修复前两条都收不到 `CancelHTTP`/`StreamClose`(`E:/Temp/nk-magpie-cancel-evidence/before.log`)。修复内容:

- 每个聊天使用独立运行时,`ChatCancel` 取消它的上下文并 `Close` 该实例,不再借用共享实例上下文。共享实例仍服务 `Models`、登录与用量。
- 刷新后的凭据写回 `Magpie.auth`,独立聊天的下一次 `auth.get`、后续聊天以及已存在的模型/登录钩子都能看到新值;运行时绑定的 provider 必须仍匹配。
- 实例创建改为不持锁构建,并在注册时复查 `closed` 与已有实例,并发创建时只保留一个共享实例,关闭后不再写入。`ChatStart` 先登记句柄再启动 goroutine,`Close` 能看见并停止它;写事件也响应取消,不再向无人读取的通道阻塞。

修复后五条定向 race 用例通过:`mobile/magpie_chat_lifecycle_test.go` 覆盖取消一个聊天不影响另一个、后续聊天继续、已存在的模型钩子复用刷新后的凭据(仅刷新一次),以及阻塞的 `StreamNext` 被关闭(日志 `focused-after.log`、`chat-lifecycle-fixed-host.log`)。这条覆盖整包、打开、读取三个阻塞阶段,并把刷新与隔离放在真实包模板上。补充用例初次失败是测试宿主按大小写精确匹配 `Authorization`,已按 HTTP 头语义修正;原失败日志 `chat-lifecycle.log` 保留。

全套 `go vet ./...` 与带真实包夹具的 `go test -race -count=1 -json ./...` 通过:22 个包,顶层 559 PASS / 0 FAIL / 1 SKIP(`race.log`、`race-summary.json`;SKIP 是未设置 `VC_WNACG_JS` 的 `TestRealSourceWnacg`,不是通过)。执行渠道是 Windows 假宿主与本地第三方包夹具,不是 iOS UI、真机或真实供应商;客户端 pin 未变。

## 新增 Core pin 的分支 CI 只通过到 App 构建(2026-11-03)

`5bc5b674d1477ac311a0470338e185e769fd1291` 的分支工作流 `41599831561` 有终态结论:**失败**。通过的是 checkout、Go、XcodeGen、pinned Core 构建、仓库检查、Kit 单测、工程生成与未签名设备 App 构建;失败步骤是“Compile the interface tests”,退出码 65,导致 IPA 打包与产物上传跳过,发布步骤因非 tag 未运行。

整体 job 日志下载被 GitHub 插件地址安全校验拒绝(未绕过),check-run 注释只有 Node 20 弃用、退出码 65、Go 缓存缺失与 macOS 队列提示,没有编译器错误行。因此失败点确定为 UITests 的 `xcodebuild build-for-testing`,但**具体编译错误未取得**:不能推断是候选代码、测试源码还是 CI 环境问题。Kit 单测与设备 App 构建通过,说明失败不在 Kit 或 App 编译。

该候选不满足“回归通过后才能发布”的条件,main 与已发布包仍用 `4f213ff`。随后源码核对发现 UITests 递归收进 `Fixtures/theme/serve.py` 与 `Fixtures/standard-ai/serve.py`;XcodeGen 默认把 `.py` 归为资源,两份文件会有同一扁平输出名。候选 `af48d652f260b4a8e58e0f6b86c4237d6717ce3c` 排除这两个宿主脚本并保留 `clip.mp4`,同时将 UITests 构建日志、xcresult 和生成工程作为 artifact 保留,用 pipefail 传递真实退出码。YAML/文档检查通过,日志 `E:/Temp/nk-ios-core-2c9-ci/resource-fix-checks.log`。新 CI `41607054742` 已核对该 HEAD 并启动,不声称原 exit 65 的原因已由日志证明或新编译已通过。

## Core pin 工具保留历史证据(2026-11-03)

旧 `set-core-pin.sh` 会全局替换两份 STATUS 中的旧 Core 哈希,使已有测试记录看起来使用了新 Core。已用临时仓库复现两份文档均被错误改写,日志 `E:/Temp/nk-pin-evidence-before.log`。脚本现在只改 `scripts/core-version` 与 `CoreVersion.pinned`,复用 `check-core-pin.sh` 校验,不改历史文档;新候选和新验收应单独通过 `update-pair.py` 记录。修复后验证历史文档与 Swift 原行尾不变、重复设置幂等、`--check` 通过、非法参数不写文件,日志 `E:/Temp/nk-pin-evidence-after.log`。这次修复本身不升级客户端 pin。
## 标准接口 HTTP 错误修复已整合(2026-11-03)

`bb77b5d` 的回答错误修复已通过 `9af6148` 整合 main:旧 `StandardAI.reply` 会把 HTTP 401/503 或 HTTP 200 内嵌供应商错误当正常助手回复,现在抛出 `StandardAIError`。Orca Worker 在 Mac 通过 `swift build --build-tests`、四条定向测试及全套 **425 tests / 78 suites**;恢复旧实现的负向对照使两条错误用例失败。证据在 Mac `/tmp/nk-ai-http-evidence/`,包括 `full-swift-test.log`、`negctl-filter.log`。四条测试使用真实 Core/URLSessionTransport,以 URLProtocol 替代网络,覆盖三协议成功回答、鉴权头、禁用 Cookie、HTTP/内嵌错误及模型目录;每条请求独立主机和临时资料,不访问 Keychain。这是 Kit 回归证据,不代表标准接口页面的 HTTP/UI 闭环通过,也不在已发布 v0.3.2 中。

新增 `UITests/Fixtures/standard-ai/serve.py` 是只监听 loopback 的整包 HTTP 服务,支持正常/慢响应/401/503/200 内嵌错误。Windows 已实际验证模型目录、三协议回答、错误、TCP peer close、控制接口释放正文,日志 `E:/Temp/nk-ai-fixture/verification.log`、`events.jsonl`。日志不含鉴权值或提示正文。它不实现流式或凭据刷新,也不证明 Swift 客户端/界面通过;页面自动化还需隔离测试设置和 Keychain 命名空间。

**新 pin 标准 API 真 HTTP(2026-11-04)**:Lead 以干净 Core 3be57b5、公开 BuildAIModelsRequest/SendAIRequest/Cancel 和真实 Go HTTP 宿主运行现有 loopback 夹具,go run -race 通过。chat/responses/messages 三协议各验证目录、正确鉴权头、整包回答、401/503及200内嵌错误的状态/JSON原样透传、慢响应取消与随后新请求成功。共21个已授权且无Cookie的请求;取消请求6、13、20均被服务端记为同ID peer_closed,无expired。日志/回执 `E:/Temp/nk-standard-ai-core-http/run.log`、`receipt.json`,可复用客户端 `client.go`。这不验证Swift错误展示、URLSession、iOS UI、密钥持久化或流式;错误处理仍由客户端负责。

## 标准接口地址输入与请求路径的分歧(2026-11-03)

`44786f2` 的 Orca Worker 回执为 Kit/App/UITests 编译通过、五次输入检查失败、夹具 0 请求;日志在 Mac `/tmp/nk-fix-evidence/`。后续 `ad8e19143bc346d09bbd6211bfce374cb6815611` 同样通过 `swift build --build-tests`(13.95 秒)及 App/UITests 构建。Worker 报告逐字输入、清空后粘贴、改回、慢速输入与重启读回五例在应用视角通过,但离线读取 plist 的 JSON 均少一个 `/`。这些是不同观测,仍未确定差异发生在应用、偏好读取还是测试驱动;不能据此认定 cfprefsd 是原因或把磁盘观测作废。

`ad8e191` 的模型目录请求仍失败:页面显示目标 `http://127.0.0.1:63640/v1`,保存假密钥后点击读取目录报 `aiapi: the API root has no host`,夹具 0 请求。后续三协议回答、取消/peer_closed、401 与假密钥重启读目录均未验收。Mac 证据 `/tmp/nk-fix2-evidence/` 包括 `build-tests.log`、`app-build4.log`、五个 `url*.log`/xcresult 以及 `full.log`/`full.xcresult`;临时驱动 SHA-256 `28ba5e27ba723a4d80ea6361913188acb6a0afc2ed94f59429b43d519e7c4f5c`。目前的通过范围限于该驱动报告的显示/清空/重启读回,不等于请求配置正确。

Lead 在 Windows 使用同一 `4f213ff` 源码的公开 `mobile.Core.BuildAIModelsRequest` 做了 18 个组合检查(三协议 × 三种地址 × 普通/转义斜杠 JSON)。完整地址均生成正确的 `/models`;`http:/127.0.0.1:63640/v1` 精确复现 `no host`;`/v1` 报的是 `must be http or https`,与此次错误不同。日志 `E:/Temp/nk-ai-root-diagnostic/core-4f-boundary.log`,临时复现源码 `main.go` 位于同一目录。该结果验证 Go 构造边界,不替代 Apple bridge 或 UI 验证。

“逐键保存/重绘竞争”以及“按钮读取了最短的中间快照”均未被直接测量证实。下一步在同一专用模拟器检查临时驱动的输入、清空和重启流程,并对照字段文本、addressDraft、config/snapshot、wireJSON 中 baseUrl 的 UTF-8 字节,寻找首次分歧。只记录本地假地址,不记录密钥或完整配置 JSON;不靠注入偏好或放宽 URL 校验让用例通过。

## 标准接口取消修复已整合(2026-11-03)

main 已整合 `77b969f` 的三份 Swift 文件,与 Mac 受测版本逐字一致,其余整合差异仅文档。Orca Worker 在该提交上通过 `swift build --build-tests`(14.79 秒)、`swift test` **421 tests / 77 suites** 与五条定向回归;之后 App + UITests 的 `xcodebuild build-for-testing` 通过,日志明确编译了 `App/StandardAIView.swift` 与 `StandardAIRequest.swift`。工程复用已有生成项目,`project.yml` 与 `9498b4c` 一致,没有声称重跑 XcodeGen。

修复让模型目录和回答请求共用可取消任务,停止、切换接口/地址、更新密钥或离开页面时取消实际操作,迟到结果不覆盖新请求状态。负向对照的边界已核清:单删成功 guard 仍 5/5,因为代际检查继续生效;同时删 guard 与取消时的代际推进后,迟到答案断言失败;去掉代际提交校验后两条替代请求用例失败。恢复后 diff 0 字节、五条复跑通过。日志 `/tmp/nk-77b-evidence/` 下的 `build-tests.log`、`swift-test.log`、`app-build.log`、`build-evidence.log`、`diag2-filter.log`、`diag3-filter.log`、`filter-restored.log`。

这是 Kit 执行与 App 编译证据,未执行标准接口页面的真实 HTTP/界面闭环,也未使用真实账号。该修复不在已发布 `v0.3.2` 中;该版本的 416/76 与完整 UI 27/0/0 保留原提交归属,不改写成当前 main 的 UI 结果。标准接口仍整包返回。

## 0.3.2/build 14 已发布并核对

tag `v0.3.2` 指向 `76a1ccd68b4834d169e58610a339322e1c7e29b4`,与受测 `9498b4c` 只差验收文档。发布 CI `41578147149` 的 13 个步骤全部成功:Build pinned Core、Check the tree、Kit 单测、Generate project、Build unsigned device app、Compile the interface tests、Package unsigned IPA、upload-artifact、Publish IPA 均 `success`,整轮 04:26:35–04:50:49 UTC。GitHub 插件拒绝下载整体 job 日志(地址安全校验指向内网/特殊地址),未绕过;本轮对 CI 的结论只依据 job/step 的 API 状态,不声称读到日志正文。

发布资源核对(本地直连下载,`E:/Temp/nk-ios-032-release/ipa-verification.log`):HTTP 200、**29,418,522 字节**、SHA-256 `f59afe889def90131a8994a59a92571b6acc823679431d37c16c032f29bc8737`,与 GitHub 记录的 asset size/digest 一致;zip CRC 通过;`Payload/Nekularity.app/Info.plist` 与 `NekularityWidgets.appex/Info.plist` 均为 **0.3.2/14、最低 iOS 26.0**;App 主二进制含 Core pin `4f213ffbd51cfa22ef032a4279a04efb71b36283`,旧的 `8e14aade75f5` 已不在包内。回执 `E:/Temp/nk-ios-032-release/ipa-receipt.json`。包未签名,签名安装与真机仍不在核对范围。

AltStore 工作流 `41582051344`(手动触发 `update-source.yml`)整轮成功,提交 `468761a5d267292d5742aa11de676e6052fb917c` 的 `apps.json` 已把 Nekularity 稳定轨道与扁平首版都更新为 **0.3.2/14**、29,418,522 字节,下载与图标均指向 `v0.3.2`;IPA 分段请求 206、`Content-Range: bytes 0-1023/29418522`,图标 HTTP 200(443,517 字节,`image/png`)。cnb.cool 镜像与 `releases/download/latest` 入口已读到 0.3.2;`raw.githubusercontent.com` 首次核对时仍返回 0.3.1,约 12 分钟后再读已是 0.3.2,属同域 CDN 缓存滞后而不是仓库内容不一致(三个入口现都读到 0.3.2)。证据 `E:/Temp/nk-ios-032-release/altstore-after.json`、`apps-468761a.json`。

## 0.3.2/build 14 合并树验收

合并树 `9498b4c7c80ce6e4edcdf5c0b5e9afc5c065d4bd` 已由 Orca Worker `mac-validate-2` 在 Mac 上验收并整合到 main:Core `4f213ff`、下载库释放修复和严格本地搜索回归在同一提交上通过。`swift build --build-tests` 14.30 秒通过,`swift test` **416 例 / 76 suites** 通过;完整 UI 一次执行 **27 PASS / 0 FAIL / 0 SKIP**,722.577 秒,主类 23、主题 3、三列 1,xcresult 摘要一致。日志 `/tmp/nk-949-evidence/build-tests.log`、`swift-test.log`、`app-build.log`、`full-ui.log`、`counts.log`、`xcresult-summary.json`。这是一轮合并树执行,不是把下述单独分支结果相加。

实际模拟器构建的 App/Widget 均为 **0.3.2/14、最低 iOS 26.0**,Bundle ID 分别为 `com.laincat.nekularity` 与 `com.laincat.nekularity.widgets`。本机 `xcodegen generate` 因命令缺失未执行成功,Worker 复用既有生成工程并只同步八个版本设置值,App/UITests 编译与上述运行均成功。发布 CI 已从 `project.yml` 全新生成工程并完成设备 Release 构建与 IPA 打包,下载/大小/包内版本/Core pin 与 AltStore 均已核对见上一节。发布提交 `76a1ccd` 相对受测 `9498b4c` 只有验收文档差异;后续 main 新增标准接口取消修复,该修复的证据见本文对应章节。

Core 实际 HEAD/pin 均为 `4f213ffbd51cfa22ef032a4279a04efb71b36283`,Vendor 与 98e 原产物整树摘要一致(`83158a56862851cac804695c720c3a14ea553f1efdb9c17e2461d81cf456efbb`)。macOS 切片 SHA-256 `69284254554cbec08a35860a8cb50c86a439c030a26dd0e1fd65343ade6b4840`,模拟器切片 `ca54af50dad6e26d1b0931c6627ec8611df45942b2630594a0717e77312d76bf`,完整记录 `/tmp/nk-949-evidence/vendor-sha256.log`。主题服务复用原 CA,未新增或删除信任项;HTTPS 4 次请求(含预检),HTTP 0 次。旧三张 CA 不在册,保留的 `C0E33FBD155EF2C9…` 到期时间为 2026-12-03 02:52:02 GMT;服务已停,证书目录保留。

Orca Worker 从旧日志核实 `1888cd3` 完整 UI:**27 PASS / 0 FAIL / 0 SKIP**,共 722.784 秒,其中主类 23、主题类 3、三列类 1。`xcresult` 摘要同为 total 27/passed 27/failed 0/skipped 0。日志 `/tmp/nk-1888-evidence/full-ui.log`、`counts.log`、`xcresult-summary.json`。同提交的单独主题 3/3 仍单列,不加到 27 中。此前 `95818c5` 的 23/4 是历史记录,不再充当最新完整回归。

`ed09c82` 的 `swift build --build-tests` 通过(14.87 秒),完整单测 **416/76 suites** 通过,共享加载 3 例、下载写盘 14 例通过;把弱引用临时改回强引用后,归档/加载器未释放的两条断言如期失败,恢复后该例通过、diff 0 字节。两条下载 UI 均通过且无跳过:失败下载重试 50.642 秒、无服务离线阅读 36.928 秒。证据在 `/tmp/nk-ed09-evidence/`: `build-tests.log`、`full-swift-test.log`、`negctl-test.log`、`negctl-restored-test.log`、`downloads-ui.log`。

`61197f8` 在 Core `4f213ff` 上通过 Swift 构建(14.62 秒)和 App/UITests 编译。有效夹具下搜索用例通过(24.823 秒);故意抛出搜索错误后退出 65、用例 FAIL(80.121 秒),断言为 `Callback Probe is local and must return Probe Comic`,没有 SKIP 或环境/编译错误。恢复后的种子与初始有效种子逐字节一致,同例再通过(23.027 秒),工作树干净。日志 `/tmp/nk-611-evidence/valid.log`、`negctl.log`、`fixture-search-failure-tree.txt`、`restored.log`。这已验证旧的站点限制跳过条件得到修正。

CA 状态也已按指纹核实:三张旧 CA(sha256 前缀 `3D1895C2E4984B91`、`FBCE77CD0660BC0E`、`38C95A8619A02359`)已从该专用模拟器生效的 trustd 存库移除;`simctl keychain reset` 本身未移除它们,不能作为清理成功的证据。当前库为 5 条系统根加 `1888cd3` 新 CA(前缀 `C0E33FBD155EF2C9`,2026-12-03 到期),因此不宣称测试 CA 已全部清空。旧 CA 移除后请求失败、夹具 0 请求,日志 `/tmp/nk-theme-after-removal.log`;原库备份 `/tmp/nk-truststore-backup-102519.sqlite3` 保留。本轮合并回归已复用该有效证书,没有 reset 或修改 trustdb。

## Core pin `4f213ff` 的 Mac 验收

Orca Worker `mac-validate-2` 在分支提交 `98e2e76f16c42b097a263cd6f0d1227708da8440` 上重新运行 `scripts/fetch-core.sh`,生成的 xcframework、`build/core` HEAD 与 `scripts/core-version`/`CoreVersion.pinned` 均为 `4f213ffbd51cfa22ef032a4279a04efb71b36283`。`swift build --build-tests` 通过(15.68 秒),`swift test` **415 例 / 76 suites 全过**,`xcodebuild build-for-testing` 通过。415 而非 416 的原因是该分支没有包含 `ed09c82` 的下载库生命周期新用例,不能据此声称那一修复已经验收。

五源种子经 `make-seed.py` 重建与 `check-seed.sh` 核对后,模拟器四例均通过、无跳过:`testSearchReachesDetailWithTags` 23.090 秒、`testCategoryPageListsItsPartsAndComics` 27.658 秒、`testBrowseLoadsSections` 25.720 秒、`testVideoPlaysTheSourcesClip` 29.073 秒。日志分别在 `/tmp/nk-98e-evidence/fetch-core.log`、`build-tests.log`、`full-swift-test.log`、`app-build.log`、`core-ui.log`。受测提交是 `98e2e76`,整合时主线相对它仅有文档差异;这四例不替代完整 27 条回归,也不是真机/账号验证。已发布 0.3.1 的包内 pin 仍是 `8e14aad`,本次未发布新版。

Worker 还在临时夹具中直接调用 `URL`/`URLSearchParams`:新 Core 通过(22.561 秒),旧 `8e14aad` 下原夹具通过(21.983 秒),加入 URL 调用后却被搜索用例的 guard 记成 `XCTSkip`「network or site limit」(112.395 秒)。这是测试把本地回归当成站点问题的缺陷,不是旧 Core 兼容通过。日志 `/tmp/nk-98e-evidence/urlprobe-4f213ff.log`、`plainprobe-8e14aad.log`、`urlprobe-8e14aad.log`。探针改动已恢复,最终 Core/Vendor 为 `4f213ff`,工作树干净,恢复态搜索再过(21.623 秒)。搜索用例的跳过条件将单独修正,不改写本次计数。

## 宿主接口形状已核对

`CoreHost` 的 21 个方法逐个比过 Core 里 `apple/CoreSmoke` 的 Swift 宿主实现(那份在 CI 里真的编译并跑过):返回对象的方法由 Clang 导入成 `(参数…, error: NSErrorPointer) -> String`,返回 `void`/`Bool` 的方法导入成 `throws`。例如 `http(_:error:) -> String`、`saveData(_:dataKey:valueJSON:) throws`、`writeClipboard(_:) throws`、`readClipboard(_:) -> String`,Nekularity 的写法与之一致。这只是签名对得上,不等于编译通过——真正的类型检查仍要等 Mac 上那次 `swift build`。

界面层调用的 Kit 成员也逐个核过:`library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`,`core.search / searchOptions / explore / explorePages`,`shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`,`searches.add`,`store.loadSetting / saveSetting` 全部存在且参数对得上。
| 视频 | 视频源是 Core 里的插件(`video-js`、Kazumi 规则、内置源),客户端只负责播:`CoreClient.videoSearch/videoDetails/videoPlay` 三个调用;「视频」页选源、搜索、加载更多;详情页按站点给的线路分组列出剧集;点剧集后向源取播放地址,带 `Referer`/`User-Agent` 交给 **AetherEngine** 播放(AetherEngine 只依赖在 App target,`NekularityKit` 不引入,免得 `swift test` 拉二进制框架)。源若只给「嗅探播放页」而不给直链,界面明说这条路径尚未实现,而不是给一个黑屏。**尚未编译、未在真机或真实视频源上验证。** |
| 下载 | `DownloadStore`:把一章的原始字节存到 `Downloads/<源>/<漫画哈希>/<章节哈希>/<页码>.img`,清单写在 `manifest.json`;地址来自 Core 的 `chapterImages`,取字节走 `ImageLoader.raw`(与阅读器同一套请求规则、同一份 `onResponse` 改写)。`ImageLoader` 在联网前先问它,所以**下载过的章节在没有网络时照样能读**,阅读器本身不需要知道下载的存在。详情页长按章节下载、右上角可下载全部,书架右上角进「下载」页看占用并删除,**下载页点一行就能直接阅读**(断网时这是唯一的入口:再去问源要章节列表等于让网络证明自己不需要网络)。Liquid Glass 只用在导航层:浮动栏与搜索球同属一个 `GlassEffectContainer`,胶囊控件用 `glassEffect`,内容卡片保持实心——玻璃铺在内容上会互相折射且掉对比度。动效遵循「只动 transform 与 opacity、0.2–0.35 秒、尊重「减弱动态效果」」;选中胶囊走一条 `matchedGeometryEffect`。**CI 已编译通过;明暗与折叠形态尚未实看。** |
| 主题 | 主题是**数据不是代码**:`Theme` 一张 JSON(强调色、背景、卡片表面、圆角、是否强制深浅),内置只有「跟随系统」(Miuix 两套因无人使用已移除);用户从「文件」导入一张 JSON 即可装新主题,存在 `Themes/<id>.json`,id 会被消毒以防写到目录外,安装不改变当前选择。「设置」页里选主题、看下载占用、看版本与 Core 提交。应用方式是在根视图统一 `.tint` + `preferredColorScheme`,不逐个界面改,否则会变成「只有部分界面生效」的样子。**尚未在 Mac 上编译验证。** |
| 本机视频库 | 「视频」页分成**本机 / 在线源**两半。本机侧:`VideoLibraryStore` 把导入的视频**复制**到 `Media/Videos`(不用安全作用域书签——别的 App 容器里的书签在对方移动或替换后就失效,「我的视频不见了」比多占一份磁盘更糟),记录时长与播放位置;「继续观看」只挑**看过 30 秒以上且未看完**的;播放器用 `AetherEngine.load(url:startPosition:)` 从上次位置开始,关闭时把位置写回。文件在外部被删掉时不会继续留在列表里。**尚未在 Mac 上编译验证。** |
| 首页卡片 | 卡片分两类:**本机模板**(继续阅读/收藏/最近搜索/已下载/本机视频/视频源)与**源分区**——源在 `explore` 里声明的推荐、排行、分类,可直接放到首页,取的就是「浏览」里同一个分区,因此源不需要知道首页存在。版式是瀑布流(`MasonryLayout`,按最短列摆放),**列数按可用宽度决定**:< 560 两列、< 900 三列、其余四列——折叠屏、分屏与 iPad 宽度各不相同,按机型判断会在展开形态上留下大片空白。编排方式仿系统小组件板:**长按卡片**进入编排并轻微抽动,拖到另一张卡上即插入该位置,「小/中」菜单直接改占列数(两列屏上中即整行),编排时卡内点击不跳转。**CI 已编译通过;交互尚未在设备上实际操作验证。** |
| 灵动岛 | 下载中的章节进入 Live Activity:锁屏与灵动岛三态各自设计(紧凑态环形进度 + 百分比、最小态只有环、展开态才有标题与页数),一次只讲一个章节,已显示的章节会留到它结束,不让第二个下载把文字在眼前换掉。文案与算术在 kit 的 `DownloadProgressText`(可在 macOS 上测),ActivityKit 只在 App 与 Widget 扩展里。`Activity` 未标 `Sendable`,跨隔离需 `@preconcurrency`。**编译通过;从未在设备上亮过。** |
| 资源库入口 | 「资源库」除媒体服务器与模块外,加了四个入口:**全源搜索**(打开搜索并默认「全部源」)、**书库**(书架与收藏夹)、**视频**(在线源 + 本机)、**下载**。入口放在这里而不是 tab 栏,因为栏位只有四个,第五个会把末位折进「更多」。**尚未在 Mac 上编译验证。** |
| Pixiv 源插件 | `sources/pixiv.js` 是一个**普通 JS 漫画源插件**,用 pixiv 匿名可读的接口:排行(`ranking.php?format=json`,日/周/月/新人/原创五档)、搜索(`/ajax/search/artworks`)、作品详情(`/ajax/illust/{id}`)、图片列表(`/ajax/illust/{id}/pages`)。**不碰需要 OAuth 的 `app-api`**——插件不该持有客户端凭据,所以收藏/关注这类要登录的功能没有做。两条实测教训写在注释里:手机 UA 下 `ranking.php` **即使带 `Accept: application/json` 也只回 HTML**,必须用桌面 UA;`i.pximg.net` 不带 `Referer: https://www.pixiv.net/` 一律 403,所以 `onImageLoad` 必带该头。已在桌面端用真实站点验证:搜索 60 条、详情、18 页图片 164ms、五个榜单 250 条、标签点击可搜。2026-11-01 又经 **Core 的 JS 引擎 + 真实站点**跑过一次(`go run ./cmd/pixivprobe plugins/pixiv.js`:60 条、约 0.3–0.8 秒),证明这条路不是只有桌面客户端能走。 |
| 视觉 | 按参考 App 的观感做了一套共享面:`DesignSystem`(渐变画布、`.glassCard()` 玻璃卡片、`Pill` 胶囊按钮、`SectionHeader` 带箭头、`PosterTile` 带「看到 mm:ss」与进度条、`StatValue` 大数字),并换成**悬浮胶囊 tab 栏 + 独立圆形搜索按钮**(标准 `TabView` 画不出这个形状)。卡片圆角与强调色取自已选主题,所以自定义主题会同时改变这套观感。**尚未在 Mac 上编译验证。** |
| 多账号（环境） | `ProfileStore`:每个环境有自己的 `sources.json`、`cookies.json`、`shelf.json`、`searches.json`、`Magpie/`、`Downloads/`、`Media/`,目录是 `Profiles/<id>`;主题保持全局(外观不是账号)。切换环境会**重建 Core**——因为 Core 就是按该环境的源记录与 Cookie 建起来的,不重建就只是换皮。AI 授权在 Keychain 里按环境分服务名,首个环境沿用原服务名,避免升级后静默掉登录。从旧版升级时根目录的旧文件会搬进「默认环境」。入口:「我的」顶部环境条 +「设置 → 环境」,**尚未在 Mac 上编译验证**。 |
| 观看历史 | 看视频和读漫画写进同一份历史,日历、热力图与当天统计都算上;视频行不伪装成漫画(不给可点的详情路由),片长未知时百分比留空而不是编一个。同一集再看一次只是把它挪到最前。 | 单测(编译待验证) |
| 源批量更新 | 「漫画源」菜单里一次更新所有**有网址来源**的源,一个弹窗报三种结果:更新了(名字 + 旧版→新版)、已是最新、失败(带原因)。从粘贴文本安装的源没有可更新之处,直接跳过而不是记成失败——那是安装方式的事实,不是源的错。 | 单测(总结文案),实际拉取待验证 |
| 媒体服务器 | Jellyfin / Emby:填地址、账号、密码一次完成连接,令牌进钥匙串(按环境分开),服务器记录本身不进令牌。能列媒体库、列影片(时长/年份/简介/海报/已看进度)、按需播放,看过的照旧写进同一份历史。自签证书**只对局域网地址**放行,公网地址不走例外。Plex 在**原生**路径上用的是另一套接口(XML + `X-Plex-Token`),原生客户端不做,明确报错而不是发一个坏请求。
**但这条路线并非关闭**:Core 的视频源接口(`search.load` / `video.loadInfo` / `loadPlay`,可带任意请求头)足以把 Plex 写成**一个视频源**,不需要原生代码——
之前把它记成「另一套接口所以做不了」是同一个误判(把接口层当成能力层)。没有 Plex 服务器可测,所以没有写。**尚未对真实服务器实测**。 | 11 个单测(假传输),真实服务器待验证 |
| 统一媒体库 | 资源库 → 媒体库:本机文件与所有服务器影片合成一份列表,可按片名**和剧名**搜索,有「继续观看」区,按来源分组(本机排在前,因为断网也能看)。某台服务器连不上只影响它自己那组,不会遮住别人。 | 5 个单测(合并/搜索/续看/分组) |
| 播放体验 | 倍速(0.5–2×,按引擎实际上限)、**字幕轨菜单**(含「关闭字幕」,标签用语言名而不是六个「字幕」)、**画中画**(原生通路)、以及**记忆位置**:同一环境看过的会从上次位置继续,「已看完」和「才看 2 秒」都不会被当成位置。服务器自己的进度与本地进度取更靠后的那个,免得手机上看过的被服务器旧位置倒回去。画中画只对引擎给出 `AVPlayer` 的原生通路显示按钮,软件解码通路的 PiP 尚未接。 | 1 个单测(续播判断),PiP 需真机 |
| 阅读日历 | 「我的」→ 阅读日历:按月网格,每天按记录条数着色,点开看当天读了/看了什么(漫画行可进详情,视频行显示进度)。显示连续天数、总记录数、有记录的天数;跨月翻页;「今天」一键回到当月。**没有追剧提醒**:漫画源只报已存在章节、不给播出日期,媒体服务器只报它已持有的剧集,凭空造一个「即将播出」是不可接受的,提醒留到有元数据源(G9)之后。 | 5 个单测(网格对齐/按日取/计数/连续) |
| Bangumi | 追番的账号侧:粘贴个人令牌(存钥匙串,按环境分服务名),看在看/想看/看过/搁置/抛弃五档收藏,改状态与 0–10 评分,按话标记看过,按关键词搜动画,以及**每日放送**(公开数据,不登录也能看)。和 TMDB 的分工:一边知道欧美剧的播出时间,一边有中文标题与话数表,两者在追剧提醒里合并成一份计划。令牌用 `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`;不做 OAuth,因为 client secret 放进 App 包就不是秘密。**已编译并跑过单测**;尚未在真机上连过真实账号。详见 [BANGUMI](BANGUMI.md)。 | 18 个单测(假传输) |
| 元数据(TMDB) | 设置里填 TMDB key 或 v4 令牌(存钥匙串,按环境分开),保存时**当场验证**并告诉你能不能查到剧集;媒体库加载服务器时会用剧名去对剧集(每次最多 6 个、已缓存的不重复请求),日历据此显示「即将播出」并注明日期来自 TMDB。v3 key 走查询参数、v4 令牌走 Authorization 头,自动判断不用问你。日期按 UTC 解析,免得跨时区把晚间播出挪一天。**需要你的 TMDB key 才能实测**,没有 key 时一切照常、只是没有「即将播出」。 | 9 个单测(假传输) |
| 弹幕与跳过片头 | 弹幕读**本地文件**(B 站 XML / DanDanPlay JSON),不需要任何账号;播放器里可开关、可加载、可清除,只画最近 4 秒并限制条数(整份列表每帧过滤是掉帧的老路)。片头**不做自动识别**:每部剧的片头长度不同,猜错会切掉第一句台词;改为「把当前位置标为片头起点」记一次(默认 90 秒),之后同剧靠「跳过片头」按钮,标记按剧存、能持久化。在线弹幕源需要第三方账号,未接。 | 7 个单测(解析/时间窗/容错/标记/持久化) |
| 本地漫画 | 资源库 → 本地漫画:导入图片文件夹或 `.cbz`/`.zip`,页面按**自然顺序**排(1,2,10 而不是 1,10,2),阅读器横滑翻页并记住停在第几页;删除会连同文件一起删。压缩包自己解:`ZipReader` 读中央目录,只支持漫画会用的 stored 与 deflate,`__MACOSX`、隐藏文件、非图片一律不当页。故意不放进「漫画源」——本地漫画没有脚本、没有网络、也没有能和源对齐的 id。 | 7 个单测(两种压缩方式/过滤/排序/导入/删除) |
| 标签翻译 | 内置约 70 个常见英文标签的中文对照(本地表,不联网),大小写/空格/下划线自动归一;**没有对照的标签原样显示**——翻译错比不翻更糟,那是关于内容的断言。用户可自己改,改了会覆盖内置表并持久化。点击标签仍然把**源自己的写法**发回去,翻译只对读者可见。**评分没做**:Core 完全没有评分能力(`mobile` 与 `comic/js` 都没有),这不是客户端能补的,要先在 Core 加绑定并给两端重新 pin。 | 4 个单测 |
| 自检页 | 设置 → 自检:版本/Core/系统/设备、环境(名称·个数·目录名)、源(总数·启用漫画·启用视频·恢复失败)、账号与凭据(**只报有没有,不报内容**)、内容计数、能力(画中画、后台音频声明、网络策略),一键复制成纯文本。目的:真机验证不再需要「装上截图给我看」,而是贴一段可核对的事实。报告里没有令牌、Cookie 或密码。 | 3 个单测(格式/失败计数/不含秘密) |
| 进度回写 | 媒体服务器播完(关闭播放器)时把位置写回服务器 `/Users/{id}/Items/{item}/UserData`,单位是 100ns ticks;本地历史照旧保留。理由:服务器才是用户**其它设备**读的地方,只存在手机上的位置会让别处的「继续观看」变错。写回失败不打断观看,但会如实返回错误。 | 3 个单测(ticks/缺 userID/被拒) |
| 首页卡片 | 新增三张卡:**继续观看**(看到一半的视频,带进度条)、**即将播出**(有 TMDB 日期时)、**本地漫画**;旧版保存的排序不会丢——新模板会自动追加,用户之前**隐藏**过的卡片不会被重新打开。同时修了一个 G4 引入的真 bug:首页「继续阅读」和书架「继续阅读」会把视频条目塞进漫画路由,点开是一个不存在的漫画;现在按 `isVideo` 过滤。 | 7 个单测(含迁移与隐藏保持) |
| 大库分页 | 服务器列影片改为**分页**(每页 200、上限 600),按 `TotalRecordCount` 判断是否还有；服务器谎报总数时遇到短页就停，不会死循环。HTTP 请求加 30 秒超时——一台不响应的 NAS 应该失败而不是让界面一直转圈。 | 2 个单测(两页走完/短页即止) |
| 进度换算统一 | 100ns ticks 换算、0–1 比例、0–100 百分比、「可续播」判断、时间格式,原先分散在 `MediaItem`、`ShelfHistory`、`VideoLibraryStore` 和三处 `clock` 里,各算各的;现在只有 `PlaybackProgress` 一份,表驱动单测覆盖夹紧、未知时长、NaN/∞、四舍五入与时间格式。附带一个更严的决定:**时长未知就不算可续播**——分不清「快看完」和「刚开始」。 | 表驱动单测 + 续播规则断言 |
| 压缩包校验 | `ZipReader` 现在核对 CRC32(标准表,已用「123456789 → 0xCBF43926」钉住);校验不过就明确报「文件可能损坏」,而不是解出半张花屏图——那种图看起来像阅读器 bug,实际是文件坏了。流式写出的包 CRC 为 0 时跳过校验(那是格式允许的情形,不是错误)。 | 2 个新单测(向量/损坏检测含改载荷) |
| 导入不卡界面 | 解压与写盘移到 `Task.detached`,主线程只做列表更新;大包导入时显示「正在导入…」而不是冻住,并且把「导入中」与结果提示分开——把正在进行的提示塞进 alert、随后又改写它,是用户读不到的进度。 | 4 个导入单测改为 async |
| 坏文件不吞数据 | 任何 store 读不出自己的文件时,先把该文件**复制**为 `名字.unreadable-时间戳.json` 再继续。原因很具体:失败的不是读取,而是**随后的一次保存**——记录一页、导入一本、搜一次,就会把内存里的空列表写回磁盘,用户看到的是「升级后我的书架没了」,而数据是被保存毁掉而不是被解码毁掉。原文件保持原位,便于日后修复或新版本读取。覆盖:书架、本机视频、搜索历史、下载清单、本地漫画、媒体服务器、片头标记、标签表、元数据缓存。 | 4 个单测(含「文件本来就不存在」不算损坏) |
| 迁移的崩溃窗口 | 旧数据搬到 `Profiles/<id>` 与写 `profiles.json` 之间若崩溃,下次启动会**新建一个新 id 的默认环境**,被搬走的数据就成了孤儿目录——效果等于删除。现在:先写清单再搬文件;若发现 `Profiles/` 下有目录却没有清单,**接管该目录**(取最新修改的),再把根目录残留的文件补进去。 | 3 个升级路径端到端单测(全量迁移/不重复不偷数据/接管中断迁移) |
| 验证工具修正 | `seed-simulator.sh` 原来写 `<support>/plugins.json`(升级前的位置);设备一旦有过 `profiles.json`,迁移不再执行,seed 就写进没人读的地方,验证机于是看到「没有源」。现在会先解析出真正在用的环境目录(优先含 `plugins.json` 的那个,否则最新),再写入。 | `sh -n` 语法检查;实际写入需在模拟器上跑 |
| 文档与代码一致性核对 | 按 STATUS 的 15 条「已实现」主张逐条找出对应符号(全部存在),再核对 13 个功能是否**有界面入口**(全部可达);界面用例仍为 16 个;公开类型里没有「App 与测试都不用」的死接口(29 个命中都是 kit 内部数据模型)。这一轮没有发现需要改代码的地方——结论本身是证据。 | 只读核对,无改动 |
| 评分显示 | 详情页显示源给出的评分(五星 + 数字)、喜欢人数与「已喜欢」标记;**没有评分就不显示**,不画五颗空星——那等于宣称「零分」。评分可写成数字或字符串(抓页面的源会给字符串),整数也照读。**修正上一轮的说法**:评分此前被记为「受 Core 限制」,实际 Core 从一开始就在详情里发 `stars`/`likesCount`/`isLiked`,是客户端模型没接这几个字段——不需要改 Core,也不需要新版本。 | 3 个单测(数字/字符串/缺省与整数) |
| Plex 视频源 | `plugins/plex.js`:把 Plex 当**视频源**实现(不是第二套原生接口)。XML 解析、`X-Plex-Token` 走查询参数、毫秒转秒、只保留电影与剧集库(音乐/相册库列出来是放不了的东西)、`<Part>` 取第一个文件作为可播地址。**没有真实 Plex 服务器**,所以只验证了解析:`node plugins/plex.test.mjs` 5 项全过(含「属性里的正则标点要按字面读」)。请求部分未验证。 | 5 项 Node 固件检查 |
| 追剧提醒 | 有 TMDB 播出日期时,可在设置里开启系统通知:**播出当天上午 9 点**提醒(不用播出时间——那是服务器所在时区的时间,本机并不知道,猜一个时点不如给一个日期);同一部剧只排一条、按最近优先、上限 20 条(iOS 有 pending 上限);已过去的日期不排(只能立刻触发,看起来像 bug);重新同步会先取消多余的再排,标识带 `airing:` 前缀,取消不会碰到别人的通知。规划逻辑在 kit 里,有 7 个单测。 | 7 个单测;权限与真实触发需真机 |
| 画中画(两条通路) | 原生通路用 `AVPlayer`,软件解码通路用 `softwarePiPSource` 的 `AVSampleBufferDisplayLayer` + `AVPictureInPictureSampleBufferPlaybackDelegate`(播放/暂停、时间轴、跳转四项)。时间轴与暂停状态**在主线程刷新成快照**,委托同步读取——用 `assumeIsolated` 一旦线程假设错了就是崩溃,而这里只需要一个短暂过期的快照。 | 需真机;软件通路要用软解源(VP9/AV1)才走得到 |
| 字幕叠层与播放时钟 | 用引擎的 `$subtitleCues` 画文字字幕(纯文本与富文本都经 `cue.text` 合并),位图字幕**不画**——软件通路本来就会把它合成进帧里,画坏不如不画。同时修了一个真实缺陷:叠层原先读 `position`,而 `position` 只在引擎状态变化时更新,所以**弹幕和字幕在播放中不会前进**;现在跟随 `clock.$sourceTime`(约 10 Hz),关闭播放器时的位置也改读 `$currentTime`,不再停在最后一次状态变化处。 | 需真机/软解源验证 |
| 引擎接口签名自查 | 把 App 用到的 **28 个 AetherEngine 符号**逐个对到 7.53.1 源码:初始化、`load` 签名、`LoadOptions(httpHeaders:)` 的公开 init、播放/暂停/跳转、`setRate`/`maxSupportedRate`、`state` 的 `case error(String)`、字幕轨与 `subtitleCues`、`currentAVPlayer`、`softwarePiPSource` 的 `layer`/`timeRange`/`setPlaying`/`skip`、`SubtitleCue.startTime`/`text`、`AetherPlayerSurface(engine:)`。**全部命中**。这一步替代不了编译(Apple SDK 签名与 SwiftUI 约束仍需编译器),但能挡掉「把引擎 API 记错」这一类错误。 | 28 项核对,无缺失 |

## 下载离线索引隔离(2026-11-03,提交 `2d9f555`)

离线图片索引原来只用「源 + 章节 + 图片地址」,没有漫画 ID:同一源的两部漫画若复用章节 ID 与图片地址,阅读器会拿到另一部漫画的字节,删除一章也可能清掉另一部的索引。现在键包含源、漫画、章节与地址,写入/读取/删除/重开四条路径一致;只有阅读页会归档,封面/缩略图请求不再命中页面字节。

Mac 单测按提交记录:`2317ea7`(仅新增复现用例)2 例全失败、共 6 条断言;`380bf89`(索引修复)剩 1 例失败,完整套件 397 PASS / 1 FAIL;`2d9f555`(缩略图隔离)目标用例 2/2、完整套件 **398 / 398 PASS,0 FAIL,0 SKIP**。环境为 macOS 27.0.1 arm64、Swift 6.4.2、Xcode 27.2,复用同一 Core pin 产物;日志在 `/tmp/nk-dl-isolation-evidence/`。该结果只覆盖临时目录与 manifest 的单元回归,不代表真机、下载界面或网络闭环。

清单也不再单方面宣称“已下载”:文件可能被系统清理、被备份跳过,或在 App 外被删掉。`9f15203` 在载入清单后检查每章目录是否存在,缺失的记录直接丢弃——存储界面与阅读器都不会再把它当成本地内容,用户可以重新下载。9 例写盘用例连续 4 轮通过,完整套件 **407 / 407 PASS**,日志在 `/tmp/nk-dl-missing-evidence/`。

半成品目录也会被清理:写盘中途进程被杀或断电时,会留下没有清单记录的目录,存储界面只列章节,这份空间原本永远收不回来。`afe1259` 在 `init` 载入清单后扫一遍未被引用的章节目录并删除,同时清掉因此变空的漫画目录;用例先完成一章再人为造一个半成品目录,验证只删后者。8 例写盘用例连续 4 轮通过,完整套件 **406 / 406 PASS**,日志在 `/tmp/nk-dl-sweep-evidence/`。

已下载章节不会重下:`download()` 原来用内存里的 `progress` 判断“已完成”,重开 App 后该状态为空,已下载章节会被整章重新拉取。现在先看磁盘清单里的章节记录,再保留失败重试判定;`b3860ea` 的用例用锁计数器验证同会话与新 store 两种情况都不产生新请求,写盘 7 例连续 4 轮通过,完整套件 **405 / 405 PASS**,日志在 `/tmp/nk-dl-skip-evidence/`。

删除与清空存储的并发入口在 2026-11-03 补上:`remove` 原来在章节尚无记录时提前返回(下载中删除会漏掉作废),`removeAll` 原来只遍历已完成章节(在飞与排队的下载会在清空后写回)。修法是让作废发生在查找记录之前,并让清空覆盖队列与在飞任务。`0049da3` 的回归用例在 Mac 上 4 条断言失败,正好暴露了第一处;`920b94a` 修正后写盘 6 例连续 4 轮全通过,完整套件 **404 / 404 PASS**,隔离仍 2/2,日志在 `/tmp/nk-dl-clear-evidence/`。

后续重试与可测性改造在 `7550c12` 上验收:失败或删除后可重新下载,写盘路径改为注入 fetch 闭包,不再要求 Core 连接;新增 4 条写盘/重试用例全部通过,隔离用例仍 2/2,完整套件 **402 / 402 PASS**。日志在 `/tmp/nk-dl-retry-evidence/`。两次执行分别对应不同提交,数字不合并求解。

## 原生导航与统一内容表面(Mac 已跑,视觉矩阵后置)

`5f15769` 在 Mac 上 App 与 UITests 构建通过,完整正式 UI 套件 **26 条 / PASS 26 / FAIL 0 / SKIP 0**,日志 `/tmp/nk-native-5f15769-evidence/full-ui.log`。这是一轮完整执行,覆盖原生标签、编辑状态跨栏目保持、资源库模块入口与既有主题/发现页用例。

后续入口与阅读修复在 `81eb017` 上单独验证:构建通过,`testLibraryModuleLinksOpenTheirPages`、`testReaderDrawsTheChaptersPage` 及临时交互探针(本地/在线阅读器返回、资源库与发现页视频入口)通过,日志在 `/tmp/nk-reader-81eb017-evidence/`。该提交的完整套件未跑,不能把三个定向用例当成整套通过。

按用户「底层优先」要求,后续明暗窄宽屏与三列截图矩阵、动态字体与减少动态效果人工验收已后置,未完成;已知的大字体截断问题仍未修复。较早的完整回归 24/24 属于 `5d9a5a1`,与上述两轮分开记录。

用户反馈 iOS 界面割裂后,根导航已从条件切换页面的手绘底栏改成系统 `TabView`,搜索使用系统 search role;栏目由 TabView 管理生命周期,不再由根视图切换时主动丢弃。发现、我的、资源库、设置及搜索使用统一页面底色,内容卡片使用主题 surface 或系统分组表面,移除卡片的重复内边距和手绘底栏的固定 76 pt 留白;工具栏编辑按钮恢复系统样式。主题 background/surface 现在参与这批页面绘制。另修复非编辑/减少动态效果时卡片仍倾斜,以及取消的旧封面任务可能回写。资源库的漫画源/视频源卡片接入实际页面;服务器摘要按已配置记录显示,不再始终声称没有连接或功能尚未接入。

现有 UI 用例改为查找原生标签栏,新增「发现页编辑→设置→发现页仍在编辑」和资源库两种模块入口导航用例。这两轮已在 Mac 上构建并执行(见本节开头);包含这批改动的新版本尚未发布。真实 iPhone 上的 iOS 27 观感与 Liquid Glass 效果仍未验证,系统 API 的存在不等同真机观感。

## Mac 上已经跑过的检查

**最新完整回归(2026-11-02,提交 `5d9a5a1dfd5ce0e9d58fead6371d5cc4b3f842c4`,Orca Worker / Mac 模拟器)**:在专用 iPhone 17 Pro 上卸载旧 App、重新安装、生成独立 profile 并补种;启动前 Themes 目录为空。完整 UI 套件 **24 条 / PASS 24 / FAIL 0 / SKIP 0**,日志 `/tmp/nk-ui-full-5d9a5a1.log`。无效主题保留选择、HTTPS 安装/选中/重启、HTTP 拒绝三个用例全部通过,三列几何用例也通过。无效主题用例已自行安装基线,不依赖前一次运行。临时服务与主题已清理;新增 CA 有效 1 天,约 2026-11-03 失效,仍在专用模拟器信任库中。这是一轮完整执行,不叠加早期单项结果;不证明真机、后台、真实账号或三列完整视觉。

**被跳过的视频 UI 用例已单独跑通(2026-11-03,`95818c5` 构建)**:根因确认是种子缺视频源。把仓内 `UITests/Fixtures/video_probe.js` 一起灌进种子后(`--replace`,落盘 `plugins.json` 131,692 字节、5 条源,`video_probe` 的 `type = video-js`,`check-seed.sh` 报 `callback_probe matches … 5 source(s) seeded`),`testVideoPlaysTheSourcesClip` **passed(29.600 秒)**、`Executed 1 test, with 0 failures`,路径是 `在线源 → video.source → Video Probe → 搜索 probe → Probe Clip → Episode 1 → 播放页`。这是**定向单独复确认**,不是整包重跑:完整套件的 23 通过 / 4 跳过仍以 `95818c5` 那轮为准,下一轮整包应变为 24 通过 / 3 跳过。一处如实交代:种子复用了 2026-11-01 用 `seedgen` 生成的那份(逐项核过 body 与仓内 fixture 逐字一致),不是现场重新生成。

**主题链接夹具已入库并有定向执行证据**:Orca Worker 在 `17ba4c5` 的 Mac 工作树上运行 `sh scripts/theme-fixture.sh 0A67B65C-9EB9-4504-B7C6-7A8EC74DA1A0`,HTTPS 安装/选中/重启、坏 JSON 保留选择、明文 HTTP 拒绝 **3/3 通过、0 跳过**;日志 `/tmp/nk-theme-fixture-run3.log`,App 仍为 0.3.1 构建。脚本提供 18791 HTTPS / 18792 HTTP 两个 loopback 服务,运行时生成有效 30 天的 CA 与叶子证书,只向指定模拟器添加信任,不改宿主钥匙串,不调用 `simctl keychain reset`;证书与私钥均不入库。该次请求日志记录有效/无效 JSON 请求,明文端口为 0 次。此结果与 27 例完整套件分开记录,不拼成一次 27/27。

`scripts/make-seed.py`(`65f086c`)从仓内漫画/视频夹具重建 body、类型与 SHA-256,可携带旧种子的真实站点记录。Worker 用新生成的五源种子定向执行视频用例 **passed 28.276 秒**,日志 `/tmp/nk-video-rebuilt-seed.log`。本地审阅另外修正主题脚本的失败退出路径(原 `set -e` 会跳过指纹回执)和生成器对 CRLF 的字节保留;本地检查包含真实 TLS 预检与退出码 0/42 两条路径,其中模拟器与 Xcode 命令为替身,不作为 iOS UI 执行证据。

**发布后完整 UI 套件(2026-11-03,`95818c5`)**:干净起点(卸载重装 + 播种,img=0、`failures.json`=0、`manifest.json`=0、`plugins.json` 129,992 字节,`check-seed.sh` 报 `callback_probe matches`、4 源、18731 端口空闲)上执行 **27 例:23 通过 / 4 跳过 / 0 失败**,617 秒,日志 `/tmp/nk-95818c5-ui-fullsuite.log`。分组:`NekularityUITests` 23 例(22 通过 / 1 跳过)、`ZZThemeLinkTests` 3 例(3 跳过)、`ZZThreeColumnTests` 1 例(通过)——完整套件是 23+3+1,不是 23。

4 条跳过都是前置条件,不是产品失败:视频那条是种子里 4 个源没有视频源(`the 视频 tab has no source picker`);主题链接 3 条需要仓库外的 HTTPS/HTTP 夹具与已装入模拟器信任库的测试 CA(`theme fixture is not listening on 127.0.0.1:[18791, 18792]`),而 UNVERIFIED 早已写明缺夹具或证书过期不能记为通过——所以按跳过记录,没有伪造夹具凑数。

同轮采集 **明暗 × 窄宽 8 张截图**(iPhone 17 Pro 1206×2622、iPad Pro 13-inch 竖屏 1032×1376 pt),`/tmp/nk-shots-95818c5/`;iPad 暗色设置页底部可见「版本 0.3.1」,与发布一致。两点如实记录:iPadOS 把五个入口渲染成顶部栏普通 Button,临时用例最初用 `tabBars` 在 iPad 上失败,改为先查 `tabBars` 再按 label 兜底后两轮通过;两台设备内容不完全一致——iPhone 沿用了套件跑完的现场(有阅读记录),iPad 的旧种子被 `--replace` 统一后阅读进度被清,故其发现页为空态模块。

**`0.3.1` build `13` 已发布并核对(2026-11-03)**:失败的下载现在能跨启动**存活**——请求与原因写进 `failures.json`,重启后仍列在「没有下载完成」里,用 App 装好的 `fallbackFetch` 重试,失败行还可以单独 swipe 删除(不必「全部删除」连库一起删);`CoreError.readable` 也改成幂等,持久化后再过一遍不会变成「源返回错误:源返回错误:」。tag `v0.3.1` 指向 `a6e4ad6`,受测代码是 `76dba85` 加那条前缀修复。发布 CI `41539849288` 通过,日志为 `Test run with 415 tests in 76 suites passed`。下载 Release 资源 HTTP 200、**29,416,931 字节**,SHA-256 `af5cc588c970e796f971b21777724362c9beac53fcd91f66e805fddafa162ecf`;解包后 App 与 Widget 均为 `0.3.1`/`13`,最低系统 26.0,应用二进制含 pin `8e14aade75f5`。AltStore 的 `update-source` 工作流 `41543336622` 成功,`apps.json` 稳定轨道与扁平首版均为 `0.3.1`/`13`、大小 29,416,931 字节、下载与图标指向 `v0.3.1`;图标 HTTP 200(443,517 字节),IPA 分段请求返回 206 并收到 1024 字节。包未签名,签名安装与真机仍不在核对范围。

**`0.3.0` build `12` 已发布并核对(2026-11-03)**:这一版让下载失败不再消失——失败的章节留在下载界面「没有下载完成」分组,可以原地重试,详情页对应章节行也有警告标记——并带上网络错误归因(不再把断网说成源返回错误)、主题对比度断言与 Core `8e14aad`(异步 rejection 保留错误名)。tag `v0.3.0` 指向 `df11f01`,相对受测代码 `6037f6a` 只多版本元数据、Core pin 与文档。发布 CI `41525488814` 通过,日志里是 `Test run with 411 tests in 76 suites passed`。下载 Release 资源得到 HTTP 200、**29,393,130 字节**,SHA-256 `8100da3764346d13f53321562e26b53336273c52e9b50d171a0d6a2395284e36`;解包后 `Nekularity.app` 与 `NekularityWidgets.appex` 均为 `0.3.0`/`12`,最低系统版本 26.0,应用二进制里能找到 pin `8e14aade75f563a95f50d4ec80be27bae0d02c63`。AltStore 的 `update-source` 工作流 `41535603457` 成功,`apps.json` 的稳定轨道与扁平首个版本均为 `0.3.0`/`12`、大小 29,393,130 字节、下载与图标都指向 `v0.3.0`;图标 HTTP 200(443,517 字节),IPA 分段请求返回 206 并收到 1024 字节。这次是手动 `workflow_dispatch` 触发的:定时任务按每 15 分钟配置,但 0.2.9 之后两个多小时没有任何定时运行,发版时不要指望 cron 自己到点。包未签名,签名安装与真机行为仍不在核对范围。

**`0.2.9` build `11` 已发布并核对(2026-11-03)**:这一版带上「清单与实际文件一致」的修复(`9f15203`):目录已消失的章节不再算已下载,下载界面与阅读器都以磁盘为准。tag `v0.2.9` 指向 `3bad666`;该提交只比受测代码多版本元数据与文档。发布 CI `41501079841` 通过。下载 Release 资源得到 HTTP 200、**29,370,355 字节**,SHA-256 `2076378ee48080f5922143b9a07fb9b62edab338587aea4439c5af6b028a5952`;解包后 `Nekularity.app` 与 `NekularityWidgets.appex` 均为 `0.2.9`/`11`,最低系统版本 26.0。AltStore 的 `update-source` 工作流 `41506082352` 成功,`apps.json` 的稳定轨道与扁平首个版本均为 `0.2.9`/`11`、大小 29,370,355 字节、下载与图标均指向 `v0.2.9`;图标 HTTP 200(443,517 字节),IPA 分段请求返回 206 并收到 1024 字节。包未签名,签名安装与真机行为仍不在核对范围。

**`0.2.8` build `10` 已发布并核对(2026-11-03)**:这一版包含下载库四项修复(离线索引按漫画/源隔离、失败与删除后可重试、删除与清空存储的并发入口、已完成章节不重下、半成品目录清理)。tag `v0.2.8` 指向 `fbab48a`;该提交的 App、kit、UITests、Widgets、Live、`Package.swift` 与 Core pin(`214e7782`)与受测代码一致,差异只是版本元数据与文档。发布 CI `41490389867` 通过(构建 pinned Core、kit 单测、真机构建、UI 测试编译、打包、上传与发布全部成功)。下载 Release 资源得到 HTTP 200、**29,370,482 字节**,SHA-256 `392c5d7a9d8e73f060ee04b8f4c7ca35966188b16d299a4122aeea00afe80159`;解包后 `Nekularity.app` 与 `NekularityWidgets.appex` 均为 `0.2.8`/`10`,最低系统版本 26.0。AltStore 的 `update-source` 工作流 `41495855498` 成功,`apps.json` 的稳定轨道与扁平首个版本均为 `0.2.8`/`10`、大小 29,370,482 字节、下载地址指向 `v0.2.8`、图标指向 `v0.2.8`;图标 HTTP 200(443,517 字节),IPA 分段请求跟随重定向后返回 206 并收到 1024 字节。该包未签名,签名安装与真机行为不在这次核对范围。

**`0.2.7` build `9` 已发布并核对(2026-11-02)**:App/Widget 版本为 `0.2.7`/`9`,tag `v0.2.7` 指向 `90b98b07d3a07df1630379263bd976924bf70260`;该提交的 App、kit、UITests、Widgets、Live、Package.swift 与 Core pin 和受测 `5d9a5a1` 相同,差异只是版本元数据与文档。发布 CI `41465697611` 通过。下载 Release 资源得到 HTTP 200、**29,368,112 字节**,SHA-256 `182f62cf2aea32d6b8183effd0f0f31aede1deeab4270ce02d22b6a12bc8b7f3`;解包后 `Nekularity.app` 为 `0.2.7`/`9`、`NekularityWidgets.appex` 为 `0.2.7`/`9`,最低系统版本 26.0。App 可执行文件含主题链接的 HTTPS 拒绝文案,说明本轮主题修复在包内。AltStore 的 `update-source` 工作流 `41471135708` 成功,`apps.json` 的稳定轨道与扁平列表首个版本均为 `0.2.7`/`9`、大小 29,368,112 字节、图标指向 `v0.2.7`;图标 HTTP 200,IPA 分段请求返回 206。该包未签名,签名安装与真机行为不在这次核对范围。

**后续全套执行(2026-11-02,提交 `9f7840f`,Orca Worker / Mac 模拟器,未通过)**:Theme 单测 12/12 PASS,明文重定向拒绝 0.015 秒,日志 `/tmp/nk-theme-9f7840f.log`。UI 回执原报 24 条 / PASS 22 / FAIL 2 / SKIP 0,日志 `/tmp/nk-ui-full-9f7840f.log`;但失败明细只列出 `testHTTPSInvalidThemeShowsErrorAndPreservesSelection` 的两条断言,未列第二个失败方法,因此失败用例数与断言失败数尚需按用例清单核对。已确认该用例依赖别的用例遗留主题,在成功安装用例后单独执行通过;`5d9a5a1` 已让它自行安装并选中基线主题,修正后的 `5d9a5a1` 已在干净容器完整执行 24/24 通过,见本节最新回执。`ZZThreeColumnTests` 1/1 PASS。不能用单独复跑替代全套通过。

**历史完整回归(2026-11-02,提交 `8acbb7841509ffa637a1392d88d439d5f1e9aaa1`,Orca Worker / Mac 模拟器)**:同一专用 iPhone 17 Pro 上测试目标构建与安装成功;完整界面套件 **19 条 / PASS 19 / FAIL 0 / SKIP 0**,日志 `/tmp/nk-ui-full-8acbb78.log`。长按拖动柄进入编排、切换尺寸后终止并重启读回、通过编辑按钮操作与批量更新都已执行通过。此结果不证明拖放排序、真机灵动岛、后台播放或真实账号可用。

**拖放与重启持久化(2026-11-02,Orca Worker / Mac 模拟器,目标提交 `7586982`)**:新增 `testBoardDragOrderSurvivesRelaunch` 并在专用 iPhone 17 Pro 上跑通(`/tmp/nk-drag-final.log`)。首版实现读排序时被**重复标识符**污染——每张卡的标题和箭头都带 `home.card.*`,于是「移动前两名」实际是同一张卡,断言空转通过;改为按首次出现去重后重跑,结果才有意义:拖动前 `history, favorites, …`,拖到第二位后为 `favorites, history, …`,terminate/launch 后仍是 `favorites, history, …`。停机后直接读 App 偏好交叉核对,`homeBlocksV2` 实读为 `['favorites','history',…]`,确认不是只重排了界面;用例末尾已拖回原顺序。**新增拖放用例的首版因比对同一张卡而空转通过**,已去重后重跑;这不意味着此前完整套件中的其他用例无效。

拖放用例已从 Mac 的 Git bundle 导入并核对 2,169 字节与 SHA-256;远端 `validate/discover-drag-7586982` 保留原提交 `33be2af3767a02e438eaacef7405262015652e80`,主线整合为 `9b2b3e621219db4ee9dea3308d85af0a114eb5e7`。作者与 Assisted-by 保留,主线测试文件 blob 与 Mac 已运行版本完全一致。Windows `check-swift.sh` 解析通过,未在 Windows 运行 UI;19/19 是历史记录;最近完整通过的套件为本节开头 `5d9a5a1` 的独立 24/24 执行,不由单项结果拼合。

**三列与主题 HTTPS 界面(2026-11-02,Orca Worker / Mac 模拟器,提交 `5d7022d`)**:iPhone 横屏实测滚动内容宽 **874 pt**,前三张卡临时调成“小”后,去重标题横坐标约 **101、347、590 pt**,落在三个不同列,`testLandscapeBoardHasThreeColumns` 明暗两次通过,结束时已恢复布局与竖屏。**这只证明 3 列确实发生**,截图以旋转方向保存且暗色顶部被导航区域裁切,文字可读性、标题截断与完整视觉仍需重拍。

主题 HTTPS:合法夹具主题写入 `Themes/p1-https-proof.json`,重启后选中状态仍在;无效 JSON 显示“未能读取数据,因为它的格式不正确。”且原主题仍选中。**反例发现一个真实缺陷**:`http://` 主题被实际下载并安装——设置页只判断 `scheme?.hasPrefix("http")`,而 `ThemeStore.install(from:)` 只校验主题内容、不校验协议。已修(提交 `0e40eeb`):`ThemeSource.validate` 要求精确 `https` 且主机非空,校验放在共享安装路径、调用 fetch 之前;设置页只保留链接形状检查并显示具体拒绝文案。新增 kit 单测覆盖 http、大写 HTTP、file、hostless https 与无 scheme,并断言 fetch 从未发生。Orca Worker 随后在 App `a526add` 上单独验证 HTTP 拒绝:弹窗为“主题链接必须是 https 地址”,主题未进入列表,HTTP 服务器收到 0 次请求,Themes 目录无新增文件;日志 `/tmp/nk-p2-http-test.log`。单测首次因捕获并改写 `fetched` 而编译失败,`9005dca` 修正后在 Mac 实跑 8/8 PASS,日志 `/tmp/nk-theme-filter.log`;`6bb7933` 加重定向/404/超限后实跑 12/12 PASS、0 FAIL、0 SKIP,日志 `/tmp/nk-theme-6bb7933.log`。该轮明文重定向用例耗时约 21 秒,`9f7840f` 已改为立即取消并断言小于 5 秒;该提交的 Theme 已在 Mac 实跑 12/12,快速拒绝实测 0.015 秒;全套 UI 未通过及计数差异见本节开头,修正提交 `5d9a5a1` 的完整 24/24 回执已收到,见本节开头。这些单项结果不并入旧的完整 19/19。

**八张真实模拟器截图(2026-11-02,App `0.2.6` / 提交 `7586982`,XCTest 在模拟器内直接捕获)**:iPhone 17 Pro(402 pt 宽)发现页 2 列、iPad Pro 13 英寸(1032 pt 宽)发现页 4 列,各含明/暗两套发现页与设置页。未看到横向溢出、标题截断或控件互相压盖,卡片文字在明暗两种外观下都可读。**3 列宽度(560–899 pt)本轮没有对应设备或分屏场景,未验证。**

**滚到底无遮挡(2026-11-02,Orca Worker / Mac 模拟器,App `211cd64`)**:build-for-testing 与 iPhone/iPad 安装均通过。连续向上滑动直到页尾元素坐标连续两次不变,再对五张截图逐一判读:iPhone 明/暗设置页、iPad 明/暗设置页及 iPhone 暗色发现页。设置页「关于」、版本 `0.2.6` 和 Core 行,发现页最后「视频源」卡片都完整位于胶囊上方。iPhone 设置页 Core 文字底边约 748 pt、胶囊顶部 774 pt(间隔 26 pt);发现页内容底边约 731 pt(间隔 43 pt);iPad 设置页 Core 文字底边约 1264 pt、胶囊顶部 1285 pt(间隔 21 pt)。五张图均未见横向溢出或标题截断,没有需要增加底部边距的证据。截图和日志在 `/tmp/nk-bottom-211cd64/`。iPad TMDB 说明完整可见;iPhone 在最底部时 TMDB 说明已滚到顶部导航栏之后,不能据底部截图声称它同时完整可见。该回执仅覆盖这些模拟器和场景,不等于全部布局或真机验证。

历史回归:`c259f3f` 因缺种子大量跳过,固定 UUID 并补齐漫画/视频夹具后 `2cf44e4` 为 18/19、0 跳过,唯一失败长按进入;`0f2a5a2` 仍失败,`8acbb78` 在未编排时移除 `.draggable` 后完整通过。不同提交的结果没有拼接成一次全套通过。

**`v0.2.6` 的发布构建(2026-11-02,提交 `75869826c890a9e1e0208aa2b05b576f11394623`,run `41431641042`)**:macOS runner 上 **全部步骤成功**(构建固定 pin 的 Core、树检查、kit 单测、生成工程、未签名真机构建、编译界面测试、打包 IPA、发布资产)。Release `v0.2.6` 已发布,`Nekularity.ipa` **29,361,985 字节**,`curl -L` 下载 **HTTP 200** 且字节数一致,SHA-256 `c25a35851a8310a593bcac89f3d2205c7c8cdc6a2b349ad484dc70498c729ae2`。下载后解包核对:`Nekularity.app` 为 **`0.2.6`(build 8)**、`com.laincat.nekularity`、最低 iOS 26.0,`PlugIns/NekularityWidgets.appex` 同为 **`0.2.6`(build 8)**,AppIcon 图标文件在包内。此构建的界面证据来自同源码的 `8acbb78` 完整套件(19/19);发布构建本身只做了编译与打包,没有在模拟器上再跑界面测试。AltStore 源 `apps.json` 已同步到 **`0.2.6`(build 8)**(大小、下载地址、`minOSVersion` 26.0 与 `releaseTag` 均一致,图标指向 `v0.2.6` 的 AppIcon),订阅入口 `releases/download/latest/apps.json` 回 **HTTP 200** 且版本相同。

**`v0.2.5` 的发布构建(2026-11-02,提交 `7a00580`,run 83)**:GitHub Actions 的 macOS runner 上 **12 个步骤全绿**——构建固定 pin 的 Core、树检查、kit 单测、生成工程、未签名真机构建、编译界面测试、打包 IPA、发布 Release 资产。产物 `Nekularity.ipa` **29,359,908 字节**,`curl -L` 拉取 **HTTP 200**,字节数与 Release 资产一致;AltStore 源的 `apps.json` 已更新到 **`0.2.5`(build 7)**,订阅入口 `releases/download/latest/apps.json` 也回 **HTTP 200** 且版本一致。

这一轮只证明「能编译、能打包、能下载、源指对了版本」:**界面用例在这条流水线里只被编译,没有被执行**(`xcodebuild build-for-testing`),所以批量更新、发现页编排、Liquid Glass、灵动岛这几项仍然只有旧的或没有的设备证据。不要把它读成「测试全过」。

**历史一轮(2026-11-01,树 `67c501a`,Core pin `d81445f`)**:`scripts/verify-ios.sh` **EXIT=0**,**13 个 UI 用例全部 PASS(0 FAIL / 0 SKIP)**;`swift test` **229 tests / 43 suites passed**,`check-seed.sh` 确认种子与仓库夹具一致,未签名 App 构建、build-for-testing、安装均通过。这一轮新增**分类页**:同时断言可选项、结果,以及切换取值后**选中态**真的改变;书架用例也改成先断言 `书架` 导航栏存在——两者都是为了让断言不会因为「元素在上一个界面也存在」而误通过。

**无障碍树揪出两个真实缺陷(2026-11-01,树 `9e8f84c`)**:连续几轮 UI 用例失败,最后靠测试在 SKIP/FAIL 时导出的整棵无障碍树定位到客户端问题,而不是测试写法。
- **「搜索」页在 iOS 27 上没有输入框**。树里导航栏只有「范围」「漫画源」两个 picker 与标题,内容区只有「最近搜索」,没有任何可输入的元素——`.searchable` 在这个布局下没有画出输入框,用户无从输入关键词。现在改成页面自带的 `TextField`(`search.field`),提交走 `onSubmit`。
- **回调按钮看得见、按不动**。树里 `setting.callback.run` 存在且未禁用,但点击后忙碌态、对话框、答案都没有出现;根因是 `LabeledContent` 给按钮的命中区域不接收点击。改成普通 `HStack` + `contentShape` 后,按钮保持标识符不变。

这两条都说明:UI 测试失败时要先取树,再判断是客户端还是测试——前几轮我把它们误判成测试写法问题,代价是多跑了三轮。

**模拟器 UI 测试第一次真正跑起来(2026-11-01,树 `177f69e`)**:种子里的四个源都写进了设备(`Callback Probe` 出现在 App 源列表,测试进入了它的设置页),`swift test` **229 tests / 43 suites passed**,iOS 不签名构建与 `xcodebuild build-for-testing` 都通过;UI 用例 **4 PASS / 1 FAIL / 1 SKIP**。通过的是 tab、种子源可见、网页登录 sheet、浏览页;失败的是回调用例,原因是**我的断言写错了**:夹具源的回调会立刻弹出对话框,而弹出 sheet 后底层设置页不在无障碍树里,所以「等忙碌标记」这种断言永远不会成立——它并不表示点击没到达客户端。现在改为「忙碌标记 / 源对话框 / 内联答案」三者任一成立即算到达,三者都没有时自动附上整棵无障碍树。SKIP 的是搜索:`.searchable` 在 iOS 27 上没有以 `searchFields` 出现,正在按占位符与工具栏按钮两种方式找,并在 SKIP 时导出树。

**UI 用例不再依赖外部站点(2026-11-01,树 `6a1df9f`)**:回调那条用例原来按 `wnacg` 的「刷新域名列表」按钮,而 `wnacg` 的 `init` 里会先联网抓域名列表,于是在打不开那个主机的机器上,按钮根本没机会跑,测到的是站点而不是客户端。现在改按自带源 `UITests/Fixtures/callback_probe.js` 的按钮:它没有任何网络,回调先弹自己的对话框再返回字符串,失败就只能是客户端的错。这个源先在桌面的 Core 上验证过合法(`cbprobe` 得到 `ANSWER callback_probe.run 0s "ran"`),同一轮也把搜索框定位从「必须是 `searchFields`」改成按占位符 `关键词` 找。另一个真实卡点是种子:`verify-ios.sh` 调种子脚本时不传 `--replace`,设备上已有旧种子时会打印「已有存储被保留」并以 rc=2 退出,测试却会在**旧种子**上继续跑——现在加 `NK_UI_SEED_REPLACE=1` 才允许覆盖,默认仍保守。

`check-swift.py` 也补了一条本地规则:把 `NSPredicate` 存进变量再传给 `matching` 会被报出来。这正是让 Mac 上 `build-for-testing` 失败的那种写法(`NSPredicate` 不是 `Sendable`,Swift 6 下跨隔离传参是数据竞争诊断),而 UI 测试是唯一不会被 Windows 类型检查覆盖的文件。规则做过反向验证:临时改回存变量的写法,它会准确报出 `stores NSPredicate probe and passes it to matching`。还有两条针对界面测试的规则:一条要求测试里的标识符真的在 `App`/`Sources` 里存在(写错标识符不会编译失败,只会让用例等到超时后报「找不到元素」,看起来像客户端坏了),另一条拒绝 XCTest 会拒绝的 `label.length` 谓词。——这同样只在 Mac 上才会暴露,成因是把 `
` 写成了真正的换行;反向验证时会报出 `line 186 ends inside a string literal`。

这一轮之前,同一个验证器在树 `1d41c57` 上 **FAIL**:`swift test` 在 `WebviewLoginCookieTests.swift:17` 强制解包 `nil` 后 signal 5 崩溃,整个测试 bundle 随之退出,App 构建根本没跑到。原因是夹具用 `HTTPCookie(properties:)!` 造 Cookie,而属性不全时这个初始化器返回 `nil`;`!` 把一条本应失败的用例变成了整包崩溃。改法是补 `.originURL`、把强制解包换成 `#require`,并把「没有 domain 的 Cookie」这一条从 Swift 套件里移除 —— 它在 Apple 平台上根本造不出来,该分支由桌面端 Go 测试覆盖。

**证据边界**:这两轮证明的是编译、单元测试与 App 构建;模拟器交互、真机与真实账号仍未验证。

2026-10-30 在一台 macOS 27 / Xcode 27 / Swift 6.4 的机器上做过一次真实验证,不装任何全局工具:

- Core 从 GitHub 现场编译出 `VeneraCatCore.xcframework`(96M,ios-arm64 / ios-simulator / macos 三个切片),`gofmt`、`go vet`、`go test -race`、`gomobile bind` 全过。
- `swiftc -typecheck -swift-version 6` 对 `Sources/NekularityKit` 的 13 个文件跑了一遍,**只有 1 条 error**:`JSONValue.swift` 里 `OrderedObject` 上多出一个从枚举那边复制过来的 `array` 访问器(`case .array(let a) = self` 对结构体不成立)。该访问器已删除,其余 12 个文件、Core 模块导入、Swift 6 语言模式与并发隔离都没有报错。
- 之后补跑了 `App/` 的 10 个文件:先在 iPhoneOS 27.1 SDK 下 `-emit-module` 出 `NekularityKit`(0 error),再用同一 SDK 对 `App/*.swift` 做 `swiftc -typecheck`。结果是 **1 条 error**:`ShelfView.swift` 里 `ForEach(shelf.recentHistory())` 走的是 `Identifiable` 单参重载,而 `ShelfHistory` 并没有声明该协议。修法不是直接补协议——它的 `id` 只是漫画 id、不含源,两个源可能撞 id——而是给 `ShelfHistory` 加 `key`(`source + "/" + id`)并在调用处写 `id: \.key`;收藏夹里 `ForEach(folder.items)` 的同类风险一并改成 `id: \.key`。
- 因此 Kit 侧是 **0 error 0 warning**,App 侧在修掉这 1 条后仍在等一次复验。

## 已写好

| 部分 | 内容 |
|---|---|
| Core 封装 | `CoreClient`:async/await 接口,任务取消会传给 Core;`CoreHost`:实现 Core 的全部宿主接口;搜索按 Core 给出的选项调用 `search.load`,默认值来自源声明,界面可改选 |
| JSON | 自写的 `JSONValue` 解析器和 `OrderedJSONDecoder`,保留键顺序和数字原文 |
| 网络 | `URLSessionTransport`:按源隔离 Cookie,重定向中途设置的 Cookie 也会保存 |
| Cookie | `CookieJars`:host-only 与域 Cookie、路径、Secure、过期;持久 Cookie 写入文件 |
| 人机验证 | `VerificationSession`:WKWebView 加载挑战页,按 Core 的完成规则判断通过,并把 Cookie 和 User-Agent 交回 |
| 存储 | `SourceStore`:源数据、设置和插件记录,原文保存;是否登录按官方规则判断(存在 `account`) |
| 图片 | `ImageLoader`:按源的 `onImageLoad`/`onThumbnailLoad` 发请求,降采样后缓存 |
| 错误提示 | Core 用英文报错,界面是中文:`CoreError.readable` 把常见失败(取消、缺源、未安装、超时、人机验证、无权限)译成中文,其余保留「源返回错误:」前缀再附 Core 原文,既不把英文句子丢给用户,也不丢排查信息 |
| 界面 | 源管理(订阅、链接安装、更新、启停、删除)、搜索(最近搜索可点选与清空;「当前源/全部源」两种范围,全部源时每个源取第一页、最多 3 个并发、按安装顺序合并并标注来源,点开别家的漫画会自动切换当前源;单源搜索下有源声明的筛选条,改选后重新搜索,合并搜索仍用各源默认值;每个搜索带一个代次号,旧搜索晚到的结果不会写进新搜索的界面)、详情(分组章节,读到的那一话标「读到」)、阅读器(竖向滚动或单页翻页两种排版,翻页可设「左→右/右→左」,上下章,把当前页与百分比写回书架;重开同一章会回到上次那一页;可选「自动接续」,默认关闭,只有真的滚到章末才自动进下一话,且只在竖向阅读时出现——分页用 `TabView` 会预先构建相邻页,没有可信的「快到章末」信号,与其猜不如不显示)、源发起的提示/对话框/输入/选择/加载 |
| 源设置 | `CoreClient.settings(key:)` 读 Core 的 `settings` 声明;源详情页进入设置页,按类型渲染下拉/开关/输入框,值以 `JSONValue` 原样写入该源 store 的 settings 段(数字、布尔不被转成字符串);input 的 `validator` 用正则校验;callback 显示为「源内操作」 |
| 书架 | `ShelfStore`:阅读历史(每部漫画一条,含章节、页码、百分比)与收藏夹;打开章节即记录,书架页可继续阅读、移除、换夹、新建/重命名/删除收藏夹;文件 `shelf.json` 与桌面端同形 |
| 标准 AI 界面 | 「AI 供应商」页顶部进入「标准接口」:选 OpenAI Chat/Responses 或 Anthropic Messages、自定义 API 根、填模型与最大 token;密钥只写钥匙串(按供应商分账号,不随备份迁移);可读模型目录、发一轮对话。回复目前**整包返回**,界面直接写「流式尚未接通」而不是假装流式。Core 侧走 `BuildAIRequest`/`BuildAIModelsRequest`/`SendAIRequest`,与 Magpie 插件完全分开 |
| 搜索历史 | `SearchHistoryStore`:最近 30 条,忽略大小写去重、最新在前,可合并备份里的 `searchHistory`;文件 `searches.json` 与桌面端同形 |
| 备份契约 | 用三个真实 `.venera` 跑 Core 的 `Plan`,把每个字段抄了下来:历史是 `{sourceKey,id,type,title,subtitle,time(毫秒),ep,page,readEpisode[],maxPage,chapterGroup}`;收藏夹是 `{name,order,items[]}`,条目里的 `time` 是字符串;图片收藏是 `{id,sourceKey,title,author,time,maxPage,episodes[{eid,ep,epName,imageFavorites[{page,imageKey,eid,ep}]}],other}`;源是 `{key,script?,data?}`;另有 `pending` 与 `settings`。本客户端的 `BackupPicture` 已按真实形状实现(页嵌在 `episodes[].imageFavorites[]`),导入时会真的落成收藏页 |
| 图片收藏 | `ShelfStore.pictures`:阅读器「收藏本页」按当前页记下源、漫画、章节、页码与图片地址,同一地址只存一份、最新在前;有缩略图、点击进漫画详情、滑除;键名与桌面端 `shelf.json` 一致(`comicId`/`chapterId`),空表不写 `pictures`;备份导入会把官方 `episodes[].imageFavorites[]` 落成收藏页 |
| 备份导入 | 走 Core 的 `planBackup`(它自己解压、读 sqlite、认 type hash),客户端只负责落库:`BackupImporter` 按计划装源、合并历史与收藏夹、合并搜索历史;设备类设置与 cookies 不覆盖本机;图片收藏按官方 `episodes[].imageFavorites[]` 落成收藏页,结果里分开报「新写入 / 已在书架 / 跳过」 |
| 补丁生成 | `scripts/make-patch.sh BASE OUT FILE...`:以对方手里的旧副本为基准生成 `fix.patch`,并**先在本机把它应用到一份草稿副本上**,逐文件比对 md5。以前是“用文字描述改哪几行”,对方照做后 md5 仍不同,只能再来一轮;现在发出去的补丁已经证明能落到目标字节 |
| 传输清单 | `scripts/make-payload.sh OUTDIR FILE...` 一次输出归档大小与 md5、解包后逐文件 md5、逐段 md5 与段数 —— 一整块可原样粘贴。之所以要一个脚本:我曾在同一条消息里给出「归档 md5」和一个**旧版本**文件的 md5,收方校到一半就会判定数据错,而实际错的是说明文字。**2026-11-01 补了一条**:脚本现在用 `git cat-file blob` 取**仓库里的字节**而不是工作树里的。Windows 上 `core.autocrlf=true` 让工作树是 CRLF、对象是 LF(仓库 `.gitattributes` 是 `* text=auto eol=lf`),直接 `cp` 会把 CRLF 发给对方:md5 与我按仓库算的永远对不上,而且 CRLF 的 `scripts/check-core-surface.sh` 在 Mac 上根本跑不起来(`set: -: invalid option`)。这已经让一轮传输白跑过,所以修在脚本里而不是靠人记得 |
| 接口面(免 Mac) | `scripts/check-surface-offline.sh` 用 gobind 在 Windows 上生成 ObjC 头,再跑与 Mac 同一个选择器清单:9.7 秒、18/18。**换 pin 后已对新提交 `d81445f` 重跑**:`19 Magpie / 3 standard AI / 1 URL rule`,与换 pin 前一致——也就是说这次 Core 发布没有改动导出面,重复编译不是必需的(Mac 上仍会照常跑一遍)。以前这件事只能在拿到 xcframework 之后做,那时一个方法不匹配已经花掉一趟传输。顺带确认清单本身是对的 —— 无参方法生成的是 `auth:`/`models:`/`savedAuth:`,不是 `…WithError:` |
| 静态检查(测试替身) | `check-swift.py` 会核对 `Tests/` 里 conform `MagpieRunner.Core` 的替身是否缺方法。协议新增方法时,这类缺失在 Windows 上是静默的、在 Mac 上是 `swift test` 编译错误 —— 代价是一整轮验证。用删掉 stub 的副本反向验证过,它会准确报出 `RefusingCore lacks readPackageArchive` |
| 分类浏览 | `CoreClient.explorePages` 与 `explore` 支持四种 browse 类型(单页多分区、多页列表、混合、多分区页);`BrowseView` 用标签切换分类、分区标题吸顶、分页、下拉刷新 |

## 八个用例全绿(2026-11-01,树 `38d3822`,Core `d81445f`)

第十三阶段:**退出码 0,八个 UI 用例全部 PASS,没有失败也没有跳过**。这是这套用例第一次全员通过,包括这一轮新加的**两分区浏览**(标签行、首分区内容、切换后列表真的换)与**评论线程**(入口只在源声明时出现,线程里作者与正文都在)。

```
check-core-pin: ok (d81445fbcf04)
swift test: 229 tests / 43 suites passed
未签名 App 构建、build-for-testing、simctl install、seed 写入、test-without-building  全通过
UI: 8 PASS / 0 FAIL / 0 SKIP
```

界面证据:[浏览](见 worker 附件)、callback 对话框、评论线程、漫画详情、网页登录 sheet 五张截图。

**界线不变**:浏览、评论、callback 的通过来自仓库自带的测试源;登录用例只证明 sheet 会打开,**没有提交过真实账号**。真机、真实账号、锁屏后台仍然没有证据。

## 第一次写 loopback 服务,被 Swift 6 并发挡住了(2026-11-01)

阅读用例的第一版在验证机上**直接编译失败**,失败点不在测试逻辑,而在 `UITests/LocalImageServer.swift`:项目里 `SWIFT_STRICT_CONCURRENCY: complete` 是**全局**设置,测试 target 也继承,于是

- 在 `NWListener` 的 `@Sendable` handler 里修改捕获的局部 `var failure` → 并发修改
- 跨 handler 捕获非 `Sendable` 的 `self` → 非 Sendable 逃逸

修法是让这个类自己承担:`@unchecked Sendable`(所有存储属性都是 `let`)加上一个自带锁的 `Signal` 传递启动结果,不再跨 handler 捕获 weak self。

**这条记下来的价值**:「测试机上的严格并发」不是理论问题——它第一次就把新代码拦下来了,而且拦在编译期而不是运行时。派发前我在本地自查时已经改了,但验证机仍按先到的旧树跑了一轮,所以失败是真实发生的,不是假设。

## 降级在验证机上实测生效(2026-11-01,树 `b5ec30b`)

上一节只是本地用 `--no-parser` 模拟的。这一轮在 Mac 上真跑了一遍:

```text
check-swift: tree-sitter is not installed, so files are not parsed for syntax; the rule checks still run.
  python3 -m pip install tree-sitter tree-sitter-swift
check-swift: 95 files checked by the rules only
退出码 0

check-docs: ok
退出码 0

python3 -c 'import tree_sitter, tree_sitter_swift'
退出码 1(ModuleNotFoundError: No module named 'tree_sitter')
```

**边界仍然要说清**:这台机器上**规则跑了,语法解析没跑**。语法错误由那台机器的真编译器(`swift build` / `xcodebuild`)负责,所以并没有留下缺口;要让解析也跑起来,需要在验证机上装 tree-sitter——那是环境选择,不是代码问题。

从下一轮起,`verify-ios.sh` 里这一项会显示 `PASS python3 scripts/check-swift.py (rules only: no parser here)`,不再是 SKIP。

## `check-swift.py` 在 Mac 上不再整套跳过(2026-11-01)

Mac worker 的门禁每次都有一个 SKIP:`check-swift.py` 因为那台机器没有 Python 的 tree-sitter 而退出 3。**恰好是最能编译的机器不跑这条检查。**

查下来只有「语法解析」那一步需要 tree-sitter,其余规则(必须 `import VeneraCatCore` / `import NekularityKit`、重复用例名、未闭合字符串、未知标识符、谓词写法)都是纯文本判断。所以缺 parser 时改成**降级为只跑规则并说明**,而不是退出:

```
check-swift.py --quiet --no-parser     → exit 0(规则全跑,解析跳过)
```

负向验证:临时放一个命名 `MobileCore` 却没 import 的文件,`--no-parser` 立刻报
`names MobileCore but does not import VeneraCatCore`,退出码 1;删掉后回到 0。

### 每条断言都要问:它在上一个界面是不是也成立

这一轮审自己的用例时抓到两条**会因错误原因通过**的断言:

- 分类用例切换值之后只断言「漫画还在」——可它本来就在屏幕上,`waitForExistence` 立刻返回真。改成等**被点的 chip 变成选中态**。
- 书架用例切换 tab 之后只断言「漫画名在」——可**详情页标题也叫这个名字**,若 tab 没切过去,断言照样通过。改成先断言 `navigationBars["书架"]` 存在、再断言书架独有的进度行(`Chapter 1 … 第 1 页`)。

规则:**断言的对象如果在操作前的界面上也存在,这条断言就证明不了操作发生了**。逐条核对后,其余用例的断言都只在目标界面成立(例如评论正文、收藏列表、分区标签、`callback_probe · probe` 导航标题)。

## 十三个界面用例各自证明什么(2026-11-01)

用例多了以后,「跑过了」很容易被当成「都验证了」。这张表说明每一例到底压在什么上,以及它证明的是客户端还是站点。

| 用例 | 证明什么 | 依赖 |
|---|---|---|
| `testTabsExist` | 四个 tab 都在 | 无 |
| `testSeededSourcesAppear` | 种子进了设备且被解析;含测试源,否则回调/标签用例会莫名跳过 | 种子 |
| `testSourceOffersInPageLogin` | 源声明网页登录时能打开登录 sheet | 种子(不提交登录) |
| `testCallbackSettingRuns` | 源自定义按钮能按、结论回到界面 | 测试源 |
| `testSearchReachesDetailWithTags` | 搜索 → 结果 → 详情,标签与章节都画出来 | 测试源 |
| `testTagTapOpensTheSourcesRule` | 点标签走的是源自己的规则,不是客户端猜的 | 测试源 |
| `testBrowseLoadsSections` | 分区标签行、首分区内容、切换分区后列表真的换 | 测试源(需两个分区) |
| `testCommentsShowTheSourcesThread` | 评论入口只在源声明时出现,且线程里作者与正文都在 | 测试源 |
| `testSearchHistorySurvivesRelaunch` | 关掉再打开,搜索过的词还在(写盘与读回都是 App 的事,单测证明不了) | 测试源 |
| `testSourceFavoritesShowWhatTheSourceKeeps` | 源自己保存的收藏能列出来(收藏是**顶层** `favorites` 块,不在 `comic` 里;写错位置只会得到空页面,不会报错) | 测试源 |
| `testReaderDrawsTheChaptersPage` | 章节的图片真的解码成页面(判据是「收藏本页」由置灰变为可用,而不是「阅读器打开了」) | 测试源 + runner 内的 loopback 服务 |
| `testReadingPutsTheComicOnTheShelf` | 读过之后书架记下这本漫画(阅读器写进度、书架读回,单测证明不了) | 同上 |
| `testCategoryPageListsItsPartsAndComics` | 分类页同时给出可选项与结果,且切换取值后**选中态**真的改变(`category` 与 `categoryComics` 是两半契约,只做一半会画出选择器却永远加载不出内容) | 测试源(声明了 `category`) |

**没有任何一例使用真实站点。** 它们证明的是「客户端把源声明的能力正确呈现」;真实站点的搜索、登录、浏览由桌面端的真实源巡检与活体测试负责。真机、真实账号、锁屏后台仍无证据。

这条界线不是自谦:第十二阶段就有一个例子——浏览用例失败,看起来像客户端没画分区,查下去是我要求了一个按设计不该出现的元素(单分区时不画标签行)。**断言写错和实现写错,在屏幕上长得一模一样**,所以每例都得说得出它压在哪个设计决定上。

## Core 的 Apple CI 现在有第三方证据(2026-11-01,提交 `d81445f`)

之前说「xcframework 能出、Swift 冒烟能过」,靠的是本机和 Mac worker 的记录。现在 GitHub 自己在 macOS 26 / Xcode 26.6 runner 上跑完了,四个 job 全绿,而且核对了日志而不只是状态色:

```
RESULT gofmt=ok / vet=ok / test=ok / bind=ok
RESULT bind_seconds=347
RESULT xcframework_total=101M
RESULT slice_ios-arm64_x86_64-simulator= 40M / slice_ios-arm64= 21M / slice_macos-arm64_x86_64= 40M
RESULT device_binary_stripped= 21M / device_binary_gzip=7.5M
Swift 冒烟(macOS)8 项通过;Swift 冒烟(iOS 模拟器)8 项通过,** TEST SUCCEEDED **
```

这意味着 Core 的 Apple 导出面不是「只在我这台机器上能编译」——有独立环境复现。

## 整轮门禁第一次 exit 0(2026-11-01,树 `848d748`,Core `d81445f`)

`sh scripts/verify-ios.sh` 第一次**整体通过**:七个 UI 用例 **6 PASS / 1 SKIP / 0 FAIL**,`check-core-pin: ok (d81445fbcf04)`,Core 按新 pin 重新拉取并重建 framework,`swift test` 229 / 43。

通过的六项覆盖了源能力这条主线:tab、种子源、网页登录 sheet、**设置回调**(对话框 + 内联答案 `ran`)、**搜索到详情**(带标签与章节)、**标签点击**(`callback_probe · probe`)。

**证据边界要写清**:搜索详情与标签走的都是**仓库自带的 Probe 源**,不碰网络。所以这轮证明的是**客户端把源能力呈现出来**是对的,不能推出「真实站点的搜索/登录/浏览都可用」——那部分由桌面端的真实源巡检与活体测试负责。

SKIP 的是浏览用例,原因不是 App 而是**测试隔离**:App 会记住上次选中的源,标签用例切到 Probe 源后,浏览用例继承了它,而 Probe 源当时没有分类入口。同一轮已修:新增 `chooseSource` 让每个用例自己声明需要的源,并给 Probe 源加了 `explore` 分区,浏览用例改为断言分区与作品。

## 界面测试走到哪一步(2026-11-01,树 `79a5dbb`)

七个用例 **6 PASS / 1 FAIL**,第一次把「源能力」这条线在模拟器上跑成了:tab、种子源、网页登录 sheet、**设置回调**(`Probe Result` 对话框 + 内联答案 `ran`)、浏览页、**标签点击**(`callback_probe · probe` sheet)全通过。

没通过的是「搜索到详情」:失败时导出的界面树里明明有 `detail.comments`、标签与章节,断言却说控件没出现。原因是 `element()` 用 `descendants(matching: .any)` 遍历整棵树,一次求值可能比它自己的超时还长,于是**在屏幕上的元素被判成缺失**。现在先查类型受限的廉价查询(buttons/staticTexts/cells),详情页改为等 `detail.comments` 或任一 cell,失败再导出 `detail-tree`。

同一轮把 Core 发布成单提交 `d81445f` 并同步两端 pin;顺带用区分性实验纠正了一个判断:**Core 的 `mobile.CallSettingCallback` 只服务 iOS**,桌面走自己的 `internal/core`,所以撤回「Core 修了两端都好」的说法。

## 证据分级(2026-11-01)

同一个「通过了」在不同层级含义不同,下表按层级列出当前结论,避免把编译通过当成运行验证。

| 结论 | 证据层级 | 说明 |
|---|---|---|
| Core 接口与 Kit 调用一致 | 静态 + Mac 编译 | `check-kit-core-calls.py`、`check-core-surface.sh`、`swift build`/`swift test` 在 Mac 上真实执行 |
| 单元测试全绿 | Mac 运行 | `swift test` 229 tests / 43 suites,同步跑在 `verify-ios.sh` 里 |
| App 能构建 | Mac 运行 | 不签名 `xcodebuild build` 与 `build-for-testing` 均成功 |
| 种子能进设备 | Mac 运行 | 写 127,249 字节,设备文件 md5 与种子一致,解析出四条记录 |
| tab / 种子源 / 网页登录 sheet / 浏览页 | 模拟器交互 | UI 用例 PASS,带截图与录屏 |
| 搜索框可用 | **已验证(模拟器)** | 原来 `searchable` 在这里根本没画出输入框(树为证);改成自带字段后,用例能输入并提交,一路走到详情 |
| 回调按钮可点 | **已验证(模拟器)** | 原来按钮可见但命中区域不接收点击;改成 `HStack` 后,对话框与内联答案 `ran` 都被观察到 |
| 标签可点 | **已验证(模拟器)** | 同一容器问题的另一处;点 `probe` 后确实出现 `callback_probe · probe` |
| 浏览分区 | **已修复,待验证** | 用例曾因继承到没有分类的源而跳过;现在每例自选源、Probe 源带 `explore`,待下一轮跑 |
| 真机、真实账号、锁屏后台 | 无 | 仍无任何证据 |

## 未验证

- **ATS 策略已定**:`App/Info.plist` 里 `NSAllowsArbitraryLoads = true`。漫画源由用户自行安装,主机无法预知,逐主机例外做不到;上架理由写在该文件与 README 里。已在读到的四个真实源上确认它们全走 https(0 处 http),放行只是不挡未来的 http 源。这个改动**已经过真正的 Xcode 构建验证**(2026-10-31,同一台 Mac):XcodeGen 从官方发布页的二进制包取用(2.46.0,放在 `/tmp/xcg`,**没有装 Homebrew、没有进系统 PATH**),`xcodegen generate` → `xcodebuild -scheme Nekularity build` 得到 `BUILD SUCCEEDED`;产物 `Nekularity.app/Info.plist` 里读出 `NSAllowsArbitraryLoads = true`,`-showBuildSettings` 回显 `INFOPLIST_FILE = App/Info.plist` 与 `GENERATE_INFOPLIST_FILE = NO`,`Copy Bundle Resources` 相关报错 0 次(即 `excludes: [Info.plist]` 生效)。`scripts/verify-ats.sh` 把这条链路写成脚本并接进 `verify-ios.sh`,现在每次整树验证都会跑真实 App 构建而不是退化成类型检查。
- **真机**:没有在 iPhone 真机上跑过。模拟器上主线**全部走通**:tab、装源、搜索到详情、标签、浏览分区、评论、收藏、回调、搜索历史跨重启,以及**阅读与阅读后书架**,共 12 个用例。真机、真实账号、锁屏后台都没有数据。
- **签名与归档**:XcodeGen 现在是门禁的一部分(`xcodegen generate` 每次都跑),`xcodebuild` 会在 generic/platform=iOS 上产出**不签名的 `Nekularity.app`**,`build-for-testing` 也通过。但签名、归档与安装到真机没有做过:`** BUILD SUCCEEDED **` 只证明能编译与打包,不证明能装到设备上。
- **真实供应商账号**:Magpie 的登录、模型列表、用量、流式与取消都只在自己的假服务与固定回答上验过;没有任何一个真实厂商账号在设备上走完授权。
- **真实漫画源**:由桌面端的 `TestLiveSource` 在仓库外验证(见 Nekophage),iOS 端没有同等的真源用例。

## 下一步

1. 编译与测试阶段已收尾:Kit 与 App 在 macOS 上按 Swift 6 模式通过 `swift build`、`swift test`(58 个)、`-typecheck`、iOS `-emit-module`、App `-typecheck` 五项(含多源搜索与收藏页跳章那一版);此后每一批改动仍按同一流程复验,编译器没看过的新包不会累积。
2. 在已就绪的模拟器上用真实源跑通主线(装源→搜索→详情→阅读→书架) —— App 能启动这一步已完成,这一步是让它真的用起来。
3. 备份导入已接上,并用真实 `.venera` 的字段形状核过;下一步是在模拟器里跑一遍并核对条数。
4. 视频源与播放仍需产品决策;旧版全局 Cookie 已按源分区迁移完成(见本页「Cookie 迁移」一节)。
5. ~~安装 iOS 模拟器运行时~~ **已完成**(2026-11-01):两个 iOS 27.2 runtime、12 台可用设备,App 已在 iPhone 18 Pro 模拟器上装起来并启动。
6. AI 能力排在主线之后:iOS 端要做的是 **Magpie 插件系统**——直接运行 Magpie 的供应商原包,账号与运行环境独立于漫画源。桌面端不做 AI 接入。

## Magpie 供应商插件(Nekularity 侧)

**能装什么,先说清楚**:社区仓库 36 个包里,目前真正能在这套系统里跑的供应商插件只有两个 —— 原始 `@magpie-community/opencode-copilot-auth` 0.1.0 与 `cloudflare-workers-ai` 0.0.4。其余多数需要 `node:fs`/`node:crypto`/`child_process`,或者入口是 TypeScript,加载时会被明确拒绝并说出缺什么(不是白屏,也不是"装上了但用不了")。所以「兼容 Magpie」这句话在这里指**包格式与运行时约定兼容**,不指"所有社区包都能装"。

Core 侧已跑通:包快照与模块定位、`fetch`/`Headers`/`URL`/`ReadableStream` 运行时、设备码登录、刷新写回、用量与模型列表、流式分块、三种协议的流事件归一,以及「已输出就不再重试」。这些都有 Go 测试,包括用原始 Copilot 包跑假服务。

本仓库这一步只做客户端这一层。**2026-10-31 的验证已全部通过**,在 macOS 27 / Xcode 27 / Swift 6.4 上:

| 检查 | 结果 |
|---|---|
| `scripts/check-core-surface.sh` | PASS —— 18/18 个 `MobileMagpie` 方法 |
| `swift build` | PASS,0 error 0 warning |
| `swift test` | **PASS — 119 tests / 27 suites** |
| Kit `-typecheck -swift-version 6`(arm64-macos26.0) | PASS,0 error 0 warning |
| iOS `-emit-module -parse-as-library -swift-version 6`(iPhoneOS 27.1) | PASS |
| App `-typecheck -swift-version 6` | PASS |
| `swift test --filter Magpie` | **PASS — 61 tests / 16 suites** |

静态计数与运行数一致:`@Test` 119、`@Suite` 27、`.swift` 56(28 Kit + 14 App + 11 Tests + `Package.swift`)。

**同日更早一轮(129 条,已被下一段覆盖,保留以说明数字怎么长起来的)**:2026-10-31 在 Mac mini(macOS 27.0.1 / Xcode 27.1 / Swift 6.4)上跑同一套五项检查,全部 exit=0:`swift build` 0 error 0 warning、`swift test` **129 tests / 27 suites passed**、Kit `-typecheck` 与 App `-typecheck` 0 error 0 warning、iOS `-emit-module` 0 error;`check-core-surface` 18/18;`swift test --filter Magpie` **71 tests / 16 suites**;`check-tree` 输出 `swift=56 tests=129 suites=27 shape=8457d8e43ce3d36849577f4cdcc07a92079b4015`,与本仓库同一 shape。**仍未验证的**:`xcodebuild` 归档与签名、iOS 模拟器运行时(机器上没有)、真机与真实供应商账号。**整树验证器现在可以一条命令跑完**:`scripts/verify-ios.sh` 在 macOS 上 `EXIT=0`,顺序为 surface、Core pin、文档、语法、`swift test`、`xcodebuild`(iOS,不签名)与 App `-typecheck`。语法那一行是 `SKIP` 而不是 `FAIL`:没有 tree-sitter(exit 2)或语法版本装不上(exit 3)都表示「这台机器跑不了」,而开发机直接跑 `scripts/check-swift.sh` 仍然硬失败。两条退出路径都在 Mac 上验过。该轮 `swift test` 130 条 / 27 suite,App 类型检查 0 error 0 warning。

**已知且无害的两条构建提示**(后续对比用,不算回归):`xcodebuild` 每次会打印 `warning: Metadata extraction skipped, no AppIntents.framework dependency found`,并另有一条以 `error:` 开头的 CoreSimulator 版本提示(`iOSSimulator: CoreSimulator is out of date … Simulator device support disabled`) —— 后者不是编译错误,`** BUILD SUCCEEDED **` 仍在。`swift test` 侧是 0 warning。出现这两条之外的 `warning:` 时才算新问题,需要单独定位。

**最新一轮整树验证(2026-11-01,同一台 Mac mini,含搜索代次号与换 pin)** —— *注意:这些是那台机器上树的数字;本仓库同一状态是 182/34,两边为何不同见下面「未决:本地树与验证树对不上」*:70 个 Swift 文件、**196 条用例 / 35 个 suite**、`shape=e18d20cb0465bbbaa651d9634b1d0a8a31dde9db`。`sh scripts/fetch-core.sh` 从 GitHub 现编 Core 到 `6e07429`(`gofmt`/`go vet`/`go test` 全过,22 个包),随后 bind 出框架并逐文件核对 SHA256(23 个文件,0 mismatch);`check-core-surface.sh` **19 个 Magpie 方法 + 3 个标准 AI 方法**,并在新框架里确认了 `streamOpen:`/`streamNext:`/`streamClose:` 与 `MobileNewMagpieWithStream`;`check-core-pin` **ok (6e0742996007)**;`PATH=/tmp/xcg/xcodegen/bin:$PATH sh scripts/verify-ios.sh` **EXIT=0**;`swift test` **196 tests / 35 suites,0 warning**;`xcodebuild generic/platform=iOS` **BUILD SUCCEEDED,0 error**(1 条既有 AppIntents 提示;产物时间晚于框架,用的是新框架);`check-partitions`/`check-docs`/`verify-ats` 全过。**反向验证**:把 `scripts/core-version` 改回 `469edfcb48ec…`,`check-core-pin.sh` 以 rc=1 并指出两侧不一致,改回后 rc=0。

这一轮还第一次拿到了**模拟器运行时的证据**:runtimes 两个 iOS 27.2,`devices available` 12 台(含已 Booted 的 `iPhone 18 Pro`),`xcodebuild -showsdks` 的 iOS SDK 为 27.2。

### 分段传输的实情(2026-11-01)

iOS 端的 `URLSessionTransport.sendStreaming` 复用 `send` 的同一条请求路径(同样的 Cookie、取消、限额、重定向策略),只是把正文**边收边给**。`CoreStreamHost` 实现 Core 的 `MobileHostStream` 协议,把它交出去。

**一个必须知道的实测约束**:**Foundation 会把小于约 256 字节的相邻 `URLProtocol` 分片合并**再交给 delegate。Mac 上量的:

```text
16B × 3   → 收到 1 块
64B × 3   → 收到 1 块
256B × 3  → 收到 2 块
1024B × 3 → 收到 3 块
8192B × 3 → 收到 3 块  首块 5ms、中块 315ms、末块 618ms
```

所以「分片要能一块一块地到」这件事,在**测试替身**里必须用 1024 字节以上的分片,否则量到的是 Foundation 的合并行为,不是我们的流式。真实服务器那组时间戳(5ms / 315ms / 618ms)才是「边收边给」的真凭据。

**接口名以生成的 objc 头为准,不靠猜**:`MobileNewMagpieWithStream(_ host:, _ stream:)` 的第二个参数**无标签** —— 头文件里 ObjC 原型没给参数名。这一点我先写错成 `stream:`,是 Mac 编译报 `extraneous argument label 'stream:' in call` 之后改的。

### 未决:本地树与验证树对不上(2026-11-01 发现)

同一份 `scripts/check-tree.sh`,两边报的数字不一样:

| 状态 | 验证 Mac 上的树 | 本仓库 |
|---|---|---|
| 标准接口 + 搜索代次号,未加分段传输之前 | `swift=70  tests=196  suites=35` `shape=e18d20cb…` | `swift=69  tests=182  suites=34` `shape=4c01f2bb…`(commit `0ae0579`) |

**suite 数相同、test 数差 10**,所以差的不是整个测试文件,而是某个已有文件里多了 10 条 `@Test`。

我的判断(待验证):早前那轮 iOS 网络/生命周期修复(URLSession delegate 保活、预取消竞态、跨 origin `X-Api-Key` 泄露、ImageLoader 共享任务取消、刷新凭据持久化、Magpie signOut runner 缓存、`MagpieUsage` null 兼容、登录超时取消)**只落在验证机的隔离目录里,没回到仓库** —— iOS 仓库是私有的,那台机器拉不到,而当时的传输是零碎 gist。

**已经把逐文件 `@Test` 清单要过去了。**拿到后逐行 diff,把缺的源码与测试一次性补回仓库,再发一个完整包;在那之前不再往树上叠零碎补丁。**因此上面几段里 Mac 报的 196/35、192/34 是那台机器上树的数字,不是本仓库的数字** —— 两者不一致本身就是这条记录要说明的事。

### 模拟器上第一次真的跑起来(2026-11-01)

这是本项目第一次拿到「App 在设备上装起来、启动、界面出来」的证据,不是编译通过:

```text
iPhone 18 Pro (1E57B720-…) 已 Booted；bootstatus -b → rc=0
模拟器版重建 → BUILD SUCCEEDED（此前 build/verify 里只有 Debug-iphoneos，装不进模拟器）
simctl install → rc=0，1s
simctl launch  → rc=0，PID 78149，往返 165ms
截图 → /tmp/nk/logs/audit-docs/app.png
进程存活 → UIKitApplication:com.laincat.nekularity
崩溃检查 → 272 行日志里 crash/fatal/signal/exception/abort 全 0；DiagnosticReports 无任何 .ips
Core 框架加载失败 → 0（grep VeneraCatCore|dyld|Library not loaded|image not found|Go runtime|MobileNew 全 0）
启动耗时 → 19:13:52.835 首行 → 19:13:53.538 界面就绪，约 0.7 秒
```

**截图上是**:标题「搜索」、搜索框占位「关键词」、中央空状态插图 + 「没有可用的漫画源」+「先在“漫画源”里添加并启用一个源。」、底部五个标签(搜索 / 浏览 / 书架 / 漫画源 / AI 供应商)且选中「搜索」。这是换 pin 后重装的**全新容器**,源列表为空是预期,不是加载失败 —— 同一份日志里 Core 框架加载失败为 0。

**这条证据的边界**:只证明「能装、能启动、界面能出来、无崩溃、Core 框架能加载」。真实供应商登录(Magpie / OpenAI / Anthropic)仍无凭据,实时流式仍未接通,真机仍未跑。

**Core 侧死锁修复的实测证据**:在 `build/core` 跑 `go test -race -run 'Reply|Chat' ./magpieplugin/`,`TestReplyBufferWriteDoesNotWaitForAReader` 等 6 条缓冲用例与 3 条聊天用例全部 PASS —— 这正是修复的那个行为:写方不等待读者。

上一轮(2026-11-01 上午,已被上面这段覆盖):68 个 Swift 文件、**192 条用例 / 34 个 suite**、`shape=e2d55356aabdec360928addd42a3f9e6e7fbcab5`。`swift test` 全过(新增的 11 条标准 AI 用例全部实际执行)、`xcodebuild -scheme Nekularity`(generic/platform=iOS,不签名)**BUILD SUCCEEDED**(0 error,1 条既有的 AppIntents 提示)、`scripts/verify-ios.sh` **EXIT=0**、`scripts/check-core-surface.sh` **19 个 Magpie 方法 + 3 个标准 AI 方法**(反向:去掉三个标准 AI 选择器的头文件会 exit 1)、`check-core-pin` `6e0742996007`、`check-partitions`、`check-docs`、`verify-ats` 全过、`scripts/check-tree.sh` shape 一致。这一轮覆盖了「标准接口」界面(`App/StandardAIView.swift`、`Sources/NekularityKit/AI/`)、`CoreClient` 的三个标准 AI 调用与 `check-core-surface.sh` 新增的 3 个选择器检查。

Mac 上实际改的 4 处都是编译问题,不是行为问题:`StandardAISettingsStore` 改为 `@unchecked Sendable`(`UserDefaults` 本身不是 `Sendable`,Swift 6 拒绝合成,官方文档保证其线程安全);`StandardAI.swift` 里两处可选模式匹配写错(`case .object(let x)? = 非可选值`);`Section("协议") { } footer: { }` 在 SwiftUI 没有这个重载,改成 `Section { } header: { } footer: { }`;测试里 `#expect(try …)` 在宏展开时不处理 `throws`,改成测试自身 `throws` 并把 `try` 提到宏外。**「流式尚未接通」这句话原文保留**。

收包时做了一处规范化:包内 9 个文件是 CRLF,统一转成 LF 再落盘。理由有两条实证 —— 仓库 `.gitattributes` 是 `* text=auto eol=lf`,CRLF 提交时会被改写、md5 立刻漂移;且 CRLF 的 `scripts/check-core-surface.sh` 直接跑不起来(`set: -: invalid option`,`
` 被当成选项)。除行尾外逐字节与收包一致(11 个文件逐一比对通过)。

上一轮(2026-10-31,已被上面这段覆盖):63 个 Swift 文件、**164 条用例 / 32 个 suite**、`shape=82fa2813dd9f4a8b397f263c1f7093a0d0294003`。`swift build` 0 error 0 warning、`swift test` 全过、`swift test --filter Magpie` **76 条 / 16 个 suite**、Kit 与 App 的 `-typecheck -swift-version 6` 均 0 error 0 warning、`xcodebuild -scheme Nekularity`(generic/platform=iOS,不签名)**BUILD SUCCEEDED**。这一轮覆盖了 `CoreVersion.swift`、供应商页脚里的 `buildLine`,以及 `theCoreVersionIsShortButIdentifiable`。唯一没跑成的是 `check-swift.py`:那台机器只有系统 Python 3.9,装不了语法版本 15 所需的 `tree-sitter>=0.24`,现在它会以 exit=3 明确表示「这台机器跑不了这个检查」,`verify-ios.sh` 记为 SKIP 而不是 FAIL —— 因为后面的步骤用的是真编译器。

框架的 macOS 部署目标也定下来了:Core 用 `gomobile -macosversion=26.0` 构建(与 `Package.swift` 的 macOS 26 一致),因此链接期那 16 条 `was built for newer macOS version` 归零 —— 用官方脚本、未改动任何文件复现过。

这一轮之前是「编译绿、测试红」:同一棵树编译零错误,`swift test` 却抓出 4 个断言失败——`modalities: null` 解不出来、安装没校验插件声明的 provider(会把登录写进别的账号)、登录循环里「空/null」一处当作等待一处当作失败(根因是 `JSONSerialization` 默认不接受顶层 `null`)。修完又补了登录与对话两个超时:能被无限等待的地方,测试和用户都会撞上。

**验证环境可以随时重建**(2026-10-31 确认):那台 macOS 机器能直接 `git clone` 公开的 Core 仓库(`github.com/laincat/VeneraCat-Core`),本地 Go 1.27.3,`gomobile` 按 `go.mod` 里的工具依赖用 `go build` 现编,不需要装任何全局工具。所以「重新验一遍」现在是从 GitHub 克隆加一条 `scripts/mac-verify.sh` 的事,不依赖谁手里留着一份源码。

验证的边界,写清楚比含糊过去好:

- ⑤ 的 App 检查是 `swiftc -typecheck -swift-version 6` 直接对 `App/*.swift` 加上 `-emit-module` 出的 `NekularityKit.swiftmodule` 跑的,等价于 Xcode 工程里的 Swift 6 编译检查;`xcodebuild` 真实打包与签名**没有跑**(那台机器也没有 iOS Simulator 运行时,安装属于系统级操作,需要另行批准)。
- 验证用的树不含 `project.yml`。它是 XcodeGen 的输入,不参与 `swift build`/`swift test`,也不参与上面的 typecheck。
- 两台机器的 `manifest.sh` 逐文件 md5 一致(68 个参与编译/测试的文件),`check-tree.sh` 的 `shape` 也一致。

下面这一段是 2026-10-30 的首轮结果,保留下来是为了说明这份文档里的数字是怎么长起来的:

2026-10-30 已在 macOS 27 / Xcode 27 / Swift 6.4 上真实编译并跑通全部五项检查:

```
① Kit swift build                     PASS  0 error 0 warning
② Kit swift test                      PASS  65 tests / 13 suites（原 58 / 11，+7 与 +2）
③ Kit -typecheck -swift-version 6     PASS  0 error 0 warning
④ iOS Kit -emit-module                PASS
⑤ App -typecheck -swift-version 6     PASS
swift test --filter Magpie            7 tests / 2 suites 全部执行
```

第一次真正编译这层就没报错、也没有 warning。文件数也对上:Sources 16→18、Tests 9→10,合计 36→38。

| 部分 | 内容 |
|---|---|
| `MagpieAuthStore` | 登录信息按 provider 分开存,存的是**原文 JSON 字符串**而不是解析后的字典:包自己写、自己读,重新编码会打乱键序,也会让 `9007199254740993` 变成浮点。`MemoryMagpieAuthStore` 供测试,`KeychainMagpieAuthStore` 用 `kSecClassGenericPassword` 按 provider 建条目,可访问性取 `AfterFirstUnlock`——锁屏时也可能要刷新,读不到就等于包悄悄失效 |
| `CoreMagpie` | 真正的桥:实现 `MagpieRunner.Core`,只把 JSON 交给生成的 `MobileMagpie`。签名不是猜的——用 `gobind -lang=objc` 生成头文件后照抄:`- (BOOL)loadPackage:(NSString*)filesJSON error:(NSError**)`、`- (NSString*)call:(NSString*)export argJSON:(NSString*)error:`、`savedAuth:`、`setAuth:authJSON:`、`close`,`MobileNewMagpie(id<MobileHost>)`。测试用一个不联网的小包走真实 Go 运行时(`CoreMagpieTests`),因此不需要造 21 个方法的宿主桩 |
| `MagpieSignIn` | 一次登录的等待与放弃:`start` 报出要打开的页面与验证码,`waitForResult` 等包的回调(包自己会轮询),取消时同时停掉等待与包内的回调,不让它继续朝供应商轮询。成功结果按 **Magpie 自己的形状**存:`{type:"oauth",refresh}` 或 `{type:"api",key}`,而不是把包的答复原样塞进去 |
| `MagpieAccounts` | 供应商列表与运行实例:`install(folder:)` 不需要用户输入 provider —— 装好后由**插件自己**报 `auth.provider`。装之前先让 Core 编译一次,拒绝的包不会留下半装状态的行。运行实例与**插件声明的规范**都按 provider 缓存:每次求值都会起一个 JS 运行时,十个供应商的列表不该每次刷新都重新起十次(有测试固定「刷新三次只加载一次」)。卸载时一并清掉缓存 |
 供应商列表与运行实例:`install(folder:)` 不需要用户输入 provider —— 装好后由**插件自己**报 `auth.provider`,用文件夹名当 id 只是临时键。装之前先让 Core 编译一次,拒绝的包不会留下半装状态的行。运行实例按 provider 缓存(每次加载都要编译,重开一次就慢一拍),卸载或退出登录时关闭 |
| 文件清单 | `scripts/manifest.sh` 打出「md5 + 路径」的清单,两台机器 `diff` 一下就知道**哪些文件不同**。增量包不该按提交的 diffstat 拼 —— 就是这么漏掉过 `MagpieRunner.swift` 与 `MagpieAuthSpec.swift` |
| 树身份 | `scripts/check-tree.sh` 打一行「commit + 是否脏 + `.swift` 数 + `@Test`/`@Suite` 数 + 按文件计数的摘要」。两台机器比对这一行就够:摘要相同说明用例在同样的文件里。只看总数不够 —— 已经两次遇到「总数对得上、文件少了」 |
| 增量包 | `scripts/make-delta.sh SINCE OUTDIR [CHUNK]`;加上 `DELTA_SKIP_TESTS=1` 时不带 `Tests/` —— 测试文件是全树最大的,几条例句写成文字比多传二十段便宜 |
| 传输排障 | `scripts/split-part.sh PARTS_FILE` 把一段 base64 拆成两半并分别打印 md5。出现过「长度对、md5 不对」的等长改写:这种情况整包 md5 只告诉你坏了,不给位置;有了逐段 md5 能定位到某一段,再拆半重发通常就过了 |
| Core 版本 | `scripts/core-version` 钉到一个提交(`6e0742996007e0246e1c56a14a09546325bb3e96`),不是 `main`。之前写 `main` 意味着同一个 Nekularity 提交,两天编出来的框架可能不是同一份 Core —— 「可复现」就只对客户端成立,对底座不成立。要换 Core 就改这一行,并在 STATUS 里写清为什么。**钉住的每个提交都在 Core 的 CI 上四个 job 全绿**(Go 三个平台 + Apple 的 xcframework 与两份 Swift 冒烟测试);每次整树验证都用 `scripts/fetch-core.sh` 现编框架,不用旧产物。**`6e07429` 的 CI 四个 job 全绿**(Go 三个平台 + Apple 的 xcframework 与两份 Swift 冒烟测试),2026-11-01 实测:run `41194668348`。

**iOS 也接上了图片回调,并在 Mac 上验过(2026-11-01)**:`ImageRequest` 现在带回 `handle` 与 `callbacks`,`ImageLoader` 每次最多试 4 个地址:取回成功但是错误页且有 `onLoadFailed` 就先问下一个镜像,取回成功且有 `onResponse` 就先把正文交给源改写(解密)再解码,解码失败同样问下一个镜像;每个地址都重新按分区补 scheme。

Mac 上这一轮还修掉了三处**在 Windows 上看不出来**的问题:一是 `fetch` 的请求 id 类型应是 `Int64`(调用方与传输层都是 `Int64`,写成 `Int` 编译不过);二是**失败路径不清理在途表** —— 一次失败之后,同一张图的每个后续请求都会立刻拿到那个已失败的 task,等于整进程内这张图再也加载不出来,现在成功/失败都清理,且只在条目仍属于本次下载时清除;三是**注释声称会挡 `file://`、`javascript:`、`ftp://`,而代码只做了 `URL(string:)`** —— `file:` 地址会被真的交给 URLSession 读本机磁盘,现在显式拒绝非 http(s)。后两条用隔离副本做过反向验证:撤掉修复后,`file:` 地址确实进了传输层、第二次请求确实复用了旧的 `image HTTP 500`。

验证:`swift test` 214 条 / 40 suite 全过(含新增 3 条 `ImageConfigTests`)、`verify-ios.sh` EXIT=0 `BUILD SUCCEEDED`、树 `77/214/40` shape `85dd5c3a…`、Core pin `69ed1f9`。**仍未验证**:真机上的图片流,包括真实源的 `onResponse` 改写与多镜像回退 —— 现在只证明编译、单元测试、App 构建与本机探针。

**封面也按规格跳过像素脚本与镜像回退(2026-11-01)**:`onThumbnailLoad` 的注释写明 `modifyImage` 与 `onLoadFailed` 对缩略图会被忽略,所以 `thumbnailRequest` 解析出配置后把这两项去掉;**`onResponse` 保留** —— 打散的封面仍然要能被解开才看得见。新增 1 条用例钉住这个取舍。另外订正一处我写错的常量:上一版用 `24 << 20`(25,165,824),与用例假定的 3000×8000 边界对不上,已改为 `24_000_000`。

**像素回传的上限按手机的内存来定(2026-11-01)**:Mac 上核过这条链的内存 —— 像素以 RGBA 交给 Core、再以 base64 回传,一次处理的峰值约为 `w·h·4×2.7`;上限设成 64M 像素时满载可达 850 MB–1.1 GB,手机上不能这么赌。iOS 侧因此收紧到 **24M 像素**:常见长条页 1080×16384(17.7M)仍在范围内(约 190 MB 峰值),更大的图原样放行,不为了让脚本跑一张图把进程逼到内存红线。判断抽成 `ImageLoader.pixelPassFits(_:_:)` 并用**除法形式**比较,`Int.max` 这种宽度也不会让乘积溢出;新增 1 条用例覆盖边界与溢出。

**2026-11-01 再把 pin 移到 `eb982d6` 的原因**:iOS 自己跑不了 JavaScript,所以由 Core 提供 gomobile 入口 `modifyImage(key, script, width, height, rgbaB64)`,返回 `{width,height,rgba}`。`ImageLoader` 解码后把像素交给它、再把结果重建为 `CGImage`;像素按直通 RGBA 走 sRGB,超过**客户端上限**的图原样放行(不为此失败;当时的 64M 后来收紧为 24M,见下条),脚本没产出图像则如实报错并照常走镜像回退。**这条路径已在 Mac 上编译并通过 216 条测试与 iOS 构建**(`26cb282`),但仍无真机验证。

**2026-11-01 把 pin 移到 `69ed1f9` 的原因**:Core 新增了图片配置的回调支持 —— `comic.onImageLoad` 除了地址和请求头,还能带 `onResponse`/`modifyImage`/`onLoadFailed` 三个函数,而函数进不了 JSON,所以客户端一直只拿到前四个字段。Core 现在把这几个函数留在源的运行时里、用句柄命名,宿主可以「把响应体交给 onResponse」「问下一个镜像」。**iOS 尚未接这三个方法**,所以这次 pin 移动对 iOS 只是协议层可用、客户端行为不变;桌面端同样还没接。这一步的意义是把「加密图的源显示破图」从「Core 做不到」变成「客户端还没接」。

**2026-11-01 又把 pin 移到 `d98e505` 的原因**:Core 修了两处搜索参数读取 —— 选项格式「`值-文字`」的左边允许为空(`-<none>` 是「值为空」,不是字符串本身),以及多选筛选组的值是一个 JSON 数组(`SearchOptionGroup.DefaultValues`)。两者都会让源把 `undefined` 或 `-<none>` 拼进搜索请求。**iOS 端已接上这两处**:多选组现在按 JSON 数组发,筛选菜单对这类组改成逐项勾选并显示「已选 N 项」,只声明 `search.loadNext` 的源按游标翻页(null 起步、原样回传、空 token 结束);同时声明两个入口的源仍用页码,与桌面端一致(`lanraragi` 的 `loadNext` 只是把 token 映射回页码)。多选那一步已在 Mac 上验过并合入 `main`(206 tests / 38 suites、iOS `BUILD SUCCEEDED`);游标那一步的分页规则抽成 `SearchPaging` 值类型并有 5 条用例,桌面端另有活体证据(`ehentai`:第 1 页 25 条、第 2 页 25 条、0 条重复),iOS 侧仍在 Mac 复验中。

**2026-11-01 换到 `cc63215` 的原因**:那一版 Core 加了 `Core.NormalizeURL` —— 一个源有时把图片地址写成 `//images.example.com/1.jpg`(少了 scheme),RFC 3986 说这继承页面的 scheme,读者里就是该源最近用过的那个。桌面端按分区记住 scheme,iOS 端由 `URLSessionTransport` 记住,两边都用 Core 的同一条规则。**这不放宽安全规则**:`file://`/`javascript:`/`ftp://` 一律不改写,补全后仍要过 http(s) 校验;非协议相对的 URL 一个字都不动。选择器从 19 + 3 变成 19 + 3 + 1(`normalizeURL:`)。

**2026-11-01 换到 `6e07429` 的原因**:那一版 Core 新增了标准 AI 的三个入口(`BuildAIRequest`/`BuildAIModelsRequest`/`SendAIRequest`)与可选的分段传输(`HostStream`),并修掉了包桥的一处死锁 —— 包在自己的 hook 里往 `__magpieChatPush` 写,而读取侧读到结束标记就停了,写方永远等不到读者。新的 Core 加了 `MobileHostStream` 协议与 `MobileNewMagpieWithStream`,所以选择器从 19 个 Magpie 增加到 19 + 3 个标准 AI;`check-core-surface.sh` 已同步 |
| 检查器 | `scripts/check-core-surface.sh` 在编译前检查 `Vendor/` 里的框架是否真的暴露了客户端调用的 18 个 `MobileMagpie` 方法 —— 就是那次「源码调 `chatStart`、框架里却没有」的坑;现在它会直接说缺哪几个,并提示重新 `scripts/fetch-core.sh`。注意列表里写的是 **Objective-C 选择器名**(`cancelSignIn:`),不是 Swift 导入后的 `cancelSign(in:)` |
| 检查器(Swift) | `scripts/check-swift.py` 除了语法,还查一类「语法对、Mac 上才炸」的错:文件里出现 `Mobile*` 这类生成的 Core 类型却没有 `import VeneraCatCore`。这条是 Mac 上一轮真实报错后加的 —— 当时 `CoreMagpie.swift` 就是少了这行,Windows 上完全看不出来 |
| 插件开关 | `MagpieOptionStore` 按 `provider|option` 存用户选择(文件小、可读,出问题能看而不是猜),`resolve` 把插件声明的开关与用户值合起来,**没动过的开关保留插件自己的默认值**;界面上的开关一改就写盘并立刻推给包 —— 只改界面不推给包的话,值看起来生效了,而真正用到它的下一次请求没有。没配保存位置的场合直接报出来 |
| 检查器 | `MagpieRunner.setOptions` 把用户选择交给 Core,键是 `provider|option` —— 一张表里放着所有插件的开关,键里不写 provider 就会串到别家账号。界面上的开关列表还没做 |
| `MagpieCheckin` | 签到按钮与结果。词表固定(claimed/done/ineligible/inactive/captcha/failed),所以界面不解析各家措辞;`captcha` 明确引导用户去供应商自己的 App,**这里不解决验证码**;`done` 算成功,不是失败。签到结果那条提示与「操作失败」分开标题,免得用户以为出错了 |
| `MagpieModel` | 供应商自己列出的模型(id、显示名、上下文/输出上限、模态)。对话页优先用这份列表做选择;供应商不提供时**退回手填并说明原因**,而不是给一个空下拉让人以为「这家没有模型」 |
| `MagpieUsage` | Core 归一后的用量形状。**没有份额就不画进度条**,而是显示供应商自己的话(「No allowance reported」)—— 画成 0% 等于告诉用户「额度充足」,而真相是这家不说。有份额则画条并保留超过 100% 的超额 |
| `MagpieUsageView` | 用量页:套餐、账号、各窗口、重置时间、可下拉刷新;钱包类窗口显示余额数字而非比例 |
| `MagpieChat` | 一轮对话的读取器:Core 只会在被问时给出事件(gomobile 不能反向推),这里把它包成 `AsyncThrowingStream`,界面 `for try await` 即可;离开界面或停止时取消**Core 里的请求**,而不是让它在后台继续朝供应商跑。事件含文本、思考、done(带 token 用量原文)、error |
| `MagpieChatView` | 对话界面:模型名、输入、边到边显示回复、可停止。刻意只是一个「读回复」的界面:**没有工具调用,也没有多轮 agent 循环**,写成那样会暗示这些能力已经存在 |
| `MagpieProvidersView` | 「AI 供应商」标签页:列出已装包、版本、是否登录,可登录/重登/退出/卸载,并从文件夹安装。与漫画源完全分开:不同的包、不同的账号、不同的 Cookie |
| 列表成本 | 插件声明在安装时就记下(`MagpiePackage.specJSON`),刷新「AI 供应商」页不再为每个包启动一个 JavaScript 运行时;旧安装没有这份记录时退回一次求值。有一个用例:在**工厂必定抛错**的第二份视图上 `rows()` 仍然成功 |
| 压缩包安装 | 安装界面现在同时接受**已解开的文件夹**与下载来的 `.zip`/`.tar.gz`:解压交给 Core 的 `readPackageArchive`(剥一层顶层目录、拒绝符号链接与 `../`、限额一致),客户端只把 Core 给的文件表存下来。压缩包展开用一个**临时 Core**,用完即关,不会留下一个没人管的运行时 |
| `MagpiePackageReader` | 从用户选的**文件夹**读包:文件按包内相对路径取,符号链接直接拒绝(包是普通文件),单文件 8 MiB、总量 32 MiB、最多 1024 个文件——与 Core 的上限一致,但在这里就先判,免得把一个视频也一起拷进来。没有 `package.json` 直接说「不是插件」;有清单却指不到任何入口(`exports["./server"]`/`main`/`index.*`)也不算插件,和 Magpie 自己的拒绝规则一致 |
| `MagpiePackageStore` | 已安装的包:每个 provider 一份,文件按 **原文 base64** 存在同一个 JSON 里,列表里显示包自己的 `name`/`version`。重复安装会替换旧副本而不是叠加;没有 `package.json` 的东西直接拒收——那种包在加载时才会失败,理由也更含糊。索引文件先写临时文件再替换,写到一半崩掉不该让整张列表连同所有包一起打不开。解压不在这里:它只接受已经解开、且会被 Core 再验一遍的文件表 |
| `MagpieSignInView` | SwiftUI 登录页,两种登录都能走:**设备码**(显示验证码、可复制、打开授权页、等待、取消)与**密钥**(按插件声明的 `prompts` 渲染表单,密码字段用 `SecureField`)。密钥类在 `authorize` 当场返回结果,所以不会出现「我已完成,继续」这种什么也不做的按钮。登录只用该设备上这家供应商自己的授权,不经过漫画源,不共用漫画源的 Cookie |
| `MagpieRunner` | 装包(路径→字节,转 base64 交 Core)、把已存的登录信息交进去、跑导出函数、**把包刷新后写回的值再存一次**(否则下次启动就掉登录)、登出时关实例并删条目。装包只接受已经解开的文件表:解压归 Core,这一层不信任何没被 Core 校验过的路径 |

`MagpieRunner.Core` 是一个协议,而不是直接写死生成的 `MobileMagpie`:这样编排逻辑用 `StubMagpieCore` 就能测,不必等 xcframework。7 个新用例覆盖 base64 往返、无登录时不发送、刷新写回、空写回不覆盖、登出、装包失败,以及原文数字不被改写。

已接上真正的 `MobileMagpie`,`MagpieAccounts` 负责「每个 provider 一个 runner + 一份声明缓存」。**一处诚实的边界**:宿主协议目前没有流式方法,gomobile 又是拉取式的,所以 iOS 上回复会**整段到达** —— `MagpieChat` 是按事件流写的,界面也是增量渲染的,但第一批事件通常已经包含全部内容。要做到真正的增量输出,需要给宿主协议加一个流式回调(属于 Core 的 API 变更),这件事没有擅自定。
7. 需要拍板的一项:iOS 的 ATS。不少漫画源的图片地址是 `http://`,而 ATS 默认拒绝明文请求。桌面端由 Go 的 `net/http` 直接放行,移动端要么开 `NSAllowsArbitraryLoads`(放宽全部明文),要么只对必要的域名例外——这属于安全取舍,未擅自决定。

## 待你决定的事

有五件事不是工程问题,而是产品/安全取向:ATS 策略、Cookie 全局到分区的迁移、视频播放架构、是否随 Core 发布参考供应商包、以及一次真实账号的端到端验证。逐条写了现状、可选项与「不定时的后果」,在 Core 的 [docs/OPEN-QUESTIONS.md](https://github.com/laincat/VeneraCat-Core/blob/main/docs/OPEN-QUESTIONS.md) —— 客户端仓库不复制那份内容,免得两处各自过期。

## iOS 也能读某一层回复了(2026-11-01,pin `cf9eb9b`)

桌面端把「N 条回复」变成按钮之后,iOS 同步:「N 条回复」点了会用 `replyTo` 重读那一层,顶部显示「回复 X 的评论」和「返回全部评论」;回到线程本身时 `replyTo` 传空(Kit 层转成 `null`,源按 null 判断)。

**未验证**:回复层在真实源上通常需要登录才能读,所以这仍是语法/键核对,不当作已验证。

## iOS 评论也能赞了(2026-11-01,pin `cf9eb9b`)

桌面端加了点赞之后,iOS 还缺。这轮补齐:

- **Core**:`LikeComicComment(callID, key, comicID, subID, commentID, isLike)` —— 与桌面端同一契约,**传 `false` 就是取消赞**,不是另一个函数。
- **Kit**:`likeComment(...)`;是否显示按钮由 `CommentSupport.like` 决定,界面不自己猜。
- **界面**:每条评论带「赞 / 取消赞」,点完重新读当前页(源可能只在下一读里给新赞数),投票期间禁用避免连点。

**活体验证边界**:`ccc`、`zaimanhua` 确实声明了 `likeComment`,但它们的评论列表要登录才能读,所以 iOS 这侧仍是**语法/调用名/键核对**,投票端到端需要真实账号与真机。

## iOS 也能打开粘贴的链接了(2026-11-01,pin `c414709`)

上一轮只做了桌面端。这轮把同一条能力带给手机:

- **Core**:`LinkDomains` / `LinkToID` / `OpenLink`。`comic.link` 是对象,用 `Runtime.Value` 读属性 —— 当函数调用只会得到「source does not define this function」。没有任何源认得该地址时返回空 target,**不是错误**,客户端据此回退成关键词搜索。
- **Kit**:`openLink(_:)`、`linkDomains(key:)`、`LinkTarget`;`looksLikeLink` 放进 Kit 的 `LinkDetection`,因为它是纯逻辑、可测,而放在 App target 里测试根本看不到。
- **界面**:搜索提交时先判地址:像地址且被某个源认得 → **直接打开那部作品**;否则照常搜索。`12.5`、`v1.2` 这类带点的关键词不会被误判成地址,否则每次搜索都白跑一轮源调用。

键核对新增 `LinkTarget`(现 14 个 payload)。

**未验证**:iOS 仍是语法、调用名与键核对;没有 Mac 编译与真机。

## iOS 标签可点了(2026-11-01,pin `0c721f3`)

上一轮记的缺口在这轮补上:详情页的标签不再是纯文本。

- **Kit**:`clickTag(key:namespace:tag:)` 返回 `TagAction`(action / keyword / param);空 action 表示源没意见,**不是失败**。
- **界面**:标签变成按钮(源没声明 `onClickTag` 时仍是文本)。源说「搜索」→ 打开 `SourceSearchSheet`(单源搜索结果页,支持页码与游标翻页,点进详情);源说「分类」→ 打开分类页并**选中源点名的那个参数值**;两者都不是 → 明说这个源没给「X」该做什么。
- **分类参数定位**:`CategoryPart.param(forValueAt:)` 与 `CategoryModel.paramTarget` 复刻加载器的同一条规则(逐值参数 → `groupParam` → 值本身)。

**自查抓到一处静默漏洞**:`ComicDetails.subId` 一直声明着、却**没写进 `CodingKeys`,也从未解码**,于是评论线程永远拿空串去定位作品。已补上解码,并加测试确认数字型 sub id 也能变成字符串。

**未验证**:仍是语法、调用名与键核对;没有 Mac 编译与真机。

## pin 到 `0c721f3`:Core 提供标签点击语义,iOS 还没接(2026-11-01)

Core 新增 `ClickTag`,把「这个标签对源意味着什么」交给客户端:搜索词,或分类参数,或空 action(源没意见)。**iOS 这轮只跟 pin**:标签目前仍是纯文本,点击后什么也不会发生。桌面端已能按源指的分类参数跳转。

## iOS 也有评论区了(2026-11-01,pin `8c5d0de`)

上一节之后桌面端加了评论,iOS 没有。这轮补上:

- **Core**:`CommentSupport(key)` 报告源声明了 load/send/like 哪些;`ComicComments(...)` 把线程归一化成 `{comments,maxPage}`(数字 id / 分数保持可读文本,字符串 replyCount 转成数字,没有 id 的评论仍然是评论);`SendComicComment(...)`。形状用具名类型,这样才能进键核对。
- **Kit**:`commentSupport` / `comments` / `sendComment`;`ComicComment` 给没有 id 的评论一个稳定 `identity`,否则 SwiftUI 列表无法区分两行。
- **界面**:`ComicCommentsView` —— 列表、翻页、回复某人、发送、刷新;`ComicDetailView` 只在源声明了评论时显示「评论」入口(`commentSupport` 与详情一起读一次,不放进视图 body)。`ComicDetails` 补上 `subId`。

键核对新增 `ComicComment` / `CommentSupport` / `TagAction`(现在 13 个 payload),负向验证把 Swift 的 `replyCount` 改名 `replyTotal`、把 `TagAction.keyword` 改名 `searchTerm`,门禁都点名该键并以 1 退出。

**未验证**:iOS 侧仍只有语法、调用名与键核对;没有 Mac 编译,也没有真机。

## iOS 的浏览页改用 Core 的共享实现(2026-11-01,pin `c855fd3`)

上一节记的缺口在这轮修掉了:浏览页的**形状归一化**(四种类型 + `load`/`loadNext` 回退)移进 Core 的 `comic/js`,桌面端与 iOS 都只调用它,不再各自拼 `explore[i].load`。

- **Core**:`js.Runtime.Explore` 统一四种形状并处理游标;`mobile.ComicExplore(callID, key, index, page, cursor)` 交给手机端。两处都有单测(形状、游标回退、越界索引)。
- **Kit**:`explore(key:index:page:cursor:)` 走 `comicExplore`,不再自己拼路径;`ExploreResult.next` 带回游标。
- **界面**:游标式浏览显示「第 N 批」而不是编造总页数;「上一页」在游标式下隐藏 —— 游标只向前发,回退需要另存历史,现在没有。

**没有验证的**:iOS 侧仍是语法与键核对,没有 Mac 编译,也没有真机。

## iOS 的浏览页对游标式源仍是坏的(2026-11-01,pin `110b0d8`)

桌面端查出 `ehentai` 三个浏览页全不可用(它只声明 `loadNext(next)`,客户端只调 `load`),Core 里已修「无 UI handler 时无返回值的 UI 调用不该报错」。

**但 iOS 这轮只跟 pin**:`CoreClient.explore` 是自己拼 `explore[i].load` 路径的,没有走 Core 的游标回退,所以对 `ehentai` 这类源仍然会失败。这是已知缺口,不是"已修"。

## iOS 面板在同样场景下也会是空的(2026-11-01,pin `7019844`)

桌面端补了「Core 侧失败也入日志」之后回头看 iOS:mobile 层的 `CallComic` 失败**同样一句话都不记**。也就是说 `baozi` 返回 403 这类最常见的失败,iOS 的面板会跟修之前的桌面端一样空着。

- `CallComic` 在源不存在或调用失败时,记录「源 key + 调用路径 + 原因」,与桌面端同一个形状。
- 负向验证做了:把那处 `if err != nil` 改成 `if false`,测试立刻失败;改回即通过。

## iOS 也有源日志面板了(2026-11-01,pin `02edab3`)

上一节说"iOS 日志面板还没做",这轮补上:

- **Core**:`LogLines()` 返回最近 400 行的 JSON(带源 key 与毫秒时间戳),`ClearLogLines()` 清空。空缓冲返回 `[]` 而不是 `null` —— 客户端是按数组解码的,`null` 不是数组。宿主仍然会收到每一行,所以已有的控制台输出不丢。
- **Kit**:`logLines()` / `clearLogLines()`;新增 `SourceLogEntry`。
- **界面**:漫画源页菜单里「源日志」→ 列表(时间、源 key、标题、正文;error 红、warn 橙)、「复制全部」(直接可贴进反馈)、「清空」、下拉刷新。

门禁新增两条能力路径,并把 `mobile.LogEntry ↔ SourceLogEntry` 加进键核对(现在 10 个 payload);负向验证把 Swift 的 `time` 改名为 `when`,门禁报出具体键名并以 1 退出。

## pin 到 `ab719fb`:Core 把源日志按源归属(2026-11-01)

Core 新增可选的 `Services.LogSource`(带源 key),并保留最近 400 行给客户端展示;桌面端已有「源日志」面板。**iOS 这轮只跟 pin,日志面板还没做** —— 同一条日志在 iOS 上目前仍只进控制台。

## pin 到 `a93ac09`:base64 容忍传输产物(2026-11-01)

Core 现在解码前会去掉 UTF-8 BOM 与 ASCII 空白。触发点是一个真实源的域名列表接口开始返回带 BOM 的 base64,导致该源 init 崩在 `null.length`,自己的兜底列表从未执行。iOS 只跟 pin。

## 键核对扩展到备份计划(2026-11-01)

iOS 导入这轮才开始读 `entry.data`:如果 Core 那边的键名与 Swift 对不上,后果和这次修的 bug 一样 —— 静默地什么都不写。`check-json-keys.py` 的对照表新增 `backup.Plan ↔ BackupPlan`、`backup.SourceRestore ↔ BackupSource`,现在覆盖 9 个 payload。

负向验证做了:把 Swift 里的 `data` 改名后,门禁报出「BackupSource reads "sourceDataRenamed", which Core's SourceRestore never sends」并以退出码 1 结束;复原后回到 ok。

## pin 到 `9013ca5`:导出不会写出自己读不开的文件(2026-11-01)

Core 的写端原来只校验脚本大小,不校验 `comic_source/<key>.data`;而读端对每个 `comic_source/` 文件都有 16 MiB 上限。现在写端用同一上限,超限直接拒绝并点名源。iOS 这里只跟 pin,没有界面改动。

## iOS 导入原来根本没写源数据(2026-11-01)

桌面端修好 `.data` 之后核对 iOS,发现更严重的一处:**`BackupImporter` 从头到尾没有读过 `entry.data`** —— 导入的源只有脚本,数据与设置全丢,而且没有任何提示。桌面端至少还会写数据。

现在:

- **导入**:源装好后调用 `restoreValues`,按源声明的 `settings` 键分流 —— 声明过的写设置桶,其余写数据桶。**装失败就不写**:猜一个桶等于把令牌放进设置面板。
- **导出**:`SourceStore.allValues(key:)` 把两个桶合并成归档要求的单个对象,同名时数据优先。
- 导入结果多一行「源数据 N 项」,不把成功说成空。

测试钉住 `allValues`:设置键出现、数据键覆盖同名设置键。

## 导出也带上源自己的数据(2026-11-01,pin `e46c8f9`)

上一版只导出脚本,恢复后源是"登出且不知道自己在哪个域名"的状态。归档格式里另有 `comic_source/<key>.data`。

- Core 不能枚举宿主的 store,所以 `ExportBackup` 多一个 `sourceDataJSON` 参数,形状是 `{"<key>":{"<name>":<value>}}`。
- Kit 的 `exportBackup(searchHistory:sourceKeys:)` 用 `SourceStore.allData(key:)` 逐源收集;新增的 `allData` 返回该源整个数据对象的 JSON 文本(空源是 `{}`)。
- 界面把 `library.comicSources.map(\.key)` 传进去。

新增测试钉住 `allData` 的形状:键顺序、大整数 `12345678901234567890` 原样保留、没有数据的源返回 `{}`。

**仍不带走**每个源的**设置**(与数据分属两个桶);合并会在导入时把设置写进数据桶,不是修复。

## iOS 也能导出备份了(2026-11-01,pin `36707d5`)

上一节说"iOS 导出界面还没写",这轮补上:

- **Core**:新增 `ExportBackup(historyJSON)`。**返回 base64 字符串而不是 `[]byte`** —— 这里每个方法都是以字符串过桥,Swift 侧的绑定形状是已知的;`[]byte` 返回值会是一种没人验证过的形状,而这台机器上没法确认 gomobile 怎么导入它。客户端再解码回 `Data`。
- **Kit**:`exportBackup(searchHistory:)` 接受任意 `Sequence<String>`,把 Core 的 base64 解回 `Data`;不是 base64 就报错,而不是写一个空文件。
- **界面**:漫画源页的「导入备份」菜单里多了「导出备份」:取已装源 + 本机搜索历史(**倒序**,与归档的"最旧在前"一致),写到临时目录的 `nekularity-<时间戳>.venera`,然后弹分享面板(Files / 邮件都行)。

Core 侧测试覆盖:导出后用自己的读取器回读,确认源 key 与脚本正文都在、搜索历史顺序正确、压缩包里**没有** `cookie.db`,以及历史不是数组时报错。

## Core 能写 .venera 备份了,pin 跟上(2026-11-01,pin `ffdfbe7`)

Core 新增 `backup.Write`(源 + `appdata.json`,固定键顺序,两次导出逐字节相同);桌面端已有「导出」入口。**iOS 这轮只跟 pin,导出界面还没写** —— 这也是本轮唯一的 iOS 侧改动,不夸大。

## 核对「解码的键 Core 到底发不发」(2026-11-01)

前面几轮反复遇到的同一类问题:Core 改了字段名或干脆不发,目标端**解码不报错**,只是字段永远是 `nil`,界面上表现为"少了点东西"。这种失败没有任何一处会报警。

`scripts/check-json-keys.py` 补上这一段:按类型一对一对比较 —— Core 的 Go 结构体 `json` 标签 vs Kit 里那个类型的 `CodingKeys`(没有就取它**自己的**存储属性)。比的是**双向里的危险方向**:Kit 读了 Core 不发的键。

写这个检查本身踩了三个坑,都修掉了:

- 第一版按文件抓 `CodingKeys`,结果抓到了**嵌套类型**的键,把漫画的 `id`/`tags` 当成分类页的键,报了 41 条假问题。
- 第二版落到属性名,又把**计算属性**当成了字段(`id`、`isRandom`、`isMultiSelect`)。
- 第三版仍然把**嵌套结构体**(`SourceSetting.Option.value`)算进来 —— 改成只取类型体第一层的存储属性。

现在 7 个 payload 全部一致。负向验证:把 `groupParam` 改名成 `groupParamRenamed`,脚本点名 `CategoryPart reads "groupParamRenamed", which Core's CategoryPart never sends` 并退出 1;恢复后回到 `ok`。已接进 `verify-ios.sh`(Core 不可用时 SKIP)。

**边界**:它只比较列在表里的 7 对 payload,也只看键名不看类型;漫画自己的 `tags`/`chapters` 来自源脚本而非 Core,不在比较范围内。

## 参数个数审计:34 个源逐个比过(2026-11-01)

上一轮那个 `favoriteId` 是"源声明了 4 个参数、我们只传 3 个"造成的静默失效,所以这轮把同类比对做了一遍:把 34 个官方源里我们**调用**的方法签名抽出来,和客户端实际传的参数个数逐个对照。

| 方法 | 源声明 | 客户端 |
| --- | --- | --- |
| `comic.loadEp` | 34 个源全为 `(comicId, epId)` | 2 个 |
| `comic.loadInfo` | `(id)` | 1 个 |
| `search.load` | `(keyword, options, page)` ×30、`(keyword, _, page)` ×2 | 3 个 |
| `categoryComics.load` | `(category, param, options, page)` ×26、`(category, params, options, page)` ×4 | 4 个 |
| `explore[i].load` | `(page)` 或 `()` | 1 个 |
| `favorites.loadComics` | `(page, folder)` ×13、`(page)` ×1 | 2 个 |
| `favorites.addOrDelFavorite` | 3 或 4 个参数 | 4 个(上一轮修) |

两处看着可疑、查过之后**不是**问题:

- `categoryComics.load(category, params, …)` 里的 `params` 是**复数写法而已**,源内部做的是 `params.split('@')`,传单个字符串就对(`baihehui`、`goda`、`mh1234`、`mh18`)。
- `ehentai` 的 `onImageLoad(image, comicId, epId, nl)` 第 4 个参数是**源自己生成、只在它自己的重试闭包里回传**的令牌;客户端传 `undefined` 是对的,重试走源自己的 `onLoadFailed`。

另外把 iOS 分类选项补成了**支持多选**(值以 JSON 数组字符串传,和搜索一致)。需要说明:官方源里**没有**哪个在 `categoryComics.optionList` 用 `multi-select` —— 两处 `multi-select` 都在 `search.optionList`,而搜索筛选两端本来就支持。所以这是**防御性补齐,没有对应的真实缺口**,不能算修复。

## 删除收藏要带源自己的句柄(2026-11-01)

与桌面端同一处修正:iOS 这边也补上 `favoriteId`。`Comic` 与 `ComicDetails` 现在都解析 `favoriteId`,`setFavorite` 始终传第四个参数(有句柄传句柄,没有传 `null`)。

原因值得单独记:`wnacg` 的删除 URL 是 `users-fav_del-id-${favoriteId}.html`,少了句柄就打到 `del-id-undefined`,**返回 200、源也返回成功**,看起来删掉了其实没有。这类失败比报错难发现得多。

## 收藏到源:详情页也能加能删了(2026-11-01)

与桌面端对齐:详情页在本地书架之外多一个「收藏到源」。源支持多收藏夹时给文件夹选择,已在该收藏夹时按钮变「已在源收藏」,再按一次移除;源抛的错误按原文显示。本地书架与源收藏是两份数据,各有各的控件。

只声明了收藏夹切换、没有列表接口的源(`ehentai`)不出现在这里 —— 加进去也没有地方能看见。单收藏夹的源传 `nil` 而不是空串。

Kit 新增 `setFavorite(key:comicID:folder:adding:)`;能力门禁 `scripts/check-capabilities.sh` 也加上了这条路径。

## 离线核对「Kit 调用的 Core 方法是否存在」(2026-11-01)

这台机器上没有 Mac,`MobileCore` 的桥接层要 `fetch-core.sh` 在 Mac 上构建出来才存在,所以 Swift 里写 `core.categoryComics(...)` 这种**根本不存在的调用**,在编译前无任何反馈 —— 只有等 Mac。

`scripts/check-kit-core-calls.py` 补上了这一段:它从 Core 源码的 `mobile/*.go` 解析 gomobile 导出的方法名(`func (c *Core)` 与 `func (m *Magpie)`),再从本仓库解析 Kit 自己声明的方法(因为 `core` 在 Kit 里也可能指 `CoreClient`),然后核对每个 `core.xxx(` 调用是否落在已知集合里。Core 不可用时退出码 3,`verify-ios.sh` 当作 SKIP 处理。

**它只比名字,不比签名** —— 参数类型仍然只有 Mac 能查。这已经能抓住实际会发生的错误:方法从未存在、或被改名。负向验证:把 `hasComic` 改成 `hasComicGone`、把 `categoryComics` 改成 `categoryComicsTypo`,脚本分别点名文件、行号与调用名并退出 1;恢复后回到 `ok (69 calls against 277 known names)`。

## 「源声明了、客户端没接」现在会被门禁抓住(2026-11-01)

前几轮反复出现的同一类问题:源在脚本里声明了某个能力(`category`、`ranking`、`account`、`favorites`、`translation`),客户端读不到,症状只是**一个空屏或一个英文键名**。每找到一处都要回头重读契约,靠人眼。

现在两端各有一个 `scripts/check-capabilities.sh`,按能力列出「Core/Kit 的入口 + 界面入口」,用**固定字符串**匹配(避免重命名后靠前缀继续通过),任何一条路径消失就失败。iOS 这边接进了 `scripts/verify-ios.sh`(Mac 上跑的那条),桌面那边接进了 `scripts/check.sh`。

负向验证做过:把 `favoritesView` 改名、把 `"favorites.loadComics"` 改名、把 `accountSection` 改名,脚本分别报出对应能力缺失并非零退出;恢复后回到 `ok`。

它只保证**路径还在**,不保证行为正确 —— 行为仍靠活体测试与截图。

## 源自己的收藏:两端都接了(2026-11-01,pin `f8ec81a`)

`favorites` 是源在**它自己那边**保存的收藏,与本地书架是两回事。三种形状实测互不相同:`nhentai` 单收藏夹、有列表、无收藏夹列表;`ehentai` 有收藏夹、有收藏夹列表、**但没有列表接口**;`wnacg` 三样都有。

- **Core**:新加 `Value` 读**数据**(`favorites.multiFolder` 是数据,`Call` 只调函数),以及 gomobile 的 `ComicValue`。
- **Kit**:`FavoritesSupport{supported,multiFolder,folders,canLoad}` 由声明路径 + `multiFolder` 推出;`favoriteFolders` / `favoriteComics` 按源的要求传参(单收藏夹的源**不传**收藏夹 id)。
- **界面**:源详情页多一个「源收藏」。能列出的显示收藏夹与列表;`ehentai` 那种只有收藏夹没有列表的,明说「这个源没有提供收藏列表」,**不去调用不存在的函数**;未登录时显示**源的原文**并给重试。

## 界面文字按源声明的翻译表显示(2026-11-01,pin `239221b`)

源可以把自己的界面文字写在 `translation` 表里,设置项只写键名(`title: "domain"`)。iOS 现在也读这张表:`CoreClient.translations(key:)` 取当前 locale 的映射,源设置页的标题走 `model.title(setting)`,取不到才退回键名。Cookie 字段名不翻译 —— 那是 Cookie 名。

## 源账号:两端都接了(2026-11-01,pin `8d2e9db`)

15 个官方源声明了 `account`,而且是**三种**不同方式:账号密码、网页内登录、Cookie 字段。桌面端按声明画面板(见桌面仓库的 `docs/STATUS.md` 表格与实测);iOS 现在也有了:

- **Kit**:`AccountStyles{password,webview,cookies,logout}` 由 `accountStyles(key:)` 用 `hasComic` 逐条探测得出,不做猜测;`accountCookieFields` 走 Core 新加的桥接入口(Cookie 名单是**数据**,`CallComic` 到不了);`loginAccount` / `loginWithCookies` / `logoutAccount` 走现成的 `CallComic`。
- **界面**:源设置页顶部多一个「账号」区 —— 密码方式给账号/密码/登录/登出,Cookie 方式按声明的字段逐个输入框 + 「校验并保存」,由源自己的 `validate` 判断;源抛出的错误按原文显示;只提供网页内登录的源(`nhentai`)当时只能写明「iOS 端暂不支持」——**这一条后来补上了**,见下面「网页内登录与源 API 级别」一节。源不需要账号时这一区根本不出现。

Core 这轮发布 `8d2e9db`(新增 `AccountCookieFields` 桥接入口),pin 跟到它 —— Core 是单提交历史,旧 pin 会被替换。

## 排行页也接上了(2026-11-01,pin `c22a944`)

源的 `enableRankingPage` 配 `categoryComics.ranking` 是**另一个独立入口**,九个官方源都有,之前两端都没读。现在 Kit 的 `CategoryPage.ranking` 带着一份扁平选项表(`RankingOption{value,label}`),`CoreClient.rankingComics` 调 `categoryComics.ranking.load`;分类界面多一行「排行」,选中后走同一套列表和分页(`rankOption` 记住当前是排行、维度还是随机搜索)。

Core 侧这轮也发布了 `c22a944`,pin 从 `26dc9a7` 跟上 —— **注意 Core 是单提交历史,旧 pin 会被替换掉**,不更新就等于指向一个不存在的提交。

## 分类浏览:界面已接,Mac 上还没跑过(2026-11-01,pin `26dc9a7`)

桌面端早就能读源的分类页,iOS 一直没有,因为桥上没有入口。这轮补了三层:

- **Core**:`mobile.Core.Category`(返回 `{"title","parts":[...],"options":[...]}`,与 `SearchOptions` 同形,客户端可以复用筛选代码)与 `mobile.Core.CategoryComics`(按 `callID` 可取消)。没有分类页的源返回 `{}` 而不是报错。Core 已发布,两个客户端的 pin 一起更新。
- **Kit**:`CategoryPage`/`CategoryPart` 与 `CoreClient.categoryPage` / `categoryComics`。取值该映射成什么参数由这里决定,顺序是「每个取值自己的参数 > 维度的 `groupParam` > 取值本身」。
- **App**:「浏览」页里,源声明了分类页就会多出一个「分类」标签,进去后每个维度一排取值、点选项重载、分页;`random` 维度的按钮是「随机一个标签」,取**一个**取值去搜索 —— **不经过分类加载**,也不拼多个标签:源里的 `randomNumber` 是「同时显示多少部」,而漫画搜索把多个标签当「同时满足」,`nhentai` 实测拼 10 个就是 0 部、拼 20 个被站点拒绝。

`scripts/check-swift.py` 报的 77 个文件全部可解析;同时修掉一个**在 main 上就一直失败**的门禁:`MagpieUsage` 里有个属性叫 `each`,tree-sitter 把它当成参数包关键字,于是 `each = try …` 被读成语法错误。检查器现在把 `each` 按标识符处理(参数包在本仓库没有用到),门禁从「1 个问题」回到「79 个文件全部可解析」。

**边界**:`swift build`、单测与 App 构建都还没在这台 Mac 上跑过,所以这只证明「语法可解析、逻辑已按 Core 契约写好」,不证明编译通过。真机上的分类页、random 搜索也都没有验证证据。

**网页内登录与源 API 级别:iOS 原本既装不上官方源,也点不了网页登录(2026-11-01,pin `9701b58`)**:两件事都在这轮补上,而且都是先复现再改。

1. **源 API 级别**:客户端把**自己的版本** `0.1.0` 当成源 API 级别报给 Core,而所有官方源都声明 `minAppVersion = "1.0.0"` 以上,于是 Core 一律拒绝 —— `js: invalid source: minAppVersion 1.0.0 is required`,源列表永远是空的。桌面端早已把两者分开(`internal/sourceapi.Level = 1.6.3`),iOS 现在也这样:级别放在 Kit 的 `SourceAPI.level`,并有三条单测固定行为 —— 报出的级别能装官方源、应用自身版本不能、要求 `9.0.0` 的源**仍然**被拒(级别是有边界的声明,不是绕过检查)。

2. **网页内登录**:`nhentai`、`ehentai`、`ccc`、`mycomic`、`manga_dex` 声明 `account.loginWithWebview`,两个回调是函数、跨不了语言边界,所以 Core 用 handle 命名它们。iOS 新增 `WebviewLoginSession`(非持久 WKWebView,避免看到别的源的会话)与 `WebviewLoginView`:每次导航后问源自己的 `checkStatus(url, title)`,成功后只把**登录站点自己**的 Cookie(开始页与结束页都算)导入该源分区,再跑 `onLoginSuccess`。

同一轮里还修掉:登出按钮原本嵌在密码方式分支里,`nhentai` 这种纯网页登录源无法登出;`type: "callback"` 的设置项原本显示「源内的操作,客户端暂不支持」,现在会按源给的 `buttonText` 画按钮并真正执行。

验证边界:这些 Swift 代码在本机(Windows)没有编译器,只能离线核对语法、Core 调用名与 JSON 键;编译、单测与模拟器运行由 Mac 侧执行,结果单独记录。
