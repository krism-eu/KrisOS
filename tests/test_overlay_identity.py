#!/usr/bin/python3
"""Verify overlay invalidation keys off the real OSTree deployment commit."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).resolve().parents[1] / "systemd/krisos-overlay.sh"
BOOTCSUM = "b" * 64
OLD_COMMIT = "a" * 64
NEW_COMMIT = "c" * 64


class OverlayIdentity(unittest.TestCase):
    def prepare(self, saved_commit, target_commit, deployserial="0", chcon_status=0, mount_status=0):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)

        ostree = root / "ostree"
        bootlink = ostree / "boot.0" / "default" / BOOTCSUM / "0"
        bootlink.parent.mkdir(parents=True)
        bootlink.symlink_to(f"../../../../deploy/default/deploy/{target_commit}.{deployserial}")

        cmdline = root / "cmdline"
        cmdline.write_text(f"quiet ostree={bootlink}\n")
        mounts = root / "mounts"
        mounts.write_text("")

        state = root / "state"
        upper = state / "upper"
        work = state / "work"
        upper.mkdir(parents=True)
        work.mkdir(parents=True)
        sentinel = upper / "sentinel"
        sentinel.write_text("keep-or-wipe")
        (state / "deployment").write_text(f"default/{saved_commit}/0\n")
        runtime = root / "run" / "krisos"

        bindir = root / "bin"
        bindir.mkdir()
        for name, status in (("chcon", chcon_status), ("mount", mount_status)):
            stub = bindir / name
            stub.write_text(f"#!/bin/sh\nexit {status}\n")
            stub.chmod(0o755)

        hook = root / "hook.sh"
        text = SOURCE.read_text()
        text = text.replace("/proc/cmdline", str(cmdline))
        text = text.replace("/proc/mounts", str(mounts))
        text = text.replace("/ostree/", str(ostree) + "/")
        text = text.replace("state=/var/lib/krisos", f"state={state}")
        text = text.replace("runtime=/run/krisos", f"runtime={runtime}")
        hook.write_text(text)
        hook.chmod(0o755)

        env = dict(os.environ)
        env["PATH"] = f"{bindir}:/usr/bin:/bin"
        result = subprocess.run(
            ["/bin/bash", str(hook)], env=env, text=True, capture_output=True
        )
        return result, state, sentinel, runtime

    def test_same_boot_checksum_new_commit_wipes_cache(self):
        result, state, sentinel, runtime = self.prepare(OLD_COMMIT, NEW_COMMIT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("deployment changed — wiping overlay cache", result.stdout)
        self.assertFalse(sentinel.exists())
        self.assertTrue((state / "needs-sync").exists())
        self.assertTrue((runtime / "overlay-mounted").exists())
        self.assertEqual(
            (state / "deployment").read_text().strip(), f"default/{NEW_COMMIT}/0"
        )

    def test_same_deployment_preserves_cache(self):
        result, state, sentinel, runtime = self.prepare(NEW_COMMIT, NEW_COMMIT)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("wiping overlay cache", result.stdout)
        self.assertTrue(sentinel.exists())
        self.assertFalse((state / "needs-sync").exists())
        self.assertTrue((runtime / "overlay-mounted").exists())
        self.assertEqual(
            (state / "deployment").read_text().strip(), f"default/{NEW_COMMIT}/0"
        )

    def test_identity_uses_deploy_serial_from_bootlink_target(self):
        result, state, _, runtime = self.prepare(OLD_COMMIT, NEW_COMMIT, deployserial="7")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((runtime / "overlay-mounted").exists())
        self.assertEqual(
            (state / "deployment").read_text().strip(), f"default/{NEW_COMMIT}/7"
        )

    def test_chcon_failure_keeps_recovery_intent_but_not_ready_marker(self):
        result, state, _, runtime = self.prepare(OLD_COMMIT, NEW_COMMIT, chcon_status=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("cannot label overlay root", result.stdout)
        self.assertTrue((state / "needs-sync").exists())
        self.assertFalse((runtime / "overlay-mounted").exists())
        self.assertEqual((state / "deployment").read_text().strip(), f"default/{OLD_COMMIT}/0")

    def test_mount_failure_keeps_recovery_intent_but_not_ready_marker(self):
        result, state, _, runtime = self.prepare(OLD_COMMIT, NEW_COMMIT, mount_status=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("overlay mount failed", result.stdout)
        self.assertTrue((state / "needs-sync").exists())
        self.assertFalse((runtime / "overlay-mounted").exists())
        self.assertEqual((state / "deployment").read_text().strip(), f"default/{OLD_COMMIT}/0")


if __name__ == "__main__":
    unittest.main()
