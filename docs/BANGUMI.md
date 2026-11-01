# Bangumi 支持

[English](BANGUMI.en.md) | 简体中文

Bangumi(bgm.tv)在这台设备上是「追番的账号」:收藏状态、评分、进度,以及每一话的放送日期。它和 TMDB 分工不同——TMDB 知道欧美剧集的播出时间,Bangumi 有中文标题、话数表和国人的收藏习惯——两者在提醒计划里合并成一份。

## 能做什么

| 功能 | 入口 | 说明 |
|---|---|---|
| 连接账号 | 我的 → Bangumi 追番 | 粘贴个人令牌,先调 `/v0/me` 验证,通过后才写进钥匙串 |
| 看收藏 | 同上 | 在看/想看/看过/搁置/抛弃五档,分档读取 |
| 改状态与评分 | 条目详情 | 状态用分段选择器,评分 0–10 |
| 标记看过 | 条目详情的话数表 | 每话一个勾,调 Bangumi 的进度接口 |
| 搜索条目 | 收藏页下方 | 只搜动画(type=2),按关键词 POST 搜索 |
| 每日放送 | 收藏页下方 | 公开数据,不登录也能看 |
| 追番提醒 | 设置 → 追剧提醒 | 「在看」里的条目按下一话日期并入 `AiringPlan`,与 TMDB 的条目同一套通知 |

## 用到的接口

| 端点 | 用途 | 需要令牌 |
|---|---|---|
| `GET /v0/me` | 验证令牌,取昵称与头像 | 是 |
| `POST /v0/search/subjects` | 关键词搜索,body 里带 `filter.type` | 否 |
| `GET /v0/subjects/{id}` | 条目详情 | 否 |
| `GET /v0/episodes?subject_id=` | 话数表,每页 100,最多 500 | 否 |
| `GET /calendar` | 每日放送 | 否 |
| `GET /v0/users/-/collections` | 本账号的收藏,可按状态与条目类型过滤 | 是 |
| `GET /v0/users/-/collections/{id}` | 单条收藏状态,404 表示没收藏 | 是 |
| `POST /v0/users/-/collections/{id}` | 改状态、评分、进度 | 是 |
| `PATCH /v0/users/-/collections/{id}/episodes` | 标记某话看过,返回 202(已排队) | 是 |

每个请求都带 `User-Agent: laincat/Nekularity (...)`。这不是装饰:Bangumi 对默认的 URLSession 标识返回 403,匿名流量限得很紧。

## 凭据

令牌只存在钥匙串里(`com.laincat.nekularity.bangumi`,按环境分服务名),`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`——从备份恢复到另一台手机不该等于把别人的收藏夹交出去。收藏与话数在内存里,不落盘。

没有做 OAuth:OAuth 要把 client secret 放进一个谁都能解压的 App 包里,那不是秘密。个人令牌是 Bangumi 官方给第三方客户端的方式。

## 还没做的

| 项 | 为什么 |
|---|---|
| 收藏列表分页 | 现在最多取 50 条一页,收藏很多的人会看不全 |
| 条目评论与讨论 | 接口存在,但没有设计过界面 |
| 书籍与游戏条目 | 客户端目前只搜动画(type=2);模型已经能解析 `type` |
| 收藏缓存落盘 | 每次进页面都要请求一次;离线时是空白 |
| 新番时间表按本地周次对齐 | 每日放送按 Bangumi 的周次显示,没有按设备时区换算 |

## 怎么验证

单测不联网:请求形状、字段解码、错误文案、以及「在看 → 追番计划」这条连接,都在 `Tests/NekularityKitTests/BangumiTests.swift` 里用假 transport 覆盖。

```sh
swift test --filter Bangumi
```

真机要看的:

1. 令牌验证失败时应当明确说是令牌问题,而不是空列表;
2. 收藏页五档切换会不会各显示各的;
3. 标记看过之后进度是否立刻前进(接口返回 202,数据是排队写入的);
4. 开追剧提醒,「在看」里的条目应当在放送日当天上午出现一条通知。
