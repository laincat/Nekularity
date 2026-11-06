# Standard-AI local HTTP fixture

[简体中文](README.md) | English

```sh
python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/standard-ai.jsonl
```

The server listens on `127.0.0.1` only. The model name is `fixture-model` and the only accepted key is the fake `fixture-key`. Chat Completions, Responses and Messages are all supported, **whole and streamed alike**: `stream:false` in the request body gets the whole reply, `stream:true` gets server-sent events. Messages also requires a positive integer `max_tokens`.

| API root | Behaviour |
|---|---|
| `http://127.0.0.1:18796/v1` | the model catalogue and normal answers for all three protocols |
| `http://127.0.0.1:18796/slow/v1` | sends the HTTP 200 headers, then withholds the body |
| `http://127.0.0.1:18796/denied/v1` | HTTP 401 error body |
| `http://127.0.0.1:18796/unavailable/v1` | HTTP 503 error body |
| `http://127.0.0.1:18796/inband/v1` | HTTP 200 carrying the provider's error |
| `http://127.0.0.1:18796/cutoff/v1` | sends two stream events and then disconnects without the protocol's completion marker |

## The shape of a stream

Each piece of text is its own event, 0.4 s apart: `流式`, `第一段`, a space, `第二段🐾`. The last is a surrogate pair, so a wrong UTF-8/UTF-16 boundary shows up. Each protocol uses its own shape:

| Protocol | Text event | Completion marker |
|---|---|---|
| Chat Completions | `data: {"choices":[{"delta":{"content":"…"}}]}` | `data: [DONE]` |
| Responses | `event: response.output_text.delta` + `data: {"type":"response.output_text.delta","delta":"…"}` | `data: {"type":"response.completed"}` |
| Messages | `event: content_block_delta` + `data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"…"}}` | `data: {"type":"message_stop"}` |

`/cutoff/v1` sends the first two pieces and closes the connection. **The completion marker is part of the protocol; a closed connection is not** - which is exactly the defect it catches: a client that reads "the connection ended" as "the answer is finished" fails here.

## Records

`GET /events` returns the request, waiting, answer, stream-start, completion and disconnect records, keyed by the server's request id. The fields are states only - which path class, whether authentication matched, whether a cookie was sent, how many pieces went out - never a key or a prompt. A request carrying a cookie is refused.

The received request bodies are written separately to `<the --log value>.requests.jsonl`, one JSON per line, so a test can assert what the app actually sent (whether `stream` is `true`, the `model`, the number of messages).

```sh
curl http://127.0.0.1:18796/events
curl -X POST http://127.0.0.1:18796/release
```

`POST /release` releases the body of the current and later slow replies; restarting the server resets the state. A client that disconnects during a slow reply produces `peer_closed`; waiting 30 s produces `expired`. The two must not be conflated into "the cancel worked".

## What this fixture proves

On Windows, over real loopback HTTP: whole replies for all three protocols, the model catalogue, 401/503/in-band errors, TCP close and body release; and the streamed replies of all three protocols decoded by **Core's own `aiapi.StreamDecoder`**, yielding `["流式","第一段"," ","第二段🐾"]` with `Done()==true`, while `/cutoff` yields the first two pieces with `Done()==false`.

It does not prove the Swift client or the screen. Increments painted on screen still need a separate test setup/Keychain namespace and evidence from real interaction.
