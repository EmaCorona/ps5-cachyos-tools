#!/usr/bin/env bash
set -u
root=$1
operation=${2:-install}
if [ "$operation" = preflight ]; then
    helper=${PS5_GAMESCOPE_PACKAGE_HELPER:-${CORE_REPO:?repository checkout non disponibile}/modules/gamescope/files/ps5-gamescope-package}
else
    helper=${PS5_GAMESCOPE_PACKAGE_HELPER:-$root/usr/local/libexec/ps5-cachyos-tools/gamescope-package}
fi
if [ "$operation" = rollback ] && { [ ! -e "$helper" ] || [ -L "$helper" ]; } && \
    [ ! -e "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] && \
    [ ! -L "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ]; then
    # The module install hook may have failed before its package helper ran.
    # With no external transaction journal there is nothing to compensate.
    exit 0
fi
[[ "$helper" = /* && -x "$helper" && ! -L "$helper" ]] || { printf 'Gamescope: helper pacman assente o non valido\n' >&2; exit 1; }
CORE_REPO=${CORE_REPO:?repository checkout non disponibile} \
CORE_INSTALL_MODE=${CORE_INSTALL_MODE:-offline} \
PS5_GAMESCOPE_PACKAGE_SOURCE="$CORE_REPO/packaging/gamescope" \
"$helper" "$operation" "$root"
