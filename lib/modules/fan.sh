#!/usr/bin/env bash
set -u

module_fan_install_copy() {
    local source=$1 target=$2 mode=$3 source_id target_id
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    if [ -f "$target" ] && [ ! -L "$target" ]; then
        source_id=$(stat -c '%d:%i' -- "$source" 2>/dev/null) || return 1
        target_id=$(stat -c '%d:%i' -- "$target" 2>/dev/null) || return 1
        if [ "$source_id" = "$target_id" ]; then chmod "$mode" -- "$target"; return $?; fi
    fi
    if [ -f "$target" ] && cmp -s -- "$source" "$target"; then chmod "$mode" -- "$target"; return; fi
    [ ! -L "$target" ] || return 1
    install -m "$mode" -- "$source" "$target"
}

module_fan_info() { echo "PS5 fan controller: 15 zones, Low/Balanced/High, fail-safe target_temp"; }
module_fan_owned_path() { case "$1" in /usr/lib/ps5-cachyos-tools/fan.sh|/usr/local/bin/ps5-fan|/usr/local/bin/ps5-fan-daemon|/usr/local/bin/ps5-temp|/etc/systemd/system/ps5-fan-daemon.service|/etc/udev/rules.d/99-ps5-fan.rules|/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service) return 0;; *) return 1;; esac; }
module_fan_manifest_path() { echo "$1/etc/ps5-fan/.ps5-cachyos-tools.manifest"; }
module_fan_manifest_text() { printf '%s\n' /usr/lib/ps5-cachyos-tools/fan.sh /usr/local/bin/ps5-fan /usr/local/bin/ps5-fan-daemon /usr/local/bin/ps5-temp /etc/systemd/system/ps5-fan-daemon.service /etc/udev/rules.d/99-ps5-fan.rules /etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service; }
module_fan_all_paths() { module_fan_manifest_text; printf '%s\n' /etc/ps5-fan/.ps5-cachyos-tools.manifest; }

module_fan_validate_write_path() {
    local root=$1 path=$2 full=$1$2 part current target
    [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    [ "$root" = / ] || { [ -d "$root" ] && [ ! -L "$root" ] || return 1; }
    local root_current=/ root_part
    IFS=/ read -ra root_parts_check <<< "${root#/}"
    for root_part in "${root_parts_check[@]}"; do
        [ -n "$root_part" ] || continue
        root_current="${root_current%/}/$root_part"
        [ ! -L "$root_current" ] || return 1
    done
    current=${root%/}; [ -n "$current" ] || current=/; target="$full"
    [ "$root" = / ] && target="$path"
    IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ "$current" = "$target" ] && break
        [ ! -L "$current" ] || { echo "fan: antenato symlink non autorizzato: $path" >&2; return 1; }
    done
    if [ -L "$full" ]; then
        case "$path:$(readlink -- "$full")" in
            /etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service:/etc/systemd/system/ps5-fan-daemon.service) : ;;
            *) echo "fan: artefatto finale symlink non autorizzato: $path" >&2; return 1;;
        esac
    fi
}

module_fan_validate_write_set() {
    local root=$1 path
    for path in /etc/ps5-fan /etc/ps5-fan/profiles /usr/lib/ps5-cachyos-tools /usr/local/bin /etc/systemd/system /etc/systemd/system/multi-user.target.wants /etc/udev/rules.d; do
        module_fan_validate_write_path "$root" "$path" || return 1
    done
    for path in /etc/ps5-fan/.ps5-cachyos-tools.manifest /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf /usr/lib/ps5-cachyos-tools/fan.sh /usr/local/bin/ps5-fan /usr/local/bin/ps5-fan-daemon /usr/local/bin/ps5-temp /etc/systemd/system/ps5-fan-daemon.service /etc/udev/rules.d/99-ps5-fan.rules /etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service; do
        module_fan_validate_write_path "$root" "$path" || return 1
    done
}

module_fan_validate_artifact() {
    local root=$1 path=$2 full mode
    full=$root$path
    case "$path" in
        /etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service)
            [ -L "$full" ] && [ "$(readlink "$full")" = /etc/systemd/system/ps5-fan-daemon.service ] || { echo "fan: symlink non valido: $path" >&2; return 1; } ;;
        *)
            [ -f "$full" ] && [ ! -L "$full" ] || { echo "fan: artefatto mancante o tipo errato: $path" >&2; return 1; }
            mode=$(stat -c '%a' "$full" 2>/dev/null) || return 1
            case "$path" in /usr/lib/ps5-cachyos-tools/*|/usr/local/bin/*) [ "$mode" = 755 ];; *) [ "$mode" = 644 ];; esac || { echo "fan: permessi non validi: $path ($mode)" >&2; return 1; } ;;
    esac
}

module_fan_validate_manifest() {
    local root=$1 manifest path line=0 expected
    manifest=$(module_fan_manifest_path "$root")
    [ -f "$manifest" ] && [ ! -L "$manifest" ] && [ -r "$manifest" ] || { echo "fan: manifest assente o non regolare" >&2; return 1; }
    [ "$(wc -l < "$manifest")" -eq 7 ] || { echo "fan: manifest troncato o con righe extra" >&2; return 1; }
    [ "$(stat -c '%a' "$manifest" 2>/dev/null)" = 644 ] || { echo "fan: permessi manifest non validi" >&2; return 1; }
    declare -A seen=()
    while IFS= read -r path; do
        line=$((line + 1)); expected=$(module_fan_manifest_text | sed -n "${line}p")
        [ -n "$path" ] && [ "$path" = "$expected" ] || { echo "fan: contenuto manifest non valido alla riga $line" >&2; return 1; }
        [[ "$path" == /* && "$path" != *$'\r'* && "$path" != *'//' && "$path" != *'/../'* && "$path" != */.. && "$path" != *'/./'* ]] || { echo "fan: percorso manifest non autorizzato: $path" >&2; return 1; }
        module_fan_owned_path "$path" || { echo "fan: artefatto non posseduto: $path" >&2; return 1; }
        [ -z "${seen[$path]+x}" ] || { echo "fan: duplicato nel manifest: $path" >&2; return 1; }; seen[$path]=1
        module_fan_validate_artifact "$root" "$path" || return 1
    done < "$manifest"
}

module_fan_check_removal_permissions() {
    local root=$1 path parent
    [ "$root" != / ] || [ "$(id -u)" -eq 0 ] || { echo "fan: rimozione live richiede root" >&2; return 1; }
    while IFS= read -r path; do parent=$root$(dirname "$path"); [ -d "$parent" ] && [ -w "$parent" ] || { echo "fan: directory non scrivibile: $parent" >&2; return 1; }; done < <(module_fan_all_paths)
    [ -w "$(dirname "$(module_fan_manifest_path "$root")")" ] || { echo "fan: manifest non rimovibile" >&2; return 1; }
}

module_fan_snapshot() {
    local root=$1 backup=$2 path source backup_path
    backup_path=${backup#"$root"}
    [[ "$backup" != "$backup_path" && "$backup_path" = /var/lib/ps5-cachyos-tools/backups/* ]] || { echo 'fan: percorso backup non autorizzato' >&2; return 1; }
    module_fan_validate_write_path "$root" "$backup_path" || return 1
    mkdir -p "$backup" || return 1
    while IFS= read -r path; do
        source=$root$path
        if [ -e "$source" ] || [ -L "$source" ]; then
            mkdir -p "$backup$(dirname "$path")" || return 1
            cp -a -- "$source" "$backup$path" || { echo "fan: backup fallito: $path" >&2; return 1; }
            printf '%s\n' "$path" >> "$backup/.present" || return 1
        fi
    done < <(module_fan_all_paths)
    for path in /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf; do
        source=$root$path
        if [ -e "$source" ] || [ -L "$source" ]; then mkdir -p "$backup$(dirname "$path")" && cp -a -- "$source" "$backup$path" || return 1; fi
    done
}

module_fan_restore() {
    local root=$1 backup=$2 path failed=0
    [ -n "$backup" ] && [ -d "$backup" ] || { echo "fan: rollback rifiutato: backup non creato" >&2; return 1; }
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        module_fan_validate_write_path "$root" "$path" || { echo "fan: rollback rifiutato per topologia non sicura: $path" >&2; failed=1; continue; }
        if [ -e "$backup$path" ] || [ -L "$backup$path" ]; then
            rm -rf -- "$root$path" || { echo "fan: rollback: impossibile rimuovere $path" >&2; failed=1; continue; }
            mkdir -p "$root$(dirname "$path")" && cp -a -- "$backup$path" "$root$path" || { echo "fan: rollback fallito: $path" >&2; failed=1; }
        else
            rm -rf -- "$root$path" || { echo "fan: rollback: impossibile rimuovere il nuovo artefatto $path" >&2; failed=1; }
        fi
    done < <(module_fan_all_paths)
    return "$failed"
}

module_fan_restore_extra() {
    local root=$1 backup=$2 path
    for path in /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf; do
        module_fan_validate_write_path "$root" "$path" || return 1
        if [ -e "$backup$path" ] || [ -L "$backup$path" ]; then
            rm -rf -- "$root$path" && mkdir -p "$root$(dirname "$path")" && cp -a -- "$backup$path" "$root$path" || return 1
        else
            rm -f -- "$root$path" || return 1
        fi
    done
}

module_fan_remove_user_files() {
    local root=$1 keep=$2 path
    [ "$keep" = 1 ] && return 0
    for path in fan.conf state profiles/low.conf profiles/balanced.conf profiles/high.conf; do rm -f -- "$root/etc/ps5-fan/$path" || return 1; done
}

module_fan_restore_service() {
    local root=$1 was_active=$2 was_enabled=$3 result=0 actual
    [ "$root" = / ] && command -v systemctl >/dev/null 2>&1 || { module_fan_rollback_result=ROLLBACK_COMPLETED; return 0; }
    systemctl daemon-reload || result=1
    if [ "$was_enabled" -eq 1 ]; then systemctl enable ps5-fan-daemon.service || result=1; else systemctl disable ps5-fan-daemon.service || result=1; fi
    if [ "$was_active" -eq 1 ]; then systemctl restart ps5-fan-daemon.service || result=1; else systemctl stop ps5-fan-daemon.service || result=1; fi
    actual=0; systemctl is-enabled --quiet ps5-fan-daemon.service 2>/dev/null && actual=1
    [ "$actual" -eq "$was_enabled" ] || result=1
    actual=0; systemctl is-active --quiet ps5-fan-daemon.service 2>/dev/null && actual=1
    [ "$actual" -eq "$was_active" ] || result=1
    if [ "$result" -eq 0 ]; then module_fan_rollback_result=ROLLBACK_COMPLETED; echo 'fan: ROLLBACK_COMPLETED (filesystem e systemd)' >&2; else module_fan_rollback_result=ROLLBACK_FILES_RESTORED_SERVICE_FAILED; echo 'fan: ROLLBACK_FILES_RESTORED_SERVICE_FAILED' >&2; fi
    return "$result"
}

module_fan_runtime_changed() {
    local root=$1 repo_dir=$2 path source full mode expected_mode runtime_file runtime_path
    runtime_file=${CORE_RUNTIME_CHANGED_FILE:-}
    if [ -n "$runtime_file" ]; then
        if [ "$root" = / ]; then runtime_path=$runtime_file; else case "$runtime_file" in "$root"/*) runtime_path=/${runtime_file#"$root"};; *) return 1;; esac; fi
        module_fan_validate_write_path "$root" "$runtime_path" || return 1
    fi
    module_fan_mark_runtime_changed() { [ -z "$runtime_file" ] || { module_fan_validate_write_path "$root" "$runtime_path" || return 1; printf '1\n' > "$runtime_file"; }; }
    for path in /usr/lib/ps5-cachyos-tools/fan.sh /usr/local/bin/ps5-fan /usr/local/bin/ps5-fan-daemon /usr/local/bin/ps5-temp /etc/systemd/system/ps5-fan-daemon.service /etc/udev/rules.d/99-ps5-fan.rules; do
        case "$path" in /usr/lib/ps5-cachyos-tools/fan.sh) source="$repo_dir/lib/modules/fan.sh";; /usr/local/bin/*) source="$repo_dir/bin/${path##*/}";; /etc/systemd/system/*) source="$repo_dir/systemd/${path##*/}";; /etc/udev/*) source="$repo_dir/systemd/${path##*/}";; esac
        full=$root$path; expected_mode=644; [[ "$path" == /usr/lib/* || "$path" == /usr/local/bin/* ]] && expected_mode=755
        if ! [ -f "$full" ] || [ -L "$full" ] || ! cmp -s "$source" "$full"; then
            module_fan_mark_runtime_changed || return 1
            return 0
        fi
        mode=$(stat -c '%a' "$full" 2>/dev/null) || return 0
        if [ "$mode" != "$expected_mode" ]; then
            module_fan_mark_runtime_changed || return 1
            return 0
        fi
    done
    full="$root/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service"
    if ! [ -L "$full" ] || [ "$(readlink "$full" 2>/dev/null)" != /etc/systemd/system/ps5-fan-daemon.service ]; then
        module_fan_mark_runtime_changed || return 1
        return 0
    fi
    return 1
}

module_fan_normalize_uint() {
    local value=${1-} normalized
    value=${value#\"}; value=${value%\"}
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    normalized=${value#${value%%[!0]*}}
    [ -n "$normalized" ] || normalized=0
    [ "${#normalized}" -le 9 ] || return 1
    printf '%s\n' "$normalized"
}

module_fan_health_timeout() {
    local root=$1 requested selected poll raw_override derived profile_file
    [ -r "$root/etc/ps5-fan/state" ] || { echo 'fan: stato profilo assente per health timeout' >&2; return 1; }
    selected=$(<"$root/etc/ps5-fan/state")
    case "$selected" in low|balanced|high) ;; *) echo 'fan: profilo persistente non valido per health timeout' >&2; return 1;; esac
    profile_file="$root/etc/ps5-fan/profiles/$selected.conf"
    [ -r "$profile_file" ] || { echo "fan: profilo assente per health timeout: $selected" >&2; return 1; }
    raw_override=$(awk -F= '$1=="POLL_INTERVAL"{print $2; exit}' "$profile_file" 2>/dev/null || true)
    poll=$(module_fan_normalize_uint "$raw_override") || { echo "fan: POLL_INTERVAL non valido nel profilo $selected" >&2; return 1; }
    [ "$poll" -ge 1 ] && [ "$poll" -le 60 ] || { echo "fan: POLL_INTERVAL fuori range nel profilo $selected" >&2; return 1; }
    if [ "${PS5_FAN_POLL_SEC+x}" = x ]; then
        raw_override=$(module_fan_normalize_uint "$PS5_FAN_POLL_SEC") || { echo 'fan: override polling non valido per health timeout' >&2; return 1; }
        [ "$raw_override" -ge 1 ] && [ "$raw_override" -le 60 ] || { echo 'fan: override polling fuori range per health timeout' >&2; return 1; }
        poll=$raw_override
    fi
    if [ "${PS5_FAN_HEALTH_TIMEOUT+x}" = x ]; then requested=$(module_fan_normalize_uint "$PS5_FAN_HEALTH_TIMEOUT") || return 1; [ "$requested" -ge 1 ] && [ "$requested" -le 300 ] || return 1; else requested=0; fi
    derived=$((poll * 2 + 5)); [ "$requested" -gt "$derived" ] 2>/dev/null && derived=$requested
    [ "$derived" -gt 300 ] && derived=300
    printf '%s\n' "$derived"
}

module_fan_wait_ready() {
    local root=$1 timeout=${2:-30} previous_pid=${3:-0} previous_cycles=${4:-0} previous_instance=${5:-} restarted=${6:-0} state=/run/ps5-fan/runtime.state deadline pid cycles updated_at instance_id profile now
    [ "$root" = / ] || return 0
    command -v systemctl >/dev/null 2>&1 || return 1
    deadline=$(( $(date +%s) + timeout )); state=${PS5_FAN_STATE_FILE:-$state}; cycles=0
    while [ "$(date +%s)" -le "$deadline" ]; do
        systemctl is-active --quiet ps5-fan-daemon.service || { sleep 1; continue; }
        pid=$(systemctl show -p MainPID --value ps5-fan-daemon.service 2>/dev/null || true)
        [ "$pid" -gt 0 ] 2>/dev/null && kill -0 "$pid" 2>/dev/null || { sleep 1; continue; }
        cycles=$(awk -F= '$1=="cycles"{print $2}' "$state" 2>/dev/null || true); updated_at=$(awk -F= '$1=="updated_at"{print $2}' "$state" 2>/dev/null || true); instance_id=$(awk -F= '$1=="instance_id"{print $2}' "$state" 2>/dev/null || true)
        now=$(date +%s)
        if [ -r "$state" ] && [ "$cycles" -ge 1 ] 2>/dev/null && [ "$updated_at" -ge "$((now - 300))" ] 2>/dev/null && [ "$updated_at" -le "$now" ] 2>/dev/null && [ -n "$instance_id" ] && [ "$instance_id" != none ] && grep -Eq '^state=(NORMAL|HEATING|EMERGENCY|DEGRADED)$' "$state" && grep -Eq '^profile_applied=(low|balanced|high)$' "$state"; then
            if [ "$restarted" -eq 1 ]; then [ "$previous_pid" -eq 0 ] || [ "$pid" -ne "$previous_pid" ] || { sleep 1; continue; }; [ -z "$previous_instance" ] || [ "$instance_id" != "$previous_instance" ] || { sleep 1; continue; }; else [ "$previous_pid" -eq 0 ] || [ "$pid" -eq "$previous_pid" ] || { sleep 1; continue; }; [ -z "$previous_instance" ] || [ "$instance_id" = "$previous_instance" ] || { sleep 1; continue; }; [ "$cycles" -gt "$previous_cycles" ] 2>/dev/null || { sleep 1; continue; }; fi
            grep -q '^state=DEGRADED$' "$state" && return 2
            return 0
        fi
        sleep 1
    done
    echo 'fan: readiness timeout: servizio attivo senza stato applicativo valido' >&2
    return 1
}

module_fan_remove() {
    local root=${1:-/} keep=${2:-0} manifest backup='' service_was_active=0 service_was_enabled=0 path framework_managed=${CORE_FRAMEWORK_MANAGED:-0}
    [ -d "$root" ] || return 1
    [[ "$root" = /* && "$root" != *'..'* ]] || { echo 'fan: root filesystem non assoluto o non sicuro' >&2; return 1; }
    [ ! -L "$root" ] || { echo 'fan: root filesystem symlink non autorizzato' >&2; return 1; }
    local current=/; IFS=/ read -ra root_parts <<< "${root#/}"
    for part in "${root_parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || { echo "fan: antenato root symlink non autorizzato: $current" >&2; return 1; }
    done
    module_fan_validate_write_set "$root" || return 1
    manifest=$(module_fan_manifest_path "$root")
    module_fan_validate_manifest "$root" || return 1
    module_fan_check_removal_permissions "$root" || return 1
    if [ "$framework_managed" != 1 ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then systemctl is-active --quiet ps5-fan-daemon.service && service_was_active=1 || service_was_active=0; systemctl is-enabled --quiet ps5-fan-daemon.service && service_was_enabled=1 || service_was_enabled=0; fi
    backup="$root/var/lib/ps5-cachyos-tools/backups/uninstall-$(date +%s%N)"
    module_fan_snapshot "$root" "$backup" || { echo "fan: preflight rollback non disponibile" >&2; return 1; }
    if [ "$keep" != 1 ]; then
        for path in /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf; do
            if [ -e "$root$path" ] || [ -L "$root$path" ]; then mkdir -p "$backup$(dirname "$path")" && cp -a "$root$path" "$backup$path" || return 1; fi
        done
    fi
    if [ "$framework_managed" != 1 ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then systemctl disable --now ps5-fan-daemon.service || { echo "fan: arresto/disabilitazione fallita; nessuna rimozione eseguita" >&2; module_fan_restore_service "$root" "$service_was_active" "$service_was_enabled" || true; return 1; }; fi
    while IFS= read -r path; do rm -f -- "$root$path" || { echo "fan: rimozione fallita: $path" >&2; module_fan_restore "$root" "$backup"; [ "$keep" = 1 ] || module_fan_restore_extra "$root" "$backup" || true; [ "$framework_managed" = 1 ] || module_fan_restore_service "$root" "$service_was_active" "$service_was_enabled" || true; echo "fan: rollback incompleto" >&2; return 1; }; done < <(module_fan_all_paths)
    module_fan_remove_user_files "$root" "$keep" || { echo "fan: rimozione configurazione fallita" >&2; module_fan_restore "$root" "$backup"; [ "$keep" = 1 ] || module_fan_restore_extra "$root" "$backup" || true; [ "$framework_managed" = 1 ] || module_fan_restore_service "$root" "$service_was_active" "$service_was_enabled" || true; echo "fan: rollback incompleto" >&2; return 1; }
    rmdir "$root/etc/ps5-fan/profiles" 2>/dev/null || true; rmdir "$root/etc/ps5-fan" 2>/dev/null || true
    if [ "$framework_managed" != 1 ] && [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then systemctl daemon-reload || { echo "fan: daemon-reload fallito dopo rimozione" >&2; module_fan_restore "$root" "$backup" || true; [ "$keep" = 1 ] || module_fan_restore_extra "$root" "$backup" || true; systemctl daemon-reload 2>/dev/null || true; module_fan_restore_service "$root" "$service_was_active" "$service_was_enabled" || true; return 1; }; if systemctl is-active --quiet ps5-fan-daemon.service || systemctl is-enabled --quiet ps5-fan-daemon.service; then echo "fan: servizio ancora active/enabled dopo rimozione" >&2; module_fan_restore "$root" "$backup" || true; [ "$keep" = 1 ] || module_fan_restore_extra "$root" "$backup" || true; systemctl daemon-reload 2>/dev/null || true; module_fan_restore_service "$root" "$service_was_active" "$service_was_enabled" || true; return 1; fi; fi
    echo "fan: disinstallazione completata; file utente non rimossi"
}

module_fan_run() {
    local root=${1:-} part current
    [ -n "$root" ] && [ -d "$root" ] || { echo "fan: root filesystem non trovato" >&2; return 1; }
    [[ "$root" = /* && "$root" != *'..'* ]] || { echo 'fan: root filesystem non assoluto o non sicuro' >&2; return 1; }
    [ ! -L "$root" ] || { echo 'fan: root filesystem symlink non autorizzato' >&2; return 1; }
    current=/; IFS=/ read -ra root_parts <<< "${root#/}"
    for part in "${root_parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || { echo "fan: antenato root symlink non autorizzato: $current" >&2; return 1; }
    done
    module_fan_validate_write_set "$root" || return 1
    local repo_dir
    if [ -n "${CORE_REPO:-}" ] && [ -d "$CORE_REPO/config" ]; then
        repo_dir=$CORE_REPO
    else
        repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
    fi
    local -a managed=(/etc/ps5-fan/.ps5-cachyos-tools.manifest /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf /usr/lib/ps5-cachyos-tools/fan.sh /usr/local/bin/ps5-fan /usr/local/bin/ps5-fan-daemon /usr/local/bin/ps5-temp /etc/systemd/system/ps5-fan-daemon.service /etc/udev/rules.d/99-ps5-fan.rules /etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service)
    local backup_state=BACKUP_NOT_REQUIRED backup_dir='' path profile active_before=0 enabled_before=0 runtime_changed=0 health_result=0 active_pid=0 health_pid=0 health_cycles=0 health_instance='' health_timeout=0 restart_required=0
    if [ "$root" = / ] && command -v systemctl >/dev/null 2>&1; then systemctl is-active --quiet ps5-fan-daemon.service && active_before=1 || active_before=0; systemctl is-enabled --quiet ps5-fan-daemon.service && enabled_before=1 || enabled_before=0; [ "$active_before" -eq 1 ] && active_pid=$(systemctl show -p MainPID --value ps5-fan-daemon.service 2>/dev/null || echo 0); [ -r /run/ps5-fan/runtime.state ] && health_cycles=$(awk -F= '$1=="cycles"{print $2}' /run/ps5-fan/runtime.state 2>/dev/null || echo 0); [ -r /run/ps5-fan/runtime.state ] && health_instance=$(awk -F= '$1=="instance_id"{print $2}' /run/ps5-fan/runtime.state 2>/dev/null || true); fi
    for path in "${managed[@]}"; do if [ -e "$root$path" ] || [ -L "$root$path" ]; then backup_state=BACKUP_CREATED; break; fi; done
    if [ "$backup_state" = BACKUP_CREATED ]; then backup_dir="$root/var/lib/ps5-cachyos-tools/backups/install-$(date +%s%N)"; module_fan_snapshot "$root" "$backup_dir" || { backup_state=BACKUP_FAILED; echo "fan: backup non disponibile, installazione annullata" >&2; return 1; }; fi
    module_fan_runtime_changed "$root" "$repo_dir" && runtime_changed=1 || true
    module_fan_fail() {
        echo "fan: installazione fallita; rollback in corso (backup=$backup_state)" >&2
        module_fan_rollback_result=ROLLBACK_FAILED
        local filesystem_result=0 service_result=0
        if [ "$backup_state" = BACKUP_CREATED ]; then backup_state=ROLLBACK_IN_PROGRESS; module_fan_restore "$root" "$backup_dir" || filesystem_result=1; module_fan_restore_extra "$root" "$backup_dir" || filesystem_result=1; [ "$filesystem_result" -eq 0 ] && backup_state=ROLLBACK_COMPLETED || backup_state=ROLLBACK_FAILED
        else for path in "${managed[@]}" /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf; do rm -rf -- "$root$path" || { filesystem_result=1; echo "fan: rollback nuovo artefatto fallito: $path" >&2; }; done; fi
        [ "${CORE_FRAMEWORK_MANAGED:-0}" = 1 ] || module_fan_restore_service "$root" "$active_before" "$enabled_before" || service_result=1
        if [ "$filesystem_result" -ne 0 ]; then module_fan_rollback_result=ROLLBACK_PARTIAL; elif [ "$service_result" -ne 0 ]; then module_fan_rollback_result=ROLLBACK_FILES_RESTORED_SERVICE_FAILED; else module_fan_rollback_result=ROLLBACK_COMPLETED; fi
        echo "fan: $module_fan_rollback_result" >&2
        return 1
    }
    install -d "$root/usr/lib/ps5-cachyos-tools" "$root/usr/local/bin" "$root/etc/ps5-fan/profiles" "$root/etc/systemd/system" "$root/etc/udev/rules.d" || { module_fan_fail; return 1; }
    module_fan_install_copy "$repo_dir/lib/modules/fan.sh" "$root/usr/lib/ps5-cachyos-tools/fan.sh" 755 || { module_fan_fail; return 1; }
    module_fan_install_copy "$repo_dir/bin/ps5-fan" "$root/usr/local/bin/ps5-fan" 755 || { module_fan_fail; return 1; }; module_fan_install_copy "$repo_dir/bin/ps5-fan-daemon" "$root/usr/local/bin/ps5-fan-daemon" 755 || { module_fan_fail; return 1; }; module_fan_install_copy "$repo_dir/bin/ps5-temp" "$root/usr/local/bin/ps5-temp" 755 || { module_fan_fail; return 1; }
    [ -e "$root/etc/ps5-fan/fan.conf" ] || module_fan_install_copy "$repo_dir/config/fan.conf" "$root/etc/ps5-fan/fan.conf" 644 || { module_fan_fail; return 1; }
    for profile in "$repo_dir"/config/profiles/*.conf; do [ -e "$root/etc/ps5-fan/profiles/$(basename "$profile")" ] || module_fan_install_copy "$profile" "$root/etc/ps5-fan/profiles/$(basename "$profile")" 644 || { module_fan_fail; return 1; }; done
    module_fan_install_copy "$repo_dir/systemd/ps5-fan-daemon.service" "$root/etc/systemd/system/ps5-fan-daemon.service" 644 || { module_fan_fail; return 1; }; module_fan_install_copy "$repo_dir/systemd/99-ps5-fan.rules" "$root/etc/udev/rules.d/99-ps5-fan.rules" 644 || { module_fan_fail; return 1; }
    mkdir -p "$root/etc/systemd/system/multi-user.target.wants" || { module_fan_fail; return 1; }; if [ -L "$root/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service" ]; then [ "$(readlink "$root/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service")" = /etc/systemd/system/ps5-fan-daemon.service ] || { module_fan_fail; return 1; }; else [ ! -e "$root/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service" ] && ln -s -- /etc/systemd/system/ps5-fan-daemon.service "$root/etc/systemd/system/multi-user.target.wants/ps5-fan-daemon.service" || { module_fan_fail; return 1; }; fi
    [ -f "$root/etc/ps5-fan/state" ] || printf '%s\n' balanced > "$root/etc/ps5-fan/state" || { module_fan_fail; return 1; }; module_fan_manifest_text > "$root/etc/ps5-fan/.ps5-cachyos-tools.manifest" && chmod 0644 "$root/etc/ps5-fan/.ps5-cachyos-tools.manifest" || { module_fan_fail; return 1; }
    if [ "$root" = / ] && [ "${CORE_FRAMEWORK_MANAGED:-0}" != 1 ] && [ "${PS5_TOOLS_NO_START:-0}" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then systemctl daemon-reload || { module_fan_fail; return 1; }; if [ "$active_before" -eq 1 ]; then [ "$runtime_changed" -eq 0 ] || systemctl restart ps5-fan-daemon.service || { module_fan_fail; return 1; }; systemctl is-active --quiet ps5-fan-daemon.service || { module_fan_fail; return 1; }; elif [ "$enabled_before" -eq 1 ]; then systemctl enable ps5-fan-daemon.service || { module_fan_fail; return 1; }; else systemctl enable --now ps5-fan-daemon.service || { module_fan_fail; return 1; }; fi; if [ "$active_before" -eq 0 ] && [ "$enabled_before" -eq 1 ]; then echo "fan: servizio lasciato inactive/enabled come nello stato iniziale" >&2; else health_pid=$active_pid; [ "$active_before" -eq 1 ] && [ "$runtime_changed" -eq 0 ] && health_pid=0; [ "$active_before" -eq 1 ] && [ "$runtime_changed" -ne 0 ] && restart_required=1; [ "$active_before" -eq 0 ] && [ "$enabled_before" -eq 0 ] && restart_required=1; health_timeout=$(module_fan_health_timeout /) || { module_fan_fail; return 1; }; module_fan_wait_ready / "$health_timeout" "$health_pid" "$health_cycles" "$health_instance" "$restart_required"; health_result=$?; case "$health_result" in 0) echo "fan: servizio aggiornato e health check applicativo verificato" >&2;; 2) echo "fan: servizio attivo ma hardware/stato DEGRADED: regolazione non confermata" >&2;; *) module_fan_fail; return 1;; esac; fi; fi
    [ "$root" != / ] && echo "fan: installazione autonoma completata (health check live da eseguire sul target)" >&2 || true
    module_fan_validate_manifest "$root" || { module_fan_fail; return 1; }; echo "fan: installazione autonoma completata"
}

module_fan_check() {
    local root=${1:-} f
    for f in /usr/local/bin/ps5-fan /usr/local/bin/ps5-fan-daemon /usr/local/bin/ps5-temp /etc/ps5-fan/.ps5-cachyos-tools.manifest /etc/ps5-fan/fan.conf /etc/ps5-fan/state /etc/ps5-fan/profiles/low.conf /etc/ps5-fan/profiles/balanced.conf /etc/ps5-fan/profiles/high.conf /etc/systemd/system/ps5-fan-daemon.service /etc/udev/rules.d/99-ps5-fan.rules; do [ -f "$root$f" ] || { echo "fan: artefatto mancante o non regolare: $f" >&2; return 1; }; done
    module_fan_validate_manifest "$root"
}
