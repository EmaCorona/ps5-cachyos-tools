#!/usr/bin/env bash
set -u
root=$1
profile="$root/etc/profile.d/ps5-tty-session.sh"
common="$root/usr/local/libexec/ps5-cachyos-tools/session-common.sh"
supervisor="$root/usr/local/libexec/ps5-cachyos-tools/session-supervisor"
config="$root/home/steam/.config/ps5-cachyos-tools/session.conf"
[ -f "$profile" ] && [ -x "$supervisor" ] && [ -x "$root/usr/bin/steamos-session-select" ] && \
    [ -f "$common" ] && [ -f "$config" ] && [ ! -L "$config" ] && \
    grep -q 'gamescope' "$supervisor" && grep -q 'FALLBACK' "$supervisor"
