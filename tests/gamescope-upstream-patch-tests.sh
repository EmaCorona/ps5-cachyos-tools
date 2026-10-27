#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SOURCE=${1:?uso: gamescope-upstream-patch-tests.sh /percorso/gamescope-3.17.0}
PATCH="$ROOT/packaging/gamescope/0001-drm-use-preferred-edid-dtd.patch"
PKGBUILD="$ROOT/packaging/gamescope/PKGBUILD"
EXPECTED_COMMIT=e6674a98118ca7b098b98a3874b8f195ae1bf750

rg -q '^  patch -Np0 -i "\$srcdir/0001-drm-use-preferred-edid-dtd\.patch"$' "$PKGBUILD" || {
    printf 'PKGBUILD non applica la patch con il livello di strip coerente con i suoi header\n' >&2
    exit 1
}
rg -q '^  install -Dm 755 build/src/gamescope "\$\{private_root\}/bin/gamescope"$' "$PKGBUILD" || {
    printf 'PKGBUILD non installa il binario dalla directory di build di Meson\n' >&2
    exit 1
}

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
cp "$ROOT/packaging/gamescope/EDIDModeSelection.h" "$tmp/src/Backends/EDIDModeSelection.h"
git -C "$tmp" apply --check -p0 "$PATCH"
git -C "$tmp" apply -p0 "$PATCH"
rg -q 'DRM_MODE_ATOMIC_TEST_ONLY \| DRM_MODE_ATOMIC_ALLOW_MODESET' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'di_edid_get_detailed_timing_defs' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'for \( size_t i = 0; pTimings\[i\]; i\+\+ \)' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'FindFirstUsableEDIDMode' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'FindFirstUsableEDIDMode' "$tmp/src/Backends/EDIDModeSelection.h"
rg -q 'std::vector<drmModeModeInfo> m_EdidModes' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'm_EdidModes.clear\(\)' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'failed atomic TEST_ONLY; trying the next candidate' "$tmp/src/Backends/DRMBackend.cpp"
rg -q 'return mode;' "$tmp/src/Backends/DRMBackend.cpp"
printf 'Gamescope patch apply, all-EDID-mode iteration, hotplug refresh, and KMS fallback checks: PASS\n'
