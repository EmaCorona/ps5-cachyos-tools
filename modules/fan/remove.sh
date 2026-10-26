#!/usr/bin/env bash
set -u
root=$1
fan_file="$root/usr/lib/ps5-cachyos-tools/fan.sh"; [ -f "$fan_file" ] && [ ! -L "$fan_file" ] || exit 1
source "$fan_file" 2>/dev/null || exit 1
if [ "${CORE_FRAMEWORK_MANAGED:-0}" = 1 ]; then
    module_fan_validate_write_set "$root" || exit 1
    module_fan_remove_user_files "$root" "${CORE_KEEP_CONFIG:-${2:-0}}" || exit 1
    if [ "${CORE_KEEP_CONFIG:-${2:-0}}" != 1 ]; then
        module_fan_rmdir_path "$root" /etc/ps5-fan/profiles || true
        module_fan_rmdir_path "$root" /etc/ps5-fan || true
    fi
else
    module_fan_remove "$root" "${CORE_KEEP_CONFIG:-${2:-0}}" || exit $?
fi
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" 2>/dev/null || exit 1
core_target_validate_final "$root" /var/lib/ps5-cachyos-tools/state/reapply/fan.request "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request" || exit 1
core_target_remove_path "$root" /var/lib/ps5-cachyos-tools/state/reapply/fan.request || exit 1
