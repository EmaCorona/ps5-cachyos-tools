#!/usr/bin/env python3
"""Focused tests for automatic KDE display mode selection."""

import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "modules/kde/files/ps5-kde-display-mode"
loader = importlib.machinery.SourceFileLoader("kde_display_mode", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
display_mode = importlib.util.module_from_spec(spec)
loader.exec_module(display_mode)


def make_edid(hblank=160):
    block = bytearray(128)
    block[:8] = b"\x00\xff\xff\xff\xff\xff\xff\x00"
    block[54:72] = bytes(
        [
            0x4E, 0xD4, 0x70, hblank & 0xFF, 0xD0 | ((hblank >> 8) & 0x0F),
            0xA0, 70, 0x50, 48, 64, 0x3A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
    )
    block[126] = 0
    block[127] = (-sum(block[:127])) & 0xFF
    return bytes(block)


def initial_state():
    return {
        "outputs": [
            {
                "name": "DP-1",
                "connected": True,
                "enabled": True,
                "currentModeId": "1",
                "modes": [
                    {"id": "1", "name": "2560x1440@60", "refreshRate": 59.95, "size": {"width": 2560, "height": 1440}},
                    {"id": "2", "name": "1920x1080@60", "refreshRate": 60.0, "size": {"width": 1920, "height": 1080}},
                    {"id": "3", "name": "1920x1080i@60", "refreshRate": 60.0, "size": {"width": 1920, "height": 1080}},
                    {"id": "4", "name": "1920x1080@60 interlaced", "refreshRate": 60.0, "size": {"width": 1920, "height": 1080}, "interlaced": True},
                ],
            }
        ]
    }


FAKE_KSCREEN = r'''#!/usr/bin/env python3
import json, os, sys
state_path = os.environ["FAKE_KSCREEN_STATE"]
trace_path = os.environ["FAKE_KSCREEN_TRACE"]
with open(state_path) as f: state = json.load(f)
arg = sys.argv[1] if len(sys.argv) > 1 else ""
if arg == "--json":
    print(json.dumps(state))
    raise SystemExit(0)
with open(trace_path, "a") as f: f.write(arg + "\n")
out = state["outputs"][0]
if ".addCustomMode." in arg:
    parts = arg.split(".addCustomMode.", 1)[1].split(".")
    width, height, rate = int(parts[0]), int(parts[1]), int(parts[2]) / 1000
    out["modes"].append({"id": "5", "name": f"{width}x{height}@{rate}", "refreshRate": 99.936,
                         "size": {"width": width, "height": height}})
elif arg.endswith(".mode.5"):
    if os.environ.get("FAKE_KSCREEN_IGNORE_MODE") != "1":
        out["currentModeId"] = "2" if os.environ.get("FAKE_KSCREEN_APPLY_WRONG_MODE") == "1" else "5"
elif arg.endswith(".mode.1"):
    if os.environ.get("FAKE_KSCREEN_IGNORE_RESTORE") != "1": out["currentModeId"] = "1"
with open(state_path, "w") as f: json.dump(state, f)
'''


class KdeDisplayModeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ps5-kde-mode-test-")
        self.base = Path(self.temp.name)
        self.drm = self.base / "drm"
        connector = self.drm / "card0-DP-1"
        connector.mkdir(parents=True)
        display_mode.DRM_ROOT = str(self.drm)
        self.edid_path = connector / "edid"
        self.edid_path.write_bytes(make_edid())
        self.state_path = self.base / "state.json"
        self.state_path.write_text(json.dumps(initial_state()))
        self.trace_path = self.base / "trace"
        self.fake = self.base / "kscreen-doctor"
        self.fake.write_text(FAKE_KSCREEN)
        self.fake.chmod(0o755)

    def tearDown(self):
        self.temp.cleanup()

    def run_helper(self, ignore_mode=False, wrong_mode=False, ignore_restore=False):
        env = os.environ.copy()
        env.update(
            PS5_KSCREEN_DOCTOR=str(self.fake),
            PS5_KDE_DRM_SYSFS_ROOT=str(self.drm),
            FAKE_KSCREEN_STATE=str(self.state_path),
            FAKE_KSCREEN_TRACE=str(self.trace_path),
        )
        if ignore_mode:
            env["FAKE_KSCREEN_IGNORE_MODE"] = "1"
        if wrong_mode:
            env["FAKE_KSCREEN_APPLY_WRONG_MODE"] = "1"
        if ignore_restore:
            env["FAKE_KSCREEN_IGNORE_RESTORE"] = "1"
        result = subprocess.run([str(HELPER)], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(self.state_path.read_text()), self.trace_path.read_text() if self.trace_path.exists() else ""

    def test_parses_advertised_edid_timing_and_checksum(self):
        mode = display_mode.parse_dtd(make_edid()[54:72], 0)
        self.assertIsNotNone(mode)
        self.assertEqual(mode[:2], (3440, 1440))
        self.assertAlmostEqual(mode[2], 99.982, delta=0.02)
        bad_edid = bytearray(make_edid())
        bad_edid[127] ^= 0x01
        self.edid_path.write_bytes(bad_edid)
        self.assertEqual(display_mode.edid_modes("DP-1"), set())

    def test_rejects_non_reduced_blanking_edid_and_interlaced_modes(self):
        self.edid_path.write_bytes(make_edid(hblank=200))
        self.assertEqual(display_mode.edid_modes("DP-1"), set())
        modes = display_mode.listed_modes(initial_state()["outputs"][0])
        self.assertEqual([mode["id"] for mode in modes], ["1", "2"])

    def test_adds_and_selects_best_advertised_mode(self):
        state, trace = self.run_helper()
        self.assertEqual(state["outputs"][0]["currentModeId"], "5")
        self.assertIn("output.DP-1.addCustomMode.3440.1440.99982.reduced", trace)
        self.assertIn("output.DP-1.mode.5", trace)

    def test_rolls_back_when_kscreen_does_not_apply_requested_mode(self):
        state, trace = self.run_helper(ignore_mode=True)
        self.assertEqual(state["outputs"][0]["currentModeId"], "1")
        self.assertIn("output.DP-1.mode.5", trace)
        self.assertIn("output.DP-1.mode.1", trace)

    def test_restores_previous_mode_after_wrong_mode_was_applied(self):
        state, trace = self.run_helper(wrong_mode=True)
        self.assertEqual(state["outputs"][0]["currentModeId"], "1")
        self.assertIn("output.DP-1.mode.5", trace)
        self.assertIn("output.DP-1.mode.1", trace)

    def test_logs_when_previous_mode_cannot_be_restored(self):
        env = os.environ.copy()
        env.update(
            PS5_KSCREEN_DOCTOR=str(self.fake),
            PS5_KDE_DRM_SYSFS_ROOT=str(self.drm),
            FAKE_KSCREEN_STATE=str(self.state_path),
            FAKE_KSCREEN_TRACE=str(self.trace_path),
            FAKE_KSCREEN_APPLY_WRONG_MODE="1",
            FAKE_KSCREEN_IGNORE_RESTORE="1",
        )
        result = subprocess.run([str(HELPER)], env=env, capture_output=True, text=True, timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.state_path.read_text())["outputs"][0]["currentModeId"], "2")
        self.assertIn("ripristino non verificato", result.stderr)

    def test_uses_highest_kscreen_mode_when_edid_is_unavailable(self):
        self.edid_path.write_bytes(b"")
        state = initial_state()
        state["outputs"][0]["currentModeId"] = "2"
        self.state_path.write_text(json.dumps(state))
        final_state, trace = self.run_helper()
        self.assertEqual(final_state["outputs"][0]["currentModeId"], "1")
        self.assertIn("output.DP-1.mode.1", trace)
        self.assertNotIn("addCustomMode", trace)


if __name__ == "__main__":
    unittest.main(verbosity=2)
