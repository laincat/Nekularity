#!/bin/sh
# Parses every Swift file; see scripts/check-swift.py for what it does and
# does not check.
set -e
cd "$(dirname "$0")/.."
exec python3 scripts/check-swift.py "$@"
