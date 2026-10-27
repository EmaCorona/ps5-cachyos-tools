#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/ps5-gamescope-package-test.XXXXXX) || exit 1
trap 'rm -rf -- "$tmp"' EXIT
ok() { printf 'PASS: %s\n' "$1"; }
no() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
root="$tmp/root"
mock="$tmp/pacman"
mkdir -p "$mock"
cat > "$tmp/pacman-build-tools.log" <<'LOG'
[2026-10-27T22:00:00+0100] [ALPM] installed base-devel (1-2)
[2026-10-27T22:00:01+0100] [ALPM] installed fakeroot (1:1.37.2-3)
[2026-10-27T22:00:02+0100] [ALPM] installed pkgconf (2.5.1-1)
[2026-10-27T22:00:03+0100] [ALPM] upgraded unrelated-package (1-2 -> 1-3)
[2026-10-27T22:00:03+0100] [ALPM] removed conflicting-old-package (1-2)
[2026-10-27T22:00:04+0100] [ALPM] installed bad;command (1-1)
LOG
if ( package_test_tmp=$tmp; source "$ROOT/modules/gamescope/files/ps5-gamescope-package"; record_build_dependencies "$package_test_tmp/pacman-build-tools.log"; [ "${build_deps_added[*]}" = 'base-devel fakeroot pkgconf' ] ); then ok 'cleanup pacman registra solo package installati anche dopo transazione parziale'; else no 'parser journal pacman include package estranei'; fi
cat > "$tmp/cleanup-pacman" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  '-Q rolled-back-package') exit 1 ;;
  '-Q base-devel'|'-Q pkgconf') exit 0 ;;
  '-R --noconfirm base-devel pkgconf') printf '%s\n' "$*" > "$MOCK_CLEANUP_LOG" ;;
  *) exit 2 ;;
esac
MOCK
chmod 0755 "$tmp/cleanup-pacman"
if ( package_test_tmp=$tmp; source "$ROOT/modules/gamescope/files/ps5-gamescope-package"; pacman_bin="$package_test_tmp/cleanup-pacman"; build_deps_added=(base-devel rolled-back-package pkgconf); export MOCK_CLEANUP_LOG="$package_test_tmp/cleanup.log"; cleanup_build_dependencies ); then
  [ "$(cat "$tmp/cleanup.log")" = '-R --noconfirm base-devel pkgconf' ] && ok 'cleanup esclude dal remove i package già assenti' || no 'cleanup ha passato package assenti a pacman -R'
else no 'cleanup pacman per pacchetti rimasti installati è fallita'; fi
mkdir -p "$tmp/build-packages"
printf 'main\n' > "$tmp/build-packages/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst"
printf 'debug\n' > "$tmp/build-packages/ps5-cachyos-gamescope-debug-3.17.0-1-x86_64.pkg.tar.zst"
cat > "$tmp/query-package" <<'MOCK'
#!/usr/bin/env bash
case "${!#}" in
  *-debug-*) printf 'ps5-cachyos-gamescope-debug 3.17.0-1\n' ;;
  *) printf 'ps5-cachyos-gamescope 3.17.0-1\n' ;;
esac
MOCK
chmod 0755 "$tmp/query-package"
if ( package_test_tmp=$tmp; source "$ROOT/modules/gamescope/files/ps5-gamescope-package"; tmp="$package_test_tmp/build-packages"; pacman_bin="$package_test_tmp/query-package"; root=/; found=$(find_built_package); [[ "$found" = "$tmp/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst" ]] ); then
  ok 'build seleziona il pacchetto Gamescope e ignora quello debug'
else no 'build ha selezionato un pacchetto non appartenente al modulo'; fi
cat > "$mock/pacman" <<'MOCK'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *' -Q ps5-cachyos-gamescope') printf 'ps5-cachyos-gamescope 3.17.0-1\n' ;;
  *' -Ql ps5-cachyos-gamescope') printf 'ps5-cachyos-gamescope /usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope\n' ;;
  *' -Qp '*) printf 'ps5-cachyos-gamescope 3.17.0-1\n' ;;
  *' -R --noconfirm ps5-cachyos-gamescope') printf '%s\n' "$args" >> "$MOCK_PACMAN_REMOVE_LOG"; : > "$MOCK_PACMAN_STATE"; exit 0 ;;
  *) exit 1 ;;
esac
MOCK
chmod 0755 "$mock/pacman"
mkdir -p "$root/var/lib/ps5-cachyos-tools/gamescope/packages" "$root/usr/lib/ps5-cachyos-tools/gamescope/bin" "$root/usr/lib/ps5-cachyos-tools/gamescope/share/gamescope/scripts" \
  "$root/usr/local/libexec/ps5-cachyos-tools" "$root/usr/local/bin" "$root/usr/bin" \
  "$root/usr/share/ps5-cachyos-tools/gamescope" "$root/usr/share/xdg-desktop-portal" "$root/etc/ps5-cachyos-tools"
PS5_GAMESCOPE_PACKAGE_HELPER="$tmp/helper-not-copied" CORE_REPO="$ROOT" "$ROOT/modules/gamescope/package.sh" "$root" rollback && ok 'rollback post-install è no-op se il modulo non ha ancora avviato il helper pacman' || no 'rollback senza helper ha segnalato un effetto esterno inesistente'
printf '#!/bin/sh\nexit 0\n' > "$root/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope"
chmod 0755 "$root/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope"
for path in gamescope-session gamescope-display-mode video-diag steam-verify-repair drm-setup; do
  case "$path" in gamescope-session) out="$root/usr/local/libexec/ps5-cachyos-tools/$path";; *) out="$root/usr/local/bin/ps5-cachyos-tools-$path";; esac
  printf '#!/bin/sh\nexit 0\n' > "$out"; chmod 0755 "$out"
done
printf '#!/bin/sh\nexit 0\n' > "$root/usr/bin/python3"; chmod 0755 "$root/usr/bin/python3"
printf 'upstream_commit=e6674a98118ca7b098b98a3874b8f195ae1bf750\n' > "$root/usr/share/ps5-cachyos-tools/gamescope/build-info"
printf 'portal\n' > "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf"
printf '# config\n' > "$root/etc/ps5-cachyos-tools/gamescope.conf"
PS5_GAMESCOPE_PACMAN="$mock/pacman" "$ROOT/modules/gamescope/check.sh" "$root" && ok 'check Gamescope accetta pacchetto downstream registrato' || no 'check Gamescope rifiuta pacchetto downstream valido'
cat > "$mock/pacman" <<'MOCK'
#!/usr/bin/env bash
case "$*" in *' -Q ps5-cachyos-gamescope') exit 1;; *) exit 1;; esac
MOCK
chmod 0755 "$mock/pacman"
if PS5_GAMESCOPE_PACMAN="$mock/pacman" "$ROOT/modules/gamescope/check.sh" "$root" >/dev/null 2>&1; then no 'check Gamescope accetta pacchetto non registrato'; else ok 'check Gamescope rifiuta pacchetto non registrato'; fi
cat > "$mock/pacman" <<'MOCK'
#!/usr/bin/env bash
args="$*"
case "$*" in
  *' -Q ps5-cachyos-gamescope') [ -f "$MOCK_PACMAN_STATE" ] && printf 'ps5-cachyos-gamescope 3.17.0-1\n' || exit 1 ;;
  *' -Qp '*) printf 'ps5-cachyos-gamescope 3.17.0-1\n' ;;
  *' -R --noconfirm ps5-cachyos-gamescope') printf '%s\n' "$args" >> "$MOCK_PACMAN_REMOVE_LOG"; rm -f "$MOCK_PACMAN_STATE"; [ "${MOCK_PACMAN_REMOVE_FAIL:-0}" = 0 ] ;;
  *' -U --noconfirm '*) printf '%s\n' "$args" >> "$MOCK_PACMAN_REMOVE_LOG"; touch "$MOCK_PACMAN_STATE" ;;
  *) exit 1 ;;
esac
MOCK
chmod 0755 "$mock/pacman"
printf '#!/usr/bin/env bash\nprintf "0\\n"\n' > "$mock/id"; chmod 0755 "$mock/id"
touch "$tmp/package-installed"
printf 'mock archive\n' > "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst"
printf 'external archive\n' > "$tmp/outside.pkg.tar.zst"
rm -f -- "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst"
ln -s "$tmp/outside.pkg.tar.zst" "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-2-x86_64.pkg.tar.zst"
MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" remove "$root" >/dev/null 2>&1 && no 'rimozione ha accettato archivio symlinkato' || ok 'rimozione ignora gli archivi symlinkati nella cache'
[ -f "$tmp/package-installed" ] && [ ! -e "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] || no 'archivio symlinkato ha modificato lo stato pacman'
rm -f -- "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-2-x86_64.pkg.tar.zst"
printf 'mock archive\n' > "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst"
MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" MOCK_PACMAN_REMOVE_FAIL=1 PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" remove "$root" >/dev/null 2>&1 && no 'rimozione parziale pacman dichiarata riuscita' || ok 'errore pacman lascia un journal per il rollback'
MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" rollback "$root" && \
  [ -f "$tmp/package-installed" ] && [ ! -e "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] && grep -q -- '-U --noconfirm' "$tmp/remove.log" && ok 'rollback pacman reinstalla dal journal nel root offline' || no 'rollback pacman non ha ripristinato il package offline'
printf 'format=1\naction=remove\nprior_version=3.17.0-1\nprior_archive=%s\nbase_gamescope_added=0\n' "$root/var/lib/ps5-cachyos-tools/gamescope/packages/ps5-cachyos-gamescope-3.17.0-1-x86_64.pkg.tar.zst" > "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction"
MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" commit "$root" && \
  [ -f "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] && \
  MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" finalize "$root" && \
  [ ! -e "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] && ok 'journal pacman restaura rollback fino a finalize e si pulisce solo dopo tutti i commit' || no 'commit/finalize ha eliminato il journal prematuramente'
MOCK_PACMAN_STATE="$tmp/package-installed" MOCK_PACMAN_REMOVE_LOG="$tmp/remove.log" PATH="$mock:$PATH" PS5_GAMESCOPE_PACMAN="$mock/pacman" CORE_TARGET_ROOT="$root" "$ROOT/modules/gamescope/files/ps5-gamescope-package" remove "$root" && \
  grep -q -- '--sysroot' "$tmp/remove.log" && grep -q -- '-R --noconfirm ps5-cachyos-gamescope' "$tmp/remove.log" && \
  [ ! -f "$tmp/package-installed" ] && [ ! -e "$root/var/lib/ps5-cachyos-tools/gamescope/package.transaction" ] && ok 'remove limita pacman al pacchetto downstream nel root offline' || no 'remove non ha usato pacman --sysroot'
printf 'PASS: suite Gamescope package completata\n'
