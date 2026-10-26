#!/usr/bin/env bash
set -u
root=$1
added_file="$root/var/lib/ps5-cachyos-tools/kde/added-groups"
group_file="$root/etc/group"
[ ! -e "$added_file" ] && exit 0
[ -f "$added_file" ] && [ ! -L "$added_file" ] && [ -f "$group_file" ] && [ ! -L "$group_file" ] || exit 1
while IFS= read -r group; do
    case "$group" in render|video|seat|input) ;; *) exit 1 ;; esac
    tmp=$(mktemp "$root/etc/.group.ps5-kde-remove.XXXXXX") || exit 1
    awk -F: -v group="$group" 'BEGIN { OFS=":" } $1 == group { n=split($4, members, ","); out=""; for (i=1; i<=n; i++) if (members[i] != "steam") out=(out == "" ? members[i] : out "," members[i]); $4=out } { print }' "$group_file" > "$tmp" || { rm -f -- "$tmp"; exit 1; }
    chmod --reference="$group_file" "$tmp" && chown --reference="$group_file" "$tmp" && mv -f -- "$tmp" "$group_file" || { rm -f -- "$tmp"; exit 1; }
done < "$added_file"
rm -f -- "$added_file"
exit 0
