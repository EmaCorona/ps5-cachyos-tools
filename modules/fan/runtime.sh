#!/usr/bin/env bash
set -u

root=${1:-/}
source "$CORE_REPO/lib/modules/fan.sh"
module_fan_runtime_changed "$root" "$CORE_REPO"
rc=$?
[ "$rc" -eq 2 ] && exit 0
exit "$rc"
