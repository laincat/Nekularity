# Nekularity 现行状态

[English](STATUS.en.md) | 简体中文

本页只保留当前构建、已证实行为与有效证据指针。历史版本流水（0.2.x–0.4.8）、旧 Core pin 变动和旧分段交接留在 Git 历史与 GitHub Releases 中。仍待真机或真实账号核实的项目见 [UNVERIFIED.md](UNVERIFIED.md)，外部交接步骤见 [HANDOFF.md](HANDOFF.md)。

## 当前构建与基线

| 项 | 现行状态 | 证据 / 备注 |
|---|---|---|
| 最近公开产物 | `v0.4.9` / build `31`（`01016b5`，内置 Core `2bafd88`） | 发布 CI `42578286568`；IPA 29,963,615 字节，SHA-256 `b75fa0ea178f7786f3b92e764054172a1255bf38cd17d0a35e17952a0d0be70c`；AltStore 三入口（GitHub Raw / CNB / Release）均已同步（`42582601315`） |
| 最近完整 Apple CI 回归 | `9b64e1a`（ATS 默认 HTTPS + `CleartextPolicy`） | CI `42743715195` **success**：Kit **509 tests / 87 suites**，模拟器界面 **34 PASS / 0 FAIL / 0 SKIP**，Magpie 回环夹具通过 |
| 依赖与 Core 策略 | `e353650` 起移除 Core pin，默认跟上游 `main`；播放引擎 `AetherEngine 7.62.0` | 公开 IPA 仍是 `0.4.9/31`，后续改动需新版本发布才会进入公开包 |
| 许可证 | LGPL-3.0-or-later 附 App Store / DRM 例外 | 见根目录 [LICENSE](../LICENSE) 与 [COPYING](../COPYING) |

## 已证实能力地图

| 领域 | 已证实行为 | 证据指针 |
|---|---|---|
| 漫画主线与隔离存储 | 源安装/更新、搜索分页、详情评分、阅读器解码与断网离线重读、书架、下载重试隔离、备份导入导出与分区 Cookie 隔离 | CI `42743715195`（Kit 509/87，UI 34/0/0） |
| 网络安全（ATS） | 默认 HTTPS（`NSAllowsArbitraryLoads=false`），`NSAllowsLocalNetworking=true`，仅对 `lrr.tvc-16.science` 设例外；`CleartextPolicy` 在建连前拒绝未声明的公网 HTTP（含 AI/Magpie/索引） | 提交 `51b9c3d`、`9b64e1a`；CI `42743715195`（11 条新单测 + 完整 UI） |
| 视频播放与字幕 | `AetherEngine` 画面时钟推进、源 `Referer` 传递、AVPlayer 字幕绘制与中英切换/关闭、30 秒 HLS 7 秒续播恢复 | CI `42199314431`、`42743715195`（共享夹具 `UITests/Fixtures/media/hls-subs/`） |
| 标准 AI 流式接口 | OpenAI Chat / Responses 与 Anthropic Messages 均已接流式呈现、增量输出、断流与响应头即时拒收（401 等不等待正文） | 提交 `b81b52d`；CI `42193319262`（`ZZStandardAIStreamTests`）及后续完整 UI |
| Magpie 原生供应商包 | 文件夹与归档导入、Keychain 凭据隔离、设备码/表单/API Key 登录、模型目录、流式对话与截断提示、本地真实 HTTP 回环验收 | `CoreMagpieTests`、`scripts/fixtures/magpie-http/run.py`、CI `42743715195` |
| 下载 Live Activity | 下载中/失败/重试/清除状态机与灵动岛文案映射 | 提交 `969d2c2`；CI `42545229418`（Kit 状态机单测 + 模拟器下载重试 UI；真机呈现未验） |
| 主题与自适应布局 | 主题本地 HTTPS 安装与 HTTP 拒绝、iPad 宽屏与 AX5 辅助字号布局 | `scripts/theme-fixture.sh`、CI `42743715195`（UI 34/0/0） |

## 证据边界与后续工作

- CI 模拟器通过不等于真机签名安装、后台/锁屏播放、PiP、硬件 ActivityKit、扬声器声音、真实账号或真实公网站点通过，详见 [UNVERIFIED.md](UNVERIFIED.md)。
- 本地 Windows 环境只负责文档结构（`scripts/check-docs.sh`）与 Swift 语法解析（`scripts/check-swift.py`），Swift 类型检查、`swift test` 与 App/UI 构建以 macOS / GitHub Actions 为准。
- 本轮架构演进与精简路线见 [ROADMAP.md](ROADMAP.md)。
