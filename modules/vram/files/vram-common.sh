#!/usr/bin/env bash

vram_normalize_hex() {
    local raw=${1-} digits value
    [[ "$raw" =~ ^(0[xX])?[0-9a-fA-F]+$ ]] || return 1
    digits=${raw#0x}; digits=${digits#0X}
    [ "${#digits}" -le 9 ] || return 1
    value=$((16#$digits)) || return 1
    (( value >= 0x20000000 && value <= 0x200000000 && value % 0x100000 == 0 )) || return 1
    printf '0x%x\n' "$value"
}

vram_config_read() {
    local file=$1 raw value
    [ -f "$file" ] && [ ! -L "$file" ] || return 1
    raw=$(cat -- "$file") || return 1
    [[ "$raw" =~ ^VRAM_BYTES=((0[xX])?[0-9a-fA-F]+)$ ]] || return 1
    value=$(vram_normalize_hex "${BASH_REMATCH[1]}") || return 1
    printf '%s\n' "$value"
}
