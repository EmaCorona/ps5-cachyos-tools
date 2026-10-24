#!/usr/bin/env bash
set -u

CORE_PREFIX=${CORE_PREFIX:-/usr/lib/ps5-cachyos-tools}
CORE_MODULE_ROOT="$CORE_PREFIX/modules"
CORE_STATE_ROOT=${CORE_STATE_ROOT:-/}
CORE_RUN_ROOT=${CORE_RUN_ROOT:-/}
source "$CORE_PREFIX/core/log.sh"
source "$CORE_PREFIX/core/registry.sh"
source "$CORE_PREFIX/core/dependencies.sh"
source "$CORE_PREFIX/core/state.sh"

runner_load_registry() { core_registry_discover "$CORE_MODULE_ROOT" >/dev/null && core_registry_validate_dependencies; }
runner_lock() { mkdir -p "$CORE_RUN_ROOT/run/ps5-cachyos-tools"; exec 9>"$CORE_RUN_ROOT/run/ps5-cachyos-tools/runner.lock"; flock -n 9 || { core_log 'runner già attivo'; return 1; }; }
runner_module() {
    local id=$1 phase=$2 data enabled type policy boot_phase rev deps unit failure state boot hook rc
    enabled=$(core_registry_field "$id" 1); type=$(core_registry_field "$id" 2); policy=$(core_registry_field "$id" 3); boot_phase=$(core_registry_field "$id" 4); rev=$(core_registry_field "$id" 5); deps=$(core_registry_field "$id" 6); unit=$(core_registry_field "$id" 7); failure=$(core_registry_field "$id" 8)
    [ "$enabled" = true ] || { core_state_write "$CORE_STATE_ROOT" "$id" SKIPPED_DISABLED "$policy" "$rev" 0 "$(core_state_boot_id)"; return 0; }
    [ "$type" = task ] || return 0
    [ "$boot_phase" = "$phase" ] || return 0
    boot=$(core_state_boot_id)
    state=$(core_state_get "$CORE_STATE_ROOT" status "$id") || { core_state_write "$CORE_STATE_ROOT" "$id" FAILED "$policy" "$rev" 65 "$boot"; return 1; }
    if [ "$policy" = once ] && [ "$state" = SUCCESS ]; then
        [ "$(core_state_get "$CORE_STATE_ROOT" revision "$id")" = "$rev" ] && return 0
        core_log "$id: revisione aggiornata, riesecuzione automatica sospesa; usare reapply/reset"
        return 0
    fi
    [ "$(core_state_get "$CORE_STATE_ROOT" automatic_attempted_boot_id "$id")" = "$boot" ] && return 0
    for dep in $deps; do
        [ "$(core_registry_field "$dep" 1)" = true ] || { core_state_write "$CORE_STATE_ROOT" "$id" BLOCKED_DEPENDENCY "$policy" "$rev" 66 "$boot"; return 0; }
        dep_state=$(core_state_get "$CORE_STATE_ROOT" status "$dep" 2>/dev/null || true)
        dep_type=$(core_registry_field "$dep" 2)
        if [ "$dep_type" = task ] && [ "$dep_state" != SUCCESS ]; then core_state_write "$CORE_STATE_ROOT" "$id" BLOCKED_DEPENDENCY "$policy" "$rev" 66 "$boot"; return 0; fi
    done
    hook="$CORE_MODULE_ROOT/$id/boot.sh"; [ -x "$hook" ] || { core_state_write "$CORE_STATE_ROOT" "$id" FAILED "$policy" "$rev" 127 "$boot"; return 1; }
    core_state_write "$CORE_STATE_ROOT" "$id" RUNNING "$policy" "$rev" 0 "$boot" || return 1
    "$hook" "$CORE_STATE_ROOT" "$phase"; rc=$?
    if [ "$rc" -eq 0 ]; then core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot"; else core_state_write "$CORE_STATE_ROOT" "$id" FAILED "$policy" "$rev" "$rc" "$boot"; [ "$failure" = critical ] && return "$rc"; fi
    return 0
}
main() { { [ "$(id -u)" -eq 0 ] || [ "$CORE_STATE_ROOT" != / ]; } || return 1; local phase=${1:-normal} id order; case "$phase" in early|normal) ;; *) return 2;; esac; runner_lock || return 1; runner_load_registry || return 1; order=$(core_registry_order) || return 1; while IFS= read -r id; do [ -n "$id" ] || continue; runner_module "$id" "$phase" || return 1; done <<< "$order"; }
main "${1:-normal}"
