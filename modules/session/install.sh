#!/usr/bin/env bash
set -u
root=$1
repo=${CORE_REPO:?}
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" || exit 1
for dir in /etc/profile.d /usr/bin /usr/local/libexec/ps5-cachyos-tools /home/steam/.config/ps5-cachyos-tools /var/lib/ps5-cachyos-tools/session/originals; do
    core_target_prepare_dir "$root" "$dir" >/dev/null || exit 1
done
copy_asset() {
    local relative=$1 destination=$2 mode=$3 source="$repo/modules/session/files/$1"
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    core_target_copy_file "$root" "$destination" "$source" && core_target_chmod "$root" "$destination" "$mode"
}
preserve_and_install() {
    local relative=$1 destination=$2 mode=$3 label=$4 target="$root$2" state="$root/var/lib/ps5-cachyos-tools/session/originals/$4.state" backup="$root/var/lib/ps5-cachyos-tools/session/originals/$4.backup"
    if [ ! -e "$state" ]; then
        [ ! -L "$target" ] || return 1
        if [ -e "$target" ]; then
            [ -f "$target" ] || return 1
            cp -a -- "$target" "$backup" || return 1
            printf 'present\n' > "$state" || return 1
        else
            printf 'absent\n' > "$state" || return 1
        fi
    fi
    copy_asset "$relative" "$destination" "$mode"
}
preserve_and_install ps5-tty-session.sh /etc/profile.d/ps5-tty-session.sh 644 profile || exit 1
preserve_and_install steamos-session-select /usr/bin/steamos-session-select 755 selector || exit 1
copy_asset session-common.sh /usr/local/libexec/ps5-cachyos-tools/session-common.sh 644 || exit 1
copy_asset session-supervisor /usr/local/libexec/ps5-cachyos-tools/session-supervisor 755 || exit 1

config="$root/home/steam/.config/ps5-cachyos-tools/session.conf"
[ -d "$root/home/steam" ] && [ ! -L "$root/home/steam" ] || exit 1
[ ! -e "$config" ] || { [ -f "$config" ] && [ ! -L "$config" ]; } || exit 1
if [ ! -e "$config" ]; then
    tmp=$(mktemp "$root/home/steam/.config/ps5-cachyos-tools/.session.conf.XXXXXX") || exit 1
    default=desktop
    legacy="$root/home/steam/.config/ps5-next-session"
    if [ -f "$legacy" ] && [ ! -L "$legacy" ]; then
        IFS= read -r legacy_value < "$legacy" || true
        case "$legacy_value" in desktop|plasma) default=desktop;; gamescope|gamescope-wayland) default=gamescope;; esac
    fi
    printf 'DEFAULT_SESSION=%s\nNEXT_SESSION=\n' "$default" > "$tmp" || { rm -f -- "$tmp"; exit 1; }
    chmod 0600 "$tmp" && mv -f -- "$tmp" "$config" || { rm -f -- "$tmp"; exit 1; }
    ids=$(awk -F: '$1 == "steam" { print $3 ":" $4; exit }' "$root/etc/passwd" 2>/dev/null)
    [[ "$ids" =~ ^[0-9]+:[0-9]+$ ]] || exit 1
    chown "$ids" "$config" || exit 1
fi
exit 0
