[English](UNVERIFIED.en.md) · 简体中文

## 标准 AI 的流式界面在 2026-11-06 转入已验证

`UITests/ZZStandardAIStreamTests.swift` 两条用例在 CI 的 iPhone 17 Pro / iOS 26.5 模拟器上通过（run `42193319262`）：流式书写中的「正在写…」与增量文字、完成后的「流式」标注与四段文字、请求体 `stream:true` 且只有一次请求；断流时报 `源返回错误:AI stream ended before completion` 且半截答案不被保留。证据与三处用例自身的修复见 [STATUS](STATUS.md)。

仍未验证：真机、真实供应商的增量行为、iOS 26 运行时，以及服务端在零正文时是否提前交响应头。

## AetherEngine 7.58.0 升级后的播放：画面推进已验，其余仍待（2026-11-06 更新）

**更新**：CI run `42199314431` 上 `testVideoPlaysTheSourcesClip` 通过，用例现在要求引擎时钟在 4 秒内增长，即画面确实在推进、源声明的 `Referer` 传到了引擎（见 [STATUS](STATUS.md) 同日条目）。下文列的字幕、HLS、取消、后台、PiP 仍未在 7.58.0 上重跑。

### 原记录

播放引擎从 `7.53.1` 升到 `7.58.0`，依据是 API 面核对 + CI：把两版的公开声明去掉行号后逐条比对，**我们用的 21 个符号全部还在**，5 条消失的声明（`timeRange()`、`isPictureInPicture` 式的便利属性等）在 7.58.0 里以同名或改名后的形态存在（`SoftwarePiPSource.timeRange()` 仍返回 `CMTimeRange`，`isPaused` 从 `engine?.state != .playing` 改成走快照）。CI `42153619870` 编译并跑完 482 项 kit 测试与整包构建，**但这不等于播放通过**。

没有重跑的：真机/模拟器播一次视频（8 秒以上，看到画面推进）、字幕轨切换、HLS 主播放列表、取消播放、后台行为。7.56.0 把软件通路的画中画控制器改成自己建（`SoftwarePiPSource.makePictureInPictureController()`），而我们的 PiP 代码仍是 `pip.update(player:software:)` 的旧形状——编译通过，但 `AVPictureInPictureController` 在模拟器上本来就不支持，无法判断行为是否变了。

下一步：用 `UITests/Fixtures` 里的本地 HTTP 媒体夹具在模拟器上重播一次，至少覆盖画面推进与字幕；PiP 与后台仍归真机项。

## 服务包能力在 2026-11-05 的验证边界

已验证（模拟器 iPhone 17 / iOS 27.2，真实入口）：空列表；从系统文件选择器导入；列表显示名字/版本/权限；滑动移除与确认文案；缺 `service.json` 的包被拒并显示 `服务包未被接受：service: package has no service.json`；`ping` 直返；服务 `fetch` 经 App 传输（夹具记录到 App UA 的请求）；只申请 `storage` 的包在 fetch 时被指名拒绝。

仅有 CI 证据（Kit 473 tests）：`describe()` 方法清单、账号值的 Keychain 存储与「账号值」界面、`ServiceCallWithSecrets` 的权限与缺键拒绝。

未验证：真机上录入账号值并运行、真实第三方服务包、服务包声明所需键名的机制（不存在，键名由使用者决定）、Core 的 `secrets` 与客户端 Keychain 在真机锁屏后的行为。


## PiP 与后台在 2026-11-05 仍是真机项

模拟器上 `AVPictureInPictureController.isPictureInPictureSupported()` 为假，播放器的画中画按钮因此不渲染（`App/VideoPlayerView.swift:503`），所以 PiP 无法在模拟器验证；后台只证明进程存活（`app_state=4`），后台续播与音频输出需真机。视频播放、下载三例、标准 AI 与 Magpie 的夹具闭环已在 iPhone 17 / iOS 27.2 上通过，详见 [STATUS](STATUS.md) 同日条目。

## 主题 HTTPS 安装与长按编排在 2026-11-05 转入已验证

真实本地 CA + 18791/18792 夹具下的三条主题链接用例（HTTPS 安装/选中/重开、非法主题保留选择、明文 HTTP 被客户端拒绝）在 iPhone 17 / iOS 27.2 上 3/3 通过；`testBoardLongPressAndSizeSurviveRelaunch` 1/1 通过；iPhone 竖/横与 iPad 竖/横的明暗 16 张截图中无裁切、重叠或不可读文字。此前"夹具缺失导致跳过"的记录不再是当前状态。

仍未验证：iOS 26 运行时（本机只有 27.2）、真机、后台/锁屏、Live Activity、PiP、实际扬声器、真实账号；横屏的坐标级元素测量不可靠，结论为整图统计加目视。详见 [STATUS](STATUS.md) 的同日条目。

# 待验证清单

[English](UNVERIFIED.en.md) | 简体中文

## 索引入口进入正式主线与0.3.6候选（2026-11-04）

Core `25e5ca3` 已发布main，四作业CI通过；iOS主线 `e64847e` 的pin指向它，产品代码与Mac受测 `107286d` 逐文件一致。Mac隔离副本上 `swift test --filter SourceLibrary --no-parallel` 为13个测试/4个套件、0失败，索引身份用例实际执行并通过；设备App的Release编译与UI测试编译均exit0。

仍未验证：UI测试只编译未执行；真机安装、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号仍单列；本机Windows不能替Mac执行Swift测试，上述计数只属于Worker回传的日志范围。

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

## 0.3.4发布与下载图片完整性修复已验(2026-11-04)

Orca Worker已在ac8e2b6基线/Core3be57b5修复两项实际缺陷:离线字节不再二次执行源的onResponse,解码后的modifyImage仍保留;raw在onResponse后以64像素缩略图验证可解码性,坏字节走既有镜像回退或DownloadStore失败/重试,不形成完成章节。有效PNG/JPEG原字节保持不变。此前已保存的坏章节不自动删除,仍需用户删除后重新下载。

真实Core配合独立URLProtocol的旧实现负向用例为4 tests/7 issues,包含二次转换not an image、200坏字节被接受及镜像未请求。最终新增6条回归通过;Xcode27.2(27B52)/Swift6.4.2完整 `swift test --no-parallel` 为436 tests/81 suites/0 failures。模拟器最终build-for-testing通过,同次串行BadImage→Reads两例均通过(58.922/52.680秒):真实本地HTTP坏图产生重试项,恢复PNG后重试成功,停服再进入下载章节看到实际“第 1 页”Image。初次fixture actor编译错误、“1 页”与实际“1/1”等待错误及端口释放失败均保留,不记为最终产品失败。

原日志仍在Mac `/tmp/nk-ac8-image-integrity/`,最终单测 `swift-test-final.log`、构建 `ui-build-final.log`、UI `ui-targeted2.log`。Windows的 `E:/Temp/nk-ios-034-evidence/mac-image-integrity-report.json` 是Worker回传回执,不冒充已复制原日志。Mac缺tree-sitter只跑173文件规则检查,不算语法解析通过。

Lead已恢复25575字节补丁,SHA256为691086b271d0a46cfc1cc9f11db1ffe8fe5bb961712240fd968f912cec7dee75;四个整合Git文件逐字节SHA均与Mac受测文件一致,回执 `E:/Temp/nk-ios-034-evidence/patch-integrated.json`。App/Widget的0.3.4/16已正式发布,tag指向66454e86f4aa3e1bbba94f64cb29b56783513a82。CI41749091496首次运行成功,公开IPA HTTP200/29,459,904字节、SHA256 c31d240513f2f82d97a507d8255bf586a28a8e518eff03d3a027c16f6571454c,ZIP CRC、两端版本/最低26.0和Core3be标识均通过。AltStore刷新41752744406成功,仓库main e81249d及GitHub Raw/CNB/固定Release三个公开入口都核到0.3.4/16,版本、大小、最低系统和下载地址一致,图标HTTP200且实际解码。交付 `E:/Code/deliveries/2026-11-04-nekularity-034/README.md`,完整回执 `E:/Temp/nk-ios-034-evidence/release-accepted.json` 与 `altstore-accepted.json`。Core pin仍3be57b5。以上不增加历史完整UI27/0/0计数,不包含真机/后台/真实账号。

## 模拟器跨进程进度恢复(Orca Worker回传,2026-11-04)

0.3.4/16、Core 3be57b5的专用模拟器定向测试中,第一App进程2020播放30秒HLS至7.211756秒,暂停并正常关闭播放器页,随后终止App。第二进程2099通过同一视频源的搜索和分集页重新进入,诊断起点7.000000秒,约2.08秒后自动播放至8.342057秒。修正测试PID千位逗号解析后,定向XCTest为1 test/0 failures。测试结束后磁盘历史为7秒/30秒/23%;这不是两次进程之间单独抓取的磁盘快照。

该结果证明上述搜索/分集路径的模拟器跨进程位置恢复,不证明“继续观看/本地条目”直接入口,也不证明真机、后台或PiP。诊断构建临时读取PID、起始位置和时钟;产品源码已还原并重建安装,受测VideoPlayerView.swift还原SHA为0daef0ed11c4cd12e4918ed0f89d30e8066a37c75011974a94f1d76c1fdbff37。原始日志在Mac `/tmp/nk-ios-cross-process-resume-evidence/`,本地 `E:/Temp/nk-ios-034-evidence/cross-process-worker-report.json` 仅是Worker回传记录,不是原日志副本。旧界面直接入口的UI验收按整体UI/UX重写计划后置。

## Mac关窗与Core主线结果(2026-11-04)

Orca Worker在用户解锁后,以隔离资料启动已核验c545212包,原生关闭按钮一次点击后窗口消失、原进程退出0,无信号终止。Core单提交main c0f0dfa在自身SHA完成三平台Go和Apple SDK/Swift四作业CI。详见[STATUS](STATUS.md);用户设备、账号与分发选择仍单列。

## Mac主题与构建补验更新(2026-11-04)

原Orca Worker已回传12张本地封面的明暗/横竖四组合、两处深色蓝字4.665:1、精确736e364本机430 tests/80 suites与IPA终态。详情进入只证明导航,源未安装不算内容加载;本机Xcode27.2/SDK27.2的IPA与正式CI发布包分别记录。详见[STATUS](STATUS.md)。离线图片正/负/恢复已验,完整受测文件与串行隔离修复已随a7b5fbd整合,历史完整UI计数不变。

## 0.3.3发布验收更新(2026-11-04)

736e364的0.3.3/15已发布:CI第二次成功,IPA HTTP200/29,457,850字节、摘要、App/Widget元数据与Core pin通过;AltStore修复生成步骤认证后,仓库及三个公开入口均0.3.3/15。详细回执见[STATUS](STATUS.md)。断网页图正/负/恢复对照已过Orca Worker实测,产品未改,测试已随a7b5fbd整合,连续负例→正例2/0。其余已派Mac任务仍按各自终态记录;真机、后台、账号等外部项不计通过。

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

## 主题矩阵补验:空状态已查看,最大字号与 iPad 已转入已验证(2026-11-05)

**这一节的范围已被取代。** 2026-11-05 在 iPad Pro 11-inch (M5)/iOS 27.2 与 iPhone 17/iOS 27.2（动态字体 AX5）上重跑了完整套件：iPad 29 例/23 通过/6 跳过/0 失败，AX5 29 例/20 通过/9 跳过/0 失败，两轮都不再有"收藏卡片一字一行"或底栏遮挡导致的失败；设置页滚动到「外观」并切换 跟随系统/亮/暗 三态也已在模拟器上实测通过（暗色重开后保持）。细节见 [STATUS](STATUS.md) 的 2026-11-05 条目。

仍然**不在**已验证范围：真机、后台/锁屏、Live Activity、PiP、实际扬声器与真实账号。下面这段是当轮（2026-11-04）当时的记录，保留作为历史。

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
