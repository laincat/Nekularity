#!/bin/sh
# Runs the theme-link UI cases against a local HTTPS/HTTP fixture.
#
#   scripts/theme-fixture.sh [DEVICE_UDID]        (default: booted)
#
# What it does, in order:
#   1. makes a throwaway CA (30 days) and a leaf for 127.0.0.1 in a temp dir;
#   2. serves the fixtures in UITests/Fixtures/theme on 18791 (https) and
#      18792 (http);
#   3. trusts that CA in ONE simulator — `simctl keychain add-root-cert`, which
#      writes that simulator's own trust store, never the Mac's;
#   4. checks the fixture answers through the CA before the tests start;
#   5. runs `ZZThemeLinkTests` and exits with its status;
#   6. stops the servers and prints the CA fingerprint and the leaf's expiry.
#
# It deliberately does not run `simctl keychain reset`: that drops every
# credential in the simulator, not just this CA. If the store already had
# content, the script says so and leaves the decision to you.
#
# Environment:
#   NK_SCHEME        default Nekularity
#   NK_DD            derivedDataPath (default: xcodebuild's own)
#   NK_XCODE_FLAGS   extra xcodebuild flags, e.g. -disableAutomaticPackageResolution
set -eu

device=${1:-booted}
root=$(cd "$(dirname "$0")/.." && pwd)
fixtures="$root/UITests/Fixtures/theme"
scheme=${NK_SCHEME:-Nekularity}
project="$root/$scheme.xcodeproj"

# The accepted theme is the one the app installed in the round that proved this
# path; pinning the hash catches a fixture edited without the cases re-run.
expect_valid=64c49a0d0473655b2ff49495ab8055498fac1e6f809fd9c1200a2bc21f87cadd

say() { printf 'theme-fixture: %s\n' "$*"; }
die() { printf 'theme-fixture: %s\n' "$*" >&2; exit 2; }

command -v openssl >/dev/null 2>&1 || die "no openssl"
command -v python3 >/dev/null 2>&1 || die "no python3"
command -v xcrun >/dev/null 2>&1 || die "no xcrun"
[ -d "$fixtures" ] || die "no fixtures at $fixtures"
[ -d "$project" ] || die "no $scheme.xcodeproj (generate it with xcodegen first)"

got=$(shasum -a 256 "$fixtures/valid.json" | cut -d' ' -f1)
[ "$got" = "$expect_valid" ] || die "valid.json drifted from the accepted theme: $got"
python3 - "$fixtures/invalid.json" <<'PY' || die "invalid.json parses; the case needs truncated JSON"
import json, sys
try:
    json.load(open(sys.argv[1]))
except Exception:
    raise SystemExit(0)
raise SystemExit(1)
PY

if [ "$device" = "booted" ]; then
	device=$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
booted = [d["udid"] for run in devices.values() for d in run if d.get("state") == "Booted"]
if not booted:
    raise SystemExit(1)
print(booted[0])') || die "no booted simulator; pass a UDID"
	say "using booted simulator $device"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/nk-theme-fixture.XXXXXX")
ca="$work/ca.pem"
cakey="$work/ca.key"
leaf="$work/leaf.pem"
leafkey="$work/leaf.key"
requests="$work/requests.log"

cat >"$work/ca.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no
[dn]
CN = Nekularity Local Fixture CA
[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF
cat >"$work/leaf.cnf" <<'EOF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = 127.0.0.1
[v3_leaf]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:127.0.0.1,DNS:localhost
subjectKeyIdentifier = hash
EOF

openssl req -x509 -newkey rsa:2048 -days 30 -nodes -keyout "$cakey" -out "$ca" \
	-config "$work/ca.cnf" >/dev/null 2>&1 || die "could not make the CA"
openssl req -newkey rsa:2048 -nodes -keyout "$leafkey" -out "$work/leaf.csr" \
	-config "$work/leaf.cnf" >/dev/null 2>&1 || die "could not make the leaf request"
openssl x509 -req -in "$work/leaf.csr" -CA "$ca" -CAkey "$cakey" -CAcreateserial \
	-days 30 -extfile "$work/leaf.cnf" -extensions v3_leaf -out "$leaf" >/dev/null 2>&1 \
	|| die "could not sign the leaf"

store="$HOME/Library/Developer/CoreSimulator/Devices/$device/data/Library/Keychains/TrustStore.sqlite3"
before=0
if [ -f "$store" ]; then
	before=$(wc -c <"$store" | tr -d ' ')
fi

python3 "$fixtures/serve.py" --cert "$leaf" --key "$leafkey" --log "$requests" \
	>"$work/serve.log" 2>&1 &
server=$!
cleanup() {
	kill "$server" 2>/dev/null || true
	wait "$server" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
sleep 1
kill -0 "$server" 2>/dev/null || { cat "$work/serve.log" >&2; die "the fixture did not stay up"; }

# Waits on a bare TCP connect, not on a fixture route: a probe that asks for
# valid.json would land in the request log and look like the app's own fetch.
port_open() {
	python3 - "$1" <<'PY'
import socket, sys
s = socket.socket()
s.settimeout(0.5)
try:
    s.connect(("127.0.0.1", int(sys.argv[1])))
except OSError:
    raise SystemExit(1)
finally:
    s.close()
PY
}

i=0
while [ "$i" -lt 50 ]; do
	if port_open 18791 && port_open 18792; then
		break
	fi
	i=$((i + 1))
	sleep 0.2
done
port_open 18791 && port_open 18792 || die "the fixtures did not take both ports"

say "trusting the CA in simulator $device only"
xcrun simctl keychain "$device" add-root-cert "$ca" || die "simctl could not add the CA"

say "pre-flight: https://127.0.0.1:18791/valid.json through $work/ca.pem"
if ! body=$(curl -sS --cacert "$ca" https://127.0.0.1:18791/valid.json); then
	die "the HTTPS fixture did not answer through the new CA"
fi
printf '  %s\n' "$body"
port_open 18792 || die "the HTTP fixture did not take its port"

if [ -n "${NK_DD:-}" ]; then
	set -- -derivedDataPath "$NK_DD"
else
	set --
fi
status=0
# shellcheck disable=SC2086
xcodebuild test -project "$project" -scheme "$scheme" \
	-destination "platform=iOS Simulator,id=$device" "$@" ${NK_XCODE_FLAGS:-} \
	-only-testing:NekularityUITests/ZZThemeLinkTests || status=$?
say "xcodebuild exit status: $status"

cleanup
trap - EXIT INT TERM

printf '\n'
say "requests the fixture saw (the first valid.json is this script's pre-flight):"
sed 's/^/  /' "$requests" 2>/dev/null || true
say "anything on 18792 is the app: the script never speaks HTTP to that port."
say "CA fingerprint (SHA-256): $(openssl x509 -in "$ca" -noout -fingerprint -sha256 | sed 's/^.*=//')"
say "CA valid until:  $(openssl x509 -in "$ca" -noout -enddate | sed 's/^notAfter=//')"
say "leaf valid until: $(openssl x509 -in "$leaf" -noout -enddate | sed 's/^notAfter=//')"
say "fixture server log: $work/serve.log"
say "certificates kept in: $work"
say "note: this run added the CA above to this simulator and removed nothing."
if [ "$before" != "0" ]; then
	say "      TrustStore.sqlite3 already held $before bytes before this run; a CA from an"
	say "      earlier run is still trusted — compare its fingerprint deliberately."
else
	say "      TrustStore.sqlite3 was 0 bytes before this run. That size is not proof of"
	say "      an empty store: a CA from an earlier run may still be trusted."
fi
say "      This script never resets the store; remove the CA deliberately if you need to."
exit "$status"
