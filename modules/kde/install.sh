#!/usr/bin/env bash
set -u

root=$1
repo=${CORE_REPO:?}
source "$root/usr/lib/ps5-cachyos-tools/core/target.sh" || exit 1

for dir in /etc/profile.d /etc/xdg/autostart /usr/local/bin /var/lib/ps5-cachyos-tools/kde; do
    core_target_prepare_dir "$root" "$dir" >/dev/null || exit 1
done

copy_asset() {
    local relative=$1 destination=$2 mode=$3 source="$repo/modules/kde/files/$1"
    [ -f "$source" ] && [ ! -L "$source" ] || return 1
    core_target_copy_file "$root" "$destination" "$source" && core_target_chmod "$root" "$destination" "$mode"
}

copy_asset ps5-kde-environment.sh /etc/profile.d/ps5-kde-environment.sh 644 || exit 1
copy_asset ps5-desktop-notify /usr/local/bin/ps5-cachyos-tools-desktop-notify 755 || exit 1
copy_asset ps5-desktop-notify.desktop /etc/xdg/autostart/ps5-cachyos-tools-desktop-notify.desktop 644 || exit 1

group_file="$root/etc/group"
added_file="$root/var/lib/ps5-cachyos-tools/kde/added-groups"
[ -f "$group_file" ] && [ ! -L "$group_file" ] || exit 1
[ ! -e "$added_file" ] || { [ -f "$added_file" ] && [ ! -L "$added_file" ]; } || exit 1
tmp=$(mktemp "$root/etc/.group.ps5-kde.XXXXXX") || exit 1
added_tmp=$(mktemp "$root/var/lib/ps5-cachyos-tools/kde/.added-groups.XXXXXX") || { rm -f -- "$tmp"; exit 1; }
if [ -f "$added_file" ]; then cat -- "$added_file" > "$added_tmp" || { rm -f -- "$tmp" "$added_tmp"; exit 1; }; fi

for group in render video seat input; do
    awk -F: -v group="$group" '$1 == group { found=1; n=split($4, members, ","); for (i=1; i<=n; i++) if (members[i] == "steam") present=1 } END { if (found) exit (present ? 0 : 1); exit 2 }' "$group_file"
    membership=$?
    [ "$membership" -eq 0 ] && continue
    [ "$membership" -eq 2 ] && continue
    awk -F: -v group="$group" 'BEGIN { OFS=":" } $1 == group { if ($4 == "") $4="steam"; else $4=$4 ",steam" } { print }' "$group_file" > "$tmp" || { rm -f -- "$tmp" "$added_tmp"; exit 1; }
    chmod --reference="$group_file" "$tmp" && chown --reference="$group_file" "$tmp" && mv -f -- "$tmp" "$group_file" || { rm -f -- "$tmp" "$added_tmp"; exit 1; }
    grep -Fxq -- "$group" "$added_tmp" || printf '%s\n' "$group" >> "$added_tmp" || { rm -f -- "$added_tmp"; exit 1; }
done
chmod 0600 "$added_tmp" && mv -f -- "$added_tmp" "$added_file" || { rm -f -- "$tmp" "$added_tmp"; exit 1; }
exit 0
