#!/usr/bin/python3
"""Policy tests: reject unsafe solved transactions before any RPM changes."""
from contextlib import redirect_stdout
import importlib.machinery
import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest import mock

rk = importlib.machinery.SourceFileLoader('rk', str(Path(__file__).resolve().parents[1] / 'bin/rk')).load_module()


def guard_output(*args):
    if args[:2] == ('findmnt', '-rn'):
        return '42 overlay rw,relatime,upperdir=/var/lib/krisos/upper,workdir=/var/lib/krisos/work'
    if args == ('getenforce',):
        return 'Enforcing'
    if args == ('ls', '-Zd', '/usr'):
        return 'system_u:object_r:usr_t:s0 /usr'
    if args == ('rpm', '--eval', '%{_dbpath}'):
        return '/usr/lib/sysimage/rpm'
    raise AssertionError(f'unexpected command: {args!r}')


class FakeRepoConfig:
    def __init__(self, enabled):
        self.enabled = enabled
        self.pkg_gpgcheck = False


class FakeRepo:
    def __init__(self, enabled):
        self.config = FakeRepoConfig(enabled)

    def get_config(self):
        return self.config


class Policy(unittest.TestCase):
    def test_repo_hardening_preserves_admin_enabled_state(self):
        for enabled in (True, False):
            with self.subTest(enabled=enabled):
                repo = FakeRepo(enabled)
                rk.harden_repo(repo)
                self.assertEqual(repo.config.enabled, enabled)
                self.assertTrue(repo.config.pkg_gpgcheck)

    def test_plan_lock_missing_falls_back_read_only(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)):
            self.assertIsNone(rk.acquire_plan_lock())

    def test_plan_lock_uses_readonly_shared_nonblocking_lock(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)):
            path = Path(directory) / 'lock'
            path.write_text('')
            real_open = os.open
            calls = []
            def tracked_open(file, flags, *args):
                calls.append((Path(file), flags))
                return real_open(file, flags, *args)
            with mock.patch.object(rk.os, 'open', side_effect=tracked_open):
                fd = rk.acquire_plan_lock()
                try:
                    self.assertEqual(calls[0], (path, os.O_RDONLY))
                finally:
                    os.close(fd)

    def test_plan_lock_busy_has_clear_error(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)), \
                mock.patch.object(rk.fcntl, 'flock', side_effect=BlockingIOError):
            (Path(directory) / 'lock').write_text('')
            with self.assertRaisesRegex(RuntimeError, 'Another rk transaction is in progress'):
                rk.acquire_plan_lock()

    def test_all_base_actions_rejected(self):
        for action in ('Install', 'Remove', 'Upgrade', 'Downgrade', 'Reinstall', 'Replaced'):
            with self.subTest(action=action), self.assertRaises(RuntimeError):
                rk.validate_plan([('glibc', 'x86_64', action)], {'glibc'}, {'glibc'})

    def test_indirect_removal_rejected(self):
        with self.assertRaises(RuntimeError):
            rk.validate_plan([('another-app', 'x86_64', 'Remove')], set(), {'tree'})

    def test_multilib_dependency_rejected(self):
        with self.assertRaises(RuntimeError):
            rk.validate_plan([('dependency', 'i686', 'Install')], set(), set())

    def test_additive_and_explicit_remove(self):
        rk.validate_plan([('tree', 'x86_64', 'Install'), ('data', 'noarch', 'Install')], {'glibc'}, set())
        rk.validate_plan([('tree', 'x86_64', 'Remove')], {'glibc'}, {'tree'})

    def test_no_cli_escape_hatches(self):
        for name in ('--disableexcludes=all', '/tmp/a.rpm', 'https://example/a.rpm', 'a.i686', 'a*', '@group'):
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                rk.names([name])

    def test_owned_names_are_not_revalidated_as_cli_input(self):
        self.assertEqual(rk.owned_names(['ordinary', 'future.x86_64']), {'ordinary', 'future.x86_64'})
        with self.assertRaises(RuntimeError):
            rk.owned_names(['bad name'])

    def test_intent_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'packages.list'
            rk.atomic(path, 'tree\n', mode=0o644)
            rk.atomic(path, 'tree\nunzip\n', mode=0o644)
            self.assertEqual(path.read_text(), 'tree\nunzip\n')
            self.assertEqual(oct(path.stat().st_mode & 0o777), '0o644')
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ['packages.list'])

    def test_atomic_default_mode_remains_private(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'pending'
            rk.atomic(path, 'recover\n')
            self.assertEqual(oct(path.stat().st_mode & 0o777), '0o600')

    def test_guard_does_not_reconstruct_deployment_from_bootcsum(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)), \
                mock.patch.object(rk, 'output', side_effect=guard_output):
            (Path(directory) / 'deployment').write_text('default/' + 'a' * 64 + '/0\n')
            mount = rk.guard()
            self.assertTrue(mount.startswith('42 overlay '))

    def test_guard_blocks_pending_transaction_recovery(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)), \
                mock.patch.object(rk, 'output', side_effect=guard_output):
            (Path(directory) / 'pending').write_text('recover\n')
            with self.assertRaisesRegex(RuntimeError, 'Interrupted transaction requires reboot'):
                rk.guard()

    def test_status_remains_readable_during_pending_recovery(self):
        with tempfile.TemporaryDirectory() as directory, \
                mock.patch.object(rk, 'STATE', Path(directory)), \
                mock.patch.object(rk, 'output', side_effect=guard_output):
            state = Path(directory)
            (state / 'pending').write_text('recover\n')
            (state / 'needs-sync').write_text('')
            (state / 'packages.list').write_text('tree\n')
            stream = io.StringIO()
            with redirect_stdout(stream):
                rk.show_status()
            text = stream.getvalue()
            self.assertIn('Overlay: ready', text)
            self.assertIn('Pending recovery: True', text)
            self.assertIn('Needs sync: True', text)
            self.assertIn('tree', text)


if __name__ == '__main__':
    unittest.main()
