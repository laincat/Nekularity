#!/bin/sh
# Checks Nekularity on a machine with Xcode: syntax, unit tests, and a build
# of the SwiftUI app for iOS.
#
#   scripts/verify-ios.sh [path-to-VeneraCatCore.xcframework]
#
# The xcframework goes to Vendor/ first (scripts/fetch-core.sh does that on a
# machine with Go). Every step writes a log under build/verify/ and prints one
# PASS/FAIL line naming the command, so a failure says where it stopped.
#
# XcodeGen is not required: when it is missing the app sources are type
# checked with swiftc against the iOS SDK and the Kit built for iOS, which
# catches the Swift errors a Mac-less editor cannot.
set -eu

cd "$(dirname "$0")/.."
out=build/verify
mkdir -p "$out"

say() { printf '%s\n' "$*"; }
pass() { say "PASS  $1  ($2)"; }
fail() { say "FAIL  $1  ($2)"; say "      see $2"; exit 1; }

if [ $# -ge 1 ]; then
	if [ ! -d "$1" ]; then
		say "no such xcframework: $1"
		exit 2
	fi
	mkdir -p Vendor
	rm -rf Vendor/VeneraCatCore.xcframework
	cp -R "$1" Vendor/
	say "Vendor/VeneraCatCore.xcframework <= $1"
fi
if [ ! -d Vendor/VeneraCatCore.xcframework ]; then
	say "Vendor/VeneraCatCore.xcframework is missing; pass its path or run scripts/fetch-core.sh"
	exit 2
fi

# 0. The framework in Vendor/ must expose what this client calls: a stale one
#    fails later, inside a Swift compile, with an error that reads like a typo.
if sh scripts/check-core-surface.sh >"$out/core-surface.log" 2>&1; then
	pass "sh scripts/check-core-surface.sh" "$out/core-surface.log"
else
	fail "sh scripts/check-core-surface.sh" "$out/core-surface.log"
fi

# 1. Documentation pairs and root cleanliness.
if sh scripts/check-docs.sh >"$out/docs.log" 2>&1; then
	pass "sh scripts/check-docs.sh" "$out/docs.log"
else
	fail "sh scripts/check-docs.sh" "$out/docs.log"
fi

# 2. Swift syntax, which needs no macOS at all.
if python3 scripts/check-swift.py >"$out/syntax.log" 2>&1; then
	pass "python3 scripts/check-swift.py" "$out/syntax.log"
else
	fail "python3 scripts/check-swift.py" "$out/syntax.log"
fi

# 3. The Kit's unit tests. They exercise Core through the real xcframework.
if swift test >"$out/swift-test.log" 2>&1; then
	pass "swift test" "$out/swift-test.log"
else
	fail "swift test" "$out/swift-test.log"
fi

sdk=$(xcrun --sdk iphoneos --show-sdk-path)

if command -v xcodegen >/dev/null 2>&1; then
	# 4a. A real app build, which is what ships.
	if xcodegen generate >"$out/xcodegen.log" 2>&1; then
		pass "xcodegen generate" "$out/xcodegen.log"
	else
		fail "xcodegen generate" "$out/xcodegen.log"
	fi
	if xcodebuild -project Nekularity.xcodeproj -scheme Nekularity \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath "$out/dd" build >"$out/app-build.log" 2>&1; then
		pass "xcodebuild ... build (iOS, no signing)" "$out/app-build.log"
	else
		fail "xcodebuild ... build (iOS, no signing)" "$out/app-build.log"
	fi
	exit 0
fi

# 4b. No XcodeGen: build the Kit for iOS, then type check the screens against
# it. SwiftPM names its scheme "<Package>-Package" when the package has no
# product.
scheme=$(xcodebuild -list -json 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("NekularityKit")
    raise SystemExit
s = (d.get("workspace") or d.get("project") or {}).get("schemes", [])
print(next((x for x in s if x.endswith("-Package")), s[0] if s else "NekularityKit"))
')
if xcodebuild -scheme "$scheme" -destination 'generic/platform=iOS' -sdk iphoneos \
	CODE_SIGNING_ALLOWED=NO -derivedDataPath "$out/dd" build \
	>"$out/kit-ios.log" 2>&1; then
	pass "xcodebuild -scheme $scheme (iOS)" "$out/kit-ios.log"
else
	fail "xcodebuild -scheme $scheme (iOS)" "$out/kit-ios.log"
fi

modules="$out/dd/Build/Products/Debug-iphoneos"
if [ ! -d "$modules" ]; then
	modules=$(find "$out/dd/Build/Products" -maxdepth 1 -type d -name '*iphoneos' | head -1)
fi
if [ -z "${modules:-}" ] || [ ! -d "$modules" ]; then
	say "could not find the built modules under $out/dd/Build/Products"
	exit 2
fi

# A type check needs every source at once, so they are handed to swiftc in
# one call. -swift-version 6 matches what Package.swift and project.yml build
# with: Swift 5 mode would accept code the real build rejects.
if swiftc -typecheck -swift-version 6 -sdk "$sdk" -target arm64-apple-ios26.0 \
	-I "$modules" -F "$modules" App/*.swift >"$out/app-typecheck.log" 2>&1; then
	pass "swiftc -typecheck App/*.swift (iOS)" "$out/app-typecheck.log"
else
	fail "swiftc -typecheck App/*.swift (iOS)" "$out/app-typecheck.log"
fi

say "note  XcodeGen is not installed, so no app bundle was built; the screens were type checked only"
