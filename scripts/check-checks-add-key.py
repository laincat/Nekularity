#!/usr/bin/env python3
"""Adds one stored property to a Swift struct, for scripts/check-checks.sh.

The self-test needs a client type that reads a key Core never sends, which means
editing a Swift source without an editor. Doing it here rather than inline keeps the
shell script free of quoting: every earlier attempt at that ended in a mangled
newline inside a string literal.
"""

from __future__ import annotations

import pathlib
import re
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: check-checks-add-key.py FILE STRUCT PROPERTY", file=sys.stderr)
        return 2
    path, struct, prop = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    text = path.read_text(encoding="utf-8")
    match = re.search(r"struct " + re.escape(struct) + r"[^{]*{", text)
    if not match:
        print(f"check-checks-add-key: no struct {struct} in {path}", file=sys.stderr)
        return 1
    # No default on purpose: the rule reads stored properties, and `= ""` makes the
    # line stop looking like one. The copy is never compiled.
    line = f"    public var {prop}: String"
    at = match.end()
    path.write_text(text[:at] + "\n" + line + text[at:], encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
