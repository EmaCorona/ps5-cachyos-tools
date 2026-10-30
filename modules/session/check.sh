#!/usr/bin/env bash
set -u
root=$1
profile="$root/etc/profile.d/ps5-tty-session.sh"
common="$root/usr/local/libexec/ps5-cachyos-tools/session-common.sh"
supervisor="$root/usr/local/libexec/ps5-cachyos-tools/session-supervisor"
policy="$root/usr/local/libexec/ps5-cachyos-tools/session-policy"
config_dir="$root/home/steam/.config/ps5-cachyos-tools"
if [ -e "$config_dir" ] || [ -L "$config_dir" ]; then
    [ -d "$config_dir" ] && [ ! -L "$config_dir" ] || exit 1
    steam_ids=$(awk -F: '$1 == "steam" { print $3 ":" $4; exit }' "$root/etc/passwd" 2>/dev/null)
    if [[ "$steam_ids" =~ ^[0-9]+:[0-9]+$ ]] && \
       { [ "$(id -u)" -eq 0 ] || [ "$steam_ids" = "$(id -u):$(id -g)" ]; }; then
        [ "$(stat -c '%u:%g' -- "$config_dir" 2>/dev/null)" = "$steam_ids" ] || exit 1
    fi
fi
[ -f "$profile" ] && [ -x "$supervisor" ] && [ -x "$root/usr/bin/steamos-session-select" ] && \
    [ -x "$policy" ] && grep -q 'ps5_session_read_config' "$policy" && \
    [ -f "$common" ] && \
    grep -q 'gamescope' "$supervisor" && grep -q 'FALLBACK' "$supervisor" && \
    grep -q 'import-environment .*KWIN_FORCE_SW_CURSOR' "$supervisor" && \
    grep -Fq -- '-u KWIN_FORCE_SW_CURSOR' "$supervisor"
