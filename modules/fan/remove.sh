#!/usr/bin/env bash
set -u
root=$1
source "$root/usr/lib/ps5-cachyos-tools/fan.sh" 2>/dev/null || exit 1
module_fan_remove "$root" "${CORE_KEEP_CONFIG:-${2:-0}}"
