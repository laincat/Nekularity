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
# Without a framework the checks that do not need one still run: the surface can be
# read from a freshly generated header, and the parser and the documentation need
# nothing. Step 3 is where a framework becomes necessary, and that is where this
# stops if it is missing.
have_framework=0
if [ -d Vendor/VeneraCatCore.xcframework ]; then
	have_framework=1
else
	say "note: no Vendor/VeneraCatCore.xcframework; the steps that link Core will stop"
fi

# 0. The framework in Vendor/ must expose what this client calls: a stale one
#    fails later, inside a Swift compile, with an error that reads like a typo.
#    Without Vendor/ there is still a Core to check: the header comes from gobind,
#    which runs wherever Go does, so the same selector list is checked against a
#    freshly generated header instead of a framework that is not there yet.
if [ -d Vendor/VeneraCatCore.xcframework ]; then
	if sh scripts/check-core-surface.sh >"$out/core-surface.log" 2>&1; then
		pass "sh scripts/check-core-surface.sh" "$out/core-surface.log"
	else
		fail "sh scripts/check-core-surface.sh" "$out/core-surface.log"
	fi
elif command -v go >/dev/null 2>&1; then
	if sh scripts/check-surface-offline.sh >"$out/core-surface.log" 2>&1; then
		pass "sh scripts/check-surface-offline.sh (no Vendor/)" "$out/core-surface.log"
	else
		fail "sh scripts/check-surface-offline.sh (no Vendor/)" "$out/core-surface.log"
	fi
else
	say "SKIP  surface check: no Vendor/VeneraCatCore.xcframework and no go"
fi

# 0b. The Core the app reports must be the Core it is built against.
if sh scripts/check-core-pin.sh >"$out/core-pin.log" 2>&1; then
	pass "sh scripts/check-core-pin.sh" "$out/core-pin.log"
else
	fail "sh scripts/check-core-pin.sh" "$out/core-pin.log"
fi

# 0c. ATS: does the plist carry the policy, and can this machine prove it reaches
# the app? Without XcodeGen it says SKIP, which is not a failure.
if sh scripts/verify-ats.sh >"$out/ats.log" 2>&1; then
	if grep -q 'SKIP' "$out/ats.log"; then
		say "SKIP  sh scripts/verify-ats.sh  (no XcodeGen here; plist contents checked)"
	else
		pass "sh scripts/verify-ats.sh" "$out/ats.log"
	fi
else
	fail "sh scripts/verify-ats.sh" "$out/ats.log"
fi

# 0d. One spelling of a cookie partition name.
if sh scripts/check-partitions.sh >"$out/partitions.log" 2>&1; then
	pass "sh scripts/check-partitions.sh" "$out/partitions.log"
else
	fail "sh scripts/check-partitions.sh" "$out/partitions.log"
fi

# 0b. Every capability a source declares still has a path in the client.
if sh scripts/check-capabilities.sh >"$out/capabilities.log" 2>&1; then
	pass "sh scripts/check-capabilities.sh" "$out/capabilities.log"
else
	fail "sh scripts/check-capabilities.sh" "$out/capabilities.log"
fi

# 0c. Every Core method the kit calls still exists. Names only, not signatures:
# this is what can be checked before the compiler runs, and it catches a call to
# a method that was never added or was renamed.
python3 scripts/check-kit-core-calls.py >"$out/core-calls.log" 2>&1 && calls=$? || calls=$?
if [ "$calls" -eq 0 ]; then
	pass "python3 scripts/check-kit-core-calls.py" "$out/core-calls.log"
elif [ "$calls" -eq 3 ]; then
	# No Core checkout on this machine: the step after this one builds one from
	# the pin, and a real mismatch then fails the compile instead.
	say "SKIP  python3 scripts/check-kit-core-calls.py  (no Core checkout; see $out/core-calls.log)"
else
	fail "python3 scripts/check-kit-core-calls.py" "$out/core-calls.log"
fi

# 0d. The JSON keys the kit decodes are keys Core actually sends. A field that is
# always nil shows up as a screen with less on it than it should have, and
# nothing else reports it.
python3 scripts/check-json-keys.py >"$out/json-keys.log" 2>&1 && jsonkeys=$? || jsonkeys=$?
if [ "$jsonkeys" -eq 0 ]; then
	pass "python3 scripts/check-json-keys.py" "$out/json-keys.log"
elif [ "$jsonkeys" -eq 2 ]; then
	say "SKIP  python3 scripts/check-json-keys.py  (no Core checkout; see $out/json-keys.log)"
else
	fail "python3 scripts/check-json-keys.py" "$out/json-keys.log"
fi

# 1. Documentation pairs and root cleanliness.
if sh scripts/check-docs.sh >"$out/docs.log" 2>&1; then
	pass "sh scripts/check-docs.sh" "$out/docs.log"
else
	fail "sh scripts/check-docs.sh" "$out/docs.log"
fi

# 2. Swift syntax, which needs no macOS at all.
python3 scripts/check-swift.py >"$out/syntax.log" 2>&1 && syntax=$? || syntax=$?
if [ "$syntax" -eq 0 ]; then
	# Without a parser the rules still ran and found nothing; saying only "PASS"
	# would hide that the files were not parsed on this machine.
	if grep -q 'the rule checks still run' "$out/syntax.log" 2>/dev/null; then
		pass "python3 scripts/check-swift.py (rules only: no parser here)" "$out/syntax.log"
	else
		pass "python3 scripts/check-swift.py" "$out/syntax.log"
	fi
elif [ "$syntax" -eq 2 ] || [ "$syntax" -eq 3 ]; then
	# 2: tree-sitter is not installed. 3: it is installed but cannot load this
	# machine's grammar version. Both are limits of the machine, not of the tree, and
	# the steps after this one compile with the real Swift compiler anyway. A
	# developer machine still gets a hard failure from scripts/check-swift.sh.
	say "SKIP  python3 scripts/check-swift.py  (parser unavailable here; see $out/syntax.log)"
else
	fail "python3 scripts/check-swift.py" "$out/syntax.log"
fi

# 3. The Kit's unit tests. They exercise Core through the real xcframework.
if [ "$have_framework" -eq 0 ]; then
	say "FAIL  swift build  (no xcframework)"
	say "      run scripts/fetch-core.sh, or pass the framework as the first argument"
	exit 1
fi
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
else

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
fi

# 6. The interface itself, when a simulator is available.
#
# The Windows machine cannot draw a window, so "the button works" was checked by
# hand on the Mac until these tests existed. The app has to be installed before it
# can be seeded, and xcodebuild installs it as part of `test`, so the order is:
# build for testing, install, seed the client's own store, then test without
# building. Without NK_UI_SEED the tests still run and skip the checks that need a
# source, which is enough to catch a missing tab.
#
# NK_UI_SEED_REPLACE=1 lets a run replace a device store that holds other sources;
# without it a differing seed is refused, which is the safe default.
#
# Off by default: a simulator run takes ten minutes and can hang, while the checks
# above are the ones that answer "does it build and does it pass". Ask for it with
# NK_UI_TESTS=1.
if [ "${NK_UI_TESTS:-0}" != "1" ]; then
	say "SKIP  xcodebuild test (set NK_UI_TESTS=1 to drive the interface)"
elif command -v xcodegen >/dev/null 2>&1; then
	device=$(xcrun simctl list devices available --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
    devices = [d for group in data.get("devices", {}).values() for d in group
               if d.get("isAvailable") and d.get("name", "").startswith("iPhone")]
    devices.sort(key=lambda d: d.get("state") != "Booted")
    print(devices[0]["udid"] if devices else "")
except (ValueError, KeyError):
    print("")
')
	if [ -z "${device:-}" ]; then
		fail "xcodebuild test (no iPhone simulator available)" "$out/ui-tests.log"
	elif ! xcodegen generate >"$out/xcodegen.log" 2>&1; then
		fail "xcodegen generate" "$out/xcodegen.log"
	else
		ui="$out/ui"
		mkdir -p "$ui"
		if xcodebuild build-for-testing -scheme Nekularity \
			-destination "platform=iOS Simulator,id=$device" \
			-derivedDataPath "$ui/dd" >"$ui/build-for-testing.log" 2>&1; then
			pass "xcodebuild build-for-testing -scheme Nekularity" "$ui/build-for-testing.log"
			app=$(find "$ui/dd/Build/Products" -maxdepth 2 -name 'Nekularity.app' -print -quit 2>/dev/null || true)
			xcrun simctl boot "$device" >"$ui/sim-boot.log" 2>&1 || true
			xcrun simctl bootstatus "$device" -b >>"$ui/sim-boot.log" 2>&1 || true
			if [ -n "${app:-}" ] && xcrun simctl install "$device" "$app" >>"$ui/sim-boot.log" 2>&1; then
				pass "xcrun simctl install ($device)" "$ui/sim-boot.log"
				if [ -n "${NK_UI_SEED:-}" ]; then
					# The store is the client's own file, written before launch. A device
					# that already holds an older seed refuses a different one on
					# purpose; NK_UI_SEED_REPLACE=1 says this run may overwrite it, which
					# is what changing the seed content needs.
					seedArgs=""
					if [ "${NK_UI_SEED_REPLACE:-0}" = "1" ]; then seedArgs="--replace"; fi
					if sh scripts/seed-simulator.sh "$NK_UI_SEED" com.laincat.nekularity "$device" $seedArgs >"$ui/seed.log" 2>&1; then
						pass "scripts/seed-simulator.sh" "$ui/seed.log"
					else
						fail "scripts/seed-simulator.sh" "$ui/seed.log"
					fi
				fi
				# NK_UI_ONLY=testSomething runs one case; a comma or a pipe separates
				# several. A whole string is not a test name, and xcodebuild answers a
				# name it cannot find with exit 0 having executed nothing — that looked
				# like two passing cases until the log was read. So the count is
				# checked here, not the exit code.
				only=""
				wanted=""
				if [ -n "${NK_UI_ONLY:-}" ]; then
					names=$(printf '%s' "$NK_UI_ONLY" | tr '|,' '  ')
					wanted=$(printf '%s\n' $names | wc -l | tr -d ' ')
					for name in $names; do
						only="$only -only-testing:NekularityUITests/NekularityUITests/$name"
					done
				fi
				if xcodebuild test-without-building -scheme Nekularity $only \
					-destination "platform=iOS Simulator,id=$device" \
					-derivedDataPath "$ui/dd" >"$ui/tests.log" 2>&1; then
					ran=$(sed -n 's/.*Executed \([0-9][0-9]*\) tests\?,.*/\1/p' "$ui/tests.log" | tail -1)
					if [ -n "$wanted" ] && [ "${ran:-0}" != "$wanted" ]; then
						printf 'expected %s case(s), ran %s\n' "$wanted" "${ran:-0}" >>"$ui/tests.log"
						fail "xcodebuild test-without-building (asked for $wanted case(s), ran ${ran:-0})" "$ui/tests.log"
					fi
					pass "xcodebuild test-without-building ($device${NK_UI_ONLY:+ only $NK_UI_ONLY, ${ran:-?} case(s)})" "$ui/tests.log"
				else
					fail "xcodebuild test-without-building ($device${NK_UI_ONLY:+ only $NK_UI_ONLY})" "$ui/tests.log"
				fi
			else
				fail "xcrun simctl install ($device)" "$ui/sim-boot.log"
			fi
		else
			fail "xcodebuild build-for-testing -scheme Nekularity" "$ui/build-for-testing.log"
		fi
	fi
else
	fail "xcodebuild test (XcodeGen is not on PATH)" "$out/xcodegen.log"
fi
