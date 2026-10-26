#!/usr/bin/env python3
"""Tests for Gamescope's DRM mode selector against mocked KMS enumeration."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "modules/gamescope/files/ps5-gamescope-display-mode"


def modetest_output(connectors):
    lines = ["Connectors:", "id encoder status name size (mm) modes encoders"]
    for connector_id, name, connected, modes in connectors:
        status = "connected" if connected else "disconnected"
        lines.append(f"{connector_id} {connector_id + 1} {status} {name} 800x330 {len(modes)} {connector_id + 1}")
        if not connected:
            continue
        lines.extend(
            [
                "  modes:",
                "    index name refresh (Hz) hdisp hss hse htot vdisp vss vse vtot",
            ]
        )
        for index, (width, height, refresh) in enumerate(modes):
            lines.append(
                f"  #{index} {width}x{height} {refresh:.2f} {width} 0 0 0 {height} 0 0 0 0 flags: type: driver"
            )
    return "\n".join(lines) + "\n"


class GamescopeDisplayModeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ps5-gamescope-mode-test-")
        self.root = Path(self.temp.name)
        self.drm = self.root / "drm"
        self.connector = self.drm / "card0-HDMI-A-1"
        self.connector.mkdir(parents=True)
        (self.connector / "status").write_text("connected\n")
        self.mode_list = self.root / "modetest-output"
        self.fake_modetest = self.root / "modetest"
        self.fake_modetest.write_text(
            "#!/usr/bin/env bash\ncat \"$PS5_GAMESCOPE_MODETEST_OUTPUT\"\n"
        )
        self.fake_modetest.chmod(0o755)
        self.env = os.environ.copy()
        self.env["PS5_GAMESCOPE_DRM_SYSFS_ROOT"] = str(self.drm)
        self.env["PS5_GAMESCOPE_MODETEST"] = str(self.fake_modetest)
        self.env["PS5_GAMESCOPE_MODETEST_OUTPUT"] = str(self.mode_list)

    def tearDown(self):
        self.temp.cleanup()

    def set_kernel_modes(self, connectors):
        self.mode_list.write_text(modetest_output(connectors))

    def run_selector(self):
        return subprocess.run([str(HELPER)], env=self.env, capture_output=True, text=True, timeout=5)

    def test_selects_largest_kernel_mode_and_its_highest_refresh(self):
        (self.connector / "modes").write_text("1920x1080\n3440x1440\n2560x1440\n")
        self.set_kernel_modes(
            [(67, "HDMI-A-1", True, [(1920, 1080, 60), (3440, 1440, 60), (3440, 1440, 100), (2560, 1440, 144)])]
        )
        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3440\t1440\t100\tHDMI-A-1")

    def test_does_not_invent_refresh_absent_from_the_kernel_mode_list(self):
        (self.connector / "modes").write_text("3840x2160\n")
        self.set_kernel_modes([(67, "HDMI-A-1", True, [(3840, 2160, 60)])])
        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3840\t2160\t60\tHDMI-A-1")

    def test_ignores_size_exposed_by_sysfs_but_not_by_kernel_enumeration(self):
        (self.connector / "modes").write_text("3440x1440\n1920x1080\n")
        self.set_kernel_modes([(67, "HDMI-A-1", True, [(1920, 1080, 60)])])
        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "1920\t1080\t60\tHDMI-A-1")

    def test_ignores_disconnected_connector(self):
        (self.connector / "status").write_text("disconnected\n")
        (self.connector / "modes").write_text("3440x1440\n")
        self.set_kernel_modes([(67, "HDMI-A-1", False, [])])
        result = self.run_selector()
        self.assertNotEqual(result.returncode, 0)

    def test_explicit_connector_limits_candidates_and_missing_connector_fails(self):
        (self.connector / "modes").write_text("3840x2160\n")
        other = self.drm / "card0-DP-1"
        other.mkdir()
        (other / "status").write_text("connected\n")
        (other / "modes").write_text("3440x1440\n")
        self.set_kernel_modes(
            [
                (67, "HDMI-A-1", True, [(3840, 2160, 120)]),
                (70, "DP-1", True, [(3440, 1440, 100)]),
            ]
        )
        self.env["PS5_GAMESCOPE_PREFERRED_CONNECTOR"] = "DP-1"
        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "3440\t1440\t100\tDP-1")
        self.env["PS5_GAMESCOPE_PREFERRED_CONNECTOR"] = "DP-9"
        self.assertNotEqual(self.run_selector().returncode, 0)

    def test_uses_conservative_refresh_if_modetest_is_unavailable(self):
        (self.connector / "modes").write_text("2560x1440\n")
        self.env["PS5_GAMESCOPE_MODETEST"] = str(self.root / "missing-modetest")
        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "2560\t1440\t60\tHDMI-A-1")


if __name__ == "__main__":
    unittest.main(verbosity=2)
