#!/bin/sh
# Checks that Vendor/VeneraCatCore.xcframework exposes the Magpie surface this
# client calls.
#
# The framework is a build artifact: it can lag behind Core without anything
# failing until a Swift file names a method that is not there. That happened
# once — the header had no chatStart while the source called it — so the surface
# is checked before the build rather than discovered by it.
#
#   scripts/check-core-surface.sh [path-to-xcframework]
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
framework=${1:-"$root/Vendor/VeneraCatCore.xcframework"}

header=$(find "$framework" -path '*ios-arm64*' -name 'Mobile.objc.h' -print -quit 2>/dev/null || true)
if [ -z "$header" ]; then
	printf 'check-core-surface: no Mobile.objc.h under %s\n' "$framework" >&2
	printf '  run scripts/fetch-core.sh first\n' >&2
	exit 2
fi

# Every MobileMagpie method this client calls, by the selector the header must
# declare. Keep this list in step with Sources/NekularityKit/Magpie/CoreMagpie.swift.
# The Objective-C selectors, which is what the header declares; Swift's imported
# names differ (cancelSignIn: becomes cancelSign(in:)).
selectors='auth: authorize: call: cancelSignIn: chatCancel: chatNext: chatStart: checkin: close loadPackage: models: poll: savedAuth: setAuth: setPluginOptions: usage: usageSummary:'

missing=''
for one in $selectors; do
	# The header declares each as "- (<type>)name:(...)", so match the selector
	# name followed by a colon, or the bare name for methods with no argument.
	case $one in
	*:) pattern=")${one}" ;;
	*) pattern=")$one;" ;;
	esac
	if ! grep -q -- "$pattern" "$header"; then
		missing="$missing $one"
	fi
done

if [ -n "$missing" ]; then
	printf 'check-core-surface: the framework is older than this client\n' >&2
	printf '  missing:%s\n' "$missing" >&2
	printf '  rebuild it with scripts/fetch-core.sh\n' >&2
	exit 1
fi

printf 'check-core-surface: %s exposes all 17 Magpie methods\n' "$(basename "$framework")"
