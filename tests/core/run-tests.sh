#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d /tmp/ps5-tools-core.XXXXXX)
export CORE_TEST_MODE=1
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1" >&2; fail=$((fail+1)); }
hold_transaction() { local target=$1; mkdir -p "$target/run/ps5-cachyos-tools"; exec 8>"$target/run/ps5-cachyos-tools/transaction.lock"; flock -n 8; sleep 1; }
wait_transaction_lock() { local target=$1 attempt; for attempt in $(seq 1 20); do test -e "$target/run/ps5-cachyos-tools/transaction.lock" && return 0; sleep 0.05; done; return 1; }

./bin/ps5-cachyos-tools list >/tmp/ps5-tools-list.out && grep -qx fan /tmp/ps5-tools-list.out && ok 'discovery dinamica del modulo fan' || no 'discovery dinamica del modulo fan'
source "$ROOT/lib/core/log.sh"; source "$ROOT/lib/core/target.sh"
test "$(core_target_path / /usr/local/bin/ps5-cachyos-tools)" = /usr/local/bin/ps5-cachyos-tools && ok 'target live root=/ valida i percorsi ordinari' || no 'target live root=/ rifiuta un percorso valido'
mkdir -p "$tmp/root/etc"
printf 'ID=linux\nNAME=fixture\n' > "$tmp/root/etc/os-release"
./bin/ps5-cachyos-tools install --root "$tmp/root" --dry-run >/tmp/ps5-tools-dry.out 2>&1 && ! test -e "$tmp/root/usr/lib/ps5-cachyos-tools" && ok 'dry-run non scrive la rootfs' || no 'dry-run ha scritto la rootfs'
./bin/ps5-cachyos-tools install --root "$tmp/root" --module fan >/tmp/ps5-tools-install.out 2>&1 && test -x "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" && test -L "$tmp/root/etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service" && ok 'installazione offline resta nella root target' || no 'installazione offline incompleta'
mkdir -p "$tmp/second/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/second/etc/os-release"
"$tmp/root/usr/local/bin/ps5-cachyos-tools" install --root "$tmp/second" --module fan >/tmp/ps5-tools-installed-cli.out 2>&1 && test -x "$tmp/second/usr/local/bin/ps5-cachyos-tools" && ok 'CLI installata riutilizzabile come sorgente' || no 'CLI installata non riutilizzabile come sorgente'
./bin/ps5-cachyos-tools install --root "$tmp/root" --module fan >/tmp/ps5-tools-reinstall.out 2>&1 && ok 'reinstallazione idempotente con symlink gestiti' || no 'reinstallazione idempotente fallita'
if "$tmp/root/usr/local/bin/ps5-cachyos-tools" install --root "$tmp/root" --module fan >/tmp/ps5-tools-installed-same-root.out 2>&1; then ok 'reinstallazione dalla CLI installata sulla stessa rootfs'; else no 'reinstallazione dalla CLI installata sulla stessa rootfs fallita'; fi
mkdir -p "$tmp/disabled-fan/etc/ps5-cachyos-tools"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/disabled-fan/etc/os-release"; mkdir -p "$tmp/disabled-fan/etc/ps5-cachyos-tools/modules.d"; printf 'ENABLED=false\n' > "$tmp/disabled-fan/etc/ps5-cachyos-tools/modules.d/fan.conf"
if ./bin/ps5-cachyos-tools install --root "$tmp/disabled-fan" --module fan >/tmp/ps5-tools-disabled-fan.out 2>&1 && test ! -e "$tmp/disabled-fan/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service"; then ok 'fan disabilitato non abilita il servizio in installazione'; else no 'fan disabilitato avvia o abilita il servizio'; fi
mkdir -p "$tmp/boot"
./bin/ps5-cachyos-tools install --root "$tmp/root" --boot "$tmp/boot" --module fan --dry-run >/tmp/ps5-tools-boot-separate.out 2>&1 && ok 'rootfs e boot su mount separati' || no 'mount boot separato rifiutato'
mkdir -p "$tmp/bad-modules/bad"
cat > "$tmp/bad-modules/bad/module.conf" <<'EOF'
ID=bad
NAME=Bad
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
OWNED_PATHS=/usr
EOF
if CORE_CONFIG_ROOT="$tmp/root" core_registry_discover "$tmp/bad-modules" >/dev/null 2>&1 && core_registry_validate_owned_paths >/dev/null 2>&1; then no 'OWNED_PATHS pericoloso accettato'; else ok 'OWNED_PATHS pericoloso rifiutato'; fi
sed -i 's#OWNED_PATHS=/usr#OWNED_PATHS=/usr/lib/ps5-cachyos-tools/modules#' "$tmp/bad-modules/bad/module.conf"
if CORE_CONFIG_ROOT="$tmp/root" core_registry_discover "$tmp/bad-modules" >/dev/null 2>&1 && core_registry_validate_owned_paths >/dev/null 2>&1; then no 'OWNED_PATHS framework interno accettato'; else ok 'OWNED_PATHS framework interno rifiutato'; fi
if CORE_TEST_MODE=0 core_target_validate_mount "$tmp/boot" boot >/dev/null 2>&1; then no 'boot non mount accettato fuori test'; else ok 'boot non mount rifiutato fuori test'; fi
test -e /etc/systemd/system/ps5-tools-boot.service && no 'offline ha scritto la unit sull host' || ok 'offline non scrive unit sull host'
ln -s /etc "$tmp/root/etc-link"
if ./bin/ps5-cachyos-tools install --root "$tmp/root/etc-link" --dry-run >/dev/null 2>&1; then no 'target symlink accettato'; else ok 'target symlink non accettato'; fi
mkdir -p "$tmp/nested/etc" "$tmp/nested/usr" "$tmp/outside"; printf 'ID=linux\n' > "$tmp/nested/etc/os-release"; ln -s "$tmp/outside" "$tmp/nested/usr/lib"
if ./bin/ps5-cachyos-tools install --root "$tmp/nested" --dry-run >/dev/null 2>&1; then no 'symlink annidato accettato'; else ok 'symlink annidato rifiutato'; fi
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example"
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf" <<'EOF'
ID=example
NAME="Example"
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
EOF
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/boot.sh" <<'EOF'
#!/usr/bin/env bash
root=$1
printf '%s\n' "$(( $(cat "$root/var/lib/ps5-cachyos-tools/example.count" 2>/dev/null || echo 0) + 1 ))" > "$root/var/lib/ps5-cachyos-tools/example.count"
EOF
chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/boot.sh"
before_reapply=$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count" 2>/dev/null || echo 0)
if "$tmp/root/usr/local/bin/ps5-cachyos-tools" reapply example --root "$tmp/root" >/tmp/ps5-tools-reapply.out 2>&1 && test -f "$tmp/root/var/lib/ps5-cachyos-tools/state/reapply/example.request" && test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count" 2>/dev/null || echo 0)" = "$before_reapply"; then ok 'reapply offline pianifica senza eseguire hook'; else no 'reapply offline ha eseguito hook o non ha pianificato'; fi
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/core" "$tmp/root/var/lib/ps5-cachyos-tools/state/modules"
cp "$ROOT/lib/core/"*.sh "$tmp/root/usr/lib/ps5-cachyos-tools/core/"; cp "$ROOT/lib/core/boot-runner.sh" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner"; chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner"
if CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then ok 'runner esegue task once dopo installazione'; else no 'runner non esegue task once'; fi
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count" 2>/dev/null)" = 1 && ok 'runner scrive lo stato persistente' || no 'runner non scrive il task'
CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count")" = 1 && ok 'runner once salta il secondo boot simulato' || no 'runner once riesegue il secondo boot simulato'
sed -i 's/^ENABLED=true$/ENABLED=false/' "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf"
CORE_BOOT_ID=boot-disabled CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
grep -q '^status=SKIPPED_DISABLED$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/example.state" && grep -q '^completed_at=[1-9]' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/example.state" && ok 'disabilitazione preserva il completamento once' || no 'disabilitazione sovrascrive il completamento once'
sed -i 's/^ENABLED=false$/ENABLED=true/' "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf"
CORE_BOOT_ID=boot-reenabled CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count")" = 1 && ok 'riabilitazione non riesegue once completato' || no 'riabilitazione riesegue once completato'
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-once"
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-once/module.conf" <<'EOF'
ID=dependent-once
NAME=Dependent once
ENABLED=true
TYPE=task
RUN_POLICY=always
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=example
FAILURE_POLICY=continue
EOF
printf '#!/usr/bin/env bash\ntest "$(cat "$1/var/lib/ps5-cachyos-tools/example.count")" = 1 || exit 23\nprintf success > "$1/var/lib/ps5-cachyos-tools/dependent-once.ok"\n' > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-once/boot.sh"; chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-once/boot.sh"
CORE_BOOT_ID=boot-dependent CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1 && test -f "$tmp/root/var/lib/ps5-cachyos-tools/dependent-once.ok" && ok 'dipendenza once completata riconosciuta dopo disable/enable' || no 'dipendenza once completata non riconosciuta'
mkdir -p "$tmp/root/etc/ps5-cachyos-tools/modules.d"; printf 'ENABLED=false\n' > "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
CORE_BOOT_ID=override-1 CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
grep -q '^status=SKIPPED_DISABLED$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/example.state" && ok 'override amministrativo disabilita il modulo senza modificare il manifest' || no 'override amministrativo ignorato'
printf 'UNKNOWN=true\n' > "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
if CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then no 'override con chiave sconosciuta accettato'; else ok 'override con chiave sconosciuta rifiutato'; fi
rm -f "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
printf 'ENABLED=false\n' > "$tmp/root/etc/ps5-cachyos-tools/modules.d/removed-module.conf"
if CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then ok 'override orphan non blocca i moduli presenti'; else no 'override orphan blocca la discovery'; fi
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/modules/always-fixture"
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/always-fixture/module.conf" <<'EOF'
ID=always-fixture
NAME=Always
ENABLED=true
TYPE=task
RUN_POLICY=always
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
EOF
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/always-fixture/boot.sh" <<'EOF'
#!/usr/bin/env bash
root=$1
printf '%s\n' "$(( $(cat "$root/var/lib/ps5-cachyos-tools/always.count" 2>/dev/null || echo 0) + 1 ))" > "$root/var/lib/ps5-cachyos-tools/always.count"
EOF
chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/modules/always-fixture/boot.sh"
CORE_BOOT_ID=always-1 CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
CORE_BOOT_ID=always-1 CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
CORE_BOOT_ID=always-2 CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/always.count")" = 2 && ok 'always esegue una volta per boot' || no 'always eseguito con semantica errata'
cp "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf" "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf.bad"
printf 'UNKNOWN=1\n' >> "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf"
if CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then no 'manifest con chiave sconosciuta accettato'; else ok 'manifest con chiave sconosciuta rifiutato'; fi
mv "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf.bad" "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example/module.conf"
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/modules/disabled" "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent"
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/disabled/module.conf" <<'EOF'
ID=disabled
NAME=Disabled
ENABLED=false
TYPE=task
RUN_POLICY=always
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
EOF
cat > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent/module.conf" <<'EOF'
ID=dependent
NAME=Dependent
ENABLED=true
TYPE=task
RUN_POLICY=always
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=disabled
FAILURE_POLICY=continue
EOF
printf '#!/usr/bin/env bash\nexit 99\n' > "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent/boot.sh"; chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent/boot.sh"
CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
grep -q '^status=BLOCKED_DEPENDENCY$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/dependent.state" && ok 'dipendenza disabilitata blocca il modulo dipendente' || no 'dipendenza disabilitata non blocca il modulo dipendente'
cp -a "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent" "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-critical"
sed -i 's/^ID=dependent$/ID=dependent-critical/; s/^FAILURE_POLICY=continue$/FAILURE_POLICY=critical/' "$tmp/root/usr/lib/ps5-cachyos-tools/modules/dependent-critical/module.conf"
CORE_BOOT_ID=critical-dep CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/tmp/ps5-tools-critical-dep.out 2>&1 && no 'failure policy critical ignorata per dipendenza bloccata' || grep -q '^status=BLOCKED_DEPENDENCY$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/dependent-critical.state" && ok 'failure policy critical interrompe la pipeline su dipendenza bloccata' || no 'failure policy critical non registrata'
fixture_repo="$tmp/fixture-repo"; cp -a "$ROOT/." "$fixture_repo"; mkdir -p "$fixture_repo/modules/failure-fixture"
cat > "$fixture_repo/modules/failure-fixture/module.conf" <<'EOF'
ID=failure-fixture
NAME=Failure fixture
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
OWNED_PATHS=/etc/failure-fixture.marker
EOF
cat > "$fixture_repo/modules/failure-fixture/install.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' changed > "$1/etc/failure-fixture.marker"
exit 23
EOF
chmod 0755 "$fixture_repo/modules/failure-fixture/install.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$fixture_repo/modules/failure-fixture/boot.sh"; chmod 0755 "$fixture_repo/modules/failure-fixture/boot.sh"
mkdir -p "$tmp/fail-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/fail-root/etc/os-release"
if ( source "$ROOT/lib/core/log.sh"; source "$ROOT/lib/core/target.sh"; source "$ROOT/lib/core/registry.sh"; source "$ROOT/lib/core/dependencies.sh"; source "$ROOT/lib/core/service.sh"; source "$ROOT/lib/core/installer.sh"; CORE_INSTALL_MODE=offline core_install "$tmp/fail-root" "$fixture_repo" failure-fixture ) >/dev/null 2>&1; then no 'hook failure accettato'; else [ ! -e "$tmp/fail-root/etc/failure-fixture.marker" ] && [ ! -e "$tmp/fail-root/usr/lib/ps5-cachyos-tools" ] && ok 'rollback transazionale rimuove artefatto hook fallito' || no 'rollback transazionale lascia artefatti hook'; fi
dep_repo="$tmp/dep-repo"; cp -a "$ROOT/." "$dep_repo"; mkdir -p "$dep_repo/modules/dep-a" "$dep_repo/modules/dep-b"
cat > "$dep_repo/modules/dep-a/module.conf" <<'EOF'
ID=dep-a
NAME=Dependency A
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=critical
OWNED_PATHS=/etc/dep-a.marker
EOF
cat > "$dep_repo/modules/dep-b/module.conf" <<'EOF'
ID=dep-b
NAME=Dependency B
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=dep-a
FAILURE_POLICY=critical
OWNED_PATHS=/etc/dep-b.marker
EOF
cat > "$dep_repo/modules/dep-a/install.sh" <<'EOF'
#!/usr/bin/env bash
printf a > "$1/etc/dep-a.marker"
printf '%s\n' "$(( $(cat "$1/var/lib/ps5-cachyos-tools/dep-a.count" 2>/dev/null || echo 0) + 1 ))" > "$1/var/lib/ps5-cachyos-tools/dep-a.count"
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$dep_repo/modules/dep-a/boot.sh"
printf '#!/usr/bin/env bash\ntest -f "$1/etc/dep-a.marker" || exit 23\nprintf b > "$1/etc/dep-b.marker"\n' > "$dep_repo/modules/dep-b/install.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$dep_repo/modules/dep-b/boot.sh"; chmod 0755 "$dep_repo/modules/dep-"*/install.sh "$dep_repo/modules/dep-"*/boot.sh
mkdir -p "$tmp/dep-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/dep-root/etc/os-release"
if "$dep_repo/bin/ps5-cachyos-tools" install --root "$tmp/dep-root" --module dep-b >/tmp/ps5-tools-deps.out 2>&1 && test -f "$tmp/dep-root/etc/dep-a.marker" && test -f "$tmp/dep-root/etc/dep-b.marker" && test "$(cat "$tmp/dep-root/var/lib/ps5-cachyos-tools/dep-a.count")" = 1 && "$dep_repo/bin/ps5-cachyos-tools" install --root "$tmp/dep-root" --module dep-b >/tmp/ps5-tools-deps-reinstall.out 2>&1 && test "$(cat "$tmp/dep-root/var/lib/ps5-cachyos-tools/dep-a.count")" = 1; then ok 'installazione selettiva include e riusa dipendenze valide'; else no 'installazione selettiva salta o reinstalla una dipendenza'; fi
printf '#!/usr/bin/env bash\nprintf corrupted > "$1/etc/dep-a.marker"\n' > "$tmp/dep-root/usr/lib/ps5-cachyos-tools/modules/dep-a/install.sh"; chmod 0755 "$tmp/dep-root/usr/lib/ps5-cachyos-tools/modules/dep-a/install.sh"
if "$dep_repo/bin/ps5-cachyos-tools" install --root "$tmp/dep-root" --module dep-b >/tmp/ps5-tools-deps-repair.out 2>&1 && test "$(cat "$tmp/dep-root/var/lib/ps5-cachyos-tools/dep-a.count")" = 2 && test "$(cat "$tmp/dep-root/etc/dep-a.marker")" = a; then ok 'dipendenza con hook alterato viene riparata'; else no 'dipendenza con hook alterato considerata valida'; fi
service_repo="$tmp/service-repo"; cp -a "$ROOT/." "$service_repo"; mkdir -p "$service_repo/modules/fixture-service"
cat > "$service_repo/modules/fixture-service/module.conf" <<'EOF'
ID=fixture-service
NAME=Fixture service
ENABLED=true
TYPE=service
RUN_POLICY=always
BOOT_PHASE=service
REVISION=1
DEPENDENCIES=
SERVICE_UNIT=fixture-service.service
FAILURE_POLICY=critical
OWNED_PATHS=/etc/systemd/system/fixture-service.service /etc/systemd/system/multi-user.target.wants/fixture-service.service
READINESS_HOOK=readiness.sh
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$service_repo/modules/fixture-service/install.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$service_repo/modules/fixture-service/remove.sh"; printf '#!/usr/bin/env bash\nprintf ready > "${READINESS_MARKER:?}"\n' > "$service_repo/modules/fixture-service/readiness.sh"; chmod 0755 "$service_repo/modules/fixture-service/"*.sh
mkdir -p "$service_repo/usr/lib/ps5-cachyos-tools/systemd"
cat > "$service_repo/usr/lib/ps5-cachyos-tools/systemd/fixture-service.service" <<'EOF'
[Unit]
Description=Fixture service
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$service_repo/modules/disabled-service"
cat > "$service_repo/modules/disabled-service/module.conf" <<'EOF'
ID=disabled-service
NAME=Disabled service
ENABLED=false
TYPE=service
RUN_POLICY=always
BOOT_PHASE=service
REVISION=1
DEPENDENCIES=
SERVICE_UNIT=disabled-service.service
FAILURE_POLICY=continue
OWNED_PATHS=/etc/systemd/system/disabled-service.service /etc/systemd/system/multi-user.target.wants/disabled-service.service
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$service_repo/modules/disabled-service/install.sh"; chmod 0755 "$service_repo/modules/disabled-service/install.sh"
cat > "$service_repo/usr/lib/ps5-cachyos-tools/systemd/disabled-service.service" <<'EOF'
[Unit]
Description=Disabled fixture service
[Service]
Type=oneshot
ExecStart=/bin/true
[Install]
WantedBy=multi-user.target
EOF
mkdir -p "$tmp/service-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/service-root/etc/os-release"
if "$service_repo/bin/ps5-cachyos-tools" install --root "$tmp/service-root" --module fixture-service >/tmp/ps5-tools-service.out 2>&1 && test -f "$tmp/service-root/etc/systemd/system/fixture-service.service" && test ! -e "$tmp/service-root/usr/local/bin/ps5-fan"; then ok 'modulo service generico selettivo senza artefatti fan'; else no 'modulo service generico non isolato'; fi
mkdir -p "$tmp/disabled-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/disabled-root/etc/os-release"
if "$service_repo/bin/ps5-cachyos-tools" install --root "$tmp/disabled-root" --module disabled-service >/tmp/ps5-tools-disabled-service.out 2>&1 && test -f "$tmp/disabled-root/etc/systemd/system/disabled-service.service" && test ! -e "$tmp/disabled-root/etc/systemd/system/multi-user.target.wants/disabled-service.service"; then ok 'ENABLED=false non abilita il service'; else no 'service disabilitato abilitato indesideratamente'; fi
if "$service_repo/bin/ps5-cachyos-tools" reapply fixture-service --root "$tmp/service-root" >/tmp/ps5-tools-service-reapply-offline.out 2>&1; then no 'reapply offline service accettato'; else test ! -e "$tmp/service-root/var/lib/ps5-cachyos-tools/state/reapply/fixture-service.request" && ok 'reapply offline service rifiutato senza richiesta pendente' || no 'reapply offline service ha lasciato una richiesta'; fi
hold_transaction "$tmp/root" & lock_pid=$!; wait_transaction_lock "$tmp/root"
if "$tmp/root/usr/local/bin/ps5-cachyos-tools" reset example --root "$tmp/root" >/tmp/ps5-tools-reset-lock.out 2>&1; then no 'reset ha ignorato il lock transazionale'; else ok 'reset rispetta il lock transazionale'; fi
wait "$lock_pid" || true
hold_transaction "$tmp/root" & lock_pid=$!; wait_transaction_lock "$tmp/root"
if "$tmp/root/usr/local/bin/ps5-cachyos-tools" reapply example --root "$tmp/root" >/tmp/ps5-tools-reapply-lock.out 2>&1; then no 'reapply ha ignorato il lock transazionale'; else ok 'reapply rispetta il lock transazionale'; fi
wait "$lock_pid" || true
hold_transaction "$tmp/disabled-root" & lock_pid=$!; wait_transaction_lock "$tmp/disabled-root"
if "$service_repo/bin/ps5-cachyos-tools" remove disabled-service --root "$tmp/disabled-root" >/tmp/ps5-tools-remove-lock.out 2>&1; then no 'remove ha ignorato il lock transazionale'; else ok 'remove rispetta il lock transazionale'; fi
wait "$lock_pid" || true
mkdir -p "$tmp/root/var/lib/ps5-cachyos-tools/state/reapply"; printf 'id=example\nphase=normal\nrevision=1\nrequested_at=1\n' > "$tmp/root/var/lib/ps5-cachyos-tools/state/reapply/example.request"
request_fail_bin="$tmp/request-fail-bin"; mkdir -p "$request_fail_bin"
cat > "$request_fail_bin/rm" <<'EOF'
#!/usr/bin/env bash
case " $* " in *example.request*) exit 1;; *) exec /usr/bin/rm "$@";; esac
EOF
chmod 0755 "$request_fail_bin/rm"
if PATH="$request_fail_bin:$PATH" CORE_BOOT_ID=request-failure CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/tmp/ps5-tools-request-failure.out 2>&1; then no 'runner ha mascherato il fallimento consumo request'; else test -f "$tmp/root/var/lib/ps5-cachyos-tools/state/reapply/example.request" && grep -q '^status=SUCCESS$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/example.state" && ok 'runner riconcilia il fallimento consumo request' || no 'runner ha perso lo stato della request'; fi
concurrent_repo="$tmp/concurrent-repo"; cp -a "$ROOT/." "$concurrent_repo"; mkdir -p "$concurrent_repo/modules/slow-fixture"
cat > "$concurrent_repo/modules/slow-fixture/module.conf" <<'EOF'
ID=slow-fixture
NAME=Slow fixture
ENABLED=true
TYPE=task
RUN_POLICY=once
BOOT_PHASE=normal
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=critical
OWNED_PATHS=/etc/slow-fixture.marker
EOF
cat > "$concurrent_repo/modules/slow-fixture/install.sh" <<'EOF'
#!/usr/bin/env bash
sleep 1
printf done > "$1/etc/slow-fixture.marker"
EOF
cat > "$concurrent_repo/modules/slow-fixture/boot.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$concurrent_repo/modules/slow-fixture/install.sh" "$concurrent_repo/modules/slow-fixture/boot.sh"
mkdir -p "$tmp/concurrent-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/concurrent-root/etc/os-release"
set +e
"$concurrent_repo/bin/ps5-cachyos-tools" install --root "$tmp/concurrent-root" --module slow-fixture >/tmp/ps5-tools-concurrent-a.out 2>&1 & concurrent_pid=$!
for attempt in $(seq 1 20); do test -e "$tmp/concurrent-root/run/ps5-cachyos-tools/transaction.lock" && break; sleep 0.05; done
"$concurrent_repo/bin/ps5-cachyos-tools" install --root "$tmp/concurrent-root" --module slow-fixture >/tmp/ps5-tools-concurrent-b.out 2>&1; concurrent_second_rc=$?
wait "$concurrent_pid"; concurrent_first_rc=$?
set -e
if test "$concurrent_first_rc" = 0 && test "$concurrent_second_rc" -ne 0 && grep -q 'transazione già attiva' /tmp/ps5-tools-concurrent-b.out; then ok 'lock transazionale serializza installazioni concorrenti'; else no 'installazioni concorrenti non serializzate'; fi
if "$tmp/service-root/usr/local/bin/ps5-cachyos-tools" status --root "$tmp/service-root" | grep -q 'fixture-service: installed=yes enabled=true type=service policy=always'; then ok 'status CLI espone il tipo service'; else no 'status CLI non espone il tipo service'; fi
mockbin="$tmp/mockbin"; mkdir -p "$mockbin"; cat > "$mockbin/systemctl" <<'EOF'
#!/usr/bin/env bash
state=${MOCK_SYSTEMCTL_STATE:?}
case "$1" in
    is-enabled) grep -q '^enabled=1$' "$state";;
    is-active) grep -q '^active=1$' "$state";;
    daemon-reload) [ "${MOCK_SYSTEMCTL_FAIL:-}" != daemon-reload ];;
    enable) sed -i 's/^enabled=.*/enabled=1/' "$state";;
    disable) sed -i 's/^enabled=.*/enabled=0/' "$state";;
    start|restart) sed -i 's/^active=.*/active=1/' "$state";;
    stop) sed -i 's/^active=.*/active=0/' "$state";;
    *) exit 0;;
esac
EOF
chmod 0755 "$mockbin/systemctl"; printf 'enabled=1\nactive=1\n' > "$tmp/mock-systemctl.state"
multi_mock="$tmp/multi-mockbin"; mkdir -p "$multi_mock"
cat > "$multi_mock/systemctl" <<'EOF'
#!/usr/bin/env bash
state=${MOCK_MULTI_STATE:?}; unit=${2-}
case "$1" in
    is-enabled) unit=${3-}; awk -F'|' -v u="$unit" '$1==u && $2==1{found=1} END{exit(found?0:1)}' "$state";;
    is-active) unit=${3-}; awk -F'|' -v u="$unit" '$1==u && $3==1{found=1} END{exit(found?0:1)}' "$state";;
    cat) grep -q "^$unit|" "$state";;
    daemon-reload) exit 0;;
    enable) sed -i "s#^$unit|0|#$unit|1|#" "$state";;
    disable) sed -i "s#^$unit|1|#$unit|0|#" "$state";;
    start) sed -i "s#^$unit|\([01]\)|0|#$unit|\1|1|#" "$state";;
    stop) sed -i "s#^$unit|\([01]\)|1|#$unit|\1|0|#" "$state";;
    *) exit 0;;
esac
EOF
chmod 0755 "$multi_mock/systemctl"
mkdir -p "$service_repo/modules/new-service"
cat > "$service_repo/modules/new-service/module.conf" <<'EOF'
ID=new-service
NAME=New service
ENABLED=true
TYPE=service
RUN_POLICY=always
BOOT_PHASE=service
REVISION=1
DEPENDENCIES=
SERVICE_UNIT=new-service.service
FAILURE_POLICY=continue
OWNED_PATHS=/etc/systemd/system/new-service.service
EOF
printf 'fixture-service.service|1|1|1\ndisabled-service.service|0|0|1\nps5-tools-early.service|0|0|1\nps5-tools-boot.service|0|0|1\n' > "$tmp/mock-multi.state"
multi_backup=$(mktemp -d "$tmp/multi-backup.XXXXXX")
if PATH="$multi_mock:$PATH" MOCK_MULTI_STATE="$tmp/mock-multi.state" CORE_CONFIG_ROOT="$service_repo" bash -c 'source "$1/lib/core/log.sh"; source "$1/lib/core/registry.sh"; source "$1/lib/core/dependencies.sh"; source "$1/lib/core/state.sh"; source "$1/lib/core/service.sh"; core_registry_discover "$2/modules" >/dev/null; core_service_transaction_snapshot / "" "$3"; printf "new-service.service|1|1|1\\n" >> "$4"; sed -i "s#^fixture-service.service|1|1|#fixture-service.service|1|0|#; s#^disabled-service.service|0|0|#disabled-service.service|0|1|#" "$4"; core_service_transaction_restore / "$3"' _ "$ROOT" "$service_repo" "$multi_backup" "$tmp/mock-multi.state" >/tmp/ps5-tools-service-multi.out 2>&1 && grep -q '^fixture-service.service|1|1|' "$tmp/mock-multi.state" && grep -q '^disabled-service.service|0|0|' "$tmp/mock-multi.state" && grep -q '^new-service.service|0|0|' "$tmp/mock-multi.state"; then ok 'snapshot e rollback ripristinano service presenti e nuovi'; else no 'snapshot multi-service incompleto'; fi
if PATH="$mockbin:$PATH" MOCK_SYSTEMCTL_STATE="$tmp/mock-systemctl.state" READINESS_MARKER="$tmp/readiness.marker" CORE_PREFIX="$tmp/service-root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/service-root" CORE_RUN_ROOT="$tmp/service-root" bash -c 'source "$1/lib/core/log.sh"; source "$1/lib/core/registry.sh"; source "$1/lib/core/state.sh"; source "$1/lib/core/service.sh"; CORE_CONFIG_ROOT="$2" core_registry_discover "$2/modules" >/dev/null; core_service_reapply / fixture-service' _ "$ROOT" "$service_repo" >/tmp/ps5-tools-service-reapply.out 2>&1 && grep -q '^status=SUCCESS$' "$tmp/service-root/var/lib/ps5-cachyos-tools/state/modules/fixture-service.state" && test -f "$tmp/readiness.marker"; then ok 'reapply live service usa lifecycle, readiness e stato'; else no 'reapply live service incompleto'; fi
printf 'enabled=1\nactive=1\n' > "$tmp/mock-systemctl.state"
if PATH="$mockbin:$PATH" MOCK_SYSTEMCTL_STATE="$tmp/mock-systemctl.state" CORE_STATE_ROOT="$tmp/service-root" CORE_RUN_ROOT="$tmp/service-root" bash -c 'source "$1/lib/core/log.sh"; source "$1/lib/core/registry.sh"; source "$1/lib/core/state.sh"; source "$1/lib/core/service.sh"; CORE_CONFIG_ROOT="$2" core_registry_discover "$2/modules" >/dev/null; eval "$(declare -f core_state_write | sed "s/core_state_write/core_state_write_real/g")"; core_state_write(){ [ "$3" = SUCCESS ] && return 77; core_state_write_real "$@"; }; core_service_reapply / fixture-service' _ "$ROOT" "$service_repo" >/tmp/ps5-tools-service-reapply-fail.out 2>&1 && false || grep -q '^enabled=1$' "$tmp/mock-systemctl.state" && grep -q '^active=1$' "$tmp/mock-systemctl.state"; then ok 'reapply service ripristina dopo failure commit stato'; else no 'reapply service non ripristina dopo failure commit stato'; fi
printf 'enabled=1\nactive=1\n' > "$tmp/mock-systemctl.state"
if PATH="$mockbin:$PATH" MOCK_SYSTEMCTL_STATE="$tmp/mock-systemctl.state" bash -c 'source "$1/lib/core/log.sh"; source "$1/lib/core/registry.sh"; source "$1/lib/core/state.sh"; source "$1/lib/core/service.sh"; CORE_CONFIG_ROOT="$2" core_registry_discover "$2/modules" >/dev/null; core_service_snapshot_state / fixture-service; MOCK_SYSTEMCTL_FAIL=daemon-reload; export MOCK_SYSTEMCTL_FAIL; core_service_stop / fixture-service || true; unset MOCK_SYSTEMCTL_FAIL; core_service_restore_state / fixture-service' _ "$ROOT" "$service_repo" >/dev/null 2>&1 && grep -q '^enabled=1$' "$tmp/mock-systemctl.state" && grep -q '^active=1$' "$tmp/mock-systemctl.state"; then ok 'rollback service ripristina stop parziale'; else no 'rollback service non ripristina stop parziale'; fi
printf '#!/usr/bin/env bash\nprintf failure > "$1/etc/fixture-remove-failure"\nexit 23\n' > "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"; chmod 0755 "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"
if "$tmp/service-root/usr/local/bin/ps5-cachyos-tools" remove fixture-service --root "$tmp/service-root" >/tmp/ps5-tools-service-remove-fail.out 2>&1 && false || test -f "$tmp/service-root/etc/systemd/system/fixture-service.service"; then ok 'rollback remove conserva il service dopo hook fallito'; else no 'rollback remove non ha conservato il service'; fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"; chmod 0755 "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"
if "$tmp/service-root/usr/local/bin/ps5-cachyos-tools" remove fixture-service --root "$tmp/service-root" >/tmp/ps5-tools-service-remove.out 2>&1 && test ! -e "$tmp/service-root/etc/systemd/system/fixture-service.service" && test ! -e "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service"; then ok 'rimozione generica del service completata'; else no 'rimozione generica del service fallita'; fi
mkdir -p "$tmp/invalid-phase/task"; cat > "$tmp/invalid-phase/task/module.conf" <<'EOF'
ID=task
NAME=Invalid phase
ENABLED=true
TYPE=task
RUN_POLICY=always
BOOT_PHASE=service
REVISION=1
DEPENDENCIES=
FAILURE_POLICY=continue
EOF
if core_registry_discover "$tmp/invalid-phase" >/dev/null 2>&1; then no 'manifest task/service accettato'; else ok 'manifest task/service rifiutato'; fi
mkdir -p "$tmp/unsafe-link/etc/systemd/system/multi-user.target.wants" "$tmp/unsafe-link/outside"; printf sentinel > "$tmp/unsafe-link/outside/file"; ln -s "$tmp/unsafe-link/outside/file" "$tmp/unsafe-link/etc/systemd/system/multi-user.target.wants/evil.service"
if core_target_validate_final "$tmp/unsafe-link" /etc/systemd/system/multi-user.target.wants/evil.service "$tmp/unsafe-link/etc/systemd/system/multi-user.target.wants/evil.service" >/dev/null 2>&1; then no 'symlink finale esterno accettato'; else grep -q '^sentinel$' "$tmp/unsafe-link/outside/file" && ok 'symlink finale esterno rifiutato senza seguire il target' || no 'sentinella symlink modificata'; fi
if PS5_TOOLS_ALLOW_LIVE=0 core_target_validate_live >/dev/null 2>&1; then no 'live host non PS5 accettato'; else ok 'live host non PS5 rifiutato'; fi
if CORE_TEST_MODE=0 core_target_validate_offline "$tmp/root" >/dev/null 2>&1; then no 'rootfs offline non montata accettata'; else ok 'rootfs offline non montata rifiutata'; fi
recovery_prefix="$tmp/recovery-prefix"; mkdir -p "$recovery_prefix/core" "$recovery_prefix/modules"; cp "$ROOT/lib/core/"*.sh "$recovery_prefix/core/"; cp "$ROOT/lib/core/boot-runner.sh" "$recovery_prefix/boot-runner"; cp -a "$tmp/root/usr/lib/ps5-cachyos-tools/modules/example" "$recovery_prefix/modules/example"
mkdir -p "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/reapply" "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules"; printf 'id=example\nphase=normal\nrevision=1\nrequested_at=42\n' > "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/reapply/example.request"; printf 'id=example\nrevision=1\ncompleted_at=10\ncompleted_revision=1\nreapply_applied_id=42\nstatus=APPLIED\n' > "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules/example.state"; chmod 600 "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules/example.state"; if CORE_TEST_MODE=1 CORE_PREFIX="$recovery_prefix" CORE_STATE_ROOT="$tmp/request-recovery" CORE_RUN_ROOT="$tmp/request-recovery" CORE_BOOT_ID=recovery-test "$recovery_prefix/boot-runner" normal >/dev/null 2>&1 && [ ! -e "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/reapply/example.request" ]; then ok 'reapply APPLIED viene riconciliato senza riesecuzione'; else no 'reapply APPLIED non riconciliato'; fi
printf 'id=example\nphase=normal\nrevision=1\nrequested_at=43\n' > "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/reapply/example.request"; printf 'id=example\nrevision=1\ncompleted_at=10\ncompleted_revision=1\nreapply_applied_id=42\nstatus=APPLIED\n' > "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules/example.state"; chmod 600 "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules/example.state"; rm -f "$tmp/request-recovery/var/lib/ps5-cachyos-tools/example.count"; if CORE_TEST_MODE=1 CORE_PREFIX="$recovery_prefix" CORE_STATE_ROOT="$tmp/request-recovery" CORE_RUN_ROOT="$tmp/request-recovery" CORE_BOOT_ID=recovery-new-request "$recovery_prefix/boot-runner" normal >/dev/null 2>&1 && test "$(cat "$tmp/request-recovery/var/lib/ps5-cachyos-tools/example.count")" = 1 && grep -q '^reapply_applied_id=43$' "$tmp/request-recovery/var/lib/ps5-cachyos-tools/state/modules/example.state"; then ok 'nuova richiesta B non viene consumata come APPLIED(A)'; else no 'recovery ha consumato una richiesta con ID diverso'; fi
printf '%s\n' "$pass test superati, $fail falliti"; [ "$fail" -eq 0 ]
