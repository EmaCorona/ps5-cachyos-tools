#!/usr/bin/env bash
set -u
root=$1
pacman=${PS5_GAMESCOPE_PACMAN:-/usr/bin/pacman}
if [ "$root" = / ]; then
    "$pacman" -Q ps5-cachyos-gamescope >/dev/null 2>&1 || exit 1
    package_files=$("$pacman" -Ql ps5-cachyos-gamescope 2>/dev/null) || exit 1
else
    "$pacman" --sysroot "$root" -Q ps5-cachyos-gamescope >/dev/null 2>&1 || exit 1
    package_files=$("$pacman" --sysroot "$root" -Ql ps5-cachyos-gamescope 2>/dev/null) || exit 1
fi
printf '%s\n' "$package_files" | grep -Fq ' /usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope' || exit 1
grep -qx 'upstream_commit=e6674a98118ca7b098b98a3874b8f195ae1bf750' "$root/usr/share/ps5-cachyos-tools/gamescope/build-info" || exit 1
[ -x "$root/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope" ] && \
    [ -d "$root/usr/lib/ps5-cachyos-tools/gamescope/share/gamescope/scripts" ] && \
    [ -x "$root/usr/local/libexec/ps5-cachyos-tools/gamescope-session" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-gamescope-display-mode" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-video-diag" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" ] && \
    [ -x "$root/usr/local/bin/ps5-cachyos-tools-drm-setup" ] && \
    [ -x "$root/usr/bin/python3" ] && \
    [ -f "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf" ] && \
    [ -f "$root/etc/ps5-cachyos-tools/gamescope.conf" ] && \
    [ ! -L "$root/etc/ps5-cachyos-tools/gamescope.conf" ]
