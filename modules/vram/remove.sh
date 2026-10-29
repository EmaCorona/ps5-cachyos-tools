#!/usr/bin/env bash
set -u
root=$1
keep_config=${CORE_KEEP_CONFIG:-${2:-1}}
[ "$keep_config" = 0 ] || [ "$keep_config" = 1 ] || exit 1
[ "$keep_config" = 0 ] || exit 0
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" || exit 1
config_path=/etc/ps5-cachyos-tools/vram.conf
config_file="$root$config_path"
core_target_validate_final "$root" "$config_path" "$config_file" || exit 1
core_target_remove_path "$root" "$config_path"
