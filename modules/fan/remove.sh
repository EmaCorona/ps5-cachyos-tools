#!/usr/bin/env bash
set -u
root=$1
source "$root/usr/lib/ps5-cachyos-tools/fan.sh" 2>/dev/null || exit 1
module_fan_remove "$root" "${CORE_KEEP_CONFIG:-${2:-0}}" || exit $?
if [ "${CORE_FRAMEWORK_MANAGED:-0}" = 1 ]; then
    rm -f -- "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request" || exit 1
fi
