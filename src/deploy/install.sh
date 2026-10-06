#!/usr/bin/env bash
# Install musebox: Meta's Muse gadget SDK patched into a files-only drop box
# (no shell; Muse reads the box and writes only tasks/<id>/out/), a `muse`
# account, a `musebox` group, the box, the `musebox` CLI and a sandboxed
# systemd unit. Idempotent: rerun to update.
#
#   sudo bash src/deploy/install.sh [--box DIR] [--members USER,...] [--start]
#   sudo bash src/deploy/install.sh --uninstall [--purge]
#
#   --box DIR          the drop box (default /srv/musebox; not under /home)
#   --members LIST     accounts that may leave tasks (default: the sudo user)
#   --start            enable and (re)start the service; needs a pairing in
#                      /var/lib/musegadget (see pair.sh)
#   --uninstall        remove the service, venv and CLI; keep box and pairing
#   --purge            with --uninstall: also the box, pairing, user and group
#
# Doesn't touch Bluetooth. Pair with pair.sh, on this machine if it has
# Bluetooth or on any other Linux box that does.
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$HERE/sdk"
UV_VERSION="$(grep -oP '^UV_VERSION="\K[^"]+' "$SDK/install.sh")"
PREFIX=/opt/musegadget
VENV="$PREFIX/venv"
UNIT=/etc/systemd/system/musegadget.service
STATE_DIR=/var/lib/musegadget

BOX=/srv/musebox
MEMBERS="${SUDO_USER:-}"
START=0
UNINSTALL=0
PURGE=0

say() { echo "==> $*"; }
die() { echo "install.sh: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --box) BOX="${2:?--box needs a directory}"; shift 2 ;;
        --members) MEMBERS="${2:?--members needs a list}"; shift 2 ;;
        --start) START=1; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        --purge) PURGE=1; shift ;;
        -h|--help) sed -n '2,21s/^# \{0,1\}//p' "$0"; exit 0 ;;
        *) die "unknown option: $1" ;;
    esac
done
[ "$(id -u)" -eq 0 ] || die "run with sudo"

if [ "$UNINSTALL" = 1 ]; then
    box="$(grep -oP '^Environment=MUSEBOX_ROOT=\K.*' "$UNIT.d/musebox.conf" 2>/dev/null || echo "$BOX")"
    say "Removing the service, venv and CLI"
    systemctl disable --now musegadget.service >/dev/null 2>&1 || true
    rm -rf "$UNIT" "$UNIT.d" "$PREFIX" /usr/local/bin/musegadget /usr/local/bin/musebox
    systemctl daemon-reload
    if [ "$PURGE" = 1 ]; then
        say "Purging $box, $STATE_DIR, user muse and group musebox"
        rm -rf "$box" "$STATE_DIR"
        userdel muse 2>/dev/null || true
        groupdel musebox 2>/dev/null || true
        echo "Also remove the gadget in the Muse app."
    fi
    exit 0
fi

BOX="$(realpath -m "$BOX")"
case "$BOX" in
    /home|/home/*|/root|/root/*|/run/user/*) die "the box can't be under /home, /root or /run/user (the sandbox hides them)" ;;
    /|/etc|/usr|/var|/opt|/srv|/mnt|/media) die "pick a dedicated directory for the box, not $BOX" ;;
esac

say "Prerequisites"
command -v systemctl >/dev/null || die "systemd is required"
command -v curl >/dev/null || die "curl is required"
if ! /usr/bin/python3 -c 'import cryptography' 2>/dev/null; then
    if command -v apt-get >/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends python3-cryptography
    else
        die "install your distribution's python3 cryptography package first"
    fi
fi

say "Accounts"
getent group musebox >/dev/null || groupadd --system musebox
getent passwd muse >/dev/null ||
    useradd --system --gid musebox --home-dir /nonexistent --no-create-home \
        --shell /usr/sbin/nologin --comment "Muse gadget file ops" muse
IFS=',' read -r -a members <<<"$MEMBERS"
for m in "${members[@]}"; do
    [ -n "$m" ] || continue
    getent passwd "$m" >/dev/null || die "no such account: $m"
    id -nG "$m" | tr ' ' '\n' | grep -qx musebox || { usermod -aG musebox "$m"; say "Added $m to musebox (new logins pick it up; musebox uses sg meanwhile)"; }
done

say "Box at $BOX"
install -d -o root -g musebox -m 2750 "$BOX"
# Sticky: members make task dirs, muse can't remove them.
install -d -o root -g musebox -m 3770 "$BOX/tasks"
sed "s|@BOX@|$BOX|g; s|@HOST@|$(hostname)|g" "$HERE/box/README.md.in" >"$BOX/README.md"
chown root:musebox "$BOX/README.md"
chmod 0640 "$BOX/README.md"

say "musegadget into $VENV"
if [ ! -x "$PREFIX/bin/uv" ] || [ "$("$PREFIX/bin/uv" --version | awk '{print $2}')" != "$UV_VERSION" ]; then
    mkdir -p "$PREFIX/bin"
    curl -fsSL "https://astral.sh/uv/$UV_VERSION/install.sh" |
        env UV_INSTALL_DIR="$PREFIX/bin" UV_NO_MODIFY_PATH=1 sh -s -- --quiet
fi
uv="$PREFIX/bin/uv"
[ -x "$VENV/bin/python" ] ||
    "$uv" venv --quiet --python /usr/bin/python3 --system-site-packages "$VENV"
# Build from a copy: building in place leaves root-owned build/ in the repo.
build="$(mktemp -d)"
trap 'rm -rf "$build"' EXIT
cp -r "$SDK" "$build/sdk"
"$uv" pip install --quiet --python "$VENV/bin/python" --no-deps --reinstall "$build/sdk"
"$uv" pip install --quiet --python "$VENV/bin/python" --require-hashes \
    -r "$SDK/src/musegadget/data/requirements.lock"
ln -sf "$VENV/bin/musegadget" /usr/local/bin/musegadget
sed "s|^BOX=.*|BOX=\"\${MUSEBOX:-$BOX}\"|" "$HERE/bin/musebox" >/usr/local/bin/musebox
chmod 0755 /usr/local/bin/musebox

say "Service"
sed "s/@RUN_AS@/muse/" "$SDK/src/musegadget/data/musegadget.service" >"$UNIT"
install -d "$UNIT.d"
sed "s|@BOX@|$BOX|g" "$HERE/deploy/musebox.conf.in" >"$UNIT.d/musebox.conf"
install -d -m 0700 "$STATE_DIR"
systemctl daemon-reload

if [ "$START" = 1 ]; then
    [ -s "$STATE_DIR/pairing.json" ] || die "not paired yet: run pair.sh first"
    systemctl enable musegadget.service >/dev/null 2>&1
    systemctl restart musegadget.service
    say "Started. A healthy start logs 'registered with the Muse': sudo journalctl -u musegadget -f"
elif systemctl is-active -q musegadget.service; then
    systemctl restart musegadget.service
    say "Restarted the running service"
else
    say "Installed. Next: pair.sh, then rerun with --start."
fi
