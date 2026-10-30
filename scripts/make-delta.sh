#!/bin/sh
# Packages the files a bundle does not have yet, for a machine that already
# has the previous bundle. Same layout and layout rules as make-bundle.sh:
# every path is normalised so the same tree gives the same bytes.
#
#   scripts/make-delta.sh SINCE OUTDIR [CHUNK]
#
# SINCE is any revision git can diff against; the files that differ from it
# are shipped under their own paths, so extracting over the old tree updates
# them in place.
#
# DELTA_SKIP_TESTS=1 leaves Tests/ out. The test file is the largest one in the
# tree, and a few added tests usually travel better as text in the conversation
# than as another twenty segments.
set -eu

if [ $# -lt 2 ]; then
	say="usage: scripts/make-delta.sh SINCE OUTDIR [CHUNK]"
	printf '%s\n' "$say" >&2
	exit 2
fi

since=$1
out=$2
chunk=${3:-1548}

mkdir -p "$out"
rm -f "$out"/[0-9][0-9].b64 "$out"/delta.* "$out"/table.txt

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/files"

n=0
files=$(git diff --name-only "$since" -- . | grep -E '\.swift$|^Package\.swift$' || true)
if [ "${DELTA_SKIP_TESTS:-0}" = 1 ]; then
	files=$(printf '%s
' "$files" | grep -v '^Tests/' || true)
fi
for f in $files; do
	mkdir -p "$work/files/$(dirname "$f")"
	cp "$f" "$work/files/$f"
	n=$((n + 1))
done
if [ "$n" -eq 0 ]; then
	printf 'no changes since %s\n' "$since"
	exit 0
fi
printf '%d file(s) changed since %s\n' "$n" "$since"

( cd "$work" && tar --format=ustar --mtime=@0 --owner=0 --group=0 \
	--numeric-owner --sort=name --mode=0644 -cf delta.tar files ) || {
	printf 'tar failed\n' >&2
	exit 1
}
gzip -n -9 -f "$work/delta.tar"
cp "$work/delta.tar.gz" "$out/delta.tar.gz"
base64 < "$out/delta.tar.gz" | tr -d '\n' > "$out/delta.b64"

python3 - "$out" "$chunk" <<'PY'
import hashlib, os, sys
out, chunk = sys.argv[1], int(sys.argv[2])
data = open(os.path.join(out, "delta.b64"), "rb").read()
rows = []
for i in range(0, len(data), chunk):
    n = i // chunk + 1
    part = data[i:i + chunk]
    open(os.path.join(out, "%02d.b64" % n), "wb").write(part)
    rows.append(("%02d" % n, len(part), hashlib.md5(part).hexdigest()))
open(os.path.join(out, "table.txt"), "w").write(
    "\n".join("%s %d %s" % r for r in rows) + "\n")
archive = open(os.path.join(out, "delta.tar.gz"), "rb").read()
print("archive %d bytes md5 %s" % (len(archive), hashlib.md5(archive).hexdigest()))
print("base64  %d chars, %d segment(s)" % (len(data), len(rows)))
for r in rows:
    print("%s %d %s" % r)
PY
