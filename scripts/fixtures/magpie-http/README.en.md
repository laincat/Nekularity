# Magpie local HTTP fixture

English | [简体中文](README.md)

This directory provides an IPv4-loopback-only Python HTTP server and an importable Magpie provider package. Every credential is a fixed fake value; no real account is needed. It separates model discovery, first text, connection cancellation, refreshed auth and client persistence. It is not a production provider or OAuth implementation.

## Start and package

From the repository root:

```sh
python3 scripts/fixtures/magpie-http/server.py --port 18797 --log /tmp/nk-magpie-http.jsonl
```

Startup reports the actual port. Use `--port 0` for an available port. In another terminal, package the provider:

```sh
cd scripts/fixtures/magpie-http/provider
python3 -m zipfile -c /tmp/magpie-local-http.zip package.json index.mjs
```

Import the ZIP into the client. The provider ID is `local-http-fixture`, the sign-in method is “本地 HTTP 夹具”, and the address is `http://127.0.0.1:18797` (use the actual port). The package rejects external addresses, HTTPS, user information, query strings and non-root paths. Initial auth uses `fixture-expired`; the loader calls `/refresh`, receives `fixture-key` and writes it through `input.client.auth.set`. This only models a fake-credential refresh contract.

## Observable behavior

The model directory contains three entries:

| Model | Server behavior |
|---|---|
| `fixture-model` | SSE returns `第一段 第二段🐾` and `[DONE]` |
| `fixture-held` | Sends `第一段 `, holds the remaining body, then waits for targeted release or peer closure |
| `fixture-denied` | HTTP 503 with JSON error `fixture temporary rejection` |

`GET /events` returns sanitized observations. The `id` on `first_chunk` identifies a request. `POST /release` with JSON `{"id":3}` (replace 3 with the observed id) releases only that request. Held requests expire after 30 seconds and record `expired`; expiry is not a pass. Cancellation must produce server-side `peer_closed`, not just stopped UI or a removed handle.

Logs omit keys, headers, prompts and arbitrary URLs. They contain known routes, request ids, authorization/cookie booleans and first-chunk/completion/rejection/peer-close events. Provider requests require the fake Bearer credential and must omit Cookie. `/events` and `/release` are unauthenticated local test controls.

## Acceptance boundaries

On Windows, published Core `3be57b5` used `mobile.NewMagpieWithStream` against actual HTTP: remote models, refreshed-auth writeback, first text before body completion, ChatCancel peer closure, targeted release, Unicode answers and HTTP 503 all passed. SavedAuth was written to a temporary file and loaded into a new instance, which remained usable with exactly one refresh. Evidence: `E:/Temp/nk-magpie-http-evidence/core-http.log` and `events.json`.

This verifies the public Core API and fixture contract, not Swift URLSession, iOS UI, Keychain, app restarts or real provider accounts. Client acceptance still needs actual import/sign-in, displayed models/replies, cancellation, refreshed-auth storage and restart readback. Do not manually rewrite client credentials as a substitute for persistence verification.
