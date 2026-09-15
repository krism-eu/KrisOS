#!/usr/bin/python3
"""Real Fedora DNF/RPM integration in a DISPOSABLE container, never on a host.

Only the VM-specific mount/SELinux guard is replaced. Solver, downloads,
signature checks, RPM tests, real install/remove and intent writes are exercised.
This test does not claim to test OverlayFS, reboot or deployment recovery.
"""
import importlib.machinery
import os
from pathlib import Path
import subprocess
import tempfile

if os.environ.get('RK_DISPOSABLE_CONTAINER_TEST') != '1' or not Path('/run/.containerenv').exists():
    raise SystemExit('Run only through the disposable Podman CI test')
rk = importlib.machinery.SourceFileLoader('rk', '/usr/bin/rk').load_module()
if subprocess.run(['rpm', '-q', 'tree'], stdout=subprocess.DEVNULL).returncode == 0:
    raise SystemExit('Fixture tree must be absent in the image')
with tempfile.TemporaryDirectory() as directory:
    rk.STATE = Path(directory)
    (rk.STATE / 'packages.list').write_text('')
    rk.guard = lambda: 'disposable container; VM guard tested separately'
    rk.transact('add', {'tree'})
    subprocess.run(['/usr/bin/tree', '--version'], check=True)
    assert (rk.STATE / 'packages.list').read_text() == 'tree\n'
    assert not (rk.STATE / 'pending').exists()
    rk.transact('rm', {'tree'})
    assert not Path('/usr/bin/tree').exists()
    assert (rk.STATE / 'packages.list').read_text() == ''
print('PASS: real signed RPM install/remove, immutable identities and package intent')
