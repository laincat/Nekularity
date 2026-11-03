# Standard AI local HTTP fixture

English | [简体中文](README.md)

```sh
python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/standard-ai.jsonl
```

The service binds only `127.0.0.1`. Its model is `fixture-model`, and it accepts only the fixed fake key `fixture-key`. It supports whole-response Chat Completions, Responses and Messages requests with `stream:false`, without streaming or credential refresh. Messages requests also require a positive integer `max_tokens`.

| API root | Behavior |
|---|---|
| `http://127.0.0.1:18796/v1` | Successful catalogs and replies in all three protocols |
| `http://127.0.0.1:18796/slow/v1` | Send HTTP 200 headers and hold the response body |
| `http://127.0.0.1:18796/denied/v1` | HTTP 401 with an error body |
| `http://127.0.0.1:18796/unavailable/v1` | HTTP 503 with an error body |
| `http://127.0.0.1:18796/inband/v1` | HTTP 200 carrying a provider error |

`GET /events` returns requests, waits, answers and peer-close observations linked by server request ID. Records contain endpoint categories, whether authorization matched and whether cookies were sent, without credentials or prompt bodies. Requests with cookies are refused.

```sh
curl http://127.0.0.1:18796/events
curl -X POST http://127.0.0.1:18796/release
```

`POST /release` releases current and subsequent slow bodies; restart the service to reset its state. A disconnected client produces `peer_closed` while a 30-second deadline produces `expired`. Expiry does not count as successful cancellation.

The fixture has been exercised on Windows over real loopback HTTP for catalogs, all three replies, errors, TCP closure and body release. This does not establish Swift-client or UI acceptance: UI validation still needs isolated settings/Keychain namespaces and actual interaction evidence.
