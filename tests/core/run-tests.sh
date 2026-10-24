#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d /tmp/ps5-tools-core.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1" >&2; fail=$((fail+1)); }

./bin/ps5-cachyos-tools list >/tmp/ps5-tools-list.out && grep -qx fan /tmp/ps5-tools-list.out && ok 'discovery dinamica del modulo fan' || no 'discovery dinamica del modulo fan'
mkdir -p "$tmp/root/etc"
printf 'ID=linux\nNAME=fixture\n' > "$tmp/root/etc/os-release"
./bin/ps5-cachyos-tools install --root "$tmp/root" --dry-run >/tmp/ps5-tools-dry.out 2>&1 && ! test -e "$tmp/root/usr/lib/ps5-cachyos-tools" && ok 'dry-run non scrive la rootfs' || no 'dry-run ha scritto la rootfs'
./bin/ps5-cachyos-tools install --root "$tmp/root" --module fan >/tmp/ps5-tools-install.out 2>&1 && test -x "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" && test -L "$tmp/root/etc/systemd/system/multi-user.target.wants/ps5-tools-boot.service" && ok 'installazione offline resta nella root target' || no 'installazione offline incompleta'
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
mkdir -p "$tmp/root/usr/lib/ps5-cachyos-tools/core" "$tmp/root/var/lib/ps5-cachyos-tools/state/modules"
cp "$ROOT/lib/core/"*.sh "$tmp/root/usr/lib/ps5-cachyos-tools/core/"; cp "$ROOT/lib/core/boot-runner.sh" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner"; chmod 0755 "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner"
if CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1; then ok 'runner esegue task once dopo installazione'; else no 'runner non esegue task once'; fi
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count" 2>/dev/null)" = 1 && ok 'runner scrive lo stato persistente' || no 'runner non scrive il task'
CORE_PREFIX="$tmp/root/usr/lib/ps5-cachyos-tools" CORE_STATE_ROOT="$tmp/root" CORE_RUN_ROOT="$tmp/root" "$tmp/root/usr/lib/ps5-cachyos-tools/boot-runner" normal >/dev/null 2>&1
test "$(cat "$tmp/root/var/lib/ps5-cachyos-tools/example.count")" = 1 && ok 'runner once salta il secondo boot simulato' || no 'runner once riesegue il secondo boot simulato'
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
printf '%s\n' "$pass test superati, $fail falliti"; [ "$fail" -eq 0 ]
