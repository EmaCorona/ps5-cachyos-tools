#!/usr/bin/env bash
set -u

# On-demand recovery helper for Steam's private crash-dump directory.
# Usage: recover.sh [ROOT]; ROOT defaults to / and is used by tests/offline checks.

root=${1:-/}
[ -d "$root" ] && [ ! -L "$root" ] || { echo 'root non valida' >&2; exit 1; }
[ -d "$root/etc" ] && [ ! -L "$root/etc" ] || { echo 'directory etc non valida' >&2; exit 1; }
[ -d "$root/tmp" ] && [ ! -L "$root/tmp" ] || { echo 'directory tmp non valida' >&2; exit 1; }
[ -f "$root/etc/passwd" ] && [ ! -L "$root/etc/passwd" ] || { echo 'passwd target non regolare: nessuna modifica eseguita' >&2; exit 1; }

if [ "$root" = / ]; then
    [ "$(id -un)" = steam ] || { echo 'eseguire come utente steam, senza sudo' >&2; exit 1; }
fi

steam_uid=$(awk -F: '$1 == "steam" { print $3; count++ } END { if (count != 1) exit 1 }' "$root/etc/passwd") || {
    echo 'utente steam assente o duplicato nel passwd del target' >&2
    exit 1
}
[[ "$steam_uid" =~ ^[0-9]+$ ]] || { echo 'UID steam non valido' >&2; exit 1; }
[ "$(id -u)" = "$steam_uid" ] || { echo 'UID corrente diverso da steam: nessuna modifica eseguita' >&2; exit 1; }
command -v pgrep >/dev/null 2>&1 || { echo 'pgrep non disponibile: nessuna modifica eseguita' >&2; exit 1; }

steam_active=0
for process in steam steamwebhelper; do
    if pgrep -u "$steam_uid" -x "$process" >/dev/null 2>&1; then
        steam_active=1
        break
    else
        pgrep_status=$?
        [ "$pgrep_status" -eq 1 ] || {
            echo "pgrep non ha verificato '$process' (codice $pgrep_status): nessuna modifica eseguita" >&2
            exit 1
        }
    fi
done

if [ "$steam_active" -eq 1 ]; then
    printf 'action=NO_ACTION\nreason=steam-active\n'
    exit 0
fi

dumps="$root/tmp/dumps"
if [ ! -e "$dumps" ] && [ ! -L "$dumps" ]; then
    mkdir -m 700 -- "$dumps" || { echo "impossibile creare $dumps" >&2; exit 1; }
    printf 'action=CREATED\npath=/tmp/dumps\nmode=700\n'
    exit 0
fi
[ -d "$dumps" ] && [ ! -L "$dumps" ] || { echo "$dumps non è una directory regolare: nessuna modifica eseguita" >&2; exit 1; }
[ "$(stat -c '%u' -- "$dumps")" = "$steam_uid" ] || { echo "$dumps non appartiene a steam: nessuna modifica eseguita" >&2; exit 1; }

mode=$(stat -c '%a' -- "$dumps") || { echo "impossibile leggere i permessi di $dumps" >&2; exit 1; }
if [ "$mode" = 700 ] || [ "$mode" = 1700 ]; then
    printf 'action=NO_ACTION\nreason=permissions-ok\nmode=%s\n' "$mode"
    exit 0
fi

chmod 700 -- "$dumps" || { echo "impossibile correggere i permessi di $dumps" >&2; exit 1; }
printf 'action=PERMISSIONS_FIXED\npath=/tmp/dumps\nprevious_mode=%s\nmode=700\n' "$mode"
