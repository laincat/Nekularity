#!/bin/sh
# Points the client at a Core revision, everywhere that records it.
#
#   scripts/set-core-pin.sh <40 hex chars>
#   scripts/set-core-pin.sh --check
#
# Four files carry the pin and they are read by different things: scripts decides
# what is built, CoreVersion.swift is what the app shows, and the two status
# documents say which revision the evidence belongs to. Updating three of them
# leaves a tree that claims one Core and links another, so this does all four and
# then proves they agree. `--check` does only the last part.
#
# What this does NOT do: fetch or build Core. Run scripts/fetch-core.sh after it.
set -eu

cd "$(dirname "$0")/.."

mode=set
pin=${1:-}
if [ "$pin" = "--check" ]; then
	mode=check
	pin=$(tr -d ' \r\n' <scripts/core-version)
fi

case "$pin" in
[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
*)
	printf 'set-core-pin: need a full 40-character revision, got %s\n' "${pin:-nothing}" >&2
	exit 2
	;;
esac

old=$(tr -d ' \r\n' <scripts/core-version)
short=$(printf '%s' "$pin" | cut -c1-8)

if [ "$mode" = set ]; then
	# python3 rather than sed -i: BSD sed wants an argument after -i and GNU sed
	# does not, and this has to run both where the app is built and where it is
	# written.
	python3 - "$pin" "$old" <<'PY'
import re
import sys

pin, old = sys.argv[1], sys.argv[2]
files = ["scripts/core-version", "Sources/NekularityKit/CoreVersion.swift",
         "docs/STATUS.md", "docs/STATUS.en.md"]
# Eight characters is only the pin where nothing hex touches it: a blind replace
# once rewrote an unrelated big integer in a document into a hash.
short = re.compile(r"(?<![0-9a-f])" + old[:8] + r"(?![0-9a-f])")
for path in files:
    try:
        data = open(path, "rb").read()
    except FileNotFoundError:
        continue
    # Bytes, not text: doing this as text would rewrite CRLF files into LF and
    # turn a one-line pin change into a whole-file diff.
    if old:
        text = data.decode("utf-8").replace(old, pin)
        text = short.sub(pin[:8], text)
        data = text.encode("utf-8")
    else:
        data = pin.encode() + b"\n"
    open(path, "wb").write(data)
PY
fi

# Every file that carried the old value must carry the new one, or the release is
# half done and nobody notices until a bug report names the wrong Core.
missing=0
for f in scripts/core-version Sources/NekularityKit/CoreVersion.swift; do
	[ -f "$f" ] || continue
	if ! grep -q "$pin" "$f"; then
		printf 'set-core-pin: %s does not mention %s\n' "$f" "$pin" >&2
		missing=1
	fi
done
for f in docs/STATUS.md docs/STATUS.en.md; do
	[ -f "$f" ] || continue
	# Standalone, so a digit run inside an unrelated number cannot pass for the pin.
	if ! grep -qE "(^|[^0-9a-f])$short([^0-9a-f]|$)" "$f"; then
		printf 'set-core-pin: %s does not mention %s\n' "$f" "$short" >&2
		missing=1
	fi
done
[ "$missing" = 0 ] || exit 1

if [ "$mode" = check ]; then
	printf 'set-core-pin: ok (%s) in every file that records it\n' "$short"
	exit 0
fi

printf 'set-core-pin: %s -> %s\n' "${old:-none}" "$pin"
printf 'set-core-pin: next, run sh scripts/fetch-core.sh\n'
