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
    mkdir -p "$root/var/lib/ps5-cachyos-tools/state/reapply"
    printf 'id=fan\nphase=normal\nrevision=1\nrequested_at=99\n' > "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request"
    if "$root/usr/local/bin/ps5-cachyos-tools" remove fan --root "$root" --keep-config && [ ! -e "$root/var/lib/ps5-cachyos-tools/state/reapply/fan.request" ]; then
        ok 'remove annulla la richiesta reapply pendente'
    else
        no 'remove lascia una richiesta reapply pendente'
    fi
else
    no 'fixture fan R4 non installabile'
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

printf '%s\n' "$pass test R4 superati, $fail falliti"
[ "$fail" -eq 0 ]
