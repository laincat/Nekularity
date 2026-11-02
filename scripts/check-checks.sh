#!/bin/sh
# Proves the checks still catch what they claim to.
#
# Three times a check ran, printed "ok", and was checking nothing: a video contract
# rule that skipped every `omitempty` field, an import rule whose pattern had been
# written as a literal backspace, and a stream test that asserted a framing the
# transport never promised. Every one of them was found by breaking the code by hand
# and watching nothing happen. This does that breaking on purpose, every run.
#
# Each case builds a throwaway tree, breaks one rule, and requires the check to fail
# with the message that names it — a check that fails for an unrelated reason is not
# proof of anything.
set -eu
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

# expect_failure NAME EXPECTED_TEXT COMMAND...
expect_failure() {
	name=$1; wanted=$2; shift 2
	if out=$("$@" 2>&1); then
		printf 'check-checks: %s did not fail\n' "$name" >&2
		fail=1
		return
	fi
	case "$out" in
	*"$wanted"*) printf 'check-checks: %s fails as it should\n' "$name" ;;
	*)
		printf 'check-checks: %s failed for another reason:\n%s\n' "$name" "$out" >&2
		fail=1
		;;
	esac
}

# expect_pass NAME COMMAND...
expect_pass() {
	name=$1; shift
	if out=$("$@" 2>&1); then
		printf 'check-checks: %s passes on a sound tree\n' "$name"
	else
		printf 'check-checks: %s failed on a sound tree:\n%s\n' "$name" "$out" >&2
		fail=1
	fi
}

# 1. A kit type named without the import. This is the mistake that shipped three
#    times and only a macOS build caught.
mkdir -p "$tmp/import/Sources/Kit" "$tmp/import/App"
printf 'public final class Widget {}\n' >"$tmp/import/Sources/Kit/Widget.swift"
printf 'struct Screen { let i = 1 }\nlet w = Widget()\n' >"$tmp/import/App/Screen.swift"
expect_failure "the missing-import rule" \
	"names Widget from the kit without importing it" \
	python3 scripts/check-swift.py --root "$tmp/import"
printf 'import NekularityKit\nlet w = Widget()\n' >"$tmp/import/App/Screen.swift"
expect_pass "the missing-import rule" \
	python3 scripts/check-swift.py --root "$tmp/import"

# 2. A member that escaped its type. Swift reports this from the call site, which
#    names the wrong file; the indent is the only local evidence.
mkdir -p "$tmp/scope/App"
printf 'struct A {
    var x = 1
}

    private func lost() { }
' >"$tmp/scope/App/Lost.swift"
expect_failure "the file-scope member rule" "indented member outside any type" 	python3 scripts/check-swift.py --root "$tmp/scope"
printf 'struct A {
    var x = 1
}

private func helper() { }
' >"$tmp/scope/App/Lost.swift"
expect_pass "the file-scope member rule" 	python3 scripts/check-swift.py --root "$tmp/scope"

# 2. A document whose pair is missing, and the same pair linked properly.
mkdir -p "$tmp/docs/docs"
printf '# a\n' >"$tmp/docs/docs/lonely.md"
expect_failure "the documentation pair rule" \
	"has no English counterpart" \
	env CHECK_DOCS_ROOT="$tmp/docs" sh scripts/check-docs.sh
printf '[en](lonely.en.md)\n\n# a\n' >"$tmp/docs/docs/lonely.md"
printf '[中文](lonely.md)\n\n# a\n' >"$tmp/docs/docs/lonely.en.md"
expect_pass "the documentation pair rule" \
	env CHECK_DOCS_ROOT="$tmp/docs" sh scripts/check-docs.sh

# 3. The video shape rule. This is the one that mattered: Core sends http.Header
#    (a map of lists) and the client read a map of strings, so every play answer
#    failed to decode and the screen said "no playable address".
# The Core checkout, in the order the other checks look for it.
core_src=${NK_CORE_SRC:-}
if [ -z "$core_src" ] && [ -f "../VeneraCat Core/video/video.go" ]; then
	core_src="../VeneraCat Core"
fi
if [ -z "$core_src" ] && [ -f "build/core/video/video.go" ]; then
	core_src="build/core"
fi
if [ -n "$core_src" ]; then
	mkdir -p "$tmp/video/Sources/NekularityKit/Video"
	video="$tmp/video/Sources/NekularityKit/Video/VideoModels.swift"
	cp Sources/NekularityKit/Video/VideoModels.swift "$video"
	python3 - "$video" <<'BROKEN'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
text = p.read_text(encoding="utf-8")
assert "[String: [String]]?" in text
p.write_text(text.replace("[String: [String]]?", "[String: String]?", 1), encoding="utf-8")
BROKEN
	expect_failure "the video shape rule" "headers" 		env NK_CLIENT_ROOT="$tmp/video" NK_CORE_SRC="$core_src" python3 scripts/check-video-json.py
	cp Sources/NekularityKit/Video/VideoModels.swift "$video"
	expect_pass "the video shape rule" 		env NK_CLIENT_ROOT="$tmp/video" NK_CORE_SRC="$core_src" python3 scripts/check-video-json.py
else
	printf 'check-checks: the video shape rule SKIPPED (no Core checkout at %s)
' "$core_src"
fi

# 4. The JSON key rule: a property the client reads and Core never sends. This is
#    the failure the check exists for, and the one that shipped when Core renamed
#    the video line title to name.
if [ -n "$core_src" ]; then
	mkdir -p "$tmp/json/Sources"
	cp -R Sources/NekularityKit "$tmp/json/Sources/NekularityKit"
	part="$tmp/json/Sources/NekularityKit/Core/Models.swift"
	python3 scripts/check-checks-add-key.py "$part" CategoryPart bogusProbeKey
	expect_failure "the JSON key rule" 'reads "bogusProbeKey"' \
		env NK_CLIENT_ROOT="$tmp/json" NK_CORE_SRC="$core_src" python3 scripts/check-json-keys.py
	cp Sources/NekularityKit/Core/Models.swift "$part"
	expect_pass "the JSON key rule" \
		env NK_CLIENT_ROOT="$tmp/json" NK_CORE_SRC="$core_src" python3 scripts/check-json-keys.py
else
	printf 'check-checks: the JSON key rule SKIPPED (no Core checkout)\n'
fi

# 5. The Magpie event rule: the keys the kit reads from a chat event, and the
#    kinds it names, against what Core sends.
if [ -n "$core_src" ]; then
	mkdir -p "$tmp/event/Sources/NekularityKit/Magpie"
	_event="$tmp/event/Sources/NekularityKit/Magpie/MagpieChat.swift"
	cp Sources/NekularityKit/Magpie/MagpieChat.swift "$_event"
	python3 scripts/check-checks-rename-key.py "$_event" 'object["kind"]' 'object["kinds"]'
	# It reports the key Core sends that nothing reads, which names the break.
	expect_failure "the Magpie event rule" 'never reads it' \
		env NK_CLIENT_ROOT="$tmp/event" NK_CORE_SRC="$core_src" python3 scripts/check-magpie-event.py
	cp Sources/NekularityKit/Magpie/MagpieChat.swift "$_event"
	expect_pass "the Magpie event rule" \
		env NK_CLIENT_ROOT="$tmp/event" NK_CORE_SRC="$core_src" python3 scripts/check-magpie-event.py
else
	printf 'check-checks: the Magpie event rule SKIPPED (no Core checkout)\n'
fi

# 6. A pair that links but says a different amount: one side gained a row.
printf '[en](lonely.en.md)\n\n# a\n\n| x |\n| - |\n' >"$tmp/docs/docs/lonely.md"
expect_failure "the pair-content rule" \
	"table rows" \
	env CHECK_DOCS_ROOT="$tmp/docs" sh scripts/check-docs.sh

[ "$fail" -eq 0 ] && echo "check-checks: the checks fail when they should"
exit "$fail"
