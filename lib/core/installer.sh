#!/usr/bin/env bash
set -u

core_install_body() {
    local root=$1 repo=$2 module=${3-} moddir id hook path lock_dir target rc core_src fan_src requires_boot order type
    [ -d "$repo/lib/core" ] && core_src="$repo/lib/core" || core_src="$repo/core"
    [ -f "$repo/lib/modules/fan.sh" ] && fan_src="$repo/lib/modules/fan.sh" || fan_src="$repo/modules/fan.sh"
    CORE_CONFIG_ROOT=${CORE_CONFIG_ROOT:-$root}
    for path in /usr /usr/lib /usr/local /usr/local/bin /etc /etc/ps5-fan /etc/systemd /etc/systemd/system /etc/udev /etc/udev/rules.d /var /var/lib /var/lib/ps5-cachyos-tools /run /run/ps5-cachyos-tools; do core_target_assert_parents "$root" "$path" || return 1; done
    lock_dir="$root/run/ps5-cachyos-tools"; mkdir -p "$lock_dir" || return 1; exec 8>"$lock_dir/install.lock"; flock -n 8 || { core_log 'installazione già attiva'; return 1; }
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/core >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/modules >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/systemd >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/lib/modules >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/bin >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/lib/ps5-cachyos-tools/config/profiles >/dev/null || return 1
    core_target_prepare_dir "$root" /usr/local/bin >/dev/null || return 1
    core_target_prepare_dir "$root" /etc/systemd/system >/dev/null || return 1
    core_target_prepare_dir "$root" /etc/systemd/system/multi-user.target.wants >/dev/null || return 1
    core_target_prepare_dir "$root" /var/lib/ps5-cachyos-tools/state/modules >/dev/null || return 1
    core_target_prepare_dir "$root" /run/ps5-cachyos-tools >/dev/null || return 1
    chmod 700 "$root/var/lib/ps5-cachyos-tools/state/modules" || return 1
    for file in log.sh target.sh registry.sh dependencies.sh state.sh boot-runner.sh installer.sh service.sh; do
        target=$(core_target_path "$root" "/usr/lib/ps5-cachyos-tools/core/$file") || return 1
        install -m 0755 "$core_src/$file" "$target" || return 1
    done
    target=$(core_target_path "$root" /usr/lib/ps5-cachyos-tools/boot-runner) || return 1
    install -m 0755 "$core_src/boot-runner.sh" "$target" || return 1
    target=$(core_target_path "$root" /usr/lib/ps5-cachyos-tools/modules/fan.sh) || return 1
    install -m 0755 "$fan_src" "$target" || return 1
    install -m 0755 "$fan_src" "$root/usr/lib/ps5-cachyos-tools/lib/modules/fan.sh" || return 1
    for path in ps5-fan ps5-fan-daemon ps5-temp; do install -m 0755 "$repo/bin/$path" "$root/usr/lib/ps5-cachyos-tools/bin/$path" || return 1; done
    install -m 0644 "$repo/config/fan.conf" "$root/usr/lib/ps5-cachyos-tools/config/fan.conf" || return 1
    for path in "$repo"/config/profiles/*.conf; do [ -f "$path" ] || continue; install -m 0644 "$path" "$root/usr/lib/ps5-cachyos-tools/config/profiles/$(basename "$path")" || return 1; done
    target=$(core_target_path "$root" /usr/local/bin/ps5-cachyos-tools) || return 1
    install -m 0755 "$repo/bin/ps5-cachyos-tools" "$target" || return 1
    for path in "$repo"/systemd/ps5-tools-*.service; do
        [ -f "$path" ] || continue
        install -m 0644 "$path" "$root/usr/lib/ps5-cachyos-tools/systemd/$(basename "$path")" || return 1
    done
    for path in ps5-fan-daemon.service 99-ps5-fan.rules; do
        [ -f "$repo/systemd/$path" ] && install -m 0644 "$repo/systemd/$path" "$root/usr/lib/ps5-cachyos-tools/systemd/$path" || return 1
    done
    printf '%s\n' "$(date +%s)-$(id -u)-$root" > "$root/var/lib/ps5-cachyos-tools/install.identity"
    core_registry_discover "$repo/modules" >/dev/null || return 1
    core_registry_validate_dependencies || return 1
    order=$(core_registry_order) || return 1
    [ -z "$module" ] || [ "${CORE_MODULE[$module]+x}" = x ] || { core_log "modulo sconosciuto: $module"; return 1; }
    while IFS= read -r id; do [ -n "$id" ] || continue; moddir="$repo/modules/$id"
        [ -d "$moddir" ] || return 1
        [ -z "$module" ] || [ "$module" = "$id" ] || continue
        [ -f "$moddir/module.conf" ] && [ ! -L "$moddir/module.conf" ] || return 1
        for hook in install.sh boot.sh check.sh remove.sh; do [ ! -L "$moddir/$hook" ] || { core_log "hook symlink non trusted: $id/$hook"; return 1; }; done
        CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
        [ "${CORE_MODULE[$id]+x}" = x ] || return 1
        requires_boot=$(core_registry_field "$id" 9)
        type=$(core_registry_field "$id" 2)
        if [ "$requires_boot" = true ]; then
            if [ -z "${CORE_BOOT_TARGET:-}" ] && [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ -d /boot ]; then CORE_BOOT_TARGET=/boot; fi
            [ -n "${CORE_BOOT_TARGET:-}" ] || { core_log "modulo $id richiede --boot"; return 1; }
            [ -d "$CORE_BOOT_TARGET" ] || { core_log "partizione boot non disponibile: $CORE_BOOT_TARGET"; return 1; }
        fi
        [ -x "$moddir/install.sh" ] || { core_log "install hook obbligatorio assente: $id"; return 1; }
        [ "$type" != task ] || [ -x "$moddir/boot.sh" ] || { core_log "boot hook obbligatorio assente: $id"; return 1; }
        mkdir -p "$root/usr/lib/ps5-cachyos-tools/modules/$id"; cp -a "$moddir/module.conf" "$root/usr/lib/ps5-cachyos-tools/modules/$id/" || return 1
        for hook in install.sh boot.sh check.sh remove.sh; do
            if [ -e "$moddir/$hook" ]; then
                [ -f "$moddir/$hook" ] && [ ! -L "$moddir/$hook" ] || { core_log "hook non regolare: $id/$hook"; return 1; }
                target=$(core_target_path "$root" "/usr/lib/ps5-cachyos-tools/modules/$id/$hook") || return 1
                install -m 0755 "$moddir/$hook" "$target" || { core_log "installazione hook fallita: $id/$hook"; return 1; }
            fi
        done
        enabled=$(core_registry_field "$id" 1)
        if [ "$enabled" = true ] || [ -n "$module" ]; then
            if [ -x "$moddir/install.sh" ]; then
                CORE_REPO="$repo" CORE_INSTALL_MODE="${CORE_INSTALL_MODE:-offline}" CORE_TARGET_ROOT="$root" CORE_BOOT_TARGET="${CORE_BOOT_TARGET:-}" CORE_MODULE_ID="$id" CORE_DRY_RUN=0 "$moddir/install.sh" "$root"; rc=$?
                [ "$rc" -eq 0 ] || { core_log "install hook fallito: $id (rc=$rc)"; return "$rc"; }
            fi
        fi
        [ "$type" != service ] || core_service_module_install "$root" "$repo" "$id" || return 1
    done <<< "$order"
    core_service_install "$root" "$repo" || return 1
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload || return 1
        systemctl enable ps5-tools-early.service ps5-tools-boot.service || return 1
    fi
}

core_txn_snapshot() {
    local root=$1 backup=$2 repo=$3 path id owned
    : > "$backup/.paths" || return 1
    for path in /usr/lib/ps5-cachyos-tools /usr/local/bin/ps5-cachyos-tools /etc/systemd/system/ps5-tools-early.service /etc/systemd/system/ps5-tools-boot.service /etc/systemd/system/multi-user.target.wants/ps5-tools-early.service /etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service /var/lib/ps5-cachyos-tools/install.identity; do
        printf '%s\n' "$path" >> "$backup/.paths" || return 1
    done
    CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
    for id in "${CORE_MODULE_IDS[@]}"; do
        owned=$(core_registry_field "$id" 10)
        for path in $owned; do printf '%s\n' "$path" >> "$backup/.paths" || return 1; done
    done
    sort -u "$backup/.paths" -o "$backup/.paths" || return 1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        core_target_assert_parents "$root" "$path" || return 1
        if [ -e "$root$path" ] || [ -L "$root$path" ]; then
            mkdir -p "$backup$(dirname "$path")" || return 1
            cp -a -- "$root$path" "$backup$path" || return 1
            printf '%s\n' "$path" >> "$backup/.present" || return 1
        fi
    done < "$backup/.paths"
}

core_txn_restore() {
    local root=$1 backup=$2 path result=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        rm -rf -- "$root$path" || result=1
        if grep -Fxq "$path" "$backup/.present" 2>/dev/null; then
            mkdir -p "$root$(dirname "$path")" || result=1
            cp -a -- "$backup$path" "$root$path" || result=1
        fi
    done < "$backup/.paths"
    return "$result"
}

core_install_preflight() {
    local root=$1 repo=$2 module=${3-} id moddir type requires_boot unit order
    core_registry_discover "$repo/modules" >/dev/null || return 1
    core_registry_validate_dependencies || return 1
    order=$(core_registry_order) || return 1
    [ -z "$module" ] || [ "${CORE_MODULE[$module]+x}" = x ] || return 1
    while IFS= read -r id; do
        [ -n "$id" ] || continue; [ -z "$module" ] || [ "$module" = "$id" ] || continue
        moddir="$repo/modules/$id"; [ -d "$moddir" ] || return 1
        [ -x "$moddir/install.sh" ] || { core_log "install hook obbligatorio assente: $id"; return 1; }
        type=$(core_registry_field "$id" 2); [ "$type" != task ] || [ -x "$moddir/boot.sh" ] || { core_log "boot hook obbligatorio assente: $id"; return 1; }
        requires_boot=$(core_registry_field "$id" 9)
        [ "$requires_boot" != true ] || [ -n "${CORE_BOOT_TARGET:-}" ] || { core_log "modulo $id richiede --boot"; return 1; }
        unit=$(core_registry_field "$id" 7)
        [ -z "$unit" ] || [ -f "$repo/systemd/$unit" ] || [ -f "$repo/usr/lib/ps5-cachyos-tools/systemd/$unit" ] || { core_log "unit dichiarata assente: $id/$unit"; return 1; }
    done <<< "$order"
}

core_install() {
    local root=$1 backup path was_enabled=0 was_active=0
    CORE_CONFIG_ROOT=${CORE_CONFIG_ROOT:-$root}
    core_install_preflight "$root" "$2" "${3-}" || return 1
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        systemctl is-enabled --quiet ps5-tools-early.service && was_enabled=1 || true
        systemctl is-active --quiet ps5-tools-early.service && was_active=1 || true
    fi
    backup=$(mktemp -d "$root/.ps5-cachyos-tools-txn.XXXXXX") || return 1
    core_txn_snapshot "$root" "$backup" "$2" || { core_log 'snapshot transazione fallito'; rm -rf -- "$backup"; return 1; }
    if core_install_body "$@"; then
        rm -rf -- "$backup"
        return 0
    fi
    core_log 'installazione core fallita: rollback transazione'
    core_txn_restore "$root" "$backup" || core_log 'ROLLBACK_PARTIAL: ripristino artefatti transazione incompleto'
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload 2>/dev/null || true
        if [ "$was_enabled" -eq 1 ]; then systemctl enable ps5-tools-early.service ps5-tools-boot.service >/dev/null 2>&1 || true; else systemctl disable ps5-tools-early.service ps5-tools-boot.service >/dev/null 2>&1 || true; fi
        if [ "$was_active" -eq 1 ]; then systemctl start ps5-tools-early.service >/dev/null 2>&1 || true; else systemctl stop ps5-tools-early.service >/dev/null 2>&1 || true; fi
    fi
    rm -rf -- "$backup"
    return 1
}
