#!/usr/bin/env bash
set -u

root=$1
keep=${2:-1}
conf="$root/etc/ps5-cachyos-tools/boot-cleanup.conf"
[ -d "$root" ] && [ ! -L "$root" ] || exit 1
[ ! -L "$root/etc" ] && [ ! -L "$root/etc/ps5-cachyos-tools" ] || exit 1
if [ "$keep" = 0 ]; then
    [ ! -L "$conf" ] || exit 1
    rm -f -- "$conf" || exit 1
fi
exit 0
