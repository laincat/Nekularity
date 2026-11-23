#!/bin/sh
# Verifies that the ATS policy (HTTPS by default, local networking allowed,
# explicit LANraragi exception, no non-exempt encryption) is present in a plist.
#
#   scripts/verify-ats.sh [--plist-only] [plist]
#
# With --plist-only, checks the given plist directly (for example the
# Info.plist inside an already-built Nekularity.app bundle) without rebuilding.
# Without --plist-only, checks App/Info.plist and, when XcodeGen is available,
# builds Nekularity.app and verifies the built bundle's Info.plist too.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

plist_only=0
if [ "${1:-}" = "--plist-only" ]; then
	plist_only=1
	shift
fi

plist=${1:-App/Info.plist}
if [ ! -f "$plist" ]; then
	printf 'verify-ats: %s is missing\n' "$plist" >&2
	exit 1
fi

check_plist() {
	ATS_PLIST="$1" python3 - <<'PY'
import os, plistlib, sys

with open(os.environ["ATS_PLIST"], "rb") as handle:
    data = plistlib.load(handle)

ats = data.get("NSAppTransportSecurity") or {}
arbitrary = ats.get("NSAllowsArbitraryLoads")
local = ats.get("NSAllowsLocalNetworking")
exceptions = ats.get("NSExceptionDomains") or {}
lrr = exceptions.get("lrr.tvc-16.science") or {}
lrr_http = lrr.get("NSExceptionAllowsInsecureHTTPLoads")
encryption = data.get("ITSAppUsesNonExemptEncryption")

print(f"verify-ats: NSAllowsArbitraryLoads = {arbitrary}")
print(f"verify-ats: NSAllowsLocalNetworking = {local}")
print(f"verify-ats: lrr.tvc-16.science NSExceptionAllowsInsecureHTTPLoads = {lrr_http}")
print(f"verify-ats: ITSAppUsesNonExemptEncryption = {encryption}")

ok = (arbitrary is False) and (local is True) and (lrr_http is True) and (encryption is False)
sys.exit(0 if ok else 1)
PY
}

check_plist "$plist"

if [ "$plist_only" -eq 1 ]; then
	exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
	printf 'verify-ats: FAIL  xcodegen is not installed; pass --plist-only to inspect %s without building\n' "$plist" >&2
	exit 1
fi

out=build/ats
mkdir -p "$out"

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

app=$(find "$out/dd" -name 'Nekularity.app' -maxdepth 6 | head -1)
[ -n "$app" ] || {
	printf 'verify-ats: FAIL  no Nekularity.app in %s\n' "$out/dd" >&2
	exit 1
}
check_plist "$app/Info.plist"
printf 'verify-ats: PASS  built bundle plist verified (%s)\n' "$app/Info.plist"
