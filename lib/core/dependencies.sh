#!/usr/bin/env bash
set -u

core_registry_order() {
    local -a pending=() result=() ids=() deps dep id progress next=()
    local ready item
    mapfile -t ids < <(printf '%s\n' "${CORE_MODULE_IDS[@]}" | sort)
    pending=("${ids[@]}")
    while [ "${#pending[@]}" -gt 0 ]; do
        progress=0
        for id in "${pending[@]}"; do
            deps=$(core_registry_field "$id" 6); ready=1
            for dep in $deps; do printf '%s\n' "${result[@]}" | grep -Fxq "$dep" || ready=0; done
            [ "$ready" -eq 1 ] || continue
            result+=("$id"); progress=1
            next=(); for item in "${pending[@]}"; do [ "$item" != "$id" ] && next+=("$item"); done; pending=("${next[@]}")
        done
        [ "$progress" -eq 1 ] || { core_log 'dipendenze cicliche o fase non ordinabile'; return 1; }
    done
    printf '%s\n' "${result[@]}"
}
