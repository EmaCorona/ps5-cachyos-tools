# Started by a TTY1 login shell; other shells and graphical terminals are untouched.
case ${PS5_TTY_SESSION_INIT:-} in 1) return 0 2>/dev/null || exit 0;; esac
PS5_TTY_SESSION_INIT=1
export PS5_TTY_SESSION_INIT
if [[ ${PS5_FORCE_TTY1:-0} != 1 ]]; then
    _ps5_tty=$(tty 2>/dev/null || true)
    [[ $_ps5_tty == /dev/tty1 && -z ${WAYLAND_DISPLAY:-} && -z ${DISPLAY:-} ]] || return 0 2>/dev/null || exit 0
fi
_ps5_supervisor=${PS5_SESSION_SUPERVISOR:-/usr/local/libexec/ps5-cachyos-tools/session-supervisor}
if [[ -x $_ps5_supervisor ]]; then
    "$_ps5_supervisor"
else
    printf 'ps5-session: supervisor mancante; login testuale disponibile su tty1\n' >&2
fi
return 0 2>/dev/null || exit 0
