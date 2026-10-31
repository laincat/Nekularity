#!/bin/sh
# Prints the message to send after a Core pin change, with the md5s read from
# the files.
#
#   scripts/make-pin-message.sh
#
# The pin lives in four places — scripts/core-version, CoreVersion.swift and both
# STATUS pages — and the receiving machine checks hashes. Typing those by hand is
# how a `?` or a stale value ends up in the message (three times so far). This
# prints the block; nothing in it is copied by eye.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

pin=$(tr -d ' \n' < scripts/core-version)
md5_of() {
	if command -v md5sum >/dev/null 2>&1; then
		md5sum "$1" | cut -d' ' -f1
	else
		md5 -q "$1"
	fi
}

printf '```sh\n'
printf 'cd /tmp/nk/src\n'
printf "grep -rq '%s' scripts/core-version Sources/NekularityKit/CoreVersion.swift || echo 'pin files not updated yet'\n" "$pin"
printf 'sh scripts/check-core-pin.sh    # expect ok (%s)\n' "$(printf '%s' "$pin" | cut -c1-12)"
printf 'sh scripts/fetch-core.sh\n'
printf 'sh scripts/verify-ios.sh        # expect EXIT=0\n'
printf 'sh scripts/check-tree.sh\n'
printf '```\n\n'
printf 'md5 of the two pin files, as they are here now:\n\n'
printf '```\n'
printf '%-44s %s\n' "scripts/core-version" "$(md5_of scripts/core-version)"
printf '%-44s %s\n' "Sources/NekularityKit/CoreVersion.swift" "$(md5_of Sources/NekularityKit/CoreVersion.swift)"
printf '```\n'
