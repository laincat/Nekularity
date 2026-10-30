# Nekularity 架构

[English](ARCHITECTURE.en.md) | 简体中文

日期:2026-10-30。

## 目标

iOS/iPadOS 26 及以上的原生客户端,界面用 SwiftUI。业务逻辑都在 [VeneraCat Core](https://github.com/laincat/VeneraCat-Core) 中,客户端负责界面、网络、WebView、播放器和数据存储。

第一阶段只做一条主线:**安装漫画源 → 搜索 → 查看详情 → 阅读图片**。

## 分层

```
App/                        SwiftUI 界面(只依赖 NekularityKit)
│   NekularityApp           启动、依赖装配
│   PromptCenter            源发起的提示、对话框、输入、选择、加载、人机验证
│   SourcesView / SearchView / ComicDetailView / ReaderView
Sources/NekularityKit/      不含界面,可用 swift test 测试
├─ Core/       CoreClient(async 封装)、CoreHost(实现 MobileHostProtocol)、
│              Models、JSONValue、OrderedJSONDecoder
├─ Platform/   URLSessionTransport、CookieJars、VerificationSession(WKWebView)
├─ Storage/    SourceStore:源数据、设置、插件记录
└─ Library/    SourceLibrary(安装与订阅)、ImageLoader
```

规则:

- 界面只调用 `CoreClient`,不直接接触 gomobile 生成的类型。
- gomobile 方法是同步阻塞的,`CoreClient` 一律在后台执行,用 `async` 暴露给界面,不在主线程调用 Core。
- 网络请求由 `URLSessionTransport` 发送,按 Core 给的 `partition` 为每个源使用独立的 Cookie 存储,源之间不共享登录状态。
- Core 要求人机验证时,`WebViewVerifier` 在 `WKWebView` 中打开页面,等页面不再出现挑战特征、并且拿到 `cf_clearance` 后,把 WebView 的 User-Agent 返回给 Core。
- `.venera` 备份不在这里解析。Core 的 `mobile.Core.ReadBackup(path, tempDir, knownKeysJSON)` 与 `PlanBackup(path, tempDir, knownKeysJSON, selectionJSON)` 已经把压缩包、sqlite 表、type hash 解析完,返回带 `history` / `folders` / `imageFavorites` / `searchHistory` / `sources` / `settingKeys` 的 JSON;客户端只负责把这份 JSON 落到自己的 `ShelfStore` 与 `SearchHistoryStore`(`merge` 已经就位),并按 `sources` 走正常安装流程。这样两端共用同一套解析,不会各自实现一份 zip/sqlite 逻辑。

## 依赖

- `VeneraCatCore.xcframework`:由 `scripts/fetch-core.sh` 调用 Core 仓库的 `scripts/mac-verify.sh` 生成,放在 `Vendor/`,不提交到仓库。
- 不引入其他第三方依赖。

## 验证

本阶段代码还没有在 macOS 上编译过。Swift 中调用 Core 的方式,与 Core 仓库 `apple/CoreSmoke` 在 CI 上已验证通过的写法一致(`MobileNew`、`MobileHostProtocol`、带 `error: NSErrorPointer` 参数的方法)。
