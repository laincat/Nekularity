#!/usr/bin/env python3
"""Replaces one literal in a file, for scripts/check-checks.sh.

The self-tests need to change a single key in a copy of a client source. Doing that
from the shell means threading quotes through two more layers than is reasonable, and
the last two attempts at it produced a mangled newline and a mangled backreference
instead of the text they meant.
"""

from __future__ import annotations

import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: check-checks-rename-key.py FILE OLD NEW", file=sys.stderr)
        return 2
    path, old, new = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
    text = path.read_text(encoding="utf-8")
    if old not in text:
        print(f"check-checks-rename-key: {old} is not in {path}", file=sys.stderr)
        return 1
    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
