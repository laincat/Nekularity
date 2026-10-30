#!/bin/sh
# Produces a patch from an older copy of the tree to the current one, and proves
# the patch reaches the current bytes before anyone sends it.
#
#   scripts/make-patch.sh BASE_DIR OUTDIR FILE [FILE ...]
#
# BASE_DIR holds the files as the other machine has them (for example, what was
# unpacked from a bundle that machine received). OUTDIR gets `fix.patch` and a
# report: the md5 the receiver should end up with, plus the md5 this script got
# by applying the patch to a scratch copy.
#
# The point is the dry run. A patch described in prose ("delete these two
# comments, keep one blank line") cannot be checked; a patch that has been
# applied here and produced the right md5 can.
set -eu

if [ $# -lt 3 ]; then
	printf 'usage: scripts/make-patch.sh BASE_DIR OUTDIR FILE [FILE ...]\n' >&2
	exit 2
fi

base=$1
out=$2
shift 2

here=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$out"
rm -f "$out/fix.patch" "$out/verify.txt"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

: > "$out/fix.patch"
for f in "$@"; do
	if [ ! -f "$base/$f" ]; then
		printf 'make-patch: %s is not in %s\n' "$f" "$base" >&2
		exit 1
	fi
	if [ ! -f "$here/$f" ]; then
		printf 'make-patch: %s is not in this tree\n' "$f" >&2
		exit 1
	fi
	mkdir -p "$work/tree/$(dirname "$f")"
	cp "$base/$f" "$work/tree/$f"
	diff -u "$base/$f" "$here/$f" | sed "1s|.*|--- $f|;2s|.*|+++ $f|" >> "$out/fix.patch" || true
done

if [ ! -s "$out/fix.patch" ]; then
	printf 'make-patch: nothing differs\n' >&2
	exit 0
fi

# Apply the patch to the scratch copy and compare with the real file. The patch
# names its own files, so it is applied once: passing a filename would make it try
# every hunk against that one file and fail on the hunks for the others.
( cd "$work/tree" && patch -p0 --quiet < "$out/fix.patch" ) || {
	printf 'make-patch: the patch does not apply to the scratch copy\n' >&2
	exit 1
}
for f in "$@"; do
	want=$(md5sum "$here/$f" | cut -d' ' -f1)
	got=$(md5sum "$work/tree/$f" | cut -d' ' -f1)
	{
		printf '%s  expected %s\n' "$want" "$f"
		if [ "$want" = "$got" ]; then
			printf '        patched  %s  ok\n' "$got"
		else
			printf '        patched  %s  MISMATCH\n' "$got"
		fi
	} | tee -a "$out/verify.txt"
	if [ "$want" != "$got" ]; then
		printf 'make-patch: applying this patch does not reproduce the file\n' >&2
		exit 1
	fi
done

printf '\npatch %s/fix.patch (%s lines), verified above\n' "$out" "$(wc -l < "$out/fix.patch" | tr -d ' ')"
