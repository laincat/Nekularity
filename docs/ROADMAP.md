# 三项目推进路线图

[English](ROADMAP.en.md) | 简体中文

## 2026-11-08 现状：0.4.5 已发布并核对，桌面当前 pin 主线已跑通（2026-11-08）

**iOS**：`v0.4.5` / build 27 已发布并核对——发布 CI `42439654644` success，IPA HTTP 200 / 29,947,418 字节 / SHA-256 `9342dc44…42cd15`，包内 App 与 Widget 都是 0.4.5/27、最低 iOS 26.0、Core pin `d9a1851`，LICENSE/COPYING md5 与仓库一致；AltStore 三入口（raw / CNB / latest）均为 **0.4.5 / 27 / 29,947,418**（`update-source` REST dispatch 204，工作流 `2026-11-08T05:10:53Z` 成功，提交 `31590d9`）。最终 HEAD 完整界面套件 **34 通过 / 0 失败 / 0 跳过**（run `42434319855`），Kit **492 tests / 85 suites**。

**Core**：pin `d9a1851` 与 main `15187e9` 相差 7 个提交，但**零生产代码改动**（非测试 `.go` 文件 0 个、`go.mod`/`go.sum` 未变），因此两端 pin 不必跟进；官方源巡检 **34/34、0 失败**。当前 pin 上 Magpie 本地 HTTP 夹具实跑 **7 PASS / 0 FAIL**（含服务端 `peer_closed`）。

**桌面**：0.2.27 的桌面探针 **21 PASS / 0 FAIL / 0 SKIP**、`scripts/check.sh` **7/7**；**Windows 原生阅读主线已在当前 pin 上用真实 UIA 点击跑通**（搜索→详情→阅读→进度落盘→正常关窗→重启→书架续读，两个进程退出码都是 0），证据 `E:/Code/deliveries/2026-11-08-windows-native-mainline/`。

**仍需外部条件**：macOS 当前 pin 主线（本机无 macOS，Mac 设备上没有可用模型路由：一次性调度报 `Scheduled remote model route unavailable: unreachable`）、真机签名安装、后台/锁屏、Live Activity、PiP / AirPlay / 外接显示器字幕、实际扬声器、真实账号与站点、Nekophage 公开发布目的地、LGPL 例外法务意见。

## 0.4.3 发布、最终回归与桌面 0.2.27（2026-11-07）

按本轮顺序收口：最终 HEAD `f486376` 的完整 UI 套件 **32 通过 / 0 失败 / 2 跳过**（run `42386284795`，Kit 490/84），HLS 字幕修复后 OCR 只读到一行文字；随后发布 `v0.4.3/build 25`（`87db928`，CI `42392553106`）：IPA HTTP 200 / 29,942,512 字节 / SHA-256 `cc64a26d…`，App 与 Widget 都是 0.4.3/25、最低 iOS 26.0，Core pin `d9a1851`，包内 LICENSE/COPYING 与仓库 md5 一致；AltStore 三入口（含 raw、CNB、latest）均为 0.4.3/25。桌面 `0.2.27` Windows ZIP 与安装包在隔离资料下 **14 PASS / 0 FAIL**，交付 `E:/Code/deliveries/2026-11-07-nekophage-0.2.27/`。Core 官方源巡检 **34/34、0 失败**，没有新增兼容缺口，两端 pin 保持 `d9a1851`。 **2026-11-08 更新**：Core 升到 `3d61c62`（`new URL` 点段解析）后，桌面重打 `0.2.28`（`719d852`）：ZIP 23,002,081 B、安装包 19,913,306 B，隔离安装 **14 PASS / 0 FAIL**，新 pin 上 Windows 原生阅读主线 PASS；iOS 在新 pin 上 CI `42460155664` 完整 UI **34/0/0**、Kit **492/85**。交付 `E:/Code/deliveries/2026-11-08-nekophage-0.2.28/`。 **0.4.6 发布**：`v0.4.6/build 28`（`442a63c`，CI `42464844452`）IPA 29,947,286 B，内容 12/0，App/Widget 0.4.6/28，Core `3d61c62`；AltStore 三入口均 0.4.6/28/29,947,286。回执 `E:/Code/deliveries/2026-11-08-nekularity-046/receipt.json`。 **0.2.28 已公开发布**：`v0.2.28` / Release `https://github.com/laincat/Nekophage/releases/tag/v0.2.28`（四资产，API 回读 4/4 200、校验和 2 OK；ZIP 公开 URL 200，安装包公开 URL 本轮 504 为 GitHub 网关问题）。回执 `E:/Code/deliveries/2026-11-08-nekophage-0.2.28/receipt.json`。

剩余外部依赖单列：真机签名安装、后台/锁屏、Live Activity、PiP 与实际扬声器；`nhentai`/`Komiic` 两条跳过用例所需的仓库外源脚本；Nekophage 没有 Git remote，公开发布目的地未指定；macOS 当前 pin 的搜索→详情→阅读主线需要 Mac；PiP/AirPlay 字幕在 suppressing legible output 下仍不覆盖。

## 在线弹幕后置，改由插件实现（2026-11-07 决策）

用户确认：**在线弹幕不重要，放到后面用插件实现**。因此本阶段 P0—P3 不再把在线弹幕的站点抓取、剧集匹配、第三方弹幕服务接进客户端主线，也不再为它追加验收项；现有本地弹幕（文件导入、解析、按播放时钟绘制叠层）与相关单测保留，作为插件将来可复用的绘制层。插件契约未定，等 Magpie/服务插件体系与 Core 能力边界明确后单独设计，不预先写死接口。Trakt 同步与制作台仍按 P4 后置。

同轮 CI 完整套件（带主题 HTTPS 夹具）run `42331728546`：**30 通过 / 2 跳过 / 1 失败**。通过项含长按编排、拖放顺序重启持久化、大小持久化、明暗设置、横屏三列、主题 HTTPS 安装与明文 HTTP 拒绝、下载重试、标准 AI 流式与断流、视频画面推进、30 秒 HLS 续播。跳过 2 条需要仓库外的 `nhentai`/`Komiic` 源脚本；唯一失败是已记录的 `testHLSPlaysAndSwitchesSubtitles`（`.remoteBypass` 上引擎没有把 cue 文本交给客户端）。日志 `E:/Temp/nk-ai-stream-ci/full2.log`、`full2-summary.txt`。

## Core313951e三条源码主线已整合（2026-11-04）

Core313951e已按单提交保树发布，Nekophage4273e06与Nekularityc751085功能候选已整合，两端pin同步。Core四作业CI41814080991、iOS CI41815696096的443/82与31/0、App及UI编译、候选IPA内容/摘要均通过。桌面实际Core pin、七项工程及文件/URL重装、索引身份负例通过；新Windows exe另经五进程合集流程验证。产品源码保持受测提交，详见[STATUS](STATUS.md)及 `E:/Code/deliveries/2026-11-04-core-313951e/`。

公开iOS0.3.5/17、AltStore和既有桌面0.2.9安装包仍属于此前Coreccb版本；新候选不覆盖正式包。iOS仍保留重复键文字兼容，结构化跨桥错误/索引安装身份需单独推进；Mac源码查看补丁已逐字节整合为2b38049；Windows原生窗口和0.2.10包已验，Mac旧Core证据不提升为当前组合。合集GUI/安装、受限传输桥和模块/服务生命周期仍有独立工作。

## Core ccb6268 与 iOS 消费端整合（2026-11-04）

此前Core ccb6268发布时，两端功能pin一致。iOS现已正式发布0.3.5/build17（7c0d61b）：CI41791891766、公开IPA HTTP200/29,478,760字节、摘要/CRC/App与Widget/最低26.0/Core标记，以及AltStore三个入口均通过，详见[STATUS](STATUS.md)。UI只编译；bac68cda组合的443/82及31项XCTest计数保留原执行归属。桌面本地包仍为0.2.9/fe101db/Core ccb6268；Windows安装媒体和Mac开发WebView证据按各自提交范围记录。

## 桌面统一合集客户端基础（2026-11-04）

Nekophage当前源码已接Core313951e合集解析/能力匹配和独立订阅持久化，提供follow/list/refresh/unfollow命令入口。Windows七项工程和五个实际二进制进程验证7条目订阅、刷新、离线重开、取消订阅、安装记录保持及无制品请求；取消连接与失败保留由真实loopback/race回归覆盖。证据 `E:/Temp/nk-collection-client/`。尚未更新0.2.9安装包或验证Mac命令；目录GUI、条目安装、模块/服务宿主仍待推进。MyGo源码查看候选由已有Orca Worker继续，不能以此命令验收替代其Mac运行结果。

## 当前主线:先完成底层、架构与基建(2026-11-04)

用户已明确:Nekularity与Nekophage各客户端的UI/UX后续都要整体重构重写。当前先收束Core与宿主/平台职责边界、源脚本和API/媒体契约,处理网络请求/流的取消与资源生命周期、源和账号隔离、存储/备份/迁移/跨进程恢复,以及固定依赖、构建打包和发布基建。

已有界面验收保留其历史证据,不再追加旧界面的布局、主题、视觉统一或截图矩阵。只保留证明底层行为所必需的触发与观察,例如跨App进程读取已保存播放位置。旧P0—P3编号用于追踪,后续执行服从本段顺序;UI/UX重写在上述基础工作之后启动。真实账号/设备和后置服务仍按既有边界交接。

## 动态Liquid Glass与高度可定制界面目标（2026-11-04）

用户明确iOS优先、桌面同方向：iOS27级别的动态Liquid Glass、动态图标、大画幅图片/漫画/视频、标签与高度自定义。按[材质清单与跨端方案](LIQUID-GLASS.md)推进：原生SwiftUI和现成MyGo Glass优先；首轮只调整材质，保持布局/间距/圆角/字体/图标身份/文案，新增控件先讨论。明暗tint按主题分别保存，降低透明度/动态效果与文字对比度优先。基础工作顺序保留；不能把原生材质库测试当成产品UI或iOS27专属API验收。

## 生态复用与按需服务插件(2026-11-04新增方向)

用户要求直接引用可维护的上游项目,整理JS引擎、编辑器高亮、Magpie兼容/桌面设计、主题与插件格式,并将Trakt/TMDB/Bangumi改为按需服务插件,安排漫画AI自动上色。新建本地[统一源目录工程](../../VeneraCat%20Sources/README.md),最新边界按用户纠正改为“一个源一个跨端合集”:插件/扩展/主题/模块统一收录,条目注明支持端和能力,订阅表示跟踪合集,不再按三项目分源。Surge风格简单配置模块也属于同一合集。目录构建及现有Core兼容格式契约均可运行;tmdb-ts加标准polyfill已在真实Core验证一个查询接口,服务宿主与客户端迁移尚未完成。Trakt的协议/插件设计进入当前底层工作,真实账号闭环仍单列,不因旧的后置条目阻止该基础设计。UI重写仍在底层之后。

## 模拟器跨进程进度恢复(Orca Worker回传,2026-11-04)

0.3.4/16、Core 3be57b5的专用模拟器定向测试中,第一App进程2020播放30秒HLS至7.211756秒,暂停并正常关闭播放器页,随后终止App。第二进程2099通过同一视频源的搜索和分集页重新进入,诊断起点7.000000秒,约2.08秒后自动播放至8.342057秒。修正测试PID千位逗号解析后,定向XCTest为1 test/0 failures。测试结束后磁盘历史为7秒/30秒/23%;这不是两次进程之间单独抓取的磁盘快照。

该结果证明上述搜索/分集路径的模拟器跨进程位置恢复,不证明“继续观看/本地条目”直接入口,也不证明真机、后台或PiP。诊断构建临时读取PID、起始位置和时钟;产品源码已还原并重建安装,受测VideoPlayerView.swift还原SHA为0daef0ed11c4cd12e4918ed0f89d30e8066a37c75011974a94f1d76c1fdbff37。原始日志在Mac `/tmp/nk-ios-cross-process-resume-evidence/`,本地 `E:/Temp/nk-ios-034-evidence/cross-process-worker-report.json` 仅是Worker回传记录,不是原日志副本。旧界面直接入口的UI验收按整体UI/UX重写计划后置。

## 当前独立修复(2026-11-04)

Nekularity的离线onResponse二次转换及HTTP200坏图被记为完成两项问题已修复,四份Mac受测文件按SHA逐字节整合并随0.3.4/16发布。Orca Worker完整单测436/81、最终build-for-testing和定向UI2/2通过;正式CI/IPA/AltStore三个公开入口均已验收,详见[STATUS](STATUS.md)。Lead另在Nekophage复现并修复图片镜像回退遗留旧POST正文/像素脚本的问题,真实Core、loopback HTTP和PNG解码回归已通过Windows race测试,证据 `E:/Temp/nk-image-fallback/`。这属于桌面客户端契约修复,提交0db2ead的Windows ZIP/安装器已通过包内容及隔离安装卸载核验,交付 `E:/Code/deliveries/2026-11-04-image-mirror-fix/README.md`。Core功能pin仍为3be57b5,旧c545212包不含该修复,Mac/GUI不因此提升为新版本通过。

## Mac关窗与Core主线结果(2026-11-04)

Orca Worker在用户解锁后,以隔离资料启动已核验c545212包,原生关闭按钮一次点击后窗口消失、原进程退出0,无信号终止。Core单提交main c0f0dfa在自身SHA完成三平台Go和Apple SDK/Swift四作业CI。详见[STATUS](STATUS.md);用户设备、账号与分发选择仍单列。

## Core测试与兼容说明已整合(2026-11-04)

经用户确认,Core main按单初始提交约定更新为c0f0dfa00c8a4daf7ce58fea5b615bc24eab88b7,文件树与通过完整CI41722875239的8922993完全一致,PR #3已关闭。只有测试与文档差异,生产转换实现未变;Nekularity/Nekophage仍使用功能pin3be57b5。保树/远端/两端pin回执 `E:/Temp/core-gbk-differential/main-published.json`。新主线SHA与已有CI受测SHA分别记录,不把旧CI改记为新SHA执行。

## Mac主题与构建补验更新(2026-11-04)

原Orca Worker已回传12张本地封面的明暗/横竖四组合、两处深色蓝字4.665:1、精确736e364本机430 tests/80 suites与IPA终态。详情进入只证明导航,源未安装不算内容加载;本机Xcode27.2/SDK27.2的IPA与正式CI发布包分别记录。详见[STATUS](STATUS.md)。离线图片正/负/恢复已验,完整受测文件与串行隔离修复已随a7b5fbd整合,历史完整UI计数不变。

## 0.3.3发布验收更新(2026-11-04)

736e364的0.3.3/15已发布:CI第二次成功,IPA HTTP200/29,457,850字节、摘要、App/Widget元数据与Core pin通过;AltStore修复生成步骤认证后,仓库及三个公开入口均0.3.3/15。详细回执见[STATUS](STATUS.md)。断网页图正/负/恢复对照已过Orca Worker实测,产品未改,测试已随a7b5fbd整合,连续负例→正例2/0。其余已派Mac任务仍按各自终态记录;真机、后台、账号等外部项不计通过。

## 30秒 HLS 续播定向通过(2026-11-04)

Orca Worker 在专用签名模拟器上用30秒本地素材,真实播放后分别下滑和点关闭按钮。关闭前位置7.24/7.30秒,均落盘7秒/30秒、23%;自动重开时未点暂停、播放或字幕,起点均为7.00秒,早期App/engine/source时钟分别为9.60/9.50秒。两次CoreMedia均记录postSeekPosition 7.000000,经过的约2.5秒包括自动播放和UI采样。临时只读诊断移除后App重新编译安装,最终VideoPlayerView SHA为0daef0ed11c4cd12e4918ed0f89d30e8066a37c75011974a94f1d76c1fdbff37,与先前受测源码一致。素材Git原始主清单为LF/110字节,Windows CRLF副本114字节,其余素材按摘要核对。日志 `/tmp/nk-hls30-resume-evidence/`,回执 `E:/Temp/nk-ios-033-evidence/hls30-mac-receipt.json`。原10秒失败日志仍保留:晚期交互接近片尾可能触发正常重播,本次不据此断言其调用原因。本次通过仅覆盖模拟器页面关闭与重开,不涵盖跨进程、后台或真机。

## 主线字幕修复安装包验收(2026-11-03)

Lead 已构建并实际安装 0.2.7/`bf9cbd9`(Core `4f213ff`)。ZIP 21,566,978 bytes,安装器 18,720,774 bytes;CRC、逐文件摘要、实际版本与安装后 exe 一致性通过,产物和构建日志位于 `E:/Temp/nk-subtitle-package/`。使用此前测试实际保存的英文字幕/3.030709 秒资料的副本,仅调整本地夹具地址,经原生搜索建立夹具会话后继续观看:英文 Subtitle rendering proof 实际可见。通过字幕控件选择关闭后文字消失且 off=true 落盘;正常逐窗退出并启动新进程后,关闭选择仍保留,恢复位置仍为 3.030709,视频区域逐像素一致。

回执、校验和截图见 `E:/Temp/nk-subtitle-package/accept-8acc7abc/receipt.json`、`verify.log`、`restored-english.png`、`off.png`、`reopened-off.png`。两轮应用均正常关闭,本任务夹具停止、临时安装卸载,实际资料文件哈希不变。此结果属于 bf9cbd9/Core 4f213ff 的 Windows 安装版,不代替 Core 3be57b5 候选安装包或 macOS 验收;夹具无音轨,不证明扬声器或真实账号自动登录。

**Core 发布与消费端更新(2026-11-04)**:Core main为3be57b5。Nekophage main已整合为c545212并升级到3be57b5,包含WebKit字幕修复、关闭竞态修复、打包pin校验及关闭字幕跨进程探针;七项检查、实际WebView2新进程关闭恢复、ZIP/NSIS构建与版本核对通过,回执 `E:/Temp/nk-desktop-core-integration-evidence/receipt.json`。Windows安装版97e24b6的语言/关闭/跨进程续播证据与当前构建分开;Mac ca8f370/Core3be的阅读、视频和同一WebKit修复后字幕已验,当时包装窗口关闭被screen_locked拒绝,后续c545包正常关窗已通过,c545212/Core3be的播放器race及两个独立进程(13544、13564)从此前页面保存的off资料恢复关闭已通过,回执 `E:/Temp/nk-c545-mac-transfer/mac-acceptance.json`。截图全白不算视觉证据。临时源码gist在Mac核对接收后已删除。Nekularity main现已升级到3be57b5;独立d3672a8组合CI/IPA已核对,随后9ae1118整合与Mac受测文件一致的登录后绑定Core修复,签名专用模拟器Magpie UI1/1完成登录/模型/首段/停止peer_closed/重启凭据恢复,两条真实Core回归已逐字节收回。标准AI专用签名模拟器UI1/1通过Chat/Responses/Messages整包答复、停止请求22后peer_closed、模型目录401和重启假密钥恢复;回执 `E:/Temp/nk-standardai-ui-acceptance/receipt.json`。最终组合3574346的CI41689864772与未签名IPA已核验通过,IPA29,455,523字节、App/Widget0.3.2/14、3be57b5;摘要/CRC回执 `E:/Temp/nk-ios-final-integration/receipt.json`。产品与测试源码不变地整合main,不是新版本发布。旧零正文扣住时未提前交头的失败保留,标准AI页面仍整包,不把编译、Go宿主或旧版本证据当新UI通过。

**桌面主线整合(2026-11-03)**:先前把 Nekophage 工作分支称作 main 的口径已更正;整合前真正 main 为 `28be4bd`/Core `214e778`,核对日志 `E:/Temp/core-magpie-first-chunk-evidence/desktop-main-ref.log`。现已将 `fix/subtitle-record-cap` 快进整合为真正 main 的 `67fc877`,pin 为 `4f213ff`,原分支保留;同时带回 WebView 探针隔离修复并移除误入版本控制的 Python 缓存。七项检查与 Windows 隔离阅读回归通过:两页解码、双页、55% 进度、重开恢复 1200,仅有本次章节存储键。回执 `E:/Temp/nk-desktop-integration/receipt.json`。`a079ce7`/Core `b55c1a4` 的 Windows 包仍属于独立候选,新 pin 的 macOS 消费端尚未验收;Nekularity main 仍 pin `4f213ff`。

更新:2026-11-03。范围为 Nekularity、Nekophage、VeneraCat Core。按用户最新要求,当前优先 Core 脚本兼容、异步取消、分区隔离、存储/备份和客户端 API/媒体契约,再完成必要功能闭环;界面重排、视觉统一和截图矩阵后置。P0–P3 编号沿用原表便于追踪,当前执行次序以上述优先级为准。已运行的验证保留结果,不再追加纯界面任务;遇到需要真机、账号或服务器的事项,记录缺口并继续可独立完成的下一项。不能把一次发版当成整个路线图完成。

## 项目判断与基线

| 项目 | 当前事实 | 主要缺口 |
|---|---|---|
| Nekularity | **0.3.5/build17已发布并核验**：7c0d61b/Core ccb6268，CI41791891766成功，IPA29,478,760字节；三个AltStore入口一致 | 发布CI执行Kit并编译UI；旧完整UI27/0/0及下载定向2/2保留原提交归属。真机、后台/锁屏、PiP、Live Activity和真实账号单列 |
| Nekophage | MyGo主窗+WebView阅读/播放；当前本地包0.2.10/3f3efee、Core313951e | 七项工程、Windows原生源码查看/URL重装/新进程恢复，以及隔离安装主窗正常关闭退出0/卸载资料保留通过；源码查看动作属于2b38049 e2e构建，未新增安装版阅读/媒体验收。Mac当前e887914/Core313951e开发构建的阅读、只读源码查看、HLS/MP4鉴权Range画面及续播已验；音频计数和扬声器未通过。签名/公证与公开目的地单列 |
| VeneraCat Core | 共享漫画/视频/备份/AI 协议逻辑;网络与系统能力交给客户端 | JS 引擎的少量兼容限制、客户端边界契约仍需维护;Sender 没有生产调用方 |

证据按提交和执行渠道分别记录,不声称重新跑过三个项目的全部测试。两端main功能pin均为 `ccb626825bc116dad3b3e9a082867fd22c09caf4`;iOS 受测分支 `98e2e76` 已由 Orca Worker 重建 xcframework、通过 415 单测与四例定向 UI 后整合。已发布 Nekularity 0.3.2 的包内 pin 核到 `4f213ff`(旧 `8e14aad` 已不在包内),Nekophage `90e784f` 的 macOS 本地夹具搜索、阅读、进度恢复与双页现已在 `4f213ff` 验证;`c387e3f` 打包 App 已实际开窗,正常关闭因 `screen_locked` 待验。Core 后续文档提交不自动改变客户端 pin。

**此前 b55c1a4 候选记录**:Core 取消修复经 `696a504` 的四个 CI 作业与真实 loopback 验收后,按仓库约定保树收拢为主线 `b55c1a4`。iOS 候选 `b39e6b0` 的 CI `41612614917` 与 IPA 内容核验已通过,仅编译 UI 用例,未执行或发布;桌面 `a079ce7` 已过七项检查与 Windows 安装版 HLS/中英字幕/关闭字幕/跨进程续播/鉴权/Range/正常关闭卸载,详见两端 STATUS。macOS 新 pin 消费端仍待验收。两端 main 仍为 `4f213ff`。Magpie 插件文字尚不能在正文结束前交付,这一限制已单独复现,不与取消通过混算。

**较早的 2c9c83b 候选记录**:`2c9c83b` 的 CI `41590287663` 四个 job 全成功(含 Apple xcframework 与双平台 Swift smoke);SDK 下载哈希和三类切片已核对。两端独立候选分支均为 `update/core-2c9c83b`:Nekularity 已由初始 `0ea786f` 更新到 `5bc5b67`:预检发现旧候选缺少 `bb77b5d` HTTP 错误修复,现已整合 main `bf9d93d`,与该 main 的功能源码只差两处 pin。分支 CI `41599831561` 已核对 HEAD 并有终态:Kit 单测与设备 App 构建通过,UITests 编译步骤退出 65,IPA 打包与上传跳过。整体日志被插件地址校验拒绝,具体编译错误未取得,不作为回归通过;后续 `af48d65` 排除两份同名宿主 Python 资源并保留构建诊断 artifact,CI `41607054742` 已通过,验证 IPA 的 CRC/版本/pin 已核对(29,436,243 字节),不是公开发布或 UI 执行,详见 STATUS,Nekophage `db024bd` 已过七项检查,Windows 开发路径实测 HLS 解码/鉴权/页面进度重开恢复、MP4 206 范围响应及英文/关闭字幕持久化。另已生成同提交 ZIP/setup,实际临时安装后主窗可见、正常关闭并卸载保留资料;随后同一 `db024bd` 安装包已在独立资料下完成原生搜索→HLS/中英字幕与关闭选择、鉴权/Range 和跨进程续播,恢复视频区域逐像素一致且关闭字幕状态保留;通过原生搜索重新建立夹具登录,不声称自动登录。回执 `E:/Temp/nk-core-2c9-runtime/media-installed-0c334515/receipt.json`。日志与回执在 `E:/Temp/nk-core-2c9-runtime/`,候选文档提交 `755ea28`。它们尚未合入两端 main,不复用旧 pin 的 UI 证据。

Nekularity 早期完整 UI 验证提交 `5d9a5a1dfd5ce0e9d58fead6371d5cc4b3f842c4`:Orca Worker 在专用 iPhone 17 Pro 上卸载旧 App、重新安装并补种,启动前 Themes 为空,完整 **24 条 / PASS 24 / FAIL 0 / SKIP 0**。HTTPS 安装/选中/重启、坏 JSON 保留原主题、HTTP 拒绝三条均通过,三列几何也通过;日志 `/tmp/nk-ui-full-5d9a5a1.log`。这是一轮完整执行,不由早期单项结果拼合。三列完整视觉仍需重拍,真机/后台/账号不在该证据范围。

`0.2.7`(build 9)已发布并核对:提交 `90b98b0`,发布 CI `41465697611` 通过;IPA 29,368,112 字节、SHA-256 `182f62cf2aea32d6b8183effd0f0f31aede1deeab4270ce02d22b6a12bc8b7f3`、下载 HTTP 200,包内 App/Widget 均为 0.2.7/9 并含主题 HTTPS 拒绝文案;AltStore `update-source` `41471135708` 已把稳定轨道与扁平首个版本更新为 0.2.7/9,图标 200、IPA 分段 206。受测功能源码与 `5d9a5a1` 一致,版本元数据与文档有差异。包未签名,真机与签名安装仍未验证。`0.2.6`(build 8,CI `41431641042`)是上一个已发布版本。

## 优先级与验收

| 顺序 | 目标 | 完成条件 |
|---|---|---|
| P0-1 | 收口当前 iOS 回归(合并树 `9498b4c` 已完成) | 同一提交上 Swift 416/76 suites、完整 UI 27 PASS/0 FAIL/0 SKIP;三类计数为 23+3+1,xcresult 与日志一致。中英文 STATUS/UNVERIFIED 已同步;单独分支的通过与负向对照保留原提交归属,不替代本轮整包 |
| P0-2 | 发布当前修复测试版（**0.3.5/build17已发布**） | 7c0d61b/Core ccb6268的CI41791891766成功；公开IPA HTTP200/29,478,760字节、资产摘要/CRC/App与Widget0.3.5/17/最低26.0通过；AltStore刷新41797483555及三个公开入口一致。CI只编译UI，真机签名安装仍需设备 |
| P1-1 | 把发现页和主题界面验证完整 | 本轮三项链接用例及8张明暗/横竖空状态截图已记录,竖屏402×874pt、横屏874×402pt;最大辅助字号单列修复已过Mac定向验收,发现/设置末端可操作,普通字号两列与顺序保留;同名下载分组修复也通过。12张封面的明暗/横竖四组合已实测;详情进入仅证明导航,不扩称未安装源的内容加载,详见UNVERIFIED。 长按进入编排、拖放顺序持久化、小/中尺寸持久化;主题 HTTPS 安装成功与错误显示;浅/深色、窄/宽屏截图核对,区分模拟器宽度与真实折叠设备 |
| P1-2 | 下载与播放真机闭环 | 本地模拟器已验HLS中文/英文/关闭及Referer/Range206;手势/按钮进度保存通过,30秒夹具的两种关闭及页面重开恢复已通过;原10秒的回零调用原因仍不确定。 下载开始/结束时 Live Activity、锁屏/灵动岛;断网阅读;播放/字幕/续播/画中画/后台音频;记录版本、设备、动作、结果。可先用本地媒体与夹具完成不需账号的部分 |
| P1-3 | iOS AI 两条接入的真实闭环 | **本地签名模拟器闭环已通过**(3be57b5候选):标准API三协议整包答复、模型目录、UI停止后的同请求peer_closed、模型目录401与重启凭据恢复;Magpie登录/模型、正文尾部释放前首段、UI停止peer_closed、重启认证恢复与刷新总数1。原始证据分别为 `/tmp/nk-standardai-acceptance/evidence/`、`/tmp/nk-d367-acceptance/ios-diagnostic/`。产品绑定修复与两条真实Core回归已随3574346受测组合整合main,CI/IPA核验通过。标准AI页面仍整包;真机、真实供应商账号和零正文完全扣住时的提前响应头行为不在通过范围 |
| P2-1 | 桌面阅读性能与取消 | 被新搜索/浏览/详情替代的请求真正取消;共享封面下载限制并发,缓存按实际字节预算;用慢响应验证旧请求停止、当前结果不受影响,并跑相应 race 测试。**本地工程验收已完成**:搜索/浏览/详情取消、4 个图片下载槽位、32/128 MiB 缓存预算,全套 race/vet 通过,详见 Nekophage STATUS |
| P2-2 | 桌面交付与 macOS 可用性 | 在当前 pin 上运行 macOS 搜索→详情→阅读→进度保存,Windows 打包可启动。**当前Windows本地包为0.2.10/3f3efee、Core313951e**：ZIP/安装器与隔离安装、主窗正常关窗退出0、卸载及源记录保留均通过，详见 `E:/Code/deliveries/2026-11-04-nekophage-0210/README.md`。源码查看和URL重装由2b38049 e2e真实窗口验证，未重跑本包阅读/媒体；以下是**旧0.2.9/fe101db、Core ccb6268**：安装版既有English/3.030709秒恢复及鉴权/Range206已验，前台关闭字幕被USER_INPUT_ACTIVE拒绝，卸载资料保留通过，详见 `E:/Code/deliveries/2026-11-04-nekophage-029/README.md`。以下为**旧0.2.8/1de7f996、Core3be57b5包**：包含图片转换失败镜像回退修复，工程/内容摘要/隔离安装主窗启动和正常关闭/卸载资料保留已通过，回执 `E:/Code/deliveries/2026-11-04-nekophage-028/receipt.json`。本轮未重跑包装阅读或媒体。以下为**旧0.2.7/0db2ead包证据**：安装/卸载与资料保留、原生搜索、英文字幕/既有3.03秒恢复已验,视频裁剪逐像素一致;前台切换/关闭操作被USER_INPUT_ACTIVE拒绝,该轮清理终止不算正常关窗。回执 `E:/Temp/nk-0db-installed-media/run-a7f2d847/receipt.json`。旧c545212安装/正常退出证据仍归原提交。Mac当前pin阅读与字幕证据及c545补验见顶部,当前主线c545212的macOS arm64包已由Orca Worker构建并核验归档往返/ad-hoc签名,10,425,020字节,回执 `/tmp/nk-c545-acceptance/packages/receipt.json`;该包隔离原生关窗后原进程退出0也已验,Gatekeeper/公证仍需外部条件。以下为**历史0.2.7/`bf9cbd9`**:英文恢复、关闭及跨进程保持关闭见本页顶部安装包回执。以下是**较早的 0.2.7/`87e2ffc` 记录**,Core `4f213ff`:ZIP 21,565,682 字节(SHA-256 `c39857ee…c7df3f8`),setup 18,722,739 字节(SHA-256 `04416d28…41702c0`),CRC、逐文件哈希、版本均通过。明确 `/D` 安装到临时目录,安装版原生视频搜索→详情→选集→HLS/中文字幕可见,源 Referer/Cookie 鉴权、清单 200 无 Range、媒体字节 206 与页面进度落盘均有证据;完整回执 `E:/Temp/nk-package-87e2ffc-accept/receipt.json`。定向字幕按键曾被 `foreground_unavailable` 拒绝,本包英文/关闭字幕操作仍未验证;随后用原始实际资料重启同一便携包,经原生搜索重新建立夹具会话后点「继续观看」,页面带 `start=0.95312`,恢复画面与保存位置裁剪逐像素一致、与片尾不同。首次无会话请求返回 403 的记录保留,不声称自动跨进程登录。补验回执 `E:/Temp/nk-package-87e2ffc-accept/resume-receipt.json`。临时卸载删除安装目录并保留实际资料。**macOS 当前 pin `4f213ff` 已在 `90e784f` 通过本地搜索/阅读、进度恢复与双页**,`c387e3f` 打包 App 已实际开窗,正常关闭因 `screen_locked` 待验;旧 ad-hoc App 打包/启动证据见 Nekophage STATUS,不当作 Developer ID 签名或公证。包未签名、未公开发布;无远端时保留本地产物,Linux 后置 **2026-11-08 补**：当前 pin 上 Windows 原生主线已用真实 UIA 点击跑通（搜索→详情→阅读→进度落盘→`WM_CLOSE` 退出 0→重启→书架「继续」→再次退出 0），证据 `E:/Code/deliveries/2026-11-08-windows-native-mainline/`；**macOS 同一条主线仍缺**，因为本机没有 macOS，Mac 设备上也没有可用模型路由（一次性远程调度报 `Scheduled remote model route unavailable: unreachable`）。 |
| P3-1 | 共享 Core 的真实兼容缺口 | 对仍可复现的 register 上限、冻结 atob 等问题做最小复现并选择上游修复/明确限制;不要把站点失效当客户端缺陷;Core 功能发布后两端 pin 与契约同步 |
| P3-2 | 桌面视频最小闭环 | **当前pin补验**:c545212/3be57b5 Windows开发WebView2实读HLS音频18537字节、原生MP4音频17976字节;无音轨MP4及虚报AAC的HLS均为0并正确拒绝,日志 `E:/Temp/nk-c545-audio/`。不证明扬声器发声。以下保留较早版本记录,当前字幕/续播与Mac补验见顶部及Nekophage STATUS。 **本地夹具链路已验收且已进默认套件**(Nekophage `78ee0e1`,后由 `a3a4ed7`/`c7fc631` 把视频与字幕探针并入 `desktop-probes.sh`,无外部变量 11 PASS / 3 SKIP):真实 Windows WebView 验证 HLS.js/fMP4/字节范围/Referer/Cookie/视频帧回读,以及原生 MP4。页面自身暂停事件落盘、磁盘重读与「继续观看」实际恢复小数秒位置;已移除手工进度注入,失败探针返回非零退出码。`30d460f` 再完成普通源管理的类型选择、文件/URL 安装与持久化:真实 Windows 原生窗口安装两个视频源,关闭进程后重启仍可选,从 GUI 安装记录恢复后的 HLS 实际解码与续播通过。类型冲突、停用更新、磁盘恢复有 race 用例。`0d8ce15` 完成搜索/分页、详情与播放准备的分代取消,控制器接真实 Core/JS/慢 HTTP 验证替代/切源/关闭时连接停止、下一次读取成功、迟到结果不覆盖新状态和分页不混用输入词;Windows HLS 窗口回归仍可实际解码并续播。列表与详情加载状态分开,已开始播放的会话不随关闭搜索窗停止。音轨改用实际解码字节判据:`8f1d812` 的清单声明判据已作废(夹具可虚报 AAC),现在 HLS.js 路径实读 `18537` 字节、原生 MP4 路径实读 `17802` 字节,两个无音轨反例均为 0 且探针非零退出(`e27d5f7`、`9e2bdda`)。这仍不等于扬声器实际发声。字幕已按投递链路验证(`41a89da`):Core 重写 `EXT-X-MEDIA` URI,播放器经代理取到 `subs.m3u8` 与五个 `.vtt`,`showing` 轨读回 10 条 cue,首条文本为夹具内容;无字幕组素材为 0 并失败。`13e74cb` 将强制第一条改为尊重 `DEFAULT=YES`,无默认时关闭,并加入语言/关闭选择框。英文第一条、中文默认第二条的反例布局验证选中中文,只读 showing 轨的活动文本;两条 DEFAULT=NO 时保持 disabled。真实 Windows 窗口截图已看到中文叠加(`E:/Temp/desktop-subtitle-visible-window.png`)。旧轮的 `foreground_unavailable` 缺口已补验:0.2.4 安装包在同一暂停 0:01 画面完成 English 可见→关闭后文字消失→中文恢复,三张窗口截图与回执 `E:/Temp/desktop-subtitle-language-024-receipt.json` 对应;最终夹具使用支持 Range 与鉴权的 Go 文件服务。打包时又发现真实缺陷:默认走原生 HLS 时 WebView2 忽略字幕组,实测不请求 `subs.m3u8`;`851884d` 改为优先内置 HLS.js,原生仅作回退。`0.2.4` 打包 GUI 内已看到「第0段字幕 / 字幕渲染检查」与 `subs.m3u8`、`sub0.vtt` 请求。字号/位置样式、macOS、iOS 与在线源字幕仍未验证。**待验证**:PiP、macOS 与真实站点;DRM/嗅探/DASH 明确报不支持。最新本地交付为 `0.2.7`(`87e2ffc`),包含清单 Range 修复,包内 HLS/中文字幕、鉴权、字节范围及页面进度落盘通过;本包跨进程续播经界面重新登录夹具后已补验,英文/关闭字幕操作仍待验证,详见 P2-2;完整语言/关闭操作的旧证据仍保留原提交归属 **2026-11-08 补：请求头成为常驻回归**。`desktop-probes.sh` 新增三条：`hls_probe.js` 的 `-video-auth -video-hlsjs` 正向（真实 WebView 解码、`11` 段 `bytes=` Range、暂停落盘 `2.104s`、重开「继续观看」恢复），以及去掉 Referer / 去掉登录 Cookie 的两条负向（各得到 `auth rejected` + HTTP 403 + 非零退出）。这把「源声明的 Referer 与 Cookie 真的经媒体代理到达上游」从历史安装包证据升级为当前 pin 的默认回归；全套 **24 PASS / 0 FAIL / 0 SKIP**、`check.sh` **7/7**。日志与回执 `E:/Code/deliveries/2026-11-08-video-auth-probes/`。仍不证明真实站点、真机、macOS 或扬声器发声。 **2026-11-08 二次补**：`-video-auth` 与 `-video-subs` 首次组合，验证 Core 重写后的 `EXT-X-MEDIA` 字幕 URI 仍带 Referer/Cookie（12 次 `/sub*` 请求、0 次 403、`showing` 轨活动文本 `字幕渲染检查`），全套 **25 PASS / 0 FAIL / 0 SKIP**、`check.sh` **7/7**。回执 `E:/Code/deliveries/2026-11-08-video-subs-auth/receipt.json`。 **2026-11-08 三补**：原生 MP4 解码路径也验证带 Referer/Cookie（`decoder=native`、0 次 403），全套 **26 PASS / 0 FAIL / 0 SKIP**（含 1 次既有对话框 flake 重试）。回执 `E:/Code/deliveries/2026-11-08-native-mp4-auth/receipt.json`。 **2026-11-08 CI 结论**：`ios-release.yml` run `42456712087`（`cba7756`）`success`，其中 “Magpie loopback HTTP acceptance” 步骤 `success`，回执 `E:/Code/deliveries/2026-11-08-magpie-ci-verified/receipt.json`。 |
| P4 | 账号与扩展能力 | Jellyfin/Emby/Plex、Bangumi、TMDB、Pixiv 登录逐项真连;Trakt 同步与制作台再评估;**在线弹幕后置,由插件实现,不进客户端主线**(见本页顶部 2026-11-07 决策)。不得把未实现功能误归为“只缺账号” |

## 需要外部条件的事项

| 事项 | 依赖 | 处理方式 |
|---|---|---|
| 灵动岛、后台、通知、真实手势观感 | 合适 iPhone 与用户设备操作 | 提供 AltStore 测试版和短操作步骤,等待事实反馈 |
| Bangumi/供应商/Pixiv 登录 | 用户授权的真实账号 | 用到再连接,不将凭据写进仓库或日志 |
| 媒体服务器与 TMDB | 可访问服务与相应凭据 | 其余工作先推进,假传输不当作真服务证据 |
| 桌面公开发布 | Nekophage 尚无远端 | 先准备可运行包,不擅自创建公开仓库 |

## 不再重复做的旧待办

代码核对已确认:iOS 传输层有分块大小限制、提前取消登记与跨 origin 鉴权头清理;ImageLoader 有共享等待者计数;标准 AI 设置/界面已接入;Magpie 已接 `MobileNewMagpieWithStream`。这些不再按“尚未实现”排队,后续只针对真实失败修复。`magpieplugin.Sender` 保留为无生产调用方的库接口,不为了证明它有用而硬接入桌面 Magpie。

`accessibilityIdentifier` 的缺失不等于 VoiceOver 文案缺失。发现页这次的树显示标签存在,标识符被祖先覆盖;它证明的是自动化可寻址性问题,不能据此声称 VoiceOver 已被验证或不可用。

## 推进与停止规则

每轮完成一个具体动作并留下证据:修复复现问题、运行相关用例、验证真实界面或交付安装包。只读旧日志、反复查询未变化的 CI 或重写文档不算新的工程完成。适当验证即可,不为推进额外堆检查器。

既有 Orca Worker 负责 Mac 测试,Lead 负责分析、实现、契约与发布整合;不要重复启动同一套测试。完整日志写文件,汇报只给命令/结果/路径,失败附最相关错误行。

本轮阶段目标是完成 P0 至 P3 中可在现有条件下独立验收的工作;需要外部条件的项目单列交接。只有逐项验收完成才能宣告该阶段完成,不能因一次发版完成就提前终止。P4 的新增产品能力后置,不自动扩大本阶段范围。
