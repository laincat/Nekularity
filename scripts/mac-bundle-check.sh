#!/bin/sh
# Verifies a transferred source bundle and builds the Kit on macOS.
#
#   scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK [WORKDIR]
#
# PARTS_DIR holds the base64 segments the bundle was sent as (1.b64, 2.b64,
# 3.b64, 4a.b64, 4b.b64, 5a.b64, 5b.b64, 6.b64, 7.b64). XCFRAMEWORK is the
# VeneraCatCore.xcframework built from VeneraCat Core. WORKDIR defaults to
# /tmp/nekularity-validation.
#
# One command does the whole check, so a machine that asks for approval per
# write only asks once: every segment is checked against its md5 before
# anything is joined, the joined archive against its own md5 before anything
# is unpacked, and only then is the Kit built. Every step prints one PASS or
# FAIL line naming what it checked.
set -eu

parts=${1:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK [WORKDIR]}
xcf=${2:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK [WORKDIR]}
work=${3:-/tmp/nekularity-validation}
# clean: remove everything this script made once it has reported, including
# the unpacked tree and the joined archive. The machine is left as found.
clean=${4:-}

# The archive these segments make; `md5` is used rather than `shasum` because
# it needs no extra permission on a locked-down machine.
want_tgz_md5=690a9566742aa232016d9bee3245dfc9
want_tgz_bytes=44575
want_swift_files=24

say() { printf '%s\n' "$*"; }
pass() { say "PASS  $1"; }
fail() { say "FAIL  $1"; exit 1; }

# cleanup leaves no bundle, no unpacked tree and no log behind.
cleanup() {
	[ "$clean" = clean ] || return 0
	rm -rf "$work" "$work.b64" "$work.tgz"
	say "cleaned $work, $work.b64, $work.tgz"
}
trap cleanup EXIT

md5_of() {
	if command -v md5 >/dev/null 2>&1; then
		md5 -q "$1"
	else
		md5sum "$1" | cut -d' ' -f1
	fi
}

# name expected-md5, in the order they join.
read_segments() {
	cat <<'EOF'
1.b64 c63c42178285d21d15d82a3829ad2a3f
2.b64 433d62db82f25eb237a10e73d7647880
3.b64 10f21838eb94d40e5860651c62522615
4a.b64 263538623a0363bba5d3d9e365a37325
4b.b64 8e4bd2a729e226eb8e70b5fb606f0ca5
5a.b64 beae026d1ef95df85a5c09def37971fd
5b.b64 2c0541ea910a6edbd215840da2e0ce63
6.b64 a795b78abcd68e4246ac1323937bfe42
7.b64 4f892a38c58589fc27fd18c17df0e613
EOF
}

bad=0
read_segments | while read -r name want; do
	file=$parts/$name
	if [ ! -f "$file" ]; then
		say "missing $name"
		exit 1
	fi
	got=$(md5_of "$file")
	[ "$got" = "$want" ] || { say "mismatch $name got $got want $want"; exit 1; }
done || fail "segment md5"

joined=$work.b64
tgz=$work.tgz
mkdir -p "$(dirname "$work")"
: >"$joined"
read_segments | while read -r name _; do
	cat "$parts/$name" >>"$joined"
done
# macOS spells it -D, GNU --decode; both read stdin.
if base64 -D <"$joined" >"$tgz" 2>/dev/null; then :; else base64 --decode <"$joined" >"$tgz"; fi
pass "base64 -D $joined"

bytes=$(wc -c <"$tgz" | tr -d ' ')
[ "$bytes" = "$want_tgz_bytes" ] || fail "archive size $bytes, want $want_tgz_bytes"
got=$(md5_of "$tgz")
[ "$got" = "$want_tgz_md5" ] || fail "archive md5 $got, want $want_tgz_md5"
pass "archive md5 $got"

rm -rf "$work"
mkdir -p "$work"
tgz_abs=$(cd "$(dirname "$tgz")" && pwd)/$(basename "$tgz")
(cd "$work" && tar -xzf "$tgz_abs")
pass "tar -xzf $tgz"

count=$(find "$work" -name '*.swift' | wc -l | tr -d ' ')
[ "$count" = "$want_swift_files" ] || fail "$count .swift files, want $want_swift_files"
pass "$count .swift files"

[ -d "$xcf" ] || fail "no xcframework at $xcf"
mkdir -p "$work/Vendor"
rm -rf "$work/Vendor/VeneraCatCore.xcframework"
cp -R "$xcf" "$work/Vendor/"
pass "Vendor/VeneraCatCore.xcframework <= $xcf"

log=$work/build.log
if (cd "$work" && swift build >"$log" 2>&1); then
	pass "swift build (log $log)"
else
	say "FAIL  swift build (log $log)"
	tail -40 "$log"
	exit 1
fi
