#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CXX=${CXX:-g++}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ps5-gamescope-edid-select.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
if ! command -v "$CXX" >/dev/null 2>&1; then
    printf 'Gamescope EDID candidate order and fallback behavior: SKIP (compiler %s unavailable)\n' "$CXX"
    exit 77
fi
"$CXX" -std=c++20 -Wall -Wextra -Werror "$ROOT/tests/gamescope-edid-mode-selection-tests.cpp" -o "$tmp/edid-mode-selection-tests"
"$tmp/edid-mode-selection-tests"
printf 'Gamescope EDID candidate order and fallback behavior: PASS\n'
