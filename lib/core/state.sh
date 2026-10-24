#!/usr/bin/env bash
set -u

core_state_dir() { printf '%s/var/lib/ps5-cachyos-tools/state/modules\n' "$1"; }
core_state_file() { printf '%s/%s.state\n' "$(core_state_dir "$1")" "$2"; }
core_state_write() {
    local root=$1 id=$2 status=$3 policy=$4 revision=$5 code=$6 boot_id=${7-unknown} dir file tmp now
    dir=$(core_state_dir "$root"); file=$(core_state_file "$root" "$id"); mkdir -p "$dir" || return 1; chmod 700 "$dir" || return 1
    [ ! -L "$file" ] && { [ ! -e "$file" ] || [ -f "$file" ]; } || return 1
    now=$(date +%s); tmp=$(mktemp "$dir/.${id}.state.XXXXXX") || return 1
    chmod 600 "$tmp"; printf 'id=%s\npolicy_at_run=%s\nrevision=%s\ncompleted_at=%s\nlast_attempt_at=%s\nlast_exit_code=%s\nlast_boot_id=%s\nattempt_boot_id=%s\nautomatic_attempted_boot_id=%s\nreapply_requested=%s\nstatus=%s\ninstall_identity=%s\n' "$id" "$policy" "$revision" "$([ "$status" = SUCCESS ] && echo "$now" || echo 0)" "$now" "$code" "$boot_id" "$boot_id" "$boot_id" "$([ -f "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ] && echo true || echo false)" "$status" "$(cat "$root/var/lib/ps5-cachyos-tools/install.identity" 2>/dev/null || echo unknown)" > "$tmp" || { rm -f "$tmp"; return 1; }
    local completed_at=0 completed_revision=$revision old
    old=$(core_state_file "$root" "$id")
    if [ -f "$old" ] && [ ! -L "$old" ]; then
        completed_at=$(awk -F= '$1=="completed_at"{print $2; exit}' "$old" 2>/dev/null || echo 0)
        completed_revision=$(awk -F= '$1=="completed_revision"{print $2; exit}' "$old" 2>/dev/null || echo "$revision")
    fi
    [ "$status" = SUCCESS ] && { completed_at=$now; completed_revision=$revision; }
    printf 'id=%s\npolicy_at_run=%s\nrevision=%s\ncompleted_at=%s\ncompleted_revision=%s\nlast_attempt_at=%s\nlast_exit_code=%s\nlast_boot_id=%s\nattempt_boot_id=%s\nautomatic_attempted_boot_id=%s\nreapply_requested=%s\nstatus=%s\ninstall_identity=%s\n' "$id" "$policy" "$revision" "$completed_at" "$completed_revision" "$now" "$code" "$boot_id" "$boot_id" "$boot_id" "$([ -f "$root/var/lib/ps5-cachyos-tools/state/reapply/$id.request" ] && echo true || echo false)" "$status" "$(cat "$root/var/lib/ps5-cachyos-tools/install.identity" 2>/dev/null || echo unknown)" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv -f -- "$tmp" "$file"
}
core_state_get() {
    local file
    file=$(core_state_file "$1" "$3")
    [ ! -L "$file" ] && { [ ! -e "$file" ] || [ -f "$file" ]; } || return 1
    [ ! -e "$file" ] && return 0
    [ "$(stat -c '%a' "$file" 2>/dev/null)" = 600 ] || return 1
    awk -F= -v key="$2" '$1==key{print substr($0,index($0,"=")+1); exit}' "$file" 2>/dev/null
}
core_state_boot_id() { [ -n "${CORE_BOOT_ID-}" ] && printf '%s\n' "$CORE_BOOT_ID" || cat /proc/sys/kernel/random/boot_id 2>/dev/null || printf 'unknown\n'; }
