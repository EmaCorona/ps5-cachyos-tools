#!/usr/bin/env bash
set -u

root=$1; state="$root/run/ps5-cachyos-tools/boot-cleanup/cleanup.state"
[ -f "$state" ] && [ ! -L "$state" ] || exit 1
grep -Eq '^checked=[0-9]+$' "$state" && grep -Eq '^removed=[0-9]+$' "$state" && grep -Eq '^active=[0-9]+$' "$state" && grep -Eq '^rejected=[0-9]+$' "$state" || exit 1
