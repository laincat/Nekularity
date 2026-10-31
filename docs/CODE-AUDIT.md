# 代码体检与清理

[English](CODE-AUDIT.en.md) | 简体中文

## 范围与基线

基线为 Nekularity `b294f04`,Core pin 为 `469edfcb48ec9564dca086a232a7b64e46fd0a9b`(那是审查开始时的 pin;审查之后 Core 已发布为单提交 `6e0742996007e0246e1c56a14a09546325bb3e96`,两端 pin 随之更新)。本轮 Lead 检查分层、存储、生命周期与桥接;Orca Worker 在 Mac 隔离目录审查网络、缓存、取消与 Magpie,并验证修复树。Windows 的语法通过不代表 Swift 6 类型检查或 App 构建通过。

## 本轮本地修复

| 问题 | 修复 | 回归/验证 |
|---|---|---|
| `signOut` 直接关闭 Core,未设置 runner 的 closed 状态 | 统一调用幂等 `close()` | 新用例检查退出、显式关闭、deinit 合计只关闭一次 |
| Core 保有 Host,Host 又强持有 Core 回调句柄 | `CoreHost.core` 改弱引用 | 需 Mac Swift 6 类型与实际生命周期检查;不假称已测峰值内存 |
| 存储文件合法 JSON 但不是对象、子字段类型异常,或读取失败时会退化成空状态 | 只有缺失文件作为新源;其余错误抛出并保留原件 | 新用例覆盖坏正文、null、数组、异常 data 与 null 对象可写 |

Core 同轮还修复了取消早于调用登记时丢失,以及关闭后的调用生命周期。iOS 仍需要带修复源码重建的框架,不能以旧 pin 产物代替。

## 架构与依赖

SwiftUI App → NekularityKit → CoreClient/CoreMagpie → gomobile Core。系统能力由客户端拥有:URLSession 发送请求,Keychain 保存 AI 凭据,CookieJars 按源隔离,ImageIO 降采样,WKWebView 完成人机验证。Package.swift 没有额外的 Swift 第三方 package;VeneraCatCore 是本地 binaryTarget。XcodeGen 是构建工具,不是 App 运行依赖。

`ImageLoader` 已有按尺寸区分的 cache key、请求合并、ImageIO 降采样与 NSCache 的 128 MiB 成本上限。该限制属于缓存回收建议,不是整个进程的硬内存上限。

## 待优化与能力缺口

- `URLSessionTransport` 当前完成整包后才检查响应大小,不能阻止先缓冲超大响应。应在 delegate/chunk 层限制并与真实流式一起设计。
- `cancel(id:)` 早于 URLSession task 注册时存在窗口,当前测试刻意等待 50ms 后取消,没有覆盖该顺序。需要保存待取消状态或直接注册可取消任务对象。
- 跨 origin 跳转需清除自定义供应商鉴权头,不能只依赖 Foundation 对 `Authorization` 的默认处理。
- `ImageLoader` 的共享 inFlight Task 不随单个等待者取消而自动终止;多等待者需引用计数或明确的缓存/预取策略,不能粗暴取消所有共享请求。
- Magpie 刷新凭据应核查 models/usage/chat 等每条路径的持久化,不能仅证明通用 call 会保存。
- 标准 AI gomobile 入口已有构造/整包执行,但客户端 UI 尚未接入;实时网络流式与真实账号仍缺证据。

## 验证边界

本轮修复的逐文件 md5、shape、测试数、suite 数与 `xcodebuild` 结果必须取自同一棵树。Mac 原有 173 条路由原型树不合并,也不作为此次客户端基线。完整三项目图见同工作区 `Nekophage/docs/analysis/architecture-audit.html`。
