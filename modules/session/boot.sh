#!/usr/bin/env bash
set -u
root=$1
[ -x "$root/usr/local/libexec/ps5-cachyos-tools/session-supervisor" ] && \
    [ -x "$root/usr/bin/steamos-session-select" ] && \
    [ -f "$root/home/steam/.config/ps5-cachyos-tools/session.conf" ] && \
    [ ! -L "$root/home/steam/.config/ps5-cachyos-tools/session.conf" ]
