#!/usr/bin/env bash
set -euo pipefail

# Run the selector's EUID=0 branch in an isolated user/mount namespace.
# The namespace prohibits setgroups, so a runuser shim validates the real
# argument vector and uses setpriv for the actual UID/GID transition.
if [[ ${1:-} == --namespace ]]; then
    tmp=$2
    while [[ ! -e $tmp/ready ]]; do sleep 0.02; done
    unshare -m bash -s -- "$tmp" <<'INNER'
set -euxo pipefail
tmp=$1
mount --make-rprivate /
mount --bind "$tmp/home" /home/steam
mount --bind "$tmp/runtime" /run/user/1000
chown -R 1000:1000 /home/steam "$tmp/runtime"
cleanup() {
    setpriv --keep-groups --reuid=1000 --regid=1000 -- python3 - <<'PY'
from pathlib import Path
import shutil
for root in (Path('/home/steam'), Path('/run/user/1000')):
    for item in root.iterdir():
        if item.is_dir() and not item.is_symlink():
            shutil.rmtree(item)
        else:
            item.unlink()
PY
    umount /run/user/1000
    umount /home/steam
    unlink "$tmp/bin/runuser"
    rmdir "$tmp/home" "$tmp/runtime" "$tmp/foreign-config" "$tmp/bin"
    unlink "$tmp/session-common.sh"
    unlink "$tmp/steamos-session-select"
    unlink "$tmp/ready"
    rmdir "$tmp"
}
trap cleanup EXIT
PATH="$tmp/bin:$PATH" \
    HOME=/root XDG_CONFIG_HOME="$tmp/foreign-config" XDG_RUNTIME_DIR=/run/user/0 \
    PS5_SESSION_CONFIG=/root/forbidden-session.conf PS5_SESSION_RUNTIME=/run/user/0 \
    PS5_SESSION_COMMON="$tmp/session-common.sh" \
    "$tmp/steamos-session-select" --default gamescope
config=/home/steam/.config/ps5-cachyos-tools/session.conf
grep -qx 'DEFAULT_SESSION=gamescope' "$config"
grep -qx 'NEXT_SESSION=' "$config"
[[ $(stat -c '%u:%g' "$config") == 1000:1000 ]]
[[ $(stat -c '%a' "$config") == 600 ]]
[[ $(stat -c '%u:%g' /home/steam/.config/ps5-cachyos-tools) == 1000:1000 ]]
[[ $(stat -c '%a' /home/steam/.config/ps5-cachyos-tools) == 700 ]]
[[ ! -e $tmp/foreign-config/ps5-cachyos-tools/session.conf ]]
[[ ! -e /root/forbidden-session.conf ]]
printf '%s\n' 'PASS: root selector dropped to steam, ignored foreign path overrides, and wrote owner 1000:1000 mode 600'
INNER
    exit
fi

repo=$(cd "$(dirname "$0")/.." && pwd)
[[ $(id -u) == 1000 && $(id -g) == 1000 && -d /run/user/1000 ]] || {
    printf '%s\n' 'SKIP: test requires the steam account UID/GID 1000 and /run/user/1000'
    exit 0
}
subuid_base=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subuid)
subgid_base=$(awk -F: -v user="$(id -un)" '$1 == user { print $2; exit }' /etc/subgid)
for tool in unshare newuidmap newgidmap setpriv; do
    command -v "$tool" >/dev/null || { printf 'SKIP: %s unavailable\n' "$tool"; exit 0; }
done
[[ $subuid_base =~ ^[0-9]+$ && $subgid_base =~ ^[0-9]+$ ]] || {
    printf '%s\n' 'SKIP: subordinate UID/GID ranges are unavailable'
    exit 0
}

tmp=$(mktemp -d /tmp/ps5-session-rootless.XXXXXX)
chmod 0755 "$tmp"
mkdir -p "$tmp/home/.config/ps5-cachyos-tools" "$tmp/runtime" "$tmp/foreign-config" "$tmp/bin"
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=\n' > "$tmp/home/.config/ps5-cachyos-tools/session.conf"
chmod 0700 "$tmp/home/.config/ps5-cachyos-tools"
chmod 0600 "$tmp/home/.config/ps5-cachyos-tools/session.conf"
cp "$repo/modules/session/files/session-common.sh" "$tmp/session-common.sh"
cp "$repo/modules/session/files/steamos-session-select" "$tmp/steamos-session-select"
chmod 0755 "$tmp/steamos-session-select"
cat > "$tmp/bin/runuser" <<'RUNUSER'
#!/usr/bin/env bash
[[ $1 == -u && $2 == steam && $3 == -- ]] || exit 90
shift 3
export HOME=/home/steam USER=steam LOGNAME=steam
exec /usr/bin/setpriv --keep-groups --reuid=1000 --regid=1000 -- "$@"
RUNUSER
chmod 0755 "$tmp/bin/runuser"
chmod 0700 "$tmp/runtime"

unshare -U --fork "$0" --namespace "$tmp" &
pid=$!
sleep 0.1
newuidmap "$pid" 0 1000 1 1000 "$subuid_base" 1
printf 'deny\n' > "/proc/$pid/setgroups"
newgidmap "$pid" 0 1000 1 1000 "$subgid_base" 1
touch "$tmp/ready"
wait "$pid"
