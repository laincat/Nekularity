#!/bin/sh
# Prints one line describing this tree, so two machines can be compared instead
# of "the numbers looked about right".
#
#   scripts/check-tree.sh
#
# Prints: commit, whether files are modified, .swift count, @Test and @Suite
# counts, and a digest over the sorted per-file counts. Two trees that agree on
# the digest have the same tests in the same files; equal totals alone do not
# prove that.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

commit=$(git rev-parse --short HEAD 2>/dev/null || echo none)
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then dirty='+dirty'; else dirty=''; fi

# `build/` holds Core's checkout after scripts/fetch-core.sh, and its own
# apple/CoreSmoke has .swift files. Counting those makes a verification machine
# disagree with the repository by two, for no reason that matters.
swift_files=$(find . -name '*.swift' -not -path './.build/*' -not -path './Vendor/*' -not -path './build/*' | wc -l | tr -d ' ')
tests=$(grep -rho '@Test' --include='*.swift' Sources App Tests 2>/dev/null | wc -l | tr -d ' ')
suites=$(grep -rho '@Suite' --include='*.swift' Sources App Tests 2>/dev/null | wc -l | tr -d ' ')

# A digest over "file:count" lines: same shape, same digest.
shape=$(
	for f in $(find Sources App Tests -name '*.swift' 2>/dev/null | sort); do
		printf '%s:%s\n' "$f" "$(grep -c '@Test' "$f" 2>/dev/null || echo 0)"
	done | git hash-object --stdin 2>/dev/null || echo none
)

printf 'tree %s%s  swift=%s  tests=%s  suites=%s  shape=%s\n' \
	"$commit" "$dirty" "$swift_files" "$tests" "$suites" "$shape"
