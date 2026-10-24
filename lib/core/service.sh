#!/usr/bin/env bash
set -u

core_service_install() {
    local root=$1 repo=$2
    install -d "$root/etc/systemd/system/multi-user.target.wants"
    install -m 0644 "$repo/systemd/ps5-tools-early.service" "$root/etc/systemd/system/ps5-tools-early.service"
    install -m 0644 "$repo/systemd/ps5-tools-boot.service" "$root/etc/systemd/system/ps5-tools-boot.service"
    ln -sfn /etc/systemd/system/ps5-tools-early.service "$root/etc/systemd/system/multi-user.target.wants/ps5-tools-early.service"
    ln -sfn /etc/systemd/system/ps5-tools-boot.service "$root/etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service"
}
