# 本地 HLS 字幕夹具

[English](README.en.md) | 简体中文

此服务供 iOS 播放器定向验收使用。媒体文件从参数目录读取，不包含在本仓库，也不复制任何真实账号或站点媒体。

```sh
go run scripts/fixtures/hls-subtitles/main.go -root /path/to/hls-subs
```

已有的自制素材可使用 Nekophage `c545212` 的 `internal/player/testdata/hls-subs`：主清单、fMP4 字节范围、中英文 WebVTT，中文默认、英文备选。服务只绑定 `127.0.0.1` 随机端口；首行 JSON 给出 `source_url`，该地址返回一个可安装的 `VideoSource` 脚本。脚本声明实际服务地址和固定假 Referer。服务没有后台安装或自启动行为，结束时终止本次拥有的进程。

除 `/source.js` 外，请求都必须携带 `Referer: https://fixture.invalid/`。每条请求输出 JSON：路径、方法、Referer 是否匹配、Range、状态、响应字节数及 Content-Range。没有输出真实凭据。媒体使用 Go 标准库文件服务，支持字节范围；清单和 WebVTT 使用对应 MIME 类型。源脚本获取无须此 Referer。

Lead 已在 Windows 真实 loopback HTTP 中验证源地址、缺 Referer 的 403、中英文清单与 UTF-8 字幕、32 字节精确 Range 206、越界 Range 416，日志 `E:/Temp/nk-ios-hls-evidence/verify.log`。这是服务夹具验证，未证明 iOS 播放器或界面通过。

模拟器定向验收应使用专用设备与本地源，观察真实视频时钟/画面、中文字幕、切换英文后的活动文字及关闭后消失；可先暂停在有 cue 的位置，避免短片在操作中结束。记录服务请求和实际截图，不能把轨道名称存在当成字幕呈现。后续应用重开或跨进程续播须单独注明。该素材没有音轨，不证明扬声器、后台、PiP 或真机行为。
