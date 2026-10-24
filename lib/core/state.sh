#!/usr/bin/env bash
set -u

core_state_dir() { printf '%s/var/lib/ps5-cachyos-tools/state/modules\n' "$1"; }
core_state_file() { printf '%s/%s.state\n' "$(core_state_dir "$1")" "$2"; }
core_state_validate_root() {
    local root=$1 current=/ part
    [[ "$root" = /* && "$root" != *'..'* && "$root" != *$'\n'* && "$root" != *$'\r'* ]] || return 1
    [ "$root" = / ] && return 0
    [ -d "$root" ] && [ ! -L "$root" ] || return 1
    IFS=/ read -ra parts <<< "${root#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || return 1
    done
}
core_state_validate_path() {
    local root=$1 path=$2 current part full
    core_state_validate_root "$root" || return 1
    [[ "$path" = /* && "$path" != *'..'* && "$path" != *$'\n'* && "$path" != *$'\r'* ]] || return 1
    current=${root%/}; [ -n "$current" ] || current=/; full="$root$path"; [ "$root" = / ] && full="$path"
    IFS=/ read -ra state_parts <<< "${path#/}"
    for part in "${state_parts[@]}"; do
        [ -n "$part" ] || continue
        current="${current%/}/$part"
        [ ! -L "$current" ] || return 1
    done
    [ ! -L "$full" ]
}
core_state_write() {
    local root=$1 id=$2 status=$3 policy=$4 revision=$5 code=$6 boot_id=${7-unknown} dir file tmp now request_id='' applied_request_id='' request_phase=NONE
    dir=$(core_state_dir "$root"); file=$(core_state_file "$root" "$id"); core_state_validate_path "$root" /var/lib/ps5-cachyos-tools/state/modules || return 1; core_state_validate_path "$root" "/var/lib/ps5-cachyos-tools/state/modules/$id.state" || return 1; core_state_validate_path "$root" /var/lib/ps5-cachyos-tools/state/reapply || return 1; core_state_validate_path "$root" /var/lib/ps5-cachyos-tools/install.identity || return 1; mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
    [ ! -L "$file" ] && { [ ! -e "$file" ] || [ -f "$file" ]; } || return 1
    now=$(date +%s); tmp=$(mktemp "$dir/.${id}.state.XXXXXX") || return 1
    chmod 600 "$tmp"; printf 'id=%s\npolicy_at_run=%s\nrevision=%s\ncompleted_at=%s\nlast_attempt_at=%s\nlast_exit_code=%s\nlast_boot_id=%s\nattempt_boot_id=%s\nautomatic_attempted_boot_id=%s\nreapply_requested=%s\nstatus=%s\ninstall_identity=%s\n' "$id" "$policy" "$revision" "$([ "$status" = SUCCESS ] && echo "$now" || echo 0)" "$now" "$code" "$boot_id" "$boot_id" "$boot_id" "$([ -f "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ] && echo true || echo false)" "$status" "$(cat "$root/var/lib/ps5-cachyos-tools/install.identity" 2>/dev/null || echo unknown)" > "$tmp" || { rm -f "$tmp"; return 1; }
    local completed_at=0 completed_revision=$revision old
    old=$(core_state_file "$root" "$id")
    if [ -f "$old" ] && [ ! -L "$old" ]; then
        completed_at=$(awk -F= '$1=="completed_at"{print $2; exit}' "$old" 2>/dev/null || echo 0)
        completed_revision=$(awk -F= '$1=="completed_revision"{print $2; exit}' "$old" 2>/dev/null || echo "$revision")
        applied_request_id=$(awk -F= '$1=="reapply_applied_id"{print $2; exit}' "$old" 2>/dev/null || true)
    fi
    if [ -f "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ] && [ ! -L "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ]; then
        request_id=$(awk -F= '$1=="requested_at"{print $2; exit}' "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" 2>/dev/null || true)
    fi
    { [ "$status" = APPLIED ] || [ "$status" = SUCCESS ]; } && [ -n "$request_id" ] && applied_request_id=$request_id
    case "$status" in RUNNING) request_phase=RUNNING;; APPLIED) request_phase=APPLIED;; SUCCESS) [ -n "$request_id" ] && request_phase=COMPLETED || request_phase=NONE;; *) [ -n "$request_id" ] && request_phase=REQUESTED || request_phase=NONE;; esac
    [ "$status" = SUCCESS ] && { completed_at=$now; completed_revision=$revision; }
    printf 'id=%s\npolicy_at_run=%s\nrevision=%s\ncompleted_at=%s\ncompleted_revision=%s\nreapply_applied_id=%s\nrequest_phase=%s\nlast_attempt_at=%s\nlast_exit_code=%s\nlast_boot_id=%s\nattempt_boot_id=%s\nautomatic_attempted_boot_id=%s\nreapply_requested=%s\nstatus=%s\ninstall_identity=%s\n' "$id" "$policy" "$revision" "$completed_at" "$completed_revision" "$applied_request_id" "$request_phase" "$now" "$code" "$boot_id" "$boot_id" "$boot_id" "$([ -f "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ] && echo true || echo false)" "$status" "$(cat "$root/var/lib/ps5-cachyos-tools/install.identity" 2>/dev/null || echo unknown)" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f -- "$tmp" "$file"
}
core_state_get() {
    local root=$1 key=$2 id=$3 file
    core_state_validate_path "$root" /var/lib/ps5-cachyos-tools/state/modules || return 1
    core_state_validate_path "$root" "/var/lib/ps5-cachyos-tools/state/modules/$id.state" || return 1
    file=$(core_state_file "$root" "$id")
    [ ! -L "$file" ] && { [ ! -e "$file" ] || [ -f "$file" ]; } || return 1
    [ ! -e "$file" ] && return 0
    [ "$(stat -c '%a' "$file" 2>/dev/null)" = 600 ] || return 1
    awk -F= -v key="$2" '$1==key{print substr($0,index($0,"=")+1); exit}' "$file" 2>/dev/null
}
core_state_boot_id() { [ -n "${CORE_BOOT_ID-}" ] && printf '%s\n' "$CORE_BOOT_ID" || cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown\n'; }
