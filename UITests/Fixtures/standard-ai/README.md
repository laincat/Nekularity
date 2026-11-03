# 标准 AI 本地 HTTP 夹具

[English](README.en.md) | 简体中文

```sh
python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/standard-ai.jsonl
```

服务仅监听 `127.0.0.1`。模型名是 `fixture-model`,只接受固定假密钥 `fixture-key`。支持 Chat Completions、Responses、Messages 的整包请求,要求正文为 `stream:false`;不实现流式或凭据刷新。Messages 请求还需正整数 `max_tokens`。

| API 根 | 行为 |
|---|---|
| `http://127.0.0.1:18796/v1` | 模型目录和三种协议的正常回答 |
| `http://127.0.0.1:18796/slow/v1` | 先发 HTTP 200 响应头,暂不发送正文 |
| `http://127.0.0.1:18796/denied/v1` | HTTP 401 错误正文 |
| `http://127.0.0.1:18796/unavailable/v1` | HTTP 503 错误正文 |
| `http://127.0.0.1:18796/inband/v1` | HTTP 200 携带供应商错误 |

`GET /events` 返回请求、等待、作答和连接关闭记录,以服务端请求 ID 关联。记录只含路径类别、鉴权是否匹配、是否携带 Cookie 等状态,不保存密钥或提示正文。携带 Cookie 的请求被拒绝。

```sh
curl http://127.0.0.1:18796/events
curl -X POST http://127.0.0.1:18796/release
```

`POST /release` 释放当前及后续慢响应的正文;重新启动服务可重置状态。慢响应期间客户端断开连接会产生 `peer_closed`,等待 30 秒则产生 `expired`。两者不能混称为取消成功。

夹具在 Windows 上用真实 loopback HTTP 验证过三种回答、模型目录、错误、TCP 关闭和释放正文。它不证明 Swift 客户端或界面通过;UI 验证仍需独立的测试设置/Keychain 命名空间与实际操作证据。
