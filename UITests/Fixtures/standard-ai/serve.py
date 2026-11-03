#!/usr/bin/env python3
"""Loopback-only, whole-response AI fixture. No external packages or accounts.

python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/ai.jsonl
API key: fixture-key; model: fixture-model.
Roots: /v1, /slow/v1, /denied/v1, /unavailable/v1, /inband/v1.
GET /events returns sanitized observations. POST /release releases slow bodies.
A slow request sends headers, then waits for release or detects a peer close.
This fixture does not implement streaming, OAuth, or credential refresh.
"""
import argparse
import json
from pathlib import Path
import select
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class State:
    def __init__(self, log=None):
        self.lock = threading.Lock()
        self.events = []
        self.counter = 0
        self.release = threading.Event()
        self.log = Path(log) if log else None
        if self.log:
            self.log.parent.mkdir(parents=True, exist_ok=True)

    def record(self, event, **fields):
        with self.lock:
            item = dict(event=event, **fields)
            self.events.append(item)
            if self.log:
                with self.log.open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps(item, ensure_ascii=False) + "\n")

    def next_id(self):
        with self.lock:
            self.counter += 1
            return self.counter

    def snapshot(self):
        with self.lock:
            return list(self.events)


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port=18796, log=None):
        self.state = State(log)
        super().__init__(("127.0.0.1", port), Handler)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass  # Never log headers, credentials, query strings or prompt bodies.

    def do_GET(self):
        self.handle_request()

    def do_POST(self):
        self.handle_request()

    def respond(self, status, payload, request_id=None, slow=False):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        if slow:
            self.server.state.record("waiting", id=request_id)
            deadline = time.monotonic() + 30
            while not self.server.state.release.wait(0.05):
                readable, _, _ = select.select([self.connection], [], [], 0)
                if readable:
                    try:
                        closed = self.connection.recv(1, socket.MSG_PEEK) == b""
                    except (ConnectionResetError, OSError):
                        closed = True
                    if closed:
                        self.server.state.record("peer_closed", id=request_id)
                        return
                if time.monotonic() >= deadline:
                    self.server.state.record("expired", id=request_id)
                    return
        try:
            self.wfile.write(body)
            self.wfile.flush()
            if request_id is not None:
                self.server.state.record("answered", id=request_id, status=status)
        except (BrokenPipeError, ConnectionResetError):
            self.server.state.record("peer_closed", id=request_id)

    def handle_request(self):
        path = urlsplit(self.path).path
        if path == "/events" and self.command == "GET":
            self.respond(200, self.server.state.snapshot())
            return
        if path == "/release" and self.command == "POST":
            self.server.state.release.set()
            self.respond(200, {"released": True})
            return
        parts = path.strip("/").split("/")
        mode = "normal"
        if parts and parts[0] in {"slow", "denied", "unavailable", "inband"}:
            mode = parts.pop(0)
        if not parts or parts.pop(0) != "v1":
            self.respond(404, {"error": {"message": "unknown fixture root"}})
            return
        endpoint = "/".join(parts)
        if endpoint not in {"models", "chat/completions", "responses", "messages"}:
            self.respond(404, {"error": {"message": "unknown fixture endpoint"}})
            return
        expected_method = "GET" if endpoint == "models" else "POST"
        if self.command != expected_method:
            self.respond(405, {"error": {"message": "wrong HTTP method"}})
            return
        authorized = self.headers.get("Authorization") == "Bearer fixture-key"
        authorized = authorized or self.headers.get("x-api-key") == "fixture-key"
        cookie_present = bool(self.headers.get("Cookie"))
        request_id = self.server.state.next_id()
        self.server.state.record("request", id=request_id, endpoint=endpoint,
                                 mode=mode, authorized=authorized, cookie_present=cookie_present)
        if not authorized:
            self.respond(401, {"error": {"message": "use the fixture key"}}, request_id)
            return
        if cookie_present:
            self.respond(400, {"error": {"message": "AI requests must not send cookies"}}, request_id)
            return
        if endpoint != "models":
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65536:
                    raise ValueError("invalid size")
                content = json.loads(self.rfile.read(size))
                field = "input" if endpoint == "responses" else "messages"
                valid = (content.get("model") == "fixture-model"
                         and content.get("stream") is False and bool(content.get(field)))
                if endpoint == "messages":
                    valid = valid and type(content.get("max_tokens")) is int and content["max_tokens"] > 0
                if not valid:
                    raise ValueError("invalid body")
            except (ValueError, AttributeError, TypeError):
                self.respond(400, {"error": {"message": "unexpected fixture request body"}}, request_id)
                return
        if mode in {"denied", "unavailable", "inband"}:
            status = {"denied": 401, "unavailable": 503, "inband": 200}[mode]
            self.respond(status, {"error": {"message": "fixture rejection"}}, request_id)
            return
        if endpoint == "models":
            reply = {"data": [{"id": "fixture-model"}, {"id": "fixture-alt"}]}
        elif endpoint == "chat/completions":
            reply = {"choices": [{"message": {"role": "assistant", "content": "Fixture Chat answer"}}]}
        elif endpoint == "responses":
            reply = {"output": [{"type": "message", "content": [{"type": "output_text", "text": "Fixture Responses answer"}]}]}
        else:
            reply = {"content": [{"type": "text", "text": "Fixture Messages answer"}]}
        self.respond(200, reply, request_id, slow=mode == "slow")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18796)
    parser.add_argument("--log")
    args = parser.parse_args()
    with Server(args.port, args.log) as server:
        print(json.dumps({"event": "ready", "host": "127.0.0.1", "port": server.server_port}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.state.release.set()


if __name__ == "__main__":
    main()
