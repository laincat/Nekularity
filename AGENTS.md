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

## 改一处、通读一遍

改一个字段的可选性、一个方法的访问级别、或者把一段代码搬进另一个 suite 时,**把同一函数、同一类型里所有用到它的地方一次看完**。这几类错误语法上完全合法,`check-swift` 抓不到,只能在 macOS 上炸:

- 已经是非可选的局部值,又写 `if let` 或 `?.`
- `private` 的成员被测试调用(测试用的是 `@testable import`,能看见 internal,看不见 private)
- 测试被放进另一个 suite,而它用到的助手是那个 suite 里定义的

已经能自动查的三种:`Tests/` 里 conform `MagpieRunner.Core` 的替身缺方法、文件用了生成的 `Mobile*` 类型却没 `import VeneraCatCore`、以及 `App/` 里用了 kit 的类型却没 `import NekularityKit`(`check-swift.py`;后两条都是「在 Mac 上才会炸」的编译错误,在 Windows 上就能先拦住)。
## 验证前先清构建产物

解包出来的文件 mtime 是 0(1970),`swift build` 会认为它们比 `.build` 里的旧,于是**新用例没被编译却显示全绿**。验证前先 `touch` 相关文件并 `rm -rf .build`,或者干脆只信一次干净构建的结果。这不是理论风险: 打包成 tar 时故意把 mtime 归零是为了可复现,代价就是这个。

## 测试之间不要共享可变状态

Swift Testing 默认**并行**跑同一个 suite 里的用例。共享的静态 stub 表加上「每个用例开头清空一次」,会让某个请求在别人清表之后才到,查不到应答就报 `-1004 cannot connect to host` —— 看起来像网络问题,实际是测试互踩。两条规矩:用例各用各的主机名/键,**不要用 `reset()` 清全局表**;真需要串行才用 `.serialized`,并写清为什么。

## 验证机上的文档可能是旧版

补丁包常常只带代码与测试,于是验证机上的 `docs/` 会落后于仓库。那边的 `check-docs.sh` 仍可跑(它只检查文件之间的配对与结构),但**不要把它的通过当成「仓库文档已同步」的证据**;文档的正确性由推送前在本机跑的那一次负责。

## 把代码送到验证机

验证机可能是另一台 Mac,而且**拿不到本仓库的凭据**。顺序是:

1. 仓库能 clone 就 clone(公开仓不需要凭据,**私有仓需要**,验证机上常常没有);
2. 不能 clone 时用 `scripts/make-payload.sh` 打整包,放到一个 **secret gist**,让验证机 `curl` 取回 —— 不要把几百段 base64 塞进对话,那里的等长改写和段错位很难发现;
3. 两边都在,就只发 `scripts/make-patch.sh` 生成的补丁。

发出去的包里**没有 `.git`**,所以验证机上 `scripts/check-tree.sh` 的 commit 会是 `none`;要对的是 `swift` / `tests` / `suites` / `shape` 四项,不是提交号。取包时先核对 archive md5,不对就停。**发送方用手敲的 md5 会错** —— 用 `scripts/make-transfer.sh OUTDIR FILE…` 生成消息:它把归档、base64 与每个文件的 md5 都从文件本身读出来,再打印成可直接粘贴的块(`GH_CREATE_GIST=1` 时连 gist 和 raw URL 一起给)。**验证一旦拿到代码,gist 立刻删掉**(`gh gist delete <id>`)—— secret gist 不列出,但拿到链接的人就能读,它不是仓库的替代品。包内是仓库本身(`./App`、`./Sources`…),不需要再摊平一层。macOS 的 `base64` 不吃位置参数:`base64 -D -i p.b64 -o p.tar.gz`。若目标机没有 tree-sitter 或只有系统 Python 3.9,`check-swift.py` 分别以 **exit=2 / exit=3** 表示「这台机器跑不了」,`verify-ios.sh` 记为 SKIP —— 环境限制,不是树有问题;开发机直接跑 `scripts/check-swift.sh` 仍然会硬失败。
