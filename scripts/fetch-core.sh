#!/bin/sh
# Builds VeneraCatCore.xcframework from VeneraCat Core into Vendor/.
#
#   scripts/fetch-core.sh [path-to-VeneraCat-Core-checkout]
#
# Without an argument it clones github.com/laincat/VeneraCat-Core at the
# branch, tag or commit in scripts/core-version into build/core. Needs macOS with
# Xcode and Go (the version in Core's go.mod).
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
pin=$(tr -d ' \n' < "$root/scripts/core-version")

if [ $# -ge 1 ]; then
	core=$(cd "$1" && pwd)
else
	core="$root/build/core"
	if [ ! -d "$core/.git" ]; then
		git clone --quiet https://github.com/laincat/VeneraCat-Core.git "$core"
	fi
	git -C "$core" fetch --quiet --force origin "+refs/heads/*:refs/remotes/origin/*" --tags
	if git -C "$core" rev-parse --verify --quiet "origin/$pin" >/dev/null; then
		git -C "$core" checkout --quiet --detach "origin/$pin"
	else
		git -C "$core" checkout --quiet --detach "$pin"
	fi
fi

# A pin that no longer exists (Core is rebuilt as one amended commit, so old hashes
# disappear) would otherwise check out something else and build it without a word.
head=$(git -C "$core" rev-parse HEAD)
case "$head" in
"$pin"*) ;;
*)
	printf 'fetch-core: HEAD %s does not match the pin %s
' "$head" "$pin" >&2
	printf 'fetch-core: update scripts/core-version, or pass the right checkout
' >&2
	if [ $# -ge 1 ]; then
		printf 'fetch-core: (continuing: a local checkout is taken as given)
' >&2
	else
		exit 1
	fi
	;;
esac

echo "Core: $(git -C "$core" rev-parse --short HEAD) (pinned $pin)"
(cd "$core" && sh scripts/mac-verify.sh)
mkdir -p "$root/Vendor"
rm -rf "$root/Vendor/VeneraCatCore.xcframework"
cp -R "$core/build/VeneraCatCore.xcframework" "$root/Vendor/"
echo "Vendor/VeneraCatCore.xcframework ready"
