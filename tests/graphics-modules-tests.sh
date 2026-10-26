#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d /tmp/ps5-graphics-modules.XXXXXX)
trap 'rm -rf -- "$tmp"' EXIT
pass=0 fail=0
ok() { printf 'PASS: %s\n' "$1"; pass=$((pass + 1)); }
no() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail + 1)); }
assert() { if "$@"; then return 0; else return 1; fi; }
CLI="$ROOT/bin/ps5-cachyos-tools"
COMMON="$ROOT/modules/session/files/session-common.sh"
SELECT="$ROOT/modules/session/files/steamos-session-select"
SUPERVISOR="$ROOT/modules/session/files/session-supervisor"
export CORE_TEST_MODE=1

fixture() {
    local root=$1
    mkdir -p "$root/etc/profile.d" "$root/usr/bin" "$root/home/steam/.config" "$root/usr/share/xdg-desktop-portal"
    printf 'ID=linux\nNAME=PS5 fixture\n' > "$root/etc/os-release"
    printf 'root:x:0:0:root:/root:/bin/bash\nsteam:x:1000:1000:Steam User:/home/steam:/bin/bash\n' > "$root/etc/passwd"
    printf 'root:x:0:\nsteam:x:1000:\nrender:x:995:\nvideo:x:27:steam\nseat:x:996:\ninput:x:97:\n' > "$root/etc/group"
}

root="$tmp/root"
fixture "$root"
printf 'old profile\n' > "$root/etc/profile.d/ps5-tty-session.sh"
printf 'old selector\n' > "$root/usr/bin/steamos-session-select"
printf '[preferred]\ndefault=kde\n' > "$root/usr/share/xdg-desktop-portal/gamescope-portals.conf"
if "$CLI" install --root "$root" --module session > "$tmp/install.log" 2>&1; then ok 'installazione Session seleziona KDE e Gamescope come dipendenze'; else cat "$tmp/install.log" >&2; no 'installazione grafica selettiva'; fi
if grep -qx 'gamescope' <(sed -n 's/^DEFAULT_SESSION=//p' "$root/home/steam/.config/ps5-cachyos-tools/session.conf") && \
   [ ! -e "$root/usr/lib/ps5-cachyos-tools/modules/fan/module.conf" ] && [ ! -e "$root/usr/lib/ps5-cachyos-tools/modules/boot-cleanup/module.conf" ]; then
    ok 'prima installazione imposta Gamescope e non tocca gli altri moduli'
else no 'default Gamescope o isolamento moduli errato'; fi
if "$CLI" check --root "$root" > "$tmp/check.log" 2>&1; then ok 'check di KDE, Gamescope e Session'; else cat "$tmp/check.log" >&2; no 'check moduli grafici'; fi
if grep -q 'steam' "$root/etc/group" && ! grep -q ',steam,steam' "$root/etc/group"; then ok 'gruppi grafici aggiunti senza duplicati'; else no 'gruppi grafici duplicati o assenti'; fi
if [ -x "$root/usr/local/libexec/ps5-cachyos-tools/gamescope-session" ] && \
   [ -x "$root/usr/local/bin/ps5-cachyos-tools-video-diag" ] && \
   [ -x "$root/usr/local/bin/ps5-cachyos-tools-steam-verify-repair" ]; then ok 'wrapper DRM e utility Gamescope installate'; else no 'utility Gamescope incomplete'; fi

# Reinstall must preserve choices and settings made by the user.
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=\n' > "$root/home/steam/.config/ps5-cachyos-tools/session.conf"
printf 'PS5_OUTPUT_WIDTH=1280\n' > "$root/etc/ps5-cachyos-tools/gamescope.conf"
if "$CLI" install --root "$root" --module session > "$tmp/reinstall.log" 2>&1 && \
   grep -qx 'DEFAULT_SESSION=desktop' "$root/home/steam/.config/ps5-cachyos-tools/session.conf" && \
   grep -qx 'PS5_OUTPUT_WIDTH=1280' "$root/etc/ps5-cachyos-tools/gamescope.conf"; then
    ok 'reinstallazione idempotente preserva le configurazioni'
else cat "$tmp/reinstall.log" >&2; no 'reinstallazione ha sovrascritto configurazioni'; fi

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
   grep -q '^video:x:27:steam$' "$root/etc/group" && ! grep -q '^render:x:995:steam$' "$root/etc/group"; then
    ok 'rimozione KDE toglie solo i gruppi aggiunti e preserva membership originale'
else cat "$tmp/remove-kde.log" >&2; no 'rimozione gruppi KDE errata'; fi

# A clean installation defaults to Gamescope; a recognized legacy choice is migrated.
legacy_root="$tmp/legacy-root"
fixture "$legacy_root"
printf 'desktop\n' > "$legacy_root/home/steam/.config/ps5-next-session"
if "$CLI" install --root "$legacy_root" --module session >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=desktop' "$legacy_root/home/steam/.config/ps5-cachyos-tools/session.conf"; then
    ok 'migrazione conserva la preferenza selezionata dal modulo legacy'
else no 'preferenza legacy non migrata'; fi

# Selector keeps persistent and one-shot preferences separate and rejects invalid input.
fakebin="$tmp/fakebin"
mkdir -p "$fakebin"
cat > "$fakebin/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "${PS5_COMMAND_TRACE:-/dev/null}"
[[ ${1:-} != is-system-running ]] || { echo running; exit 0; }
exit 0
EOF
for command in pgrep pkill loginctl; do
    cat > "$fakebin/$command" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >> "${PS5_COMMAND_TRACE:-/dev/null}"
exit 1
EOF
done
chmod 0755 "$fakebin"/*
session_config="$tmp/selector/session.conf"
session_runtime="$tmp/selector/run"
mkdir -p "${session_config%/*}"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$session_config"
if PS5_SESSION_CONFIG="$session_config" PS5_SESSION_RUNTIME="$session_runtime" PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" --once desktop >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$session_config" && grep -qx 'NEXT_SESSION=desktop' "$session_config"; then
    ok 'switch one-shot non modifica il default persistente'
else no 'switch one-shot sovrascrive il default'; fi
if PS5_SESSION_CONFIG="$session_config" PS5_SESSION_RUNTIME="$session_runtime" PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" --default plasma >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=desktop' "$session_config" && grep -qx 'NEXT_SESSION=desktop' "$session_config"; then
    ok 'alias plasma resta compatibile e seleziona il default KDE'
else no 'alias sessione legacy non rispettato'; fi
command_trace="$tmp/kde-to-gamescope.commands"
if XDG_CURRENT_DESKTOP=KDE XDG_SESSION_ID=42 PS5_COMMAND_TRACE="$command_trace" PS5_SESSION_CONFIG="$session_config" \
   PS5_SESSION_RUNTIME="$session_runtime" PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" --default gamescope >/dev/null 2>&1 && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$session_config" && grep -qx 'NEXT_SESSION=gamescope' "$session_config"; then
    if grep -q 'systemctl --user stop plasma-workspace-wayland.target' "$command_trace" && \
       grep -q 'pkill -TERM .* -x plasmashell' "$command_trace" && \
       grep -q 'pkill -TERM .* -x kwin_wayland' "$command_trace" && \
       grep -q 'loginctl terminate-session 42' "$command_trace"; then
        ok 'switch persistente KDE→Gamescope aggiorna preferenza e chiude Plasma/sessione corrente'
    else no 'switch KDE→Gamescope non arresta Plasma e sessione corrente'; fi
else no 'switch persistente da KDE a Gamescope non applicato'; fi
if PS5_SESSION_CONFIG="$session_config" PS5_SESSION_RUNTIME="$session_runtime" PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" invalid >/dev/null 2>&1; then no 'selettore accetta un target invalido'; else ok 'selettore rifiuta target non supportato'; fi

plasma="$tmp/startplasma-wayland"
cat > "$plasma" <<'EOF'
#!/usr/bin/env bash
printf 'plasma\n' >> "$PS5_TRACE"
exit "${PLASMA_RC:-0}"
EOF
gamescope_mock="$tmp/gamescope-session"
cat > "$gamescope_mock" <<'EOF'
#!/usr/bin/env bash
printf 'gamescope\n' >> "$PS5_TRACE"
if [[ ${FAKE_GAMESCOPE_WAIT:-0} == 1 ]]; then sleep 30; fi
exit "${FAKE_GAMESCOPE_RC:-0}"
EOF
chmod 0755 "$plasma" "$gamescope_mock"

run_supervisor() {
    local config=$1 trace=$2 home=$3
    PS5_SESSION_CONFIG="$config" PS5_SESSION_RUNTIME="$home/run" PS5_SESSION_COMMON="$COMMON" \
      PS5_SESSION_LOG="$home/session.log" PS5_FALLBACK_LOG="$home/fallback.log" PS5_ALERT_FILE="$home/alert.txt" \
      PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$trace" HOME="$home" \
      PS5_FORCE_TTY1=1 PATH="$fakebin:$PATH" "$SUPERVISOR"
}

startup="$tmp/startup"
mkdir -p "$startup/home" "$startup/run"
printf 'DEFAULT_SESSION=desktop\nNEXT_SESSION=\n' > "$startup/session.conf"
if run_supervisor "$startup/session.conf" "$startup/trace" "$startup/home" >/dev/null 2>&1 && \
   grep -qx plasma "$startup/trace" && ! grep -q gamescope "$startup/trace"; then
    ok 'preferenza KDE avvia Plasma direttamente'
else no 'default KDE non applicato'; fi

drm_root="$tmp/drm"
mkdir -p "$drm_root/card0-DP-1"
printf 'connected\n' > "$drm_root/card0-DP-1/status"
printf '1920x1080\n' > "$drm_root/card0-DP-1/modes"
touch "$tmp/card0"

timeout_case="$tmp/timeout"
mkdir -p "$timeout_case/home" "$timeout_case/drm"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$timeout_case/session.conf"
if PS5_SESSION_CONFIG="$timeout_case/session.conf" PS5_SESSION_RUNTIME="$timeout_case/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$timeout_case/home/session.log" PS5_FALLBACK_LOG="$timeout_case/home/fallback.log" PS5_ALERT_FILE="$timeout_case/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$timeout_case/trace" HOME="$timeout_case/home" \
   PS5_FORCE_TTY1=1 PS5_DRM_SYSFS_ROOT="$timeout_case/drm" PS5_DRM_DEVICE="$timeout_case/no-card" PS5_SESSION_DRM_READY_TIMEOUT_SEC=1 \
   PS5_SESSION_DRM_POLL_INTERVAL_SEC=0.1 PS5_SESSION_DRM_STABLE_SAMPLES=1 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 && \
   grep -qx plasma "$timeout_case/trace" && grep -q 'DRM non pronto' "$timeout_case/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$timeout_case/session.conf"; then
    ok 'timeout DRM avvia KDE senza sovrascrivere il default'
else no 'fallback timeout DRM'; fi

failure="$tmp/failure"
mkdir -p "$failure/home" "$failure/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$failure/session.conf"
if PS5_SESSION_CONFIG="$failure/session.conf" PS5_SESSION_RUNTIME="$failure/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$failure/home/session.log" PS5_FALLBACK_LOG="$failure/home/fallback.log" PS5_ALERT_FILE="$failure/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$failure/trace" HOME="$failure/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 FAKE_GAMESCOPE_RC=42 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 && \
   printf 'gamescope\nplasma\n' > "$failure/expected" && cmp -s "$failure/expected" "$failure/trace" && grep -q 'exit=42' "$failure/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$failure/session.conf" && [ -f "$failure/home/alert.txt" ]; then
    ok 'crash Gamescope pulisce la sessione, registra causa e avvia KDE'
else no 'fallback crash Gamescope'; fi

missing="$tmp/missing-wrapper"
mkdir -p "$missing/home" "$missing/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$missing/session.conf"
if PS5_SESSION_CONFIG="$missing/session.conf" PS5_SESSION_RUNTIME="$missing/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$missing/home/session.log" PS5_FALLBACK_LOG="$missing/home/fallback.log" PS5_ALERT_FILE="$missing/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$missing/not-installed" PS5_TRACE="$missing/trace" HOME="$missing/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 && \
   grep -qx plasma "$missing/trace" && grep -q 'wrapper assente' "$missing/home/fallback.log" && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$missing/session.conf"; then
    ok 'wrapper Gamescope assente avvia KDE e conserva il default'
else no 'wrapper Gamescope assente non attiva il fallback'; fi

normal="$tmp/normal-exit"
mkdir -p "$normal/home" "$normal/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$normal/session.conf"
if PS5_SESSION_CONFIG="$normal/session.conf" PS5_SESSION_RUNTIME="$normal/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$normal/home/session.log" PS5_FALLBACK_LOG="$normal/home/fallback.log" PS5_ALERT_FILE="$normal/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$normal/trace" HOME="$normal/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 FAKE_GAMESCOPE_RC=0 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 && \
   printf 'gamescope\nplasma\n' > "$normal/expected" && cmp -s "$normal/expected" "$normal/trace" && \
   { [ ! -e "$normal/home/fallback.log" ] || ! grep -q 'Gamescope failure' "$normal/home/fallback.log"; } && \
   grep -qx 'DEFAULT_SESSION=gamescope' "$normal/session.conf"; then
    ok 'uscita normale avvia KDE senza falso log di errore o cambio default'
else no 'uscita normale Gamescope classificata male'; fi

switch="$tmp/manual-switch"
mkdir -p "$switch/home" "$switch/run" "$switch/drm/card0-HDMI-A-1"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$switch/session.conf"
printf 'connected\n' > "$switch/drm/card0-HDMI-A-1/status"
printf '1920x1080\n' > "$switch/drm/card0-HDMI-A-1/modes"
env PS5_SESSION_CONFIG="$switch/session.conf" PS5_SESSION_RUNTIME="$switch/run" PS5_SESSION_COMMON="$COMMON" \
  PS5_SESSION_LOG="$switch/home/session.log" PS5_FALLBACK_LOG="$switch/home/fallback.log" PS5_ALERT_FILE="$switch/home/alert.txt" \
  PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$gamescope_mock" PS5_TRACE="$switch/trace" HOME="$switch/home" \
  PS5_FORCE_TTY1=1 PS5_DRM_SYSFS_ROOT="$switch/drm" PS5_DRM_DEVICE="$tmp/card0" PS5_SESSION_DRM_POLL_INTERVAL_SEC=0.1 \
  PS5_SESSION_DRM_STABLE_SAMPLES=1 FAKE_GAMESCOPE_WAIT=1 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 &
supervisor_pid=$!
for _ in $(seq 1 50); do [ -s "$switch/run/ps5-cachyos-tools/gamescope.pgid" ] && break; sleep 0.1; done
if [ -s "$switch/run/ps5-cachyos-tools/gamescope.pgid" ] && \
   PS5_SESSION_CONFIG="$switch/session.conf" PS5_SESSION_RUNTIME="$switch/run" PS5_SESSION_COMMON="$COMMON" PATH="$fakebin:$PATH" "$SELECT" --once desktop >/dev/null 2>&1; then
    wait "$supervisor_pid" || true
    if grep -qx plasma "$switch/trace" && grep -qx 'DEFAULT_SESSION=gamescope' "$switch/session.conf" && \
       grep -qx 'NEXT_SESSION=' "$switch/session.conf" && \
       { [ ! -e "$switch/home/fallback.log" ] || ! grep -q 'Gamescope failure' "$switch/home/fallback.log"; }; then
        ok 'switch Gamescope verso KDE è volontario e conserva il default';
    else no 'switch Gamescope/KDE non conserva lo stato'; fi
else
    kill "$supervisor_pid" 2>/dev/null || true; wait "$supervisor_pid" 2>/dev/null || true; no 'switch manuale non ha terminato Gamescope';
fi

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
while [[ $# -gt 0 && $1 != -- ]]; do shift; done
[[ $# -gt 0 ]] || exit 99
shift
"$@"
EOF
chmod 0755 "$tmp/mockbin/steam" "$tmp/mockbin/gamescope"
printf 'PS5_OUTPUT_WIDTH=1280\nPS5_REFRESH_RATE=60\n' > "$tmp/gamescope.conf"
if HOME="$wrapper_home" PS5_STEAM_DIR="$wrapper_home/steam" PS5_GAMESCOPE_LOG="$tmp/wrapper.log" \
   PS5_GAMESCOPE_CONFIG="$tmp/gamescope.conf" PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" \
   PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" PS5_STEAM_ARGS="$tmp/steam-args" PS5_GAMESCOPE_ARGS="$tmp/gs-args" \
   "$ROOT/modules/gamescope/files/gamescope-session-ps5" >/dev/null 2>&1 && \
   grep -qx -- '-W' "$tmp/gs-args" && grep -qx '1280' "$tmp/gs-args" && grep -qx '1080' "$tmp/gs-args" && \
   grep -qx -- '-gamepadui -steamos' "$tmp/steam-args"; then
    ok 'wrapper Gamescope rileva DRM e costruisce gli argomenti con override validato'
else no 'wrapper Gamescope non applica override/DRM'; fi

steam_crash="$tmp/steam-crash"
mkdir -p "$steam_crash/home/steam/logs" "$steam_crash/run"
printf 'DEFAULT_SESSION=gamescope\nNEXT_SESSION=\n' > "$steam_crash/session.conf"
if PS5_SESSION_CONFIG="$steam_crash/session.conf" PS5_SESSION_RUNTIME="$steam_crash/run" PS5_SESSION_COMMON="$COMMON" \
   PS5_SESSION_LOG="$steam_crash/home/session.log" PS5_FALLBACK_LOG="$steam_crash/home/fallback.log" PS5_ALERT_FILE="$steam_crash/home/alert.txt" \
   PS5_PLASMA_BIN="$plasma" PS5_GAMESCOPE_BIN="$ROOT/modules/gamescope/files/gamescope-session-ps5" PS5_TRACE="$steam_crash/trace" HOME="$steam_crash/home" \
   PS5_FORCE_TTY1=1 PS5_SESSION_SKIP_DRM_WAIT=1 PS5_STEAM_DIR="$steam_crash/home/steam" \
   PS5_DRM_SYSFS_ROOT="$drm_root" PS5_DRM_DEVICE="$tmp/card0" PS5_STEAM_EXEC="$tmp/mockbin/steam" PS5_GAMESCOPE_EXEC="$tmp/mockbin/gamescope" \
   PS5_STEAM_ARGS="$steam_crash/steam-args" PS5_GAMESCOPE_ARGS="$steam_crash/gamescope-args" PS5_GAMESCOPE_CONFIG="$tmp/gamescope.conf" \
   PS5_GAMESCOPE_LOG="$steam_crash/home/gamescope.log" FAKE_STEAM_CRASH_MARKER=1 PATH="$fakebin:$PATH" "$SUPERVISOR" >/dev/null 2>&1 && \
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
