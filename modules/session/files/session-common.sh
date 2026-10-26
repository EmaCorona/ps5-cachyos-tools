#!/usr/bin/env bash
PS5_SESSION_CONFIG=${PS5_SESSION_CONFIG:-${XDG_CONFIG_HOME:-${HOME:-/home/steam}/.config}/ps5-cachyos-tools/session.conf}
PS5_SESSION_RUNTIME=${PS5_SESSION_RUNTIME:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}
PS5_SESSION_DEFAULT=desktop
PS5_SESSION_NEXT=''

ps5_session_read_config() {
    local file=${1:-$PS5_SESSION_CONFIG} line key value
    PS5_SESSION_DEFAULT=desktop PS5_SESSION_NEXT=''
    [[ -f "$file" && ! -L "$file" ]] || return 1
    declare -A seen=()
    while IFS= read -r line || [[ -n "$line" ]]; do
        line=${line%%#*}; [[ -z "${line//[[:space:]]/}" ]] && continue
        [[ "$line" =~ ^[[:space:]]*(DEFAULT_SESSION|NEXT_SESSION)=([[:alnum:]_-]*)[[:space:]]*$ ]] || return 1
        key=${BASH_REMATCH[1]} value=${BASH_REMATCH[2]}
        [[ -z ${seen[$key]+x} ]] || return 1
        seen[$key]=1
        case "$key:$value" in
            DEFAULT_SESSION:gamescope|DEFAULT_SESSION:desktop|DEFAULT_SESSION:plasma)
                [[ $value == plasma ]] && value=desktop
                PS5_SESSION_DEFAULT=$value ;;
            NEXT_SESSION:|NEXT_SESSION:gamescope|NEXT_SESSION:desktop|NEXT_SESSION:plasma)
                [[ $value == plasma ]] && value=desktop
                PS5_SESSION_NEXT=$value ;;
            *) return 1 ;;
        esac
    done < "$file"
    return 0
}

ps5_session_write_config() {
    local default=$1 next=$2 config_dir tmp lock_dir lock_file
    case "$default" in gamescope|desktop) ;; *) return 2;; esac
    case "$next" in ''|gamescope|desktop) ;; *) return 2;; esac
    config_dir=${PS5_SESSION_CONFIG%/*}
    lock_dir="$PS5_SESSION_RUNTIME/ps5-cachyos-tools"
    mkdir -p -- "$lock_dir" "$config_dir" || return 1
    [[ ! -L "$lock_dir" && ! -L "$config_dir" ]] || return 1
    lock_file="$lock_dir/session.lock"
    exec {lock_fd}>"$lock_file" || return 1
    flock -x "$lock_fd" || { exec {lock_fd}>&-; return 1; }
    tmp=$(mktemp "$config_dir/.session.conf.XXXXXX") || { exec {lock_fd}>&-; return 1; }
    printf 'DEFAULT_SESSION=%s\nNEXT_SESSION=%s\n' "$default" "$next" > "$tmp" || { rm -f -- "$tmp"; exec {lock_fd}>&-; return 1; }
    chmod 0600 "$tmp" || { rm -f -- "$tmp"; exec {lock_fd}>&-; return 1; }
    mv -f -- "$tmp" "$PS5_SESSION_CONFIG" || { rm -f -- "$tmp"; exec {lock_fd}>&-; return 1; }
    exec {lock_fd}>&-
}

ps5_session_log() {
    local level=$1 message=$2 file=${PS5_SESSION_LOG:-${HOME:-/home/steam}/.gamescope-session.log}
    printf '[%s] session %s: %s\n' "$(date -Is 2>/dev/null || date)" "$level" "$message" >> "$file" 2>/dev/null || true
    if command -v logger >/dev/null 2>&1; then logger -t ps5-session -- "$level: $message" 2>/dev/null || true; fi
}
