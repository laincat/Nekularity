#!/bin/sh
# Splits one base64 segment in half and prints both halves with their md5s.
#
#   scripts/split-part.sh parts/02
#
# A segment that arrives with the right length but the wrong md5 has been
# rewritten in transit. Resending it whole tends to fail the same way; two
# shorter halves usually survive, and each half can be checked on its own
# before the pair is joined.
set -eu

file=${1:?usage: split-part.sh PARTS_FILE}
size=$(wc -c <"$file" | tr -d ' ')
if [ "$size" -lt 4 ]; then
	printf 'split-part: %s is only %s bytes\n' "$file" "$size" >&2
	exit 2
fi
half=$((size / 2))
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
head -c "$half" "$file" >"$tmp/a"
tail -c "$((size - half))" "$file" >"$tmp/b"

md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1"; }

printf 'whole   %s bytes  md5 %s\n' "$size" "$(md5 "$file")"
printf 'half A  %s bytes  md5 %s\n' "$half" "$(md5 "$tmp/a")"
printf 'half B  %s bytes  md5 %s\n' "$((size - half))" "$(md5 "$tmp/b")"
printf '\n--- A ---\n'; cat "$tmp/a"; printf '\n--- B ---\n'; cat "$tmp/b"; printf '\n'
