#!/usr/bin/env bash
set -u

CORE_PREFIX=${CORE_PREFIX:-/usr/lib/ps5-cachyos-tools}
CORE_MODULE_ROOT="$CORE_PREFIX/modules"
CORE_STATE_ROOT=${CORE_STATE_ROOT:-/}
CORE_RUN_ROOT=${CORE_RUN_ROOT:-/}
CORE_CONFIG_ROOT=${CORE_CONFIG_ROOT:-$CORE_STATE_ROOT}
CORE_REAPPLY_ID=${CORE_REAPPLY_ID:-}
source "$CORE_PREFIX/core/log.sh"
source "$CORE_PREFIX/core/registry.sh"
source "$CORE_PREFIX/core/dependencies.sh"
source "$CORE_PREFIX/core/state.sh"

runner_load_registry() { core_registry_discover "$CORE_MODULE_ROOT" >/dev/null && core_registry_validate_dependencies; }
runner_lock() { core_state_validate_path "$CORE_RUN_ROOT" /run/ps5-cachyos-tools || return 1; mkdir -p "$CORE_RUN_ROOT/run/ps5-cachyos-tools" || return 1; core_state_validate_path "$CORE_RUN_ROOT" /run/ps5-cachyos-tools || return 1; exec 7>"$CORE_RUN_ROOT/run/ps5-cachyos-tools/transaction.lock"; core_state_validate_path "$CORE_RUN_ROOT" /run/ps5-cachyos-tools || return 1; flock -n 7 || { core_log 'transazione amministrativa già attiva'; return 1; }; core_state_validate_path "$CORE_RUN_ROOT" /run/ps5-cachyos-tools || return 1; exec 9>"$CORE_RUN_ROOT/run/ps5-cachyos-tools/runner.lock"; core_state_validate_path "$CORE_RUN_ROOT" /run/ps5-cachyos-tools || return 1; flock -n 9 || { core_log 'runner già attivo'; return 1; }; }
runner_wait_service() {
    local unit=$1 attempt deadline=${CORE_RUNNER_DEADLINE:-0} now
    [ "$CORE_STATE_ROOT" = / ] || return 1
    [ "$deadline" -gt 0 ] || deadline=$(( $(date +%s) + ${CORE_SERVICE_WAIT_SEC:-30} ))
    for attempt in $(seq 1 "${CORE_SERVICE_WAIT_SEC:-30}"); do
        systemctl is-active --quiet "$unit" 2>/dev/null && return 0
        now=$(date +%s); [ "$now" -lt "$deadline" ] || break
        sleep 1
    done
    return 1
}
runner_record_failure() {
    local id=$1 status=$2 policy=$3 revision=$4 code=$5 boot=$6
    core_state_write "$CORE_STATE_ROOT" "$id" "$status" "$policy" "$revision" "$code" "$boot" || return 1
    [ "$policy" = critical ] && return "$code"
    return 0
}
runner_module() {
    local id=$1 phase=$2 data enabled type policy boot_phase rev deps unit failure state boot hook rc request=0 request_file dep_policy dep_rev request_id
    enabled=$(core_registry_field "$id" 1); type=$(core_registry_field "$id" 2); policy=$(core_registry_field "$id" 3); boot_phase=$(core_registry_field "$id" 4); rev=$(core_registry_field "$id" 5); deps=$(core_registry_field "$id" 6); unit=$(core_registry_field "$id" 7); failure=$(core_registry_field "$id" 8)
    [ -z "$CORE_REAPPLY_ID" ] || [ "$CORE_REAPPLY_ID" = "$id" ] || return 0
    request_file="$CORE_STATE_ROOT/var/lib/ps5-cachyos-tools/state/reapply/$id.request"
    core_state_validate_path "$CORE_STATE_ROOT" "/var/lib/ps5-cachyos-tools/state/reapply/$id.request" || return 1
    [ -n "$CORE_REAPPLY_ID" ] || [ -f "$request_file" ] || true
    [ -n "$CORE_REAPPLY_ID" ] || [ ! -f "$request_file" ] || request=1
    [ "$enabled" = true ] || { core_state_write "$CORE_STATE_ROOT" "$id" SKIPPED_DISABLED "$policy" "$rev" 0 "$(core_state_boot_id)"; return 0; }
    [ "$type" = task ] || return 0
    [ "$boot_phase" = "$phase" ] || return 0
    boot=$(core_state_boot_id)
    state=$(core_state_get "$CORE_STATE_ROOT" status "$id") || { core_state_write "$CORE_STATE_ROOT" "$id" FAILED "$policy" "$rev" 65 "$boot"; return 1; }
    if [ "$request" -eq 0 ] && [ -z "$CORE_REAPPLY_ID" ] && [ "$policy" = once ] && [ "$(core_state_get "$CORE_STATE_ROOT" completed_at "$id")" -gt 0 ] 2>/dev/null; then
        [ "$(core_state_get "$CORE_STATE_ROOT" completed_revision "$id")" = "$rev" ] && return 0
        core_log "$id: revisione aggiornata, riesecuzione automatica sospesa; usare reapply/reset"
        return 0
    fi
    request_id=$(awk -F= '$1=="requested_at"{print $2; exit}' "$request_file" 2>/dev/null || true)
    if [ "$request" -eq 1 ] && [ -n "$request_id" ] &&
       [ "$(core_state_get "$CORE_STATE_ROOT" status "$id")" = SUCCESS ] &&
       [ "$(core_state_get "$CORE_STATE_ROOT" completed_revision "$id")" = "$rev" ] &&
       [ "$(core_state_get "$CORE_STATE_ROOT" reapply_applied_id "$id")" = "$request_id" ]; then
        core_state_validate_path "$CORE_STATE_ROOT" "/var/lib/ps5-cachyos-tools/state/reapply/$id.request" || return 1
        rm -f -- "$request_file" || return 1
        core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot" || return 1
        return 0
    fi
    if [ "$request" -eq 1 ] && [ "$(core_state_get "$CORE_STATE_ROOT" status "$id")" = APPLIED ] &&
       [ "$(core_state_get "$CORE_STATE_ROOT" revision "$id")" = "$rev" ] &&
       [ -n "$request_id" ] && [ "$(core_state_get "$CORE_STATE_ROOT" reapply_applied_id "$id")" = "$request_id" ]; then
            core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot" || return 1
            core_state_validate_path "$CORE_STATE_ROOT" "/var/lib/ps5-cachyos-tools/state/reapply/$id.request" || return 1
            rm -f -- "$request_file" || return 1
            core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot" || return 1
            return 0
    fi
    [ "$request" -eq 1 ] || [ -n "$CORE_REAPPLY_ID" ] || [ "$(core_state_get "$CORE_STATE_ROOT" automatic_attempted_boot_id "$id")" != "$boot" ] || return 0
    for dep in $deps; do
        [ "$(core_registry_field "$dep" 1)" = true ] || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
        dep_state=$(core_state_get "$CORE_STATE_ROOT" status "$dep" 2>/dev/null || true)
        dep_type=$(core_registry_field "$dep" 2)
        if [ "$dep_type" = task ]; then
            dep_policy=$(core_registry_field "$dep" 3); dep_rev=$(core_registry_field "$dep" 5)
            if [ "$dep_policy" = once ]; then
                [ "$(core_state_get "$CORE_STATE_ROOT" completed_at "$dep")" -gt 0 ] 2>/dev/null || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
                [ "$(core_state_get "$CORE_STATE_ROOT" completed_revision "$dep")" = "$dep_rev" ] || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
                [ ! -f "$CORE_STATE_ROOT/var/lib/ps5-cachyos-tools/state/reapply/$dep.request" ] || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
            else
                [ "$dep_state" = SUCCESS ] || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
                [ "$(core_state_get "$CORE_STATE_ROOT" last_boot_id "$dep")" = "$boot" ] || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
            fi
        elif [ "$dep_type" = service ]; then
            if [ "$CORE_STATE_ROOT" = / ]; then
                runner_wait_service "$(core_registry_field "$dep" 7)" || { runner_record_failure "$id" BLOCKED_DEPENDENCY "$failure" "$rev" 66 "$boot"; return $?; }
            fi
        fi
    done
    hook="$CORE_MODULE_ROOT/$id/boot.sh"; [ -x "$hook" ] || { runner_record_failure "$id" FAILED "$failure" "$rev" 127 "$boot"; return $?; }
    core_state_write "$CORE_STATE_ROOT" "$id" RUNNING "$policy" "$rev" 0 "$boot" || return 1
    CORE_INSTALL_MODE=live CORE_TARGET_ROOT="$CORE_STATE_ROOT" CORE_MODULE_ID="$id" CORE_BOOT_PHASE="$phase" "$hook" "$CORE_STATE_ROOT" "$phase"; rc=$?
    if [ "$rc" -eq 0 ]; then
        if [ "$request" -eq 1 ]; then
            core_state_write "$CORE_STATE_ROOT" "$id" APPLIED "$policy" "$rev" 0 "$boot" || return 1
        fi
        core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot" || return 1
        if [ "$request" -eq 1 ]; then
            if core_state_validate_path "$CORE_STATE_ROOT" "/var/lib/ps5-cachyos-tools/state/reapply/$id.request" && rm -f -- "$request_file"; then
                core_state_write "$CORE_STATE_ROOT" "$id" SUCCESS "$policy" "$rev" 0 "$boot" || { core_log "$id: richiesta consumata ma stato da riconciliare"; printf 'id=%s\nphase=%s\nrevision=%s\nrequested_at=%s\n' "$id" "$phase" "$rev" "$(date +%s)" > "$request_file"; return 1; }
            else
                core_log "$id: impossibile consumare la richiesta di reapply"; return 1
            fi
        fi
    else core_state_write "$CORE_STATE_ROOT" "$id" FAILED "$policy" "$rev" "$rc" "$boot" || return 1; [ "$failure" = critical ] && return "$rc"; fi
    return 0
}
main() { if [ "$(id -u)" -ne 0 ]; then case "${CORE_TEST_MODE:-0}:$CORE_STATE_ROOT:$CORE_RUN_ROOT" in 1:/tmp/ps5-tools-core.*:/tmp/ps5-tools-core.*) ;; *) core_log 'runner richiede root'; return 1;; esac; fi; local phase=${1:-normal} id order; case "$phase" in early|normal) ;; *) return 2;; esac; CORE_RUNNER_DEADLINE=${CORE_RUNNER_DEADLINE:-$(( $(date +%s) + ${CORE_RUNNER_BUDGET_SEC:-60} ))}; runner_lock || return 1; runner_load_registry || return 1; order=$(core_registry_order) || return 1; while IFS= read -r id; do [ -n "$id" ] || continue; runner_module "$id" "$phase" || return 1; done <<< "$order"; }
main "${1:-normal}"
