# 界面测试的源种子

[English](README.en.md) | 简体中文

`plugins.json` 是客户端自己的源存储文件，装着仓库里的两个夹具源：`video_probe`（视频）与 `callback_probe`（漫画回调）。CI 的界面测试步骤在跑用例前把它写进模拟器的 App 容器，需要源的用例因此不再跳过。

重新生成（在桌面端仓库里）：

```sh
go run ./cmd/seedgen plugins.json \
  ../Nekularity/UITests/Fixtures/video_probe.js \
  ../Nekularity/UITests/Fixtures/callback_probe.js
```

`scripts/check-seed.sh` 逐字节核对 `callback_probe` 与仓库夹具一致；改动夹具后要重新生成这份种子，否则核对会失败。

真实站点的源（如 `nhentai`、`Komiic`）的脚本是别人的作品，不进仓库，所以依赖它们的用例仍会跳过。
