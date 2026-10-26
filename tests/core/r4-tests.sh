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

framework_remove="$tmp/framework-remove"; mkdir -p "$framework_remove/etc"; printf 'ID=linux\nNAME=framework-remove\n' > "$framework_remove/etc/os-release"
if "$repo/bin/ps5-cachyos-tools" install --root "$framework_remove" --module fan >/dev/null 2>&1; then
    rm -f -- "$framework_remove/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service"
    source "$repo/bin/ps5-cachyos-tools" list >/dev/null 2>&1 || true
    if CORE_KEEP_CONFIG=0 core_cli_run_remove_hook "$framework_remove" fan \
        "$framework_remove/usr/lib/ps5-cachyos-tools/modules/fan/remove.sh" 0 >/dev/null 2>&1 && \
            [ ! -e "$framework_remove/etc/ps5-fan/fan.conf" ] && [ -f "$framework_remove/etc/ps5-fan/.ps5-cachyos-tools.manifest" ]; then
        ok 'remove framework gestisce il service già disabilitato prima dell hook'
    else
        no 'remove framework fallisce dopo la disabilitazione del service'
    fi
else
    no 'fixture remove framework non installabile'
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

run_escape_root="$tmp/run-escape-root"; run_outside="$tmp/run-outside"; run_backup="$tmp/run-escape-backup"
mkdir -p "$run_escape_root" "$run_outside" "$run_backup"; printf sentinel > "$run_outside/sentinel"
ln -s "$run_outside" "$run_escape_root/run"
: > "$run_backup/.paths"; : > "$run_backup/.present"
if core_txn_restore "$run_escape_root" "$run_backup" >/dev/null 2>&1; then
    no 'rollback ha seguito run symlinkato'
elif [ "$(cat "$run_outside/sentinel")" = sentinel ]; then
    ok 'rollback rifiuta run symlinkato senza cancellare la sentinella esterna'
else
    no 'rollback ha modificato la sentinella esterna tramite run symlinkato'
fi

request_escape_root="$tmp/request-escape-root"; request_outside="$tmp/request-outside"
mkdir -p "$request_escape_root/var/lib/ps5-cachyos-tools/state/reapply" "$request_outside"
printf request > "$request_outside/fan.request"
rm -rf "$request_escape_root/var"
ln -s "$request_outside" "$request_escape_root/var"
if core_remove_module_artifacts "$request_escape_root" fan >/dev/null 2>&1; then
    no 'cleanup request accetta var symlinkata'
elif [ -f "$request_outside/fan.request" ]; then
    ok 'cleanup request rifiuta var symlinkata senza cancellare fuori root'
else
    no 'cleanup request ha cancellato la request esterna'
fi

dir_escape_root="$tmp/dir-escape-root"; dir_outside="$tmp/dir-outside"; dir_backup="$tmp/dir-escape-backup"
mkdir -p "$dir_escape_root/var" "$dir_outside/lib/ps5-cachyos-tools" "$dir_backup"
ln -s "$dir_outside/lib" "$dir_escape_root/var/lib"
: > "$dir_backup/.paths"; : > "$dir_backup/.present"
printf '/var/lib/ps5-cachyos-tools\n' > "$dir_backup/.created-dirs"
if core_txn_restore "$dir_escape_root" "$dir_backup" >/dev/null 2>&1; then
    no 'rollback ha seguito var/lib symlinkato durante cleanup directory'
elif [ -d "$dir_outside/lib/ps5-cachyos-tools" ]; then
    ok 'rollback rifiuta var/lib symlinkato senza rimuovere fuori root'
else
    no 'rollback ha rimosso directory esterna tramite var/lib symlinkato'
fi

lock_escape_root="$tmp/lock-escape-root"; lock_outside="$tmp/lock-outside"
mkdir -p "$lock_escape_root" "$lock_outside"; ln -s "$lock_outside" "$lock_escape_root/run"
if core_txn_lock "$lock_escape_root" >/dev/null 2>&1; then
    no 'transaction lock accetta run symlinkato'
elif [ -z "$(find "$lock_outside" -mindepth 1 -print -quit)" ]; then
    ok 'transaction lock rifiuta run symlinkato senza scrivere fuori root'
else
    no 'transaction lock ha scritto fuori root tramite run symlinkato'
fi

reset_root="$tmp/reset-root"; reset_outside="$tmp/reset-outside"
mkdir -p "$reset_root/etc" "$reset_outside"; printf 'ID=linux\nNAME=r4\n' > "$reset_root/etc/os-release"
if "$repo/bin/ps5-cachyos-tools" install --root "$reset_root" --module fan >/dev/null 2>&1; then
    mkdir -p "$reset_root/var/lib/ps5-cachyos-tools/state"; printf sentinel > "$reset_outside/fan.state"
    rm -rf "$reset_root/var/lib/ps5-cachyos-tools/state/modules"; ln -s "$reset_outside" "$reset_root/var/lib/ps5-cachyos-tools/state/modules"
    if "$reset_root/usr/local/bin/ps5-cachyos-tools" reset fan --root "$reset_root" >/dev/null 2>&1; then
        no 'reset accetta state/modules symlinkato'
    elif [ "$(cat "$reset_outside/fan.state")" = sentinel ]; then
        ok 'reset rifiuta state/modules symlinkato senza cancellare fuori root'
    else
        no 'reset ha cancellato stato esterno tramite state/modules symlinkato'
    fi
else
    no 'fixture reset non installabile'
fi

traversal_root="$tmp/traversal-root"; traversal_outside="$tmp/traversal-outside"; traversal_backup="$tmp/traversal-backup"
mkdir -p "$traversal_root" "$traversal_outside" "$traversal_backup"; printf sentinel > "$traversal_outside/sentinel"
printf '/../../../../%s/sentinel\n' "${traversal_outside#/}" > "$traversal_backup/.paths"; : > "$traversal_backup/.present"
if core_txn_restore "$traversal_root" "$traversal_backup" >/dev/null 2>&1; then
    no 'rollback accetta percorso con traversal ..'
elif [ "$(cat "$traversal_outside/sentinel")" = sentinel ]; then
    ok 'rollback rifiuta traversal .. senza cancellare fuori root'
else
    no 'rollback ha cancellato la sentinella tramite traversal ..'
fi

remove_hook_root="$tmp/remove-hook-root"; remove_hook_outside="$tmp/remove-hook-outside"
mkdir -p "$remove_hook_root/etc" "$remove_hook_outside"; printf 'ID=linux\nNAME=r4\n' > "$remove_hook_root/etc/os-release"; printf sentinel > "$remove_hook_outside/fan.state"
if "$repo/bin/ps5-cachyos-tools" install --root "$remove_hook_root" --module fan >/dev/null 2>&1; then
    printf '#!/usr/bin/env bash\nrm -rf -- "$1/var/lib/ps5-cachyos-tools/state/modules"\nln -s -- "%s" "$1/var/lib/ps5-cachyos-tools/state/modules"\n' "$remove_hook_outside" > "$remove_hook_root/usr/lib/ps5-cachyos-tools/modules/fan/remove.sh"
    chmod 0755 "$remove_hook_root/usr/lib/ps5-cachyos-tools/modules/fan/remove.sh"
    if "$remove_hook_root/usr/local/bin/ps5-cachyos-tools" remove fan --root "$remove_hook_root" --keep-config >/dev/null 2>&1; then
        no 'remove post-hook accetta state/modules symlinkato'
    elif [ "$(cat "$remove_hook_outside/fan.state")" = sentinel ]; then
        ok 'remove post-hook rifiuta state/modules symlinkato senza cancellare fuori root'
    else
        no 'remove post-hook ha cancellato stato esterno tramite state/modules symlinkato'
    fi
else
    no 'fixture remove post-hook non installabile'
fi

state_escape_root="$tmp/state-escape-root"; state_outside="$tmp/state-outside"
mkdir -p "$state_escape_root" "$state_outside"; ln -s "$state_outside" "$state_escape_root/var"
if core_state_write "$state_escape_root" fan SUCCESS always 1 0 state-escape >/dev/null 2>&1; then
    no 'state writer accetta var symlinkata'
elif [ -z "$(find "$state_outside" -mindepth 1 -print -quit)" ]; then
    ok 'state writer rifiuta var symlinkata senza scrivere fuori root'
else
    no 'state writer ha scritto fuori root tramite var symlinkata'
fi

runner_escape_root="$tmp/runner-escape-root"; runner_outside="$tmp/runner-outside"
mkdir -p "$runner_escape_root" "$runner_outside"; ln -s "$runner_outside" "$runner_escape_root/run"
if CORE_RUN_ROOT="$runner_escape_root" CORE_STATE_ROOT="$runner_escape_root" CORE_PREFIX="$ROOT" bash -c 'source "$0/lib/core/boot-runner.sh"; runner_lock' "$ROOT" >/dev/null 2>&1; then
    no 'boot runner lock accetta run symlinkato'
elif [ -z "$(find "$runner_outside" -mindepth 1 -print -quit)" ]; then
    ok 'boot runner lock rifiuta run symlinkato senza scrivere fuori root'
else
    no 'boot runner lock ha scritto fuori root tramite run symlinkato'
fi

root_link="$tmp/root-link"; root_link_target="$tmp/root-link-target"; mkdir -p "$root_link_target"; ln -s "$root_link_target" "$root_link"
if core_txn_lock "$root_link" >/dev/null 2>&1; then
    no 'transaction lock accetta root symlinkata'
elif [ -z "$(find "$root_link_target" -mindepth 1 -print -quit)" ]; then
    ok 'transaction lock rifiuta root symlinkata senza scrivere fuori root'
else
    no 'transaction lock ha scritto fuori root tramite root symlinkata'
fi

printf '%s\n' "$pass test R4 superati, $fail falliti"
[ "$fail" -eq 0 ]
