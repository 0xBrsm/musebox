#!/usr/bin/env bash
# Pair a musebox gadget with the Muse app over Bluetooth LE. Run as root on
# any Linux box with Bluetooth: the gadget host itself, or another machine
# near your phone when the gadget host has no Bluetooth (the running service
# never needs it).
#
#   sudo bash pair.sh --install           pair here, save into /var/lib/musegadget
#   sudo bash pair.sh --out FILE|-        pair here, write the device state as a
#                                         tarball (- = stdout) for another host
#   options: --sdk DIR (default: sdk/ or ../sdk next to this script)
#            --token-file FILE (default: the SDK token on stdin)
#            --trace (keep an HCI trace for debugging)
#
# Remote pairing, from the gadget host:
#   d=$(ssh HOST mktemp -d) && scp -rq src/sdk src/deploy/pair.sh HOST:$d/
#   ssh HOST "sudo bash $d/pair.sh --out -" <token.txt >state.tgz
#   ssh HOST "sudo rm -rf $d"
#   sudo tar -C /var/lib/musegadget -xzf state.tgz && shred -u state.tgz
#
# Needs bluez, python3-dbus and python3-gi. Uses a throwaway venv; changes
# BlueZ settings only while pairing and puts back what it found. Logs go to
# stderr.
set -euo pipefail
umask 077

HERE="$(cd "$(dirname "$0")" && pwd)"
SDK="$HERE/../sdk"
[ -d "$HERE/sdk" ] && SDK="$HERE/sdk"   # copied next to pair.sh, as for remote pairing
MODE=""
OUT=""
TOKEN_FILE=""
TRACE=0
CONF=/etc/bluetooth/main.conf
DROPIN=/run/systemd/system/bluetooth.service.d/musebox-pair.conf
STATE_DIR=/var/lib/musegadget

say() { echo "==> $*" >&2; }
die() { echo "pair.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --install) MODE=install; shift ;;
        --out) MODE=out; OUT="${2:?--out needs a file or -}"; shift 2 ;;
        --sdk) SDK="${2:?}"; shift 2 ;;
        --token-file) TOKEN_FILE="${2:?}"; shift 2 ;;
        --trace) TRACE=1; shift ;;
        -h|--help) sed -n '2,24s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
[ -n "$MODE" ] || die "choose --install or --out FILE"
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -f "$SDK/install.sh" ] || die "no SDK at $SDK (pass --sdk)"
[ -n "$(ls /sys/class/bluetooth 2>/dev/null)" ] || die "no Bluetooth adapter here"
/usr/bin/python3 -c 'import dbus, gi' 2>/dev/null || die "install python3-dbus and python3-gi"
if [ "$MODE" = install ] && [ -s "$STATE_DIR/pairing.json" ]; then
    die "already paired; unpair in the Muse app and remove $STATE_DIR/pairing.json first"
fi

if [ -n "$TOKEN_FILE" ]; then TOKEN="$(tr -d '[:space:]' <"$TOKEN_FILE")"; else IFS= read -r TOKEN || true; fi
[[ "$TOKEN" =~ ^mgst_[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$ ]] ||
    die "no valid SDK token (mgst_…, from gadgets.muse.ai)"

W="$(mktemp -d /tmp/musebox-pair.XXXXXX)"
STATE="$W/state"
UV_VERSION="$(grep -oP '^UV_VERSION="\K[^"]+' "$SDK/install.sh")"

say "Throwaway musegadget in $W"
curl -fsSL "https://astral.sh/uv/$UV_VERSION/install.sh" |
    env UV_UNMANAGED_INSTALL="$W/bin" sh -s -- --quiet >&2
"$W/bin/uv" venv --quiet --python /usr/bin/python3 --system-site-packages "$W/venv" >&2
cp -r "$SDK" "$W/sdk"
"$W/bin/uv" pip install --quiet --python "$W/venv/bin/python" --no-deps "$W/sdk" >&2
"$W/bin/uv" pip install --quiet --python "$W/venv/bin/python" --require-hashes \
    -r "$W/sdk/src/musegadget/data/requirements.lock" >&2
install -d -m 0700 "$STATE"
printf '%s\n' "$TOKEN" >"$STATE/sdk_token"

was_active=0
systemctl is-active -q bluetooth && was_active=1
cp -a "$CONF" "$W/main.conf.orig" 2>/dev/null || : >"$W/main.conf.orig"
BTMON=""

restore() {
    say "Restoring Bluetooth"
    [ -z "$BTMON" ] || kill "$BTMON" 2>/dev/null || true
    if [ -s "$W/main.conf.orig" ]; then cp -a "$W/main.conf.orig" "$CONF"; else rm -f "$CONF"; fi
    rm -f "$DROPIN"
    systemctl daemon-reload
    if [ "$was_active" = 1 ]; then systemctl restart bluetooth; else systemctl stop bluetooth || true; fi
    if [ "$TRACE" = 1 ] && [ -s "$W/hci.btsnoop" ]; then
        cp "$W/hci.btsnoop" "/tmp/musebox-pair-$(date +%s).btsnoop"
        say "HCI trace kept in /tmp (read with btmon -r)"
    fi
    rm -rf "$W"
}
trap restore EXIT

say "Bluetooth on for pairing"
# Android writes (MTU - 3)-byte packets and fails above 512; iPhones drop
# pairing when BlueZ's battery plugin asks them to bond. The same fixes as the
# SDK's install.sh, but undone on exit.
if grep -q '^\[GATT\]' "$CONF" 2>/dev/null; then
    sed -i 's/^\[GATT\]$/[GATT]\nExchangeMTU = 256/' "$CONF"
else
    printf '\n[GATT]\nExchangeMTU = 256\n' >>"$CONF"
fi
bluetoothd="$(systemctl show -p ExecStart --value bluetooth | grep -oP 'path=\K[^ ;]+' | head -1)"
[ -x "${bluetoothd:-}" ] || bluetoothd="$(ls /usr/libexec/bluetooth/bluetoothd /usr/lib/bluetooth/bluetoothd 2>/dev/null | head -1)"
[ -n "$bluetoothd" ] || die "can't find bluetoothd"
mkdir -p "${DROPIN%/*}"
printf '[Service]\nExecStart=\nExecStart=%s -P battery\n' "$bluetoothd" >"$DROPIN"
systemctl daemon-reload
rfkill unblock bluetooth 2>/dev/null || true
systemctl restart bluetooth
sleep 2
if [ "$TRACE" = 1 ] && command -v btmon >/dev/null; then
    btmon -w "$W/hci.btsnoop" >/dev/null 2>&1 &
    BTMON=$!
fi

say "Open the Muse app and add the device named below"
MUSEGADGET_STATE_DIR="$STATE" "$W/venv/bin/musegadget" -v pair >&2 || true
[ -s "$STATE/pairing.json" ] || die "not paired"

if [ "$MODE" = install ]; then
    install -d -m 0700 "$STATE_DIR"
    install -m 0600 "$STATE/identity.json" "$STATE/pairing.json" "$STATE/sdk_token" "$STATE_DIR/"
    say "Saved in $STATE_DIR. Start with: sudo bash install.sh --start"
elif [ "$OUT" = - ]; then
    tar -C "$STATE" -cz identity.json pairing.json sdk_token
else
    tar -C "$STATE" -czf "$OUT" identity.json pairing.json sdk_token
    say "Device state in $OUT (secret: move it to the gadget host, then shred it)"
fi
