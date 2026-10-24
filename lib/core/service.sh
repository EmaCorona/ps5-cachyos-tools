#!/usr/bin/env bash
set -u

core_service_module_install() {
    local root=$1 repo=$2 id=$3 unit source target wants
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    source="$repo/systemd/$unit"; [ -f "$source" ] || return 1
    target=$(core_target_path "$root" "/etc/systemd/system/$unit") || return 1
    install -m 0644 "$source" "$target" || return 1
    core_target_assert_parents "$root" "/etc/systemd/system/multi-user.target.wants" || return 1
    wants="$root/etc/systemd/system/multi-user.target.wants/$unit"
    if [ -L "$wants" ]; then [ "$(readlink "$wants")" = "/etc/systemd/system/$unit" ] || return 1; else [ ! -e "$wants" ] || return 1; ln -s -- "/etc/systemd/system/$unit" "$wants" || return 1; fi
}

core_service_module_remove() {
    local root=$1 id=$2 unit
    unit=$(core_registry_field "$id" 7); [ -n "$unit" ] || return 0
    if [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then
        systemctl disable --now "$unit" || return 1
        systemctl daemon-reload || return 1
    fi
    rm -f -- "$root/etc/systemd/system/multi-user.target.wants/$unit" "$root/etc/systemd/system/$unit"
}

core_service_install() {
    local root=$1 repo=$2 path target
    for path in /etc/systemd/system /etc/systemd/system/multi-user.target.wants; do
        core_target_prepare_dir "$root" "$path" >/dev/null || return 1
    done
    for path in /etc/systemd/system/ps5-tools-early.service /etc/systemd/system/ps5-tools-boot.service; do
        target=$(core_target_path "$root" "$path") || return 1
        install -m 0644 "$repo/systemd/${path##*/}" "$target" || return 1
    done
    for path in ps5-tools-early.service ps5-tools-boot.service; do
        target=$(core_target_path "$root" "/etc/systemd/system/multi-user.target.wants/$path") || return 1
        [ ! -e "$target" ] || [ -L "$target" ] || return 1
        ln -s -- "/etc/systemd/system/$path" "$target" || return 1
    done
}
