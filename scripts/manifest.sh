#!/bin/sh
# Prints "md5  path" for every source and test file, sorted, so two trees can be
# diffed file by file.
#
#   scripts/manifest.sh > mine.txt
#   diff mine.txt theirs.txt
#
# Twice a delta was assembled from a commit's diffstat and shipped a tree that
# was missing files nobody had listed. A manifest answers "what is different"
# instead of "what did I think changed".
set -eu

cd "$(dirname "$0")/.."

md5() { md5sum "$1" 2>/dev/null | cut -d' ' -f1 || md5 -q "$1"; }

{
	find Sources App Tests -name '*.swift' 2>/dev/null
	[ -f Package.swift ] && echo Package.swift
	find scripts -type f 2>/dev/null
	find docs -name '*.md' 2>/dev/null
} | sed 's|^\./||' | sort | while read -r f; do
	[ -f "$f" ] || continue
	printf '%s  %s\n' "$(md5 "$f")" "$f"
done
