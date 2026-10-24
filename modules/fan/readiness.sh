#!/usr/bin/env bash
set -u

root=${1:-/}
source "$root/usr/lib/ps5-cachyos-tools/fan.sh" 2>/dev/null || exit 1

module_fan_wait_ready "$root" "${CORE_SERVICE_READINESS_TIMEOUT:-30}" \
    "${CORE_SERVICE_PRE_PID:-0}" "${CORE_SERVICE_PRE_CYCLES:-0}" \
    "${CORE_SERVICE_PRE_INSTANCE:-}" "${CORE_SERVICE_RESTARTED:-0}"
