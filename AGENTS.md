# Nekularity 开发约定

[English](AGENTS.en.md) | 简体中文

本文件写给参与开发的人和 AI 助手。修改代码前请先阅读。

## 原则

- 业务逻辑放在 VeneraCat Core。客户端只负责界面、网络、WebView、播放器和存储;需要新的逻辑时先改 Core。
- 界面只调用 `CoreClient`,不直接使用 gomobile 生成的 `Mobile*` 类型。
- 不在主线程调用 Core。gomobile 方法是阻塞的,`CoreClient` 把它们放到后台执行。
- 每个源的 Cookie 和登录状态互相隔离:Cookie 按 Core 给出的 `partition` 分别存放,不使用 `HTTPCookieStorage.shared`;人机验证使用非持久化的 WebView 数据存储。
- JSON 保持键顺序和数字原文:Core 的结果用 `OrderedJSONDecoder` 或 `JSONValue.parse` 解码,不经过 `JSONSerialization` 或 Double。
- 不要从 AGPL 项目(Animeko、AnimeFlow)或没有许可证的项目(AniCh)复制代码。不放入第三方凭据、账号或站点密钥。
- 许可证是 **LGPL-3.0-or-later 附 App Store / DRM 例外**(见 `LICENSE`,GPL-3.0 全文在 `COPYING`)。新文件沿用同一许可;引入新依赖前先看它的许可证能否并进来,不能就只有重写。

## 仓库约定

- 根目录只放工具链或惯例要求必须在根目录的文件。
- 所有 `.md` 都提供中英双语:`X.md` 为中文,`X.en.md` 为英文,顶部互相链接。修改其中一份时同步修改另一份,用 `scripts/update-pair.py` —— 它先在两边都找到锚点才写,避免只改了一边。`scripts/check-docs.sh` 会检查配对、根目录以及两边的表格行数与标题数。
- `Vendor/` 存放编译出的 Core,不提交。
- **gomobile 的两种导入形状不要混**:返回 `NSString*` 的方法保留 `NSError**` 形参
  (`magpie.call(export, argJSON:, error: $0)`);返回 `BOOL` 的方法导成
  **`throws` 且返回 `Void`** —— 那个 BOOL 被 `throws` 吃掉了,既没有 `error:` 形参
  也没有 `Bool` 可判(`try magpie.loadPackage(json)`,要中文提示就包一层 `do/catch`)。
  另外 **Clang importer 会按介词拆选择器**:`cancelSignIn:error:` 变成
  `cancelSign(in:)`,别照头文件名字直写。
  写反了只有 Mac 上的编译器会发现。

## 检查

```sh
scripts/check-docs.sh
scripts/check-swift.sh     # 解析全部 Swift 文件,抓语法错误(不需要 macOS)
scripts/verify-ios.sh [xcframework]   # macOS:文档、语法、swift test、App 构建或类型检查
swift test                 # macOS,需先运行 scripts/fetch-core.sh
```

`check-swift.sh` 只解析,不做类型检查:名字、协议和平台 API 仍要 `swift build`
或 CI。它用的 tree-sitter 语法比 Swift 6 落后一点,`scripts/check-swift.py` 里
列出了要先抹掉的记号。

## 作用域问题本地查不出来

`check-swift.py` 只做语法与几条文本规则,**不做作用域/类型检查**。把 `@Environment` 的 `library`、`@State` 的 `model` 用到另一个类型里,语法完全合法,只有 Mac 上编译才会炸——这一轮就发生过一次(辅助方法落进了 `SearchModel`,而它没有 `library`)。

试过把它写成规则,但启发式在整个仓库报出 12 处候选、**全部是误报**(参数与局部变量同名),所以没有加。可行的替代是:改动某个 View 后,自己在改动涉及的类型块里数一遍——用到 `model.` / `library.` 的地方,那个类型里有没有相应的声明。

## 改一处、通读一遍

改一个字段的可选性、一个方法的访问级别、或者把一段代码搬进另一个 suite 时,**把同一函数、同一类型里所有用到它的地方一次看完**。这几类错误语法上完全合法,`check-swift` 抓不到,只能在 macOS 上炸:

- 已经是非可选的局部值,又写 `if let` 或 `?.`
- `private` 的成员被测试调用(测试用的是 `@testable import`,能看见 internal,看不见 private)
- 测试被放进另一个 suite,而它用到的助手是那个 suite 里定义的

已经能自动查的三种:`Tests/` 里 conform `MagpieRunner.Core` 的替身缺方法、文件用了生成的 `Mobile*` 类型却没 `import VeneraCatCore`、以及 `App/` 里用了 kit 的类型却没 `import NekularityKit`(`check-swift.py`;后两条都是「在 Mac 上才会炸」的编译错误,在 Windows 上就能先拦住)。
## 测试可能和代码一起错

恢复备份的 cookie 时,代码把 cookie 写进了「裸源 key」分区,而所有请求读的是 `"comic:<key>"` —— cookie 落在一个没人会读的地方,导入摘要却显示「恢复了 N 条」。**当时的测试断言的是同一个错误假设**(`partition: "mini"`),所以全绿。

这类错误和「测试没覆盖到」不同:覆盖率、语法检查、甚至用例本身都正常,只是**用例在帮我确认误解**。能拦住它的办法不是多写用例,而是:

- 去代码以外的**事实源**核对(这里是传输层真正用的 key),而不是相信自己的实现;
- 让错写不成立(`restore(source:)` 内部加前缀),而不是靠「记得用助手」;
- 回归用例同时断言**正确位置有、错误位置没有** —— 只断言「有」的用例换个假设也能通过。

## 界面用例不碰网络,包括图片

界面用例跑的都是仓库自带的测试源(`UITests/Fixtures/callback_probe.js`),它自己回答搜索、详情、章节、评论和收藏。**阅读器需要图片,而图片以前必须有站点**——现在不需要了:测试 runner 和 App 是同一个模拟器上的两个进程,**共用 loopback**,所以 `UITests/LocalImageServer.swift` 在 runner 里起一个只回一张 PNG 的 HTTP 服务,夹具的章节指向 `http://127.0.0.1:18731/page.png`。

三条要记住:

- **那个端口只在 runner 里活**。在别处用这个夹具读章节,会得到 `images=1 decoded=0`(用桌面 `cmd/readercheck` 实测过),所以没有桌面探针去读它。
- PNG 是**运行时画出来的**,不是手敲的 base64。手敲的 blob 解码失败时看起来跟客户端 bug 一模一样。
- 测试 target 也继承 `SWIFT_STRICT_CONCURRENCY: complete`,所以那个服务必须自己处理 Sendable:`NWListener` 的 handler 是 `@Sendable`,在里面改捕获的 `var` 或捕获非 Sendable 的 `self` 都是编译错误。现在用 `@unchecked Sendable`(所有存储属性是 `let`)+ 一个自带锁的 `Signal` 传递启动结果。

页图判据必须检查实际解码后的图片元素或画面。HTTP 200 的坏字节负例已证明:章节和「收藏本页」按钮都可能存在,而页图仍无法解码,因此按钮可用不能证明图片已到达。离线正例应停服后进入下载章节,检查实际 `Image` 元素(如「第 1 页」);坏图应显示失败并可重试,恢复有效 PNG 后再次停服验证。相邻用例必须清理各自测试章节,不能让旧的完成条目替代本次下载。

## 验证前先清构建产物

解包出来的文件 mtime 是 0(1970),`swift build` 会认为它们比 `.build` 里的旧,于是**新用例没被编译却显示全绿**。验证前先 `touch` 相关文件并 `rm -rf .build`,或者干脆只信一次干净构建的结果。这不是理论风险: 打包成 tar 时故意把 mtime 归零是为了可复现,代价就是这个。

## 测试之间不要共享可变状态

Swift Testing 默认**并行**跑同一个 suite 里的用例。共享的静态 stub 表加上「每个用例开头清空一次」,会让某个请求在别人清表之后才到,查不到应答就报 `-1004 cannot connect to host` —— 看起来像网络问题,实际是测试互踩。两条规矩:用例各用各的主机名/键,**不要用 `reset()` 清全局表**;真需要串行才用 `.serialized`,并写清为什么。

## 小文件直接贴正文

给验证机送一个**新文件**(脚本、plist 之类)时,`scripts/make-transfer.sh --inline FILE` 会打印 md5 加全文。原因是实测过的:链接和正文分两条消息发,两次都没到。整包仍然走 gist(文件多、正文会过长),但几十行的东西没必要增加一层不确定性。

## 换 pin 的消息也由脚本生成

pin 出现在四个地方,而对方要拿 md5 对账。手写这两个哈希已经错过三次(其中两次是占位符没填)。`scripts/make-pin-message.sh` 把要发的整块打印出来,哈希从文件读 —— 和 `make-transfer.sh` 同一个道理:只要消息里有哈希,就不该由人敲。

## 验证机上的文档可能是旧版

补丁包常常只带代码与测试,于是验证机上的 `docs/` 会落后于仓库。那边的 `check-docs.sh` 仍可跑(它只检查文件之间的配对与结构),但**不要把它的通过当成「仓库文档已同步」的证据**;文档的正确性由推送前在本机跑的那一次负责。

## 整树验证要能真构建 App

`verify-ios.sh` 在没有 XcodeGen 时会退化成 SwiftPM 编 Kit——**App bundle 从不构建**,于是 `Info.plist`、`excludes`、ATS 这类只在资源阶段生效的配置全都验不到,而输出仍是 `EXIT=0`。

需要那一步时,取官方发布页的二进制包,不要装 Homebrew:

```sh
mkdir -p /tmp/xcg && cd /tmp/xcg
curl -fsSL -o xcodegen.zip https://github.com/yonaskolb/XcodeGen/releases/latest/download/xcodegen.zip
unzip -o -q xcodegen.zip
PATH="$(dirname $(find /tmp/xcg -name xcodegen -type f | head -1)):$PATH" sh scripts/verify-ats.sh
```

`/tmp/xcg` 是临时目录,删掉即还原;这比 `brew install` 更容易回退,也不改系统。

## 把代码送到验证机

验证机可能是另一台 Mac,而且**拿不到本仓库的凭据**。顺序是:

1. 仓库能 clone 就 clone(公开仓不需要凭据,**私有仓需要**,验证机上常常没有);
2. 不能 clone 时用 `scripts/make-payload.sh` 打整包,放到一个 **secret gist**,让验证机 `curl` 取回 —— 不要把几百段 base64 塞进对话,那里的等长改写和段错位很难发现;
3. 两边都在,就只发 `scripts/make-patch.sh` 生成的补丁。

**发整棵树用 `scripts/make-tree-transfer.sh`**:`make-transfer.sh` 只打包它被点名的文件——`make-transfer.sh OUT /tmp/seed.json` 会寄出一个只有种子的包,验证机拿到后满机器找代码树。这个新脚本总是寄整棵树,而且在打印消息**之前**先把自己刚建的 bundle clone 一遍,核 HEAD 与文件数:

```
sh scripts/make-tree-transfer.sh /tmp/nk C:/Temp/seed-ios9.json
tree <sha> (141 files) / bundle md5 / b64 md5 / 以及可直接粘贴的消息块
```

这条是从一次真实损失里来的:那轮验证机解包后只看到种子,又因为没有 `.git` 而没法自行补代码。

**直接粘贴脚本打印的块,不要手写**:这一轮三次传输问题里,两次是我在消息里手写了哈希或路径,而脚本打印的块不可能和自己不一致。要改的是说明文字,不是命令与哈希——那部分整段复制。

**种子也一起上传**:给了第二个参数时,脚本会把种子同样打包、上传并打印 raw URL 与两级哈希。之前消息里只写种子名字和 md5、没给地址,那台机器只能干等——`check-seed.sh` 比的是种子与树,它不能替接收方拿到种子。

**只跑一个用例**:`NK_UI_ONLY=testReaderDrawsTheChaptersPage` 会给 `xcodebuild` 加上 `-only-testing:`。十几个用例要跑几分钟,其中一个失败时没必要把已经通过的再跑一遍——门禁的标签里会写明这次只跑了哪个。

**设备上的种子不会自动被覆盖**:`scripts/seed-simulator.sh` 发现设备里已有**不同**的种子会停下来,这是有意的——不然一次验证会悄悄改掉别人设备上的数据。所以两种做法二选一:给出与设备一致的种子,或显式 `NK_UI_SEED_REPLACE=1`。注意 `check-seed.sh` 比的是「种子 ↔ 树」,它证明不了设备上是什么;设备状态只有验证机看得见,所以这一项要让验证机自己核。

**种子先对一遍再发**:`sh scripts/check-seed.sh /tmp/seed.json` 会核对种子里 `callback_probe` 的 `body` 与 `UITests/Fixtures/callback_probe.js` 是否一致(忽略换行差异),并校验种子自己的 sha256。种子由桌面的 `cmd/seedgen` 生成,却和代码分成两个文件、两个 md5 发送——曾经出现过种子基于旧夹具、用例跑在昨天的脚本上、失败却指向客户端的情况。

整棵树用 `scripts/make-tree-transfer.sh` 发(git bundle,clone 下来**有 `.git`**,`check-tree.sh` 能报出真实提交号);`make-transfer.sh` 只打包它点名的文件,`make-transfer.sh OUT /tmp/seed.json` 只会寄出一个种子。两者都把哈希从文件里读出来打印成可直接粘贴的块(`GH_CREATE_GIST=1` 时连 gist 与 raw URL 一起给)——**消息里只要出现哈希,就不该由人敲**。**收到代码后立刻删 gist**(`gh gist delete <id>`):secret gist 不列出,但拿到链接的人就能读,它不是仓库的替代品。macOS 的 `base64` 不吃位置参数:`base64 -D -i p.b64 -o p.tar.gz`。若目标机没有 tree-sitter 或只有系统 Python 3.9,**它不再整套跳过**:语法解析需要 parser,其余规则都是纯文本判断,所以缺 parser 时降级为「只跑规则」并以 exit 0/1 报告,`verify-ios.sh` 会标成 `PASS python3 scripts/check-swift.py (rules only: no parser here)`。**不要把降级当成完整通过**——它没解析语法;要解析就在那台机器上 `python3 -m pip install tree-sitter tree-sitter-swift`。
