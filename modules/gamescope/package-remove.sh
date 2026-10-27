#!/usr/bin/env bash
set -u
root=$1
operation=${2:-remove}
backup=${CORE_REMOVE_BACKUP_ROOT:-}
if [ -n "$backup" ]; then
    [[ "$backup" = /* && -d "$backup" && ! -L "$backup" ]] || exit 1
    helper=${PS5_GAMESCOPE_PACKAGE_HELPER:-$backup/usr/local/libexec/ps5-cachyos-tools/gamescope-package}
else
    helper=${PS5_GAMESCOPE_PACKAGE_HELPER:-$root/usr/local/libexec/ps5-cachyos-tools/gamescope-package}
fi
[ -x "$helper" ] && [ ! -L "$helper" ] || { printf 'Gamescope: helper pacman assente o non valido\n' >&2; exit 1; }
CORE_TARGET_ROOT="$root" "$helper" "$operation" "$root"
