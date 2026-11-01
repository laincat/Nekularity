#!/usr/bin/env python3
"""Compares the JSON each Core payload carries with what the kit decodes.

The failure this catches has happened repeatedly and always silently: Core renames
or drops a field, the kit decodes the payload without complaint, and the screen
shows less than it should. A field that is always nil is the visible symptom, and
nothing reports it.

    python3 scripts/check-json-keys.py            # uses $NK_CORE_SRC, else
                                                  # ../VeneraCat Core
    NK_CORE_SRC=/path/to/core python3 scripts/check-json-keys.py

Exit codes: 0 both sides agree, 1 a key is read that Core never sends, 2 the
comparison could not run (no Core checkout, or a struct that moved).

Only the pairs in TYPES are compared, because only those are Core's own
encodings. A comic's `tags` or `chapters` come from the source script rather than
from Core, so they are not Core's to declare and are not checked here.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent

# Go type in Core → Swift type in this kit. Both are matched by name, and the Go
# side is searched for across the whole checkout so a move does not break this.
TYPES: list[tuple[str, str]] = [
    ("Category", "CategoryPage"),
    ("CategoryPart", "CategoryPart"),
    ("Ranking", "RankingPage"),
    ("RankingOption", "RankingOption"),
    ("SearchOptionGroup", "SearchOptionGroup"),
    ("Record", "PluginRecord"),
    ("SourceSetting", "SourceSetting"),
    # The restore plan: the iOS importer now writes each source's values back,
    # and a renamed key here would make that silently write nothing.
    ("LogEntry", "SourceLogEntry"),
    # The thread the phone draws: a renamed field there shows an empty comment.
    ("TagAction", "TagAction"),
    # A pasted link: a renamed field means the comic never opens.
    ("LinkTarget", "LinkTarget"),
    ("ComicComment", "ComicComment"),
    ("CommentSupport", "CommentSupport"),
    ("Plan", "BackupPlan"),
    ("SourceRestore", "BackupSource"),
    # The usage card: Core builds this report itself from whatever the package
    # answered, so a renamed key here is a quota that stops being shown.
    ("UsageReport", "MagpieUsage"),
    ("UsageResets", "Resets"),
    ("UsageWindow", "Window"),
]

GO_TAG = re.compile(r'json:"([^",]+)')
SWIFT_CASE_LINE = re.compile(r"^\s*case\s+(.+?)\s*$", re.MULTILINE)
# A stored property: `var name: Type` with nothing else on the line. A computed
# property (`{ ... }`) or one with an initialiser is not part of the wire format,
# and taking those was how this check first reported `id` and `isRandom` as keys.
SWIFT_STORED = re.compile(
    r"^\s*(?:public\s+|internal\s+|private\s+)?(?:var|let)\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*[^={]+$",
    re.MULTILINE,
)


def core_source() -> pathlib.Path | None:
    given = os.environ.get("NK_CORE_SRC", "").strip()
    candidates = [pathlib.Path(given)] if given else [ROOT / "build" / "core", ROOT.parent / "VeneraCat Core"]
    for candidate in candidates:
        if (candidate / "mobile" / "mobile.go").is_file():
            return candidate
    return None


def brace_body(text: str, start: int) -> str | None:
    """The text inside the first {...} at or after start, brace-matched."""
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


def go_struct_keys(core: pathlib.Path, name: str) -> set[str] | None:
    """The JSON keys of one Go struct, or None when no such struct exists."""
    pattern = re.compile(r"type " + re.escape(name) + r" struct\b")
    for path in sorted(core.rglob("*.go")):
        if path.name.endswith("_test.go"):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        match = pattern.search(text)
        if not match:
            continue
        body = brace_body(text, match.start())
        if body is None:
            continue
        return {tag for tag in GO_TAG.findall(body) if tag != "-"}
    return None


def top_level_properties(body: str) -> set[str]:
    """Stored properties declared directly in a type body, not in a nested one."""
    keys: set[str] = set()
    depth = 0
    for line in body.splitlines():
        stripped = line.strip()
        if depth == 0:
            match = SWIFT_STORED.match(line)
            if match:
                keys.add(match.group(1))
        depth += stripped.count("{") - stripped.count("}")
        if depth < 0:
            depth = 0
    return keys


def swift_type_keys(name: str) -> set[str] | None:
    """The wire keys one Swift type decodes, or None when the type moved.

    Only this type's own body is read. A nested type's CodingKeys would otherwise
    answer for its parent, which is how an early version of this check reported a
    comic's keys as belonging to a category page.
    """
    pattern = re.compile(r"(?:public\s+)?(?:struct|final class|enum)\s+" + re.escape(name) + r"\b")
    for path in sorted((ROOT / "Sources" / "NekularityKit").rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in pattern.finditer(text):
            body = brace_body(text, match.start())
            if body is None:
                continue
            coding = re.search(r"enum CodingKeys\b[^{]*", body)
            if coding:
                coding_body = brace_body(body, coding.start())
                if coding_body is None:
                    continue
                keys: set[str] = set()
                for line in SWIFT_CASE_LINE.findall(coding_body):
                    for part in line.split(","):
                        part = part.strip()
                        if "=" in part:
                            keys.add(part.split("=", 1)[1].strip().strip('"'))
                        elif part:
                            keys.add(part)
                if keys:
                    return keys
                continue
            # No CodingKeys: the type's own stored properties are the wire
            # names. Nested types carry their own, so only depth one counts.
            keys = top_level_properties(body)
            if keys:
                return keys
    return None


def main() -> int:
    core = core_source()
    if core is None:
        print(
            "check-json-keys: no Core checkout to compare against\n"
            "  set NK_CORE_SRC, or put the two repositories side by side",
            file=sys.stderr,
        )
        return 2

    problems: list[str] = []
    pairs = 0
    for go_name, swift_name in TYPES:
        go_keys = go_struct_keys(core, go_name)
        swift_keys = swift_type_keys(swift_name)
        if go_keys is None:
            problems.append(f"{go_name}: no such struct in Core — update the table")
            continue
        if swift_keys is None:
            problems.append(f"{swift_name}: no such type in the kit — update the table")
            continue
        pairs += 1
        # Reading a key Core never sends is the silent failure. Core sending a
        # key the kit ignores is usually deliberate, so it is not reported.
        for key in sorted(swift_keys - go_keys):
            problems.append(f"{swift_name} reads \"{key}\", which Core's {go_name} never sends")

    if problems:
        print(f"check-json-keys: {len(problems)} problem(s)", file=sys.stderr)
        for line in problems:
            print(f"  {line}", file=sys.stderr)
        print(f"  compared against {core}", file=sys.stderr)
        return 1

    print(f"check-json-keys: ok ({pairs} payload(s) agree)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
