#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/ps5-cachyos-tools"
tmp=$(mktemp -d /tmp/ps5-vram-test.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0 fail=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass+1)); }
no() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }

root="$tmp/root"; boot="$tmp/boot"
mkdir -p "$root/etc" "$boot"
printf 'ID=fixture\nNAME=Fixture\n' > "$root/etc/os-release"

if CORE_TEST_MODE=1 "$CLI" install --root "$root" --module vram --dry-run >/dev/null 2>&1; then
    no 'preflight VRAM accetta un install senza mount boot'
else
    ok 'preflight richiede mount boot esplicito'
fi
if CORE_TEST_MODE=1 "$CLI" install --root "$root" --boot "$boot" --module vram --vram-size 9GiB --dry-run >/dev/null 2>&1; then
    no 'dimensione sopra 8 GiB accettata'
else
    ok 'dimensione sopra 8 GiB rifiutata'
fi
if CORE_TEST_MODE=1 "$CLI" install --root "$root" --boot "$boot" --module vram --dry-run >/dev/null 2>&1; then
    ok 'dry-run VRAM con mount boot esplicito'
else
    no 'dry-run VRAM con mount boot esplicito'
fi

if CORE_TEST_MODE=1 "$CLI" install --root "$root" --boot "$boot" --module vram >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x100000000 ] && \
   grep -qx 'VRAM_BYTES=0x100000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'default 4 GiB scritto su FAT e config root'
else
    no 'default 4 GiB scritto su FAT e config root'
fi

printf 'VRAM_BYTES=0x80000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
printf '0x100000000\n' > "$boot/vram.txt"
if CORE_TEST_MODE=1 "$CLI" install --root "$root" --boot "$boot" --module vram >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x80000000 ]; then
    ok 'configurazione persistente esistente mantenuta'
else
    no 'configurazione persistente esistente mantenuta'
fi

if CORE_TEST_MODE=1 "$CLI" install --root "$root" --boot "$boot" --module vram --vram-size 6GiB >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x180000000 ] && \
   grep -qx 'VRAM_BYTES=0x180000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'opzione install-time sovrascrive la configurazione esistente'
else
    no 'opzione install-time sovrascrive la configurazione esistente'
fi

if CORE_TEST_MODE=1 "$CLI" check --root "$root" >/dev/null 2>&1 && \
   CORE_TEST_MODE=1 bash "$root/usr/lib/ps5-cachyos-tools/modules/vram/boot.sh" "$root"; then
    ok 'check e boot hook validano la configurazione installata'
else
    no 'check o boot hook non validano la configurazione installata'
fi

rollback_root="$tmp/rollback-root"; rollback_boot="$tmp/rollback-boot"
mkdir -p "$rollback_root/etc" "$rollback_boot"
printf 'ID=fixture\nNAME=Fixture\n' > "$rollback_root/etc/os-release"
printf '0x80000000\n' > "$rollback_boot/vram.txt"
if CORE_TEST_MODE=1 CORE_BOOT_TARGET="$rollback_boot" CORE_CONFIG_ROOT="$rollback_root" CORE_INSTALL_MODE=offline \
   bash -c 'source "$1/lib/core/log.sh"; source "$1/lib/core/target.sh"; source "$1/lib/core/registry.sh"; source "$1/lib/core/dependencies.sh"; source "$1/lib/core/state.sh"; source "$1/lib/core/installer.sh"; source "$1/lib/core/service.sh"; core_service_install(){ return 77; }; core_install "$2" "$1" vram' _ "$ROOT" "$rollback_root" >/dev/null 2>&1; then
    no 'errore successivo al hook non fallisce l’installazione'
elif [ "$(cat "$rollback_boot/vram.txt")" = 0x80000000 ] && \
     [ ! -e "$rollback_root/etc/ps5-cachyos-tools/vram.conf" ]; then
    ok 'rollback transazionale ripristina vram.txt esterno e config root'
else
    no 'rollback transazionale non ripristina vram.txt esterno'
fi

printf '%s test superati, %s falliti\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
