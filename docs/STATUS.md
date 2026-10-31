# Nekularity 状态

[English](STATUS.en.md) | 简体中文

更新:2026-10-31。

## 宿主接口形状已核对

`CoreHost` 的 21 个方法逐个比过 Core 里 `apple/CoreSmoke` 的 Swift 宿主实现(那份在 CI 里真的编译并跑过):返回对象的方法由 Clang 导入成 `(参数…, error: NSErrorPointer) -> String`,返回 `void`/`Bool` 的方法导入成 `throws`。例如 `http(_:error:) -> String`、`saveData(_:dataKey:valueJSON:) throws`、`writeClipboard(_:) throws`、`readClipboard(_:) -> String`,Nekularity 的写法与之一致。这只是签名对得上,不等于编译通过——真正的类型检查仍要等 Mac 上那次 `swift build`。

界面层调用的 Kit 成员也逐个核过:`library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`,`core.search / searchOptions / explore / explorePages`,`shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`,`searches.add`,`store.loadSetting / saveSetting` 全部存在且参数对得上。

## Mac 上已经跑过的检查

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
| 接口面(免 Mac) | `scripts/check-surface-offline.sh` 用 gobind 在 Windows 上生成 ObjC 头,再跑与 Mac 同一个选择器清单:9.7 秒、18/18。以前这件事只能在拿到 xcframework 之后做,那时一个方法不匹配已经花掉一趟传输。顺带确认清单本身是对的 —— 无参方法生成的是 `auth:`/`models:`/`savedAuth:`,不是 `…WithError:` |
| 静态检查(测试替身) | `check-swift.py` 会核对 `Tests/` 里 conform `MagpieRunner.Core` 的替身是否缺方法。协议新增方法时,这类缺失在 Windows 上是静默的、在 Mac 上是 `swift test` 编译错误 —— 代价是一整轮验证。用删掉 stub 的副本反向验证过,它会准确报出 `RefusingCore lacks readPackageArchive` |
| 分类浏览 | `CoreClient.explorePages` 与 `explore` 支持四种 browse 类型(单页多分区、多页列表、混合、多分区页);`BrowseView` 用标签切换分类、分区标题吸顶、分页、下拉刷新 |

## 未验证

- **ATS 策略已定**:`App/Info.plist` 里 `NSAllowsArbitraryLoads = true`。漫画源由用户自行安装,主机无法预知,逐主机例外做不到;上架理由写在该文件与 README 里。已在读到的四个真实源上确认它们全走 https(0 处 http),放行只是不挡未来的 http 源。这个改动**已经过真正的 Xcode 构建验证**(2026-10-31,同一台 Mac):XcodeGen 从官方发布页的二进制包取用(2.46.0,放在 `/tmp/xcg`,**没有装 Homebrew、没有进系统 PATH**),`xcodegen generate` → `xcodebuild -scheme Nekularity build` 得到 `BUILD SUCCEEDED`;产物 `Nekularity.app/Info.plist` 里读出 `NSAllowsArbitraryLoads = true`,`-showBuildSettings` 回显 `INFOPLIST_FILE = App/Info.plist` 与 `GENERATE_INFOPLIST_FILE = NO`,`Copy Bundle Resources` 相关报错 0 次(即 `excludes: [Info.plist]` 生效)。`scripts/verify-ats.sh` 把这条链路写成脚本并接进 `verify-ios.sh`,现在每次整树验证都会跑真实 App 构建而不是退化成类型检查。
- **真机**:没有在 iPhone 真机上跑过。**模拟器已经跑起来了**(2026-11-01,首次):装、启动、界面出来、无崩溃、Core 框架加载失败 0,约 0.7 秒到界面 —— 详见上面「模拟器上第一次真的跑起来」那段。但那是空容器,主线(装源→搜索→详情→阅读→书架)还没在设备上走过。
- **签名与归档**:`xcodebuild -scheme Nekularity` 用的是 generic/platform=iOS 且不签名,`** BUILD SUCCEEDED **` 只证明能编译,不证明能装到设备上。没有 XcodeGen,所以也没有 `.xcodeproj` 与 App bundle。
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

**2026-11-01 又把 pin 移到 `d98e505` 的原因**:Core 修了两处搜索参数读取 —— 选项格式「`值-文字`」的左边允许为空(`-<none>` 是「值为空」,不是字符串本身),以及多选筛选组的值是一个 JSON 数组(`SearchOptionGroup.DefaultValues`)。两者都会让源把 `undefined` 或 `-<none>` 拼进搜索请求。**iOS 端还没接这两处**:协议本身的解析在 Core 里,所以 iOS 装源后已经受益;但客户端侧把多选组拼成数组、以及只声明 `search.loadNext` 的源按游标翻页,仍是桌面端已有、iOS 待补的两项,记在「下一步」里。

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
