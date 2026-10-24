#!/usr/bin/env bash
set -u

core_target_realpath() {
    local path=$1 resolved current part
    [ -d "$path" ] || { core_die "target non trovato: $path"; return 1; }
    case "$path" in /*) ;; *) core_die 'target deve essere un percorso assoluto'; return 1;; esac
    current=/; IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do [ -n "$part" ] || continue; current="$current/$part"; [ ! -L "$current" ] || { core_die "antenato target symlink: $current"; return 1; }; done
    resolved=$(realpath -e -- "$path" 2>/dev/null) || { core_die "target non canonicalizzabile: $path"; return 1; }
    [ "$resolved" != / ] || { core_die 'modalità offline non può usare /; specificare --live'; return 1; }
    printf '%s\n' "$resolved"
}

core_target_validate_offline() {
    local root=$1 boot=${2-} part
    [[ "$root" != *'..'* ]] || { core_die 'rootfs non può contenere componenti ..'; return 1; }
    [ ! -L "$root" ] || { core_die 'rootfs target non può essere un symlink'; return 1; }
    root=$(core_target_realpath "$root") || return 1
    [ -r "$root/etc/os-release" ] || { core_die "rootfs senza etc/os-release: $root"; return 1; }
    [ -w "$root" ] || { core_die "rootfs non scrivibile: $root"; return 1; }
    for part in etc usr var run; do
        [ ! -L "$root/$part" ] || { core_die "directory target non può essere un symlink: $part"; return 1; }
    done
    for part in /usr/lib /usr/local /usr/local/bin /etc/systemd /etc/systemd/system /etc/udev /etc/udev/rules.d /var/lib/ps5-cachyos-tools /run/ps5-cachyos-tools; do
        core_target_assert_parents "$root" "$part" || return 1
        [ ! -L "$root$part" ] || { core_die "directory target non può essere un symlink: $part"; return 1; }
    done
    if [ -n "$boot" ]; then
        [ ! -L "$boot" ] || { core_die 'mount boot symlink non valido'; return 1; }
        boot=$(realpath -e -- "$boot" 2>/dev/null) || { core_die "boot non canonicalizzabile: $boot"; return 1; }
        [ "$boot" != / ] || { core_die 'mount boot non valido'; return 1; }
        core_target_validate_mount "$boot" boot || return 1
        [ -d "$boot" ] && [ -w "$boot" ] || { core_die "boot non scrivibile: $boot"; return 1; }
    fi
    printf '%s\n' "$root"
}

core_target_validate_mount() {
    local path=$1 label=$2 current part
    case "$path" in /*) ;; *) core_die "$label non assoluto"; return 1;; esac
    [ -d "$path" ] || { core_die "$label non è una directory: $path"; return 1; }
    [ ! -L "$path" ] || { core_die "$label non può essere un symlink"; return 1; }
    current=/; IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="$current/$part"
        [ ! -L "$current" ] || { core_die "antenato $label symlink: $current"; return 1; }
    done
    [ "$(realpath -e -- "$path")" != / ] || { core_die "$label non può essere /"; return 1; }
}

core_target_path() {
    local root=$1 path=$2 resolved parent full allow_final=${3:-0}
    [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    core_target_assert_parents "$root" "$path" || return 1
    parent=$(dirname "$root$path"); resolved=$(realpath -m -- "$parent" 2>/dev/null) || return 1
    case "$resolved/" in "$root/"*|"$root") ;; *) return 1;; esac
    full="$root$path"
    if [ -L "$full" ] && [ "$allow_final" != 1 ]; then return 1; fi
    printf '%s\n' "$full"
}

core_target_prepare_dir() {
    local root=$1 path=$2 full
    full=$(core_target_path "$root" "$path" 0) || return 1
    [ ! -e "$full" ] || [ -d "$full" ] || return 1
    [ ! -L "$full" ] || { core_die "directory target symlink non autorizzata: $full"; return 1; }
    mkdir -p -- "$full" || return 1
    [ ! -L "$full" ] || return 1
    printf '%s\n' "$full"
}

core_target_assert_parents() {
    local root=$1 path=$2 part current
    [[ "$path" = /* ]] || return 1
    current=$root
    IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="$current/$part"
        [ "$current" = "$root$path" ] && break
        [ ! -L "$current" ] || { core_die "symlink nell'antenato target: $current"; return 1; }
    done
}

core_target_validate_final() {
    local root=$1 path=$2 full=$3 link target resolved
    core_target_assert_parents "$root" "$path" || return 1
    if [ -L "$full" ]; then
        link=$(readlink -- "$full") || return 1
        case "$link" in
            /*) target="$root$link";;
            *) target="$(dirname "$full")/$link";;
        esac
        resolved=$(realpath -m -- "$target") || return 1
        case "$resolved/" in "$root/"*|"$root") ;; *) core_die "symlink gestito fuori target: $path -> $link"; return 1;; esac
    elif [ -e "$full" ]; then
        [ -f "$full" ] || [ -d "$full" ] || return 1
    fi
}

core_target_validate_live() {
    [ "$(id -u)" -eq 0 ] || { core_die 'modalità live richiede root'; return 1; }
    [ "$(realpath -e /)" = / ] || return 1
    [ -r /etc/os-release ] || { core_die 'sistema live senza etc/os-release'; return 1; }
    printf '/\n'
}

core_target_boot_path() {
    local root=$1 boot=$2 resolved
    [ -n "$boot" ] || return 0
    case "$boot" in /*) ;; *) core_die 'boot deve essere un percorso assoluto'; return 1;; esac
    [ ! -L "$boot" ] || return 1
    resolved=$(realpath -e -- "$boot" 2>/dev/null) || return 1
    [ "$resolved" != / ] || return 1
    core_target_validate_mount "$resolved" boot || return 1
    printf '%s\n' "$resolved"
}
