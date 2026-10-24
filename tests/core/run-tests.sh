#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d /tmp/ps5-tools-core.XXXXXX)
export CORE_TEST_MODE=1
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1" >&2; fail=$((fail+1)); }

./bin/ps5-cachyos-tools list >/tmp/ps5-tools-list.out && grep -qx fan /tmp/ps5-tools-list.out && ok 'discovery dinamica del modulo fan' || no 'discovery dinamica del modulo fan'
mkdir -p "$tmp/root/etc"
printf 'ID=linux\nNAME=fixture\n' > "$tmp/root/etc/os-release"
./bin/ps5-cachyos-tools install --root "$tmp/root" --dry-run >/tmp/ps5-tools-dry.out 2>&1 && ! test -e "$tmp/root/usr/lib/ps5-cachyos-tools" && ok 'dry-run non scrive la rootfs' || no 'dry-run ha scritto la rootfs'
./bin/ps5-cachyos-tools install --root "$tmp/root" --module fan >/tmp/ps5-tools-install.out 2>&1 && test -x "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" && test -L "$tmp/root/etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service" && ok 'installazione offline resta nella root target' || no 'installazione offline incompleta'
mkdir -p "$tmp/second/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/second/etc/os-release"
"$tmp/root/usr/local/bin/ps5-cachyos-tools" install --root "$tmp/second" --module fan >/tmp/ps5-tools-installed-cli.out 2>&1 && test -x "$tmp/second/usr/local/bin/ps5-cachyos-tools" && ok 'CLI installata riutilizzabile come sorgente' || no 'CLI installata non riutilizzabile come sorgente'
./bin/ps5-cachyos-tools install --root "$tmp/root" --module fan >/tmp/ps5-tools-reinstall.out 2>&1 && ok 'reinstallazione idempotente con symlink gestiti' || no 'reinstallazione idempotente fallita'
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
mkdir -p "$tmp/root/etc/ps5-cachyos-tools/modules.d"; printf 'ENABLED=false\n' > "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
CORE_BOOT_ID=override-1 CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
grep -q '^status=SKIPPED_DISABLED$' "$tmp/root/var/lib/ps5-cachyos-tools/state/modules/example.state" && ok 'override amministrativo disabilita il modulo senza modificare il manifest' || no 'override amministrativo ignorato'
printf 'UNKNOWN=true\n' > "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
if CORE_CONFIG_ROOT="$tmp/root" CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then no 'override con chiave sconosciuta accettato'; else ok 'override con chiave sconosciuta rifiutato'; fi
rm -f "$tmp/root/etc/ps5-cachyos-tools/modules.d/example.conf"
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
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$service_repo/modules/fixture-service/install.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$service_repo/modules/fixture-service/remove.sh"; chmod 0755 "$service_repo/modules/fixture-service/"*.sh
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
mkdir -p "$tmp/service-root/etc"; printf 'ID=linux\nNAME=fixture\n' > "$tmp/service-root/etc/os-release"
if "$service_repo/bin/ps5-cachyos-tools" install --root "$tmp/service-root" --module fixture-service >/tmp/ps5-tools-service.out 2>&1 && test -f "$tmp/service-root/etc/systemd/system/fixture-service.service" && test ! -e "$tmp/service-root/usr/local/bin/ps5-fan"; then ok 'modulo service generico selettivo senza artefatti fan'; else no 'modulo service generico non isolato'; fi
printf '#!/usr/bin/env bash\nprintf failure > "$1/etc/fixture-remove-failure"\nexit 23\n' > "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"; chmod 0755 "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"
if "$tmp/service-root/usr/local/bin/ps5-cachyos-tools" remove fixture-service --root "$tmp/service-root" >/tmp/ps5-tools-service-remove-fail.out 2>&1 && false || test -f "$tmp/service-root/etc/systemd/system/fixture-service.service"; then ok 'rollback remove conserva il service dopo hook fallito'; else no 'rollback remove non ha conservato il service'; fi
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"; chmod 0755 "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service/remove.sh"
if "$tmp/service-root/usr/local/bin/ps5-cachyos-tools" remove fixture-service --root "$tmp/service-root" >/tmp/ps5-tools-service-remove.out 2>&1 && test ! -e "$tmp/service-root/etc/systemd/system/fixture-service.service" && test ! -e "$tmp/service-root/usr/lib/ps5-cachyos-tools/modules/fixture-service"; then ok 'rimozione generica del service completata'; else no 'rimozione generica del service fallita'; fi
printf '%s\n' "$pass test superati, $fail falliti"; [ "$fail" -eq 0 ]
