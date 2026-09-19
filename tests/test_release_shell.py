#!/usr/bin/python3
"""Execute the shell paths that previously lost home/admin arguments."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ReleaseShell(unittest.TestCase):
    def test_home_check_passes_the_actual_home_to_readlink(self):
        line = next(line for line in (ROOT / 'tests/release-check.sh').read_text().splitlines() if 'run_check "admin home resolves below /var/home"' in line)
        with tempfile.TemporaryDirectory() as directory:
            stub = Path(directory) / 'readlink'
            stub.write_text('#!/bin/sh\n[ "$1" = -f ] || exit 1\n[ "$2" = -- ] || exit 1\n[ "$3" = /home/qa ] || exit 1\nprintf "%s\\n" /var/home/qa\n')
            stub.chmod(0o755)
            script = 'run_check() { shift; "$@"; }\nadmin_home=/home/qa\nexpected_admin_user=qa\n' + line
            result = subprocess.run(['bash', '-c', script], env={**os.environ, 'PATH': directory + ':' + os.environ['PATH']}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_vm_harness_transmits_admin_user(self):
        source = (ROOT / 'tests/run-release-vm.sh').read_text()
        function = re.search(r'run_release_check\(\) \{.*?\n\}', source, re.S).group()
        script = '''ssh() { printf '%s\\n' "$@"; }
ssh_opts=()
target=qa@example
expected_kriscc=version
expected_image=image
expected_admin_user=desktop
token=token
remote_dir=/tmp/qa
''' + function + '\nrun_release_check check\n'
        result = subprocess.run(['bash', '-c', script], capture_output=True, text=True, check=True)
        self.assertIn("KRISOS_EXPECT_ADMIN_USER='desktop'", result.stdout)


if __name__ == '__main__':
    unittest.main()
