#!/usr/bin/env bash
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd); pass=0; fail=0; skip=0
ok(){ echo "PASS: $1"; pass=$((pass+1)); }
no(){ echo "FAIL: $1" >&2; fail=$((fail+1)); }
if "$ROOT/tests/boot-cleanup-tests.sh"; then ok 'suite boot-cleanup completata'; else no 'suite boot-cleanup fallita'; fi
if "$ROOT/tests/vram-module-tests.sh"; then ok 'suite modulo VRAM completata'; else no 'suite modulo VRAM fallita'; fi
if CORE_TEST_MODE=1 "$ROOT/tests/graphics-modules-tests.sh"; then ok 'suite moduli grafici completata'; else no 'suite moduli grafici fallita'; fi
if python3 "$ROOT/tests/kde-display-mode-tests.py"; then ok 'suite rilevamento modalità KDE completata'; else no 'suite rilevamento modalità KDE fallita'; fi
if python3 "$ROOT/tests/gamescope-display-mode-tests.py"; then ok 'suite rilevamento modalità Gamescope completata'; else no 'suite rilevamento modalità Gamescope fallita'; fi
edid_rc=0; "$ROOT/tests/gamescope-edid-mode-selection-tests.sh" || edid_rc=$?
case "$edid_rc" in 0) ok 'suite selezione DTD EDID Gamescope completata';; 77) echo 'SKIP: suite selezione DTD EDID Gamescope non eseguita'; skip=$((skip+1));; *) no 'suite selezione DTD EDID Gamescope fallita';; esac
if "$ROOT/tests/gamescope-package-tests.sh"; then ok 'suite lifecycle package Gamescope completata'; else no 'suite lifecycle package Gamescope fallita'; fi
if python3 "$ROOT/tests/gamescope-steam-verify-repair-tests.py"; then ok 'suite verifica manifesti Steam completata'; else no 'suite verifica manifesti Steam fallita'; fi
printf '%s\n' "$pass test superati, $fail falliti, $skip saltati"; [ "$fail" -eq 0 ]
