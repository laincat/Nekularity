#!/usr/bin/env python3
"""Compares Core's video payloads with what the kit decodes.

A line's label is `name` in Core and was decoded as `title` here. A missing
non-optional field does not fail one field: it fails the whole payload, so every
video detail screen stayed on its spinner and nothing said why. This check is the
one that would have said why.

    python3 scripts/check-video-json.py            # uses $NK_CORE_SRC, else
                                                   # ../VeneraCat Core
    NK_CORE_SRC=/path/to/core python3 scripts/check-video-json.py

Exit codes: 0 both sides agree, 1 a key is read that Core never sends, 3 no Core
checkout to compare against (a limit of this machine, not of the tree).

The Swift types are named by their full path — `VideoDetails.Line` and not
`Line` — because three different `Episode`-shaped types exist in this kit and
matching by last component compared the wrong two.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

# NK_CLIENT_ROOT points the comparison at a tree that is not this repository, so
# scripts/check-checks.sh can break the client on purpose and watch this report it.
ROOT = pathlib.Path(os.environ.get("NK_CLIENT_ROOT") or
                    pathlib.Path(__file__).resolve().parent.parent)
SWIFT = ROOT / "Sources" / "NekularityKit" / "Video" / "VideoModels.swift"

# Core type → the Swift declaration it is decoded into, by full path.
PAIRS: list[tuple[str, list[str]]] = [
    ("Page", ["VideoPage"]),
    ("Item", ["VideoPage", "Item"]),
    ("Details", ["VideoDetails"]),
    ("Line", ["VideoDetails", "Line"]),
    ("Episode", ["VideoDetails", "Line", "Episode"]),
    ("Play", ["VideoPlay"]),
    ("Sniff", ["VideoPlay", "Sniff"]),
]

# Keys Core sends that this client does not read, with the reason. Listed rather
# than omitted: a key that quietly disappears from the payload should show up as a
# one-line change here, not as a screen that stopped showing something.
IGNORED: dict[tuple[str, str], str] = {
    ("VideoPlay", "hls"): "HLS options are not implemented; the player takes a plain URL",
    ("VideoPlay", "variants"): "same: variant selection is not implemented",
    ("VideoPlay.Sniff", "followIframes"): "the WebView sniffer reads the top document only",
    ("VideoPlay.Sniff", "timeoutMs"): "the sniffer uses one fixed timeout",
    ("VideoPlay.Sniff", "match"): "read by the play answer, not by the sniffer description",
}

GO_FIELD = re.compile(r'^\s*([A-Z]\w*)\s+([^\s`]+)\s+`json:"([^"]+)"', re.MULTILINE)
SWIFT_FIELD = re.compile(r"^[ \t]*(?:public\s+|internal\s+|private\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([^={}\n]+)$", re.MULTILINE)

GO_TAG = re.compile(r'json:"([^"]+)"')
SWIFT_DECL = re.compile(r"\b(?:public\s+)?struct\s+([A-Za-z_][A-Za-z0-9_]*)")
# Newlines are excluded on purpose: without that the character class spans lines
# and one match swallows a whole struct, which is how this check first reported
# every field as missing.
SWIFT_PROPERTY = re.compile(
    r"^[ \t]*(?:public\s+|internal\s+|private\s+)?var\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[^={}\n]+$",
    re.MULTILINE,
)
SWIFT_CASE = re.compile(r'^\s*case\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*"([^"]+)"', re.MULTILINE)


def core_source() -> pathlib.Path | None:
    given = os.environ.get("NK_CORE_SRC", "").strip()
    candidates = [pathlib.Path(given)] if given else [ROOT / "build" / "core", ROOT.parent / "VeneraCat Core"]
    for candidate in candidates:
        if (candidate / "video" / "video.go").is_file():
            return candidate
    return None


def brace_body(text: str, start: int) -> str | None:
    open_at = text.find("{", start)
    if open_at < 0:
        return None
    depth = 0
    for index in range(open_at, len(text)):
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
            if depth == 0:
                return text[open_at + 1:index]
    return None


def go_keys(core: pathlib.Path, name: str) -> set[str] | None:
    pattern = re.compile(r"type " + re.escape(name) + r" struct\b")
    text = (core / "video" / "video.go").read_text(encoding="utf-8")
    match = pattern.search(text)
    if not match:
        return None
    body = brace_body(text, match.start())
    if body is None:
        return None
    return {tag.split(",")[0] for tag in GO_TAG.findall(body) if tag != "-"}


def swift_body(path: list[str]) -> str | None:
    """The body of one struct, found by walking the declaration path."""
    text = SWIFT.read_text(encoding="utf-8")
    scope = (0, len(text))
    body = None
    for name in path:
        pattern = re.compile(r"\bstruct\s+" + re.escape(name) + r"\b")
        match = pattern.search(text, scope[0], scope[1])
        if not match:
            return None
        body = brace_body(text, match.start())
        if body is None:
            return None
        open_at = text.find("{", match.start())
        scope = (open_at, open_at + len(body) + 2)
    return body


def top_level(body: str) -> str:
    """Only the lines outside nested braces: a nested struct's CodingKeys must not
    rewrite its parent's keys (VideoDetails.title would become "name" because
    VideoDetails.Line maps title to what Core calls `name`)."""
    kept: list[str] = []
    depth = 0
    for line in body.splitlines():
        if depth == 0:
            kept.append(line)
        depth += line.count("{") - line.count("}")
    return chr(10).join(kept)


# `http.Header` is `map[string][]string` with a name on it, so counting brackets in
# the Go type text — which is the cheap shape test everywhere else — says zero.
GO_LIST_DEPTH = {"http.Header": 2}


def list_depth(go_type: str) -> int:
    return GO_LIST_DEPTH.get(go_type, go_type.count("["))


def go_shapes(core: pathlib.Path, name: str) -> dict[str, str]:
    """Wire key -> the Go type, for the fields of one struct."""
    text = (core / "video" / "video.go").read_text(encoding="utf-8")
    match = re.search(r"type " + re.escape(name) + r" struct", text)
    if not match:
        return {}
    body = brace_body(text, match.start())
    if body is None:
        return {}
    shapes: dict[str, str] = {}
    for _, kind, tag in GO_FIELD.findall(body):
        shapes[tag.split(",")[0]] = kind
    return shapes


def swift_shapes(body: str) -> dict[str, str]:
    """Wire key → the Swift type, for the type's own fields."""
    return {name: kind.strip() for name, kind in SWIFT_FIELD.findall(top_level(body))}


def swift_keys(body: str) -> set[str]:
    """The wire keys a Swift type reads.

    Properties come from the type's own lines. CodingKeys comes from its own
    `enum CodingKeys`, recognised by sitting directly in this struct — a child's
    mapping must not rewrite the parent, which is how `VideoDetails.title` first
    became Core's `name`.
    """
    keys = {name for name in SWIFT_PROPERTY.findall(top_level(body))}
    overrides: dict[str, str] = {}
    depth = 0
    in_keys = False
    for line in body.splitlines():
        stripped = line.strip()
        if depth == 0:
            in_keys = stripped.startswith("enum CodingKeys") or stripped.startswith("private enum CodingKeys")
            if not in_keys:
                depth += line.count("{") - line.count("}")
                continue
        if in_keys and depth == 1:
            match = SWIFT_CASE.match(line)
            if match:
                overrides[match.group(1)] = match.group(2)
        depth += line.count("{") - line.count("}")
        if depth == 0:
            in_keys = False
    return {(overrides.get(key, key)) for key in keys}


def main() -> int:
    core = core_source()
    if core is None:
        print("check-video-json: no Core checkout to compare against")
        print("  set NK_CORE_SRC, or put the two repositories side by side")
        return 3

    problems = 0
    for go_name, path in PAIRS:
        wanted = go_keys(core, go_name)
        if wanted is None:
            print(f"check-video-json: Core has no type {go_name}")
            problems += 1
            continue
        body = swift_body(path)
        if body is None:
            print(f"check-video-json: the kit has no struct {'.'.join(path)}")
            problems += 1
            continue
        have = swift_keys(body)
        missing = sorted(wanted - have - {key for (path_key, key) in IGNORED if path_key == ".".join(path)})
        shapes = go_shapes(core, go_name)
        swift_types = swift_shapes(body)
        for key, go_type in sorted(shapes.items()):
            if key in IGNORED and ((".".join(path)), key) in IGNORED:
                continue
            swift_type = swift_types.get(key)
            if swift_type is None:
                continue
            if list_depth(go_type) > swift_type.count("["):
                problems += 1
                print(f"check-video-json: {'.'.join(path)}.{key} is {swift_type} but Core sends "
                      f"{go_type} — the payload will not decode")
        if missing:
            problems += 1
            print(f"check-video-json: {'.'.join(path)} does not read "
                  + ", ".join(missing) + f" (Core's {go_name} sends it)")

    if problems:
        print(f"check-video-json: {problems} mismatch(es) against {core}")
        return 1
    # Named on success too: an ignore that nobody can see is a hole.
    print(f"check-video-json: ok ({len(PAIRS)} pairs against {core}; "
          f"{len(IGNORED)} key(s) deliberately unread)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
