#!/usr/bin/env python3
"""Compares the chat events Core emits with the ones the kit reads.

The chat stream crosses the gomobile boundary as JSON, so a field Core adds and the
kit never reads is dropped without a word — that is how a reply cut off by the
token limit used to look like one that finished. The same applies to the `kind`
values: an event the kit does not name arrives as `.other` and is ignored.

    python3 scripts/check-magpie-event.py           # uses $NK_CORE_SRC, else
                                                    # ../VeneraCat Core
    NK_CORE_SRC=/path/to/core python3 scripts/check-magpie-event.py

Exit codes: 0 both sides agree, 1 a field or kind is missing, 3 no Core checkout.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SWIFT = ROOT / "Sources" / "NekularityKit" / "Magpie" / "MagpieChat.swift"

# Fields the client may ignore on purpose, with the reason.
IGNORED: dict[str, str] = {}


def core_source() -> pathlib.Path | None:
    given = os.environ.get("NK_CORE_SRC", "").strip()
    candidates = [pathlib.Path(given)] if given else [ROOT / "build" / "core", ROOT.parent / "VeneraCat Core"]
    for candidate in candidates:
        if (candidate / "mobile" / "magpie.go").is_file():
            return candidate
    return None


def core_payload(core: pathlib.Path) -> tuple[set[str], set[str]]:
    """The JSON keys chatEventJSON writes, and the EventKind values Core emits."""
    text = (core / "mobile" / "magpie.go").read_text(encoding="utf-8")
    start = text.index("func chatEventJSON")
    end = text.index("\n}", start)
    body = text[start:end]

    # Only the payload's own map: the usage map nested inside it is kept whole by
    # the kit as JSON text, so its keys are not this level's business.
    start_map = body.index("payload := map[string]any{")
    depth = 0
    end_map = len(body)
    for index in range(start_map, len(body)):
        if body[index] == "{":
            depth += 1
        elif body[index] == "}":
            depth -= 1
            if depth == 0:
                end_map = index
                break
    keys = set(re.findall(r'"([a-zA-Z]+)":', body[start_map:end_map]))
    keys |= set(re.findall(r'payload\["([a-zA-Z]+)"\]', body))

    stream = (core / "magpieplugin" / "stream.go").read_text(encoding="utf-8")
    kinds = set(re.findall(r'EventKind = "([a-z]+)"', stream))
    return keys, kinds


def kit_payload() -> tuple[set[str], set[str]]:
    """The keys the kit reads from the event object, and the kinds it names."""
    text = SWIFT.read_text(encoding="utf-8")
    keys = set(re.findall(r'object\["([a-zA-Z]+)"\]', text))

    enum = re.search(r"public enum Kind: String, Sendable \{(.*?)\n    \}", text, re.DOTALL)
    kinds: set[str] = set()
    if enum:
        for line in enum.group(1).splitlines():
            line = line.strip()
            if not line.startswith("case "):
                continue
            for name in line[len("case "):].split(","):
                name = name.strip()
                if re.fullmatch(r"[a-z]+", name):
                    kinds.add(name)
    return keys, kinds


def main() -> int:
    core = core_source()
    if core is None:
        print("check-magpie-event: no Core checkout to compare against")
        print("  set NK_CORE_SRC, or put the two repositories side by side")
        return 3

    core_keys, core_kinds = core_payload(core)
    kit_keys, kit_kinds = kit_payload()
    problems = 0

    for key in sorted(core_keys - kit_keys - set(IGNORED)):
        problems += 1
        print(f"check-magpie-event: Core sends \"{key}\" and the kit never reads it")
    for kind in sorted(core_kinds - kit_kinds):
        if kind == "end":
            # `end` is the stream marker, not a chat event: Core closes with it.
            continue
        problems += 1
        print(f"check-magpie-event: Core emits kind \"{kind}\" and the kit has no case for it")

    if problems:
        print(f"check-magpie-event: {problems} mismatch(es) against {core}")
        return 1
    print(f"check-magpie-event: ok ({len(core_keys)} keys, {len(core_kinds)} kinds against {core})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
