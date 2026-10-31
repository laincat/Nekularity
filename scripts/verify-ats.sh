#!/bin/sh
# Proves that the ATS settings reach the built app, or says it cannot.
#
#   scripts/verify-ats.sh
#
# The plist being valid is not the same as Xcode using it: `verify-ios.sh` falls
# back to type checking when XcodeGen is absent, and then no app bundle is built at
# all. This script does the three steps that settle it — generate the project, ask
# the build settings which plist it will use, then read the plist out of the built
# bundle — and refuses to claim anything it did not do.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

out=build/ats
mkdir -p "$out"

if [ ! -f App/Info.plist ]; then
	printf 'verify-ats: App/Info.plist is missing\n' >&2
	exit 1
fi

if ! command -v xcodegen >/dev/null 2>&1; then
	printf 'verify-ats: SKIP  xcodegen is not installed, so no app bundle is built\n'
	printf 'verify-ats:       the plist contents are checked by check-plist below\n'
else
	xcodegen generate >"$out/xcodegen.log" 2>&1 || {
		printf 'verify-ats: FAIL  xcodegen generate (see %s)\n' "$out/xcodegen.log" >&2
		exit 1
	}
	xcodebuild -project Nekularity.xcodeproj -scheme Nekularity \
		-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO \
		-derivedDataPath "$out/dd" build >"$out/build.log" 2>&1 || {
		printf 'verify-ats: FAIL  xcodebuild (see %s)\n' "$out/build.log" >&2
		exit 1
	}

	settings=$(xcodebuild -project Nekularity.xcodeproj -scheme Nekularity \
		-showBuildSettings 2>/dev/null | grep -E '^ *INFOPLIST_FILE = ' || true)
	case "$settings" in
	*App/Info.plist*) ;;
	*)
		printf 'verify-ats: FAIL  the build is not using App/Info.plist: %s\n' "${settings:-unknown}" >&2
		exit 1
		;;
	esac

	app=$(find "$out/dd" -name 'Nekularity.app' -maxdepth 6 | head -1)
	[ -n "$app" ] || {
		printf 'verify-ats: FAIL  no Nekularity.app in %s\n' "$out/dd" >&2
		exit 1
	}
	if plutil -extract NSAppTransportSecurity.NSAllowsArbitraryLoads raw -o - "$app/Info.plist" 2>/dev/null | grep -qx true; then
		printf 'verify-ats: PASS  the built app allows arbitrary loads\n'
	else
		printf 'verify-ats: FAIL  the built app does not carry NSAllowsArbitraryLoads\n' >&2
		exit 1
	fi
fi

# What can always be checked, on any machine: the file itself. python3 is used rather
# than plutil so this half also runs where plutil does not exist.
python3 - <<'PY'
import plistlib, sys

with open("App/Info.plist", "rb") as handle:
    data = plistlib.load(handle)
ats = data.get("NSAppTransportSecurity") or {}
allows = ats.get("NSAllowsArbitraryLoads")
encryption = data.get("ITSAppUsesNonExemptEncryption")
print(f"check-plist: NSAllowsArbitraryLoads = {allows}")
print(f"check-plist: ITSAppUsesNonExemptEncryption = {encryption}")
sys.exit(0 if allows is True and encryption is False else 1)
PY
