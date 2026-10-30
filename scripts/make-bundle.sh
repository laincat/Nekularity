#!/bin/sh
# Build a deterministic source bundle for handing Nekularity to a machine
# without GitHub access, and split it into base64 segments with checksums.
#
# usage: make-bundle.sh OUTDIR [CHUNK]
#   OUTDIR  where to write nk-kit.tgz and NN.b64 segments
#   CHUNK   base64 characters per segment (default 1650)
#
# Every file is added in sorted order with mtime 0, so the same tree always
# produces the same archive and the same segment checksums.
set -eu

OUT=${1:?usage: make-bundle.sh OUTDIR [CHUNK]}
CHUNK=${2:-1650}

python3 - "$OUT" "$CHUNK" <<'PY'
import hashlib, io, os, pathlib, subprocess, sys, tarfile, gzip, base64

out = pathlib.Path(sys.argv[1])
chunk = int(sys.argv[2])
root = pathlib.Path(
    subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                   text=True, check=True).stdout.strip())

keep = ["Package.swift"]
for top in ("Sources", "App", "Tests"):
    base = root / top
    if not base.is_dir():
        continue
    for path in sorted(base.rglob("*.swift")):
        keep.append(path.relative_to(root).as_posix())

def normalise(info):
    info.mtime = 0
    info.uid = info.gid = 0
    info.uname = info.gname = ""
    info.mode = 0o644
    return info

raw = io.BytesIO()
with tarfile.open(fileobj=raw, mode="w") as tar:
    for name in keep:
        tar.add(root / name, arcname=name, filter=normalise)
gz = gzip.compress(raw.getvalue(), 9, mtime=0)

out.mkdir(parents=True, exist_ok=True)
(out / "nk-kit.tgz").write_bytes(gz)

b64 = base64.b64encode(gz).decode()
parts = [b64[i:i + chunk] for i in range(0, len(b64), chunk)]
for index, part in enumerate(parts, 1):
    (out / f"{index:02d}.b64").write_text(part)

print(f"files   {len(keep)} (.swift {sum(1 for n in keep if n.endswith('.swift'))})")
print(f"tgz     {len(gz)} bytes  md5 {hashlib.md5(gz).hexdigest()}")
print(f"base64  {len(b64)} chars in {len(parts)} segments of <= {chunk}")
print()
print("segment  chars  md5                                tail")
for index, part in enumerate(parts, 1):
    digest = hashlib.md5(part.encode()).hexdigest()
    print(f"{index:02d}       {len(part):5d}  {digest}  {part[-12:]}")
PY
