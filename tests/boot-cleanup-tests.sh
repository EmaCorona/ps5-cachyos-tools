#!/usr/bin/env bash
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/ps5-boot-cleanup-test.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
pass=0; fail=0
ok() { echo "PASS: $1"; pass=$((pass + 1)); }
no() { echo "FAIL: $1" >&2; fail=$((fail + 1)); }

for hook in "$ROOT"/modules/boot-cleanup/*.sh; do
    bash -n "$hook" && ok "bash -n $(basename "$hook")" || no "bash -n $hook"
done

root="$tmp/root"; mkdir -p "$root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$root/etc/os-release"
fixture_uid=$(id -u); fixture_gid=$(id -g)
mkdir -p "$root/home/alice/.steam"
printf 'alice:x:%s:%s:Alice:/home/alice:/bin/bash\n' "$fixture_uid" "$fixture_gid" > "$root/etc/passwd"

if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$root" --module boot-cleanup >/dev/null 2>&1; then
    ok 'installazione iniziale boot-cleanup asserita'
else
    no 'installazione iniziale boot-cleanup fallita'
fi

mkdir -p "$root/proc/1234" "$root/run/ps5-cachyos-tools/boot-cleanup" "$root/run/user/$fixture_uid"
ln -s /bin/steam "$root/proc/1234/exe"
mkfifo "$root/home/alice/.steam/steam.pipe"
stat_line='1234 (fixture) S'; for field in $(seq 1 18); do stat_line="$stat_line 0"; done; stat_line="$stat_line 42"; printf '%s\n' "$stat_line" > "$root/proc/1234/stat"
printf stale > "$root/run/user/$fixture_uid/steam-runtime-9999"
printf '1234 42 %s /run/user/%s/steam-runtime-1234 steam\n9999 41 %s /run/user/%s/steam-runtime-9999 steam\n' "$fixture_uid" "$fixture_uid" "$fixture_uid" "$fixture_uid" > "$root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list"
if "$ROOT/modules/boot-cleanup/boot.sh" "$root" early &&
   grep -q '^checked=2$' "$root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" &&
   grep -q '^removed=1$' "$root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" &&
   grep -q '^active=1$' "$root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" &&
   [ ! -e "$root/run/user/$fixture_uid/steam-runtime-9999" ] &&
   [ ! -e "$root/run/user/$fixture_uid/steam-runtime-1234" ] &&
   [ -p "$root/home/alice/.steam/steam.pipe" ] &&
   "$ROOT/modules/boot-cleanup/check.sh" "$root"; then
    ok 'boot-cleanup Steam allowlist, PID starttime e ownership verificati'
else
    no 'boot-cleanup Steam bounded fallito'
fi

printf 'stale\n' > "$root/run/user/$fixture_uid/steam-runtime-9999"
if PS5_CLEANUP_DRY_RUN=1 "$ROOT/modules/boot-cleanup/boot.sh" "$root" early &&
   grep -q '^action=DRY_RUN$' "$root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" &&
   [ -e "$root/run/user/$fixture_uid/steam-runtime-9999" ]; then
    ok 'boot-cleanup dry-run preserva gli artefatti'
else
    no 'boot-cleanup dry-run modifica gli artefatti'
fi

dry_root="$tmp/dry-root"; mkdir -p "$dry_root/etc/ps5-cachyos-tools" "$dry_root/home/alice/.steam" "$dry_root/run"
cp -p "$root/etc/ps5-cachyos-tools/boot-cleanup.conf" "$dry_root/etc/ps5-cachyos-tools/boot-cleanup.conf"
printf '9999\n' > "$dry_root/home/alice/.steam/steam.pid"
if PS5_CLEANUP_DRY_RUN=1 "$ROOT/modules/boot-cleanup/boot.sh" "$dry_root" early &&
   [ ! -e "$dry_root/var/lib/ps5-cachyos-tools/boot-cleanup/migration.state" ] &&
   [ ! -e "$dry_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list" ]; then
    ok 'boot-cleanup dry-run migrazione non mutativa'
else
    no 'boot-cleanup dry-run migrazione muta lo stato'
fi

rescan_root="$tmp/rescan-root"; mkdir -p "$rescan_root/etc/ps5-cachyos-tools" "$rescan_root/home/alice/.steam" "$rescan_root/run" "$rescan_root/proc/7777"
cp -p "$root/etc/ps5-cachyos-tools/boot-cleanup.conf" "$rescan_root/etc/ps5-cachyos-tools/boot-cleanup.conf"
printf '7777\n' > "$rescan_root/home/alice/.steam/steam.pid"; ln -s /bin/steam "$rescan_root/proc/7777/exe"
printf '7777 (fixture) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 42\n' > "$rescan_root/proc/7777/stat"
if "$ROOT/modules/boot-cleanup/boot.sh" "$rescan_root" early && sleep 1 &&
   printf '8888\n' > "$rescan_root/home/alice/.steam/steam.pid" &&
   "$ROOT/modules/boot-cleanup/boot.sh" "$rescan_root" early &&
   grep -q '^8888 0 ' "$rescan_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list" &&
   ! grep -q '^7777 ' "$rescan_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list"; then
    ok 'boot-cleanup ri-analizza artifact legacy modificati'
else
    no 'boot-cleanup non ri-analizza artifact legacy modificati'
fi

bad_root="$tmp/bad-proc-root"; mkdir -p "$bad_root/etc/ps5-cachyos-tools" "$bad_root/home/alice/.steam" "$bad_root/run" "$bad_root/proc/4321"
cp -p "$root/etc/ps5-cachyos-tools/boot-cleanup.conf" "$bad_root/etc/ps5-cachyos-tools/boot-cleanup.conf"
printf '4321\n' > "$bad_root/home/alice/.steam/steam.pid"; : > "$bad_root/proc/4321/stat"
if "$ROOT/modules/boot-cleanup/boot.sh" "$bad_root" early &&
   { [ ! -e "$bad_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list" ] || ! grep -q '^4321 0 ' "$bad_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list"; }; then
    ok 'boot-cleanup non registra processo legacy non verificabile'
else
    no 'boot-cleanup registra starttime=0 per processo presente'
fi

proc_link_root="$tmp/proc-link-root"; mkdir -p "$proc_link_root/etc/ps5-cachyos-tools" "$proc_link_root/run/user/1000" "$proc_link_root/run" "$proc_link_root/proc"
cp -p "$root/etc/ps5-cachyos-tools/boot-cleanup.conf" "$proc_link_root/etc/ps5-cachyos-tools/boot-cleanup.conf"
printf stale > "$proc_link_root/run/user/1000/steam-runtime-4321"; ln -s /run/user/1000 "$proc_link_root/proc/4321"
mkdir -p "$proc_link_root/run/ps5-cachyos-tools/boot-cleanup"
printf '4321 0 1000 /run/user/1000/steam-runtime-4321 steam\n' > "$proc_link_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list"
if "$ROOT/modules/boot-cleanup/boot.sh" "$proc_link_root" early &&
   [ -e "$proc_link_root/run/user/1000/steam-runtime-4321" ] &&
   grep -q '^rejected=1$' "$proc_link_root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state"; then
    ok 'boot-cleanup non tratta un proc symlinkato come PID assente'
else
    no 'boot-cleanup rimuove un artefatto con proc symlinkato'
fi

reuse_root="$tmp/reuse-root"; mkdir -p "$reuse_root/etc/ps5-cachyos-tools" "$reuse_root/run/user/1000" "$reuse_root/proc/4321"
cp -p "$root/etc/ps5-cachyos-tools/boot-cleanup.conf" "$reuse_root/etc/ps5-cachyos-tools/boot-cleanup.conf"
printf stale > "$reuse_root/run/user/1000/steam-runtime-4321"; ln -s /bin/steam "$reuse_root/proc/4321/exe"
printf '4321 (fixture) S 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 42\n' > "$reuse_root/proc/4321/stat"
mkdir -p "$reuse_root/run/ps5-cachyos-tools/boot-cleanup"
printf '4321 41 1000 /run/user/1000/steam-runtime-4321 steam\n' > "$reuse_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list"
if "$ROOT/modules/boot-cleanup/boot.sh" "$reuse_root" early &&
   [ -e "$reuse_root/run/user/1000/steam-runtime-4321" ] &&
   grep -q '^rejected=1$' "$reuse_root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state"; then
    ok 'boot-cleanup rifiuta PID riusato con starttime diverso'
else
    no 'boot-cleanup accetta PID riusato con starttime diverso'
fi

if "$ROOT/bin/ps5-cachyos-tools" list 2>/dev/null | grep -q '^boot-cleanup'; then
    ok 'list include boot-cleanup senza dipendenze irrisolte'
else
    no 'list non include boot-cleanup'
fi

selective="$tmp/selective"; mkdir -p "$selective/etc"; printf 'ID=linux\nNAME=fixture\n' > "$selective/etc/os-release"
if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$selective" --module boot-cleanup >/dev/null 2>&1 &&
   [ -x "$selective/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/boot.sh" ] &&
   [ -x "$selective/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/recover.sh" ] &&
   cmp -s "$ROOT/modules/boot-cleanup/recover.sh" "$selective/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/recover.sh"; then
    ok 'installazione selettiva include recovery helper e solo boot-cleanup'
else
    no 'installazione selettiva di boot-cleanup ha installato moduli extra o fallito'
fi

# The on-demand recovery helper must be deterministic and preserve dump data.
recover_root="$tmp/recover-root"; recover_uid=$(id -u); recover_gid=$(id -g)
mkdir -p "$recover_root/etc" "$recover_root/tmp/dumps" "$tmp/mock-bin"
printf 'steam:x:%s:%s:Steam:/home/steam:/bin/bash\n' "$recover_uid" "$recover_gid" > "$recover_root/etc/passwd"
chmod 0755 "$recover_root/tmp/dumps"; printf 'keep this dump\n' > "$recover_root/tmp/dumps/diagnostic.dmp"
cat > "$tmp/mock-bin/pgrep" <<'EOF'
#!/usr/bin/env bash
exit "${MOCK_PGREP_STATUS:-1}"
EOF
chmod 0755 "$tmp/mock-bin/pgrep"
recovery="$selective/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/recover.sh"
if PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=1 "$recovery" "$recover_root" >/dev/null 2>&1 &&
   [ "$(stat -c '%a' "$recover_root/tmp/dumps")" = 700 ] &&
   [ "$(cat "$recover_root/tmp/dumps/diagnostic.dmp")" = 'keep this dump' ]; then
    ok 'recovery corregge solo i permessi non privati e conserva i dump'
else
    no 'recovery non corregge in modo circoscritto la directory dump'
fi
if PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=1 "$recovery" "$recover_root" 2>&1 | grep -q '^action=NO_ACTION$'; then
    ok 'recovery ripetuta non modifica permessi già sicuri'
else
    no 'recovery ripetuta non è idempotente'
fi
chmod 0755 "$recover_root/tmp/dumps"
if PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=0 "$recovery" "$recover_root" 2>&1 | grep -q '^action=NO_ACTION$' &&
   [ "$(stat -c '%a' "$recover_root/tmp/dumps")" = 755 ]; then
    ok 'recovery non modifica i dump se Steam è attivo'
else
    no 'recovery ha modificato i dump mentre Steam risulta attivo'
fi
if ! PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=2 "$recovery" "$recover_root" >/dev/null 2>&1 &&
   [ "$(stat -c '%a' "$recover_root/tmp/dumps")" = 755 ]; then
    ok 'errore di rilevamento processi interrompe recovery senza modifiche'
else
    no 'recovery ha modificato i dump dopo errore di pgrep'
fi
mkdir -p "$tmp/no-pgrep-bin"
ln -s "$(command -v bash)" "$tmp/no-pgrep-bin/bash"
ln -s "$(command -v awk)" "$tmp/no-pgrep-bin/awk"
if ! PATH="$tmp/no-pgrep-bin" "$recovery" "$recover_root" >/dev/null 2>&1 &&
   [ "$(stat -c '%a' "$recover_root/tmp/dumps")" = 755 ]; then
    ok 'pgrep assente interrompe recovery senza modifiche'
else
    no 'recovery procede se pgrep non è disponibile'
fi
mismatch_root="$tmp/mismatch-root"; mismatch_uid=$((recover_uid + 1))
mkdir -p "$mismatch_root/etc" "$mismatch_root/tmp/dumps"
printf 'steam:x:%s:%s:Steam:/home/steam:/bin/bash\n' "$mismatch_uid" "$recover_gid" > "$mismatch_root/etc/passwd"
chmod 0755 "$mismatch_root/tmp/dumps"
if ! PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=1 "$recovery" "$mismatch_root" >/dev/null 2>&1 &&
   [ "$(stat -c '%a' "$mismatch_root/tmp/dumps")" = 755 ]; then
    ok 'UID diverso da steam rifiutato senza modifiche'
else
    no 'recovery modifica la directory con UID diverso da steam'
fi
symlink_root="$tmp/symlink-passwd-root"; mkdir -p "$symlink_root/etc" "$symlink_root/tmp/dumps"
ln -s "$recover_root/etc/passwd" "$symlink_root/etc/passwd"; chmod 0755 "$symlink_root/tmp/dumps"
if ! PATH="$tmp/mock-bin:$PATH" MOCK_PGREP_STATUS=1 "$recovery" "$symlink_root" >/dev/null 2>&1 &&
   [ "$(stat -c '%a' "$symlink_root/tmp/dumps")" = 755 ]; then
    ok 'passwd symlinkato rifiutato senza modifiche'
else
    no 'recovery usa un passwd symlinkato'
fi

printf 'DRY_RUN=1\nSTEAM_STALE_FILE=/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list\n' > "$selective/etc/ps5-cachyos-tools/boot-cleanup.conf"
if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$selective" --module boot-cleanup >/dev/null 2>&1 &&
   grep -q '^DRY_RUN=1$' "$selective/etc/ps5-cachyos-tools/boot-cleanup.conf"; then
    ok 'reinstallazione preserva boot-cleanup.conf modificato'
else
    no 'reinstallazione sovrascrive boot-cleanup.conf modificato'
fi

remove_root="$tmp/remove-root"; mkdir -p "$remove_root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$remove_root/etc/os-release"
if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$remove_root" --module boot-cleanup >/dev/null 2>&1 &&
   mkdir -p "$remove_root/run/ps5-cachyos-tools/boot-cleanup" "$remove_root/var/lib/ps5-cachyos-tools/boot-cleanup" &&
   printf state > "$remove_root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" &&
   printf stale > "$remove_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list" &&
   printf migration > "$remove_root/var/lib/ps5-cachyos-tools/boot-cleanup/migration.state" &&
   CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" remove --module boot-cleanup --root "$remove_root" --keep-config >/dev/null 2>&1 &&
   [ -f "$remove_root/etc/ps5-cachyos-tools/boot-cleanup.conf" ] &&
   [ ! -e "$remove_root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" ] &&
   [ ! -e "$remove_root/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list" ] &&
   [ ! -e "$remove_root/var/lib/ps5-cachyos-tools/boot-cleanup/migration.state" ]; then
    ok 'rimozione keep-config elimina gli artefatti interni e conserva la configurazione'
else
    no 'rimozione keep-config non rispetta ownership/configurazione'
fi

purge_root="$tmp/purge-root"; mkdir -p "$purge_root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$purge_root/etc/os-release"
if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$purge_root" --module boot-cleanup >/dev/null 2>&1 &&
   CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" remove --module boot-cleanup --root "$purge_root" --purge-config >/dev/null 2>&1 &&
   [ ! -e "$purge_root/etc/ps5-cachyos-tools/boot-cleanup.conf" ]; then
    ok 'rimozione purge-config elimina la configurazione del modulo'
else
    no 'rimozione purge-config conserva la configurazione del modulo'
fi

runner_root=$(mktemp -d /tmp/ps5-tools-core.XXXXXX); mkdir -p "$runner_root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$runner_root/etc/os-release"
if CORE_TEST_MODE=1 "$ROOT/bin/ps5-cachyos-tools" install --root "$runner_root" --module boot-cleanup >/dev/null 2>&1 &&
   CORE_TEST_MODE=1 CORE_BOOT_ID=boot-cleanup-a CORE_PREFIX="$runner_root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$runner_root" CORE_RUN_ROOT="$runner_root" "$runner_root/usr/lib/ps5-cachyos-tools/boot-runner" early >/dev/null 2>&1 &&
   grep -q '^status=SUCCESS$' "$runner_root/var/lib/ps5-cachyos-tools/state/modules/boot-cleanup.state" &&
   CORE_TEST_MODE=1 CORE_BOOT_ID=boot-cleanup-b CORE_PREFIX="$runner_root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$runner_root" CORE_RUN_ROOT="$runner_root" "$runner_root/usr/lib/ps5-cachyos-tools/boot-runner" early >/dev/null 2>&1 &&
   grep -q '^status=SUCCESS$' "$runner_root/var/lib/ps5-cachyos-tools/state/modules/boot-cleanup.state" &&
   [ -f "$runner_root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state" ]; then
    ok 'runner early esegue boot-cleanup con RUN_POLICY=always su due boot'
else
    no 'runner early non completa boot-cleanup su due boot'
fi

printf '%s test superati, %s falliti\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
