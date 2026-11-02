#!/bin/sh
# Puts sources into a booted simulator's app container, so a UI test opens on a
# client that already has them.
#
#   scripts/seed-simulator.sh SEED.json [BUNDLE_ID] [DEVICE_UDID] [--replace]
# Existing source data is preserved unless --replace is supplied.
#
# The file is the same one a client writes after installing sources by hand: Core
# records, script bodies included. It is placed where the client restores from at
# launch, which is `Library/Application Support/Nekularity/plugins.json` inside the
# app's data container. Nothing in the app knows about this script — it is the
# client's own storage, filled before launch rather than through the interface.
#
# Generate the file anywhere Core runs (cmd/seedgen in the desktop client):
#
#   seedgen plugins.json nhentai.js wnacg.js
set -eu

if [ $# -lt 1 ]; then
	printf 'usage: scripts/seed-simulator.sh SEED.json [BUNDLE_ID]\n' >&2
	exit 2
fi

seed=$1
bundle=${2:-com.laincat.nekularity}
device=${3:-booted}
replace=${4:-}

if [ ! -f "$seed" ]; then
	printf 'seed-simulator: no such file: %s\n' "$seed" >&2
	exit 2
fi

if ! xcrun simctl list devices booted | grep -q 'Booted'; then
	printf 'seed-simulator: no booted simulator\n' >&2
	printf '  xcrun simctl boot "iPhone 17e"  (or whichever device is available)\n' >&2
	exit 2
fi

# The container only exists once the app is installed, so the caller installs
# first. Getting this wrong silently seeds nothing, hence the explicit failure.
if ! container=$(xcrun simctl get_app_container "$device" "$bundle" data 2>/dev/null); then
	printf 'seed-simulator: %s is not installed on simulator %s\n' "$bundle" "$device" >&2
	printf '  install it first: xcrun simctl install %s <path to Nekularity.app>\n' "$device" >&2
	exit 2
fi

target="$container/Library/Application Support/Nekularity"
mkdir -p "$target"

# Where the records actually live depends on whether this install has run the
# environment migration. Writing to the old root path on a device that has
# already migrated puts the seed where nothing reads it, and the run then reports
# "no sources" as if the app were broken.
if [ -d "$target/Profiles" ]; then
	active=""
	# Prefer the environment that already holds sources, then the newest one.
	for candidate in "$target"/Profiles/*/; do
		[ -d "$candidate" ] || continue
		if [ -f "$candidate/plugins.json" ]; then
			active="${candidate%/}"
			break
		fi
		[ -z "$active" ] && active="${candidate%/}"
	done
	if [ -z "$active" ]; then
		printf 'seed-simulator: %s/Profiles is empty\n' "$target" >&2
		exit 2
	fi
	target="$active"
fi

if [ -e "$target/plugins.json" ] && [ "$replace" != "--replace" ]; then
	if cmp -s "$seed" "$target/plugins.json"; then
		printf 'seed-simulator: matching seed already present: %s\n' "$target/plugins.json"
		exit 0
	fi
	printf 'seed-simulator: existing source store preserved: %s\n' "$target/plugins.json" >&2
	printf '  pass --replace only when the simulator data may be overwritten\n' >&2
	exit 2
fi
cp "$seed" "$target/plugins.json"
printf 'seed-simulator: wrote %s (%s bytes)\n' "$target/plugins.json" "$(wc -c <"$seed" | tr -d ' ')"
