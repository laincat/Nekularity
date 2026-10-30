#!/usr/bin/env python3
"""Parses every Swift file and reports syntax errors.

The client is written on Windows and compiled on macOS, so this catches the
kind of mistake that would otherwise wait for a Mac: a missing brace, an
unclosed string, a stray keyword. It does not type-check: names, protocols
and platform APIs still need `swift build` on a Mac or in CI. One whole class is
caught anyway: a file that names a generated `Mobile*` Core type must import
`VeneraCatCore`, and forgetting that reads as a syntax-valid file until a Mac
compiles it.

    scripts/check-swift.sh            # reports, exits 1 when a file fails
    scripts/check-swift.sh --quiet    # only the summary

tree-sitter-swift lags the Swift 6 grammar in places, so tokens it does not
know yet are blanked out before parsing. That keeps the check useful without
hiding real mistakes: the token list is short, explicit and only removes
syntax, never structure.
"""

from __future__ import annotations

import argparse
import pathlib
import sys

try:
    import tree_sitter
    import tree_sitter_swift
except ImportError:  # pragma: no cover - the message is the point
    sys.exit(
        "check-swift: tree-sitter is not installed; run\n"
        "  python3 -m pip install tree-sitter tree-sitter-swift"
    )

# Tokens newer than the grammar. Each is replaced by nothing, which keeps
# line numbers right and leaves the surrounding syntax to be checked.
UNKNOWN_TOKENS = [b"nonisolated(unsafe)"]

SKIP_DIRS = {".build", "Vendor", "build", ".git", "DerivedData"}

# Types gomobile generates live in their own module. A file that names one and
# forgets the import parses fine here and fails on the Mac, which is exactly the
# mistake this check can catch for free.
CORE_TYPES = ("MobileCore", "MobileHostProtocol", "MobileMagpie", "MobileVersion")
CORE_IMPORT = b"import VeneraCatCore"


def swift_files(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        p
        for p in root.rglob("*.swift")
        if not any(part in SKIP_DIRS for part in p.relative_to(root).parts)
    )


def errors_in(parser, source: bytes) -> list[tuple[int, str]]:
    """Returns (line, detail) for every ERROR or missing node."""
    for token in UNKNOWN_TOKENS:
        source = source.replace(token, b"")
    tree = parser.parse(source)
    found: list[tuple[int, str]] = []
    stack = [tree.root_node]
    while stack:
        node = stack.pop()
        if node.type == "ERROR" or node.is_missing:
            text = source[node.start_byte : min(node.end_byte, node.start_byte + 40)]
            detail = "missing " + node.type if node.is_missing else "unexpected " + text.decode("utf-8", "replace").replace("\n", " ")
            found.append((node.start_point.row + 1, detail.strip()))
            continue
        stack.extend(node.children)
    return sorted(found)


def missing_core_imports(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """Files that name a generated Core type without importing its module."""
    problems: list[tuple[str, str]] = []
    for path in files:
        source = path.read_bytes()
        if CORE_IMPORT in source:
            continue
        for name in CORE_TYPES:
            if name.encode() in source:
                problems.append((str(path.relative_to(root)), name))
                break
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="only print the summary")
    ap.add_argument("--root", default=".", help="where to look for .swift files")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    files = swift_files(root)
    if not files:
        print("check-swift: no .swift files", file=sys.stderr)
        return 1

    parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    failed = 0
    for path in files:
        rel = path.relative_to(root)
        try:
            problems = errors_in(parser, path.read_bytes())
        except Exception as err:  # pragma: no cover - unreadable file
            failed += 1
            print(f"{rel}: {err}")
            continue
        if not problems:
            continue
        failed += 1
        for line, detail in problems[:10]:
            print(f"{rel}:{line}: {detail}")
        if len(problems) > 10:
            print(f"{rel}: … {len(problems) - 10} more")

    for rel, name in missing_core_imports(root, files):
        failed += 1
        print(f"{rel}: names {name} but does not import VeneraCatCore")

    if failed:
        print(f"check-swift: {failed} of {len(files)} files do not parse")
        return 1
    if not args.quiet:
        print(f"check-swift: {len(files)} files parse")
    return 0


if __name__ == "__main__":
    sys.exit(main())
