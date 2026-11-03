#!/bin/sh
# Updates the two authoritative build pins, without rewriting acceptance history.
#
#   scripts/set-core-pin.sh <40 hex chars>
#   scripts/set-core-pin.sh --check
#
# scripts/core-version selects the checkout and CoreVersion.swift is what the
# app reports. STATUS records evidence from earlier builds: changing the build
# pin must not change which Core those tests ran. Update paired documentation
# explicitly with scripts/update-pair.py when recording a new candidate/result.
# This does not fetch or build Core; run scripts/fetch-core.sh afterwards.
set -eu

cd "$(dirname "$0")/.."
pin=${1:-}
if [ "$pin" = "--check" ]; then
	exec sh scripts/check-core-pin.sh
fi
old=$(tr -d ' \r\n' <scripts/core-version)

python3 - "$pin" <<'PY'
import pathlib
import re
import sys

pin = sys.argv[1]
if not re.fullmatch(r"[0-9a-f]{40}", pin):
    print("set-core-pin: need a full 40-character revision", file=sys.stderr)
    raise SystemExit(2)

path = pathlib.Path("Sources/NekularityKit/CoreVersion.swift")
raw = path.read_bytes()
updated, count = re.subn(
    rb'(static let pinned = ")[0-9a-f]{40}(\")',
    lambda match: match[1] + pin.encode("ascii") + match[2],
    raw,
)
if count != 1:
    print("set-core-pin: expected one CoreVersion.pinned constant", file=sys.stderr)
    raise SystemExit(1)

# Validate the replacement before writing either build configuration. Keep the
# Swift file's original line endings and all comments unchanged.
path.write_bytes(updated)
pathlib.Path("scripts/core-version").write_bytes(pin.encode("ascii") + b"\n")
PY

sh scripts/check-core-pin.sh
printf 'set-core-pin: %s -> %s\n' "$old" "$pin"
printf 'set-core-pin: next, run sh scripts/fetch-core.sh\n'
