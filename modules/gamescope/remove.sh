#!/usr/bin/env bash
set -u
root=$1
portal="$root/usr/share/xdg-desktop-portal/gamescope-portals.conf"
portal_state="$root/var/lib/ps5-cachyos-tools/gamescope/originals/portal.state"
portal_backup="$root/var/lib/ps5-cachyos-tools/gamescope/originals/portal.backup"
if [ -e "$portal_state" ] || [ -L "$portal_state" ]; then
    [ -f "$portal_state" ] && [ ! -L "$portal_state" ] && [ ! -L "$portal" ] || exit 1
    case "$(cat "$portal_state")" in
        present)
            [ -f "$portal_backup" ] && [ ! -L "$portal_backup" ] || exit 1
            tmp=$(mktemp "${portal%/*}/.gamescope-portal.XXXXXX") || exit 1
            cp -a -- "$portal_backup" "$tmp" && mv -f -- "$tmp" "$portal" || { rm -f -- "$tmp"; exit 1; } ;;
        absent) rm -f -- "$portal" || exit 1 ;;
        *) exit 1 ;;
    esac
    rm -f -- "$portal_state" "$portal_backup" || exit 1
    rmdir -- "$root/var/lib/ps5-cachyos-tools/gamescope/originals" 2>/dev/null || true
fi
if [ "${CORE_KEEP_CONFIG:-${2:-1}}" = 0 ]; then
    config="$root/etc/ps5-cachyos-tools/gamescope.conf"
    [ ! -L "$config" ] || exit 1
    rm -f -- "$config" || exit 1
    rmdir -- "$root/etc/ps5-cachyos-tools" 2>/dev/null || true
fi
exit 0
