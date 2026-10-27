#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=${1:?uso: gamescope-upstream-patch-tests.sh /percorso/gamescope-3.17.0}
PATCH="$ROOT/packaging/gamescope/patches/0001-drm-use-preferred-edid-dtd.patch"
EXPECTED_COMMIT=e6674a98118ca7b098b98a3874b8f195ae1bf750

[[ -d "$SOURCE/.git" && -f "$SOURCE/src/Backends/DRMBackend.cpp" ]] || {
    printf 'sorgente Gamescope Git non valido: %s\n' "$SOURCE" >&2
    exit 2
}
actual_commit=$(git -C "$SOURCE" rev-parse HEAD)
[[ "$actual_commit" == "$EXPECTED_COMMIT" ]] || {
    printf 'commit Gamescope non supportato: atteso %s, trovato %s\n' "$EXPECTED_COMMIT" "$actual_commit" >&2
    exit 2
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/ps5-gamescope-patch-test.XXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/src/Backends"
git -C "$SOURCE" show "$EXPECTED_COMMIT:src/Backends/DRMBackend.cpp" > "$tmp/src/Backends/DRMBackend.cpp"
git -C "$tmp" apply --check -p0 "$PATCH"
git -C "$tmp" apply -p0 "$PATCH"
rg -q 'DRM_MODE_ATOMIC_TEST_ONLY \| DRM_MODE_ATOMIC_ALLOW_MODESET' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'di_edid_get_detailed_timing_defs' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'failed atomic TEST_ONLY; keeping KMS-enumerated modes' "$tmp/src/Backends/DRMBackend.cpp"
printf 'Gamescope patch apply and fallback checks: PASS\n'
