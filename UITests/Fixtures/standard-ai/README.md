# 标准 AI 本地 HTTP 夹具

[English](README.en.md) | 简体中文

```sh
python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/standard-ai.jsonl
```

服务仅监听 `127.0.0.1`。模型名是 `fixture-model`,只接受固定假密钥 `fixture-key`。支持 Chat Completions、Responses、Messages 三种协议,**整包与流式都支持**:请求正文里 `stream:false` 得到整包回答,`stream:true` 得到 server-sent events。Messages 请求还需正整数 `max_tokens`。

| API 根 | 行为 |
|---|---|
| `http://127.0.0.1:18796/v1` | 模型目录和三种协议的正常回答 |
| `http://127.0.0.1:18796/slow/v1` | 先发 HTTP 200 响应头,暂不发送正文 |
| `http://127.0.0.1:18796/denied/v1` | HTTP 401 错误正文 |
| `http://127.0.0.1:18796/unavailable/v1` | HTTP 503 错误正文 |
| `http://127.0.0.1:18796/inband/v1` | HTTP 200 携带供应商错误 |
| `http://127.0.0.1:18796/cutoff/v1` | 流式回答发两段后直接断开,不发本协议的完成标记 |

## 流式的形状

每段文字是一个独立事件,默认间隔 1.2 秒(`--interval` 可改,界面用例靠这段间隔看到「写了一半」),依次是 `流式` / `第一段` / 一个空格 / `第二段🐾` —— 最后一段是代理对,UTF-8 与 UTF-16 边界算错就会露出来。三种协议各按自己的形状发:

| 协议 | 文字事件 | 完成标记 |
|---|---|---|
| Chat Completions | `data: {"choices":[{"delta":{"content":"…"}}]}` | `data: [DONE]` |
| Responses | `event: response.output_text.delta` + `data: {"type":"response.output_text.delta","delta":"…"}` | `data: {"type":"response.completed"}` |
| Messages | `event: content_block_delta` + `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}` | `data: {"type":"message_stop"}` |

`/cutoff/v1` 只发前两段就关闭连接。**完成标记是协议的一部分,连接关闭不是** —— 这正是它要抓的缺陷:把「连接断了」当成「回答说完了」的客户端会在这里被抓住。

## 记录

`GET /events` 返回请求、等待、作答、开始流式、完成与断开记录,以服务端请求 ID 关联。记录的字段只含路径类别、鉴权是否匹配、是否携带 Cookie、发了几段等状态,不保存密钥或提示正文。携带 Cookie 的请求被拒绝。

收到的请求正文可以用 `GET /requests` 读(界面用例走这条,不读主机文件),也写到 `<--log 的值>.requests.jsonl`,一行一个 JSON,供测试断言「App 实际发了什么」(`stream` 是否为 `true`、`model`、消息条数)。

```sh
curl http://127.0.0.1:18796/events
curl -X POST http://127.0.0.1:18796/release
```

`POST /release` 释放当前及后续慢响应的正文;重新启动服务可重置状态。慢响应期间客户端断开连接会产生 `peer_closed`,等待 30 秒则产生 `expired`。两者不能混称为取消成功。

## 这份夹具证明什么

在 Windows 上用真实 loopback HTTP 跑过:三种协议的整包回答、模型目录、401/503/在包内报错、TCP 关闭与释放正文;三种协议的流式回答用 **Core 自己的 `aiapi.StreamDecoder`** 解码,得到 `["流式","第一段"," ","第二段🐾"]` 且 `Done()==true`,`/cutoff` 得到前两段且 `Done()==false`。

它不证明 Swift 客户端或界面通过 —— 界面上的增量显示仍需独立的测试设置/Keychain 命名空间与实际操作证据。
