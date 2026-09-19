#!/usr/bin/python3
import importlib.machinery
from pathlib import Path
import unittest

state = importlib.machinery.SourceFileLoader('release_state', str(Path(__file__).with_name('release-state.py'))).load_module()


def deployment(ref):
    return {'image': {'image': {'image': ref}}}


class ReleaseState(unittest.TestCase):
    def test_only_booted_exact_reference_passes(self):
        state.check_image({'status': {'booted': deployment('expected')}}, 'expected')
        for booted in (None, {}, deployment('expected-extra'), deployment('old')):
            with self.subTest(booted=booted), self.assertRaises(ValueError):
                state.check_image({'status': {'booted': booted, 'staged': deployment('expected'), 'rollback': deployment('expected')}}, 'expected')

    def test_rk_requires_complete_healthy_state(self):
        healthy = 'Overlay: ready\nPending recovery: False\nNeeds sync: False\ntree\n'
        state.check_rk(healthy)
        for invalid in ('', healthy.replace('ready', 'degraded'), healthy.replace('Pending recovery: False', 'Pending recovery: True'), healthy.replace('Needs sync: False', 'Needs sync: True'), healthy + 'Needs sync: True\n'):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                state.check_rk(invalid)


if __name__ == '__main__':
    unittest.main()
