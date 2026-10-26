#!/usr/bin/env bash
set -u
root=$1
restore_original() {
    local target=$1 label=$2 state="$root/var/lib/ps5-cachyos-tools/session/originals/$2.state" backup="$root/var/lib/ps5-cachyos-tools/session/originals/$2.backup" tmp
    [ -f "$state" ] && [ ! -L "$state" ] || return 1
    case "$(cat "$state")" in
        present)
            [ -f "$backup" ] && [ ! -L "$backup" ] || return 1
            tmp=$(mktemp "${target%/*}/.ps5-session-restore.XXXXXX") || return 1
            cp -a -- "$backup" "$tmp" && mv -f -- "$tmp" "$target" || { rm -f -- "$tmp"; return 1; } ;;
        absent) rm -f -- "$target" || return 1 ;;
        *) return 1 ;;
    esac
    rm -f -- "$state" "$backup"
}
restore_original "$root/etc/profile.d/ps5-tty-session.sh" profile || exit 1
restore_original "$root/usr/bin/steamos-session-select" selector || exit 1
for saved in profile.state profile.backup selector.state selector.backup; do
    [ ! -L "$root/var/lib/ps5-cachyos-tools/session/originals/$saved" ] || exit 1
    rm -f -- "$root/var/lib/ps5-cachyos-tools/session/originals/$saved" || exit 1
done
rmdir -- "$root/var/lib/ps5-cachyos-tools/session/originals" 2>/dev/null || true
if [ "${CORE_KEEP_CONFIG:-${2:-1}}" = 0 ]; then
    config="$root/home/steam/.config/ps5-cachyos-tools/session.conf"
    [ ! -L "$config" ] || exit 1
    rm -f -- "$config" || exit 1
    rmdir -- "$root/home/steam/.config/ps5-cachyos-tools" 2>/dev/null || true
fi
exit 0
