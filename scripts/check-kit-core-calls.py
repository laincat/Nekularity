#!/usr/bin/env python3
"""Checks that every `core.method(...)` the kit calls is one that exists.

The client is written on Windows and compiled on macOS, and the gomobile module
only exists after `scripts/fetch-core.sh` has built it there. Until then a Swift
file can name `core.categoryComics(...)` and nothing objects — the failure waits
for the Mac, which is exactly the wait this shortens.

    python3 scripts/check-kit-core-calls.py            # uses $NK_CORE_SRC, else
                                                       # ../VeneraCat Core
    NK_CORE_SRC=/path/to/core python3 scripts/check-kit-core-calls.py

Exit codes: 0 every call exists, 1 a call names a method nothing declares,
3 no Core checkout to compare against (a limit of this machine, not of the tree;
`verify-ios.sh` treats it as a skip).

Three things are called `core` in this kit, and a call may reach any of them:

  * `MobileCore`, exported by Core for comics — parsed from Core's mobile package
  * `MobileMagpie`, Core's plugin runtime — parsed the same way
  * `CoreClient`, this kit's own wrapper around both — parsed from the kit

Only names are compared, never signatures, so this is not a compiler: it catches
the mistake that actually happens — calling a method that was never added, or
was renamed — and leaves argument types to the Mac.
"""

from __future__ import annotations

import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CORE_METHOD = re.compile(r"^func \(c \*Core\) ([A-Z][A-Za-z0-9]*)\(", re.MULTILINE)
MAGPIE_METHOD = re.compile(r"^func \(m \*Magpie\) ([A-Z][A-Za-z0-9]*)\(", re.MULTILINE)
# A Swift method this kit declares, at any visibility: `public func install(`
# and `func plainText(` both count, since both are reachable through `core.`.
SWIFT_METHOD = re.compile(r"^\s*(?:public |internal |private |fileprivate )?func ([a-zA-Z][A-Za-z0-9]*)\(", re.MULTILINE)
CALL = re.compile(r"\bcore\.([a-z][A-Za-z0-9]*)\(")


def core_source() -> pathlib.Path | None:
    """The Core checkout to compare against, or None when this machine has none."""
    given = os.environ.get("NK_CORE_SRC", "").strip()
    candidates = [pathlib.Path(given)] if given else [ROOT / "build" / "core", ROOT.parent / "VeneraCat Core"]
    for candidate in candidates:
        if (candidate / "mobile" / "mobile.go").is_file():
            return candidate
    return None


def go_methods(directory: pathlib.Path, pattern: re.Pattern[str]) -> set[str]:
    """Every method gomobile exports from one type, under the name Swift sees it.

    Swift lowercases the first letter of the Go method: `CategoryComics` becomes
    `categoryComics`, `NormalizeURL` becomes `normalizeURL`. Both spellings are
    kept so a rename in either direction still fails the comparison.
    """
    names: set[str] = set()
    for file in sorted(directory.glob("*.go")):
        if file.name.endswith("_test.go"):
            continue
        text = file.read_text(encoding="utf-8", errors="replace")
        for name in pattern.findall(text):
            names.add(name)
            names.add(name[0].lower() + name[1:])
    return names


def swift_methods() -> set[str]:
    """Every method this kit declares, which is what `core.` may also reach."""
    names: set[str] = set()
    for path in sorted((ROOT / "Sources" / "NekularityKit").rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        names.update(SWIFT_METHOD.findall(text))
    return names


def main() -> int:
    core = core_source()
    if core is None:
        print(
            "check-kit-core-calls: no Core checkout to compare against\n"
            "  set NK_CORE_SRC, or put the two repositories side by side",
            file=sys.stderr,
        )
        return 3

    core_methods = go_methods(core / "mobile", CORE_METHOD)
    magpie_methods = go_methods(core / "mobile", MAGPIE_METHOD)
    if not core_methods or not magpie_methods:
        print(f"check-kit-core-calls: no exported methods found in {core}", file=sys.stderr)
        return 3
    known = core_methods | magpie_methods | swift_methods()

    missing: list[tuple[str, int, str]] = []
    seen = 0
    for path in sorted((ROOT / "Sources" / "NekularityKit").rglob("*.swift")):
        text = path.read_text(encoding="utf-8", errors="replace")
        for match in CALL.finditer(text):
            seen += 1
            name = match.group(1)
            if name in known:
                continue
            line = text.count("\n", 0, match.start()) + 1
            missing.append((str(path.relative_to(ROOT)), line, name))

    if missing:
        print(f"check-kit-core-calls: {len(missing)} call(s) name a method nothing declares", file=sys.stderr)
        for where, line, name in missing:
            print(f"  {where}:{line}: core.{name}", file=sys.stderr)
        print(f"  compared against {core}", file=sys.stderr)
        return 1

    print(f"check-kit-core-calls: ok ({seen} calls against {len(known)} known names)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
