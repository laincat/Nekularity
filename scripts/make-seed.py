#!/usr/bin/env python3
"""Rebuilds the records of a simulator seed from the scripts in this tree.

    python3 scripts/make-seed.py OLD_SEED NEW_SEED [SCRIPT ...]

    python3 scripts/make-seed.py /tmp/seed.json /tmp/seed-new.json \\
        UITests/Fixtures/callback_probe.js UITests/Fixtures/video_probe.js

Why this exists: the seed a simulator is fed is written by `cmd/seedgen` in the
desktop repository, which has no remote, so a machine that only has this
repository cannot regenerate one. A seed is not magic — it is one record per
source, and for a script inside this tree every field of that record can be read
off the script itself:

    type      from `class X extends ComicSource` / `class X extends VideoSource`
              -> "comic" / "video-js" (the values Core reports, and the ones
              `PluginRecord.isVideo` checks)
    key       the `key = "..."` declaration
    name      the `name = "..."` declaration
    version   the `version = "..."` declaration
    body      the script, verbatim
    sha256    sha256 of that body, which is what `scripts/check-seed.sh` verifies
    origin    "file", enabled true, empty attribution

Real sites are the part this cannot rebuild: their scripts are not in this
repository and never will be, so their records are carried over from OLD_SEED
untouched and flagged in the output. A seed rebuilt this way is only as good as
OLD_SEED for those, which is why the tool prints both lists.

The output is written with two-space indentation and LF line endings. Script
bodies keep their original line endings, so their hashes describe the files on
disk. Load order is preserved for carried records and the rebuilt ones follow.
"""

import argparse
import hashlib
import json
import re
import sys

KINDS = {"ComicSource": "comic", "VideoSource": "video-js"}
FIELDS = ("name", "key", "version")


def record(path):
    """The record a client would write for this script."""
    with open(path, encoding="utf-8", newline="") as f:
        body = f.read()
    found = re.search(r"class\s+\w+\s+extends\s+(\w+)", body)
    if not found:
        raise SystemExit(f"{path}: no `class X extends Y` to read the kind from")
    parent = found.group(1)
    if parent not in KINDS:
        raise SystemExit(f"{path}: extends {parent}, which this tool does not know")
    values = {}
    for field in FIELDS:
        match = re.search(rf'^\s*{field}\s*=\s*"([^"]*)"', body, re.M)
        if not match:
            raise SystemExit(f"{path}: no `{field} = \"...\"` declaration")
        values[field] = match.group(1)
    return {
        "type": KINDS[parent],
        "key": values["key"],
        "name": values["name"],
        "version": values["version"],
        "body": body,
        "sha256": hashlib.sha256(body.encode()).hexdigest(),
        "origin": "file",
        "enabled": True,
        "attribution": {},
        "indexAttribution": {},
    }


def main():
    parser = argparse.ArgumentParser(description="rebuild seed records from scripts in this tree")
    parser.add_argument("old", help="seed to carry real-site records over from")
    parser.add_argument("new", help="where to write the rebuilt seed")
    parser.add_argument("scripts", nargs="+", help="scripts whose records should be rebuilt")
    args = parser.parse_args()

    with open(args.old, encoding="utf-8") as f:
        old = json.load(f)
    if not isinstance(old, list):
        raise SystemExit(f"{args.old}: a seed is a list of records")

    rebuilt = [record(path) for path in args.scripts]
    keys = {r["key"] for r in rebuilt}
    if len(keys) != len(rebuilt):
        raise SystemExit("two scripts declare the same key")
    carried = [r for r in old if r.get("key") not in keys]

    with open(args.new, "w", encoding="utf-8", newline="\n") as f:
        json.dump(carried + rebuilt, f, ensure_ascii=False, indent=2)

    print("rebuilt: " + ", ".join(f"{r['key']}({r['type']})" for r in rebuilt))
    print("carried over: " + (", ".join(sorted(r["key"] for r in carried)) or "none"))
    print(f"wrote {args.new}: {len(carried) + len(rebuilt)} source(s)")


if __name__ == "__main__":
    sys.exit(main())
