#!/usr/bin/env bash
set -u

core_txn_lock() {
    local root=$1 lock_dir="$1/run/ps5-cachyos-tools"
    core_target_prepare_dir "$root" /run/ps5-cachyos-tools >/dev/null || return 1
    core_target_validate_final "$root" /run/ps5-cachyos-tools "$root/run/ps5-cachyos-tools" || return 1
    [ -d "$lock_dir" ] && [ ! -L "$lock_dir" ] || return 1
    core_target_validate_final "$root" /run/ps5-cachyos-tools "$lock_dir" || return 1
    exec 10<"$lock_dir" || return 1
    [ "$(readlink -e /proc/self/fd/10 2>/dev/null)" = "$(realpath -e -- "$lock_dir" 2>/dev/null)" ] || { exec 10<&-; return 1; }
    exec 8>"/proc/self/fd/10/transaction.lock" || { exec 10<&-; return 1; }; exec 10<&-
    flock -n 8 || { core_log 'transazione già attiva'; return 1; }
}

core_install_copy() {
    local source=$1 target=$2 mode=$3 source_id target_id root path
    [ -f "$source" ] || return 1
    [ ! -L "$source" ] || return 1
    if [ -f "$target" ] && [ ! -L "$target" ]; then
        source_id=$(stat -c '%d:%i' -- "$source" 2>/dev/null) || return 1
        target_id=$(stat -c '%d:%i' -- "$target" 2>/dev/null) || return 1
        if [ "$source_id" = "$target_id" ]; then
            root=${CORE_CONFIG_ROOT:-/}; path=${target#"$root"}; [ "$root" = / ] && path=$target; core_target_chmod "$root" "$path" "$mode" || return 1
            return 0
        fi
    fi
    if [ -f "$target" ] && cmp -s -- "$source" "$target"; then
        root=${CORE_CONFIG_ROOT:-/}; path=${target#"$root"}; [ "$root" = / ] && path=$target; core_target_chmod "$root" "$path" "$mode" || return 1
        return 0
    fi
    [ ! -L "$target" ] || { core_log "target install symlink non autorizzato: $target"; return 1; }
    root=${CORE_CONFIG_ROOT:-/}; path=${target#"$root"}; [ "$root" = / ] && path=$target
    core_target_copy_file "$root" "$path" "$source" && core_target_chmod "$root" "$path" "$mode"
}

core_install_module_valid() {
    local root=$1 repo=$2 id=$3 path source target unit check unknown post_install_hook post_remove_hook
    local target_conf="$root/usr/lib/ps5-cachyos-tools/modules/$id/module.conf"
    [ -f "$target_conf" ] && [ ! -L "$target_conf" ] && cmp -s -- "$repo/modules/$id/module.conf" "$target_conf" || return 1
    [ "$(stat -c '%a' "$target_conf" 2>/dev/null)" = 644 ] || return 1
    post_install_hook=$(core_registry_field "$id" 16)
    post_remove_hook=$(core_registry_field "$id" 17)
    for path in install.sh boot.sh check.sh remove.sh readiness.sh runtime.sh recover.sh post-install.sh "$post_install_hook" "$post_remove_hook"; do
        [ -n "$path" ] || continue
        source="$repo/modules/$id/$path"; target="$root/usr/lib/ps5-cachyos-tools/modules/$id/$path"
        if [ -e "$source" ]; then
            [ -f "$target" ] && [ ! -L "$target" ] && cmp -s -- "$source" "$target" || return 1
            [ "$(stat -c '%a' "$target" 2>/dev/null)" = 755 ] || return 1
        else
            [ ! -e "$target" ] && [ ! -L "$target" ] || return 1
        fi
    done
    for path in $(core_registry_field "$id" 10); do
        [ -e "$root$path" ] || [ -L "$root$path" ] || return 1
        case "$path" in
            /etc/systemd/system/multi-user.target.wants/*.service)
                unit=${path##*/}; [ -L "$root$path" ] && [ "$(readlink -- "$root$path")" = "/etc/systemd/system/$unit" ] || return 1 ;;
            /etc/systemd/system/*.service)
                unit=${path##*/}; source=$(core_service_source "$repo" "$unit") || return 1
                [ -f "$root$path" ] && [ ! -L "$root$path" ] && cmp -s -- "$source" "$root$path" || return 1
                [ "$(stat -c '%a' "$root$path" 2>/dev/null)" = 644 ] || return 1 ;;
            /usr/lib/ps5-cachyos-tools/fan.sh)
                source="$repo/lib/modules/fan.sh"; [ -f "$root$path" ] && cmp -s -- "$source" "$root$path" || return 1
                [ "$(stat -c '%a' "$root$path" 2>/dev/null)" = 755 ] || return 1 ;;
            /usr/lib/ps5-cachyos-tools/lib/modules/fan.sh)
                source="$repo/lib/modules/fan.sh"; [ -f "$root$path" ] && cmp -s -- "$source" "$root$path" || return 1
                [ "$(stat -c '%a' "$root$path" 2>/dev/null)" = 755 ] || return 1 ;;
            /usr/local/bin/ps5-fan|/usr/local/bin/ps5-fan-daemon|/usr/local/bin/ps5-temp)
                source="$repo/bin/${path##*/}"; [ -f "$root$path" ] && cmp -s -- "$source" "$root$path" || return 1
                [ "$(stat -c '%a' "$root$path" 2>/dev/null)" = 755 ] || return 1 ;;
            /etc/udev/rules.d/99-ps5-fan.rules)
                source="$repo/systemd/99-ps5-fan.rules"; [ -f "$root$path" ] && cmp -s -- "$source" "$root$path" || return 1
                [ "$(stat -c '%a' "$root$path" 2>/dev/null)" = 644 ] || return 1 ;;
        esac
    done
    check="$root/usr/lib/ps5-cachyos-tools/modules/$id/check.sh"
    if [ -x "$check" ]; then
        CORE_INSTALL_MODE=offline CORE_TARGET_ROOT="$root" CORE_MODULE_ID="$id" "$check" "$root" || return 1
    else
        unknown=0
        for path in $(core_registry_field "$id" 10); do
            case "$path" in
                /etc/systemd/system/*.service|/etc/systemd/system/multi-user.target.wants/*.service|/usr/lib/ps5-cachyos-tools/fan.sh|/usr/lib/ps5-cachyos-tools/lib/modules/fan.sh|/usr/local/bin/*|/etc/udev/rules.d/*) ;;
                *) unknown=1; break;;
            esac
        done
        [ "$unknown" -eq 0 ] || return 1
    fi
}

core_install_body() {
    local root=$1 repo=$2 module=${3-} moddir id hook path lock_dir target rc core_src fan_src requires_boot order type identity install_disabled readiness_hook runtime_hook post_install_hook post_remove_hook pre_order pre_id
    [ -d "$repo/lib/core" ] && core_src="$repo/lib/core" || core_src="$repo/core"
    [ -f "$repo/lib/modules/fan.sh" ] && fan_src="$repo/lib/modules/fan.sh" || fan_src="$repo/modules/fan.sh"
    CORE_CONFIG_ROOT=${CORE_CONFIG_ROOT:-$root}
    core_target_validate_final "$root" /run/ps5-cachyos-tools/runtime-changed "$root/run/ps5-cachyos-tools/runtime-changed" || return 1
    mkdir -p "$root/run/ps5-cachyos-tools/runtime-changed" || return 1
    CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
    for path in /usr /usr/lib /usr/local /usr/local/bin /etc /etc/ps5-fan /etc/systemd /etc/systemd/system /etc/udev /etc/udev/rules.d /var /var/lib /var/lib/ps5-cachyos-tools /run /run/ps5-cachyos-tools; do core_target_assert_parents "$root" "$path" || return 1; done
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
        core_install_copy "$core_src/$file" "$target" 755 || return 1
    done
    target=$(core_target_path "$root" /usr/lib/ps5-cachyos-tools/boot-runner) || return 1
    core_install_copy "$core_src/boot-runner.sh" "$target" 755 || return 1
    if [ -z "$module" ] || [ "$module" = fan ]; then
        target=$(core_target_path "$root" /usr/lib/ps5-cachyos-tools/modules/fan.sh) || return 1
        core_install_copy "$fan_src" "$target" 755 || return 1
        core_install_copy "$fan_src" "$root/usr/lib/ps5-cachyos-tools/lib/modules/fan.sh" 755 || return 1
        for path in ps5-fan ps5-fan-daemon ps5-temp; do core_install_copy "$repo/bin/$path" "$root/usr/lib/ps5-cachyos-tools/bin/$path" 755 || return 1; done
        core_install_copy "$repo/config/fan.conf" "$root/usr/lib/ps5-cachyos-tools/config/fan.conf" 644 || return 1
        for path in "$repo"/config/profiles/*.conf; do [ -f "$path" ] || continue; core_install_copy "$path" "$root/usr/lib/ps5-cachyos-tools/config/profiles/$(basename "$path")" 644 || return 1; done
    fi
    target=$(core_target_path "$root" /usr/local/bin/ps5-cachyos-tools) || return 1
    core_install_copy "$repo/bin/ps5-cachyos-tools" "$target" 755 || return 1
    core_install_copy "$repo/bin/ps5-cachyos-tools" "$root/usr/lib/ps5-cachyos-tools/bin/ps5-cachyos-tools" 755 || return 1
    for path in "$repo"/systemd/ps5-tools-*.service; do
        [ -f "$path" ] || continue
        core_install_copy "$path" "$root/usr/lib/ps5-cachyos-tools/systemd/$(basename "$path")" 644 || return 1
    done
    if [ -z "$module" ] || [ "$module" = fan ]; then
        for path in ps5-fan-daemon.service 99-ps5-fan.rules; do
            [ -f "$repo/systemd/$path" ] && core_install_copy "$repo/systemd/$path" "$root/usr/lib/ps5-cachyos-tools/systemd/$path" 644 || return 1
        done
    fi
    identity="$root/var/lib/ps5-cachyos-tools/install.identity"
    core_target_validate_final "$root" /var/lib/ps5-cachyos-tools/install.identity "$identity" || return 1
    if [ ! -f "$identity" ]; then
        core_target_write_file "$root" /var/lib/ps5-cachyos-tools/install.identity 600 "$(date +%s)-$(id -u)-$root" || return 1
    fi
    core_registry_validate_owned_paths || return 1
    core_registry_validate_dependencies || return 1
    [ -z "$module" ] || [ "${CORE_MODULE[$module]+x}" = x ] || { core_log "modulo sconosciuto: $module"; return 1; }
    pre_order=$(core_registry_selection_order "$module") || return 1
    while IFS= read -r pre_id; do
        [ -n "$pre_id" ] || continue
        runtime_hook=$(core_registry_field "$pre_id" 14)
        [ -n "$runtime_hook" ] || continue
        [ -f "$repo/modules/$pre_id/$runtime_hook" ] && [ ! -L "$repo/modules/$pre_id/$runtime_hook" ] && [ -x "$repo/modules/$pre_id/$runtime_hook" ] || { core_log "runtime hook non valido: $pre_id/$runtime_hook"; return 1; }
        rm -f -- "$root/run/ps5-cachyos-tools/runtime-changed/$pre_id"
        CORE_REPO="$repo" CORE_INSTALL_MODE="${CORE_INSTALL_MODE:-offline}" CORE_TARGET_ROOT="$root" CORE_BOOT_TARGET="${CORE_BOOT_TARGET:-}" CORE_MODULE_ID="$pre_id" CORE_RUNTIME_CHANGED_FILE="$root/run/ps5-cachyos-tools/runtime-changed/$pre_id" CORE_FRAMEWORK_MANAGED=1 CORE_DRY_RUN=0 "$repo/modules/$pre_id/$runtime_hook" "$root" || return $?
    done <<< "$pre_order"
    order=$(core_registry_selection_order "$module") || return 1
    while IFS= read -r id; do [ -n "$id" ] || continue; moddir="$repo/modules/$id"
        [ -d "$moddir" ] || return 1
        [ -f "$moddir/module.conf" ] && [ ! -L "$moddir/module.conf" ] || return 1
        post_install_hook=$(core_registry_field "$id" 16)
        post_remove_hook=$(core_registry_field "$id" 17)
        for hook in install.sh boot.sh check.sh remove.sh readiness.sh runtime.sh recover.sh post-install.sh "$post_install_hook" "$post_remove_hook"; do [ -z "$hook" ] || [ ! -L "$moddir/$hook" ] || { core_log "hook symlink non trusted: $id/$hook"; return 1; }; done
        CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
        [ "${CORE_MODULE[$id]+x}" = x ] || return 1
        requires_boot=$(core_registry_field "$id" 9)
        type=$(core_registry_field "$id" 2)
        if [ "$requires_boot" = true ]; then
            [ -n "${CORE_BOOT_TARGET:-}" ] || { core_log "modulo $id richiede --boot"; return 1; }
            core_target_validate_mount "$CORE_BOOT_TARGET" boot || return 1
        fi
        [ -x "$moddir/install.sh" ] || { core_log "install hook obbligatorio assente: $id"; return 1; }
        [ "$type" != task ] || [ -x "$moddir/boot.sh" ] || { core_log "boot hook obbligatorio assente: $id"; return 1; }
        readiness_hook=$(core_registry_field "$id" 11)
        if [ -n "$readiness_hook" ]; then
            [ -f "$moddir/$readiness_hook" ] && [ ! -L "$moddir/$readiness_hook" ] && [ -x "$moddir/$readiness_hook" ] || { core_log "readiness hook non valido: $id/$readiness_hook"; return 1; }
        fi
        if [ -n "$module" ] && [ "$id" != "$module" ] && core_install_module_valid "$root" "$repo" "$id"; then
            core_log "dipendenza già valida: $id"
            CORE_INSTALL_REUSED_MODULES+=("$id")
            continue
        fi
        mkdir -p "$root/usr/lib/ps5-cachyos-tools/modules/$id" || return 1
        core_install_copy "$moddir/module.conf" "$root/usr/lib/ps5-cachyos-tools/modules/$id/module.conf" 644 || return 1
        post_install_hook=$(core_registry_field "$id" 16)
        post_remove_hook=$(core_registry_field "$id" 17)
        for hook in install.sh boot.sh check.sh remove.sh readiness.sh runtime.sh recover.sh post-install.sh "$post_install_hook" "$post_remove_hook"; do
            [ -n "$hook" ] || continue
            if [ -e "$moddir/$hook" ]; then
                [ -f "$moddir/$hook" ] && [ ! -L "$moddir/$hook" ] || { core_log "hook non regolare: $id/$hook"; return 1; }
                target=$(core_target_path "$root" "/usr/lib/ps5-cachyos-tools/modules/$id/$hook") || return 1
                core_install_copy "$moddir/$hook" "$target" 755 || { core_log "installazione hook fallita: $id/$hook"; return 1; }
            fi
        done
        if [ -n "$readiness_hook" ]; then
            target="$root/usr/lib/ps5-cachyos-tools/modules/$id/$readiness_hook"
            [ -f "$target" ] && [ ! -L "$target" ] && [ -x "$target" ] && cmp -s -- "$moddir/$readiness_hook" "$target" || { core_log "readiness hook non verificato dopo la copia: $id"; return 1; }
        fi
        enabled=$(core_registry_field "$id" 1)
        install_disabled=$(core_registry_field "$id" 12)
        [ -n "$(core_registry_field "$id" 14)" ] || rm -f -- "$root/run/ps5-cachyos-tools/runtime-changed/$id"
        if [ "$enabled" = true ] || { [ -n "$module" ] && [ "$install_disabled" = true ]; }; then
            if [ -x "$moddir/install.sh" ]; then
                CORE_REPO="$repo" CORE_INSTALL_MODE="${CORE_INSTALL_MODE:-offline}" CORE_TARGET_ROOT="$root" CORE_BOOT_TARGET="${CORE_BOOT_TARGET:-}" CORE_MODULE_ID="$id" CORE_RUNTIME_CHANGED_FILE="$root/run/ps5-cachyos-tools/runtime-changed/$id" CORE_FRAMEWORK_MANAGED=1 CORE_DRY_RUN=0 "$moddir/install.sh" "$root"; rc=$?
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
    local root=$1 backup=$2 repo=$3 requested=${4-} path id owned transaction boot_transaction selected_order dir boot_root
    : > "$backup/.paths" || return 1
    : > "$backup/.created-dirs" || return 1
    : > "$backup/.boot-paths" || return 1
    : > "$backup/.boot-present" || return 1
    for dir in /usr/lib/ps5-cachyos-tools /usr/lib/ps5-cachyos-tools/core /usr/lib/ps5-cachyos-tools/modules /usr/lib/ps5-cachyos-tools/systemd /usr/lib/ps5-cachyos-tools/lib /usr/lib/ps5-cachyos-tools/lib/modules /usr/lib/ps5-cachyos-tools/bin /usr/lib/ps5-cachyos-tools/config /usr/lib/ps5-cachyos-tools/config/profiles /run/ps5-cachyos-tools/runtime-changed; do
        [ -e "$root$dir" ] || printf '%s\n' "$dir" >> "$backup/.created-dirs" || return 1
    done
    for path in /usr/local/bin/ps5-cachyos-tools /usr/lib/ps5-cachyos-tools/boot-runner /usr/lib/ps5-cachyos-tools/bin/ps5-cachyos-tools /usr/lib/ps5-cachyos-tools/systemd/ps5-tools-early.service /usr/lib/ps5-cachyos-tools/systemd/ps5-tools-boot.service /etc/systemd/system/ps5-tools-early.service /etc/systemd/system/ps5-tools-boot.service /etc/systemd/system/multi-user.target.wants/ps5-tools-early.service /etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service /var/lib/ps5-cachyos-tools/install.identity; do
        printf '%s\n' "$path" >> "$backup/.paths" || return 1
    done
    for path in log.sh target.sh registry.sh dependencies.sh state.sh boot-runner.sh installer.sh service.sh; do
        printf '%s\n' "/usr/lib/ps5-cachyos-tools/core/$path" >> "$backup/.paths" || return 1
    done
    CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
    selected_order=$(core_registry_selection_order "$requested") || return 1
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        printf '%s\n' "/usr/lib/ps5-cachyos-tools/modules/$id" >> "$backup/.paths" || return 1
        owned=$(core_registry_field "$id" 10)
        for path in $owned; do printf '%s\n' "$path" >> "$backup/.paths" || return 1; done
        transaction=$(core_registry_field "$id" 13)
        for path in $transaction; do printf '%s\n' "$path" >> "$backup/.paths" || return 1; done
        boot_transaction=$(core_registry_field "$id" 15)
        if [ -n "$boot_transaction" ]; then
            boot_root=${CORE_BOOT_TARGET:-}
            [ -n "$boot_root" ] || { core_log "modulo $id richiede un mount boot per la transazione"; return 1; }
            for path in $boot_transaction; do
                grep -Fxq "$path" "$backup/.boot-paths" 2>/dev/null || printf '%s\n' "$path" >> "$backup/.boot-paths" || return 1
            done
        fi
    done <<< "$selected_order"
    sort -u "$backup/.paths" -o "$backup/.paths" || return 1
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        core_target_validate_final "$root" "$path" "$root$path" || return 1
        if [ -e "$root$path" ] || [ -L "$root$path" ]; then
            core_target_mkdir_path "$root" "${backup#"$root"}$(dirname "$path")" || return 1
            core_target_snapshot_file "$root" "$path" "$backup$path" || return 1
            printf '%s\n' "$path" >> "$backup/.present" || return 1
        fi
    done < "$backup/.paths"
    if [ -s "$backup/.boot-paths" ]; then
        boot_root=${CORE_BOOT_TARGET:-}
        [ -n "$boot_root" ] || { core_log 'mount boot assente durante lo snapshot'; return 1; }
        core_target_validate_mount "$boot_root" boot || return 1
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            core_target_validate_final "$boot_root" "$path" "$boot_root$path" || return 1
            if [ -e "$boot_root$path" ] || [ -L "$boot_root$path" ]; then
                core_target_mkdir_path "$root" "${backup#"$root"}/.boot$(dirname "$path")" || return 1
                cp -a -- "$boot_root$path" "$backup/.boot$path" || return 1
                printf '%s\n' "$path" >> "$backup/.boot-present" || return 1
            fi
        done < "$backup/.boot-paths"
    fi
}

core_txn_restore() {
    local root=$1 backup=$2 path dir result=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        core_target_validate_final "$root" "$path" "$root$path" || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-paths"; continue; }
        core_target_remove_path "$root" "$path" 1 || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-paths"; }
        if grep -Fxq "$path" "$backup/.present" 2>/dev/null; then
            core_target_assert_parents "$root" "$path" || { result=1; continue; }
            core_target_prepare_dir "$root" "$(dirname "$path")" >/dev/null || result=1
            core_target_copy_file "$root" "$path" "$backup$path" || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-paths"; }
        fi
    done < "$backup/.paths"
    if [ -s "$backup/.boot-paths" ]; then
        local boot_root=${CORE_BOOT_TARGET:-}
        if [ -n "$boot_root" ] && core_target_validate_mount "$boot_root" boot; then
            while IFS= read -r path; do
                [ -n "$path" ] || continue
                core_target_validate_final "$boot_root" "$path" "$boot_root$path" || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-boot-paths"; continue; }
                core_target_remove_path "$boot_root" "$path" 1 || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-boot-paths"; continue; }
                if grep -Fxq "$path" "$backup/.boot-present" 2>/dev/null; then
                    core_target_copy_file "$boot_root" "$path" "$backup/.boot$path" || { result=1; printf '%s\n' "$path" >> "$backup/.rollback-failed-boot-paths"; }
                fi
            done < "$backup/.boot-paths"
        else
            result=1
            core_log 'mount boot assente o non valido durante il rollback'
        fi
    fi
    if core_target_validate_final "$root" /run/ps5-cachyos-tools/runtime-changed "$root/run/ps5-cachyos-tools/runtime-changed"; then
        core_target_remove_path "$root" /run/ps5-cachyos-tools/runtime-changed 1 || result=1
    else
        result=1
        printf '%s\n' /run/ps5-cachyos-tools/runtime-changed >> "$backup/.rollback-failed-paths"
    fi
    if [ -f "$backup/.created-dirs" ]; then
        while IFS= read -r dir; do
            [ -n "$dir" ] || continue
            if core_target_validate_final "$root" "$dir" "$root$dir"; then
                core_target_rmdir "$root" "$dir" || { [ ! -e "$root$dir" ] || result=1; }
            else
                result=1
                printf '%s\n' "$dir" >> "$backup/.rollback-failed-paths"
            fi
        done < <(sort -r "$backup/.created-dirs")
    fi
    return "$result"
}

core_install_preflight() {
    local root=$1 repo=$2 module=${3-} id dep moddir type requires_boot unit order readiness_hook runtime_hook post_install_hook post_remove_hook boot_transaction boot_root enabled install_disabled
    core_registry_discover "$repo/modules" >/dev/null || return 1
    core_registry_validate_dependencies || return 1
    core_registry_validate_owned_paths || return 1
    [ -z "$module" ] || [ "${CORE_MODULE[$module]+x}" = x ] || return 1
    order=$(core_registry_selection_order "$module") || return 1
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        moddir="$repo/modules/$id"; [ -d "$moddir" ] || return 1
        for dep in $(core_registry_field "$id" 6); do
            [ "$(core_registry_field "$dep" 1)" = true ] || { core_log "dipendenza disabilitata: $id -> $dep"; return 1; }
        done
        [ -x "$moddir/install.sh" ] || { core_log "install hook obbligatorio assente: $id"; return 1; }
        type=$(core_registry_field "$id" 2); [ "$type" != task ] || [ -x "$moddir/boot.sh" ] || { core_log "boot hook obbligatorio assente: $id"; return 1; }
        requires_boot=$(core_registry_field "$id" 9)
        boot_transaction=$(core_registry_field "$id" 15)
        [ "$requires_boot" != true ] && [ -z "$boot_transaction" ] || [ -n "${CORE_BOOT_TARGET:-}" ] || { core_log "modulo $id richiede --boot"; return 1; }
        if [ -n "$boot_transaction" ]; then
            boot_root=${CORE_BOOT_TARGET:-}
            core_target_validate_mount "$boot_root" boot || return 1
            [ -w "$boot_root" ] || { core_log "boot non scrivibile: $boot_root"; return 1; }
        fi
        unit=$(core_registry_field "$id" 7)
        [ -z "$unit" ] || core_service_source "$repo" "$unit" >/dev/null || { core_log "unit dichiarata assente: $id/$unit"; return 1; }
        readiness_hook=$(core_registry_field "$id" 11)
        if [ -n "$readiness_hook" ]; then
            [ -f "$moddir/$readiness_hook" ] && [ ! -L "$moddir/$readiness_hook" ] && [ -x "$moddir/$readiness_hook" ] || { core_log "readiness hook non valido: $id/$readiness_hook"; return 1; }
        fi
        runtime_hook=$(core_registry_field "$id" 14)
        if [ -n "$runtime_hook" ]; then
            [ -f "$moddir/$runtime_hook" ] && [ ! -L "$moddir/$runtime_hook" ] && [ -x "$moddir/$runtime_hook" ] || { core_log "runtime hook non valido: $id/$runtime_hook"; return 1; }
        fi
        post_install_hook=$(core_registry_field "$id" 16)
        if [ -n "$post_install_hook" ]; then
            [ -f "$moddir/$post_install_hook" ] && [ ! -L "$moddir/$post_install_hook" ] && [ -x "$moddir/$post_install_hook" ] || { core_log "post-install hook non valido: $id/$post_install_hook"; return 1; }
            enabled=$(core_registry_field "$id" 1)
            install_disabled=$(core_registry_field "$id" 12)
            if [ "$enabled" = true ] || { [ -n "$module" ] && [ "$install_disabled" = true ]; }; then
                if [ -n "$module" ] && [ "$id" != "$module" ] && core_install_module_valid "$root" "$repo" "$id"; then
                    core_log "preflight post-hook saltato: dipendenza già valida $id"
                else
                    CORE_REPO="$repo" CORE_INSTALL_MODE="${CORE_INSTALL_MODE:-offline}" CORE_TARGET_ROOT="$root" CORE_MODULE_ID="$id" CORE_FRAMEWORK_MANAGED=1 CORE_DRY_RUN=1 "$moddir/$post_install_hook" "$root" preflight || return $?
                fi
            fi
        fi
        post_remove_hook=$(core_registry_field "$id" 17)
        if [ -n "$post_remove_hook" ]; then
            [ -f "$moddir/$post_remove_hook" ] && [ ! -L "$moddir/$post_remove_hook" ] && [ -x "$moddir/$post_remove_hook" ] || { core_log "post-remove hook non valido: $id/$post_remove_hook"; return 1; }
        fi
    done <<< "$order"
}

core_install_post_hooks() {
    local root=$1 repo=$2 module=${3-} action=${4:-install} order id hook enabled install_disabled copied reused
    order=$(core_registry_selection_order "$module") || return 1
    [ "$action" != rollback ] || order=$(tac <<< "$order")
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        for reused in "${CORE_INSTALL_REUSED_MODULES[@]}"; do
            [ "$id" != "$reused" ] || continue 2
        done
        hook=$(core_registry_field "$id" 16)
        [ -n "$hook" ] || continue
        enabled=$(core_registry_field "$id" 1)
        install_disabled=$(core_registry_field "$id" 12)
        if [ "$enabled" != true ] && { [ -z "$module" ] || [ "$install_disabled" != true ]; }; then
            continue
        fi
        copied="$root/usr/lib/ps5-cachyos-tools/modules/$id/$hook"
        if [ "$action" = rollback ] && { [ ! -e "$copied" ] || [ -L "$copied" ]; }; then continue; fi
        [ -f "$copied" ] && [ ! -L "$copied" ] && [ -x "$copied" ] && cmp -s -- "$repo/modules/$id/$hook" "$copied" || { core_log "post-install hook installato non verificato: $id/$hook"; return 1; }
        if ! CORE_REPO="$repo" CORE_INSTALL_MODE="${CORE_INSTALL_MODE:-offline}" CORE_TARGET_ROOT="$root" CORE_MODULE_ID="$id" CORE_RUNTIME_CHANGED_FILE="$root/run/ps5-cachyos-tools/runtime-changed/$id" CORE_INSTALL_TRANSACTION_BACKUP="${CORE_INSTALL_TRANSACTION_BACKUP:-}" CORE_FRAMEWORK_MANAGED=1 CORE_DRY_RUN=0 "$repo/modules/$id/$hook" "$root" "$action"; then
            core_log "post-install hook $action fallito: $id"
            [ "$action" != install ] || return 1
            return 1
        fi
    done <<< "$order"
}

core_install() {
    local root=$1 backup path rollback_status=ROLLBACK_PARTIAL service_rollback_failed=0 filesystem_restore_failed=0
    CORE_CONFIG_ROOT=${CORE_CONFIG_ROOT:-$root}
    core_install_preflight "$root" "$2" "${3-}" || return 1
    core_target_prepare_dir "$root" /run/ps5-cachyos-tools >/dev/null || return 1
    core_target_prepare_dir "$root" /var/lib/ps5-cachyos-tools/state/reapply >/dev/null || return 1
    core_txn_lock "$root" || return 1
    backup=$(mktemp -d "$root/.ps5-cachyos-tools-txn.XXXXXX") || return 1
    core_txn_snapshot "$root" "$backup" "$2" "${3-}" || { core_log 'snapshot transazione fallito'; rm -rf -- "$backup"; return 1; }
    core_service_transaction_snapshot "$root" "${3-}" "$backup" || { core_log 'snapshot servizi fallito'; rm -rf -- "$backup"; return 1; }
    CORE_INSTALL_TRANSACTION_BACKUP="$backup"
    CORE_INSTALL_REUSED_MODULES=()
    if core_install_body "$@" && core_install_post_hooks "$@" install && core_install_post_hooks "$@" commit; then
        if ! core_install_post_hooks "$@" finalize; then
            core_log "installazione applicata ma finalizzazione hook fallita; backup conservato in $backup"
            printf '%s\n' FINALIZE_HOOK_FAILED > "$backup/.rollback-status"
            return 1
        fi
        rm -rf -- "$backup"
        return 0
    fi
    core_log 'installazione core fallita: rollback transazione'
    core_install_post_hooks "$@" rollback || { rollback_status=ROLLBACK_EXTERNAL_FAILED; core_log 'ROLLBACK_EXTERNAL_FAILED: post-install hook'; }
    if core_txn_restore "$root" "$backup"; then
        [ "$rollback_status" = ROLLBACK_EXTERNAL_FAILED ] || rollback_status=ROLLBACK_COMPLETED
    else
        filesystem_restore_failed=1
        core_log "ROLLBACK_PARTIAL: backup conservato in $backup"
    fi
    if [ "${CORE_INSTALL_MODE:-offline}" = live ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        core_service_transaction_restore "$root" "$backup" || service_rollback_failed=1
    fi
    if [ "$service_rollback_failed" -ne 0 ]; then
        if [ "$filesystem_restore_failed" -ne 0 ] || [ "$rollback_status" = ROLLBACK_EXTERNAL_FAILED ]; then
            rollback_status=ROLLBACK_FAILED
        else
            rollback_status=ROLLBACK_FILES_RESTORED_SERVICE_FAILED
        fi
    fi
    if [ "$rollback_status" = ROLLBACK_COMPLETED ]; then
        rm -rf -- "$backup"
    else
        printf '%s\n' "$rollback_status" > "$backup/.rollback-status"
        core_log "backup transazione conservato: $backup"
    fi
    return 1
}

core_remove_module_artifacts() {
    local root=$1 id=$2 path full request
    for path in $(core_registry_field "$id" 10); do
        full="$root$path"
        [ -e "$full" ] || [ -L "$full" ] || continue
        core_target_validate_final "$root" "$path" "$full" || return 1
        core_target_remove_path "$root" "$path" || return 1
    done
    request="$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request"
    core_target_validate_final "$root" "/var/lib/ps5-cachyos-tools/state/reapply/$id.request" "$request" || return 1
    [ ! -e "$request" ] || [ -L "$request" ] || rm -f -- "$request" || return 1
}

core_remove_snapshot() {
    local root=$1 id=$2 backup=$3 path full transaction
    core_txn_lock "$root" || return 1
    : > "$backup/.paths" || return 1
    for path in $(core_registry_field "$id" 10) /usr/lib/ps5-cachyos-tools/modules/$id /var/lib/ps5-cachyos-tools/state/modules/$id.state /var/lib/ps5-cachyos-tools/state/reapply/$id.request; do
        printf '%s\n' "$path" >> "$backup/.paths" || return 1
        full="$root$path"
        core_target_validate_final "$root" "$path" "$full" || return 1
        if [ -e "$full" ] || [ -L "$full" ]; then
            core_target_mkdir_path "$root" "${backup#"$root"}$(dirname "$path")" || return 1
            core_target_snapshot_file "$root" "$path" "$backup$path" || return 1
            printf '%s\n' "$path" >> "$backup/.present" || return 1
        fi
    done
    transaction=$(core_registry_field "$id" 13)
    for path in $transaction; do
        grep -Fxq "$path" "$backup/.paths" 2>/dev/null || printf '%s\n' "$path" >> "$backup/.paths" || return 1
        full="$root$path"
        core_target_validate_final "$root" "$path" "$full" || return 1
        if [ -e "$full" ] || [ -L "$full" ]; then
            core_target_mkdir_path "$root" "${backup#"$root"}$(dirname "$path")" || return 1
            core_target_snapshot_file "$root" "$path" "$backup$path" || return 1
            printf '%s\n' "$path" >> "$backup/.present" || return 1
        fi
    done
}

core_remove_restore() {
    local root=$1 backup=$2 path result=0
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        core_target_validate_final "$root" "$path" "$root$path" || { result=1; continue; }
        rm -rf -- "$root$path" || result=1
        if grep -Fxq "$path" "$backup/.present" 2>/dev/null; then
            core_target_assert_parents "$root" "$path" || { result=1; continue; }
            core_target_prepare_dir "$root" "$(dirname "$path")" >/dev/null || result=1
            core_target_copy_file "$root" "$path" "$backup$path" || result=1
        fi
    done < "$backup/.paths"
    return "$result"
}
