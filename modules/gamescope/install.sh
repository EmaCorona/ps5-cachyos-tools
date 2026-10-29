#!/usr/bin/env bash
set -u
root=$1
repo=${CORE_REPO:?}
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" || exit 1
if [ ! -x "$root/usr/bin/python3" ]; then
    printf 'dipendenza Gamescope mancante: /usr/bin/python3 richiesto per la verifica in-process dei manifesti Steam\n' >&2
    exit 1
fi
for dir in /etc/ps5-cachyos-tools /usr/local/bin /usr/local/libexec/ps5-cachyos-tools /usr/share/xdg-desktop-portal /var/lib/ps5-cachyos-tools/gamescope/originals; do
    core_target_prepare_dir "$root" "$dir" >/dev/null || exit 1
done
copy_asset() {
    local relative=$1 destination=$2 mode=$3 source="$repo/modules/gamescope/files/$1"
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    core_target_copy_file "$root" "$destination" "$source" && core_target_chmod "$root" "$destination" "$mode"
}
copy_asset gamescope-session-ps5 /usr/local/libexec/ps5-cachyos-tools/gamescope-session 755 || exit 1
copy_asset ps5-gamescope-package /usr/local/libexec/ps5-cachyos-tools/gamescope-package 755 || exit 1
copy_asset ps5-gamescope-display-mode /usr/local/bin/ps5-cachyos-tools-gamescope-display-mode 755 || exit 1
copy_asset ps5-video-diag /usr/local/bin/ps5-cachyos-tools-video-diag 755 || exit 1
copy_asset ps5-steam-verify-repair /usr/local/bin/ps5-cachyos-tools-steam-verify-repair 755 || exit 1
copy_asset ps5-drm-setup /usr/local/bin/ps5-cachyos-tools-drm-setup 755 || exit 1
portal="$root/usr/share/xdg-desktop-portal/gamescope-portals.conf"
portal_state="$root/var/lib/ps5-cachyos-tools/gamescope/originals/portal.state"
portal_backup="$root/var/lib/ps5-cachyos-tools/gamescope/originals/portal.backup"
if [ ! -e "$portal_state" ]; then
    [ ! -L "$portal" ] || exit 1
    if [ -e "$portal" ]; then cp -a -- "$portal" "$portal_backup" && printf 'present\n' > "$portal_state" || exit 1; else printf 'absent\n' > "$portal_state" || exit 1; fi
fi
copy_asset gamescope-portals.conf /usr/share/xdg-desktop-portal/gamescope-portals.conf 644 || exit 1
config="$root/etc/ps5-cachyos-tools/gamescope.conf"
if [ ! -e "$config" ]; then
    tmp=$(mktemp "$root/etc/ps5-cachyos-tools/.gamescope.conf.XXXXXX") || exit 1
    cat > "$tmp" <<'EOF'
# Override DRM/EDID auto-detection only when the display requires it.
# PS5_OUTPUT_WIDTH=1920
# PS5_OUTPUT_HEIGHT=1080
# PS5_NESTED_WIDTH=1920
# PS5_NESTED_HEIGHT=1080
# PS5_REFRESH_RATE=60
# PS5_OUTPUT_CONN=DP-1
# PS5_DRM_DIAGNOSTICS=1
EOF
    chmod 0644 "$tmp" && mv -f -- "$tmp" "$config" || { rm -f -- "$tmp"; exit 1; }
fi
[ -f "$config" ] && [ ! -L "$config" ] || exit 1
exit 0
