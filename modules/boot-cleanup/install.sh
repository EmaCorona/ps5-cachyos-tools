#!/usr/bin/env bash
set -u

root=$1
conf="$root/etc/ps5-cachyos-tools/boot-cleanup.conf"
[ -d "$root" ] && [ ! -L "$root" ] || exit 1
for dir in "$root/etc" "$root/etc/ps5-cachyos-tools" "$root/run" "$root/run/ps5-cachyos-tools"; do
    [ ! -L "$dir" ] || exit 1
    mkdir -p -- "$dir" || exit 1
done
if [ ! -e "$conf" ]; then
    umask 077
    tmp=$(mktemp "$root/etc/ps5-cachyos-tools/.boot-cleanup.conf.XXXXXX") || exit 1
    printf '%s\n' '# Steam stale records: pid starttime uid artifact command reason owner' 'STEAM_STALE_FILE=/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list' 'DRY_RUN=0' > "$tmp" || { rm -f -- "$tmp"; exit 1; }
    chmod 0640 "$tmp" && mv -f -- "$tmp" "$conf" || { rm -f -- "$tmp"; exit 1; }
fi
[ -f "$conf" ] && [ ! -L "$conf" ] || exit 1
exit 0
