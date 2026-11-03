# 待验证清单

[English](UNVERIFIED.en.md) | 简体中文

**新 pin 的 Mac 真 HTTP 组合验收(2026-11-03)**:Orca Worker mac-validate-2 在 Nekularity `d3672a8`/Core `3be57b5` 上,经真实 URLSessionTransport→CoreHost/CoreStreamHost→gomobile CoreMagpie→loopback HTTP 完成 1 test/1 suite。模型目录、尾部释放前首段「第一段 」到达、取消后同一请求 ID 3 的 peer_closed、SavedAuth 原样保存到临时文件并重建实例后完整回答「第一段 第二段🐾」均通过;刷新总数为 1,四个供应商请求均授权且无 Cookie。SDK 来自精确干净 Core 检出,macOS 切片 SHA-256 24c00ca89b47cd80529063924f56d6a39f5304481174dca12712d0115e71f366。

定向日志 `/tmp/nk-d367-acceptance/evidence/acceptance-test-02.log`,事件 `events-final.json`,SDK 来源 `sdk-identity.log`;Lead 汇总 `E:/Temp/nk-3be-candidates/mac-http-acceptance.json`。第一次仅测试代码编译失败(Thread.isMainThread 的 Swift 6 异步上下文限制),修正后通过;产品 Sources/ 无差异。未运行本轮 503、完整 Kit、App 构建、iOS UI 或 Keychain 验收。CI 41661859155 现已在精确 d3672a8 上成功:Core 构建、Kit 单测执行、App 与 UITests 编译、IPA 打包均通过。2026-11-04 下载核对未签名 IPA 29,455,876 bytes,SHA-256 7590d8ebcdf67b4fed8bd191e187f0337ba144cde6baf7f5fe033229fcd4f77c;App/Widget 均为 0.3.2/14,最低 iOS 26.0,App 二进制含 Core 3be57b5 pin。artifact 摘要与两层 ZIP CRC 通过,回执及日志 `E:/Temp/nk-ios-d367-ci/receipt.json`、`verify.log`。UI 在该 CI 中仅编译,未执行;发布步骤跳过,未更新 AltStore,不代表真机或 iOS 界面已验。

**Magpie 本地 HTTP 夹具(2026-11-03)**:新增 `scripts/fixtures/magpie-http/`，包括仅绑定 127.0.0.1 的服务与可导入供应商包；支持模型目录、假凭据刷新、可扣住后半段的 SSE、指定请求释放、对端关闭和 HTTP 503。Lead 使用发布 Core `3be57b5` 的公开 mobile Magpie API 经真实 HTTP 验证：首段先于正文完成、取消令服务端观察到 peer_closed、SavedAuth 文件保存后重建实例继续可用且刷新次数保持一次、Unicode 回答与错误传播均通过。包内文件也经 ReadPackageArchive/LoadPackage/Auth 核对。日志与 ZIP 在 `E:/Temp/nk-magpie-http-evidence/`，使用方法见 [夹具说明](../scripts/fixtures/magpie-http/README.md)。这是 Windows Go 宿主的接口验收，不是 Swift URLSession、Keychain、App 重启或 iOS UI 通过；main pin 仍为 4f213ff，后续客户端需自行保存刷新结果并真实重启读取。

**Core 发布与消费端候选更新(2026-11-03)**:Core main 已发布 `3be57b5`,功能源码与通过 CI `41631619233` 四个作业的 `6129f59` 相同,保树收拢回执见 `E:/Temp/core-stream-release/publish-receipt.json`。新的独立 pin 候选为 Nekularity `ea87eb5` 与 Nekophage `f7b99d1`,均指向 3be57b5;桌面七项检查与实际二进制版本核对通过,iOS 候选 `ea87eb5` 的 Mac CI `41638119772` 通过 Kit 单测、App 与 UI 测试编译;下载的未签名 IPA 的 SHA-256、ZIP CRC、App/Widget 0.3.2/14、最低 iOS 26.0 和 Core marker 已核对,UI 未执行。Swift 提前响应头候选 `65eba9f` 的 CI `41635149850` 在 Kit 单测失败;后续 `77c2c6` 的 Mac 定向三项断言也失败,首个结束原因正在诊断,尚未并入新 pin 候选。Core 可在响应头提前交付的宿主上增量返回文字,但旧客户端宿主仍延后,标准 AI 页面仍整包;新 pin 的窗口、Mac 消费端、UI 与真机结果不能借用旧版本。两端 main pin 均保持 4f213ff。

**桌面主线整合(2026-11-03)**:先前把 Nekophage 工作分支称作 main 的口径已更正;整合前真正 main 为 `28be4bd`/Core `214e778`,核对日志 `E:/Temp/core-magpie-first-chunk-evidence/desktop-main-ref.log`。现已将 `fix/subtitle-record-cap` 快进整合为真正 main 的 `67fc877`,pin 为 `4f213ff`,原分支保留;同时带回 WebView 探针隔离修复并移除误入版本控制的 Python 缓存。七项检查与 Windows 隔离阅读回归通过:两页解码、双页、55% 进度、重开恢复 1200,仅有本次章节存储键。回执 `E:/Temp/nk-desktop-integration/receipt.json`。`a079ce7`/Core `b55c1a4` 的 Windows 包仍属于独立候选,新 pin 的 macOS 消费端尚未验收;Nekularity main 仍 pin `4f213ff`。

**标准接口 HTTP 错误修复已过 Mac Kit 回归,页面待验**:`bb77b5d` 已经 `9af6148` 整合 main,Orca Worker 的四条定向测试与全套 425/78 suites 通过,恢复旧实现的负向对照使两条错误用例失败。Windows loopback 夹具和 Mac URLProtocol 测试各有证据,不替代页面真实 HTTP/UI 结果。地址候选 `ad8e191` 已有 Mac 回执,模型目录仍失败,根因未证实。详见 STATUS。

**标准接口输入与请求配置仍有分歧**:`ad8e191` 已经 Mac 编译,Orca Worker 报告五个显示/清空/重启读回用例通过,但模型目录仍报 `no host`、夹具 0 请求;后续回答/取消/错误态未验收。离线 plist 读值与应用读回不一致,根因待逐层字节对照,不能认定是滞后快照。Lead 的同 pin Go 边界复现区分了完整地址、单斜杠和 `/v1` 三种输入,见 STATUS。

**此前 b55c1a4 的候选验收记录**:Core `b55c1a4` 已整合真实连接取消修复,两端候选为 iOS `b39e6b0`、桌面功能源码 `a079ce7`,main pin 未变。新 pin iOS CI/IPA 已通过,但 UI 未运行;Windows 安装版本地 HLS、字幕、跨进程续播、鉴权与 Range 已验收,macOS 新 pin、音频/真机仍待验收。Magpie 传输虽收到分块,插件文字仍等到正文结束才交付,已在 loopback 复现,不能声称界面流式。详见 STATUS。

**Magpie 聊天取消已修复,但未进客户端**:`2c9c83b` 的 `ChatCancel` 原先只删句柄,阻塞中的 `Host.HTTP`/`StreamOpen`/`StreamNext` 不会停止;分支 `fix/magpie-chat-cancel` 让每个聊天独立运行时并关闭它,五条定向 race 与带夹具的全套(22 包、559 PASS/0 FAIL/1 SKIP)通过。证据在 Windows 假宿主,不是 iOS UI、真机或真实供应商;两端 pin 未变。

**标准接口取消修复已过编译与单元回归**:`77b969f` 的代码已整合 main,Mac Kit 421/77 suites、五条定向回归、App/UITests 编译通过;负向对照与日志见 STATUS。标准接口页面的真实 HTTP/界面闭环、真实账号与网络首块时序仍未验证,当前路径仍整包返回。已发布 v0.3.2 不含该修复。

**发布已核对,真机仍待验**:`v0.3.2` 发布 CI `41578147149` 13 步全成功;IPA 下载 HTTP 200、29,418,522 字节、SHA-256 `f59afe889def90131a8994a59a92571b6acc823679431d37c16c032f29bc8737`,包内 App/Widget 均为 0.3.2/14、最低 iOS 26.0,并含 pin `4f213ff`(旧 `8e14aad` 已不在包内)。AltStore `468761a` 的稳定轨道与扁平首版均为 0.3.2/14,图标 200、IPA 分段 206,cnb 镜像与 release 入口已生效;首次核对时 `raw.githubusercontent.com` 仍回 0.3.1,约 12 分钟后已是 0.3.2,属 CDN 缓存滞后(三个入口现均 0.3.2)。CI 整体日志下载被插件地址安全校验拒绝,未绕过,故 CI 结论只依据 job/step 状态。合并树 `9498b4c` 的 Mac 验收(416 单测/76 suites、完整 UI 27/0/0)见 STATUS。真机、后台/锁屏、PiP、Live Activity 与真实账号仍未验收。

**历史回执已核全**:`1888cd3` 完整 UI 为 27/0/0,`ed09c82` 为 416 单测和两条下载 UI 通过,`61197f8` 的搜索正向通过、故意破坏后 FAIL、恢复后再通过。三项按各自提交记录,合并候选现已另有 `9498b4c` 的整包通过证据。三张旧 CA 已按指纹移除,仍保留 `1888cd3` 新 CA `C0E33FBD155EF2C9…`(2026-12-03 到期),不宣称测试信任库全空。

**下载离线索引与重试已过单元回归**:`2d9f555` 在 macOS 上 2/2 与 398/398 通过,`7550c12` 再以 4/4 新用例与 402/402 全套通过,`920b94a` 以 6/6 写盘用例(连续 4 轮)与 404/404 全套通过,`b3860ea` 以 7/7(连续 4 轮)与 405/405 全套通过,`afe1259` 以 8/8(连续 4 轮)与 406/406 全套通过,`9f15203` 以 9/9(连续 4 轮)与 407/407 全套通过。只覆盖临时目录、manifest 与注入闭包,未在真机、下载界面或真实网络验收;失败后重试的界面入口已有模拟器用例(`6037f6a` 上连跑两次、起点均为已下载脏状态,均通过),它跨启动同样有效(`0.3.1`):请求与原因写进 `failures.json`,重启后仍可重试,重试用 App 的 `fallbackFetch`;失败行也能单独 swipe 删除。仍未验证的是真机、后台与真实网络下的同一条链路。下载的功能边界也要写明:中断的章节从第 1 页重来(没有断点续传),排队中的任务不跨 App 重启保留,后台/锁屏时的下载与 Live Activity 未做验收;重开后不会被引用到的半成品目录会被清理,而不是续用。

**界面改动已执行、视觉矩阵后置**:`5f15769` 的 Mac App/UITests 构建与完整 UI 26/26 通过;`81eb017` 构建及三个定向交互用例通过,但其完整套件未跑。明暗窄宽屏、方向正确的三列截图、动态字体与减少动态效果仍未验收,大字体截断问题已知且未修复;这些属用户要求后置的界面工作。下述 24/24 与发布记录属于更早提交,与本轮分开。

更新:2026-11-03。最新已核完整 Mac UI 回归为 `9498b4c`:27 PASS / 0 FAIL / 0 SKIP,日志 `/tmp/nk-949-evidence/full-ui.log`,与三类明细和 xcresult 摘要一致。较早 `1888cd3` 的同计数属于它自己的执行记录。以下 `95818c5`(0.3.1 构建)结果保留为历史:干净起点上 **27 例 / 23 通过 / 4 跳过 / 0 失败**,日志 `/tmp/nk-95818c5-ui-fullsuite.log`。该轮 4 条跳过全是前置条件:视频源与 HTTPS 夹具/测试 CA 缺失。其后视频用例用新五源种子单独通过(28.276 秒),主题三例在 `17ba4c5` 夹具上单独 3/3 通过;该轮计数仍保留为 23/4;两项前置同时就绪后的 `1888cd3` 整包 27/0/0 另有独立日志,不改写旧轮结果。上一轮 `5d9a5a1` 的 **24 条 / PASS 24 / FAIL 0 / SKIP 0** 是当时的完整结果(口径不同:那次包含两个旧辅助类),日志 `/tmp/nk-ui-full-5d9a5a1.log`,不复用为当前结论。三个主题链接用例和三列用例均通过;此前 `8acbb78` 的 19/19 仅作为历史记录。长按进入编排与尺寸重启持久化已经验证。较早 Orca Worker 在 App `7586982` 上单独执行拖放重启用例通过,并读 `homeBlocksV2` 交叉确认;这不是重新跑完整套件。用例原提交 `33be2af` 已推送验证分支,并整合到主线 `9b2b3e6`;测试文件与 Mac 执行版本一致,Windows 只补做 Swift 解析。已采集 iPhone 402 pt/2 列与 iPad 1032 pt/4 列的明暗发现页、设置页共八张模拟器截图;后续 `211cd64` 的五张到底截图已确认页尾与胶囊不相交(约 21–43 pt 间隔),无需补底边距;后续 `5d7022d` 已在 874 pt 横屏内容宽度确认 3 列几何位置;截图旋转与暗色顶部裁切仍需重拍。iPhone 到底截图无法同时完整显示已经滚到顶部的 TMDB 说明。主题 HTTPS 安装/选中/重启与坏 JSON 路径在 `5d7022d` 已通过,明文 HTTP 拒绝在 App `a526add` 单独通过;`9005dca` 的 Theme 单测 8/8、`6bb7933` 的 12/12 已在 Mac 实跑。`9f7840f` 的 Theme 已实跑 12/12,快速拒绝 0.015 秒;完整 UI 未通过,Worker 原报 24 条 / PASS 22 / FAIL 2 / SKIP 0,但明细只列一个失败方法的两条断言,失败用例数待核。主题用例顺序依赖已在 `5d9a5a1` 修正,该提交的完整 24/24 回执已收到。0.2.7/build 9 的发布 CI `41465697611` 已通过:IPA 下载 HTTP 200、29,368,112 字节、SHA-256 `182f62cf2aea32d6b8183effd0f0f31aede1deeab4270ce02d22b6a12bc8b7f3`,包内 App/Widget 均为 0.2.7/9 且含主题 HTTPS 拒绝文案;AltStore 工作流 `41471135708` 已把稳定轨道与扁平列表首个版本更新为 0.2.7/9,图标 200、IPA 分段 206。该 IPA 未签名,因此签名安装、真机启动与该版本在设备上的界面仍属未验证;旧版发布结论不复用。不同提交结果不拼为一轮。真机/后台/真实账号仍未验证。`0.2.6`(build 8)发布构建 `41431641042` 全绿;下载的 IPA 为 29,361,985 字节、App/Widget 版本一致、HTTP 200,AltStore 仓库和订阅入口均已核对为同一版本。CI 单测与模拟器 UI 是不同的证据,不复用旧版本测试数作为当前结果。

补一条量出来的事实,免得只写「过了阈值」:三套强调色对最终选定文字色的对比度分别是 `#3482FF` 3.63:1、`#6BA4FF` 8.38:1(深色字)、`#0A84FF` 3.65:1。它们都高于代码采用的 3:1 大字号底限,但前两者低于 WCAG AA 正文的 4.5:1——这是既有配色取舍,本轮不改色,只把数字记录在此。

三套强调色的对比度判据仍来自 `accentTextFollowsTheAccent` 单测与代码;本轮一般明暗布局截图没有逐个测量三套强调色的对比度。三个内置强调色的判定为 `#3482FF` 白字、`#6BA4FF` 深字、`#0A84FF` 白字。

更早的那份结论是:**这棵树编译过了**:GitHub Actions 运行 `41316459367`(提交 `71c8c97`)在 macOS 上完成内置 Core 构建、四项仓库检查、工程生成、`xcodebuild` 编译,并产出了未签名 IPA(18.9 MB)。此前 `b9fdf3c` 之后的一批提交从未经过编译器,那份顾虑到此为止。

编译通过不等于行为正确。CI 已运行 `swift test`,但 iPhone 界面用例在 CI 里只编译、未执行;模拟器执行交给 Mac Orca Worker。真机、真实账号与服务器仍按下表保留缺口。

## 主题链接 UI 用例的本地夹具

`UITests/ZZThemeLinkTests.swift` 的三个用例需要 `127.0.0.1:18791` 的 HTTPS 服务(有效/无效 JSON)、`127.0.0.1:18792` 的 HTTP 服务,以及该模拟器信任的测试 CA。服务代码与三份 JSON 现已在 `UITests/Fixtures/theme/` 入库;证书与私钥在运行时生成,不入库。生成 Xcode 工程后运行 `sh scripts/theme-fixture.sh <UDID>` 即可启动夹具、添加仅限模拟器的 CA、预检并执行三条用例。脚本保留证书目录并打印指纹/到期日,不会重置钥匙串。服务未启动时用例仍按设计 `XCTSkip`,缺夹具或证书过期不能记为通过。

证据归属:2026-11-02 由 Orca Worker 在专用模拟器 `0A67B65C-9EB9-4504-B7C6-7A8EC74DA1A0` 上验证 App `a526add`;UI 用例提交 `aeead82` 已 cherry-pick 为 `3167a5e`。HTTP 反例:弹窗原文含 `https`、列表未出现测试主题、明文服务器收到 0 次请求、Themes 目录无新增文件。HTTPS 成功安装/选中/重启与无效 JSON 错误路径是同一夹具上的既有通过项。早期 CA 有效期 2 天;最新 `5d9a5a1` 完整回归新增的 CA 有效期 1 天,约 2026-11-03 失效,仍留在专用模拟器信任库。该轮临时服务与测试主题已清理;后续复跑应重建夹具并使用有效 CA,缺失夹具或证书过期时不能记为通过。

## 构建已经证明的

| 项目 | 证据 |
|---|---|
| 整个 kit 与 App 能在真实 iOS SDK 上编译 | 运行 `41316459367` 的「Build unsigned device app」成功 |
| 打包成 IPA 的路径可用 | 同一次运行的「Package unsigned IPA」与产物上传成功 |
| 仓库检查在 macOS 上同样通过 | 同一运行的检查步骤:`check-docs`、`check-partitions`、`check-core-pin`、`check-kit-core-calls`、`check-swift`(已装 tree-sitter,真解析 152 个文件) |
| 内核 pin 可复现 | 同一运行先从 `214e7782190d` 拉取并构建 Core 成功 |

首次真实编译抓到并已修掉的四个错误,都是静态检查看不见的:`ComicDetails` 的评分字段被误写进 `Comic`(**会让每个详情页整页失败**)、`@MainActor` 类里的静态方法被非隔离调用、两处 `status == errSecSuccess || errSecItemNotFound`(把 `OSStatus` 当 `Bool`),以及随后 App 目标暴露的 12 个界面错误(样式三元、`Environment` 参数顺序、可选链、PiP 内容源与跨线程快照)。

## 还没验证的

下载库引用环修复 `ed09c82` 已在 Mac 上通过构建、416 单测与两条下载 UI;强引用负向对照确实失败,恢复后通过。合并后的 `9498b4c` 现已通过 416 单测和完整 UI 27/0/0;后续只剩发布与外部条件验收,不再标记该修复为未执行。

| 提交 | 改了什么 | 现在的状态 | 还剩什么 |
|---|---|---|---|
| 回复截断提示 | 读 Core 事件里的 `outcome`,达到长度上限时在聊天页显示「已达长度上限,回复可能不完整」 | **已编译并跑过单测**(构建 `381f2a6` 全绿) | 让模型答满 max_tokens,看提示是否真的出现 |
| Bangumi 支持 | 账号、收藏五档、话数、每日放送、与追番提醒的合并 | **已编译并跑过单测**(`v0.2.0` 构建全绿,359 项测试) | 真机连一次真实令牌 |
| `33c5c7a` | `seed-simulator.sh` 写入真正在用的环境目录 | 脚本级改动,不参与编译 | 一次 seeded 运行是否真的出现 5 个源 |
| 字幕叠层 | 用 `$subtitleCues` 画文字字幕,跟随 `clock.$sourceTime` | 编译通过 | 播放一次带字幕的源,确认文字按时间出现 |
| 软件通路画中画 | `AVPictureInPictureSampleBufferPlaybackDelegate` | 编译通过;内容源改为按图层构造,两个同步问题的答案放进带锁的快照 | 真机软解一次(VP9/AV1)并转画中画 |
| `198d1ad` | 追剧提醒:kit 规划 + `UNUserNotificationCenter` | 编译通过 | 真机开通知后看「已安排 N 条」;7 个规划单测 |
| `43decff` | Plex 视频源 + Node 固件测试 | `node plugins/plex.test.mjs` 五项通过 | 装进源列表,由真实 Core 运行时加载一次 |
| `ab1ebbb` | 详情读 `stars`/`likesCount`/`isLiked` 并显示评分 | 编译通过(字段已从 `Comic` 移到 `ComicDetails`) | 真实来源下一次详情页见到评分数字 |
| `a4ead24` | 关闭播放器时把位置回写服务器 | 编译通过 | 播放一次服务器条目后关闭;`MediaServer` 3 个回写测试 |
| `0031190` `40e0962` | 发布流水线回到仓库、版本 0.2.0 | **已验证**:手动触发即可完成构建并上传产物 | 打 tag 才会走发布分支;未打 |
| `27dd92c` | 首页三张卡;继续阅读过滤视频 | 编译通过 | 首页渲染;`HomeLayout` 两个新用例 |
| `467b9c5` `4db8265` | 压缩包重名页、弹幕行标识、整数时间戳 | 编译通过,风险低 | 对应单测 |
| `017522b` | 服务器分页 + 30 秒超时 | 编译通过 | 媒体库能否列出条目(需真实服务器) |
| `7787b3b` | `PlaybackProgress` 收敛 | 编译通过(原先最担心的一处,已排除) | 三个播放界面的时长与续播显示 |
| `a693a63` | zip CRC 校验 | 编译通过 | 4 个导入测试 |
| `6ffe7d7` | `VideoPlayerView` 参数顺序 | 编译通过 | 播放器界面实际显示 |
| `4b80a57` | 导入移到后台、`importComic` 变 async | 编译通过 | 导入一个文件夹与一个 `.cbz` |
| `e460fba` | 读不出的文件先备份 | 编译通过 | 造一个坏 store 文件,看是否留下副本 |
| `6d7dc5d` | 迁移崩溃窗口 | 编译通过 | 3 个升级测试;真机升级一次 |

## 需要真实条件才能验证

| 项 | 缺什么 |
|---|---|
| 媒体服务器连接、浏览、播放、进度回写 | 一台 Jellyfin/Emby 的地址与账号 |
| 「即将播出」 | 一个 TMDB key |
| Pixiv 登录后的关注与收藏 | 真实 Pixiv 账号 |
| 画中画、锁屏后台播放、通知触发 | 真机 |
| 本机视频与导入的漫画 | 真机上的文件 |

## 核对清单本身

```sh
git log --oneline b9fdf3c..HEAD
```

表格里**改动过代码或脚本**的提交都该出现;纯文档提交不列,它不参与编译。写这份文档时正是这样发现 `a4ead24`(进度回写)被漏掉的——清单会漂移,所以要能一句话核对。

## 怎么跑

```sh
sh scripts/fetch-core.sh
NK_UI_TESTS=1 NK_UI_SEED=/tmp/seed.json NK_UI_SEED_REPLACE=1 sh scripts/verify-ios.sh
```

CI 已加入 `swift test --no-parallel --verbose`;`xcodebuild build-for-testing` 仍只编译界面用例。执行 UI 要在 Mac 上运行 `test-without-building`,汇报提交号、总数、失败与跳过,保留完整日志。新增用例必须重新构建测试目标;不要拿旧构建产物验证新源码。
