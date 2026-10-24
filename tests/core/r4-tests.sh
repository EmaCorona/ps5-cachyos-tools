#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$ROOT/tests/core/assertions.sh"
source "$ROOT/lib/core/log.sh"
source "$ROOT/lib/core/target.sh"
source "$ROOT/lib/core/registry.sh"
source "$ROOT/lib/core/dependencies.sh"
source "$ROOT/lib/core/state.sh"
source "$ROOT/lib/core/service.sh"
source "$ROOT/lib/core/installer.sh"

tmp=$(mktemp -d /tmp/ps5-tools-r4.XXXXXX)
export CORE_TEST_MODE=1
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

root="$tmp/root"; mkdir -p "$root/etc"; printf 'ID=linux\nNAME=r4\n' > "$root/etc/os-release"
repo="$tmp/repo"; cp -a "$ROOT/." "$repo"

rm -f "$repo/modules/fan/readiness.sh"
if CORE_CONFIG_ROOT="$root" core_install_preflight "$root" "$repo" fan >/dev/null 2>&1; then no 'READINESS_HOOK mancante accettato dal preflight'; else ok 'READINESS_HOOK mancante rifiutato dal preflight'; fi
cp "$ROOT/modules/fan/readiness.sh" "$repo/modules/fan/readiness.sh"
chmod 0644 "$repo/modules/fan/readiness.sh"
if CORE_CONFIG_ROOT="$root" core_install_preflight "$root" "$repo" fan >/dev/null 2>&1; then no 'READINESS_HOOK non eseguibile accettato dal preflight'; else ok 'READINESS_HOOK non eseguibile rifiutato dal preflight'; fi
chmod 0755 "$repo/modules/fan/readiness.sh"

if CORE_CONFIG_ROOT="$root" core_install_preflight "$root" "$repo" fan >/dev/null 2>&1 && "$repo/bin/ps5-cachyos-tools" install --root "$root" --module fan >/dev/null 2>&1; then
    printf changed > "$root/usr/local/bin/ps5-fan-daemon"
    if CORE_INSTALL_MODE=offline core_install_body "$root" "$repo" fan >/dev/null 2>&1 && [ -s "$root/run/ps5-cachyos-tools/runtime-changed/fan" ]; then
        ok 'runtime hook conserva il marker fino al service hook'
    else
        no 'runtime hook perde il marker prima del service hook'
    fi
    cp "$repo/bin/ps5-fan-daemon" "$root/usr/local/bin/ps5-fan-daemon"
    mkdir -p "$root/var/lib/ps5-cachyos-tools/state/reapply"
    printf 'id=fan\nphase=normal\nrevision=1\nrequested_at=99\n' > "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request"
    if "$root/usr/local/bin/ps5-cachyos-tools" remove fan --root "$root" --keep-config && [ ! -e "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request" ]; then
        ok 'remove annulla la richiesta reapply pendente'
    else
        no 'remove lascia una richiesta reapply pendente'
    fi

failed_remove="$tmp/failed-remove"; mkdir -p "$failed_remove/etc"; printf 'ID=linux\nNAME=r4\n' > "$failed_remove/etc/os-release"
"$repo/bin/ps5-cachyos-tools" install --root "$failed_remove" --module fan >/dev/null 2>&1
mkdir -p "$failed_remove/var/lib/ps5-cachyos-tools/state/reapply"
printf 'id=fan\nphase=normal\nrevision=1\nrequested_at=100\n' > "$failed_remove/var/lib/ps5-cachyos-tools/state/reapply/fan.request"
printf '#!/usr/bin/env bash\nprintf failure > "$1/etc/fan-remove-failure"\nexit 23\n' > "$failed_remove/usr/lib/ps5-cachyos-tools/modules/fan/remove.sh"
chmod 0755 "$failed_remove/usr/lib/ps5-cachyos-tools/modules/fan/remove.sh"
if "$failed_remove/usr/local/bin/ps5-cachyos-tools" remove fan --root "$failed_remove" --keep-config >/dev/null 2>&1; then
    no 'remove fallito accettato'
elif [ -f "$failed_remove/var/lib/ps5-cachyos-tools/state/reapply/fan.request" ]; then
    ok 'rollback remove ripristina la richiesta reapply'
else
    no 'rollback remove ha perso la richiesta reapply'
fi
else
    no 'fixture fan R4 non installabile'
fi

remove_target="$tmp/remove-target"; remove_link="$tmp/remove-link"
mkdir -p "$remove_target/etc"; printf 'ID=linux\nNAME=r4\n' > "$remove_target/etc/os-release"
if "$repo/bin/ps5-cachyos-tools" install --root "$remove_target" --module fan >/dev/null 2>&1; then
    printf sentinel > "$tmp/remove-sentinel"
    ln -s "$remove_target" "$remove_link"
    source "$remove_target/usr/lib/ps5-cachyos-tools/fan.sh"
    if module_fan_remove "$remove_link" 1 >/dev/null 2>&1; then
        no 'remove standalone accetta una root symlinkata'
    elif [ -f "$remove_target/etc/ps5-fan/.ps5-cachyos-tools.manifest" ] && [ "$(cat "$tmp/remove-sentinel")" = sentinel ]; then
        ok 'remove standalone rifiuta root symlinkata senza alterare il target'
    else
        no 'remove standalone altera il target dopo root symlinkata'
    fi
else
    no 'fixture remove standalone non installabile'
fi

backup_root="$tmp/backup-root"; backup_outside="$tmp/backup-outside"
mkdir -p "$backup_root/etc" "$backup_outside"; printf 'ID=linux\nNAME=r4\n' > "$backup_root/etc/os-release"
if "$repo/bin/ps5-cachyos-tools" install --root "$backup_root" --module fan >/dev/null 2>&1; then
    mkdir -p "$backup_root/var/lib/ps5-cachyos-tools"
    ln -s "$backup_outside" "$backup_root/var/lib/ps5-cachyos-tools/backups"
    source "$backup_root/usr/lib/ps5-cachyos-tools/fan.sh"
    if module_fan_run "$backup_root" >/dev/null 2>&1; then
        no 'backup fan accetta var symlinkata'
    elif [ -z "$(find "$backup_outside" -mindepth 1 -print -quit)" ]; then
        ok 'backup fan rifiuta var symlinkata senza scrivere fuori root'
    else
        no 'backup fan ha scritto fuori root tramite var symlinkata'
    fi
else
    no 'fixture backup fan non installabile'
fi

remove_etc_root="$tmp/remove-etc-root"; remove_etc_outside="$tmp/remove-etc-outside"
mkdir -p "$remove_etc_root/etc" "$remove_etc_outside"; printf 'ID=linux\nNAME=r4\n' > "$remove_etc_root/etc/os-release"
if "$repo/bin/ps5-cachyos-tools" install --root "$remove_etc_root" --module fan >/dev/null 2>&1; then
    mv "$remove_etc_root/etc" "$remove_etc_outside/real-etc"
    ln -s "$remove_etc_outside/real-etc" "$remove_etc_root/etc"
    if (source "$remove_etc_root/usr/lib/ps5-cachyos-tools/fan.sh"; module_fan_remove "$remove_etc_root" 0) >/dev/null 2>&1; then
        no 'remove standalone accetta antenato etc symlinkato'
    elif [ -f "$remove_etc_outside/real-etc/ps5-fan/.ps5-cachyos-tools.manifest" ]; then
        ok 'remove standalone rifiuta antenato etc symlinkato senza cancellare fuori root'
    else
        no 'remove standalone ha cancellato artefatti tramite etc symlinkato'
    fi
else
    no 'fixture remove etc non installabile'
fi

rollback_root="$tmp/rollback-root"; mkdir -p "$rollback_root/etc"; printf 'ID=linux\nNAME=r4\n' > "$rollback_root/etc/os-release"
rollback_repo="$tmp/rollback-repo"; cp -a "$ROOT/." "$rollback_repo"
cat > "$rollback_repo/modules/fan/install.sh" <<'EOF'
#!/usr/bin/env bash
set -u
root=$1
source "$CORE_REPO/lib/modules/fan.sh"
module_fan_run "$root" || exit $?
printf 'transient-change\n' > "$root/etc/ps5-fan/state"
exit 23
EOF
chmod 0755 "$rollback_repo/modules/fan/install.sh"
if CORE_CONFIG_ROOT="$rollback_root" CORE_INSTALL_MODE=offline core_install "$rollback_root" "$rollback_repo" fan; then
    no 'fallimento post-hook fan accettato'
elif [ ! -e "$rollback_root/etc/ps5-fan/state" ] && [ ! -e "$rollback_root/usr/lib/ps5-cachyos-tools" ]; then
    ok 'rollback install rimuove i file fan creati dalla transazione'
else
    no 'rollback install lascia file fan creati dalla transazione'
fi

escape_root="$tmp/escape-root"; outside="$tmp/outside"; backup="$tmp/escape-backup"
mkdir -p "$escape_root/etc" "$outside" "$backup"; printf sentinel > "$outside/sentinel"; ln -s "$outside" "$escape_root/etc/evil"
printf '/etc/evil/sentinel\n' > "$backup/.paths"; : > "$backup/.present"
if core_txn_restore "$escape_root" "$backup" >/dev/null 2>&1; then
    no 'rollback ha seguito un antenato symlinkato'
elif [ "$(cat "$outside/sentinel")" = sentinel ]; then
    ok 'rollback rifiuta escape symlink senza toccare la sentinella esterna'
else
    no 'rollback ha modificato la sentinella esterna'
fi

printf '%s\n' "$pass test R4 superati, $fail falliti"
[ "$fail" -eq 0 ]
