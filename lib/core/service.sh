#!/usr/bin/env bash
set -u
CORE_SERVICE_FILE_CHANGED=0
CORE_SERVICE_WAS_ENABLED=0
CORE_SERVICE_WAS_ACTIVE=0

core_service_snapshot_state() {
    local root=$1 id=$2 unit
    CORE_SERVICE_WAS_ENABLED=0; CORE_SERVICE_WAS_ACTIVE=0
    [ "$root" = / ] || return 0
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 0
    systemctl is-enabled --quiet "$unit" && CORE_SERVICE_WAS_ENABLED=1 || true
    systemctl is-active --quiet "$unit" && CORE_SERVICE_WAS_ACTIVE=1 || true
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

core_service_source() {
    local repo=$1 unit=$2
    if [ -f "$repo/systemd/$unit" ]; then printf '%s\n' "$repo/systemd/$unit"; return 0; fi
    if [ -f "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit" ]; then printf '%s\n' "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit"; return 0; fi
    return 1
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
    local root=$1 repo=$2 id=$3 unit source target wants
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
    core_target_assert_parents "$root" "/etc/systemd/system/multi-user.target.wants" || return 1
    wants="$root/etc/systemd/system/multi-user.target.wants/$unit"
    core_service_enable_link "$wants" "/etc/systemd/system/$unit" || return 1
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && [ "${PS5_TOOLS_NO_START:-0}" != 1 ]; then
        systemctl daemon-reload || return 1
        systemctl enable "$unit" || return 1
        if [ "$CORE_SERVICE_FILE_CHANGED" -eq 1 ]; then systemctl restart "$unit" 2>/dev/null || systemctl start "$unit" || return 1; else systemctl is-active --quiet "$unit" || systemctl start "$unit" || return 1; fi
        systemctl is-active --quiet "$unit" || { core_log "health check service fallito: $unit"; return 1; }
    fi
}

core_service_module_remove() {
    local root=$1 id=$2 unit
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
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
