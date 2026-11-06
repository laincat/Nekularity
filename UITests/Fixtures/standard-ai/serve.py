#!/usr/bin/env python3
"""Loopback-only AI fixture: whole replies and server-sent streams. No external packages.

python3 UITests/Fixtures/standard-ai/serve.py --port 18796 --log /tmp/ai.jsonl
API key: fixture-key; model: fixture-model.
Roots: /v1, /slow/v1, /denied/v1, /unavailable/v1, /inband/v1, /cutoff/v1.
GET /events returns sanitized observations; GET /requests returns the request
bodies, accepted or rejected, so a 400 can be diagnosed from the client side. POST /release releases slow bodies.
A slow request sends headers, then waits for release or detects a peer close.
A request says which it wants with `stream`: false gets the whole reply, true gets
events. /cutoff sends two text events and then closes without the protocol's
completion marker, so a client that treats a closed connection as a finished
answer is caught.

The request bodies are appended to <log>.requests.jsonl so a test can assert what
the app actually sent. No credentials, cookies or query strings are logged.
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

# The text a stream produces, split so a test can tell pieces apart: the first
# event is one word, the second starts with a space, and the fourth is a
# surrogate pair, which is where a wrong UTF-8/UTF-16 boundary would show.
STREAM_PIECES = ["流式", "第一段", " ", "第二段🐾"]
CUTOFF_PIECES = STREAM_PIECES[:2]


class State:
    def __init__(self, log=None):
        self.lock = threading.Lock()
        self.events = []
        self.counter = 0
        self.release = threading.Event()
        self.log = Path(log) if log else None
        self.requests = None
        self.bodies = []
        self.interval = 1.2
        if self.log:
            self.log.parent.mkdir(parents=True, exist_ok=True)
            self.requests = self.log.with_name(self.log.name + ".requests.jsonl")

    def record(self, event, **fields):
        with self.lock:
            item = dict(event=event, **fields)
            self.events.append(item)
            if self.log:
                with self.log.open("a", encoding="utf-8") as stream:
                    stream.write(json.dumps(item, ensure_ascii=False) + "\n")

    def record_request(self, body):
        """Keeps one received body; called only when the fixture accepted it."""
        with self.lock:
            self.bodies.append(body)
            if not self.requests:
                return
            with self.requests.open("a", encoding="utf-8") as stream:
                stream.write(json.dumps(body, ensure_ascii=False) + "\n")

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

    # --- streaming -------------------------------------------------------

    def stream_event(self, data, event=None):
        """Writes one server-sent event and flushes it, so pieces arrive apart."""
        lines = []
        if event:
            lines.append("event: " + event)
        lines.append("data: " + data)
        payload = ("\n".join(lines) + "\n\n").encode("utf-8")
        self.wfile.write(payload)
        self.wfile.flush()

    def text_event(self, protocol, text):
        """The event that carries one piece of text, in that protocol's shape."""
        if protocol == "chat":
            body = {"choices": [{"index": 0, "delta": {"content": text}}]}
            self.stream_event(json.dumps(body, ensure_ascii=False))
        elif protocol == "responses":
            body = {"type": "response.output_text.delta", "delta": text}
            self.stream_event(json.dumps(body, ensure_ascii=False), "response.output_text.delta")
        else:
            body = {"type": "content_block_delta",
                    "index": 0,
                    "delta": {"type": "text_delta", "text": text}}
            self.stream_event(json.dumps(body, ensure_ascii=False), "content_block_delta")

    def completion_event(self, protocol):
        """The protocol's own end marker: a closed connection is not one."""
        if protocol == "chat":
            self.stream_event("[DONE]")
        elif protocol == "responses":
            self.stream_event(json.dumps({"type": "response.completed"}), "response.completed")
        else:
            self.stream_event(json.dumps({"type": "message_stop"}), "message_stop")

    def stream_reply(self, protocol, request_id, pieces, cutoff):
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.flush()
        self.close_connection = True
        self.server.state.record("streamed", id=request_id, protocol=protocol, mode="cutoff" if cutoff else "normal")
        sent = 0
        try:
            for piece in pieces:
                self.text_event(protocol, piece)
                sent += 1
                time.sleep(self.server.state.interval)  # long enough to see the half answer
            if cutoff:
                self.server.state.record("stream_cut", id=request_id, sent=sent)
                return  # no completion marker: the body just ends
            self.completion_event(protocol)
            self.server.state.record("stream_complete", id=request_id, sent=sent)
        except (BrokenPipeError, ConnectionResetError):
            self.server.state.record("peer_closed", id=request_id)

    # --- routing ---------------------------------------------------------

    def handle_request(self):
        path = urlsplit(self.path).path
        if path == "/events" and self.command == "GET":
            self.respond(200, self.server.state.snapshot())
            return
        if path == "/requests" and self.command == "GET":
            # Over HTTP rather than only in a file: a UI test runs in the
            # simulator and should not depend on reading the host's /tmp.
            with self.server.state.lock:
                bodies = list(self.server.state.bodies)
            self.respond(200, bodies)
            return
        if path == "/release" and self.command == "POST":
            self.server.state.release.set()
            self.respond(200, {"released": True})
            return
        parts = path.strip("/").split("/")
        mode = "normal"
        if parts and parts[0] in {"slow", "denied", "unavailable", "inband", "cutoff"}:
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
        content = None
        if endpoint != "models":
            try:
                size = int(self.headers.get("Content-Length", "0"))
                if not 0 < size <= 65536:
                    raise ValueError("invalid size")
                content = json.loads(self.rfile.read(size))
                field = "input" if endpoint == "responses" else "messages"
                # A caller states what it wants; the fixture answers in kind
                # rather than deciding for it.
                valid = (content.get("model") == "fixture-model"
                         and type(content.get("stream")) is bool
                         and bool(content.get(field)))
                if endpoint == "messages":
                    valid = valid and type(content.get("max_tokens")) is int and content["max_tokens"] > 0
                if not valid:
                    raise ValueError("invalid body")
            except (ValueError, AttributeError, TypeError):
                # Recorded, not just refused: a 400 with no body is a failure
                # nobody can diagnose from the client side.
                self.server.state.record("rejected", id=request_id, body=content)
                self.server.state.record_request({"rejected": True, "body": content})
                self.respond(400, {"error": {"message": "unexpected fixture request body"}}, request_id)
                return
        if mode in {"denied", "unavailable", "inband"}:
            status = {"denied": 401, "unavailable": 503, "inband": 200}[mode]
            self.respond(status, {"error": {"message": "fixture rejection"}}, request_id)
            return
        if content is not None:
            self.server.state.record_request(content)
        if endpoint == "models":
            reply = {"data": [{"id": "fixture-model"}, {"id": "fixture-alt"}]}
        elif endpoint == "chat/completions":
            reply = {"choices": [{"message": {"role": "assistant", "content": "Fixture Chat answer"}}]}
        elif endpoint == "responses":
            reply = {"output": [{"type": "message", "content": [{"type": "output_text", "text": "Fixture Responses answer"}]}]}
        else:
            reply = {"content": [{"type": "text", "text": "Fixture Messages answer"}]}
        if content is not None and content.get("stream") is True:
            protocol = {"chat/completions": "chat", "responses": "responses", "messages": "messages"}[endpoint]
            pieces = CUTOFF_PIECES if mode == "cutoff" else STREAM_PIECES
            self.stream_reply(protocol, request_id, pieces, cutoff=mode == "cutoff")
            return
        self.respond(200, reply, request_id, slow=mode == "slow")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=18796)
    parser.add_argument("--log")
    parser.add_argument("--interval", type=float, default=1.2,
                        help="seconds between stream pieces (default 1.2)")
    args = parser.parse_args()
    with Server(args.port, args.log) as server:
        server.state.interval = args.interval
        print(json.dumps({"event": "ready", "host": "127.0.0.1", "port": server.server_port}), flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
        finally:
            server.state.release.set()


if __name__ == "__main__":
    main()
