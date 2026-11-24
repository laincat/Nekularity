# Kit 声明式模块与服务包

[English](KIT-EXTENSIONS.en.md) | 简体中文

## 阅读模块

`VCModuleDocument.parse` 读取 `veneracat-module/1-draft` 的 UTF-8 文本。头部包含必填的 `#!name`、`#!version`、`#!format` 和可选的 `#!desc`。首期分节为 `[Reader]`，可用 `page-gap`（0–128）、`keep-screen-on`、`layout`（`vertical` 或 `paged`）、`right-to-left` 和 `auto-next`。布尔值使用 `true` 或 `false`。整行注释以 `;` 或 `#` 开头。未知分节、未知键、重复赋值和错误类型会使整个模块被拒绝。

宿主向 `VCModuleStore.install` 提供稳定身份，比如由合集 ID 和条目 ID 组成的身份。模块安装后默认为禁用。之后安装的启用模块按键覆盖较早的启用模块。同身份更新保留原顺序和启用状态。调用 `effectiveSettings(over:)` 时传入当前基础配置，禁用或移除模块立即恢复下一层的值。正文和启用状态在同一个带文件保护的原子快照中保存，损坏的索引保留供恢复。模块管理和读取有效设置目前由 Kit API 提供。

## 服务包调用契约

Core 从服务包调用 `handle(method, payloadText)`。有参数时 `payloadText` 是 JSON 对象文本，无参数时是 `null`。读取方法直接返回结果对象或数组。`collection.get` 可返回 `null` 表示未收藏。写入应在操作成功后返回 `null` 或 `{"ok":true}`。

| 服务包 | 方法 | 请求字段及结果 |
|---|---|---|
| `service.bangumi` | `account.me`、`calendar.list` | 无参数，分别返回 `BangumiUser`、`[BangumiCalendarDay]` |
| `service.bangumi` | `subject.search`、`subject.detail`、`subject.episodes` | 分别传 `keyword/type/limit`、`subject_id`、`subject_id/type`，返回条目列表、条目、剧集列表 |
| `service.bangumi` | `collection.list`、`collection.get`、`collection.update`、`episode.markWatched` | 分别传 `subject_type/limit/type?`、`subject_id`、`subject_id/type/rate?/ep_status?/comment?`、`subject_id/episode_id` |
| `service.tmdb` | `series.search`、`series.detail`、`series.artwork` | 分别传 `query/language`、`id/language`、`id/language`。剧集使用 `id/name/overview?/poster?/firstAirDate?/nextEpisode?/status?`，图集使用 `TMDBArtwork` |
| `service.trakt` | `account.me`、`search`、`watchlist.list`、`history.list` | `search` 传 `query`，其他无参数。返回账号、条目列表或观看记录列表 |
| `service.trakt` | `watchlist.set`、`history.add`、`scrobble` | 分别传 `item/included`、`item/watchedAt`、`item/action/progress`。请求内 `item` 使用 `kind/id`，读回的条目另外提供 `title` 和可选 `year` |

Bangumi 的账号、收藏与进度方法需要 `token`。TMDB 方法需要 `api_key`。Trakt 搜索需要 `client_id`，账号相关方法额外需要 `access_token`。这些值通过当前环境的 `ServiceAccounts` 提供。内置功能授权绑定到安装存档的摘要，调用时授予运行所需要且包已声明的 `network` 和 `secrets`。现有 Bangumi 和 TMDB 凭据保留在原 Keychain，确认包未安装时继续供内置客户端使用。授权后可在服务包账号或对应设置里为包单独录入凭据。Trakt 提供可注入的 `TraktProvider` 回退，现有 App 没有内置 Trakt 客户端。

当前 Core 服务宿主只提供 `fetch(url)` 的 GET 请求。需要认证请求头、POST 或 PATCH 的真实上游操作依赖 Core 补齐 HTTP 能力。三服务包在源合集中仍是设计稿。离线用例验证 Swift 调用契约、权限与回退，并通过实际安装的夹具包验证 Core 和 `CoreHost` 调用链。
