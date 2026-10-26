#!/usr/bin/env bash
PS5_SESSION_CONFIG=${PS5_SESSION_CONFIG:-${XDG_CONFIG_HOME:-${HOME:-/home/steam}/.config}/ps5-cachyos-tools/session.conf}
PS5_SESSION_RUNTIME=${PS5_SESSION_RUNTIME:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}
PS5_SESSION_CONTROL_DIR=${PS5_SESSION_CONTROL_DIR:-$PS5_SESSION_RUNTIME/ps5-cachyos-tools}
PS5_SESSION_SWITCH_FILE=${PS5_SESSION_SWITCH_FILE:-$PS5_SESSION_CONTROL_DIR/session.request}
PS5_SESSION_SUPERVISOR_PID_FILE=${PS5_SESSION_SUPERVISOR_PID_FILE:-$PS5_SESSION_CONTROL_DIR/session-supervisor.pid}
PS5_SESSION_BOOT_ID=unknown
IFS= read -r PS5_SESSION_BOOT_ID < "${PS5_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}" || PS5_SESSION_BOOT_ID=unknown
[[ "$PS5_SESSION_BOOT_ID" =~ ^[A-Fa-f0-9-]{8,64}$ ]] || PS5_SESSION_BOOT_ID=unknown
PS5_SESSION_DEFAULT=desktop
PS5_SESSION_NEXT=''
PS5_SESSION_SWITCH_TARGET=''

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

ps5_session_control_prepare() {
    [[ ! -L "$PS5_SESSION_RUNTIME" ]] || return 1
    mkdir -p -- "$PS5_SESSION_RUNTIME" "$PS5_SESSION_CONTROL_DIR" || return 1
    [[ -d "$PS5_SESSION_RUNTIME" && ! -L "$PS5_SESSION_RUNTIME" && -O "$PS5_SESSION_RUNTIME" ]] || return 1
    [[ -d "$PS5_SESSION_CONTROL_DIR" && ! -L "$PS5_SESSION_CONTROL_DIR" && -O "$PS5_SESSION_CONTROL_DIR" ]] || return 1
    chmod 0700 "$PS5_SESSION_CONTROL_DIR" || return 1
    [[ ! -L "$PS5_SESSION_SWITCH_FILE" && ! -L "$PS5_SESSION_SUPERVISOR_PID_FILE" ]] || return 1
}

ps5_session_control_lock() {
    local lock_file="$PS5_SESSION_CONTROL_DIR/session-control.lock"
    [[ ! -L "$lock_file" ]] || return 1
    exec 9>"$lock_file" || return 1
    flock -x 9 || { exec 9>&-; return 1; }
}

ps5_session_supervisor_is_running() {
    local pid=$1 command_line
    [[ $pid =~ ^[1-9][0-9]{0,9}$ && -d /proc/$pid && -O /proc/$pid ]] || return 1
    command_line=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || return 1
    [[ $command_line == *session-supervisor* ]]
}

ps5_session_control_register() {
    local tmp supervisor_lock="$PS5_SESSION_CONTROL_DIR/session-supervisor.lock"
    ps5_session_control_prepare || return 1
    [[ ! -L "$supervisor_lock" ]] || return 1
    exec 8>"$supervisor_lock" || return 1
    flock -n 8 || { exec 8>&-; return 1; }
    ps5_session_control_lock || { exec 8>&-; return 1; }
    rm -f -- "$PS5_SESSION_SWITCH_FILE"
    tmp=$(mktemp "$PS5_SESSION_CONTROL_DIR/.session-supervisor.XXXXXX") || { exec 9>&-; exec 8>&-; return 1; }
    printf '%s\n' "$$" > "$tmp" && chmod 0600 "$tmp" && mv -f -- "$tmp" "$PS5_SESSION_SUPERVISOR_PID_FILE" || {
        rm -f -- "$tmp"; exec 9>&-; exec 8>&-; return 1;
    }
    exec 9>&-
}

ps5_session_control_unregister() {
    local pid=''
    ps5_session_control_prepare || return 0
    ps5_session_control_lock || return 0
    if [[ -f "$PS5_SESSION_SUPERVISOR_PID_FILE" && ! -L "$PS5_SESSION_SUPERVISOR_PID_FILE" ]]; then
        IFS= read -r pid < "$PS5_SESSION_SUPERVISOR_PID_FILE" || true
        [[ $pid != "$$" ]] || rm -f -- "$PS5_SESSION_SUPERVISOR_PID_FILE"
    fi
    rm -f -- "$PS5_SESSION_SWITCH_FILE"
    exec 9>&-
}

ps5_session_control_request_switch() {
    local target=$1 pid tmp
    case "$target" in desktop|plasma) target=desktop;; gamescope|gamescope-wayland) target=gamescope;; *) return 2;; esac
    ps5_session_control_prepare || return 1
    ps5_session_control_lock || return 1
    [[ -f "$PS5_SESSION_SUPERVISOR_PID_FILE" && ! -L "$PS5_SESSION_SUPERVISOR_PID_FILE" ]] || { exec 9>&-; return 1; }
    IFS= read -r pid < "$PS5_SESSION_SUPERVISOR_PID_FILE" || true
    ps5_session_supervisor_is_running "$pid" || { rm -f -- "$PS5_SESSION_SUPERVISOR_PID_FILE"; exec 9>&-; return 1; }
    tmp=$(mktemp "$PS5_SESSION_CONTROL_DIR/.session-request.XXXXXX") || { exec 9>&-; return 1; }
    printf '%s\n' "$target" > "$tmp" && chmod 0600 "$tmp" && mv -f -- "$tmp" "$PS5_SESSION_SWITCH_FILE" || {
        rm -f -- "$tmp"; exec 9>&-; return 1;
    }
    exec 9>&-
}

ps5_session_control_take_request() {
    local target=''
    PS5_SESSION_SWITCH_TARGET=''
    ps5_session_control_lock || return 1
    if [[ -f "$PS5_SESSION_SWITCH_FILE" && ! -L "$PS5_SESSION_SWITCH_FILE" ]]; then
        IFS= read -r target < "$PS5_SESSION_SWITCH_FILE" || true
        rm -f -- "$PS5_SESSION_SWITCH_FILE"
    fi
    exec 9>&-
    case "$target" in desktop|gamescope) PS5_SESSION_SWITCH_TARGET=$target; return 0;; esac
    return 1
}

ps5_session_monotonic_ms() {
    local uptime seconds fraction
    IFS=' ' read -r uptime _ < "${PS5_UPTIME_FILE:-/proc/uptime}" || { printf 'unknown'; return 0; }
    if [[ "$uptime" =~ ^([0-9]+)\.([0-9]{2,})$ ]]; then
        seconds=${BASH_REMATCH[1]} fraction=${BASH_REMATCH[2]}
        fraction=${fraction:0:3}; while (( ${#fraction} < 3 )); do fraction+="0"; done
        printf '%s' "$((10#$seconds * 1000 + 10#$fraction))"
    else
        printf 'unknown'
    fi
}

ps5_session_current_id() {
    local pid=''
    if [[ -n ${PS5_SESSION_ID:-} && $PS5_SESSION_ID =~ ^[A-Za-z0-9._-]{1,128}$ ]]; then
        printf '%s' "$PS5_SESSION_ID"
        return 0
    fi
    if [[ -f $PS5_SESSION_SUPERVISOR_PID_FILE && ! -L $PS5_SESSION_SUPERVISOR_PID_FILE ]]; then
        IFS= read -r pid < "$PS5_SESSION_SUPERVISOR_PID_FILE" || true
    fi
    [[ $pid =~ ^[1-9][0-9]{0,9}$ ]] || pid=$$
    printf '%s-%s' "${PS5_SESSION_BOOT_ID:0:8}" "$pid"
}

ps5_session_log() {
    local level=$1 message=$2 file=${PS5_SESSION_LOG:-${HOME:-/home/steam}/.gamescope-session.log}
    local wall session_id monotonic
    wall=$(date -Is 2>/dev/null || date)
    session_id=$(ps5_session_current_id)
    monotonic=$(ps5_session_monotonic_ms)
    printf '[%s] session boot_id=%s session_id=%s monotonic_ms=%s %s: %s\n' \
        "$wall" "$PS5_SESSION_BOOT_ID" "$session_id" "$monotonic" "$level" "$message" >> "$file" 2>/dev/null || true
    if command -v logger >/dev/null 2>&1; then
        logger -t ps5-session -- "boot_id=$PS5_SESSION_BOOT_ID session_id=$session_id monotonic_ms=$monotonic $level: $message" 2>/dev/null || true
    fi
}
