# Nekularity

[English](README.en.md) | 简体中文

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/brand/nekularity-banner-dark.png">
  <img src="docs/assets/brand/nekularity-banner.png" alt="Nekularity" width="720">
</picture>

iOS/iPadOS 漫画客户端(视频为后续阶段),界面使用 SwiftUI,许可证为 GPL-3.0-or-later。业务逻辑来自 [VeneraCat Core](https://github.com/laincat/VeneraCat-Core),兼容 Venera 的漫画源脚本和订阅索引。

## 状态

主线是:**添加漫画源 → 搜索 / 浏览 → 查看详情 → 阅读 → 记进书架**。另有一个独立的「AI 供应商」页,运行 Magpie 供应商插件包:装包(文件夹或 `.zip`/`.tar.gz`)、登录、用量、模型列表、对话、打卡、插件自己的开关。两者互不相干 —— 不同的包、不同的账号、不同的 Cookie,AI 凭据只进 Keychain。装包被拒时会说明原因:TypeScript 源码、需要 Node 内置模块这两类会给出「该怎么办」,并附上 Core 的原文;认不出的拒绝就原样显示 Core 的话,不编造理由。

在 macOS 27 / Xcode 27 / Swift 6.4 上的一次真实验证:`swift build`、`swift test`(**119 tests / 27 suites**)、Kit 与 App 的 Swift 6 类型检查、iOS 模块产出全过,0 error 0 warning;Core 接口检查 18/18;`swift test --filter Magpie` 61 tests。**没有**跑过 `xcodebuild` 归档与签名,也没有 iOS 模拟器运行时。详见 [docs/STATUS.md](docs/STATUS.md),那里也写明了这次验证覆盖不到的部分。每次改动仍先过 `scripts/check-swift.sh`(解析全部 Swift 文件,抓语法错误)。

用法:在「AI 供应商」页点「安装插件包」,选一个已解开的文件夹或下载来的 `.zip`/`.tar.gz`;插件自己声明登录方式——设备码就按提示打开页面输入验证码,API 密钥就在应用里填表(密码字段不会明文显示)。登录后可以看用量、拉模型列表、在对话页选模型发消息。停止按钮会取消**Core 里的请求**,不是只把界面关掉。

**能装哪些 AI 供应商包,先说清楚**:社区仓库 36 个包里,目前真正能跑的是原始 Copilot 与 `cloudflare-workers-ai`;其余多需要 Node 内建模块或被拒绝并说明原因。

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

## 装一个供应商包

App 本身不随附供应商包。要试,可以自己压一个:Core 仓库的 `magpieplugin/testdata/openai-compatible/` 与 `anthropic-compatible/` 是两个**能跑**的模板(只用 `fetch`,没有 Node 依赖),把它们压成 zip 后在「AI 供应商」里安装即可;契约与自测方法见 Core 的 [docs/PROVIDER-TEMPLATE.md](https://github.com/laincat/VeneraCat-Core/blob/main/docs/PROVIDER-TEMPLATE.md)。

## 网络策略(上架说明用)

`App/Info.plist` 里 `NSAllowsArbitraryLoads = true`。理由不是「图省事」:漫画源由用户自行安装,主机名无法预知,逐主机例外(NSExceptionDomains)列不出来;而拒绝 http 会让一部分能用的源直接不可用。已核对的四个真实源全部只走 https,所以放行的是**未来可能出现的 http 源**,不是当前故障。`ITSAppUsesNonExemptEncryption = false` 也写在同一个文件里 —— 应用只用系统提供的传输加密,没有自研加密。

## 仓库

本仓库是**私有**的:`https://github.com/laincat/Nekularity`。Core 与它不同,是公开的 —— 所以验证机器可以 clone Core,却需要凭据才能拿到这里的源码。

## 在没有 Xcode 的机器上

`scripts/check-swift.sh` 只解析语法,任何机器都能跑:`python3 scripts/check-swift.py`(不需要 Xcode,能抓未闭合的字符串、括号这类错误)。

接口面也能在这里查:`scripts/check-surface-offline.sh` 用 gobind 生成 Core 的 ObjC 头,再跑与 Mac 同一份选择器清单,约十秒。它查的是**头文件**,不是记忆 —— 清单里写错一个选择器,以前要等一趟传输之后才会暴露。

客户端仓库不公开,所以要在另一台 Mac 上验证时,Swift 源码仍需搬过去;Core 不必 —— 它公开在 GitHub 上,直接 `git clone` 后跑 `scripts/mac-verify.sh` 即可。搬 Swift 源码时,分段传输并逐段核对 md5 比整包重传可靠(下面这套工具仍保留,用于没有网络的机器):

```sh
scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]
```

逐段对 md5、拼接、解码、核对归档 md5 与字节数、解包、数 `.swift`、把 xcframework 放进去、跑 `swift build`,每一步一行 `PASS`/`FAIL`。最后多传一个 `clean`,它会在报告之后删掉解包目录、拼接件和归档,机器保持原样。校验用 `md5` 而不是 `shasum`:受限机器上 `md5` 不需要额外授权。

分段包由 `scripts/make-bundle.sh OUTDIR [CHUNK]` 生成:`Package.swift`、`Sources/`、`App/`、`Tests/` 里所有 `.swift` 按路径排序、mtime 与属主归零后打成一个 47 KB 左右的归档,再切成 `CHUNK`(默认 1650)字符的 base64 段,并打印归档 md5 与每段 md5/末尾字符。同样的文件树每次生成的归档逐字节相同,所以校验值可以写进对话里核对。

只改了少数文件时不必重发整包:`scripts/make-delta.sh SINCE OUTDIR [CHUNK]` 用 `git diff --name-only` 取出相对某个提交变化的 `.swift`,按同样规则打成 `delta.tar.gz`,解到旧目录上就地覆盖。默认段长 1548 字符,并同样打印归档 md5 与每段 md5。实测它与手写打包命令产出的归档逐字节相同。

## 许可证

GPL-3.0-or-later,见 [LICENSE](LICENSE)。
