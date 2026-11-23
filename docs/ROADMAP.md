# 路线图与现行决定

[English](ROADMAP.en.md) | 简体中文

本页只保留仍然生效的产品/架构决定、当前推进顺序与停止规则；已发布版本的逐日流水留在 Git 历史与 [STATUS.md](STATUS.md)。

## 现行架构与产品决定

- **业务逻辑归 VeneraCat Core**：源执行、备份格式与跨端协议由 Core 维护，Nekularity 负责 SwiftUI 界面、网络、WebView、播放器与平台存储；客户端从 `e353650` 起默认跟 Core 上游 `main`。
- **默认 HTTPS 与隔离安全**：ATS 默认关闭 `NSAllowsArbitraryLoads`，只对本机回环与显式声明的官方源域名放行 HTTP；Cookie 按源分区隔离，AI 与服务凭据进 Keychain；备份恢复 Cookie 必须由用户显式确认。
- **界面将整体重写**：当前阶段不打磨旧 SwiftUI 页面的视觉与布局细节，只收口 Kit/App 边界、修正确性与性能开销，确保新界面直接经 Kit 入口访问能力。
- **插件化与分发边界**：在线弹幕、外部元信息与扩展服务按插件/后置方向演进；iOS 兼顾侧载（AltStore）与未来 App Store 分发（正式上架前完成 LGPL 例外法务核对）。

## 当前推进顺序

| 阶段 | 目标 | 验收标准 |
|---|---|---|
| Wave 2B（当前） | Nekularity 本地瘦身、冗余门禁与重复素材清理、源安装/设置边界收口、Cookie/流式传输/书架存储开销修复 | Windows 语法与双语文档检查全过；合回后 Apple CI 完整 Kit 单测、App 构建与定向回归全绿 |
| Wave 3 | 与 VeneraCat Core / Sources 联动：收藏/账号/挑战规则与 Magpie 包入口下沉 Core、统一 `plugins/plex.js` 归属 | 跨端契约测试覆盖并合回主线 |
| UI 重写阶段 | 在干净的 Kit 边界之上重构 iOS/iPadOS 交互与视觉体验 | 新界面通过完整模拟器套件与真机验收 |

## 需要外部条件的事项

- 真机签名安装、后台/锁屏播放、PiP、硬件 ActivityKit、扬声器声音、真实账号与真实公网站点（详见 [UNVERIFIED.md](UNVERIFIED.md) 与 [HANDOFF.md](HANDOFF.md)）。
- 正式 App Store / DRM 分发前的许可证法务核对。

## 推进与停止规则

- 优先消除真实正确性、数据一致性与内存/IO 开销隐患，再做跨仓契约收敛。
- 不伪造未在 macOS / 真机上跑过的验证结论；任何构建或测试范围变更都要明确写出实际覆盖边界。
