#!/usr/bin/env bash
set -u
root=$1
repo=${CORE_REPO:?}
boot=${CORE_BOOT_TARGET:-}
source "$repo/modules/vram/files/vram-common.sh" || exit 1
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" || exit 1

[ -n "$boot" ] || { printf '%s\n' 'modulo vram: specificare la partizione FAT32 con --boot' >&2; exit 1; }
core_target_validate_mount "$boot" boot || exit 1
if [ "${CORE_TEST_MODE:-0}" != 1 ]; then
    fs_type=$(findmnt -n -o FSTYPE --target "$boot" 2>/dev/null) || exit 1
    [ "$fs_type" = vfat ] || { printf 'modulo vram: filesystem boot non FAT32 (FSTYPE=%s)\n' "$fs_type" >&2; exit 1; }
fi
core_target_validate_final "$boot" /vram.txt "$boot/vram.txt" || exit 1

config_path=/etc/ps5-cachyos-tools/vram.conf
config_file="$root$config_path"
core_target_validate_final "$root" "$config_path" "$config_file" || exit 1
core_target_validate_final "$root" /usr/local/libexec/ps5-cachyos-tools/vram-common.sh "$root/usr/local/libexec/ps5-cachyos-tools/vram-common.sh" || exit 1
config_present=0
boot_present=0
if [ -e "$config_file" ] || [ -L "$config_file" ]; then
    config_present=1
    [ -f "$config_file" ] && [ ! -L "$config_file" ] || { printf '%s\n' 'modulo vram: configurazione esistente non regolare' >&2; exit 1; }
fi
if [ -e "$boot/vram.txt" ] || [ -L "$boot/vram.txt" ]; then
    boot_present=1
    [ -f "$boot/vram.txt" ] && [ ! -L "$boot/vram.txt" ] || { printf '%s\n' 'modulo vram: vram.txt esistente non valido' >&2; exit 1; }
fi

if [ -n "${CORE_VRAM_SIZE:-}" ]; then
    size=$(vram_normalize_hex "$CORE_VRAM_SIZE") || { printf '%s\n' 'modulo vram: CORE_VRAM_SIZE non valido' >&2; exit 1; }
else
    if [ "$config_present" -eq 1 ]; then
        config_size=$(vram_config_read "$config_file") || { printf '%s\n' 'modulo vram: configurazione esistente non valida' >&2; exit 1; }
    fi
    if [ "$boot_present" -eq 1 ]; then
        existing=$(cat -- "$boot/vram.txt") || exit 1
        boot_size=$(vram_normalize_hex "$existing") || { printf '%s\n' 'modulo vram: vram.txt esistente non valido o fuori dai limiti supportati' >&2; exit 1; }
    fi
    if [ "$config_present" -eq 1 ] && [ "$boot_present" -eq 1 ]; then
        [ "$config_size" = "$boot_size" ] || { printf '%s\n' 'modulo vram: vram.conf e vram.txt discordanti; specificare --vram-size per risolvere' >&2; exit 1; }
        size=$config_size
    elif [ "$config_present" -eq 1 ]; then
        size=$config_size
    elif [ "$boot_present" -eq 1 ]; then
        size=$boot_size
    else
        size=0x20000000
    fi
fi

core_target_prepare_dir "$root" /etc/ps5-cachyos-tools >/dev/null || exit 1
core_target_prepare_dir "$root" /usr/local/libexec/ps5-cachyos-tools >/dev/null || exit 1
core_target_copy_file "$root" /usr/local/libexec/ps5-cachyos-tools/vram-common.sh "$repo/modules/vram/files/vram-common.sh" || exit 1
core_target_chmod "$root" /usr/local/libexec/ps5-cachyos-tools/vram-common.sh 755 || exit 1
core_target_write_file "$boot" /vram.txt 644 "$size" || exit 1
core_target_write_file "$root" "$config_path" 644 "VRAM_BYTES=$size" || exit 1
printf 'modulo vram: impostato %s byte nel file %s/vram.txt\n' "$size" "$boot"
