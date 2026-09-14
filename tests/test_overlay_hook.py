"""Unprivileged hook control-flow tests; SELinux/mounts still need the M0 VM."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


HOOK = Path(__file__).resolve().parents[1] / "dracut/modules.d/90raku-kris/raku-kris-overlay.sh"
IDENTITY = "default/" + "a" * 64 + "/0"


class OverlayHookTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sysroot = self.root / "sysroot"
        (self.sysroot / "usr").mkdir(parents=True)
        self.state = self.sysroot / "ostree/deploy/default/var/lib/raku-kris"
        self.state.mkdir(parents=True)
        cmdline = self.root / "cmdline"
        cmdline.write_text("ostree=/ostree/boot.0/" + IDENTITY + "\n")
        mounts = self.root / "mounts"
        mounts.write_text("")
        self.hook = self.root / "hook.sh"
        # Redirect only host paths; execute the production control flow.
        self.hook.write_text(HOOK.read_text().replace(
            "/proc/cmdline", str(cmdline)).replace(
            "/proc/mounts", str(mounts)).replace(
            "sysroot=/sysroot", "sysroot=" + str(self.sysroot)))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls"
        self.env = dict(os.environ, PATH=str(self.bin) + ":" + os.environ["PATH"],
                        RK_CALLS=str(self.calls), RK_STATE=str(self.state))
        self.stub("chcon", 'printf "label\\n" >> "$RK_CALLS"\nexit "${RK_LABEL_EXIT:-0}"\n')
        self.stub("mount", 'printf "mount\\n" >> "$RK_CALLS"\nexit "${RK_MOUNT_EXIT:-0}"\n')

    def stub(self, name, body):
        script = self.bin / name
        script.write_text("#!/bin/bash\n" + body)
        script.chmod(0o755)

    def run_hook(self, **env):
        result = subprocess.run(["bash", str(self.hook)], env=dict(self.env, **env),
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def test_first_boot_labels_before_mount_and_records_identity(self):
        self.run_hook()
        self.assertEqual(self.calls.read_text(), "label\nmount\n")
        self.assertEqual((self.state / "deployment").read_text(), IDENTITY + "\n")
        self.assertTrue((self.state / "needs-sync").exists())

    def test_label_failure_does_not_mount_or_record_identity(self):
        output = self.run_hook(RK_LABEL_EXIT="1")
        self.assertIn("cannot label overlay root", output)
        self.assertEqual(self.calls.read_text(), "label\n")
        self.assertFalse((self.state / "deployment").exists())

    def test_reused_cache_is_labelled_without_losing_payload(self):
        (self.state / "deployment").write_text(IDENTITY + "\n")
        (self.state / "upper").mkdir()
        payload = self.state / "upper/keep-me"
        payload.write_text("payload")
        self.run_hook()
        self.assertEqual(self.calls.read_text(), "label\nmount\n")
        self.assertEqual(payload.read_text(), "payload")
        self.assertFalse((self.state / "needs-sync").exists())

    def test_label_failure_preserves_reused_payload(self):
        (self.state / "deployment").write_text(IDENTITY + "\n")
        (self.state / "upper").mkdir()
        payload = self.state / "upper/keep-me"
        payload.write_text("payload")
        self.run_hook(RK_LABEL_EXIT="1")
        self.assertEqual(self.calls.read_text(), "label\n")
        self.assertEqual(payload.read_text(), "payload")

    def test_mount_failure_does_not_record_identity(self):
        self.run_hook(RK_MOUNT_EXIT="1")
        self.assertFalse((self.state / "deployment").exists())


if __name__ == "__main__":
    unittest.main()
