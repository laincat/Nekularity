#!/bin/sh
# Verifies Nekularity on a machine with Xcode: docs, Swift syntax, Kit unit
# tests, real iOS App bundle build + ATS plist check, and optional simulator UI.
#
#   scripts/verify-ios.sh [path-to-VeneraCatCore.xcframework]
#
# Requires XcodeGen for App bundle verification. Set NK_TYPECHECK_ONLY=1 only
# when you explicitly want a SwiftPM + swiftc type-check without building an
# App bundle (note: that does not verify Info.plist or app resources).
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

# 1. Documentation pairs and root cleanliness.
if sh scripts/check-docs.sh >"$out/docs.log" 2>&1; then
	pass "sh scripts/check-docs.sh" "$out/docs.log"
else
	fail "sh scripts/check-docs.sh" "$out/docs.log"
fi

# 2. Swift syntax check.
python3 scripts/check-swift.py >"$out/syntax.log" 2>&1 && syntax=$? || syntax=$?
if [ "$syntax" -eq 0 ]; then
	if grep -q 'the rule checks still run' "$out/syntax.log" 2>/dev/null; then
		pass "python3 scripts/check-swift.py (rules only: no parser here)" "$out/syntax.log"
	else
		pass "python3 scripts/check-swift.py" "$out/syntax.log"
	fi
elif [ "$syntax" -eq 2 ] || [ "$syntax" -eq 3 ]; then
	say "SKIP  python3 scripts/check-swift.py  (parser unavailable here; see $out/syntax.log)"
else
	fail "python3 scripts/check-swift.py" "$out/syntax.log"
fi

# 3. Kit unit tests against the real xcframework.
if [ ! -d Vendor/VeneraCatCore.xcframework ]; then
	say "FAIL  swift test  (no Vendor/VeneraCatCore.xcframework)"
	say "      run scripts/fetch-core.sh, or pass the framework as the first argument"
	exit 1
fi
if swift test --no-parallel >"$out/swift-test.log" 2>&1; then
	pass "swift test --no-parallel" "$out/swift-test.log"
else
	fail "swift test --no-parallel" "$out/swift-test.log"
fi

# 4. Real App bundle build + built Info.plist ATS check.
if command -v xcodegen >/dev/null 2>&1; then
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
	app=$(find "$out/dd" -name 'Nekularity.app' -maxdepth 6 | head -1)
	if [ -n "${app:-}" ] && sh scripts/verify-ats.sh --plist-only "$app/Info.plist" >"$out/ats.log" 2>&1; then
		pass "sh scripts/verify-ats.sh --plist-only (built app)" "$out/ats.log"
	else
		fail "sh scripts/verify-ats.sh --plist-only (built app)" "$out/ats.log"
	fi
elif [ "${NK_TYPECHECK_ONLY:-0}" = "1" ]; then
	sdk=$(xcrun --sdk iphoneos --show-sdk-path)
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
	if swiftc -typecheck -swift-version 6 -sdk "$sdk" -target arm64-apple-ios26.0 \
		-I "$modules" -F "$modules" App/*.swift >"$out/app-typecheck.log" 2>&1; then
		pass "swiftc -typecheck App/*.swift (iOS, NK_TYPECHECK_ONLY=1)" "$out/app-typecheck.log"
	else
		fail "swiftc -typecheck App/*.swift (iOS, NK_TYPECHECK_ONLY=1)" "$out/app-typecheck.log"
	fi
else
	say "FAIL  xcodegen is required to build Nekularity.app (set NK_TYPECHECK_ONLY=1 for SwiftPM typecheck only)"
	exit 1
fi

# 5. Optional simulator UI suite (NK_UI_TESTS=1).
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
					seedArgs=""
					if [ "${NK_UI_SEED_REPLACE:-0}" = "1" ]; then seedArgs="--replace"; fi
					if sh scripts/seed-simulator.sh "$NK_UI_SEED" com.laincat.nekularity "$device" $seedArgs >"$ui/seed.log" 2>&1; then
						pass "scripts/seed-simulator.sh" "$ui/seed.log"
					else
						fail "scripts/seed-simulator.sh" "$ui/seed.log"
					fi
				fi
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
					-parallel-testing-enabled NO \
					-destination "platform=iOS Simulator,id=$device" \
					-derivedDataPath "$ui/dd" >"$ui/tests.log" 2>&1; then
					ran=$(grep -o 'Executed [0-9][0-9]* test' "$ui/tests.log" | tail -1 | grep -o '[0-9][0-9]*')
					if [ -n "$wanted" ] && [ "${ran:-0}" -lt "$wanted" ]; then
						fail "xcodebuild test-without-building (asked for $wanted, ran ${ran:-0})" "$ui/tests.log"
					elif [ -n "$wanted" ]; then
						pass "xcodebuild test-without-building ($NK_UI_ONLY, $ran cases)" "$ui/tests.log"
					else
						pass "xcodebuild test-without-building -scheme Nekularity ($device)" "$ui/tests.log"
					fi
				else
					fail "xcodebuild test-without-building -scheme Nekularity" "$ui/tests.log"
				fi
			else
				fail "xcrun simctl install ($device)" "$ui/sim-boot.log"
			fi
		else
			fail "xcodebuild build-for-testing -scheme Nekularity" "$ui/build-for-testing.log"
		fi
	fi
else
	say "FAIL  NK_UI_TESTS=1 requires xcodegen"
	exit 1
fi
