# hls-subs

[English](hls-subs.en.md) | 简体中文

界面用例 `testHLSPlaysAndSwitchesSubtitles` 用的 HLS 夹具：主清单带两组 WebVTT 字幕（中文默认、英文备选），视频为 fMP4 字节范围分段，无音轨。文件与 Nekophage `internal/player/testdata/hls-subs` 逐字节相同（`stream.mp4` md5 `d321224cce67c39a7f30eb9a90e1dfec`）。

- 画面改制自 **Big Buck Bunny**，© 2008 Blender Foundation，[peach.blender.org](https://peach.blender.org/)，[CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)。原料为同目录 `clip.mp4`；改动为缩放、压缩和无音轨 HLS 封装。
- 字幕是测试文字。

测试进程在 loopback 的 `/hls/` 下提供这些文件，缺少源声明的 `Referer` 一律 403。

## 30 秒续播夹具

`hls-subs/resume/` 是同一授权片段重复三次、无音轨的 30 秒 HLS（`scripts/fixtures/hls-subtitles/media30/` 的副本），没有字幕。7 秒保存点离片尾足够远，满足客户端「位置 > 5 秒且未到 95%」的续播规则。测试用的 shelf 文件名带 UUID，不读写默认的 `shelf.json`。
