#!/usr/bin/env python3
"""Run the Magpie loopback fixture against the pinned VeneraCat Core.

    python3 scripts/fixtures/magpie-http/run.py [CORE_CHECKOUT] [EVIDENCE_DIR]

CORE_CHECKOUT defaults to build/core (what scripts/fetch-core.sh creates in CI),
then ../VeneraCat Core. EVIDENCE_DIR defaults to build/magpie-http-probe.

The Go client in this directory talks to Core's public mobile API over real
loopback HTTP. It is not an iOS UI test, does not use URLSession or the Keychain,
and needs no provider account. Failing assertions make it exit non-zero.
"""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import threading

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def core_checkout(given: str | None) -> Path:
    candidates = [Path(given)] if given else [
        ROOT / "build" / "core",
        ROOT.parent / "VeneraCat Core",
    ]
    for path in candidates:
        if (path / "mobile" / "magpie.go").is_file():
            return path
    raise SystemExit("no VeneraCat Core checkout (looked at %s)" %
                     ", ".join(str(p) for p in candidates))


def main() -> int:
    core = core_checkout(sys.argv[1] if len(sys.argv) > 1 else None)
    # The Go client runs with cwd set to the Core checkout, so relative evidence
    # paths would resolve inside Core instead of this repository. Make it absolute.
    out = (Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "build" / "magpie-http-probe").resolve()
    out.mkdir(parents=True, exist_ok=True)

    spec = importlib.util.spec_from_file_location("magpie_http_server", HERE / "server.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    server = module.Server(0, out / "events.jsonl")
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base = "http://127.0.0.1:%d" % server.server_port
    env = os.environ.copy()
    env["GOWORK"] = "off"
    cmd = ["go", "run", str(HERE / "probe.go"), str(HERE / "provider"), base, str(out)]
    try:
        result = subprocess.run(cmd, cwd=str(core), env=env, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=120)
        log = out / "core-http.log"
        log.write_text("$ " + " ".join(cmd) + "\n" + result.stdout + result.stderr,
                       encoding="utf-8")
        print(result.stdout, end="")
        if result.returncode:
            print(result.stderr, end="", file=sys.stderr)
        return result.returncode
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
        (out / "events.json").write_text(
            json.dumps(server.events, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    raise SystemExit(main())
