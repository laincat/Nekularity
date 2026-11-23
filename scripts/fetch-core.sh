#!/bin/sh
# Builds VeneraCatCore.xcframework from VeneraCat Core into Vendor/.
#
#   scripts/fetch-core.sh [path-to-VeneraCat-Core-checkout]
#
# Without an argument it uses the latest Core main in build/core. Needs macOS with
# Xcode and Go (the version in Core's go.mod).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
if [ $# -ge 1 ]; then
	core=$(cd "$1" && pwd)
else
	core="$root/build/core"
	if [ ! -d "$core/.git" ]; then
		git clone --quiet https://github.com/laincat/VeneraCat-Core.git "$core"
	fi
	git -C "$core" fetch --quiet origin '+refs/heads/main:refs/remotes/origin/main'
	git -C "$core" checkout --quiet --detach origin/main
fi

head=$(git -C "$core" rev-parse HEAD)
if [ -n "$(git -C "$core" status --porcelain --untracked-files=no)" ]; then
	head="$head-dirty"
fi
echo "Core: $head"
(cd "$core" && sh scripts/mac-verify.sh)
mkdir -p "$root/Vendor"
rm -rf "$root/Vendor/VeneraCatCore.xcframework"
cp -R "$core/build/VeneraCatCore.xcframework" "$root/Vendor/"
printf '%s\n' "$head" > "$root/Vendor/CoreRevision.txt"
echo "Vendor/VeneraCatCore.xcframework ready"
