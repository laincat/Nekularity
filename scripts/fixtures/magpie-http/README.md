# Magpie 本地 HTTP 夹具

[English](README.en.md) | 简体中文

此目录提供仅绑定 `127.0.0.1` 的 Python HTTP 服务与可导入的 Magpie 供应商包。所有凭据都是固定假值，不需要真实账号。它用于区分模型目录、首段文字、取消连接、刷新结果与客户端持久化；不是生产供应商或 OAuth 实现。

## 启动与打包

在仓库根目录运行：

```sh
python3 scripts/fixtures/magpie-http/server.py --port 18797 --log /tmp/nk-magpie-http.jsonl
```

服务启动会输出实际端口。可以用 `--port 0` 取得空闲端口。另开终端打包供应商：

```sh
cd scripts/fixtures/magpie-http/provider
python3 -m zipfile -c /tmp/magpie-local-http.zip package.json index.mjs
```

客户端导入 ZIP，供应商 ID 为 `local-http-fixture`，登录方法为「本地 HTTP 夹具」，地址填 `http://127.0.0.1:18797`（使用实际端口）。包拒绝外部地址、HTTPS、用户信息、查询参数和非根路径。首次账号值为 `fixture-expired`，loader 调用 `/refresh` 得到 `fixture-key` 并通过 `input.client.auth.set` 写回；它只演示假凭据的刷新合同。

## 可验证行为

模型目录有三个条目：

| 模型 | 服务端行为 |
|---|---|
| `fixture-model` | SSE 返回 `第一段 第二段🐾` 与 `[DONE]` |
| `fixture-held` | 先发送 `第一段 `，扣住后半段，等待指定请求的 release 或客户端关闭 |
| `fixture-denied` | HTTP 503，JSON 错误 `fixture temporary rejection` |

`GET /events` 返回脱敏观察。`first_chunk` 的 `id` 标识一次请求；发送 `POST /release`，JSON 体为 `{"id":3}`（以实际 id 替换 3），只释放该请求。每个 held 请求最多等待 30 秒，过期记录 `expired`，不计通过。取消必须看到服务端 `peer_closed`，不能仅以 UI 停止或句柄消失判断。

日志不记录密钥、请求头、提示词或任意 URL，只记录已知路由、请求 id、鉴权/是否带 Cookie、首块/结束/拒绝/对端关闭。供应商请求必须携带假 Bearer 凭据且不能带 Cookie。`/events` 和 `/release` 是无需凭据的本机测试控制接口。

## 验收边界

Windows 已用发布 Core `3be57b5` 的 `mobile.NewMagpieWithStream` 发真实 HTTP 请求：模型目录、刷新写回、首段先于正文完成、ChatCancel 对端关闭、指定请求释放、Unicode 回答、HTTP 503 均通过。将 SavedAuth 写入临时文件并重建实例后仍能调用，刷新次数保持一次。证据：`E:/Temp/nk-magpie-http-evidence/core-http.log` 与 `events.json`。

这证明 Core 公共接口与本夹具的合同，不证明 Swift URLSession、iOS UI、钥匙串、App 重启或真实供应商账号已通过。客户端验收还需实际导入/登录、显示目录与回答、取消、保存刷新结果并重启读取；不要手工改写客户端凭据来替代持久化验证。
