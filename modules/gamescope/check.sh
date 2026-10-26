#!/usr/bin/env bash
set -u
root=$1
[ -x "$root/usr/local/libexec/ps5-cachyos-tools/gamescope-session" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-video-diag" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-drm-setup" ] && \
    [ -f "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf" ] && \
    [ -f "$root/etc/ps5-cachyos-tools/gamescope.conf" ] && \
    [ ! -L "$root/etc/ps5-cachyos-tools/gamescope.conf" ]
