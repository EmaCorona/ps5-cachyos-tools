#!/usr/bin/env bash
set -u
root=$1
fan_file="$root/usr/lib/ps5-cachyos-tools/fan.sh"; [ -f "$fan_file" ] && [ ! -L "$fan_file" ] || exit 1
source "$fan_file" 2>/dev/null || exit 1
CORE_FRAMEWORK_MANAGED=1 module_fan_remove "$root" "${CORE_KEEP_CONFIG:-${2:-0}}" || exit $?
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" 2>/dev/null || exit 1
core_target_validate_final "$root" /var/lib/ps5-cachyos-tools/state/reapply/fan.request "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request" || exit 1
core_target_remove_path "$root" /var/lib/ps5-cachyos-tools/state/reapply/fan.request || exit 1
