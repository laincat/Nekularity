#!/bin/sh
# Packs named files for a machine that cannot clone the client, and prints one
# block to paste into a message: archive size and md5, per-file md5, and a
# segment table.
#
#   scripts/make-payload.sh OUTDIR FILE [FILE ...]
#
# Why one block: the numbers that matter live in two places — the archive a
# receiver verifies and the files they check after unpacking. Reading one from
# memory and the other from this script is how a message ends up telling the
# receiver to expect the md5 of a file that is no longer in the archive. One
# block, copied whole, cannot disagree with itself.
#
# Segment size defaults to 1400 characters; override with PAYLOAD_CHUNK.
set -eu

if [ $# -lt 2 ]; then
	printf 'usage: scripts/make-payload.sh OUTDIR FILE [FILE ...]\n' >&2
	exit 2
fi

out=$1
shift
chunk=${PAYLOAD_CHUNK:-1400}

mkdir -p "$out"
rm -f "$out"/seg*.txt "$out"/p.tar.gz "$out"/p.b64

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/files"

for f in "$@"; do
	if [ ! -f "$f" ]; then
		printf 'make-payload: no such file: %s\n' "$f" >&2
		exit 1
	fi
	mkdir -p "$work/files/$(dirname "$f")"
	cp "$f" "$work/files/$f"
done

( cd "$work" && tar --format=ustar --mtime=@0 --owner=0 --group=0 \
	--numeric-owner --sort=name --mode=0644 -cf p.tar files ) || {
	printf 'make-payload: tar failed\n' >&2
	exit 1
}
gzip -9 -n -f "$work/p.tar"
cp "$work/p.tar.gz" "$out/p.tar.gz"
base64 < "$out/p.tar.gz" | tr -d '\n' > "$out/p.b64"

python3 - "$out" "$chunk" "$work/files" <<'PY'
import hashlib, os, sys

out, chunk, files = sys.argv[1], int(sys.argv[2]), sys.argv[3]
data = open(os.path.join(out, "p.b64"), "rb").read()
segments = []
for i in range(0, len(data), chunk):
    n = i // chunk + 1
    part = data[i:i + chunk]
    name = "seg%02d.txt" % n
    open(os.path.join(out, name), "wb").write(part)
    segments.append((n, len(part), hashlib.md5(part).hexdigest()))

archive = open(os.path.join(out, "p.tar.gz"), "rb").read()
print("archive p.tar.gz %d bytes md5 %s" % (len(archive), hashlib.md5(archive).hexdigest()))
print("base64 %d chars in %d segment(s) of %d" % (len(data), len(segments), chunk))
print("")
print("--- files inside, md5 after unpacking ---")
for root, _, names in os.walk(files):
    for name in sorted(names):
        path = os.path.join(root, name)
        rel = os.path.relpath(path, files).replace(os.sep, "/")
        print("%s  %s" % (hashlib.md5(open(path, "rb").read()).hexdigest(), rel))
print("")
print("--- segments ---")
for n, length, digest in segments:
    print("seg%02d  %4d  %s" % (n, length, digest))
PY

printf '\nsegments written to %s/segNN.txt\n' "$out"
