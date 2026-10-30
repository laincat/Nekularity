#!/bin/sh
# Checks that the Core the app reports is the Core it is built against.
#
# CoreVersion.pinned is what a user sees in the app; scripts/core-version is what
# scripts/fetch-core.sh builds. Two copies of one fact, so one of them will go
# stale — this is the check that says which.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
pin=$(tr -d ' \n' < "$root/scripts/core-version")
file="$root/Sources/NekularityKit/CoreVersion.swift"

if [ ! -f "$file" ]; then
	printf 'check-core-pin: %s is missing\n' "$file" >&2
	exit 2
fi

shown=$(sed -n 's/.*static let pinned = "\([0-9a-f]*\)".*/\1/p' "$file" | head -n 1)
if [ -z "$shown" ]; then
	printf 'check-core-pin: no `static let pinned = "<sha>"` in %s\n' "$file" >&2
	exit 2
fi

if [ "$shown" != "$pin" ]; then
	printf 'check-core-pin: the app reports %s but scripts/core-version builds %s\n' \
		"$shown" "$pin" >&2
	printf 'check-core-pin: update Sources/NekularityKit/CoreVersion.swift\n' >&2
	exit 1
fi

printf 'check-core-pin: ok (%s)\n' "$(printf '%s' "$pin" | cut -c1-12)"
