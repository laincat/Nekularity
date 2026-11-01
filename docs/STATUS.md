# Nekularity 状态

[English](STATUS.en.md) | 简体中文

更新:2026-10-31。

## 宿主接口形状已核对

`CoreHost` 的 21 个方法逐个比过 Core 里 `apple/CoreSmoke` 的 Swift 宿主实现(那份在 CI 里真的编译并跑过):返回对象的方法由 Clang 导入成 `(参数…, error: NSErrorPointer) -> String`,返回 `void`/`Bool` 的方法导入成 `throws`。例如 `http(_:error:) -> String`、`saveData(_:dataKey:valueJSON:) throws`、`writeClipboard(_:) throws`、`readClipboard(_:) -> String`,Nekularity 的写法与之一致。这只是签名对得上,不等于编译通过——真正的类型检查仍要等 Mac 上那次 `swift build`。

界面层调用的 Kit 成员也逐个核过:`library.comicSources / sources / refresh / install / loadIndex / restoreFailures / setEnabled / remove`,`core.search / searchOptions / explore / explorePages`,`shelf.recentHistory / record / forgetHistory / folders / createFolder / renameFolder / deleteFolder / remove / lastError`,`searches.add`,`store.loadSetting / saveSetting` 全部存在且参数对得上。
| 视频 | 视频源是 Core 里的插件(`video-js`、Kazumi 规则、内置源),客户端只负责播:`CoreClient.videoSearch/videoDetails/videoPlay` 三个调用;「视频」页选源、搜索、加载更多;详情页按站点给的线路分组列出剧集;点剧集后向源取播放地址,带 `Referer`/`User-Agent` 交给 **AetherEngine** 播放(AetherEngine 只依赖在 App target,`NekularityKit` 不引入,免得 `swift test` 拉二进制框架)。源若只给「嗅探播放页」而不给直链,界面明说这条路径尚未实现,而不是给一个黑屏。**尚未编译、未在真机或真实视频源上验证。** |
| 下载 | `DownloadStore`:把一章的原始字节存到 `Downloads/<源>/<漫画哈希>/<章节哈希>/<页码>.img`,清单写在 `manifest.json`;地址来自 Core 的 `chapterImages`,取字节走 `ImageLoader.raw`(与阅读器同一套请求规则、同一份 `onResponse` 改写)。`ImageLoader` 在联网前先问它,所以**下载过的章节在没有网络时照样能读**,阅读器本身不需要知道下载的存在。详情页长按章节下载、右上角可下载全部,书架右上角进「下载」页看占用并删除。**尚未在 Mac 上编译验证。** |
| 主题 | 主题是**数据不是代码**:`Theme` 一张 JSON(强调色、背景、卡片表面、圆角、是否强制深浅),内置「跟随系统」「Miuix」「Miuix 深色」三套;用户从「文件」导入一张 JSON 即可装新主题,存在 `Themes/<id>.json`,id 会被消毒以防写到目录外,安装不改变当前选择。「设置」页里选主题、看下载占用、看版本与 Core 提交。应用方式是在根视图统一 `.tint` + `preferredColorScheme`,不逐个界面改,否则会变成「只有部分界面生效」的样子。**尚未在 Mac 上编译验证。** |
| 本机视频库 | 「视频」页分成**本机 / 在线源**两半。本机侧:`VideoLibraryStore` 把导入的视频**复制**到 `Media/Videos`(不用安全作用域书签——别的 App 容器里的书签在对方移动或替换后就失效,「我的视频不见了」比多占一份磁盘更糟),记录时长与播放位置;「继续观看」只挑**看过 30 秒以上且未看完**的;播放器用 `AetherEngine.load(url:startPosition:)` 从上次位置开始,关闭时把位置写回。文件在外部被删掉时不会继续留在列表里。**尚未在 Mac 上编译验证。** |
| 首页卡片 | 卡片分两类:**本机模板**(继续阅读/收藏/最近搜索/已下载/本机视频/视频源)与**源分区**——源在 `explore` 里声明的推荐、排行、分类,可直接放到首页,取的就是「浏览」里同一个分区,因此源不需要知道首页存在。版式是两列瀑布(`MasonryLayout`,按最短列摆放),编辑页可拖动排序、隐藏、删除,并能「从源添加分区」。**尚未在 Mac 上编译验证。** |
| 资源库入口 | 「资源库」除媒体服务器与模块外,加了四个入口:**全源搜索**(打开搜索并默认「全部源」)、**书库**(书架与收藏夹)、**视频**(在线源 + 本机)、**下载**。入口放在这里而不是 tab 栏,因为栏位只有四个,第五个会把末位折进「更多」。**尚未在 Mac 上编译验证。** |
| Pixiv 源插件 | `sources/pixiv.js` 是一个**普通 JS 漫画源插件**,用 pixiv 匿名可读的接口:排行(`ranking.php?format=json`,日/周/月/新人/原创五档)、搜索(`/ajax/search/artworks`)、作品详情(`/ajax/illust/{id}`)、图片列表(`/ajax/illust/{id}/pages`)。**不碰需要 OAuth 的 `app-api`**——插件不该持有客户端凭据,所以收藏/关注这类要登录的功能没有做。两条实测教训写在注释里:手机 UA 下 `ranking.php` **即使带 `Accept: application/json` 也只回 HTML**,必须用桌面 UA;`i.pximg.net` 不带 `Referer: https://www.pixiv.net/` 一律 403,所以 `onImageLoad` 必带该头。已在桌面端用真实站点验证:搜索 60 条、详情、18 页图片 164ms、五个榜单 250 条、标签点击可搜。 |
| 视觉 | 按参考 App 的观感做了一套共享面:`DesignSystem`(渐变画布、`.glassCard()` 玻璃卡片、`Pill` 胶囊按钮、`SectionHeader` 带箭头、`PosterTile` 带「看到 mm:ss」与进度条、`StatValue` 大数字),并换成**悬浮胶囊 tab 栏 + 独立圆形搜索按钮**(标准 `TabView` 画不出这个形状)。卡片圆角与强调色取自已选主题,所以自定义主题会同时改变这套观感。**尚未在 Mac 上编译验证。** |
| 多账号（环境） | `ProfileStore`:每个环境有自己的 `sources.json`、`cookies.json`、`shelf.json`、`searches.json`、`Magpie/`、`Downloads/`、`Media/`,目录是 `Profiles/<id>`;主题保持全局(外观不是账号)。切换环境会**重建 Core**——因为 Core 就是按该环境的源记录与 Cookie 建起来的,不重建就只是换皮。AI 授权在 Keychain 里按环境分服务名,首个环境沿用原服务名,避免升级后静默掉登录。从旧版升级时根目录的旧文件会搬进「默认环境」。入口:「我的」顶部环境条 +「设置 → 环境」,**尚未在 Mac 上编译验证**。 |
| 观看历史 | 看视频和读漫画写进同一份历史,日历、热力图与当天统计都算上;视频行不伪装成漫画(不给可点的详情路由),片长未知时百分比留空而不是编一个。同一集再看一次只是把它挪到最前。 | 单测(编译待验证) |
| 源批量更新 | 「漫画源」菜单里一次更新所有**有网址来源**的源,一个弹窗报三种结果:更新了(名字 + 旧版→新版)、已是最新、失败(带原因)。从粘贴文本安装的源没有可更新之处,直接跳过而不是记成失败——那是安装方式的事实,不是源的错。 | 单测(总结文案),实际拉取待验证 |
| 媒体服务器 | Jellyfin / Emby:填地址、账号、密码一次完成连接,令牌进钥匙串(按环境分开),服务器记录本身不进令牌。能列媒体库、列影片(时长/年份/简介/海报/已看进度)、按需播放,看过的照旧写进同一份历史。自签证书**只对局域网地址**放行,公网地址不走例外。Plex 用另一套接口,明确报错而不是发一个坏请求。**尚未对真实服务器实测**。 | 11 个单测(假传输),真实服务器待验证 |
| 统一媒体库 | 资源库 → 媒体库:本机文件与所有服务器影片合成一份列表,可按片名**和剧名**搜索,有「继续观看」区,按来源分组(本机排在前,因为断网也能看)。某台服务器连不上只影响它自己那组,不会遮住别人。 | 5 个单测(合并/搜索/续看/分组) |
| 播放体验 | 倍速(0.5–2×,按引擎实际上限)、**字幕轨菜单**(含「关闭字幕」,标签用语言名而不是六个「字幕」)、**画中画**(原生通路)、以及**记忆位置**:同一环境看过的会从上次位置继续,「已看完」和「才看 2 秒」都不会被当成位置。服务器自己的进度与本地进度取更靠后的那个,免得手机上看过的被服务器旧位置倒回去。画中画只对引擎给出 `AVPlayer` 的原生通路显示按钮,软件解码通路的 PiP 尚未接。 | 1 个单测(续播判断),PiP 需真机 |
| 阅读日历 | 「我的」→ 阅读日历:按月网格,每天按记录条数着色,点开看当天读了/看了什么(漫画行可进详情,视频行显示进度)。显示连续天数、总记录数、有记录的天数;跨月翻页;「今天」一键回到当月。**没有追剧提醒**:漫画源只报已存在章节、不给播出日期,媒体服务器只报它已持有的剧集,凭空造一个「即将播出」是不可接受的,提醒留到有元数据源(G9)之后。 | 5 个单测(网格对齐/按日取/计数/连续) |
| 元数据(TMDB) | 设置里填 TMDB key 或 v4 令牌(存钥匙串,按环境分开),保存时**当场验证**并告诉你能不能查到剧集;媒体库加载服务器时会用剧名去对剧集(每次最多 6 个、已缓存的不重复请求),日历据此显示「即将播出」并注明日期来自 TMDB。v3 key 走查询参数、v4 令牌走 Authorization 头,自动判断不用问你。日期按 UTC 解析,免得跨时区把晚间播出挪一天。**需要你的 TMDB key 才能实测**,没有 key 时一切照常、只是没有「即将播出」。 | 9 个单测(假传输) |
| 弹幕与跳过片头 | 弹幕读**本地文件**(B 站 XML / DanDanPlay JSON),不需要任何账号;播放器里可开关、可加载、可清除,只画最近 4 秒并限制条数(整份列表每帧过滤是掉帧的老路)。片头**不做自动识别**:每部剧的片头长度不同,猜错会切掉第一句台词;改为「把当前位置标为片头起点」记一次(默认 90 秒),之后同剧靠「跳过片头」按钮,标记按剧存、能持久化。在线弹幕源需要第三方账号,未接。 | 7 个单测(解析/时间窗/容错/标记/持久化) |
| 本地漫画 | 资源库 → 本地漫画:导入图片文件夹或 `.cbz`/`.zip`,页面按**自然顺序**排(1,2,10 而不是 1,10,2),阅读器横滑翻页并记住停在第几页;删除会连同文件一起删。压缩包自己解:`ZipReader` 读中央目录,只支持漫画会用的 stored 与 deflate,`__MACOSX`、隐藏文件、非图片一律不当页。故意不放进「漫画源」——本地漫画没有脚本、没有网络、也没有能和源对齐的 id。 | 7 个单测(两种压缩方式/过滤/排序/导入/删除) |

## Mac 上已经跑过的检查

**最新一轮(2026-11-01,树 `67c501a`,Core pin `d81445f`)**:`scripts/verify-ios.sh` **EXIT=0**,**13 个 UI 用例全部 PASS(0 FAIL / 0 SKIP)**;`swift test` **229 tests / 43 suites passed**,`check-seed.sh` 确认种子与仓库夹具一致,未签名 App 构建、build-for-testing、安装均通过。这一轮新增**分类页**:同时断言可选项、结果,以及切换取值后**选中态**真的改变;书架用例也改成先断言 `书架` 导航栏存在——两者都是为了让断言不会因为「元素在上一个界面也存在」而误通过。

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
