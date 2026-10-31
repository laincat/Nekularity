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

## Magpie 插件层的分层

iOS 的 **Magpie 插件系统在 App 内集成并独立运行**,和漫画源的 `plugin.Registry` 完全分开,不共用任何注册表。它不依赖桌面端已安装的 Magpie、不要求访问桌面网关,也不以桌面 Bun 进程作为前置条件。桌面 Nekophage 首期连接本机安装版 Magpie,属于另一条接入路径。

当前目标是 **Core 内置 OpenAI Chat/Responses 与 Anthropic Messages 标准 API,其他供应商及路由、用量、内容脱敏等通过安装 Magpie 插件扩展**。Core 保留协议、流式/取消、插件宿主、事件和策略调用机制;具体业务策略不继续硬编码为标准调用的必经路径。详见 Core 的 [分层取舍](https://github.com/laincat/VeneraCat-Core/blob/main/docs/AI-CORE-BOUNDARY.md)。

现阶段已实现的是下列供应商插件与客户端基础,以及未接入 iOS 的路由原型。标准 API 独立入口、通用策略/中间件扩展点仍需补齐并逐项验证,尚不能声称已完成 Magpie 全能力集成:


```
Core(magpieplugin 包)        读包、校验路径与体积、起一个独立 JS 运行时、
│                            实现 fetch/Headers/URL/AbortSignal/ReadableStream、
│                            把 SSE 解成 EventText/EventReasoning/EventEnd/EventError
│                            Core 不开任何连接,网络由客户端注入
NekularityKit/Magpie/
├─ CoreMagpie                对 gomobile MobileMagpie 的薄封装
├─ MagpieAccounts            每个 provider 一个 runner + 声明缓存(同一次刷新不重复编译)
├─ MagpieRunner              安装、登录、用量、模型、对话、打卡、选项
├─ MagpieAuthStore(Keychain) 凭据原文存 Keychain,不重排键顺序、不改数字
├─ MagpiePackageStore        一个 provider 一个包,重装替换,索引原子写
│                           装包来源两种:已解开的文件夹,或下载来的 zip / tar.gz
├─ MagpieSignIn              设备码/回调轮询、取消、超时
├─ MagpieChat                事件流(AsyncThrowingStream)、停止即取消请求、超时
└─ MagpieOptionStore         插件声明的开关,键为 provider|option
App/                         「AI 供应商」页、登录页、用量页、选项页
```

规则:

- **凭据只在客户端**:Core 通过 `client.auth.get/set` 拿到的是客户端给的字符串,它自己既不持久化也不跨 provider 复用;写入落 Keychain,按 provider 分键。
- **解压归 Core**:`ReadArchive` 解开 zip 与 tar.gz,剥掉一层顶层目录,拒绝符号链接与目录穿越,限额与文件夹安装一致;客户端只把 Core 给的文件表存下来,不另写一份解压。
- **包的请求走包自己的 loader/fetch**:Core 不复制供应商的刷新、鉴权逻辑,否则每加一个供应商就要改一次 Core。
- **对话是拉取而不是推送**:gomobile 无法从 Go 回调 Swift,所以 `chatNext` 轮询;关闭 runner 会取消其中所有对话,避免往没人读的 channel 里写。
- **未报告 ≠ 零**:用量的 share 缺失是 `null`,界面不画 0% 进度条;供应商拒绝(404/403)是错误,不是空列表。
- **不在输出之后重试**:已经吐出文字就锁定,避免重复段落;输出之前的失败可以换端点。
- **不支持的依赖必须显式失败**:Node 内建模块、npm 依赖、CLI 调用报 `ErrUnsupportedModule` 或能力错误,不做空壳。
- **超时**:登录与对话都有上限,一个永远说「还没有」的包不能让界面无限转圈。

## 依赖

- `VeneraCatCore.xcframework`:由 `scripts/fetch-core.sh` 调用 Core 仓库的 `scripts/mac-verify.sh` 生成,放在 `Vendor/`,不提交到仓库。
- 不引入其他第三方依赖。

## 验证

本阶段代码还没有在 macOS 上编译过。Swift 中调用 Core 的方式,与 Core 仓库 `apple/CoreSmoke` 在 CI 上已验证通过的写法一致(`MobileNew`、`MobileHostProtocol`、带 `error: NSErrorPointer` 参数的方法)。
