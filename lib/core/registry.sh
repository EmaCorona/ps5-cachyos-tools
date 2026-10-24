#!/usr/bin/env bash
set -u

CORE_REGISTRY_ROOT=${CORE_REGISTRY_ROOT:-}
declare -a CORE_MODULE_IDS=()
declare -A CORE_MODULE=()
declare -A CORE_MODULE_OVERRIDE=()

core_registry_unquote() {
    local value=${1-}
    case "$value" in
        \"*\") value=${value#\"}; value=${value%\"};;
        \'*\') value=${value#\'}; value=${value%\'};;
    esac
    [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
    printf '%s\n' "$value"
}

core_registry_parse_file() {
    local file=$1 id key value raw line_no=0
    declare -A data=()
    while IFS= read -r raw || [ -n "$raw" ]; do
        line_no=$((line_no + 1)); [ -z "$raw" ] && continue; [[ "$raw" == \#* ]] && continue
        [[ "$raw" =~ ^([A-Z][A-Z0-9_]*)=(.*)$ ]] || { core_log "manifest non valido: $file:$line_no"; return 1; }
        key=${BASH_REMATCH[1]}; value=$(core_registry_unquote "${BASH_REMATCH[2]}") || return 1
        case "$key" in
            ID|NAME|ENABLED|TYPE|RUN_POLICY|BOOT_PHASE|REVISION|DEPENDENCIES|SERVICE_UNIT|FAILURE_POLICY|REQUIRES_BOOT|OWNED_PATHS|READINESS_HOOK) ;;
            *) core_log "chiave manifest non autorizzata: $key"; return 1;;
        esac
        [ -z "${data[$key]+x}" ] || { core_log "chiave duplicata: $key"; return 1; }
        data[$key]=$value
    done < "$file"
    id=${data[ID]-}; [[ "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { core_log "ID modulo non valido: $id"; return 1; }
    [ "${data[NAME]+x}" = x ] && [ "${data[ENABLED]+x}" = x ] && [ "${data[TYPE]+x}" = x ] || { core_log "manifest incompleto: $id"; return 1; }
    case "${data[ENABLED]}" in true|false) ;; *) return 1;; esac
    case "${data[TYPE]}" in task|service) ;; *) return 1;; esac
    case "${data[RUN_POLICY]-}" in once|always) ;; *) return 1;; esac
    case "${data[BOOT_PHASE]-normal}" in early|normal|service) ;; *) return 1;; esac
    case "${data[REVISION]-}" in ''|*[!0-9]*) core_log "REVISION non valida: $id"; return 1;; esac
    case "${data[FAILURE_POLICY]-continue}" in continue|critical) ;; *) core_log "FAILURE_POLICY non valida: $id"; return 1;; esac
    case "${data[REQUIRES_BOOT]-false}" in true|false) ;; *) core_log "REQUIRES_BOOT non valido: $id"; return 1;; esac
    for dep in ${data[DEPENDENCIES]-}; do [[ "$dep" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { core_log "dipendenza non valida: $id -> $dep"; return 1; }; done
    if [ -n "${data[SERVICE_UNIT]-}" ]; then [[ "${data[SERVICE_UNIT]}" =~ ^[a-zA-Z0-9_.@-]+\.service$ ]] || return 1; fi
    if [ -n "${data[READINESS_HOOK]-}" ]; then [[ "${data[READINESS_HOOK]}" =~ ^[a-zA-Z0-9_.-]+\.sh$ ]] || { core_log "READINESS_HOOK non valido: $id"; return 1; }; fi
    case "${data[TYPE]}:${data[BOOT_PHASE]-normal}" in
        task:early|task:normal|service:service) : ;;
        *) core_log "combinazione TYPE/BOOT_PHASE non supportata: $id"; return 1;;
    esac
    [ "${data[TYPE]}" != service ] || { [ "${data[RUN_POLICY]}" = always ] && [ -n "${data[SERVICE_UNIT]-}" ] || { core_log "servizio incoerente: $id"; return 1; }; }
    for path in ${data[OWNED_PATHS]-}; do
        [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || { core_log "OWNED_PATHS non valido: $id"; return 1; }
        case "$path" in
            /|/etc|/usr|/usr/lib|/usr/local|/var|/var/lib|/run|/etc/systemd|/etc/systemd/system|/var/lib/ps5-cachyos-tools|/run/ps5-cachyos-tools|/usr/lib/ps5-cachyos-tools|/usr/lib/ps5-cachyos-tools/core|/usr/lib/ps5-cachyos-tools/modules|/usr/lib/ps5-cachyos-tools/systemd|/usr/lib/ps5-cachyos-tools/bin|/usr/lib/ps5-cachyos-tools/config|/usr/lib/ps5-cachyos-tools/lib|/etc/ps5-cachyos-tools|/etc/ps5-fan|/etc/ps5-fan/profiles|/usr/local/bin|/etc/udev|/etc/udev/rules.d|*/.ps5-cachyos-tools-txn.*)
                core_log "OWNED_PATHS pericoloso: $id:$path"; return 1;;
        esac
    done
    CORE_MODULE[$id]=$(printf '%s\034' "${data[NAME]}" "${data[ENABLED]}" "${data[TYPE]}" "${data[RUN_POLICY]}" "${data[BOOT_PHASE]-normal}" "${data[REVISION]-1}" "${data[DEPENDENCIES]-}" "${data[SERVICE_UNIT]-}" "${data[FAILURE_POLICY]-continue}" "${data[REQUIRES_BOOT]-false}" "${data[OWNED_PATHS]-}" "${data[READINESS_HOOK]-}")
}

core_registry_validate_owned_paths() {
    local id path other other_path a b unit service_path
    declare -A owners=()
    declare -A service_units=()
    for id in "${CORE_MODULE_IDS[@]}"; do
        for path in $(core_registry_field "$id" 10); do
            [ "$path" != / ] || { core_log "OWNED_PATHS non può essere /"; return 1; }
            [ -n "$path" ] || { core_log "OWNED_PATHS vuoto: $id"; return 1; }
            [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* ]] || return 1
            case "$path" in
                /etc|/usr|/usr/lib|/usr/local|/var|/var/lib|/run|/etc/systemd|/etc/systemd/system|/var/lib/ps5-cachyos-tools|/run/ps5-cachyos-tools|/usr/lib/ps5-cachyos-tools|/usr/lib/ps5-cachyos-tools/core|/usr/lib/ps5-cachyos-tools/modules|/usr/lib/ps5-cachyos-tools/systemd|/usr/lib/ps5-cachyos-tools/bin|/usr/lib/ps5-cachyos-tools/config|/usr/lib/ps5-cachyos-tools/lib|/etc/ps5-cachyos-tools|/etc/ps5-fan|/etc/ps5-fan/profiles|/usr/local/bin|/etc/udev|/etc/udev/rules.d|*/.ps5-cachyos-tools-txn.*) return 1;;
            esac
            [ -z "${owners[$path]+x}" ] || { core_log "ownership duplicata: $path"; return 1; }
            owners[$path]=$id
        done
        if [ "$(core_registry_field "$id" 2)" = service ]; then
            unit=$(core_registry_field "$id" 7); service_path="/etc/systemd/system/$unit"
            case "$unit" in ps5-tools-early.service|ps5-tools-boot.service) core_log "unit riservata al core: $id/$unit"; return 1;; esac
            [ -z "${service_units[$unit]+x}" ] || { core_log "SERVICE_UNIT duplicata: $unit"; return 1; }
            service_units[$unit]=$id
            case " $(core_registry_field "$id" 10) " in *" $service_path "*) : ;; *) core_log "unit non inclusa in OWNED_PATHS: $id/$unit"; return 1;; esac
        fi
    done
    for path in "${!owners[@]}"; do
        for other in "${!owners[@]}"; do
            [ "$path" = "$other" ] && continue
            a=${path%/}; b=${other%/}
            case "$a/" in "$b/"*) core_log "ownership sovrapposta: $a e $b"; return 1;; esac
        done
    done
}

core_registry_discover() {
    local root=$1 dir id
    CORE_REGISTRY_ROOT=$root; CORE_MODULE_IDS=(); CORE_MODULE=(); CORE_MODULE_OVERRIDE=()
    [ -d "$root" ] || { core_log "registry assente: $root"; return 1; }
    while IFS= read -r dir; do
        [ -f "$dir/module.conf" ] && [ ! -L "$dir/module.conf" ] || { core_log "manifest assente o symlink: $dir/module.conf"; return 1; }
        core_registry_parse_file "$dir/module.conf" || return 1
        id=${dir##*/}; [ "${CORE_MODULE[$id]+x}" = x ] || { core_log "ID e directory divergenti: $id"; return 1; }
        CORE_MODULE_IDS+=("$id")
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '_*' -print | sort)
    [ "${#CORE_MODULE_IDS[@]}" -gt 0 ] || { core_log 'nessun modulo trovato'; return 1; }
    core_registry_load_overrides "${CORE_CONFIG_ROOT:-/}" || return 1
    printf '%s\n' "${CORE_MODULE_IDS[@]}"
}

core_registry_load_overrides() {
    local config_root=$1 id file raw key value
    local dir="$config_root/etc/ps5-cachyos-tools/modules.d"
    [ -d "$dir" ] || return 0
    while IFS= read -r file; do
        id=${file##*/}; id=${id%.conf}
        [ "${CORE_MODULE[$id]+x}" = x ] || { core_log "override orfano ignorato: $id"; continue; }
        while IFS= read -r raw || [ -n "$raw" ]; do
            [ -z "$raw" ] && continue; [[ "$raw" == \#* ]] && continue
            [[ "$raw" =~ ^(ENABLED|RUN_POLICY)=([^[:space:]]+)$ ]] || { core_log "override non valido: $file"; return 1; }
            key=${BASH_REMATCH[1]}; value=${BASH_REMATCH[2]}
            case "$key:$value" in ENABLED:true|ENABLED:false|RUN_POLICY:once|RUN_POLICY:always) ;; *) return 1;; esac
            [ "$key" != RUN_POLICY ] || [ "$(core_registry_field "$id" 2)" != service ] || { core_log "RUN_POLICY non sovrascrivibile per service: $id"; return 1; }
            [ -z "${CORE_MODULE_OVERRIDE[$id:$key]+x}" ] || return 1
            CORE_MODULE_OVERRIDE[$id:$key]=$value
        done < "$file"
    done < <(find "$dir" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | sort)
}

core_registry_field() {
    local id=$1 index=$2 IFS=$'\034' value
    local -a fields
    read -r -a fields <<< "${CORE_MODULE[$id]}"
    [ "$index" -ne 1 ] || [ -z "${CORE_MODULE_OVERRIDE[$id:ENABLED]+x}" ] || fields[1]=${CORE_MODULE_OVERRIDE[$id:ENABLED]}
    [ "$index" -ne 3 ] || [ -z "${CORE_MODULE_OVERRIDE[$id:RUN_POLICY]+x}" ] || fields[3]=${CORE_MODULE_OVERRIDE[$id:RUN_POLICY]}
    printf '%s\n' "${fields[$index]-}"
}
core_registry_validate_dependencies() {
    local id dep deps type phase dep_type dep_phase
    for id in "${CORE_MODULE_IDS[@]}"; do
        deps=$(core_registry_field "$id" 6)
        type=$(core_registry_field "$id" 2); phase=$(core_registry_field "$id" 4)
        for dep in $deps; do
            [ "${CORE_MODULE[$dep]+x}" = x ] || { core_log "$id: dipendenza sconosciuta: $dep"; return 1; }
            dep_type=$(core_registry_field "$dep" 2); dep_phase=$(core_registry_field "$dep" 4)
            [ "$phase" != early ] || [ "$dep_phase" = early ] || { core_log "$id: dipendenza non disponibile nella fase early: $dep"; return 1; }
            [ "$type" != service ] || [ "$dep_type" = service ] || { core_log "$id: service dipende da task non disponibile: $dep"; return 1; }
            [ "$(core_registry_field "$dep" 2)" != service ] || [ -n "$(core_registry_field "$dep" 7)" ] || { core_log "$id: dipendenza service senza unit"; return 1; }
        done
    done
    return 0
}
