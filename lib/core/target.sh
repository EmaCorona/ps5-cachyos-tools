#!/usr/bin/env bash
set -u

core_target_is_within_root() {
    local root=$1 path=$2
    [ "$root" = / ] && { [[ "$path" = /* ]] || return 1; return 0; }
    case "$path" in "$root"|"$root"/*) return 0;; *) return 1;; esac
}

core_target_realpath() {
    local path=$1 resolved current part
    [ -d "$path" ] || { core_die "target non trovato: $path"; return 1; }
    case "$path" in /*) ;; *) core_die 'target deve essere un percorso assoluto'; return 1;; esac
    current=/; IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do [ -n "$part" ] || continue; current="${current%/}/$part"; [ ! -L "$current" ] || { core_die "antenato target symlink: $current"; return 1; }; done
    resolved=$(realpath -e -- "$path" 2>/dev/null) || { core_die "target non canonicalizzabile: $path"; return 1; }
    [ "$resolved" != / ] || { core_die 'modalità offline non può usare /; specificare --live'; return 1; }
    printf '%s\n' "$resolved"
}

core_target_validate_offline() {
    local root=$1 boot=${2-} part
    [[ "$root" != *'..'* ]] || { core_die 'rootfs non può contenere componenti ..'; return 1; }
    [ ! -L "$root" ] || { core_die 'rootfs target non può essere un symlink'; return 1; }
    root=$(core_target_realpath "$root") || return 1
    core_target_validate_mount "$root" root || return 1
    [ -r "$root/etc/os-release" ] || { core_die "rootfs senza etc/os-release: $root"; return 1; }
    [ -w "$root" ] || { core_die "rootfs non scrivibile: $root"; return 1; }
    for part in etc usr var run; do
        [ ! -L "$root/$part" ] || { core_die "directory target non può essere un symlink: $part"; return 1; }
    done
    for part in /usr/lib /usr/local /usr/local/bin /etc/systemd /etc/systemd/system /etc/udev /etc/udev/rules.d /var/lib/ps5-cachyos-tools /var/lib/ps5-cachyos-tools/state/reapply /usr/lib/ps5-cachyos-tools/modules /run/ps5-cachyos-tools; do
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
    local path=$1 label=$2 current part mountpoint
    case "$path" in /*) ;; *) core_die "$label non assoluto"; return 1;; esac
    [ -d "$path" ] || { core_die "$label non è una directory: $path"; return 1; }
    [ ! -L "$path" ] || { core_die "$label non può essere un symlink"; return 1; }
    current=/; IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || { core_die "antenato $label symlink: $current"; return 1; }
    done
    [ "$(realpath -e -- "$path")" != / ] || { core_die "$label non può essere /"; return 1; }
    if command -v findmnt >/dev/null 2>&1; then
        mountpoint=$(findmnt -T "$path" -no TARGET 2>/dev/null || true)
        if [ "${CORE_TEST_MODE:-0}" != 1 ]; then
            [ "$mountpoint" = "$path" ] || { core_die "$label non è un mountpoint esplicito: $path"; return 1; }
        fi
    elif [ "${CORE_TEST_MODE:-0}" != 1 ]; then
        core_die "impossibile verificare il mountpoint $label"; return 1
    fi
}

core_target_path() {
    local root=$1 path=$2 resolved parent full allow_final=${3:-0}
    [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    core_target_assert_parents "$root" "$path" || return 1
    parent=$(dirname "$root$path"); resolved=$(realpath -m -- "$parent" 2>/dev/null) || return 1
    core_target_is_within_root "$root" "$resolved" || return 1
    if [ "$root" = / ]; then full="$path"; else full="$root$path"; fi
    if [ -L "$full" ] && [ "$allow_final" != 1 ]; then return 1; fi
    printf '%s\n' "$full"
}

core_target_validate_root() {
    local root=$1 current=/ part
    [[ "$root" = /* && "$root" != *'..'* && "$root" != *$'\n'* && "$root" != *$'\r'* ]] || return 1
    [ "$root" = / ] && return 0
    [ -d "$root" ] && [ ! -L "$root" ] || return 1
    IFS=/ read -ra parts <<< "${root#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || { core_die "antenato root symlink: $current"; return 1; }
    done
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
    local root=$1 path=$2 part current resolved target_path
    [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    core_target_validate_root "$root" || return 1
    current=${root%/}
    [ -n "$current" ] || current=/
    target_path="$root$path"; [ "$root" = / ] && target_path="$path"
    IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ "$current" = "$target_path" ] && break
        if [ -L "$current" ]; then
            [ "$root" = / ] || { core_die "symlink nell'antenato target: $current"; return 1; }
            resolved=$(realpath -m -- "$current") || return 1
            core_target_is_within_root / "$resolved" || { core_die "symlink live fuori root: $current"; return 1; }
        fi
    done
}

core_target_validate_final() {
    local root=$1 path=$2 full=$3 link target resolved expected_unit
    [ "$root" = / ] && full="$path"
    core_target_assert_parents "$root" "$path" || return 1
    if [ -L "$full" ]; then
        link=$(readlink -- "$full") || return 1
        case "$path" in
            /etc/systemd/system/multi-user.target.wants/*.service)
                expected_unit=${path##*/}
                [ "$link" = "/etc/systemd/system/$expected_unit" ] || { core_die "symlink finale non autorizzato: $path -> $link"; return 1; } ;;
            *) core_die "symlink finale non autorizzato: $path -> $link"; return 1;;
        esac
        case "$link" in
            /*) target="$root$link";;
            *) target="$(dirname "$full")/$link";;
        esac
        resolved=$(realpath -m -- "$target") || return 1
        core_target_is_within_root "$root" "$resolved" || { core_die "symlink gestito fuori target: $path -> $link"; return 1; }
    elif [ -e "$full" ]; then
        [ -f "$full" ] || [ -d "$full" ] || return 1
    fi
}

core_target_parent_fd() {
    local root=$1 path=$2 parent full expected actual fd
    core_target_assert_parents "$root" "$path" || return 1
    parent=$(dirname "$path")
    full=$root$parent
    [ -d "$full" ] && [ ! -L "$full" ] || return 1
    exec {fd}<"$full" || return 1
    expected=$(realpath -e -- "$full") || { exec {fd}<&-; return 1; }
    actual=$(readlink -e -- "/proc/self/fd/$fd") || { exec {fd}<&-; return 1; }
    [ "$actual" = "$expected" ] || { exec {fd}<&-; return 1; }
    CORE_TARGET_PARENT_FD=$fd
}

core_target_remove_path() {
    local root=$1 path=$2 recursive=${3:-0} fd name
    core_target_validate_final "$root" "$path" "$root$path" || return 1
    [ -e "$root$path" ] || [ -L "$root$path" ] || return 0
    core_target_parent_fd "$root" "$path" || return 1
    fd=$CORE_TARGET_PARENT_FD; name=$(basename "$path")
    if [ -L "$root$path" ] || [ "$recursive" -ne 1 ]; then rm -f -- "/proc/self/fd/$fd/$name"; else rm -rf -- "/proc/self/fd/$fd/$name"; fi
    local rc=$?; exec {fd}<&-; return "$rc"
}

core_target_write_file() {
    local root=$1 path=$2 mode=$3 content=$4 fd name tmp rc
    core_target_parent_fd "$root" "$path" || return 1
    fd=$CORE_TARGET_PARENT_FD; name=$(basename "$path")
    tmp=$(mktemp "/proc/self/fd/$fd/.$name.XXXXXX") || { exec {fd}<&-; return 1; }
    printf '%s\n' "$content" > "$tmp" || { rm -f -- "$tmp"; exec {fd}<&-; return 1; }
    chmod "$mode" -- "$tmp" || { rm -f -- "$tmp"; exec {fd}<&-; return 1; }
    mv -f -- "$tmp" "/proc/self/fd/$fd/$name"; rc=$?; [ "$rc" -eq 0 ] || rm -f -- "$tmp"; exec {fd}<&-; return "$rc"
}

core_target_copy_file() {
    local root=$1 path=$2 source=$3 fd name tmp rc
    [ -e "$source" ] || [ -L "$source" ] || return 1
    core_target_parent_fd "$root" "$path" || return 1
    fd=$CORE_TARGET_PARENT_FD; name=$(basename "$path")
    tmp=$(mktemp "/proc/self/fd/$fd/.$name.XXXXXX") || { exec {fd}<&-; return 1; }
    rm -f -- "$tmp" || { exec {fd}<&-; return 1; }
    cp -a -- "$source" "$tmp" || { rm -rf -- "$tmp"; exec {fd}<&-; return 1; }
    mv -f -- "$tmp" "/proc/self/fd/$fd/$name"; rc=$?; [ "$rc" -eq 0 ] || rm -f -- "$tmp"; exec {fd}<&-; return "$rc"
}

core_target_snapshot_file() {
    local root=$1 path=$2 destination=$3 parent fd name expected actual
    core_target_validate_final "$root" "$path" "$root$path" || return 1
    [ -e "$root$path" ] || [ -L "$root$path" ] || return 0
    parent=$(dirname "$path"); exec {fd}<"$root$parent" || return 1
    expected=$(realpath -e -- "$root$parent") || { exec {fd}<&-; return 1; }
    actual=$(readlink -e -- "/proc/self/fd/$fd") || { exec {fd}<&-; return 1; }
    [ "$actual" = "$expected" ] || { exec {fd}<&-; return 1; }
    name=$(basename "$path"); mkdir -p "$(dirname "$destination")" || { exec {fd}<&-; return 1; }
    cp -a -- "/proc/self/fd/$fd/$name" "$destination"; local rc=$?; exec {fd}<&-; return "$rc"
}

core_target_rmdir() {
    local root=$1 path=$2 parent fd name expected actual rc
    core_target_validate_final "$root" "$path" "$root$path" || return 1
    [ -d "$root$path" ] || return 0
    parent=$(dirname "$path"); exec {fd}<"$root$parent" || return 1
    expected=$(realpath -e -- "$root$parent") || { exec {fd}<&-; return 1; }
    actual=$(readlink -e -- "/proc/self/fd/$fd") || { exec {fd}<&-; return 1; }
    [ "$actual" = "$expected" ] || { exec {fd}<&-; return 1; }
    name=$(basename "$path"); rmdir -- "/proc/self/fd/$fd/$name" 2>/dev/null; rc=$?; exec {fd}<&-; return "$rc"
}

core_target_chmod() {
    local root=$1 path=$2 mode=$3 fd name rc
    core_target_parent_fd "$root" "$path" || return 1
    fd=$CORE_TARGET_PARENT_FD; name=$(basename "$path")
    chmod "$mode" -- "/proc/self/fd/$fd/$name"; rc=$?; exec {fd}<&-; return "$rc"
}

core_target_validate_live() {
    [ "$(id -u)" -eq 0 ] || { core_die 'modalità live richiede root'; return 1; }
    [ "$(realpath -e /)" = / ] || return 1
    [ -r /etc/os-release ] || { core_die 'sistema live senza etc/os-release'; return 1; }
    if [ "${PS5_TOOLS_ALLOW_LIVE:-0}" != 1 ]; then
        if ! grep -Eiq 'playstation|ps5' /sys/firmware/devicetree/base/model /sys/devices/virtual/dmi/id/product_name /etc/os-release 2>/dev/null &&
           ! compgen -G '/sys/devices/platform/ps5*' >/dev/null && ! compgen -G '/dev/ps5*' >/dev/null; then
            core_die 'ambiente live PS5 non riconosciuto; usare --root per offline oppure PS5_TOOLS_ALLOW_LIVE=1'; return 1
        fi
    fi
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

core_target_write_reapply_request() {
    local root=$1 id=$2 phase=$3 revision=$4 dir request_fd tmp expected actual; dir="$root/var/lib/ps5-cachyos-tools/state/reapply"
    core_target_validate_final "$root" /var/lib/ps5-cachyos-tools/state/reapply "$dir" || return 1
    [ -d "$dir" ] && [ ! -L "$dir" ] || return 1
    core_target_validate_final "$root" /var/lib/ps5-cachyos-tools/state/reapply "$dir" || return 1
    exec {request_fd}<"$dir" || return 1
    expected=$(realpath -e -- "$dir") || { exec {request_fd}<&-; return 1; }
    actual=$(readlink -e -- "/proc/self/fd/$request_fd") || { exec {request_fd}<&-; return 1; }
    [ "$actual" = "$expected" ] || { exec {request_fd}<&-; return 1; }
    tmp=$(mktemp "/proc/self/fd/$request_fd/.$id.request.XXXXXX") || { exec {request_fd}<&-; return 1; }
    printf 'id=%s\nphase=%s\nrevision=%s\nrequested_at=%s\n' "$id" "$phase" "$revision" "$(date +%s%N)" > "$tmp" || { rm -f -- "$tmp"; exec {request_fd}<&-; return 1; }
    mv -f -- "$tmp" "/proc/self/fd/$request_fd/$id.request" || { rm -f -- "$tmp"; exec {request_fd}<&-; return 1; }
    exec {request_fd}<&-
}
