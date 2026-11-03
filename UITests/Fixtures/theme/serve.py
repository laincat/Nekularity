#!/usr/bin/env python3
"""Serves the theme-link fixtures that `UITests/ZZThemeLinkTests.swift` installs.

    python3 UITests/Fixtures/theme/serve.py --cert leaf.pem --key leaf.key

Two listeners on loopback, because the cases test two schemes:

    18791  https  /valid.json   a theme the app accepts, and selects, and keeps
                  /invalid.json truncated, so the app must keep its old theme
    18792  http   /http.json    a valid theme, which the app must refuse on the
                              scheme alone, before it fetches anything

The certificate is not in the repository: `scripts/theme-fixture.sh` generates a
throwaway CA for the run and trusts it in one simulator only. Nothing here needs
the network, an account or a real site.

Every request is appended to `--log` when given, so a failing case can be told
apart from one whose fixture was never asked.
"""

import argparse
import http.server
import ssl
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent

HTTPS_ROUTES = {"/valid.json": HERE / "valid.json", "/invalid.json": HERE / "invalid.json"}
HTTP_ROUTES = {"/http.json": HERE / "http.json"}


class Handler(http.server.BaseHTTPRequestHandler):
    """Answers only the routes this fixture owns; anything else is a 404."""

    protocol_version = "HTTP/1.1"

    def do_GET(self):
        route = self.path.split("?", 1)[0]
        target = self.server.routes.get(route)
        self._record("%d GET %s" % (self.server.server_port, route))
        if target is None:
            body = b"not a fixture route\n"
            self.send_response(404)
        else:
            body = target.read_bytes() if target.exists() else b""
            self.send_response(200 if target.exists() else 404)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _record(self, line):
        log = getattr(self.server, "request_log", None)
        if log is None:
            sys.stderr.write(line + "\n")
            return
        with log["lock"]:
            with open(log["path"], "a", encoding="utf-8") as f:
                f.write(line + "\n")

    def log_message(self, fmt, *args):
        pass


def listen(port, routes, tls=None, request_log=None):
    server = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
    server.routes = routes
    server.request_log = request_log
    if tls:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(str(tls[0]), str(tls[1]))
        server.socket = context.wrap_socket(server.socket, server_side=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


def main():
    parser = argparse.ArgumentParser(description="theme-link fixtures")
    parser.add_argument("--cert", required=True, help="PEM certificate for 18791")
    parser.add_argument("--key", required=True, help="PEM private key for 18791")
    parser.add_argument("--https-port", type=int, default=18791)
    parser.add_argument("--http-port", type=int, default=18792)
    parser.add_argument("--log", help="append one line per request to this file")
    args = parser.parse_args()

    request_log = None
    if args.log:
        request_log = {"path": args.log, "lock": threading.Lock()}
        Path(args.log).write_text("", encoding="utf-8")

    listen(args.https_port, HTTPS_ROUTES, (args.cert, args.key), request_log)
    listen(args.http_port, HTTP_ROUTES, None, request_log)
    print(
        "theme fixture: https://127.0.0.1:%d/{valid,invalid}.json "
        "http://127.0.0.1:%d/http.json" % (args.https_port, args.http_port),
        flush=True,
    )
    threading.Event().wait()


if __name__ == "__main__":
    main()
