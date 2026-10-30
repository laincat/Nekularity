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
- 所有 `.md` 都提供中英双语:`X.md` 为中文,`X.en.md` 为英文,顶部互相链接。修改其中一份时同步修改另一份。`scripts/check-docs.sh` 会检查配对和根目录。
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

已经能自动查的两种:`Tests/` 里 conform `MagpieRunner.Core` 的替身缺方法、以及文件用了生成的 `Mobile*` 类型却没 `import VeneraCatCore`(`check-swift.py`)。
