# Nekularity 状态

[English](STATUS.en.md) | 简体中文

更新:2026-10-30。

## 已写好(未编译)

| 部分 | 内容 |
|---|---|
| Core 封装 | `CoreClient`:async/await 接口,任务取消会传给 Core;`CoreHost`:实现 Core 的全部宿主接口;搜索按 Core 给出的选项默认值调用 `search.load` |
| JSON | 自写的 `JSONValue` 解析器和 `OrderedJSONDecoder`,保留键顺序和数字原文 |
| 网络 | `URLSessionTransport`:按源隔离 Cookie,重定向中途设置的 Cookie 也会保存 |
| Cookie | `CookieJars`:host-only 与域 Cookie、路径、Secure、过期;持久 Cookie 写入文件 |
| 人机验证 | `VerificationSession`:WKWebView 加载挑战页,按 Core 的完成规则判断通过,并把 Cookie 和 User-Agent 交回 |
| 存储 | `SourceStore`:源数据、设置和插件记录,原文保存;是否登录按官方规则判断(存在 `account`) |
| 图片 | `ImageLoader`:按源的 `onImageLoad`/`onThumbnailLoad` 发请求,降采样后缓存 |
| 界面 | 源管理(订阅、链接安装、更新、启停、删除)、搜索、详情(分组章节)、阅读器(竖向滚动、上下章)、源发起的提示/对话框/输入/选择/加载 |
| 源设置 | `CoreClient.settings(key:)` 读 Core 的 `settings` 声明;源详情页进入设置页,按类型渲染下拉/开关/输入框,值以 `JSONValue` 原样写入该源 store 的 settings 段(数字、布尔不被转成字符串);input 的 `validator` 用正则校验;callback 显示为「源内操作」 |
| 书架 | `ShelfStore`:阅读历史(每部漫画一条,含章节、页码、百分比)与收藏夹;打开章节即记录,书架页可继续阅读、移除、换夹、新建/重命名/删除收藏夹;文件 `shelf.json` 与桌面端同形 |
| 搜索历史 | `SearchHistoryStore`:最近 30 条,忽略大小写去重、最新在前,可合并备份里的 `searchHistory`;文件 `searches.json` 与桌面端同形 |
| 分类浏览 | `CoreClient.explorePages` 与 `explore` 支持四种 browse 类型(单页多分区、多页列表、混合、多分区页);`BrowseView` 用标签切换分类、分区标题吸顶、分页、下拉刷新 |

## 未验证

- **编译**:`scripts/verify-ios.sh` 在 macOS 上串起检查(文档、`check-swift`、`swift test`、App 构建);没有 XcodeGen 时退化为「先给 iOS 编 Kit,再用 `swiftc -typecheck` 检查 App 源码」,仍然能抓到界面层的类型错误。代码还没有在 macOS 上实际跑过,但每次改动都过 `scripts/check-swift.sh`(tree-sitter 解析,能抓语法错误,不抓类型错误)。调用 Core 的写法和 Core 仓库在 CI 上通过的 `apple/CoreSmoke` 一致;`BrowseView` 新增后同样未编译。
- `swift test` 中的单元测试(JSON、Cookie、存储)也还没运行。
- 真机运行、真实漫画源。

## 下一步

1. 公开仓库或在 Mac 上编译,修正编译错误,运行 `swift test`。
2. 用真实漫画源跑通主线。
3. 书架(阅读历史与收藏)还没做;桌面端已有 `internal/shelf` 与 `.venera` 历史/收藏导入,可以照它的做法搬。
4. 在 Mac 上编译 `BrowseView` 与搜索选项的调用,修掉编译错误。
5. 第二阶段:收藏与历史、`.venera` 备份导入、视频源。
