#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CXX=${CXX:-g++}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/ps5-gamescope-edid-select.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
"$CXX" -std=c++20 -Wall -Wextra -Werror "$ROOT/tests/gamescope-edid-mode-selection-tests.cpp" -o "$tmp/edid-mode-selection-tests"
"$tmp/edid-mode-selection-tests"
printf 'Gamescope EDID candidate order and fallback behavior: PASS\n'
