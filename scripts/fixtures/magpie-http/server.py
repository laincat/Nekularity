#!/usr/bin/env python3
"""Account-free Magpie HTTP fixture, bound only to IPv4 loopback."""
import argparse
import json
from pathlib import Path
import select
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Server(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, port=18797, log=None):
        self.lock = threading.Lock()
        self.events = []
        self.gates = {}
        self.counter = 0
        self.log = Path(log) if log else None
        if self.log:
            self.log.parent.mkdir(parents=True, exist_ok=True)
        super().__init__(("127.0.0.1", port), Handler)

    def record(self, event, **fields):
        with self.lock:
            item = dict(event=event, **fields)
            self.events.append(item)
            if self.log:
                with self.log.open("a", encoding="utf-8") as out:
                    out.write(json.dumps(item, ensure_ascii=False) + "\n")

    def next_id(self):
        with self.lock:
            self.counter += 1
            return self.counter


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass  # Do not log headers, keys, prompts or arbitrary URLs.

    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def payload(self):
        size = int(self.headers.get("Content-Length", "0"))
        if not 0 < size <= 65536:
            raise ValueError("invalid content length")
        body = json.loads(self.rfile.read(size))
        if not isinstance(body, dict):
            raise ValueError("expected object")
        return body

    def reply(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        self.wfile.write(body)
        self.wfile.flush()

    def do_GET(self):
        self.dispatch()

    def do_POST(self):
        self.dispatch()

    def dispatch(self):
        path = urlsplit(self.path).path
        try:
            if path == "/events" and self.command == "GET":
                with self.server.lock:
                    events = list(self.server.events)
                self.reply(200, events)
                return
            if path == "/release" and self.command == "POST":
                request_id = self.payload().get("id")
                with self.server.lock:
                    gate = self.server.gates.get(request_id) if type(request_id) is int else None
                if gate:
                    gate.set()
                self.reply(200 if gate else 404, {"released": bool(gate)})
                return
            expected = {"/refresh": "POST", "/v1/models": "GET", "/v1/chat/completions": "POST"}
            if path not in expected:
                self.reply(404, {"error": {"message": "unknown fixture endpoint"}})
                return
            if self.command != expected[path]:
                self.reply(405, {"error": {"message": "wrong HTTP method"}})
                return
            request_id = self.server.next_id()
            cookie = bool(self.headers.get("Cookie"))
            if path == "/refresh":
                valid = self.payload().get("refresh_token") == "fixture-refresh" and not cookie
                self.server.record("refresh", id=request_id, authorized=valid, cookie_present=cookie)
                self.reply(200 if valid else 401, {"key": "fixture-key"} if valid else {"error": {"message": "invalid fixture refresh"}})
                return
            authorized = self.headers.get("Authorization") == "Bearer fixture-key"
            self.server.record("request", id=request_id, endpoint=path, authorized=authorized, cookie_present=cookie)
            if not authorized or cookie:
                self.reply(401, {"error": {"message": "fixture authorization required; cookies forbidden"}})
                return
            if path == "/v1/models":
                self.reply(200, {"data": [{"id": m} for m in ("fixture-model", "fixture-held", "fixture-denied")]})
                return
            body = self.payload()
            model = body.get("model")
            if body.get("stream") is not True or not body.get("messages") or model not in {"fixture-model", "fixture-held", "fixture-denied"}:
                self.reply(400, {"error": {"message": "unexpected fixture chat body"}})
                return
            if model == "fixture-denied":
                self.server.record("rejected", id=request_id, status=503)
                self.reply(503, {"error": {"message": "fixture temporary rejection"}})
                return
            self.stream(request_id, held=model == "fixture-held")
        except (ValueError, TypeError, TimeoutError):
            self.reply(400, {"error": {"message": "invalid fixture request"}})
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def stream(self, request_id, held):
        gate = threading.Event()
        if held:
            with self.server.lock:
                self.server.gates[request_id] = gate
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Connection", "close")
            self.end_headers()
            self.close_connection = True
            self.delta("第一段 ")
            self.server.record("first_chunk", id=request_id, held=held)
            if held:
                deadline = time.monotonic() + 30
                while not gate.wait(.05):
                    readable, _, _ = select.select([self.connection], [], [], 0)
                    if readable:
                        try:
                            closed = self.connection.recv(1, socket.MSG_PEEK) == b""
                        except (ConnectionResetError, OSError):
                            closed = True
                        if closed:
                            self.server.record("peer_closed", id=request_id)
                            return
                    if time.monotonic() >= deadline:
                        self.server.record("expired", id=request_id)
                        return
            self.delta("第二段🐾")
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()
            self.server.record("answered", id=request_id)
        except (BrokenPipeError, ConnectionResetError):
            self.server.record("peer_closed", id=request_id)
        finally:
            with self.server.lock:
                self.server.gates.pop(request_id, None)

    def delta(self, text):
        chunk = {"choices": [{"delta": {"content": text}}]}
        self.wfile.write(("data: " + json.dumps(chunk, ensure_ascii=False) + "\n\n").encode("utf-8"))
        self.wfile.flush()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18797)
    parser.add_argument("--log")
    args = parser.parse_args()
    with Server(args.port, args.log) as server:
        print(json.dumps({"event": "ready", "host": "127.0.0.1", "port": server.server_port}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
