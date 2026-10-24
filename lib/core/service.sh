#!/usr/bin/env bash
set -u
CORE_SERVICE_FILE_CHANGED=0
CORE_SERVICE_WAS_ENABLED=0
CORE_SERVICE_WAS_ACTIVE=0
CORE_SERVICE_READINESS_STATUS=not-checked

core_service_snapshot_state() {
    local root=$1 id=$2 unit
    CORE_SERVICE_WAS_ENABLED=0; CORE_SERVICE_WAS_ACTIVE=0
    [ "$root" = / ] || return 0
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl is-enabled --quiet "$unit" && CORE_SERVICE_WAS_ENABLED=1 || true
    systemctl is-active --quiet "$unit" && CORE_SERVICE_WAS_ACTIVE=1 || true
}

core_service_transaction_snapshot() {
    local root=$1 requested=${2-} backup=$3 order id type unit enabled active present
    : > "$backup/.services" || return 1
    [ "$root" = / ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    order=$(core_registry_selection_order "$requested") || return 1
    for unit in ps5-tools-early.service ps5-tools-boot.service; do
        enabled=0; active=0
        systemctl is-enabled --quiet "$unit" && enabled=1 || true
        systemctl is-active --quiet "$unit" && active=1 || true
        printf '%s|%s|%s|%s\n' "$unit" "$enabled" "$active" "$(systemctl cat "$unit" >/dev/null 2>&1 && echo 1 || echo 0)" >> "$backup/.services" || return 1
    done
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        type=$(core_registry_field "$id" 2); [ "$type" = service ] || continue
        unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || continue
        enabled=0; active=0; present=0
        systemctl is-enabled --quiet "$unit" && enabled=1 || true
        systemctl is-active --quiet "$unit" && active=1 || true
        systemctl cat "$unit" >/dev/null 2>&1 && present=1 || true
        awk -F'|' -v wanted="$unit" '$1 == wanted { found=1; exit } END { exit found ? 0 : 1 }' "$backup/.services" || printf '%s|%s|%s|%s\n' "$unit" "$enabled" "$active" "$present" >> "$backup/.services" || return 1
    done <<< "$order"
}

core_service_transaction_restore() {
    local root=$1 backup=$2 unit enabled active present result=0
    [ "$root" = / ] || return 0
    [ -f "$backup/.services" ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl daemon-reload || result=1
    while IFS='|' read -r unit enabled active present; do
        [ -n "$unit" ] || continue
        if [ "$present" != 1 ]; then
            systemctl stop "$unit" >/dev/null 2>&1 || true
            systemctl disable "$unit" >/dev/null 2>&1 || true
            systemctl is-active --quiet "$unit" && result=1 || true
            systemctl is-enabled --quiet "$unit" && result=1 || true
            continue
        fi
        if [ "$enabled" = 1 ]; then systemctl enable "$unit" || result=1; else systemctl disable "$unit" || result=1; fi
        if [ "$active" = 1 ]; then systemctl start "$unit" || result=1; else systemctl stop "$unit" || result=1; fi
    done < "$backup/.services"
    return "$result"
}

core_service_stop() {
    local root=$1 id=$2 unit
    [ "$root" = / ] || return 0
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl stop "$unit" || return 1
    systemctl disable "$unit" || return 1
    systemctl daemon-reload || return 1
}

core_service_restore_state() {
    local root=$1 id=$2 unit result=0
    [ "$root" = / ] || return 0
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl daemon-reload || result=1
    if [ "$CORE_SERVICE_WAS_ENABLED" -eq 1 ]; then systemctl enable "$unit" || result=1; else systemctl disable "$unit" || result=1; fi
    if [ "$CORE_SERVICE_WAS_ACTIVE" -eq 1 ]; then systemctl start "$unit" || result=1; else systemctl stop "$unit" || result=1; fi
    return "$result"
}

core_service_reapply() {
    local root=$1 id=$2 unit dep dep_type policy revision boot rc=0 state_root run_root pre_pid=0 pre_cycles=0 pre_instance=''; state_root=${CORE_STATE_ROOT:-$root}; run_root=${CORE_RUN_ROOT:-$root}
    [ "$root" = / ] || return 1
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 1
    policy=$(core_registry_field "$id" 3); revision=$(core_registry_field "$id" 5); boot=$(core_state_boot_id)
    if declare -F core_txn_lock >/dev/null 2>&1; then core_txn_lock "$run_root" || return 1; fi
    local run_dir="$run_root/run/ps5-cachyos-tools" run_fd expected_run actual_run
    [ -d "$run_dir" ] && [ ! -L "$run_dir" ] || return 1
    exec {run_fd}<"$run_dir" || return 1; expected_run=$(realpath -e -- "$run_dir") || { exec {run_fd}<&-; return 1; }; actual_run=$(readlink -e -- "/proc/self/fd/$run_fd") || { exec {run_fd}<&-; return 1; }; [ "$actual_run" = "$expected_run" ] || { exec {run_fd}<&-; return 1; }
    exec 9>"/proc/self/fd/$run_fd/reapply.lock" || { exec {run_fd}<&-; return 1; }; exec {run_fd}<&-
    flock -n 9 || { core_log "reapply già attivo: $id"; return 1; }
    for dep in $(core_registry_field "$id" 6); do
        [ "$(core_registry_field "$dep" 1)" = true ] || { core_state_write "$state_root" "$id" BLOCKED_DEPENDENCY "$policy" "$revision" 66 "$boot"; return 1; }
        dep_type=$(core_registry_field "$dep" 2)
        if [ "$dep_type" = service ]; then
            systemctl is-active --quiet "$(core_registry_field "$dep" 7)" || { core_state_write "$state_root" "$id" BLOCKED_DEPENDENCY "$policy" "$revision" 66 "$boot"; return 1; }
        elif [ "$(core_state_get "$state_root" status "$dep")" != SUCCESS ]; then
            core_state_write "$state_root" "$id" BLOCKED_DEPENDENCY "$policy" "$revision" 66 "$boot"; return 1
        fi
    done
    core_service_snapshot_state / "$id"
    pre_pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || echo 0)
    pre_pid=${pre_pid:-0}
    if [ "$id" = fan ] && [ -r /run/ps5-fan/runtime.state ]; then
        pre_cycles=$(awk -F= '$1=="cycles"{print $2; exit}' /run/ps5-fan/runtime.state 2>/dev/null || echo 0)
        pre_instance=$(awk -F= '$1=="instance_id"{print $2; exit}' /run/ps5-fan/runtime.state 2>/dev/null || true)
    fi
    core_state_write "$state_root" "$id" RUNNING "$policy" "$revision" 0 "$boot" || return 1
    systemctl daemon-reload || rc=$?
    [ "$rc" -ne 0 ] || systemctl restart "$unit" || rc=$?
    [ "$rc" -ne 0 ] || systemctl is-active --quiet "$unit" || rc=1
    CORE_SERVICE_PRE_PID=$pre_pid CORE_SERVICE_PRE_CYCLES=$pre_cycles CORE_SERVICE_PRE_INSTANCE=$pre_instance CORE_SERVICE_RESTARTED=1 core_service_readiness "$root" "$id" || rc=1
    if [ "$rc" -eq 0 ]; then
        if ! core_state_write "$state_root" "$id" SUCCESS "$policy" "$revision" 0 "$boot"; then
            core_service_restore_state / "$id" || core_log "ROLLBACK_FILES_RESTORED_SERVICE_FAILED: service=$id"
            core_log "commit stato service fallito: rollback applicato per $id"
            return 1
        fi
    else
        core_state_write "$state_root" "$id" FAILED "$policy" "$revision" "$rc" "$boot" || true
        core_service_restore_state / "$id" || core_log "ROLLBACK_FILES_RESTORED_SERVICE_FAILED: service=$id"
        return "$rc"
    fi
}

core_service_source() {
    local repo=$1 unit=$2
    if [ -f "$repo/systemd/$unit" ] && [ ! -L "$repo/systemd/$unit" ]; then printf '%s\n' "$repo/systemd/$unit"; return 0; fi
    if [ -f "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit" ] && [ ! -L "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit" ]; then printf '%s\n' "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit"; return 0; fi
    return 1
}

core_service_readiness() {
    local root=$1 id=$2 hook rc
    CORE_SERVICE_READINESS_STATUS=not-checked
    [ "$root" = / ] || return 0
    hook=$(core_registry_field "$id" 11)
    [ -n "$hook" ] || return 0
    hook="${CORE_PREFIX:-/usr/lib/ps5-cachyos-tools}/modules/$id/$hook"
    [ -x "$hook" ] || { core_log "readiness hook assente: $id"; return 1; }
    local hook_fd expected actual current part
    expected=$(realpath -e -- "$hook") || return 1
    [ -f "$hook" ] && [ ! -L "$hook" ] || return 1
    current=/; IFS=/ read -ra hook_parts <<< "${hook#/}"; for part in "${hook_parts[@]}"; do [ -n "$part" ] || continue; current="${current%/}/$part"; [ "$current" = "$hook" ] && break; [ ! -L "$current" ] || return 1; done
    exec {hook_fd}<"$hook" || return 1
    actual=$(readlink -e -- "/proc/self/fd/$hook_fd") || { exec {hook_fd}<&-; return 1; }
    [ "$actual" = "$expected" ] || { exec {hook_fd}<&-; return 1; }
    [ ! -L "$hook" ] || { exec {hook_fd}<&-; return 1; }
    CORE_INSTALL_MODE=live CORE_MODULE_ID="$id" \
        CORE_SERVICE_PRE_PID="${CORE_SERVICE_PRE_PID:-0}" \
        CORE_SERVICE_PRE_CYCLES="${CORE_SERVICE_PRE_CYCLES:-0}" \
        CORE_SERVICE_PRE_INSTANCE="${CORE_SERVICE_PRE_INSTANCE:-}" \
        CORE_SERVICE_RESTARTED="${CORE_SERVICE_RESTARTED:-0}" \
        bash "/proc/self/fd/$hook_fd" "$root"; rc=$?; exec {hook_fd}<&-
    case "$rc" in
        0) CORE_SERVICE_READINESS_STATUS=ready; return 0 ;;
        2) CORE_SERVICE_READINESS_STATUS=degraded; core_log "readiness applicativa degradata: $id"; return 0 ;;
        *) CORE_SERVICE_READINESS_STATUS=failed; core_log "readiness check fallito: $id (rc=$rc)"; return "$rc" ;;
    esac
}

core_service_runtime_changed() {
    local root=$1 id=$2 marker; marker="${CORE_RUNTIME_CHANGED_FILE:-$root/run/ps5-cachyos-tools/runtime-changed/$id}"
    [ -f "$marker" ] && grep -qx '1' "$marker"
}

core_service_install_file() {
    local source=$1 target=$2 mode=$3 managed=${4:-0}
    [ -f "$source" ] || return 1
    if [ -f "$target" ]; then
        if cmp -s -- "$source" "$target" && [ "$(stat -c '%a' "$target" 2>/dev/null)" = "$mode" ]; then
            CORE_SERVICE_FILE_CHANGED=0
            return 0
        fi
        [ "$managed" = 1 ] || { core_log "unit esistente non posseduta: $target"; return 1; }
    fi
    [ ! -L "$target" ] || { core_log "target unit è un symlink estraneo: $target"; return 1; }
    install -m "$mode" -- "$source" "$target" || return 1
    CORE_SERVICE_FILE_CHANGED=1
}

core_service_enable_link() {
    local link=$1 target=$2 current
    if [ -L "$link" ]; then
        current=$(readlink -- "$link") || return 1
        [ "$current" = "$target" ] || { core_log "symlink service non coerente: $link"; return 1; }
        return 0
    fi
    [ ! -e "$link" ] || { core_log "conflitto service non symlink: $link"; return 1; }
    ln -s -- "$target" "$link"
}

core_service_module_install() {
    local root=$1 repo=$2 id=$3 unit source target wants enabled runtime_changed=0 restarted=0 pre_pid=0 pre_cycles=0 pre_instance=''
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    source=$(core_service_source "$repo" "$unit") || return 1
    core_target_assert_parents "$root" "/etc/systemd/system/$unit" || return 1
    target="$root/etc/systemd/system/$unit"
    local managed=0 manifest
    for manifest in "$root"/usr/lib/ps5-cachyos-tools/modules/*/module.conf; do
        [ -f "$manifest" ] || continue
        grep -Eq "(^|[[:space:]])/etc/systemd/system/$unit([[:space:]]|$)" "$manifest" && managed=1
    done
    core_service_install_file "$source" "$target" 644 "$managed" || return 1
    core_service_runtime_changed "$root" "$id" && runtime_changed=1 || true
    enabled=$(core_registry_field "$id" 1)
    if [ "$enabled" != true ]; then
        if [ -L "$root/etc/systemd/system/multi-user.target.wants/$unit" ]; then
            [ "$(readlink -- "$root/etc/systemd/system/multi-user.target.wants/$unit")" = "/etc/systemd/system/$unit" ] || return 1
            rm -f -- "$root/etc/systemd/system/multi-user.target.wants/$unit" || return 1
        elif [ -e "$root/etc/systemd/system/multi-user.target.wants/$unit" ]; then
            return 1
        fi
        if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
            systemctl disable --now "$unit" || return 1
            systemctl is-enabled --quiet "$unit" && { core_log "service ancora enabled: $unit"; return 1; } || true
            systemctl is-active --quiet "$unit" && { core_log "service ancora active: $unit"; return 1; } || true
        fi
        return 0
    fi
    core_target_assert_parents "$root" "/etc/systemd/system/multi-user.target.wants" || return 1
    wants="$root/etc/systemd/system/multi-user.target.wants/$unit"
    core_service_enable_link "$wants" "/etc/systemd/system/$unit" || return 1
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && [ "${PS5_TOOLS_NO_START:-0}" != 1 ]; then
        if systemctl is-active --quiet "$unit"; then
            pre_pid=$(systemctl show -p MainPID --value "$unit" 2>/dev/null || echo 0)
            pre_pid=${pre_pid:-0}
            if [ "$id" = fan ] && [ -r /run/ps5-fan/runtime.state ]; then
                pre_cycles=$(awk -F= '$1=="cycles"{print $2; exit}' /run/ps5-fan/runtime.state 2>/dev/null || echo 0)
                pre_instance=$(awk -F= '$1=="instance_id"{print $2; exit}' /run/ps5-fan/runtime.state 2>/dev/null || true)
            fi
        fi
        systemctl daemon-reload || return 1
        systemctl enable "$unit" || return 1
        if [ "$CORE_SERVICE_FILE_CHANGED" -eq 1 ] || [ "$runtime_changed" -eq 1 ]; then
            systemctl restart "$unit" || return 1
            restarted=1
        else
            systemctl is-active --quiet "$unit" || { systemctl start "$unit" || return 1; restarted=1; }
        fi
        systemctl is-active --quiet "$unit" || { core_log "health check service fallito: $unit"; return 1; }
        CORE_SERVICE_PRE_PID=$pre_pid CORE_SERVICE_PRE_CYCLES=$pre_cycles CORE_SERVICE_PRE_INSTANCE=$pre_instance CORE_SERVICE_RESTARTED=$restarted
        core_service_readiness "$root" "$id" || return 1
    fi
}

core_service_module_remove() {
    local root=$1 id=$2 unit
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    declare -F core_target_validate_final >/dev/null || return 1
    core_target_validate_final "$root" "/etc/systemd/system/multi-user.target.wants/$unit" "$root/etc/systemd/system/multi-user.target.wants/$unit" || return 1
    core_target_validate_final "$root" "/etc/systemd/system/$unit" "$root/etc/systemd/system/$unit" || return 1
    if [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "$unit" || return 1
        systemctl daemon-reload || return 1
    fi
    [ ! -L "$root/etc/systemd/system/multi-user.target.wants/$unit" ] || [ "$(readlink "$root/etc/systemd/system/multi-user.target.wants/$unit")" = "/etc/systemd/system/$unit" ] || return 1
    rm -f -- "$root/etc/systemd/system/multi-user.target.wants/$unit" "$root/etc/systemd/system/$unit"
}

core_service_install() {
    local root=$1 repo=$2 path target
    for path in /etc/systemd/system /etc/systemd/system/multi-user.target.wants; do
        core_target_prepare_dir "$root" "$path" >/dev/null || return 1
    done
    for path in /etc/systemd/system/ps5-tools-early.service /etc/systemd/system/ps5-tools-boot.service; do
        core_target_assert_parents "$root" "$path" || return 1
        target="$root$path"
        core_service_install_file "$repo/systemd/${path##*/}" "$target" 644 1 || return 1
    done
    for path in ps5-tools-early.service ps5-tools-boot.service; do
        target="$root/etc/systemd/system/multi-user.target.wants/$path"
        core_service_enable_link "$target" "/etc/systemd/system/$path" || return 1
    done
}
