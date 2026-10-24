#!/usr/bin/env bash
set -u
root=$1
fan_file="$root/usr/lib/ps5-cachyos-tools/fan.sh"; [ -f "$fan_file" ] && [ ! -L "$fan_file" ] || exit 1
source "$fan_file" 2>/dev/null || exit 1
module_fan_check "$root"
