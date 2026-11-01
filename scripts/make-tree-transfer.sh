#!/bin/sh
# Packs this repository as a git bundle and prints a message that can be pasted
# into the verification machine, with every hash read from the files.
#
#   scripts/make-tree-transfer.sh OUTDIR [/path/to/seed.json]
#
# Why this exists next to make-transfer.sh: that one ships the files it is *given*,
# so `make-transfer.sh OUT /tmp/seed.json` sends a seed and nothing else. That
# happened — the receiving machine spent a round looking for a tree that was never
# in the archive. This script always ships the whole repository, checks its own
# output by cloning the bundle it just built, and uploads the seed as well: a local
# path in the message is useless to the other machine, and a round was lost to a
# message that named a seed and its md5 and nothing the receiver could fetch.
#
# GH_CREATE_GIST=1 (the default) uploads p.b64 and, when given, the seed.
set -eu

out=${1:-}
seed=${2:-}
if [ -z "$out" ]; then
	printf 'usage: scripts/make-tree-transfer.sh OUTDIR [/path/to/seed.json]\n' >&2
	exit 2
fi

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

md5_of() {
	if command -v md5sum >/dev/null 2>&1; then
		md5sum "$1" | cut -d' ' -f1
	else
		md5 -q "$1"
	fi
}

upload() {
	# upload FILE FILENAME DESCRIPTION -> prints the raw URL, or nothing
	b64file=$1
	name=$2
	desc=$3
	url=$(gh gist create "$b64file" --desc "$desc" --filename "$name" 2>/dev/null | tr -d '\r' | tail -1)
	if [ -z "$url" ]; then
		return 0
	fi
	gh api "gists/$(basename "$url")" --jq ".files[\"$name\"].raw_url" 2>/dev/null || true
}

head=$(git rev-parse HEAD)
if [ -n "$(git status --porcelain)" ]; then
	printf 'make-tree-transfer: the working tree is dirty; the bundle would not match HEAD\n' >&2
	exit 1
fi

mkdir -p "$out"
bundle=$out/tree.bundle
gz=$out/tree.tgz
b64=$out/tree.b64
rm -f "$bundle" "$gz" "$b64"

git bundle create "$bundle" --all >/dev/null 2>&1
gzip -c "$bundle" >"$gz"
base64 <"$gz" | tr -d '\n' >"$b64"

# Self-check: a round was lost to an archive that did not hold what the message
# promised, so the promise is verified here instead of by the receiver.
check=$(mktemp -d)
trap 'rm -rf "$check"' EXIT
git clone -q "$bundle" "$check/tree" 2>/dev/null
cloned=$(git -C "$check/tree" rev-parse HEAD 2>/dev/null || echo none)
if [ "$cloned" != "$head" ]; then
	printf 'make-tree-transfer: the bundle clones to %s, not %s\n' "$cloned" "$head" >&2
	exit 1
fi
files=$(git -C "$check/tree" ls-files | wc -l | tr -d ' ')

bundle_md5=$(md5_of "$bundle")
gz_md5=$(md5_of "$gz")
b64_md5=$(md5_of "$b64")

seed_gz=""
seed_b64=""
if [ -n "$seed" ]; then
	if [ ! -f "$seed" ]; then
		printf 'make-tree-transfer: no such seed: %s\n' "$seed" >&2
		exit 1
	fi
	seed_gz=$out/seed.tgz
	seed_b64=$out/seed.b64
	gzip -c "$seed" >"$seed_gz"
	base64 <"$seed_gz" | tr -d '\n' >"$seed_b64"
fi

printf 'tree %s (%s files)\n' "$head" "$files"
printf 'bundle %s bytes md5 %s\n' "$(wc -c <"$bundle" | tr -d ' ')" "$bundle_md5"
printf 'base64 %s bytes md5 %s\n' "$(wc -c <"$b64" | tr -d ' ')" "$b64_md5"
if [ -n "$seed" ]; then
	printf 'seed %s bytes md5 %s\n' "$(wc -c <"$seed" | tr -d ' ')" "$(md5_of "$seed")"
	printf 'seed base64 %s bytes md5 %s\n' "$(wc -c <"$seed_b64" | tr -d ' ')" "$(md5_of "$seed_b64")"
fi

printf '\n--- message to send ---\n\n'
printf '```sh\n'

if [ "${GH_CREATE_GIST:-1}" = "1" ] && command -v gh >/dev/null 2>&1; then
	tree_raw=$(upload "$b64" tree.b64 "Nekularity tree $head")
	seed_raw=""
	if [ -n "$seed" ]; then
		seed_raw=$(upload "$seed_b64" seed.b64 "Nekularity seed $head")
	fi
else
	tree_raw=""
	seed_raw=""
fi

if [ -n "$tree_raw" ]; then
	printf "curl -fsSL '%s' -o tree.b64\n" "$tree_raw"
else
	printf 'curl -fsSL <gist raw url> -o tree.b64\n'
fi
printf 'md5 tree.b64        # %s\n' "$b64_md5"
printf 'base64 --decode -i tree.b64 -o tree.tgz\n'
printf 'md5 tree.tgz        # %s\n' "$gz_md5"
printf 'gunzip -c tree.tgz > tree.bundle\n'
printf 'md5 tree.bundle     # %s\n' "$bundle_md5"
printf 'git clone tree.bundle src-tree\n'
printf 'cd src-tree && git log --oneline -1   # %s\n' "$head"

if [ -n "$seed" ]; then
	if [ -n "$seed_raw" ]; then
		printf "curl -fsSL '%s' -o seed.b64\n" "$seed_raw"
	else
		printf 'curl -fsSL <seed gist raw url> -o seed.b64\n'
	fi
	printf 'md5 seed.b64        # %s\n' "$(md5_of "$seed_b64")"
	printf 'base64 --decode -i seed.b64 -o seed.tgz\n'
	printf 'md5 seed.tgz        # %s\n' "$(md5_of "$seed_gz")"
	printf 'gunzip -c seed.tgz > /tmp/seed.json\n'
	printf 'md5 /tmp/seed.json  # %s\n' "$(md5_of "$seed")"
	printf 'sh scripts/check-seed.sh /tmp/seed.json\n'
fi

printf '```\n'
