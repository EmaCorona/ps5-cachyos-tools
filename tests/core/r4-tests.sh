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
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1" >&2; fail=$((fail+1)); }

escape_root="$tmp/escape-root"; outside="$tmp/outside"; backup="$tmp/escape-backup"
mkdir -p "$escape_root/etc" "$outside" "$backup"; printf sentinel > "$outside/sentinel"; ln -s "$outside" "$escape_root/etc/evil"
printf '/etc/evil/sentinel\n' > "$backup/.paths"; : > "$backup/.present"
if core_txn_restore "$escape_root" "$backup" >/dev/null 2>&1; then no 'rollback ha seguito un antenato symlinkato'; elif grep -qx sentinel "$outside/sentinel"; then ok 'rollback rifiuta escape symlink senza toccare la sentinella esterna'; else no 'rollback ha modificato la sentinella esterna'; fi

run_escape_root="$tmp/run-escape-root"; run_outside="$tmp/run-outside"; run_backup="$tmp/run-escape-backup"
mkdir -p "$run_escape_root" "$run_outside" "$run_backup"; printf sentinel > "$run_outside/sentinel"; ln -s "$run_outside" "$run_escape_root/run"
: > "$run_backup/.paths"; : > "$run_backup/.present"
if core_txn_restore "$run_escape_root" "$run_backup" >/dev/null 2>&1; then no 'rollback ha seguito run symlinkato'; elif grep -qx sentinel "$run_outside/sentinel"; then ok 'rollback rifiuta run symlinkato senza cancellare la sentinella esterna'; else no 'rollback ha modificato la sentinella esterna tramite run symlinkato'; fi

request_escape_root="$tmp/request-escape-root"; request_outside="$tmp/request-outside"
mkdir -p "$request_escape_root/var/lib/ps5-cachyos-tools/state/reapply" "$request_outside"; printf request > "$request_outside/example.request"
rm -rf "$request_escape_root/var"; ln -s "$request_outside" "$request_escape_root/var"
if core_remove_module_artifacts "$request_escape_root" example >/dev/null 2>&1; then no 'cleanup request accetta var symlinkata'; elif [ -f "$request_outside/example.request" ]; then ok 'cleanup request rifiuta var symlinkata senza cancellare fuori root'; else no 'cleanup request ha cancellato la request esterna'; fi

dir_escape_root="$tmp/dir-escape-root"; dir_outside="$tmp/dir-outside"; dir_backup="$tmp/dir-escape-backup"
mkdir -p "$dir_escape_root/var" "$dir_outside/lib/ps5-cachyos-tools" "$dir_backup"; ln -s "$dir_outside/lib" "$dir_escape_root/var/lib"
: > "$dir_backup/.paths"; : > "$dir_backup/.present"; printf '/var/lib/ps5-cachyos-tools\n' > "$dir_backup/.created-dirs"
if core_txn_restore "$dir_escape_root" "$dir_backup" >/dev/null 2>&1; then no 'rollback ha seguito var/lib symlinkato durante cleanup directory'; elif [ -d "$dir_outside/lib/ps5-cachyos-tools" ]; then ok 'rollback rifiuta var/lib symlinkato senza rimuovere fuori root'; else no 'rollback ha rimosso directory esterna tramite var/lib symlinkato'; fi

lock_escape_root="$tmp/lock-escape-root"; lock_outside="$tmp/lock-outside"
mkdir -p "$lock_escape_root" "$lock_outside"; ln -s "$lock_outside" "$lock_escape_root/run"
if core_txn_lock "$lock_escape_root" >/dev/null 2>&1; then no 'transaction lock accetta run symlinkato'; elif [ -z "$(find "$lock_outside" -mindepth 1 -print -quit)" ]; then ok 'transaction lock rifiuta run symlinkato senza scrivere fuori root'; else no 'transaction lock ha scritto fuori root tramite run symlinkato'; fi

traversal_root="$tmp/traversal-root"; traversal_outside="$tmp/traversal-outside"; traversal_backup="$tmp/traversal-backup"
mkdir -p "$traversal_root" "$traversal_outside" "$traversal_backup"; printf sentinel > "$traversal_outside/sentinel"
printf '/../../../../%s/sentinel\n' "${traversal_outside#/}" > "$traversal_backup/.paths"; : > "$traversal_backup/.present"
if core_txn_restore "$traversal_root" "$traversal_backup" >/dev/null 2>&1; then no 'rollback accetta percorso con traversal ..'; elif grep -qx sentinel "$traversal_outside/sentinel"; then ok 'rollback rifiuta traversal .. senza cancellare fuori root'; else no 'rollback ha cancellato la sentinella tramite traversal ..'; fi

state_escape_root="$tmp/state-escape-root"; state_outside="$tmp/state-outside"
mkdir -p "$state_escape_root" "$state_outside"; ln -s "$state_outside" "$state_escape_root/var"
if core_state_write "$state_escape_root" example SUCCESS always 1 0 state-escape >/dev/null 2>&1; then no 'state writer accetta var symlinkata'; elif [ -z "$(find "$state_outside" -mindepth 1 -print -quit)" ]; then ok 'state writer rifiuta var symlinkata senza scrivere fuori root'; else no 'state writer ha scritto fuori root tramite var symlinkata'; fi

runner_escape_root="$tmp/runner-escape-root"; runner_outside="$tmp/runner-outside"
mkdir -p "$runner_escape_root" "$runner_outside"; ln -s "$runner_outside" "$runner_escape_root/run"
if CORE_RUN_ROOT="$runner_escape_root" CORE_STATE_ROOT="$runner_escape_root" CORE_PREFIX="$ROOT" bash -c 'source "$0/lib/core/boot-runner.sh"; runner_lock' "$ROOT" >/dev/null 2>&1; then no 'boot runner lock accetta run symlinkato'; elif [ -z "$(find "$runner_outside" -mindepth 1 -print -quit)" ]; then ok 'boot runner lock rifiuta run symlinkato senza scrivere fuori root'; else no 'boot runner lock ha scritto fuori root tramite run symlinkato'; fi

root_link="$tmp/root-link"; root_link_target="$tmp/root-link-target"; mkdir -p "$root_link_target"; ln -s "$root_link_target" "$root_link"
if core_txn_lock "$root_link" >/dev/null 2>&1; then no 'transaction lock accetta root symlinkata'; elif [ -z "$(find "$root_link_target" -mindepth 1 -print -quit)" ]; then ok 'transaction lock rifiuta root symlinkata senza scrivere fuori root'; else no 'transaction lock ha scritto fuori root tramite root symlinkata'; fi

printf '%s\n' "$pass test R4 superati, $fail falliti"
[ "$fail" -eq 0 ]
