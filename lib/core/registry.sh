#!/usr/bin/env bash
set -u

CORE_REGISTRY_ROOT=${CORE_REGISTRY_ROOT:-}
declare -a CORE_MODULE_IDS=()
declare -A CORE_MODULE=()

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
            ID|NAME|ENABLED|TYPE|RUN_POLICY|BOOT_PHASE|REVISION|DEPENDENCIES|SERVICE_UNIT|FAILURE_POLICY|REQUIRES_BOOT) ;;
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
    [ "${data[TYPE]}" != service ] || { [ "${data[RUN_POLICY]}" = always ] && [ -n "${data[SERVICE_UNIT]-}" ] || { core_log "servizio incoerente: $id"; return 1; }; }
    CORE_MODULE[$id]=$(printf '%s\034' "${data[NAME]}" "${data[ENABLED]}" "${data[TYPE]}" "${data[RUN_POLICY]}" "${data[BOOT_PHASE]-normal}" "${data[REVISION]-1}" "${data[DEPENDENCIES]-}" "${data[SERVICE_UNIT]-}" "${data[FAILURE_POLICY]-continue}" "${data[REQUIRES_BOOT]-false}")
}

core_registry_discover() {
    local root=$1 dir id
    CORE_REGISTRY_ROOT=$root; CORE_MODULE_IDS=(); CORE_MODULE=()
    [ -d "$root" ] || { core_log "registry assente: $root"; return 1; }
    while IFS= read -r dir; do
        [ -f "$dir/module.conf" ] && [ ! -L "$dir/module.conf" ] || { core_log "manifest assente o symlink: $dir/module.conf"; return 1; }
        core_registry_parse_file "$dir/module.conf" || return 1
        id=${dir##*/}; [ "${CORE_MODULE[$id]+x}" = x ] || { core_log "ID e directory divergenti: $id"; return 1; }
        CORE_MODULE_IDS+=("$id")
    done < <(find "$root" -mindepth 1 -maxdepth 1 -type d ! -name '_*' -print | sort)
    [ "${#CORE_MODULE_IDS[@]}" -gt 0 ] || { core_log 'nessun modulo trovato'; return 1; }
    printf '%s\n' "${CORE_MODULE_IDS[@]}"
}

core_registry_field() {
    local id=$1 index=$2 IFS=$'\034' value
    local -a fields
    read -r -a fields <<< "${CORE_MODULE[$id]}"
    printf '%s\n' "${fields[$index]-}"
}
core_registry_validate_dependencies() {
    local id dep deps
    for id in "${CORE_MODULE_IDS[@]}"; do
        deps=$(core_registry_field "$id" 6)
        for dep in $deps; do
            [ "${CORE_MODULE[$dep]+x}" = x ] || { core_log "$id: dipendenza sconosciuta: $dep"; return 1; }
            [ "$(core_registry_field "$id" 4)" = early ] && [ "$(core_registry_field "$dep" 4)" = normal ] && { core_log "$id: dipendenza normal da fase early"; return 1; }
        done
    done
    return 0
}
