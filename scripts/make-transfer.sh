#!/bin/sh
# Prepares a transfer package and prints the whole message to send, with every
# md5 filled in from the files themselves.
#
#   scripts/make-transfer.sh OUTDIR FILE...
#
# Why: three times in one day a hand-typed md5 in a message was wrong — a stale
# value, or a placeholder left where a hash should be. The receiving machine is
# told to stop when a hash disagrees, so a wrong hash in the message turns into a
# wasted round trip at best and a "fixed" tree at worst. This prints nothing that
# was not read from a file.
#
# The gist is created only when `gh` is available and GH_CREATE_GIST=1; otherwise
# the block stops after the md5 table and the upload is left to the caller.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

if [ $# -lt 2 ]; then
	printf 'usage: scripts/make-transfer.sh OUTDIR FILE...\n' >&2
	exit 2
fi

out=$1
shift

payload=$(sh scripts/make-payload.sh "$out" "$@")
printf '%s\n' "$payload" | sed -n '1,2p'

archive_md5=$(printf '%s\n' "$payload" | sed -n 's/^archive .* md5 \([0-9a-f]*\)$/\1/p')
if [ -z "$archive_md5" ]; then
	printf 'make-transfer: could not read the archive md5 from make-payload.sh\n' >&2
	exit 1
fi

b64_md5=$(md5sum "$out/p.b64" 2>/dev/null | cut -d' ' -f1 || mdg="$out/p.b64")
if [ -z "$b64_md5" ]; then
	b64_md5=$(openssl dgst -md5 -r "$out/p.b64" | cut -d' ' -f1)
fi

printf '\n--- message to send ---\n\n'
printf '```sh\n'
printf 'cd /tmp/nk\n'
if [ "${GH_CREATE_GIST:-0}" = "1" ] && command -v gh >/dev/null 2>&1; then
	url=$(gh gist create "$out/p.b64" --desc "Nekularity transfer" --filename p.b64 2>/dev/null | tr -d '\r' | tail -1)
	# The file name contains a dot, so the jq path has to be subscripted;
	# `.files.p.b64` would look for nested objects and quietly return nothing.
	raw=$(gh api "gists/$(basename "$url")" --jq '.files["p.b64"].raw_url' 2>/dev/null || true)
	if [ -n "$raw" ]; then
		printf "curl -fsSL '%s' -o p.b64\n" "$raw"
	else
		printf 'make-transfer: created %s but could not read its raw url\n' "$url" >&2
	fi
else
	printf 'curl -fsSL <gist raw url> -o p.b64\n'
fi
printf 'md5 p.b64        # %s\n' "$b64_md5"
printf 'base64 -D -i p.b64 -o p.tar.gz\n'
printf 'md5 p.tar.gz     # %s\n' "$archive_md5"
printf 'cd src && tar -xzf ../p.tar.gz && chmod -R u+rwX .\n'
printf '%s\n' "$payload" | sed -n '/^[0-9a-f]\{32\}  /p' |
	sed 's/^\([0-9a-f]\{32\}\)  \(.*\)$/md5 \2   # \1/'
printf '```\n'
