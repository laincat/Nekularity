#!/bin/sh
# Checks the Core surface without a Mac.
#
# `check-core-surface.sh` reads the header out of the built xcframework, which
# only exists on macOS. But the header is produced by gobind, which runs
# anywhere Go runs, so the same check can be made on Windows before a bundle is
# ever transferred — which is where a mismatch is cheap to fix.
#
#   scripts/check-surface-offline.sh [CORE_DIR] [WORKDIR]
#
# CORE_DIR defaults to ../VeneraCat\ Core and WORKDIR to a temporary directory.
set -eu

core=${1:-../VeneraCat\ Core}
work=${2:-}

here=$(cd "$(dirname "$0")/.." && pwd)
out=${work:-$(mktemp -d)}
mkdir -p "$out/gobind"

if [ ! -d "$core/mobile" ]; then
	printf 'check-surface-offline: no mobile package under %s\n' "$core" >&2
	printf 'check-surface-offline: pass the Core checkout as the first argument\n' >&2
	exit 2
fi

( cd "$core" && go run golang.org/x/mobile/cmd/gobind -lang=objc -outdir "$out/gobind" ./mobile ) || {
	printf 'check-surface-offline: gobind failed\n' >&2
	exit 1
}

header="$out/gobind/src/gobind/Mobile.objc.h"
if [ ! -f "$header" ]; then
	printf 'check-surface-offline: gobind produced no header\n' >&2
	exit 1
fi

# Put it where the real check looks, so both run the same selector list.
fake="$out/fw/ios-arm64/VeneraCatCore.framework/Headers"
mkdir -p "$fake"
cp "$header" "$fake/Mobile.objc.h"

"$here/scripts/check-core-surface.sh" "$out/fw"
