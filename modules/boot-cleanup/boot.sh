#!/usr/bin/env bash
set -u

root=$1
run="$root/run/ps5-cachyos-tools/boot-cleanup"
conf="$root/etc/ps5-cachyos-tools/boot-cleanup.conf"
state="$run/cleanup.state"
stale_file="$run/steam-stale.list"
[ -d "$root" ] && [ ! -L "$root" ] || exit 1
[ -f "$conf" ] && [ ! -L "$conf" ] || exit 1
if [ ! -e "$run" ]; then mkdir -p -- "$run" || exit 1; fi
[ -d "$run" ] && [ ! -L "$run" ] || exit 1
lock="$run/.lock"; mkdir -- "$lock" 2>/dev/null || exit 1
trap 'rmdir -- "$lock" 2>/dev/null || true' EXIT
grep -Eq '^STEAM_STALE_FILE=/run/ps5-cachyos-tools/boot-cleanup/steam-stale.list$' "$conf" || exit 1
dry_run=0; grep -Eq '^DRY_RUN=1$' "$conf" && dry_run=1; [ "${PS5_CLEANUP_DRY_RUN:-0}" = 1 ] && dry_run=1

valid_artifact() { [[ "$1" =~ ^/run/user/[0-9]+/steam-(runtime|webhelper|client)-[0-9]+$ || "$1" =~ ^/home/[a-z_][a-z0-9_-]*/\.steam/steam\.(pid|pipe)$ ]]; }
proc_start() { awk '{sub(/^.*\) /, ""); print $20}' "$1/stat" 2>/dev/null; }
proc_uid() { stat -c '%u' "$1" 2>/dev/null; }
proc_command() { basename -- "$(readlink "$1/exe" 2>/dev/null || true)"; }
safe_parent() {
    local path=$1 current="$root" part
    IFS=/ read -ra parts <<< "${path#/}"
    for part in "${parts[@]}"; do
        [ -n "$part" ] || continue
        current="$current/$part"
        [ "$current" = "$root$path" ] && break
        [ ! -L "$current" ] || return 1
    done
}
safe_tree() { local p=$1 cur=/ part; IFS=/ read -ra parts <<< "${p#/}"; for part in "${parts[@]}"; do [ -n "$part" ] || continue; cur="${cur%/}/$part"; [ ! -L "$root$cur" ] || return 1; done; }

checked=0; removed=0; active=0; rejected=0; records=0
safe_tree /run/ps5-cachyos-tools/boot-cleanup || exit 1
# Produce records only for the two exact legacy Steam artifacts owned by this
# migration. Unknown files and all diagnostic data remain untouched.
persist="$root/var/lib/ps5-cachyos-tools/boot-cleanup"
safe_tree /var/lib/ps5-cachyos-tools/boot-cleanup || exit 1
[ -e "$persist" ] || mkdir -p -- "$persist" || exit 1
[ -d "$persist" ] && [ ! -L "$persist" ] || exit 1
migration="$persist/migration.state"
record_legacy() {
    local artifact=$1 pid=$2 uid=$3 command_name=steam start_time=0 proc="$root/proc/$pid" line tmp observed_uid observed_command
    if [ -e "$proc" ] || [ -L "$proc" ]; then
        [ -d "$proc" ] && [ ! -L "$proc" ] || return 0
        start_time=$(proc_start "$proc")
        observed_uid=$(proc_uid "$proc")
        observed_command=$(proc_command "$proc")
        # An existing process must be fully observable and match the legacy
        # artifact. Never downgrade an observed-but-unverifiable process to
        # starttime=0: that value is reserved for an absent process.
        [ "$start_time" -gt 0 ] 2>/dev/null || return 0
        [ "$observed_uid" = "$uid" ] || return 0
        case "$observed_command" in
            steam|steamwebhelper|steam-runtime-launcher) command_name=$observed_command;;
            *) return 0;;
        esac
    fi
    [ "$dry_run" -eq 0 ] || return 0
    line="$pid $start_time $uid $artifact $command_name migration legacy"
    tmp=$(mktemp "$run/.steam-stale.XXXXXX") || return 1
    if [ -f "$stale_file" ] && [ ! -L "$stale_file" ]; then
        awk -v artifact="$artifact" '($4 == artifact && $6 == "migration" && $7 == "legacy") { next } { print }' "$stale_file" > "$tmp" || { rm -f -- "$tmp"; return 1; }
    fi
    printf '%s\n' "$line" >> "$tmp" || { rm -f -- "$tmp"; return 1; }
    chmod 0600 "$tmp" && mv -f -- "$tmp" "$stale_file" || { rm -f -- "$tmp"; return 1; }
}

needs_migration=0
[ ! -e "$migration" ] && needs_migration=1
if [ "$needs_migration" -eq 0 ]; then
    for home_dir in "$root"/home/*; do
        artifact_full="$home_dir/.steam/steam.pid"
        [ -f "$artifact_full" ] && [ ! -L "$artifact_full" ] && [ "$artifact_full" -nt "$migration" ] && needs_migration=1
    done
fi
if [ "$needs_migration" -eq 1 ]; then
    [ "$dry_run" -eq 1 ] || { [ -e "$stale_file" ] || { [ ! -L "$stale_file" ] || exit 1; : > "$stale_file"; } || exit 1; }
    for home_dir in "$root"/home/*; do
        [ -d "$home_dir" ] && [ ! -L "$home_dir" ] || continue
        # steam.pipe may be a FIFO/socket; it is never read or migrated.
        artifact_full="$home_dir/.steam/steam.pid"
        [ -f "$artifact_full" ] && [ ! -L "$artifact_full" ] || continue
        uid=$(stat -c '%u' "$artifact_full" 2>/dev/null) || continue
        pid=$(sed -n '1{/^[[:space:]]*[0-9][0-9]*[[:space:]]*$/p;}' "$artifact_full" | tr -d '[:space:]')
        [ "$pid" -gt 0 ] 2>/dev/null || continue
        artifact=${artifact_full#"$root"}
        record_legacy "$artifact" "$pid" "$uid" || exit 1
    done
    if [ "$dry_run" -eq 0 ]; then
        umask 077; migration_tmp=$(mktemp "$persist/.migration.state.XXXXXX") || exit 1
        printf 'status=completed\nreason=legacy-exact-artifacts\nowner=boot-cleanup\nupdated_at=%s\n' "$(date +%s)" > "$migration_tmp" || { rm -f -- "$migration_tmp"; exit 1; }
        chmod 0600 "$migration_tmp" && mv -f -- "$migration_tmp" "$migration" || { rm -f -- "$migration_tmp"; exit 1; }
    fi
fi
would_remove=0
if [ -f "$stale_file" ] && [ ! -L "$stale_file" ]; then
    while IFS=' ' read -r pid start_time uid artifact command reason owner extra || [ -n "${pid:-}" ]; do
        [ -z "${pid:-}" ] && continue
        records=$((records + 1)); [ "$records" -le 128 ] || { rejected=$((rejected + 1)); break; }
        [ -z "${extra:-}" ] || { rejected=$((rejected + 1)); continue; }
        [[ "$pid" =~ ^[1-9][0-9]*$ && "$start_time" =~ ^[0-9]+$ && "$uid" =~ ^[0-9]+$ ]] || { rejected=$((rejected + 1)); continue; }
        [[ "$command" = steam || "$command" = steamwebhelper || "$command" = steam-runtime-launcher ]] || { rejected=$((rejected + 1)); continue; }
        valid_artifact "$artifact" || { rejected=$((rejected + 1)); continue; }
        case "$artifact" in /run/user/"$uid"/*) ;; /home/*/.steam/steam.pid) ;; *) rejected=$((rejected + 1)); continue;; esac
        artifact_full="$root$artifact"
        safe_parent "$artifact" || { rejected=$((rejected + 1)); continue; }
        proc="$root/proc/$pid"
        if [ -e "$proc" ] || [ -L "$proc" ]; then
            [ -d "$proc" ] && [ ! -L "$proc" ] || { rejected=$((rejected + 1)); continue; }
            [ "$start_time" -gt 0 ] 2>/dev/null && [ "$(proc_start "$proc")" = "$start_time" ] && [ "$(proc_uid "$proc")" = "$uid" ] && [ "$(proc_command "$proc")" = "$command" ] || { rejected=$((rejected + 1)); continue; }
            active=$((active + 1)); checked=$((checked + 1)); continue
        fi
        [ -f "$artifact_full" ] && [ ! -L "$artifact_full" ] || { rejected=$((rejected + 1)); continue; }
        [ "$(stat -c '%u' "$artifact_full" 2>/dev/null)" = "$uid" ] || { rejected=$((rejected + 1)); continue; }
        if [ "$dry_run" -eq 1 ]; then would_remove=$((would_remove + 1)); else rm -f -- "$artifact_full" || { rejected=$((rejected + 1)); continue; }; removed=$((removed + 1)); fi
        checked=$((checked + 1))
    done < "$stale_file"
fi
umask 077; tmp=$(mktemp "$run/.cleanup.state.XXXXXX") || exit 1
action=COMPLETED; [ "$removed" -eq 0 ] && [ "$would_remove" -eq 0 ] && action=NO_ACTION; [ "$dry_run" -eq 1 ] && action=DRY_RUN
printf 'action=%s\nchecked=%s\nremoved=%s\nwould_remove=%s\nactive=%s\nrejected=%s\nupdated_at=%s\n' "$action" "$checked" "$removed" "$would_remove" "$active" "$rejected" "$(date +%s)" > "$tmp" || { rm -f -- "$tmp"; exit 1; }
chmod 0600 "$tmp" && mv -f -- "$tmp" "$state" || { rm -f -- "$tmp"; exit 1; }
exit 0
