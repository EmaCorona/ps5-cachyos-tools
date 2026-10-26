#!/usr/bin/env bash
set -u
root=$1
source "$root/usr/local/libexec/ps5-cachyos-tools/vram-common.sh" || exit 1
vram_config_read "$root/etc/ps5-cachyos-tools/vram.conf" >/dev/null
