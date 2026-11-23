# 仍待验证的边界

[English](UNVERIFIED.en.md) | 简体中文

本页只列当前**仍未验证**的硬件、系统运行时、真实账号与真实站点边界；已经通过 CI 单测或模拟器界面验证的项目见 [STATUS.md](STATUS.md)，外部验机操作步骤见 [HANDOFF.md](HANDOFF.md)。

## 真机与系统能力边界

| 项 | 已有工程证据 | 仍缺什么 |
|---|---|---|
| 签名安装与真机启动 | 未签名 IPA 归档与模拟器运行（CI `42743715195`） | 真机签名安装、首次启动与升级迁移 |
| iOS 26 实际运行时 | 主要在 CI 模拟器 / Xcode 27 运行时测试 | 目标 iOS 26 真机运行时核对 |
| 后台与锁屏播放、画中画（PiP） | 模拟器回环播放与续播；模拟器 `AVPictureInPictureController.isPictureInPictureSupported()` 恒为 `false`，无法渲染 PiP 按钮 | 真机启动 PiP、切后台/锁屏及软件解码通路（VP9/AV1）转 PiP |
| 字幕在 AirPlay / 外接显示器上的呈现 | 模拟器内 AVPlayer 字幕绘制、切换与关闭 | 真机 AirPlay 与外接显示器实测 |
| 实际扬声器出声 | HLS 夹具无音轨，只验证画面时钟推进 | 带真实音轨的素材在真机扬声器/耳机上的实际听感 |
| 下载 Live Activity 硬件呈现 | Kit 状态机单测与模拟器下载失败重试 UI（`42545229418`） | 真机锁屏与灵动岛展示、后台更新、拒绝权限或重试成功后的消失 |
| 通知权限与追番提醒 | Kit 提醒规划单测与编译通过 | 真机授权通知后的实际送达 |

## 真实网络、账号与后置服务

| 项 | 已有工程证据 | 仍缺什么 |
|---|---|---|
| 公网 HTTP 源兼容性 | `CleartextPolicy` 单测、`lrr.tvc-16.science` 例外与本地回环 UI | 用户自装公网 HTTP 源在默认 HTTPS 策略下的真实反馈 |
| 标准 AI 真实端点 | 模拟器流式输出、取消与 401 响应头拒收（`ZZStandardAIStreamTests`） | 真实 OpenAI / Anthropic 端点下的流式增量、截断提示（`max_tokens`）、服务端停止生成与重启凭据恢复 |
| Magpie 真实供应商账号 | 本地回环 HTTP 夹具与假凭据测试 | 用户授权的真实供应商登录、凭据刷新、额度与重启恢复 |
| 媒体服务器与外部服务 | 模型解析、回写逻辑与单测 | 真实 Jellyfin / Emby / Plex 服务器连接、浏览、播放与进度回写；Bangumi 令牌；TMDB key；Pixiv 登录 |
| 本机导入与大书架真机负载 | Kit 导入/CRC/坏档备份单测 | 真机本地 `.cbz`/文件夹/视频导入与大书架长期使用体感 |

## 如何复跑工程验证

在具备 macOS、Xcode、Go 与 XcodeGen 的机器上运行：

```sh
sh scripts/fetch-core.sh
sh scripts/verify-ios.sh
```

需要同时跑模拟器界面套件时加上 `NK_UI_TESTS=1`（可配合 `NK_UI_SEED`、`NK_UI_SEED_REPLACE=1` 与 `NK_UI_ONLY`）；也可直接手动触发 `.github/workflows/ios-release.yml`（勾选 `ui_tests`）。汇报结果时写明提交号、通过/失败/跳过数与设备边界，不以模拟器通过替代真机验证。
