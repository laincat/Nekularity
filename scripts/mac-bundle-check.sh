#!/bin/sh
# Verifies a transferred source bundle, then type checks the client on macOS.
#
#   scripts/mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES \
#       SWIFT_FILES [WORKDIR] [clean]
#
# PARTS_DIR holds the base64 segments the bundle was sent as, one file per
# segment; they are joined in the order `sort` gives, so either 01.b64, 02.b64,
# ... or the seg01.txt names scripts/make-payload.sh writes will do.
# XCFRAMEWORK is a VeneraCatCore.xcframework built from VeneraCat
# Core. WORKDIR defaults to /tmp/nekularity-validation. Pass `clean` as the
# last argument to remove everything this script made once it has reported.
#
# One command does the whole check, so a machine that asks for approval per
# write only asks once: every segment is joined, the archive is checked
# against its own md5 and size before anything is unpacked, the unpacked tree
# is checked for the expected number of Swift files, and only then are the Kit
# and the App type checked. Every step prints one PASS or FAIL line naming
# what it checked.
#
# The type checks run in Swift 6 language mode, because that is what
# Package.swift and project.yml build with: a Swift 5 type check would accept
# code the real build rejects.
set -eu

parts=${1:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]}
xcf=${2:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]}
want_tgz_md5=${3:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]}
want_tgz_bytes=${4:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]}
want_swift_files=${5:?usage: mac-bundle-check.sh PARTS_DIR XCFRAMEWORK TGZ_MD5 TGZ_BYTES SWIFT_FILES [WORKDIR] [clean]}
work=${6:-/tmp/nekularity-validation}
clean=${7:-}
ios_target=${IOS_TARGET:-arm64-apple-ios26.0}

# `md5` is used rather than `shasum` because it needs no extra tooling.
say() { printf '%s\n' "$*"; }
pass() { say "PASS  $1"; }
fail() { say "FAIL  $1"; exit 1; }

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

parts_abs=$(cd "$parts" && pwd)
# Segments are named 01.b64 by older scripts and seg01.txt by
# scripts/make-payload.sh; both sort into the right order.
# Only the segment files: make-payload.sh also leaves the joined p.b64 beside
# them, and joining that as well would decode a file twice.
segments=$(cd "$parts_abs" && ls [0-9][0-9].b64 seg[0-9][0-9].txt 2>/dev/null | sort)
[ -n "$segments" ] || fail "no NN.b64 or segNN.txt segments in $parts_abs"

mkdir -p "$(dirname "$work")"
joined=$work.b64
tgz=$work.tgz
: >"$joined"
for name in $segments; do
	cat "$parts_abs/$name" >>"$joined"
done
pass "joined $(printf '%s\n' $segments | wc -l | tr -d ' ') segments from $parts_abs"

# macOS spells it -D, GNU --decode; both read stdin.
if base64 -D <"$joined" >"$tgz" 2>/dev/null; then :; else base64 --decode <"$joined" >"$tgz"; fi
pass "base64 decode"

bytes=$(wc -c <"$tgz" | tr -d ' ')
[ "$bytes" = "$want_tgz_bytes" ] || fail "archive size $bytes, want $want_tgz_bytes"
got=$(md5_of "$tgz")
[ "$got" = "$want_tgz_md5" ] || fail "archive md5 $got, want $want_tgz_md5"
pass "archive md5 $got ($bytes bytes)"

rm -rf "$work"
mkdir -p "$work"
tgz_abs=$(cd "$(dirname "$tgz")" && pwd)/$(basename "$tgz")
(cd "$work" && tar -xzf "$tgz_abs")
# tar can restore directories without a write bit, which makes later steps fail
# with a confusing file count.
chmod -R u+rwX "$work"
count=$(find "$work" -name '*.swift' | wc -l | tr -d ' ')
[ "$count" = "$want_swift_files" ] || fail "$count .swift files, want $want_swift_files"
pass "unpacked $count .swift files"

[ -d "$xcf" ] || fail "no xcframework at $xcf"
mkdir -p "$work/Vendor"
rm -rf "$work/Vendor/VeneraCatCore.xcframework"
cp -R "$xcf" "$work/Vendor/"
pass "Vendor/VeneraCatCore.xcframework <= $xcf"

# 0. The framework must expose what this client calls; a stale one fails later,
#    inside a Swift compile, as if a method name were wrong.
log=$work/core-surface.log
if (cd "$work" && sh scripts/check-core-surface.sh >"$log" 2>&1); then
	pass "sh scripts/check-core-surface.sh" "$log"
else
	fail "sh scripts/check-core-surface.sh" "$log"
fi

# 1. The Kit builds for macOS in Swift 6 mode, which also builds the tests'
#    dependencies and so type checks everything Sources/ declares.
log=$work/kit-build.log
if (cd "$work" && swift build >"$log" 2>&1); then
	pass "swift build (Kit, macOS): $(grep -c ' error: ' "$log" 2>/dev/null || true) errors"
else
	say "FAIL  swift build (Kit, macOS), log $log"
	grep ' error: ' "$log" | head -20 || tail -40 "$log"
	exit 1
fi

# 1b. The Kit's unit tests run against the real xcframework, so a wrong Core
#     binding shows up here rather than on a device. Run in one script with the
#     other steps because each approval on this machine costs a round trip.
log=$work/kit-test.log
if (cd "$work" && swift test >"$log" 2>&1); then
	pass "swift test (Kit, macOS): $(grep -c "Test run with" "$log" 2>/dev/null || true) run, $(grep -c ' error: ' "$log" 2>/dev/null || true) errors"
else
	say "FAIL  swift test (Kit, macOS), log $log"
	grep ' error: ' "$log" | head -20 || tail -40 "$log"
	exit 1
fi

# 2. The Kit emits an iOS module: this is the shape the App compiles against.
#    -F must point at the xcframework's slice directory, not at the
#    xcframework itself: a module built for iOS is not found in Vendor/ alone.
sdk=$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null) || fail "no iphoneos SDK"
slice=$work/Vendor/VeneraCatCore.xcframework/ios-arm64
[ -d "$slice" ] || fail "no ios-arm64 slice under $work/Vendor"
log=$work/kit-ios.log
if (cd "$work" && swiftc -emit-module -parse-as-library -swift-version 6 \
	-sdk "$sdk" -target "$ios_target" -F "$slice" \
	-module-name NekularityKit -emit-module-path "$work/Vendor/NekularityKit.swiftmodule" \
	$(find Sources/NekularityKit -name '*.swift' | sort) >"$log" 2>&1); then
	pass "swiftc -emit-module (Kit, iOS)"
else
	say "FAIL  swiftc -emit-module (Kit, iOS), log $log"
	grep ' error: ' "$log" | head -20 || tail -40 "$log"
	exit 1
fi

# 3. The App type checks against that module, also in Swift 6 mode.
log=$work/app-typecheck.log
if swiftc -typecheck -swift-version 6 -sdk "$sdk" -target "$ios_target" \
	-I "$work/Vendor" -F "$slice" App/*.swift >"$log" 2>&1; then
	errors=$(grep -c ' error: ' "$log" 2>/dev/null || true)
	warnings=$(grep -c ' warning: ' "$log" 2>/dev/null || true)
	pass "swiftc -typecheck (App, iOS): ${errors:-0} errors, ${warnings:-0} warnings"
else
	say "FAIL  swiftc -typecheck (App, iOS), log $log"
	say "errors: $(grep -c ' error: ' "$log" || true) warnings: $(grep -c ' warning: ' "$log" || true)"
	grep ' error: ' "$log" | head -20
	exit 1
fi

say "all checks passed"
