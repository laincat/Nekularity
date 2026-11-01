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
import re
import sys

# The parse needs tree-sitter; every rule below it does not. A machine that
# compiles the tree (a Mac with Xcode) often has no Python tree-sitter, and
# skipping the whole check there would lose the rules exactly where they are
# cheapest to apply — so a missing parser downgrades this to the rule checks and
# says so, instead of exiting.
PARSER_NOTE = ""

try:
    import tree_sitter
    import tree_sitter_swift
    # The grammar is compiled for a specific tree-sitter ABI. Constructing a
    # Parser is what actually raises for a grammar built against a newer ABI; the
    # Language object alone does not.
    tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    HAVE_PARSER = True
except ImportError:
    HAVE_PARSER = False
    PARSER_NOTE = (
        "check-swift: tree-sitter is not installed, so files are not parsed for "
        "syntax; the rule checks still run.\n"
        "  python3 -m pip install tree-sitter tree-sitter-swift"
    )
except ValueError as exc:
    HAVE_PARSER = False
    PARSER_NOTE = (
        f"check-swift: the Swift grammar cannot load here ({exc}), so files are not "
        "parsed for syntax; the rule checks still run.\n"
        "  a Python 3.10+ with tree-sitter>=0.24 is needed"
    )

# Tokens newer than the grammar. Each is replaced by nothing, which keeps
# line numbers right and leaves the surrounding syntax to be checked.
UNKNOWN_TOKENS = [b"nonisolated(unsafe)"]

# tree-sitter-swift reads `each` as the parameter-pack keyword everywhere, so a
# property named `each` in an assignment reads as an error — and MagpieUsage
# has one, decoded from the usage JSON. Renaming it here keeps the columns and
# the line numbers right while letting the grammar see a plain identifier.
# Parameter packs do not appear in this codebase; if they ever do, this is the
# line to revisit.
IDENTIFIER_ALIASES = [(re.compile(rb"\beach\b"), b"eack")]

SKIP_DIRS = {".build", "Vendor", "build", ".git", "DerivedData"}

# Types gomobile generates live in their own module. A file that names one and
# forgets the import parses fine here and fails on the Mac, which is exactly the
# mistake this check can catch for free.
CORE_TYPES = ("MobileCore", "MobileHostProtocol", "MobileMagpie", "MobileVersion")
CORE_IMPORT = b"import VeneraCatCore"

# The same mistake one layer up: an App file that names a kit type and forgets
# `import NekularityKit`. Picking distinctive names keeps this from flagging a
# word that happens to appear in a comment about something else.
KIT_TYPES = (
    "MagpieAccounts",
    "MagpiePackageStore",
    "MagpieSignIn",
    "MagpieOptionStore",
    "CoreVersion",
    "ShelfStore",
    "SourceStore",
    "SearchHistoryStore",
    "BackupImporter",
    "ImageLoader",
    "SourceLibrary",
    "ReaderNavigation",
    "CoreClient",
    "CoreHost",
)
KIT_IMPORT = b"import NekularityKit"


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
    for pattern, alias in IDENTIFIER_ALIASES:
        source = pattern.sub(alias, source)
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


def missing_kit_imports(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """App files that name a kit type without importing the kit.

    Only App/ is checked: the kit imports itself, and the tests use
    `@testable import NekularityKit`, which contains the same bytes.
    """
    problems: list[tuple[str, str]] = []
    app = root / "App"
    for path in files:
        if app not in path.parents:
            continue
        source = path.read_bytes()
        if KIT_IMPORT in source:
            continue
        for name in KIT_TYPES:
            if name.encode() in source:
                problems.append((str(path.relative_to(root)), name))
                break
    return problems


def protocol_methods(source: bytes, name: bytes) -> list[bytes]:
    """Method names a protocol declares, by looking for its declaration."""
    at = source.find(b"protocol " + name)
    if at < 0:
        return []
    body = source[at:]
    end = body.find(b"\n}")
    body = body[: end if end > 0 else len(body)]
    names: list[bytes] = []
    for line in body.split(b"\n"):
        line = line.strip()
        if line.startswith(b"func "):
            names.append(line[5:].split(b"(")[0].split(b"<")[0].strip())
    return names


def test_stubs_missing_methods(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """Test doubles that conform to `MagpieRunner.Core` and miss a method.

    A test-only stub is the one place where a protocol gaining a method stays
    silent here and fails on the Mac, and it costs a whole validation round:
    `swift build` passes and only `swift test` fails. Only declarations are
    checked, not the many places that merely hold a `MagpieRunner.Core`.
    """
    runner = root / "Sources/NekularityKit/Magpie/MagpieRunner.swift"
    if not runner.exists():
        return []
    required = protocol_methods(runner.read_bytes(), b"Core")
    if not required:
        return []
    declaration = re.compile(
        r"(?:class|struct|actor)\s+(\w+)[^\n{]*:\s*MagpieRunner\.Core"
    )
    problems: list[tuple[str, str]] = []
    for path in files:
        # Only tests: a real type is spread over extensions, so a window would
        # misread it, and the Mac's type check covers those anyway.
        if "Tests" not in path.relative_to(root).parts:
            continue
        source = path.read_bytes().decode("utf-8", "replace")
        for match in declaration.finditer(source):
            # A stub is a short thing; look at its own body only.
            window = source[match.start() : match.start() + 4000]
            missing = [n.decode() for n in required if "func " + n.decode() not in window]
            if missing:
                problems.append(
                    (
                        str(path.relative_to(root)),
                        f"{match.group(1)} lacks " + ", ".join(missing),
                    )
                )
    return problems


def duplicate_test_names(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """Two tests with the same name in one suite.

    Swift reports that as an invalid redeclaration; here it happens when a test is
    copied into a file that already has it, which reads fine and fails on a Mac.
    """
    suite_at = re.compile(r"\s*@Suite\s+(?:struct|class|enum|actor)\s+(\w+)")
    test_at = re.compile(r"\s*@Test\b.*?func\s+(\w+)\s*\(")
    problems: list[tuple[str, str]] = []
    for path in files:
        if "Tests" not in path.relative_to(root).parts:
            continue
        suite = None
        seen: dict[str, dict[str, int]] = {}
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            match = suite_at.match(line)
            if match:
                suite = match.group(1)
                seen.setdefault(suite, {})
                continue
            match = test_at.match(line)
            if not match or suite is None:
                continue
            name = match.group(1)
            first = seen[suite].get(name)
            if first is not None:
                problems.append((str(path.relative_to(root)), f"{suite}.{name}(), first at line {first}"))
            else:
                seen[suite][name] = number
    return problems



def stored_predicates(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """An NSPredicate kept in a variable and passed to `matching`.

    That reads fine and fails on a Mac under Swift 6: NSPredicate is not Sendable,
    so handing a stored one to a main-actor-isolated method is a data-race
    diagnostic. Building it at the call site has no such problem, and this file
    cannot see the error any other way — the interface tests are the one part of
    the tree the Windows machine never type-checks.
    """
    stored = re.compile(r"\s*(?:let|var)\s+(\w+)\s*(?::\s*NSPredicate\s*)?=\s*NSPredicate\(")
    problems: list[tuple[str, str]] = []
    for path in files:
        text = path.read_text(encoding="utf-8")
        names = set()
        for line in text.splitlines():
            match = stored.match(line)
            if match:
                names.add(match.group(1))
        if not names:
            continue
        for name in sorted(names):
            if re.search(r"matching\(\s*" + name + r"\s*\)", text):
                problems.append((str(path.relative_to(root)), f"stores NSPredicate {name} and passes it to matching"))
    return problems


def unterminated_strings(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """A "..." literal that continues past the end of its line.

    Swift has no multi-line form with single quotes, so this is a compile error —
    but the parser used here recovers instead of failing, and the Mac is the only
    place it would otherwise be noticed. It happens when a newline is written where
    an escaped \n was meant.
    """
    problems: list[tuple[str, str]] = []
    for path in files:
        in_block = False
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if '"""' in line:
                # An odd count opens or closes a multi-line literal.
                if line.count('"""') % 2 == 1:
                    in_block = not in_block
                continue
            if in_block:
                continue
            # Prose in a comment may quote a word; that is not a literal.
            stripped = line.lstrip()
            if stripped.startswith("//") or stripped.startswith("*") or stripped.startswith("/*"):
                continue
            quotes = 0
            escaped = False
            for ch in line:
                if escaped:
                    escaped = False
                    continue
                if ch == "\\":
                    escaped = True
                    continue
                if ch == '"':
                    quotes += 1
            if quotes % 2 == 1:
                problems.append((str(path.relative_to(root)), f"line {number} ends inside a string literal"))
    return problems


def element_query_predicates(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """An element query predicate that XCTest refuses.

    `label.length > 0` reads like a filter and fails at run time with
    XCTElementQueryInvalidPredicate, which no compile catches. Asking for a
    predicate that cannot work is a test that can never pass.
    """
    problems: list[tuple[str, str]] = []
    for path in files:
        for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "label.length" not in line:
                continue
            problems.append((str(path.relative_to(root)),
                             f"line {number}: 'label.length' in a query predicate is rejected by XCTest"))
    return problems


def unknown_identifiers(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """An identifier the interface tests ask for that nothing in the app creates.

    The tests reach controls by identifier, so a typo is not a compile error — it is
    a case that waits out its timeout and reports "missing", which reads like a
    client fault. Only literals inside a namespace the app actually uses are
    checked, so an email or a URL in a test is not mistaken for a tag.
    """
    app_text = "\n".join(p.read_text(encoding="utf-8") for p in root.rglob("*.swift")
                         if p.relative_to(root).parts[0] in ("App", "Sources"))
    namespaces = set(re.findall(r'"([a-z][A-Za-z0-9_]*)\.', app_text))
    problems: list[tuple[str, str]] = []
    for path in files:
        if "UITests" not in path.relative_to(root).parts:
            continue
        for literal in sorted(set(re.findall(r'"([a-z][\w.]*\.[\w.]+)"', path.read_text(encoding="utf-8")))):
            namespace, _, _ = literal.partition(".")
            if namespace + "." not in {n + "." for n in namespaces}:
                continue
            prefix = literal.rsplit(".", 1)[0] + "."
            if prefix not in app_text and literal not in app_text:
                problems.append((str(path.relative_to(root)), f"asks for {literal!r}, which no identifier in App or Sources creates"))
    return problems

def missing_kit_import(root: pathlib.Path, files: list[pathlib.Path]) -> list[tuple[str, str]]:
    """A file that names a kit type without importing the kit.

    This shipped once: DesignSystem named ThemeStore and Theme after the kit was
    split out, and nothing said so until CI built it — three commits, none of them
    compiling. Parsing cannot see it, because the syntax is perfect.
    """
    declared: set[str] = set()
    for path in root.rglob("*.swift"):
        parts = path.relative_to(root).parts
        if parts[0] != "Sources":
            continue
        text = path.read_text(encoding="utf-8")
        declared |= set(re.findall(
            # `public final class ThemeStore` is the shape that got missed.
            r"^public\s+(?:final\s+|open\s+|indirect\s+|@\w+\s+)*"
            r"(?:struct|class|enum|protocol|actor|typealias|func|var|let)\s+([A-Z]\w*)",
            text, re.M))

    problems: list[tuple[str, str]] = []
    for path in files:
        parts = path.relative_to(root).parts
        if parts[0] not in ("App", "Tests"):
            continue
        text = path.read_text(encoding="utf-8")
        if re.search(r"^\s*(?:@testable\s+)?import NekularityKit\s*$", text, re.M):
            continue
        # Names this file declares itself are its own.
        local = set(re.findall(r"^\s*(?:public\s+)?(?:struct|class|enum|protocol|actor)\s+([A-Z]\w*)",
                               text, re.M))
        used = {name for name in declared - local
                if name in text}
        if used:
            problems.append((str(path.relative_to(root)),
                             f"names {', '.join(sorted(used)[:3])} from the kit without importing it"))
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--quiet", action="store_true", help="only print the summary")
    ap.add_argument("--root", default=".", help="where to look for .swift files")
    ap.add_argument("--no-parser", action="store_true",
                    help="run the rule checks without parsing (no tree-sitter needed)")
    args = ap.parse_args()

    root = pathlib.Path(args.root).resolve()
    files = swift_files(root)
    if not files:
        print("check-swift: no .swift files", file=sys.stderr)
        return 1

    failed = 0
    parse = HAVE_PARSER and not args.no_parser
    if parse:
        parser = tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
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
    elif PARSER_NOTE:
        print(PARSER_NOTE, file=sys.stderr)

    for rel, name in missing_core_imports(root, files):
        failed += 1
        print(f"{rel}: names {name} but does not import VeneraCatCore")

    for rel, name in missing_kit_imports(root, files):
        failed += 1
        print(f"{rel}: names {name} but does not import NekularityKit")

    for rel, detail in test_stubs_missing_methods(root, files):
        failed += 1
        print(f"{rel}: a MagpieRunner.Core stub lacks {detail}")

    for rel, detail in duplicate_test_names(root, files):
        failed += 1
        print(f"{rel}: {detail} is declared twice")

    for rel, detail in unterminated_strings(root, files):
        failed += 1
        print(f"{rel}: {detail}")

    for rel, detail in missing_kit_import(root, files):
        failed += 1
        print(f"{rel}: {detail}")

    for rel, detail in unknown_identifiers(root, files):
        failed += 1
        print(f"{rel}: {detail}")

    for rel, detail in element_query_predicates(root, files):
        failed += 1
        print(f"{rel}: {detail}")

    for rel, detail in stored_predicates(root, files):
        failed += 1
        print(f"{rel}: {detail}; build it at the call site")

    if failed:
        print(f"check-swift: {failed} problem(s) across {len(files)} files")
        return 1
    if not args.quiet:
        if parse:
            print(f"check-swift: {len(files)} files parse")
        else:
            print(f"check-swift: {len(files)} files checked by the rules only")
    return 0


if __name__ == "__main__":
    sys.exit(main())
