#!/usr/bin/env bash
set -u

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
