# Nekularity

[English](README.en.md) | 简体中文

iOS/iPadOS 漫画与视频客户端,界面使用 SwiftUI,许可证为 GPL-3.0-or-later。业务逻辑来自 [VeneraCat Core](https://github.com/laincat/VeneraCat-Core),兼容 Venera 的漫画源脚本和订阅索引。

## 状态

第一阶段只做一条主线:**添加漫画源 → 搜索 / 浏览 → 查看详情 → 阅读 → 记进书架**。代码还没有在 macOS 上编译过,但每次改动都过 `scripts/check-swift.sh`(解析全部 Swift 文件,抓语法错误)。详见 [docs/STATUS.md](docs/STATUS.md)。

## 目录

| 目录 | 内容 |
|---|---|
| `App/` | SwiftUI 界面:源管理、搜索、详情、阅读器、源发起的对话框与人机验证 |
| `Sources/NekularityKit/` | 不含界面的部分:Core 封装、网络、Cookie、存储、图片加载 |
| `Tests/` | NekularityKit 单元测试 |
| `docs/` | 架构与状态 |
| `scripts/` | 编译 Core、文档检查、Swift 语法检查 |

## 编译

需要 macOS、Xcode 26、Go(版本见 Core 的 `go.mod`)和 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```sh
scripts/fetch-core.sh            # 编译 VeneraCatCore.xcframework 到 Vendor/
swift test                       # NekularityKit 单元测试
xcodegen generate                # 生成 Nekularity.xcodeproj
open Nekularity.xcodeproj
```

`scripts/core-version` 写明要使用的 Core 分支、标签或提交。也可以传入本地 Core 目录:`scripts/fetch-core.sh ../VeneraCat-Core`。

## 许可证

GPL-3.0-or-later,见 [LICENSE](LICENSE)。
