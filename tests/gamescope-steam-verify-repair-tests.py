#!/usr/bin/env python3
"""Regression tests for the in-process Steam manifest verifier."""

from __future__ import annotations

import contextlib
import errno
import importlib.machinery
import importlib.util
import io
import os
import re
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "modules/gamescope/files/ps5-steam-verify-repair"
loader = importlib.machinery.SourceFileLoader("steam_verify_repair", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
repair = importlib.util.module_from_spec(spec)
loader.exec_module(repair)


class SteamVerifyRepairTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="ps5-steam-verify-")
        self.root = Path(self.temp.name)
        self.steam = self.root / "Steam"
        self.package = self.steam / "package"
        self.package.mkdir(parents=True)
        self.data = self.steam / "appcache"
        self.data.mkdir()

    def tearDown(self) -> None:
        self.temp.cleanup()

    def manifest(self, name: str, *lines: str) -> Path:
        path = self.package / name
        path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        return path

    def run_helper(self) -> tuple[int, str, str]:
        stdout = io.StringIO()
        stderr = io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            rc = repair.run(str(self.steam))
        return rc, stdout.getvalue(), stderr.getvalue()

    def test_valid_formats_metadata_and_symlink_target_are_preserved(self) -> None:
        payload = self.data / "valid.bin"
        payload.write_bytes(b"1234")
        link = self.data / "link.bin"
        link.symlink_to(payload)
        marker = self.manifest(
            "steam_client_ubuntu12.installed",
            "SIGNATURE:ignored",
            "OSVER=ignored",
            "appcache/valid.bin,4;0;0",
            "appcache/link.bin\tsize=4\tother=ignored",
            "unsupported metadata row",
        )

        rc, stdout, stderr = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")
        self.assertIn("records=2", stderr)
        self.assertTrue(marker.is_file())
        self.assertEqual(payload.read_bytes(), b"1234")

    def test_confirmed_missing_file_and_size_mismatch_remove_only_own_markers(self) -> None:
        payload = self.data / "wrong.bin"
        payload.write_bytes(b"abc")
        bad_size = self.manifest("steam_a.installed", "appcache/wrong.bin,9;0;0")
        absent = self.manifest("steam_b.installed", "appcache/absent.bin,9;0;0")
        valid = self.manifest("steam_c.installed", "appcache/wrong.bin,3;0;0")

        rc, stdout, _ = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 2")
        self.assertFalse(bad_size.exists())
        self.assertFalse(absent.exists())
        self.assertTrue(valid.is_file())
        self.assertEqual(payload.read_bytes(), b"abc")

    def test_absolute_traversal_and_malformed_rows_do_not_touch_files(self) -> None:
        outside = self.root / "outside.bin"
        outside.write_bytes(b"abc")
        marker = self.manifest(
            "steam_invalid_rows.installed",
            f"{outside},99;0;0",
            "../outside.bin,99;0;0",
            "appcache/../../outside.bin,99;0;0",
            "appcache/no-size,not-a-number;0;0",
        )

        rc, stdout, _ = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")
        self.assertTrue(marker.is_file())
        self.assertEqual(outside.read_bytes(), b"abc")

    def test_symlink_manifest_is_skipped(self) -> None:
        (self.data / "present.bin").write_bytes(b"x")
        target = self.manifest("target.installed", "appcache/present.bin,1;0;0")
        link = self.package / "linked.installed"
        link.symlink_to(target)

        rc, stdout, _ = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertTrue(target.is_file())
        self.assertTrue(link.is_symlink())
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")
        self.assertTrue(target.exists())

    def test_non_regular_manifest_is_skipped_without_blocking(self) -> None:
        fifo = self.package / "steam_fifo.installed"
        os.mkfifo(fifo)

        rc, stdout, _ = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertTrue(fifo.exists())
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")

    def test_unknown_stat_error_is_fail_open_and_prevents_all_marker_changes(self) -> None:
        missing_marker = self.manifest("steam_missing.installed", "appcache/not-here.bin,1;0;0")
        io_marker = self.manifest("steam_io.installed", "appcache/io.bin,1;0;0")
        (self.data / "io.bin").write_bytes(b"x")
        original_stat = os.stat

        def stat_with_io_error(path, *args, **kwargs):
            if os.fspath(path) == str(self.data / "io.bin"):
                raise OSError(errno.EIO, "simulated I/O error", os.fspath(path))
            return original_stat(path, *args, **kwargs)

        with mock.patch.object(repair.os, "stat", side_effect=stat_with_io_error):
            rc, stdout, stderr = self.run_helper()

        self.assertEqual(rc, 1)
        self.assertTrue(missing_marker.is_file())
        self.assertTrue(io_marker.is_file())
        self.assertIn("EIO", stderr)
        self.assertIn("errors=1", stderr)
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")

    def test_permission_error_is_not_treated_as_missing(self) -> None:
        payload = self.data / "restricted.bin"
        payload.write_bytes(b"x")
        marker = self.manifest("steam_permission.installed", "appcache/restricted.bin,1;0;0")
        original_stat = os.stat

        def stat_with_permission_error(path, *args, **kwargs):
            if os.fspath(path) == str(payload):
                raise PermissionError(errno.EACCES, "simulated permission error", os.fspath(path))
            return original_stat(path, *args, **kwargs)

        with mock.patch.object(repair.os, "stat", side_effect=stat_with_permission_error):
            rc, _, stderr = self.run_helper()

        self.assertEqual(rc, 1)
        self.assertTrue(marker.is_file())
        self.assertIn("EACCES", stderr)

    def test_race_to_enoent_invalidates_only_marker(self) -> None:
        payload = self.data / "raced.bin"
        payload.write_bytes(b"x")
        marker = self.manifest("steam_race.installed", "appcache/raced.bin,1;0;0")
        original_stat = os.stat

        def stat_after_disappearance(path, *args, **kwargs):
            if os.fspath(path) == str(payload):
                raise FileNotFoundError(errno.ENOENT, "simulated race", os.fspath(path))
            return original_stat(path, *args, **kwargs)

        with mock.patch.object(repair.os, "stat", side_effect=stat_after_disappearance):
            rc, stdout, _ = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertFalse(marker.exists())
        self.assertTrue(payload.is_file())
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 1")

    def test_large_fixture_reports_all_records_without_external_stat_loop(self) -> None:
        count = 13_526
        manifest = self.package / "steam_large.installed"
        with manifest.open("w", encoding="ascii") as stream:
            for index in range(count):
                name = f"asset-{index:05d}.bin"
                (self.data / name).write_bytes(b"x")
                stream.write(f"appcache/{name},1;0;0\n")

        rc, stdout, stderr = self.run_helper()

        self.assertEqual(rc, 0)
        self.assertTrue(manifest.is_file())
        self.assertEqual(stdout.strip(), "Manifest Steam non validi rilevati: 0")
        self.assertRegex(stderr, rf"manifests=1 records={count} files={count} invalid=0 errors=0 elapsed_ms=[0-9.]+")


if __name__ == "__main__":
    unittest.main(verbosity=2)
