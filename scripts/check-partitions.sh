#!/bin/sh
# Cookie partitions are named in one place.
#
#   sh scripts/check-partitions.sh
#
# A restore once wrote cookies under the bare source key while every request reads
# "comic:<key>", so the cookies were stored where nothing would ever send them —
# and the tests passed, because they were written from the same wrong assumption.
# The name now lives in `CookiePartition`; this check refuses a second spelling.
set -eu

cd "$(dirname "$0")/.."

allowed='Sources/NekularityKit/Platform/CookieJars.swift'

# Test files may spell the prefix when they are pinning that it is NOT used raw;
# sources and app code may not.
hits=$(grep -rn '"comic:' Sources App --include='*.swift' | grep -v "^$allowed:" || true)
if [ -n "$hits" ]; then
	printf 'check-partitions: the partition prefix is written outside CookiePartition:\n%s\n' "$hits" >&2
	exit 1
fi

# The helper has to be the one that spells it, or this check protects nothing.
if ! grep -q '"comic:" + key' "$allowed"; then
	printf 'check-partitions: CookiePartition.comic no longer builds "comic:<key>"\n' >&2
	exit 1
fi

printf 'check-partitions: ok\n'
