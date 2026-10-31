#!/usr/bin/env python3
"""Applies the same change to a Chinese/English document pair, or to neither.

    scripts/update-pair.py spec.json

The spec is:

    {
      "pair": ["docs/STATUS.md", "docs/STATUS.en.md"],
      "edits": [
        {"zh": {"old": "…", "new": "…"}, "en": {"old": "…", "new": "…"}}
      ]
    }

Why this exists: editing the two files with two separate scripts went wrong three
times in one day — the Chinese edit landed, the English anchor did not match, and
the result was committed because the failure was one `assert` in the middle of a
shell line. Here every anchor is checked in both files before anything is written,
so a mismatch leaves both files untouched and exits non-zero.

`check-docs.sh` catches structural drift (row and heading counts). It cannot catch
prose that only one side received. This script prevents the mistake instead.
"""

from __future__ import annotations

import json
import pathlib
import sys


def load(spec_path: pathlib.Path) -> tuple[list[pathlib.Path], list[dict]]:
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    pair = [pathlib.Path(p) for p in spec["pair"]]
    if len(pair) != 2:
        raise SystemExit("update-pair: \"pair\" must name exactly two files")
    return pair, spec["edits"]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: update-pair.py spec.json", file=sys.stderr)
        return 2
    pair, edits = load(pathlib.Path(sys.argv[1]))
    for path in pair:
        if not path.is_file():
            print(f"update-pair: {path} does not exist", file=sys.stderr)
            return 2

    texts = {path: path.read_text(encoding="utf-8") for path in pair}
    # Check every anchor in memory first. Nothing is written until all of them match,
    # so a half-applied pair cannot exist.
    for index, edit in enumerate(edits, start=1):
        for path, side in zip(pair, ("zh", "en"), strict=True):
            old = edit[side]["old"]
            new = edit[side]["new"]
            found = texts[path].count(old)
            if found != 1:
                print(
                    f"update-pair: edit {index}: {path} contains the anchor {found} times, expected 1",
                    file=sys.stderr,
                )
                print(f"  anchor: {old.splitlines()[0][:80] if old else '(empty)'}", file=sys.stderr)
                return 1
            texts[path] = texts[path].replace(old, new, 1)

    for path, text in texts.items():
        path.write_text(text, encoding="utf-8", newline="\n")
        print(f"update-pair: wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
