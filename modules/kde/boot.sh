#!/usr/bin/env bash
set -u
root=$1
[ -x "$root/usr/local/bin/ps5-cachyos-tools-desktop-notify" ] && [ -f "$root/etc/profile.d/ps5-kde-environment.sh" ]
