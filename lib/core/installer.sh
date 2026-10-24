#!/usr/bin/env bash
set -u

core_install_body() {
    local root=$1 repo=$2 module=${3-} moddir id hook path lock_dir
    for path in /usr /usr/lib /usr/local /usr/local/bin /etc /etc/ps5-fan /etc/systemd /etc/systemd/system /etc/udev /etc/udev/rules.d /var /var/lib /var/lib/ps5-cachyos-tools /run /run/ps5-cachyos-tools; do core_target_assert_parents "$root" "$path" || return 1; done
    lock_dir="$root/run/ps5-cachyos-tools"; mkdir -p "$lock_dir" || return 1; exec 8>"$lock_dir/install.lock"; flock -n 8 || { core_log 'installazione già attiva'; return 1; }
    mkdir -p "$root/usr/lib/ps5-cachyos-tools/core" "$root/usr/lib/ps5-cachyos-tools/modules" "$root/var/lib/ps5-cachyos-tools/state/modules" "$root/run/ps5-cachyos-tools" || return 1
    chmod 700 "$root/var/lib/ps5-cachyos-tools/state/modules" || return 1
    for file in log.sh target.sh registry.sh dependencies.sh state.sh boot-runner.sh installer.sh service.sh; do install -m 0755 "$repo/lib/core/$file" "$root/usr/lib/ps5-cachyos-tools/core/$file" || return 1; done
    install -m 0755 "$repo/lib/core/boot-runner.sh" "$root/usr/lib/ps5-cachyos-tools/boot-runner" || return 1
    printf '%s\n' "$(date +%s)-$(id -u)-$root" > "$root/var/lib/ps5-cachyos-tools/install.identity"
    core_registry_discover "$repo/modules" >/dev/null || return 1
    [ -z "$module" ] || [ "${CORE_MODULE[$module]+x}" = x ] || { core_log "modulo sconosciuto: $module"; return 1; }
    for moddir in "$repo"/modules/*; do [ -d "$moddir" ] || continue; id=${moddir##*/}; [ "$id" != _template ] || continue; [ -z "$module" ] || [ "$module" = "$id" ] || continue
        [ -f "$moddir/module.conf" ] && [ ! -L "$moddir/module.conf" ] || return 1
        for hook in install.sh boot.sh check.sh remove.sh; do [ ! -L "$moddir/$hook" ] || { core_log "hook symlink non trusted: $id/$hook"; return 1; }; done
        CORE_REGISTRY_ROOT="$repo/modules" core_registry_discover "$repo/modules" >/dev/null || return 1
        [ "${CORE_MODULE[$id]+x}" = x ] || return 1
        mkdir -p "$root/usr/lib/ps5-cachyos-tools/modules/$id"; cp -a "$moddir/module.conf" "$root/usr/lib/ps5-cachyos-tools/modules/$id/" || return 1
        for hook in install.sh boot.sh check.sh remove.sh; do [ -e "$moddir/$hook" ] && install -m 0755 "$moddir/$hook" "$root/usr/lib/ps5-cachyos-tools/modules/$id/$hook" || true; done
        enabled=$(core_registry_field "$id" 1)
        if [ "$enabled" = true ] || [ -n "$module" ]; then
            [ -x "$moddir/install.sh" ] && CORE_REPO="$repo" "$moddir/install.sh" "$root" || { core_log "install hook fallito: $id"; return 1; }
        fi
    done
}

core_install() {
    local root=$1 backup path
    backup=$(mktemp -d "$root/.ps5-cachyos-tools-txn.XXXXXX") || return 1
    for path in /usr/lib/ps5-cachyos-tools /var/lib/ps5-cachyos-tools/install.identity; do
        if [ -e "$root$path" ] || [ -L "$root$path" ]; then mkdir -p "$backup$(dirname "$path")" && cp -a -- "$root$path" "$backup$path" || { rm -rf -- "$backup"; return 1; }; fi
    done
    if core_install_body "$@"; then
        rm -rf -- "$backup"
        return 0
    fi
    core_log 'installazione core fallita: rollback transazione'
    for path in /usr/lib/ps5-cachyos-tools /var/lib/ps5-cachyos-tools/install.identity; do
        rm -rf -- "$root$path"
        if [ -e "$backup$path" ] || [ -L "$backup$path" ]; then mkdir -p "$root$(dirname "$path")" && cp -a -- "$backup$path" "$root$path" || true; fi
    done
    rm -rf -- "$backup"
    return 1
}
