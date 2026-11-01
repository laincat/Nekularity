#!/bin/sh
# Checks that a simulator seed really contains the fixture in this tree.
#
#   sh scripts/check-seed.sh /tmp/seed-ios9.json
#   sh scripts/check-seed.sh /tmp/seed.json UITests/Fixtures/callback_probe.js
#
# A seed is built from the fixture by the desktop's `cmd/seedgen`, and the two are
# sent to the verification machine as separate files with separate hashes. They
# drifted once: the seed was built before a fixture edit, the case then ran against
# yesterday's script and the failure pointed at the client. This makes that drift a
# one-line check instead of a mystery.
set -eu

cd "$(dirname "$0")/.."
seed=${1:-}
fixture=${2:-UITests/Fixtures/callback_probe.js}
key=callback_probe

if [ -z "$seed" ] || [ ! -f "$seed" ]; then
	printf 'check-seed: pass the seed json (built by nekophage cmd/seedgen)\n' >&2
	exit 2
fi
if [ ! -f "$fixture" ]; then
	printf 'check-seed: no fixture at %s\n' "$fixture" >&2
	exit 2
fi

python3 - "$seed" "$fixture" "$key" <<'PY'
import hashlib
import json
import sys

seed_path, fixture_path, key = sys.argv[1], sys.argv[2], sys.argv[3]

with open(seed_path, encoding="utf-8") as f:
    entries = json.load(f)
if not isinstance(entries, list):
    print("check-seed: the seed is not a list of sources")
    raise SystemExit(1)

entry = next((e for e in entries if isinstance(e, dict) and e.get("key") == key), None)
if entry is None:
    print(f"check-seed: the seed holds no source called {key}")
    raise SystemExit(1)

body = entry.get("body") or ""
digest = entry.get("sha256") or ""
if hashlib.sha256(body.encode()).hexdigest() != digest:
    print("check-seed: the seed's own sha256 does not match its body")
    raise SystemExit(1)

# The generator writes with the platform's line endings; the fixture in the tree
# may use either. Compare the script, not the newlines.
def normalise(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")

with open(fixture_path, encoding="utf-8") as f:
    fixture = f.read()

if normalise(body) != normalise(fixture):
    print(f"check-seed: the seed's {key} body is not {fixture_path}")
    print("            rebuild it with nekophage's cmd/seedgen")
    raise SystemExit(1)

others = [e.get("key") for e in entries if isinstance(e, dict) and e.get("key") != key]
print(f"check-seed: {key} matches {fixture_path}; {len(entries)} source(s) seeded"
      + (f", others: {', '.join(sorted(k for k in others if k))}" if others else ""))
PY
