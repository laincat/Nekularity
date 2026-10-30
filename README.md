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

## 在没有 Xcode 的机器上

`scripts/check-swift.sh` 只解析语法,任何机器都能跑:`python3 scripts/check-swift.py`(不需要 Xcode,能抓未闭合的字符串、括号这类错误)。

把源码送到一台 Mac 上验证时,源码被切成 base64 分段,一段一段核对比整包重传可靠得多:

```sh
scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]
```

逐段对 md5、拼接、解码、核对归档 md5 与字节数、解包、数 `.swift`、把 xcframework 放进去、跑 `swift build`,每一步一行 `PASS`/`FAIL`。最后多传一个 `clean`,它会在报告之后删掉解包目录、拼接件和归档,机器保持原样。校验用 `md5` 而不是 `shasum`:受限机器上 `md5` 不需要额外授权。

分段包由 `scripts/make-bundle.sh OUTDIR [CHUNK]` 生成:`Package.swift`、`Sources/`、`App/`、`Tests/` 里所有 `.swift` 按路径排序、mtime 与属主归零后打成一个 47 KB 左右的归档,再切成 `CHUNK`(默认 1650)字符的 base64 段,并打印归档 md5 与每段 md5/末尾字符。同样的文件树每次生成的归档逐字节相同,所以校验值可以写进对话里核对。

只改了少数文件时不必重发整包:`scripts/make-delta.sh SINCE OUTDIR [CHUNK]` 用 `git diff --name-only` 取出相对某个提交变化的 `.swift`,按同样规则打成 `delta.tar.gz`,解到旧目录上就地覆盖。默认段长 1548 字符,并同样打印归档 md5 与每段 md5。实测它与手写打包命令产出的归档逐字节相同。

## 许可证

GPL-3.0-or-later,见 [LICENSE](LICENSE)。
