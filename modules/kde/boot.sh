#!/usr/bin/env bash
set -u
root=$1
[ -x "$root/usr/local/bin/ps5-cachyos-tools-desktop-notify" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-kde-display-mode" ] && \
    [ -f "$root/etc/xdg/autostart/ps5-cachyos-tools-kde-display-mode.desktop" ] && \
    [ -f "$root/etc/profile.d/ps5-kde-environment.sh" ]
