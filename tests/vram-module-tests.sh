#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
CLI="$ROOT/bin/ps5-cachyos-tools"
tmp=$(mktemp -d /tmp/ps5-vram-test.XXXXXX)
runner_root=''
trap 'rm -rf "$tmp"; [ -z "$runner_root" ] || rm -rf "$runner_root"' EXIT
pass=0 fail=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass+1)); }
no() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
install_vram() { CORE_TEST_MODE=1 "$CLI" install --root "$1" --boot "$2" --module vram "${@:3}"; }

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
if install_vram "$root" "$boot" --dry-run >/dev/null 2>&1; then
    ok 'dry-run VRAM con mount boot esplicito'
else
    no 'dry-run VRAM con mount boot esplicito'
fi

if install_vram "$root" "$boot" >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x20000000 ] && \
   grep -qx 'VRAM_BYTES=0x20000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'default 512 MiB scritto su FAT e config root'
else
    no 'default 512 MiB scritto su FAT e config root'
fi

# A single persisted source remains authoritative and initializes its mirror.
printf 'VRAM_BYTES=0x80000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
rm -f "$boot/vram.txt"
if install_vram "$root" "$boot" >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x80000000 ]; then
    ok 'config root valida mantenuta e specchiata su FAT'
else
    no 'config root valida mantenuta e specchiata su FAT'
fi
rm -f "$root/etc/ps5-cachyos-tools/vram.conf"
printf '0xc0000000\n' > "$boot/vram.txt"
if install_vram "$root" "$boot" >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0xc0000000 ] && \
   grep -qx 'VRAM_BYTES=0xc0000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'config FAT valida mantenuta e specchiata in root'
else
    no 'config FAT valida mantenuta e specchiata in root'
fi

# Matching copies remain stable; mismatches fail without changing either file.
printf 'VRAM_BYTES=0xc0000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
if install_vram "$root" "$boot" >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0xc0000000 ]; then
    ok 'copie persistenti concordi mantenute'
else
    no 'copie persistenti concordi mantenute'
fi
printf 'VRAM_BYTES=0x80000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
printf '0x140000000\n' > "$boot/vram.txt"
root_before=$(cat "$root/etc/ps5-cachyos-tools/vram.conf")
boot_before=$(cat "$boot/vram.txt")
if install_vram "$root" "$boot" >/dev/null 2>&1; then
    no 'configurazioni discordanti sovrascritte senza scelta esplicita'
elif [ "$(cat "$root/etc/ps5-cachyos-tools/vram.conf")" = "$root_before" ] && \
     [ "$(cat "$boot/vram.txt")" = "$boot_before" ]; then
    ok 'conflitto root/FAT rifiutato senza scritture'
else
    no 'conflitto root/FAT ha modificato una configurazione'
fi

# An explicit valid value resolves a conflict, but malformed inputs remain fail-closed.
if install_vram "$root" "$boot" --vram-size 6GiB >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x180000000 ] && \
   grep -qx 'VRAM_BYTES=0x180000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'opzione install-time risolve esplicitamente il conflitto'
else
    no 'opzione install-time non risolve il conflitto'
fi
printf 'invalid\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
if install_vram "$root" "$boot" --vram-size 6GiB >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x180000000 ] && \
   grep -qx 'VRAM_BYTES=0x180000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'override CLI esplicito corregge una config root regolare malformata'
else
    no 'override CLI non corregge la config root regolare malformata'
fi
printf 'invalid\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
root_before=$(cat "$root/etc/ps5-cachyos-tools/vram.conf")
boot_before=$(cat "$boot/vram.txt")
if install_vram "$root" "$boot" >/dev/null 2>&1; then
    no 'config root malformata accettata senza override'
elif [ "$(cat "$root/etc/ps5-cachyos-tools/vram.conf")" = "$root_before" ] && \
     [ "$(cat "$boot/vram.txt")" = "$boot_before" ]; then
    ok 'config root malformata rifiutata senza override e senza scritture'
else
    no 'input root malformato ha causato scritture'
fi
printf 'VRAM_BYTES=0x180000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
printf 'invalid\n' > "$boot/vram.txt"
root_before=$(cat "$root/etc/ps5-cachyos-tools/vram.conf")
boot_before=$(cat "$boot/vram.txt")
if install_vram "$root" "$boot" >/dev/null 2>&1; then
    no 'vram.txt malformato accettato senza override'
elif [ "$(cat "$root/etc/ps5-cachyos-tools/vram.conf")" = "$root_before" ] && \
     [ "$(cat "$boot/vram.txt")" = "$boot_before" ]; then
    ok 'vram.txt malformato rifiutato senza override e senza scritture'
else
    no 'rifiuto vram.txt malformato ha modificato una configurazione'
fi
if install_vram "$root" "$boot" --vram-size 4GiB >/dev/null 2>&1 && \
   [ "$(cat "$boot/vram.txt")" = 0x100000000 ] && \
   grep -qx 'VRAM_BYTES=0x100000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'override CLI esplicito corregge vram.txt regolare malformato'
else
    no 'override CLI non corregge vram.txt regolare malformato'
fi

config_external="$tmp/config-external"
printf 'untouched\n' > "$config_external"
rm -f "$root/etc/ps5-cachyos-tools/vram.conf"
ln -s "$config_external" "$root/etc/ps5-cachyos-tools/vram.conf"
root_before=$(cat "$config_external")
boot_before=$(cat "$boot/vram.txt")
if install_vram "$root" "$boot" --vram-size 6GiB >/dev/null 2>&1; then
    no 'symlink config root accettato'
elif [ -L "$root/etc/ps5-cachyos-tools/vram.conf" ] && \
     [ "$(cat "$config_external")" = "$root_before" ] && \
     [ "$(cat "$boot/vram.txt")" = "$boot_before" ]; then
    ok 'symlink config root rifiutato senza modificare i target'
else
    no 'rifiuto symlink root ha modificato un target'
fi
rm -f "$root/etc/ps5-cachyos-tools/vram.conf"
printf 'VRAM_BYTES=0x180000000\n' > "$root/etc/ps5-cachyos-tools/vram.conf"
boot_external="$tmp/boot-external"
printf '0x40000000\n' > "$boot_external"
rm -f "$boot/vram.txt"
ln -s "$boot_external" "$boot/vram.txt"
boot_before=$(cat "$boot_external")
if install_vram "$root" "$boot" --vram-size 6GiB >/dev/null 2>&1; then
    no 'symlink vram.txt accettato'
elif [ -L "$boot/vram.txt" ] && [ "$(cat "$boot_external")" = "$boot_before" ] && \
     grep -qx 'VRAM_BYTES=0x180000000' "$root/etc/ps5-cachyos-tools/vram.conf"; then
    ok 'symlink FAT rifiutato senza modificare i target'
else
    no 'rifiuto symlink FAT ha modificato un target'
fi
rm -f "$boot/vram.txt"
printf '0x180000000\n' > "$boot/vram.txt"

if install_vram "$root" "$boot" --vram-size 9GiB >/dev/null 2>&1; then
    no 'dimensione sopra 8 GiB accettata dall’install'
else
    ok 'dimensione sopra 8 GiB rifiutata dall’install'
fi

if CORE_TEST_MODE=1 "$CLI" check --root "$root" >/dev/null 2>&1 && \
   CORE_TEST_MODE=1 bash "$root/usr/lib/ps5-cachyos-tools/modules/vram/boot.sh" "$root"; then
    ok 'check e boot hook validano la configurazione installata'
else
    no 'check o boot hook non validano la configurazione installata'
fi

# The VRAM task obeys registry overrides and boot-runner enabled semantics.
runner_root=$(mktemp -d /tmp/ps5-tools-core.vram.XXXXXX)
runner_boot="$runner_root/boot"
mkdir -p "$runner_root/etc" "$runner_boot"
printf 'ID=fixture\nNAME=Fixture\n' > "$runner_root/etc/os-release"
if ! install_vram "$runner_root" "$runner_boot" >/dev/null 2>&1; then
    no 'fixture installata per il test lifecycle VRAM'
else
    override_dir="$runner_root/etc/ps5-cachyos-tools/modules.d"
    runner="$runner_root/usr/lib/ps5-cachyos-tools/boot-runner"
    mkdir -p "$override_dir"
    printf 'ENABLED=false\n' > "$override_dir/vram.conf"
    if CORE_TEST_MODE=1 CORE_BOOT_ID=vram-disabled CORE_PREFIX="$runner_root/usr/lib/ps5-cachyos-tools" \
       CORE_STATE_ROOT="$runner_root" CORE_RUN_ROOT="$runner_root" CORE_CONFIG_ROOT="$runner_root" \
       "$runner" normal >"$tmp/vram-disabled.out" 2>&1 && \
       grep -qx 'status=SKIPPED_DISABLED' "$runner_root/var/lib/ps5-cachyos-tools/state/modules/vram.state"; then
        ok 'override ENABLED=false disabilita il task VRAM nel boot runner'
    else
        cat "$tmp/vram-disabled.out" >&2
        no 'override ENABLED=false non produce SKIPPED_DISABLED'
    fi
    printf 'ENABLED=true\n' > "$override_dir/vram.conf"
    if CORE_TEST_MODE=1 CORE_BOOT_ID=vram-enabled CORE_PREFIX="$runner_root/usr/lib/ps5-cachyos-tools" \
       CORE_STATE_ROOT="$runner_root" CORE_RUN_ROOT="$runner_root" CORE_CONFIG_ROOT="$runner_root" \
       "$runner" normal >"$tmp/vram-enabled.out" 2>&1 && \
       grep -qx 'status=SUCCESS' "$runner_root/var/lib/ps5-cachyos-tools/state/modules/vram.state"; then
        ok 'override ENABLED=true rende il task eleggibile al boot successivo'
    else
        cat "$tmp/vram-enabled.out" >&2
        no 'override ENABLED=true non riabilita il task al boot successivo'
    fi
    rm -f "$override_dir/vram.conf"
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

# Default removal keeps the root configuration; purge removes only that mirror.
remove_root="$tmp/remove-root"; remove_boot="$tmp/remove-boot"
mkdir -p "$remove_root/etc" "$remove_boot"
printf 'ID=fixture\nNAME=Fixture\n' > "$remove_root/etc/os-release"
if install_vram "$remove_root" "$remove_boot" >/dev/null 2>&1 && \
   CORE_TEST_MODE=1 "$CLI" remove --module vram --root "$remove_root" >/dev/null 2>&1 && \
   [ -f "$remove_root/etc/ps5-cachyos-tools/vram.conf" ] && \
   [ "$(cat "$remove_boot/vram.txt")" = 0x20000000 ]; then
    ok 'remove predefinito conserva vram.conf e vram.txt'
else
    no 'remove predefinito non conserva i file di configurazione'
fi
purge_root="$tmp/purge-root"; purge_boot="$tmp/purge-boot"
mkdir -p "$purge_root/etc" "$purge_boot"
printf 'ID=fixture\nNAME=Fixture\n' > "$purge_root/etc/os-release"
if install_vram "$purge_root" "$purge_boot" >/dev/null 2>&1 && \
   CORE_TEST_MODE=1 "$CLI" remove --module vram --root "$purge_root" --purge-config >/dev/null 2>&1 && \
   [ ! -e "$purge_root/etc/ps5-cachyos-tools/vram.conf" ] && \
   [ "$(cat "$purge_boot/vram.txt")" = 0x20000000 ]; then
    ok 'remove --purge-config rimuove solo il mirror root e conserva vram.txt'
else
    no 'remove --purge-config non rispetta la persistenza FAT'
fi

printf '%s test superati, %s falliti\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
