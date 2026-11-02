# 待验证清单

[English](UNVERIFIED.en.md) | 简体中文

更新:2026-11-02。最新完整 Mac UI 回归是 `8acbb78`:Orca Worker 在同一专用模拟器上完成测试目标构建、安装与完整执行,**19 条 / PASS 19 / FAIL 0 / SKIP 0**。长按进入编排与尺寸重启持久化已经验证。后续 Orca Worker 在 App `7586982` 上单独执行拖放重启用例通过,并读 `homeBlocksV2` 交叉确认;这不是重新跑完整套件。已采集 iPhone 402 pt/2 列与 iPad 1032 pt/4 列的明暗发现页、设置页共八张模拟器截图;后续 `211cd64` 的五张到底截图已确认页尾与胶囊不相交(约 21–43 pt 间隔),无需补底边距;3 列宽度仍待验证。iPhone 到底截图无法同时完整显示已经滚到顶部的 TMDB 说明。主题 HTTPS 界面闭环、真机/后台/真实账号仍未验证。`0.2.6`(build 8)发布构建 `41431641042` 全绿;下载的 IPA 为 29,361,985 字节、App/Widget 版本一致、HTTP 200,AltStore 仓库和订阅入口均已核对为同一版本。CI 单测与模拟器 UI 是不同的证据,不复用旧版本测试数作为当前结果。

三套强调色的对比度判据仍来自 `accentTextFollowsTheAccent` 单测与代码;本轮一般明暗布局截图没有逐个测量三套强调色的对比度。三个内置强调色的判定为 `#3482FF` 白字、`#6BA4FF` 深字、`#0A84FF` 白字。

更早的那份结论是:**这棵树编译过了**:GitHub Actions 运行 `41316459367`(提交 `71c8c97`)在 macOS 上完成内置 Core 构建、四项仓库检查、工程生成、`xcodebuild` 编译,并产出了未签名 IPA(18.9 MB)。此前 `b9fdf3c` 之后的一批提交从未经过编译器,那份顾虑到此为止。

编译通过不等于行为正确。CI 已运行 `swift test`,但 iPhone 界面用例在 CI 里只编译、未执行;模拟器执行交给 Mac Orca Worker。真机、真实账号与服务器仍按下表保留缺口。

## 构建已经证明的

| 项目 | 证据 |
|---|---|
| 整个 kit 与 App 能在真实 iOS SDK 上编译 | 运行 `41316459367` 的「Build unsigned device app」成功 |
| 打包成 IPA 的路径可用 | 同一次运行的「Package unsigned IPA」与产物上传成功 |
| 仓库检查在 macOS 上同样通过 | 同一运行的检查步骤:`check-docs`、`check-partitions`、`check-core-pin`、`check-kit-core-calls`、`check-swift`(已装 tree-sitter,真解析 152 个文件) |
| 内核 pin 可复现 | 同一运行先从 `214e7782190d` 拉取并构建 Core 成功 |

首次真实编译抓到并已修掉的四个错误,都是静态检查看不见的:`ComicDetails` 的评分字段被误写进 `Comic`(**会让每个详情页整页失败**)、`@MainActor` 类里的静态方法被非隔离调用、两处 `status == errSecSuccess || errSecItemNotFound`(把 `OSStatus` 当 `Bool`),以及随后 App 目标暴露的 12 个界面错误(样式三元、`Environment` 参数顺序、可选链、PiP 内容源与跨线程快照)。

## 还没验证的

| 提交 | 改了什么 | 现在的状态 | 还剩什么 |
|---|---|---|---|
| 回复截断提示 | 读 Core 事件里的 `outcome`,达到长度上限时在聊天页显示「已达长度上限,回复可能不完整」 | **已编译并跑过单测**(构建 `381f2a6` 全绿) | 让模型答满 max_tokens,看提示是否真的出现 |
| Bangumi 支持 | 账号、收藏五档、话数、每日放送、与追番提醒的合并 | **已编译并跑过单测**(`v0.2.0` 构建全绿,359 项测试) | 真机连一次真实令牌 |
| `33c5c7a` | `seed-simulator.sh` 写入真正在用的环境目录 | 脚本级改动,不参与编译 | 一次 seeded 运行是否真的出现 5 个源 |
| 字幕叠层 | 用 `$subtitleCues` 画文字字幕,跟随 `clock.$sourceTime` | 编译通过 | 播放一次带字幕的源,确认文字按时间出现 |
| 软件通路画中画 | `AVPictureInPictureSampleBufferPlaybackDelegate` | 编译通过;内容源改为按图层构造,两个同步问题的答案放进带锁的快照 | 真机软解一次(VP9/AV1)并转画中画 |
| `198d1ad` | 追剧提醒:kit 规划 + `UNUserNotificationCenter` | 编译通过 | 真机开通知后看「已安排 N 条」;7 个规划单测 |
| `43decff` | Plex 视频源 + Node 固件测试 | `node plugins/plex.test.mjs` 五项通过 | 装进源列表,由真实 Core 运行时加载一次 |
| `ab1ebbb` | 详情读 `stars`/`likesCount`/`isLiked` 并显示评分 | 编译通过(字段已从 `Comic` 移到 `ComicDetails`) | 真实来源下一次详情页见到评分数字 |
| `a4ead24` | 关闭播放器时把位置回写服务器 | 编译通过 | 播放一次服务器条目后关闭;`MediaServer` 3 个回写测试 |
| `0031190` `40e0962` | 发布流水线回到仓库、版本 0.2.0 | **已验证**:手动触发即可完成构建并上传产物 | 打 tag 才会走发布分支;未打 |
| `27dd92c` | 首页三张卡;继续阅读过滤视频 | 编译通过 | 首页渲染;`HomeLayout` 两个新用例 |
| `467b9c5` `4db8265` | 压缩包重名页、弹幕行标识、整数时间戳 | 编译通过,风险低 | 对应单测 |
| `017522b` | 服务器分页 + 30 秒超时 | 编译通过 | 媒体库能否列出条目(需真实服务器) |
| `7787b3b` | `PlaybackProgress` 收敛 | 编译通过(原先最担心的一处,已排除) | 三个播放界面的时长与续播显示 |
| `a693a63` | zip CRC 校验 | 编译通过 | 4 个导入测试 |
| `6ffe7d7` | `VideoPlayerView` 参数顺序 | 编译通过 | 播放器界面实际显示 |
| `4b80a57` | 导入移到后台、`importComic` 变 async | 编译通过 | 导入一个文件夹与一个 `.cbz` |
| `e460fba` | 读不出的文件先备份 | 编译通过 | 造一个坏 store 文件,看是否留下副本 |
| `6d7dc5d` | 迁移崩溃窗口 | 编译通过 | 3 个升级测试;真机升级一次 |

## 需要真实条件才能验证

| 项 | 缺什么 |
|---|---|
| 媒体服务器连接、浏览、播放、进度回写 | 一台 Jellyfin/Emby 的地址与账号 |
| 「即将播出」 | 一个 TMDB key |
| Pixiv 登录后的关注与收藏 | 真实 Pixiv 账号 |
| 画中画、锁屏后台播放、通知触发 | 真机 |
| 本机视频与导入的漫画 | 真机上的文件 |

## 核对清单本身

```sh
git log --oneline b9fdf3c..HEAD
```

表格里**改动过代码或脚本**的提交都该出现;纯文档提交不列,它不参与编译。写这份文档时正是这样发现 `a4ead24`(进度回写)被漏掉的——清单会漂移,所以要能一句话核对。

## 怎么跑

```sh
sh scripts/fetch-core.sh
NK_UI_TESTS=1 NK_UI_SEED=/tmp/seed.json NK_UI_SEED_REPLACE=1 sh scripts/verify-ios.sh
```

CI 已加入 `swift test --no-parallel --verbose`;`xcodebuild build-for-testing` 仍只编译界面用例。执行 UI 要在 Mac 上运行 `test-without-building`,汇报提交号、总数、失败与跳过,保留完整日志。新增用例必须重新构建测试目标;不要拿旧构建产物验证新源码。
