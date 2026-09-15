#!/usr/bin/python3
"""Policy tests: reject unsafe solved transactions before any RPM changes."""
import importlib.machinery
from pathlib import Path
import tempfile
import unittest

rk = importlib.machinery.SourceFileLoader('rk', str(Path(__file__).resolve().parents[1] / 'bin/rk')).load_module()


class Policy(unittest.TestCase):
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

    def test_intent_atomic_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'packages.list'
            rk.atomic(path, 'tree\n')
            rk.atomic(path, 'tree\nunzip\n')
            self.assertEqual(path.read_text(), 'tree\nunzip\n')
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ['packages.list'])


if __name__ == '__main__':
    unittest.main()
