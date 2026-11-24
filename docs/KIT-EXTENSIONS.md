# Kit 声明式模块与服务包

[English](KIT-EXTENSIONS.en.md) | 简体中文

## 阅读模块

`VCModuleDocument.parse` 读取 `veneracat-module/1-draft` 的 UTF-8 文本。头部包含必填的 `#!name`、`#!version`、`#!format` 和可选的 `#!desc`、`#!id`、`#!requires`。`#!requires` 当前接受 `settings-module.v1`。首期分节为 `[Reader]`，可用 `page-gap`（0–128）、`keep-screen-on`、`layout`（`vertical` 或 `paged`）、`right-to-left` 和 `auto-next`。布尔值使用 `true` 或 `false`。整行注释以 `;` 或 `#` 开头。未知分节、未知键、重复赋值和错误类型会使整个模块被拒绝。

宿主向 `VCModuleStore.install` 提供稳定身份，比如由合集 ID 和条目 ID 组成的身份。模块安装后默认为禁用。之后安装的启用模块按键覆盖较早的启用模块。同身份更新保留原顺序和启用状态。调用 `effectiveSettings(over:)` 时传入当前基础配置，禁用或移除模块立即恢复下一层的值。正文和启用状态在同一个带文件保护的原子快照中保存，损坏的索引保留供恢复。模块管理和读取有效设置目前由 Kit API 提供。

## 服务包调用契约

Core 调用服务包导出的 `handle(method, payloadText)`。有参数时传 JSON 对象文本，无参数时传 `null`。桥接与 Sources 的实际服务包对齐，校验 `{ok, service, method, data}` 外壳后解码 `data`。执行错误对外只显示服务和方法，凭据值不进入请求参数或诊断。

| 服务包 | 方法与请求 |
|---|---|
| `service.bangumi` | `account.me`、`metadata.search`（`keyword/type/limit`）、`metadata.detail`（`subjectId`，可带 `includeEpisodes/episodeType/episodeOffset`）、`collection.get`（`subjectId` 或列表筛选）、`collection.update`、`episode.update`（`subjectId/episodeIds/type`）。每日放送仍由内置客户端读取 |
| `service.tmdb` | `metadata.search`、`metadata.detail`、`artwork.list`。TV 请求提供 `mediaType: "tv"` 和语言。当前包的详情不提供下次播出集 |
| `service.trakt` | `account.me`、`metadata.search`、`watchlist.list`、`history.list`、`scrobble.start`、`scrobble.stop`。`TraktService` 的片单写入、历史写入和暂停会在当前包返回 `UNSUPPORTED_METHOD` 时明确报错 |

Bangumi 的账号、收藏和进度方法需要 `access_token`。TMDB 接受 `api_read_token` 或 `api_key`。Trakt 搜索需要 `client_id`，账号相关方法额外需要 `access_token`。这些值来自当前环境的 `ServiceAccounts`。内置功能授权绑定到安装存档的摘要，调用仅授予必需且包已声明的 `network` 和 `secrets`。现有 Bangumi 和 TMDB 凭据保留在原 Keychain，确认包未安装时继续供内置客户端使用。可以在服务包账号或对应设置里单独录入包凭据。Trakt 需要调用方提供 `TraktProvider` 才有回退，现有 App 没有内置 Trakt 客户端。

当前 Core 服务宿主只提供 `fetch(url)` 的 GET 请求。认证请求头、POST、PATCH 或 PUT 依赖 Core 扩展 HTTP 契约。Sources 已发布三份通过离线夹具验证的包。本仓库离线用例验证 Swift 请求、响应、权限与回退，并通过实际安装的夹具包验证 Core 和 `CoreHost` 调用链。
