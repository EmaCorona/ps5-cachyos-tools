#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/ps5-graphics-modules.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/fake-gamescope-scripts"
export PS5_GAMESCOPE_SCRIPT_PATH="$tmp/fake-gamescope-scripts"
pass=0 fail=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }
assert() { if "$@"; then return 0; else return 1; fi; }
CLI="$ROOT/bin/ps5-cachyos-tools"
COMMON="$ROOT/modules/session/files/session-common.sh"
SELECT="$ROOT/modules/session/files/steamos-session-select"
SUPERVISOR="$ROOT/modules/session/files/session-supervisor"
export CORE_TEST_MODE=1
mock_package="$tmp/mock-gamescope-package"
mock_pacman="$tmp/mock-pacman"
cat > "$mock_package" <<'EOF'
#!/usr/bin/env bash
set -eu
root=$2
printf '%s\n' "$1" >> "${MOCK_PACKAGE_LOG:-/dev/null}"
case "$1" in
  preflight) exit "${MOCK_FAIL_PREFLIGHT:-0}" ;;
  install)
    mkdir -p "$root/usr/lib/ps5-cachyos-tools/gamescope/bin" "$root/usr/lib/ps5-cachyos-tools/gamescope/share/gamescope/scripts" "$root/usr/share/ps5-cachyos-tools/gamescope" "$root/var/lib/ps5-cachyos-tools/gamescope/packages"
    printf '#!/bin/sh\nexit 0\n' > "$root/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope"
    chmod 0755 "$root/usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope"
    printf 'upstream_commit=e6674a98118ca7b098b98a3874b8f195ae1bf750\n' > "$root/usr/share/ps5-cachyos-tools/gamescope/build-info"
    ;;
  rollback) rm -rf "$root/usr/lib/ps5-cachyos-tools/gamescope" "$root/usr/share/ps5-cachyos-tools/gamescope" ;;
  commit|finalize) : ;;
  remove) rm -rf "$root/usr/lib/ps5-cachyos-tools/gamescope" "$root/usr/share/ps5-cachyos-tools/gamescope" ;;
  *) exit 2 ;;
esac
EOF
cat > "$mock_pacman" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *' -Q ps5-cachyos-gamescope') exit 0 ;;
  *' -Ql ps5-cachyos-gamescope') printf 'ps5-cachyos-gamescope /usr/lib/ps5-cachyos-tools/gamescope/bin/gamescope\n' ;;
  *) exit 1 ;;
esac
EOF
chmod 0755 "$mock_package" "$mock_pacman"
export PS5_GAMESCOPE_PACKAGE_HELPER="$mock_package" PS5_GAMESCOPE_PACMAN="$mock_pacman" MOCK_PACKAGE_LOG="$tmp/package-operations.log"
export XDG_SESSION_ID=1

fixture() {
    local root=$1 python3
    mkdir -p "$root/etc/profile.d" "$root/usr/bin" "$root/home/steam/.config" "$root/usr/share/xdg-desktop-portal"
    python3=$(command -v python3) || return 1
    ln -s "$python3" "$root/usr/bin/python3"
    printf 'ID=linux\nNAME=PS5 fixture\n' > "$root/etc/os-release"
    printf 'root:x:0:0:root:/root:/bin/bash\nsteam:x:1000:1000:Steam User:/home/steam:/bin/bash\n' > "$root/etc/passwd"
    printf 'root:x:0:\nsteam:x:1000:\nrender:x:995:\nvideo:x:27:steam\nseat:x:996:\ninput:x:97:\n' > "$root/etc/group"
}

root="$tmp/root"
fixture "$root"
if "$CLI" install --root "$root" --module kde --module gamescope --dry-run > "$tmp/duplicate-module.log" 2>&1; then
    no 'CLI rifiuta selezioni --module multiple anziché installare solo l’ultima'
elif grep -Fq -- '--module può essere specificato una sola volta' "$tmp/duplicate-module.log" && \
     [ ! -e "$root/usr/lib/ps5-cachyos-tools" ]; then
    ok 'CLI rifiuta selezioni --module multiple senza modificare il target'
else
    no 'CLI rifiuta selezioni --module multiple con errore esplicito'
fi
printf 'old profile\n' > "$root/etc/profile.d/ps5-tty-session.sh"
printf 'old selector\n' > "$root/usr/bin/steamos-session-select"
printf '[preferred]\ndefault=kde\n' > "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf"
if "$CLI" install --root "$root" --module session > "$tmp/install.log" 2>&1; then ok 'installazione Session seleziona KDE e Gamescope come dipendenze'; else cat "$tmp/install.log" >&2; no 'installazione grafica selettiva'; fi
if grep -qx install "$MOCK_PACKAGE_LOG"; then ok 'prima installazione esegue il post-hook Gamescope'; else no 'prima installazione non esegue il post-hook Gamescope'; fi
: > "$MOCK_PACKAGE_LOG"
if "$CLI" install --root "$root" --module session > "$tmp/reinstall-session.log" 2>&1 && \
   ! grep -Eq '^(install|commit|finalize|rollback)$' "$MOCK_PACKAGE_LOG"; then
    ok 'reinstallazione Session riusa Gamescope valido senza ricostruirne il pacchetto'
else
    cat "$tmp/reinstall-session.log" >&2
    no 'reinstallazione Session ha rieseguito il post-hook Gamescope'
fi
: > "$MOCK_PACKAGE_LOG"
if MOCK_FAIL_PREFLIGHT=71 "$CLI" install --root "$root" --module session > "$tmp/reinstall-no-build-tools.log" 2>&1 && \
   [ ! -s "$MOCK_PACKAGE_LOG" ]; then
    ok 'dipendenza Gamescope valida non richiede preflight del pacchetto'
else
    cat "$tmp/reinstall-no-build-tools.log" >&2
    no 'preflight della dipendenza Gamescope valida ha bloccato Session'
fi
if grep -qx 'desktop' <(sed -n 's/^DEFAULT_SESSION=//p' "$root/home/steam/.config/ps5-cachyos-tools/session.conf") && \
   [ ! -e "$root/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/module.conf" ]; then
    ok 'prima installazione imposta KDE e resta selettiva'
else no 'default KDE o isolamento moduli errato'; fi
if "$CLI" check --root "$root" > "$tmp/check.log" 2>&1; then ok 'check di KDE, Gamescope e Session'; else cat "$tmp/check.log" >&2; no 'check moduli grafici'; fi
if grep -q 'steam' "$root/etc/group" && ! grep -q ',steam,steam' "$root/etc/group"; then ok 'gruppi grafici aggiunti senza duplicati'; else no 'gruppi grafici duplicati o assenti'; fi
if [ -x "$root/usr/local/libexec/ps5-cachyos-tools/gamescope-session" ] && \
   [ -x "$root/usr/local/bin/ps5-cachyos-tools-gamescope-display-mode" ] && \
   [ -x "$root/usr/local/bin/ps5-cachyos-tools-video-diag" ] && \
   [ -x "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" ]; then ok 'wrapper DRM e utility Gamescope installate'; else no 'utility Gamescope incomplete'; fi
if grep -Fq 'KWIN_FORCE_SW_CURSOR=${KWIN_FORCE_SW_CURSOR:-0}' "$root/etc/profile.d/ps5-kde-environment.sh" && \
   grep -q 'KWIN_FORCE_SW_CURSOR' "$root/usr/local/libexec/ps5-cachyos-tools/session-supervisor" && \
   env -u KWIN_FORCE_SW_CURSOR bash -c 'source "$1"; [[ $KWIN_FORCE_SW_CURSOR == 0 ]]' _ "$ROOT/modules/kde/files/ps5-kde-environment.sh" && \
   env KWIN_FORCE_SW_CURSOR=1 bash -c 'source "$1"; [[ $KWIN_FORCE_SW_CURSOR == 1 ]]' _ "$ROOT/modules/kde/files/ps5-kde-environment.sh"; then
    ok 'KWin mantiene default 0 e override software cursor 1 solo in KDE'
else no 'default/override KWIN_FORCE_SW_CURSOR o isolamento sessione incompleto'; fi

if grep -Fq 'KWIN_FORCE_SW_CURSOR=${KWIN_FORCE_SW_CURSOR:-0}' "$root/etc/profile.d/ps5-kde-environment.sh" && \
   grep -q 'KWIN_FORCE_SW_CURSOR' "$root/usr/local/libexec/ps5-cachyos-tools/session-supervisor" && \
   env -u KWIN_FORCE_SW_CURSOR bash -c 'source "$1"; [[ $KWIN_FORCE_SW_CURSOR == 0 ]]' _ "$ROOT/modules/kde/files/ps5-kde-environment.sh" && \
   env KWIN_FORCE_SW_CURSOR=1 bash -c 'source "$1"; [[ $KWIN_FORCE_SW_CURSOR == 1 ]]' _ "$ROOT/modules/kde/files/ps5-kde-environment.sh"; then
    ok 'KWin software cursor opt-in mantiene default 0 e override 1 propagabile solo alla sessione KDE'
else no 'configurazione/propagazione KWIN_FORCE_SW_CURSOR incompleta'; fi

# A module revision change must refresh the helper assets of installed dependencies.
sed -i 's/^REVISION=3$/REVISION=1/' "$root/usr/lib/ps5-cachyos-tools/modules/gamescope/module.conf"
sed -i 's/^REVISION=3$/REVISION=1/' "$root/usr/lib/ps5-cachyos-tools/modules/kde/module.conf"
sed -i 's/^REVISION=7$/REVISION=4/' "$root/usr/lib/ps5-cachyos-tools/modules/session/module.conf"
printf 'stale helper\n' > "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair"
printf 'stale session runtime\n' > "$root/usr/local/libexec/ps5-cachyos-tools/session-common.sh"
printf 'stale KDE environment\n' > "$root/etc/profile.d/ps5-kde-environment.sh"
if "$CLI" install --root "$root" --module session > "$tmp/revision-upgrade.log" 2>&1 && \
   cmp -s "$ROOT/modules/gamescope/files/ps5-steam-verify-repair" "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" && \
   cmp -s "$ROOT/modules/session/files/session-common.sh" "$root/usr/local/libexec/ps5-cachyos-tools/session-common.sh" && \
   cmp -s "$ROOT/modules/kde/files/ps5-kde-environment.sh" "$root/etc/profile.d/ps5-kde-environment.sh"; then
    ok 'revisione module aggiorna helper Gamescope, sessione e ambiente KDE già installati'
else cat "$tmp/revision-upgrade.log" >&2; no 'aggiornamento selettivo non ha rinfrescato gli helper'; fi

missing_python="$tmp/missing-python"
fixture "$missing_python"
rm "$missing_python/usr/bin/python3"
if "$CLI" install --root "$missing_python" --module gamescope > "$tmp/missing-python.log" 2>&1; then
    no 'installazione Gamescope accetta Python runtime assente'
elif grep -q '/usr/bin/python3 richiesto' "$tmp/missing-python.log" && \
     [ ! -e "$missing_python/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" ]; then
    ok 'runtime Python dichiarato e installazione incompleta rifiutata senza residui'
else cat "$tmp/missing-python.log" >&2; no 'errore runtime Python non chiaro o rollback incompleto'; fi

if [ -x "$root/usr/local/bin/ps5-cachyos-tools-kde-display-mode" ] && \
   [ -f "$root/etc/xdg/autostart/ps5-cachyos-tools-kde-display-mode.desktop" ] && \
   grep -q 'ps5-cachyos-tools-kde-display-mode' "$root/usr/lib/ps5-cachyos-tools/modules/kde/check.sh" && \
   "$root/usr/lib/ps5-cachyos-tools/modules/kde/boot.sh" "$root"; then
    ok 'selezione automatica modalità KDE installata, controllata e verificata al boot'
else no 'helper o avvio automatico display KDE assenti'; fi

# Reinstall must preserve choices and settings made by the user.
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=\n' > "$root/home/steam/.config/ps5-cachyos-tools/session.conf"
printf 'PS5_OUTPUT_WIDTH=1280\n' > "$root/etc/ps5-cachyos-tools/gamescope.conf"
if "$CLI" install --root "$root" --module session > "$tmp/reinstall.log" 2>&1 && \
   grep -qx 'DEFAULT_SESSION=desktop' "$root/home/steam/.config/ps5-cachyos-tools/session.conf" && \
   grep -qx 'PS5_OUTPUT_WIDTH=1280' "$root/etc/ps5-cachyos-tools/gamescope.conf"; then
    ok 'reinstallazione idempotente preserva le configurazioni'
else cat "$tmp/reinstall.log" >&2; no 'reinstallazione ha sovrascritto configurazioni'; fi

legacy_config="$root/home/steam/.config/ps5-cachyos-tools/session.conf"
mv "$legacy_config" "$legacy_config.saved"
if "$CLI" check --root "$root" --module session >/dev/null 2>&1; then
    ok 'check Session non dipende più dal file session.conf legacy'
else no 'check Session richiede ancora session.conf'; fi
mv "$legacy_config.saved" "$legacy_config"

if "$CLI" remove gamescope --root "$root" > "$tmp/blocked.log" 2>&1; then no 'rimozione dipendenza Gamescope mentre Session è installato'; else ok 'framework blocca la rimozione di una dipendenza usata'; fi
if "$CLI" remove session --root "$root" > "$tmp/remove-session.log" 2>&1 && \
   grep -qx 'old profile' "$root/etc/profile.d/ps5-tty-session.sh" && \
   grep -qx 'old selector' "$root/usr/bin/steamos-session-select" && \
   [ -f "$root/home/steam/.config/ps5-cachyos-tools/session.conf" ]; then
    ok 'rimozione Session ripristina i file preesistenti e conserva la preferenza'
else cat "$tmp/remove-session.log" >&2; no 'rimozione Session non selettiva'; fi
if "$CLI" remove gamescope --root "$root" > "$tmp/remove-gamescope.log" 2>&1 && \
   grep -qx 'default=kde' "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf" && \
   [ -f "$root/etc/ps5-cachyos-tools/gamescope.conf" ]; then
    ok 'rimozione Gamescope ripristina portal e mantiene config con keep-config'
else cat "$tmp/remove-gamescope.log" >&2; no 'rimozione Gamescope non selettiva'; fi
if "$CLI" remove kde --root "$root" > "$tmp/remove-kde.log" 2>&1 && \
   grep -q '^video:x:27:steam$' "$root/etc/group" && ! grep -q '^render:x:995:steam$' "$root/etc/group" && \
   [ ! -e "$root/usr/local/bin/ps5-cachyos-tools-kde-display-mode" ] && \
   [ ! -e "$root/etc/xdg/autostart/ps5-cachyos-tools-kde-display-mode.desktop" ]; then
    ok 'rimozione KDE toglie solo gruppi e artefatti aggiunti e preserva membership originale'
else cat "$tmp/remove-kde.log" >&2; no 'rimozione gruppi KDE errata'; fi

# A clean installation defaults to KDE; a recognized legacy preference is preserved.
legacy_root="$tmp/legacy-root"
fixture "$legacy_root"
printf 'desktop\n' > "$legacy_root/home/steam/.config/ps5-next-session"
if "$CLI" install --root "$legacy_root" --module session >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=desktop' "$legacy_root/home/steam/.config/ps5-cachyos-tools/session.conf"; then
    ok 'migrazione conserva la preferenza selezionata dal modulo legacy'
else no 'preferenza legacy non migrata'; fi

legacy_gamescope_root="$tmp/legacy-gamescope-root"
fixture "$legacy_gamescope_root"
printf 'gamescope\n' > "$legacy_gamescope_root/home/steam/.config/ps5-next-session"
if "$CLI" install --root "$legacy_gamescope_root" --module session >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$legacy_gamescope_root/home/steam/.config/ps5-cachyos-tools/session.conf"; then
    ok 'migrazione conserva una preferenza Gamescope legacy esplicita'
else no 'preferenza Gamescope legacy non preservata'; fi

# Legacy selector must not alter boot policy or terminate a running session.
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${PS5_COMMAND_TRACE:-/dev/null}"
[[ ${1:-} != is-system-running ]] || { echo running; exit 0; }
if [[ ${1:-} == --user && ${2:-} == show ]]; then
    case "${3:-}" in
        xdg-desktop-portal-kde.service) printf 'not-found\ninactive\n' ;;
        *) printf 'loaded\ninactive\n' ;;
    esac
    exit 0
fi
exit 0
EOF
for command in pgrep pkill loginctl; do
    cat > "$fakebin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${PS5_COMMAND_TRACE:-/dev/null}"
if [[ ${0##*/} == loginctl && ${1:-} == seat-status ]]; then
    printf 'seat0\n  /sys/devices/test/drm/card0\n  drm:card0\n'
    exit 0
fi
if [[ ${0##*/} == loginctl && ${1:-} == show-session ]]; then
    session_id=$2; property=${4#-p}; property=${4#Property=}
    property=${4:-}; [[ $property == -p ]] && property=${5:-}
    property=${property#User=}; property=${property#Class=}; property=${property#Seat=}; property=${property#Active=}
    case "$session_id:$property" in
        1:User) value=1000;; 1:Class) value=user;; 1:Seat) value=seat0;; 1:Active) value=yes;;
        2:User) value=1000;; 2:Class) value=manager;; 2:Seat) value='';; 2:Active) value=yes;;
        *) exit 1;;
    esac
    printf '%s\n' "$value"
    exit 0
fi
if [[ ${0##*/} == loginctl && ${1:-} == show-user && ${4:-} == Sessions ]]; then
    printf '1 2\n'
    exit 0
fi
if [[ ${0##*/} == loginctl && ${1:-} == list-sessions ]]; then
    printf '1 1000 steam seat0 tty1 no -\n2 1000 steam - - no -\n'
    exit 0
fi
exit 1
EOF
done
chmod 0755 "$fakebin"/*
session_config="$tmp/selector/session.conf"
session_runtime="$tmp/selector/run"
mkdir -p "${session_config%/*}"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=gamescope\n' > "$session_config"
command_trace="$tmp/selector/commands"
if ! PS5_COMMAND_TRACE="$command_trace" PS5_SESSION_CONFIG="$session_config" PS5_SESSION_RUNTIME="$session_runtime" \
   PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" --default desktop >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$session_config" && grep -qx 'NEXT_SESSION=gamescope' "$session_config" && \
   [ ! -s "$command_trace" ]; then
    ok 'selettore live senza supervisore fallisce senza modificare il default di boot'
else no 'selettore senza supervisore ha modificato config o processi'; fi

plasma="$tmp/startplasma-wayland"
cat > "$plasma" <<'EOF'
#!/usr/bin/env bash
printf 'plasma\n' >> "$PS5_TRACE"
if [[ -n ${PS5_ENV_TRACE:-} ]]; then printf '%s|%s|%s|%s\n' "${KWIN_DRM_PREFER_COLOR_DEPTH-unset}" "${KWIN_DRM_NO_DIRECT_SCANOUT-unset}" "${KWIN_FORCE_ASSUME_HDR_SUPPORT-unset}" "${KWIN_FORCE_SW_CURSOR-unset}" >> "$PS5_ENV_TRACE"; fi
if [[ ${FAKE_PLASMA_WAIT:-0} == 1 ]]; then trap 'exit 0' TERM INT; while :; do sleep 0.1; done; fi
exit "${PLASMA_RC:-0}"
EOF
gamescope_mock="$tmp/gamescope-session"
cat > "$gamescope_mock" <<'EOF'
#!/usr/bin/env bash
printf 'gamescope\n' >> "$PS5_TRACE"
if [[ -n ${PS5_ENV_TRACE:-} ]]; then printf '%s|%s|%s|%s\n' "${KWIN_DRM_PREFER_COLOR_DEPTH-unset}" "${KWIN_DRM_NO_DIRECT_SCANOUT-unset}" "${KWIN_FORCE_ASSUME_HDR_SUPPORT-unset}" "${KWIN_FORCE_SW_CURSOR-unset}" >> "$PS5_ENV_TRACE"; fi
if [[ ${FAKE_GAMESCOPE_WAIT:-0} == 1 ]]; then sleep 30; fi
exit "${FAKE_GAMESCOPE_RC:-0}"
EOF
chmod 0755 "$plasma" "$gamescope_mock"

# Live switching is transient and keeps the repository boot policy unchanged.
live="$tmp/live-switch"
mkdir -p "$live/home" "$live/run" "$live/home/.config/ps5-cachyos-tools"
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=gamescope\n' > "$live/home/.config/ps5-cachyos-tools/session.conf"
cp "$live/home/.config/ps5-cachyos-tools/session.conf" "$live/session.conf.expected"
cp "$SUPERVISOR" "$live/home/session-supervisor"
cp "$ROOT/modules/session/files/session-policy" "$live/home/session-policy"
printf '#!/usr/bin/env bash\nprintf desktop\n' > "$live/home/session-policy"
chmod 0755 "$live/home/session-policy"
PS5_SESSION_RUNTIME="$live/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$live/home/session.log" \
  PS5_COMMAND_TRACE="$live/commands" PS5_ENV_TRACE="$live/env-trace" PS5_PLASMA_BIN="$plasma" \
  PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$live/trace" HOME="$live/home" \
  KWIN_DRM_PREFER_COLOR_DEPTH=24 KWIN_DRM_NO_DIRECT_SCANOUT=1 KWIN_FORCE_ASSUME_HDR_SUPPORT=0 KWIN_FORCE_SW_CURSOR=1 \
  PS5_FORCE_TTY1=1 FAKE_PLASMA_WAIT=1 FAKE_GAMESCOPE_WAIT=1 PATH="$fakebin:$PATH" \
  "$live/home/session-supervisor" >"$live/home/supervisor.out" 2>&1 &
live_pid=$!
wait_for_trace() {
    local expected=$1 count=0
    while (( count < 100 )); do
        [[ -f "$live/trace" ]] && (( $(grep -xc "$expected" "$live/trace") >= 1 )) && return 0
        sleep 0.05; count=$((count + 1))
    done
    return 1
}
live_ok=1
wait_for_trace plasma || live_ok=0
if PS5_SESSION_RUNTIME="$live/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$live/home/duplicate.log" \
   PS5_SESSION_SUPERVISOR=1 "$live/home/session-supervisor" >/dev/null 2>&1; then live_ok=0; fi
PS5_SESSION_RUNTIME="$live/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --default gamescope >/dev/null 2>&1 || live_ok=0
for _ in {1..100}; do [[ -f "$live/trace" ]] && (( $(grep -xc gamescope "$live/trace") >= 1 )) && break; sleep 0.05; done
[[ -f "$live/trace" ]] && (( $(grep -xc gamescope "$live/trace") >= 1 )) || live_ok=0
PS5_SESSION_RUNTIME="$live/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --once desktop >/dev/null 2>&1 || live_ok=0
for _ in {1..100}; do [[ -f "$live/trace" ]] && (( $(grep -xc plasma "$live/trace") >= 2 )) && break; sleep 0.05; done
[[ -f "$live/trace" ]] && (( $(grep -xc plasma "$live/trace") >= 2 )) || live_ok=0
"$live/home/session-policy" | grep -qx desktop || live_ok=0
cmp -s "$live/session.conf.expected" "$live/home/.config/ps5-cachyos-tools/session.conf" || live_ok=0
grep -q 'systemctl --user import-environment .*KWIN_FORCE_SW_CURSOR' "$live/commands" 2>/dev/null || live_ok=0
grep -q 'systemctl --user unset-environment .*KWIN_FORCE_SW_CURSOR' "$live/commands" 2>/dev/null || live_ok=0
printf '24|1|0|1\nunset|unset|unset|unset\n24|1|0|1\n' > "$live/env-trace.expected"
cmp -s "$live/env-trace.expected" "$live/env-trace" || live_ok=0
grep -q 'unità KDE opzionale assente, ignorata: xdg-desktop-portal-kde.service' "$live/home/session.log" 2>/dev/null || live_ok=0
! grep -q 'systemctl --user stop xdg-desktop-portal-kde.service' "$live/commands" 2>/dev/null || live_ok=0
kill -TERM "$live_pid" 2>/dev/null || true
wait "$live_pid" 2>/dev/null || true
if (( live_ok )); then ok 'supervisore consente KDE→Gamescope→KDE senza cambiare policy o session.conf'; else cat "$live/home/supervisor.out" "$live/home/session.log" "$live/trace" >&2 2>/dev/null; no 'transizione live KDE/Gamescope'; fi

# If KWin remains active, the live switch is rejected and KDE is restored.
busy_seat="$tmp/busy-seat"
mkdir -p "$busy_seat/home" "$busy_seat/run" "$busy_seat/bin"
cp "$SUPERVISOR" "$busy_seat/home/session-supervisor"
cat > "$busy_seat/home/session-policy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' gamescope
EOF
cat > "$busy_seat/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == --user && ${2:-} == show ]]; then
    if [[ ${3:-} == plasma-kwin_wayland.service ]]; then printf 'loaded\nactive\n'; else printf 'loaded\ninactive\n'; fi
    exit 0
fi
exit 0
EOF
chmod 0755 "$busy_seat/home/session-policy" "$busy_seat/bin/systemctl"
busy_ok=1
if PS5_SESSION_RUNTIME="$busy_seat/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$busy_seat/home/session.log" \
   PS5_FALLBACK_LOG="$busy_seat/home/fallback.log" PS5_ALERT_FILE="$busy_seat/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$busy_seat/trace" HOME="$busy_seat/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 PS5_SESSION_SEAT_RELEASE_TIMEOUT_SEC=1 \
   PATH="$busy_seat/bin:$fakebin:$PATH" "$busy_seat/home/session-supervisor" >/dev/null 2>&1; then
    grep -qx plasma "$busy_seat/trace" 2>/dev/null || busy_ok=0
    grep -qx gamescope "$busy_seat/trace" 2>/dev/null && busy_ok=0
    grep -q 'compositor KWin ancora attivo' "$busy_seat/home/fallback.log" 2>/dev/null || busy_ok=0
else busy_ok=0; fi
if (( busy_ok )); then ok 'KWin ancora attivo rifiuta Gamescope e ripristina KDE'; else cat "$busy_seat/home/session.log" "$busy_seat/home/fallback.log" "$busy_seat/trace" >&2 2>/dev/null; no 'KWin attivo non protegge il fallback'; fi

multi_session="$tmp/multi-session"
mkdir -p "$multi_session/home" "$multi_session/run" "$multi_session/bin" "$multi_session/home/.config/ps5-cachyos-tools"
cp "$SUPERVISOR" "$multi_session/home/session-supervisor"
cat > "$multi_session/home/session-policy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' desktop
EOF
cat > "$multi_session/bin/loginctl" <<'EOF'
#!/usr/bin/env bash
if [[ ${1:-} == show-session ]]; then
    case "${2:-}:${4:-}" in
        1:User|3:User|2:User) echo 1000;;
        1:Class|3:Class) echo user;; 2:Class) echo manager;;
        1:Seat) echo seat0;; 1:Active) echo yes;; 3:Seat) echo seat1;; 3:Active) echo yes;;
        2:Seat) echo '';; 2:Active) echo yes;; *) exit 1;;
    esac
    exit 0
fi
if [[ ${1:-} == show-user && ${4:-} == Sessions ]]; then
    if [[ -e ${FAKE_MULTI_SESSION_FILE:-/nonexistent} ]]; then printf '1 3 2\n'; else printf '1 2\n'; fi
    exit 0
fi
if [[ ${1:-} == list-sessions ]]; then
    [[ ! -e ${FAKE_SESSION_LIST_EMPTY_FILE:-/nonexistent} ]] || exit 0
    printf '1 1000 steam seat0 tty1 no -\n'
    if [[ -e ${FAKE_MULTI_SESSION_FILE:-/nonexistent} && ! -e ${FAKE_SESSION_LIST_PARTIAL_FILE:-/nonexistent} ]]; then
        printf '3 1000 steam seat1 tty2 no -\n'
    fi
    printf '2 1000 steam - - no -\n'
    exit 0
fi
exit 1
EOF
chmod 0755 "$multi_session/home/session-policy" "$multi_session/bin/loginctl"
touch "$multi_session/multi.active"
PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$multi_session/home/session.log" \
  PS5_COMMAND_TRACE="$multi_session/commands" PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" \
  PS5_TRACE="$multi_session/trace" HOME="$multi_session/home" FAKE_MULTI_SESSION_FILE="$multi_session/multi.active" PS5_FORCE_TTY1=1 FAKE_PLASMA_WAIT=1 \
  PATH="$multi_session/bin:$fakebin:$PATH" "$multi_session/home/session-supervisor" >"$multi_session/home/supervisor.out" 2>&1 &
multi_pid=$!
multi_ok=1
for _ in {1..100}; do [[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" && break; sleep 0.05; done
[[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" || multi_ok=0
if PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --once gamescope >/dev/null 2>&1; then :; else multi_ok=0; fi
for _ in {1..100}; do grep -q 'sessione KDE lasciata attiva' "$multi_session/home/session.log" 2>/dev/null && break; sleep 0.05; done
grep -q 'sessione KDE lasciata attiva' "$multi_session/home/session.log" 2>/dev/null || multi_ok=0
grep -qx plasma "$multi_session/trace" 2>/dev/null || multi_ok=0
grep -qx gamescope "$multi_session/trace" 2>/dev/null && multi_ok=0
grep -q 'systemctl --user stop plasma-workspace-wayland.target' "$multi_session/commands" 2>/dev/null && multi_ok=0
rm -f "$multi_session/multi.active"
kill -TERM "$multi_pid" 2>/dev/null || true
wait "$multi_pid" 2>/dev/null || true
if (( multi_ok )); then ok 'sessione utente concorrente rifiuta lo switch senza fermare KDE'; else cat "$multi_session/home/supervisor.out" "$multi_session/home/session.log" "$multi_session/commands" "$multi_session/trace" >&2 2>/dev/null; no 'sessione concorrente non protegge KDE'; fi

: > "$multi_session/trace"
: > "$multi_session/home/session.log"
: > "$multi_session/commands"
touch "$multi_session/multi.active" "$multi_session/session-list.partial"
partial_sessions_ok=1
PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$multi_session/home/session.log" \
  PS5_COMMAND_TRACE="$multi_session/commands" PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" \
  PS5_TRACE="$multi_session/trace" HOME="$multi_session/home" FAKE_MULTI_SESSION_FILE="$multi_session/multi.active" \
  FAKE_SESSION_LIST_PARTIAL_FILE="$multi_session/session-list.partial" PS5_FORCE_TTY1=1 FAKE_PLASMA_WAIT=1 \
  PATH="$multi_session/bin:$fakebin:$PATH" "$multi_session/home/session-supervisor" >"$multi_session/home/partial-supervisor.out" 2>&1 &
partial_pid=$!
for _ in {1..100}; do [[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" && break; sleep 0.05; done
[[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" || partial_sessions_ok=0
if PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --once gamescope >/dev/null 2>&1; then :; else partial_sessions_ok=0; fi
for _ in {1..100}; do grep -q 'elenco sessioni logind incompleto rispetto' "$multi_session/home/session.log" 2>/dev/null && break; sleep 0.05; done
grep -q 'elenco sessioni logind incompleto rispetto' "$multi_session/home/session.log" 2>/dev/null || partial_sessions_ok=0
grep -qx gamescope "$multi_session/trace" 2>/dev/null && partial_sessions_ok=0
grep -q 'systemctl --user stop plasma-workspace-wayland.target' "$multi_session/commands" 2>/dev/null && partial_sessions_ok=0
rm -f "$multi_session/multi.active" "$multi_session/session-list.partial"
kill -TERM "$partial_pid" 2>/dev/null || true
wait "$partial_pid" 2>/dev/null || true
if (( partial_sessions_ok )); then ok 'elenco sessioni parziale viene rilevato dal controllo logind incrociato'; else cat "$multi_session/home/partial-supervisor.out" "$multi_session/home/session.log" "$multi_session/commands" "$multi_session/trace" >&2 2>/dev/null; no 'elenco sessioni parziale non blocca cleanup'; fi

: > "$multi_session/trace"
: > "$multi_session/home/session.log"
: > "$multi_session/commands"
touch "$multi_session/sessions.empty"
empty_sessions_ok=1
PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$multi_session/home/session.log" \
  PS5_COMMAND_TRACE="$multi_session/commands" PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" \
  PS5_TRACE="$multi_session/trace" HOME="$multi_session/home" FAKE_MULTI_SESSION_FILE="$multi_session/multi.active" \
  FAKE_SESSION_LIST_EMPTY_FILE="$multi_session/sessions.empty" PS5_FORCE_TTY1=1 FAKE_PLASMA_WAIT=1 \
  PATH="$multi_session/bin:$fakebin:$PATH" "$multi_session/home/session-supervisor" >"$multi_session/home/empty-supervisor.out" 2>&1 &
empty_sessions_pid=$!
for _ in {1..100}; do [[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" && break; sleep 0.05; done
[[ -f "$multi_session/trace" ]] && grep -qx plasma "$multi_session/trace" || empty_sessions_ok=0
if PS5_SESSION_RUNTIME="$multi_session/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --once gamescope >/dev/null 2>&1; then :; else empty_sessions_ok=0; fi
for _ in {1..100}; do grep -q 'elenco sessioni logind vuoto o incompleto' "$multi_session/home/session.log" 2>/dev/null && break; sleep 0.05; done
grep -q 'elenco sessioni logind vuoto o incompleto' "$multi_session/home/session.log" 2>/dev/null || empty_sessions_ok=0
grep -qx gamescope "$multi_session/trace" 2>/dev/null && empty_sessions_ok=0
grep -q 'systemctl --user stop plasma-workspace-wayland.target' "$multi_session/commands" 2>/dev/null && empty_sessions_ok=0
rm -f "$multi_session/sessions.empty"
kill -TERM "$empty_sessions_pid" 2>/dev/null || true
wait "$empty_sessions_pid" 2>/dev/null || true
if (( empty_sessions_ok )); then ok 'elenco logind vuoto rifiuta cleanup e mantiene KDE attivo'; else cat "$multi_session/home/empty-supervisor.out" "$multi_session/home/session.log" "$multi_session/commands" "$multi_session/trace" >&2 2>/dev/null; no 'elenco logind vuoto non blocca cleanup'; fi

if ! rg -q 'pkill|kill -TERM.*(plasmashell|kwin_wayland|Xwayland)' "$SUPERVISOR"; then
    ok 'cleanup KDE non invia segnali per UID/nome a processi grafici esterni al process group'
else no 'cleanup KDE conserva un kill grafico UID-wide'; fi

# A live request can leave the DRM readiness gate before Gamescope starts.
drm_switch="$tmp/drm-live-switch"
mkdir -p "$drm_switch/home" "$drm_switch/run"
cp "$SUPERVISOR" "$drm_switch/home/session-supervisor"
cat > "$drm_switch/home/session-policy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' gamescope
EOF
chmod 0755 "$drm_switch/home/session-policy"
PS5_SESSION_RUNTIME="$drm_switch/run" PS5_SESSION_COMMON="$COMMON" PS5_SESSION_LOG="$drm_switch/home/session.log" \
  PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$drm_switch/trace" HOME="$drm_switch/home" \
  PS5_FORCE_TTY1=1 PS5_DRM_DEVICE="$drm_switch/no-card" PS5_SESSION_DRM_READY_TIMEOUT_SEC=60 \
  PS5_SESSION_DRM_POLL_INTERVAL_SEC=1 PATH="$fakebin:$PATH" "$drm_switch/home/session-supervisor" >"$drm_switch/home/supervisor.out" 2>&1 &
drm_pid=$!
for _ in {1..100}; do grep -q 'attesa DRM' "$drm_switch/home/session.log" 2>/dev/null && break; sleep 0.05; done
drm_ok=1
grep -q 'attesa DRM' "$drm_switch/home/session.log" 2>/dev/null || drm_ok=0
PS5_SESSION_RUNTIME="$drm_switch/run" PS5_SESSION_COMMON="$COMMON" "$SELECT" --once desktop >/dev/null 2>&1 || drm_ok=0
wait "$drm_pid" 2>/dev/null || true
grep -qx plasma "$drm_switch/trace" 2>/dev/null || drm_ok=0
if (( drm_ok )); then ok 'richiesta live KDE viene rilevata durante l’attesa DRM'; else cat "$drm_switch/home/supervisor.out" "$drm_switch/home/session.log" "$drm_switch/trace" >&2 2>/dev/null; no 'richiesta durante attesa DRM'; fi

write_gamescope_policy() {
    cp "$SUPERVISOR" "${1%/*}/session-supervisor"
    cat > "$1" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' gamescope
EOF
    chmod 0755 "$1"
}

run_supervisor() {
    local config=$1 trace=$2 home=$3
    local policy="$home/session-policy"
    cp "$SUPERVISOR" "$home/session-supervisor"
    if [[ ! -x $policy ]]; then cp "$ROOT/modules/session/files/session-policy" "$policy"; chmod 0755 "$policy"; fi
    PS5_SESSION_CONFIG="$config" PS5_SESSION_RUNTIME="$home/run" PS5_SESSION_COMMON="$COMMON" \
      PS5_SESSION_LOG="$home/session.log" PS5_FALLBACK_LOG="$home/fallback.log" PS5_ALERT_FILE="$home/alert.txt" \
      PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$trace" HOME="$home" \
      PS5_FORCE_TTY1=1 PATH="$fakebin:$PATH" "$home/session-supervisor"
}

startup="$tmp/startup"
mkdir -p "$startup/home" "$startup/run"
if run_supervisor "$startup/session.conf" "$startup/trace" "$startup/home" >/dev/null 2>&1 && \
   grep -qx plasma "$startup/trace" && ! grep -q gamescope "$startup/trace" && \
   grep -q 'policy repository seleziona desktop' "$startup/home/session.log"; then
    ok 'policy repository assente config legacy avvia Plasma con default KDE'
else no 'policy KDE non avvia Plasma'; fi

invalid_startup="$tmp/invalid-startup"
mkdir -p "$invalid_startup/home" "$invalid_startup/run"
printf 'DEFAULT_SESSION=invalid\n' > "$invalid_startup/session.conf"
if run_supervisor "$invalid_startup/session.conf" "$invalid_startup/trace" "$invalid_startup/home" >/dev/null 2>&1 && \
   grep -qx plasma "$invalid_startup/trace" && ! grep -q gamescope "$invalid_startup/trace" && \
   grep -q 'policy repository seleziona desktop' "$invalid_startup/home/session.log"; then
    ok 'configurazione invalida legacy non cambia la policy KDE'
else no 'configurazione invalida legacy ha cambiato policy'; fi

stale_choice="$tmp/stale-choice"
mkdir -p "$stale_choice/home" "$stale_choice/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=gamescope\n' > "$stale_choice/session.conf"
if run_supervisor "$stale_choice/session.conf" "$stale_choice/trace" "$stale_choice/home" >/dev/null 2>&1 && \
   grep -qx plasma "$stale_choice/trace" && ! grep -q gamescope "$stale_choice/trace" && \
   grep -q 'policy repository seleziona desktop' "$stale_choice/home/session.log"; then
    ok 'policy repository KDE prevale su DEFAULT_SESSION e NEXT_SESSION legacy'
else no 'configurazione legacy ha prevalso sulla policy KDE'; fi

for policy_state in missing invalid; do
    policy_case="$tmp/policy-$policy_state"
    mkdir -p "$policy_case/home" "$policy_case/run"
    cp "$SUPERVISOR" "$policy_case/home/session-supervisor"
    if [[ $policy_state == invalid ]]; then
        printf '#!/usr/bin/env bash\nprintf unknown\n' > "$policy_case/home/session-policy"
        chmod 0755 "$policy_case/home/session-policy"
    fi
    if PS5_SESSION_CONFIG="$policy_case/session.conf" PS5_SESSION_RUNTIME="$policy_case/run" PS5_SESSION_COMMON="$COMMON" \
       PS5_SESSION_LOG="$policy_case/home/session.log" PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" \
       PS5_TRACE="$policy_case/trace" HOME="$policy_case/home" PS5_FORCE_TTY1=1 PATH="$fakebin:$PATH" \
       "$policy_case/home/session-supervisor" >/dev/null 2>&1 && grep -qx plasma "$policy_case/trace" && ! grep -q gamescope "$policy_case/trace"; then
        ok "policy $policy_state ricade su KDE"
    else no "policy $policy_state non ricade su KDE"; fi
done

drm_root="$tmp/drm"
mkdir -p "$drm_root/card0-DP-1"
printf 'connected\n' > "$drm_root/card0-DP-1/status"
printf '1920x1080\n' > "$drm_root/card0-DP-1/modes"
touch "$tmp/card0"

timeout_case="$tmp/timeout"
mkdir -p "$timeout_case/home" "$timeout_case/drm"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$timeout_case/session.conf"
write_gamescope_policy "$timeout_case/home/session-policy"
if PS5_SESSION_CONFIG="$timeout_case/session.conf" PS5_SESSION_RUNTIME="$timeout_case/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$timeout_case/home/session.log" PS5_FALLBACK_LOG="$timeout_case/home/fallback.log" PS5_ALERT_FILE="$timeout_case/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$timeout_case/trace" HOME="$timeout_case/home" \
   PS5_FORCE_TTY1=1 PS5_DRM_SYSFS_ROOT="$timeout_case/drm" PS5_DRM_DEVICE="$timeout_case/no-card" PS5_SESSION_DRM_READY_TIMEOUT_SEC=1 \
   PS5_SESSION_DRM_POLL_INTERVAL_SEC=0.1 PS5_SESSION_DRM_STABLE_SAMPLES=1 PATH="$fakebin:$PATH" "$timeout_case/home/session-supervisor" >/dev/null 2>&1 && \
   grep -qx plasma "$timeout_case/trace" && grep -q 'DRM non pronto' "$timeout_case/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$timeout_case/session.conf"; then
    ok 'timeout DRM avvia KDE senza sovrascrivere il default'
else no 'fallback timeout DRM'; fi

failure="$tmp/failure"
mkdir -p "$failure/home" "$failure/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$failure/session.conf"
write_gamescope_policy "$failure/home/session-policy"
if PS5_SESSION_CONFIG="$failure/session.conf" PS5_SESSION_RUNTIME="$failure/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$failure/home/session.log" PS5_FALLBACK_LOG="$failure/home/fallback.log" PS5_ALERT_FILE="$failure/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$failure/trace" HOME="$failure/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 FAKE_GAMESCOPE_RC=42 PATH="$fakebin:$PATH" "$failure/home/session-supervisor" >/dev/null 2>&1 && \
   printf 'gamescope\nplasma\n' > "$failure/expected" && cmp -s "$failure/expected" "$failure/trace" && grep -q 'exit=42' "$failure/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$failure/session.conf" && [ -f "$failure/home/alert.txt" ]; then
    ok 'crash Gamescope pulisce la sessione, registra causa e avvia KDE'
else no 'fallback crash Gamescope'; fi

missing="$tmp/missing-wrapper"
mkdir -p "$missing/home" "$missing/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$missing/session.conf"
write_gamescope_policy "$missing/home/session-policy"
if PS5_SESSION_CONFIG="$missing/session.conf" PS5_SESSION_RUNTIME="$missing/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$missing/home/session.log" PS5_FALLBACK_LOG="$missing/home/fallback.log" PS5_ALERT_FILE="$missing/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$missing/not-installed" PS5_TRACE="$missing/trace" HOME="$missing/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 PATH="$fakebin:$PATH" "$missing/home/session-supervisor" >/dev/null 2>&1 && \
   grep -qx plasma "$missing/trace" && grep -q 'wrapper assente' "$missing/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$missing/session.conf"; then
    ok 'wrapper Gamescope assente avvia KDE e conserva il default'
else no 'wrapper Gamescope assente non attiva il fallback'; fi

normal="$tmp/normal-exit"
mkdir -p "$normal/home" "$normal/run"
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=desktop\n' > "$normal/session.conf"
write_gamescope_policy "$normal/home/session-policy"
if PS5_SESSION_CONFIG="$normal/session.conf" PS5_SESSION_RUNTIME="$normal/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$normal/home/session.log" PS5_FALLBACK_LOG="$normal/home/fallback.log" PS5_ALERT_FILE="$normal/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$normal/trace" HOME="$normal/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 FAKE_GAMESCOPE_RC=0 PATH="$fakebin:$PATH" "$normal/home/session-supervisor" >/dev/null 2>&1 && \
   printf 'gamescope\nplasma\n' > "$normal/expected" && cmp -s "$normal/expected" "$normal/trace" && \
   { [ ! -e "$normal/home/fallback.log" ] || ! grep -q 'Gamescope failure' "$normal/home/fallback.log"; } && \
   grep -qx 'DEFAULT_SESSION=desktop' "$normal/session.conf" && grep -qx 'NEXT_SESSION=desktop' "$normal/session.conf"; then
    ok 'uscita normale avvia KDE senza falso log di errore o cambio default'
else no 'uscita normale Gamescope classificata male'; fi

# Exercise the mode detector and argument validation in the installed wrapper.
wrapper_home="$tmp/wrapper-home"
mkdir -p "$wrapper_home/steam/logs" "$tmp/mockbin"
cat > "$tmp/mockbin/steam" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$PS5_STEAM_ARGS"
if [[ ${FAKE_STEAM_CRASH_MARKER:-0} == 1 ]]; then printf 'Segmentation fault\n' >> "$PS5_STEAM_DIR/logs/console-linux.txt"; fi
exit 0
EOF
cat > "$tmp/mockbin/gamescope" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$PS5_GAMESCOPE_ARGS"
if [[ -n ${PS5_GAMESCOPE_DIAG_STATE:-} ]]; then printf '%s\n' "${PS5_GAMESCOPE_DRM_DIAGNOSTICS:-unset}" > "$PS5_GAMESCOPE_DIAG_STATE"; fi
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
[[ $# -gt 0 ]] || exit 99
shift
"$@"
EOF
chmod 0755 "$tmp/mockbin/steam" "$tmp/mockbin/gamescope"
printf 'PS5_OUTPUT_WIDTH=1280\nPS5_OUTPUT_HEIGHT=720\nPS5_REFRESH_RATE=60\n' > "$tmp/gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" PS5_STEAM_ARGS="$tmp/steam-args" PS5_GAMESCOPE_ARGS="$tmp/gs-args" PS5_GAMESCOPE_DIAG_STATE="$tmp/diag-default" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   grep -qx -- '-W' "$tmp/gs-args" && grep -qx '1280' "$tmp/gs-args" && grep -qx -- '-H' "$tmp/gs-args" && grep -qx '720' "$tmp/gs-args" && \
   grep -qx -- '-gamepadui -steamos' "$tmp/steam-args" && grep -qx 'unset' "$tmp/diag-default"; then
    ok 'wrapper Gamescope rileva DRM e costruisce gli argomenti con override validato'
else no 'wrapper Gamescope non applica override/DRM'; fi

printf 'PS5_DRM_DIAGNOSTICS=1\n' > "$tmp/diagnostic-gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/diagnostic-wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/diagnostic-gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" PS5_STEAM_ARGS="$tmp/steam-args" \
   PS5_GAMESCOPE_ARGS="$tmp/diagnostic-gs-args" PS5_GAMESCOPE_DIAG_STATE="$tmp/diag-enabled" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   grep -qx '1' "$tmp/diag-enabled" && grep -q 'milestone=drm_diagnostics_enabled scope=first-32-commits-and-page-flips' "$tmp/diagnostic-wrapper.log"; then
    ok 'diagnostica DRM Gamescope opt-in esportata solo quando richiesta dalla config'
else no 'diagnostica DRM Gamescope non è opt-in o non viene propagata'; fi

printf 'PS5_DRM_DIAGNOSTICS=2\n' > "$tmp/invalid-diagnostic-gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/invalid-diagnostic-wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/invalid-diagnostic-gamescope.conf" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1; then
    no 'valore non booleano diagnostica DRM accettato'
else
    ok 'valore non booleano diagnostica DRM rifiutato prima dell’avvio';
fi

cat > "$tmp/fake-gamescope-mode-detector" <<'EOF'
#!/usr/bin/env bash
[[ -z ${PS5_GAMESCOPE_PREFERRED_CONNECTOR:-} || ${PS5_GAMESCOPE_PREFERRED_CONNECTOR:-} == HDMI-A-1 ]] || exit 90
printf '3440\t1440\t100\tHDMI-A-1\n'
EOF
chmod 0755 "$tmp/fake-gamescope-mode-detector"
printf 'PS5_OUTPUT_CONN=HDMI-A-1\n' > "$tmp/dynamic-gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/dynamic-wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/dynamic-gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_GAMESCOPE_MODE_DETECTOR="$tmp/fake-gamescope-mode-detector" PS5_STEAM_EXEC="$tmp/mockbin/steam" \
   PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" PS5_STEAM_ARGS="$tmp/steam-args" PS5_GAMESCOPE_ARGS="$tmp/dynamic-gs-args" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   grep -qx -- '--backend' "$tmp/dynamic-gs-args" && grep -qx 'drm' "$tmp/dynamic-gs-args" && \
   grep -qx -- '--prefer-output' "$tmp/dynamic-gs-args" && grep -qx 'HDMI-A-1' "$tmp/dynamic-gs-args" && \
   ! grep -Eq '^(-W|-H|-w|-h|-r)$' "$tmp/dynamic-gs-args" && \
   grep -q 'connector=HDMI-A-1 3440x1440 aspect=3440:1440 refresh=100 source=DRM-KMS' "$tmp/dynamic-wrapper.log"; then
    ok 'wrapper mantiene mode DRM, aspect e refresh solo diagnostici e non li fissa al cambio display'
else no 'wrapper Gamescope fissa dimensioni automatiche invece di seguire il backend DRM'; fi

printf '# automatico: lascia selezione nativa e hotplug al backend Gamescope DRM\n' > "$tmp/automatic-gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/automatic-wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/automatic-gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_GAMESCOPE_MODE_DETECTOR="$tmp/fake-gamescope-mode-detector" PS5_STEAM_EXEC="$tmp/mockbin/steam" \
   PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" PS5_STEAM_ARGS="$tmp/steam-args" PS5_GAMESCOPE_ARGS="$tmp/automatic-gs-args" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   ! grep -Eq '^(-W|-H|-w|-h|-r|--prefer-output)$' "$tmp/automatic-gs-args" && \
   grep -q 'milestone=display_mode_candidate' "$tmp/automatic-wrapper.log"; then
    ok 'config vuota non blocca resolution, aspect, refresh o connettore automatici'
else no 'config vuota forza una modalità o un connettore'; fi

# A diagnostic error in the synchronous verifier must stay fail-open, and
# timeline fields must correlate the wrapper with the requesting session.
cat > "$tmp/failing-steam-helper" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PS5_SESSION_ID" > "$PS5_HELPER_SESSION_ID"
printf 'simulated EIO while inspecting Steam manifest\n' >&2
exit 17
EOF
chmod 0755 "$tmp/failing-steam-helper"
printf '11111111-2222-3333-4444-555555555555\n' > "$tmp/boot-id"
printf '123.45 0.00\n' > "$tmp/uptime"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/fail-open-wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_VERIFY_REPAIR="$tmp/failing-steam-helper" PS5_BOOT_ID_FILE="$tmp/boot-id" PS5_UPTIME_FILE="$tmp/uptime" \
   PS5_SESSION_ID=integration-session-17 PS5_HELPER_SESSION_ID="$tmp/helper-session-id" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" \
   PS5_STEAM_ARGS="$tmp/steam-args" PS5_GAMESCOPE_ARGS="$tmp/fail-open-gs-args" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   [ "$(cat "$tmp/helper-session-id")" = integration-session-17 ] && \
   grep -q 'warning=Steam manifest inspection failed (exit=17); continuing fail-open' "$tmp/fail-open-wrapper.log" && \
   grep -q 'milestone=steam_manifest_check_start' "$tmp/fail-open-wrapper.log" && \
   grep -q 'milestone=steam_manifest_check_end exit=17 elapsed_ms=0' "$tmp/fail-open-wrapper.log" && \
   grep -q 'milestone=gamescope_exec_start' "$tmp/fail-open-wrapper.log" && \
   grep -q 'milestone=gamescope_exec_exit exit=0 elapsed_ms=0' "$tmp/fail-open-wrapper.log" && \
   grep -q 'boot_id=11111111-2222-3333-4444-555555555555 session_id=integration-session-17 monotonic_ms=123450' "$tmp/fail-open-wrapper.log"; then
    ok 'helper Steam fail-open conserva l’avvio e registra milestone monotone correlate'
else cat "$tmp/fail-open-wrapper.log" >&2 2>/dev/null; no 'errore helper blocca Gamescope o milestone non correlate'; fi

printf 'abcdef12-2222-3333-4444-555555555555\n' > "$tmp/session-boot-id"
printf '234.56 0.00\n' > "$tmp/session-uptime"
if PS5_SESSION_LOG="$tmp/session-milestones.log" PS5_BOOT_ID_FILE="$tmp/session-boot-id" \
   PS5_UPTIME_FILE="$tmp/session-uptime" PS5_SESSION_ID=supervisor-session-9 \
   bash -c 'source "$1" && ps5_session_log info milestone=test_event' _ "$COMMON" && \
   grep -q 'boot_id=abcdef12-2222-3333-4444-555555555555 session_id=supervisor-session-9 monotonic_ms=234560 info: milestone=test_event' "$tmp/session-milestones.log"; then
    ok 'log Session usa boot ID, session ID e clock monotono'
else no 'metadati temporali Session non correlabili'; fi

steam_crash="$tmp/steam-crash"
mkdir -p "$steam_crash/home/steam/logs" "$steam_crash/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$steam_crash/session.conf"
write_gamescope_policy "$steam_crash/home/session-policy"
if PS5_SESSION_CONFIG="$steam_crash/session.conf" PS5_SESSION_RUNTIME="$steam_crash/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$steam_crash/home/session.log" PS5_FALLBACK_LOG="$steam_crash/home/fallback.log" PS5_ALERT_FILE="$steam_crash/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$ROOT/modules/gamescope/files/gamescope-session-ps5" PS5_TRACE="$steam_crash/trace" HOME="$steam_crash/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 PS5_STEAM_DIR="$steam_crash/home/steam" \
   PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" \
   PS5_STEAM_ARGS="$steam_crash/steam-args" PS5_GAMESCOPE_ARGS="$steam_crash/gamescope-args" PS5_GAMESCOPE_CONFIG="$tmp/gamescope.conf" \
   PS5_GAMESCOPE_LOG="$steam_crash/home/gamescope.log" FAKE_STEAM_CRASH_MARKER=1 PATH="$fakebin:$PATH" "$steam_crash/home/session-supervisor" >/dev/null 2>&1 && \
   grep -qx plasma "$steam_crash/trace" && grep -q 'exit=73' "$steam_crash/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$steam_crash/session.conf"; then
    ok 'marker di crash Steam rilevato dal wrapper provoca fallback KDE conservando il default'
else no 'marker crash Steam non rilevato o fallback non eseguito'; fi
printf 'PS5_OUTPUT_WIDTH=64\n' > "$tmp/bad-gamescope.conf"
if HOME="$wrapper_home" PS5_GAMESCOPE_CONFIG="$tmp/bad-gamescope.conf" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1; then
    no 'wrapper Gamescope accetta una modalità fuori limite'
else invalid_rc=$?; if [ "$invalid_rc" -eq 78 ]; then ok 'wrapper Gamescope rifiuta modalità fuori limite'; else no "configurazione Gamescope fallisce con codice inatteso $invalid_rc"; fi; fi

steam_dir="$tmp/steam-repair"
mkdir -p "$steam_dir/package" "$steam_dir/appcache"
printf abc > "$steam_dir/appcache/test.bin"
printf 'appcache/test.bin,9;0;0\n' > "$steam_dir/package/steam_client_test.installed"
if "$ROOT/modules/gamescope/files/ps5-steam-verify-repair" "$steam_dir" >/dev/null 2>&1 && \
   [ ! -e "$steam_dir/package/steam_client_test.installed" ] && [ -f "$steam_dir/appcache/test.bin" ]; then
    ok 'verifica Steam invalida solo il marker non integro e preserva i dati'
else no 'riparazione Steam tocca dati o non rileva corruzione'; fi

printf '%s test superati, %s falliti\n' "$pass" "$fail"
(( fail == 0 ))
