import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'bin/.local/bin/proton-sync'
SETUP = Path(__file__).resolve().parents[1] / 'scripts/proton-drive/setup.sh'
RCLONE = shutil.which('rclone')


@unittest.skipUnless(os.name == 'posix' and os.uname().sysname == 'Linux', 'Linux setup only.')
class ProtonSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='proton setup ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / '.local/bin'
        self.bin.mkdir(parents=True)
        # Existing commands keep this installer test entirely offline.
        for name in ('rclone', 'proton-drive'):
            command = self.bin / name
            command.write_text('#!/bin/sh\nexit 0\n')
            command.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin')

    def setup(self):
        return subprocess.run(['/usr/bin/bash', str(SETUP)], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_setup_preserves_existing_tools_and_unrelated_helpers(self):
        unrelated = self.bin / 'work-keep-awake'
        unrelated.write_text('unrelated local helper\n')
        before = {name: (self.bin / name).read_bytes()
                  for name in ('rclone', 'proton-drive', 'work-keep-awake')}
        for _ in range(2):
            result = self.setup()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual({name: (self.bin / name).read_bytes() for name in before}, before)
            self.assertEqual((self.bin / 'proton-sync').resolve(), SCRIPT)
            self.assertFalse(os.readlink(self.bin / 'proton-sync').startswith('/'))
            self.assertTrue((self.home / 'ProtonDrive').is_dir())
            self.assertEqual(list((self.home / 'ProtonDrive').iterdir()), [])

    def test_setup_refuses_to_overwrite_an_existing_sync_helper(self):
        target = self.bin / 'proton-sync'
        target.write_text('existing local command\n')
        result = self.setup()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Refusing to replace', result.stderr)
        self.assertEqual(target.read_text(), 'existing local command\n')


@unittest.skipUnless(RCLONE, 'Install rclone to exercise sync with local folders.')
class ProtonSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='proton sync ')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home = root / 'home'
        self.local = self.home / 'ProtonDrive'
        self.remote = root / 'cloud/LinuxSync'
        self.local.mkdir(parents=True)
        self.remote.mkdir(parents=True)
        self.state = root / 'state/rclone/bisync'
        config = root / 'rclone.conf'
        config.write_text(f'[proton]\ntype = alias\nremote = {self.remote.parent}\n')
        self.env = dict(os.environ, HOME=str(self.home), XDG_STATE_HOME=str(root / 'state'),
                        RCLONE_CONFIG=str(config))
        # A local alias exercises real bisync without credentials or network.
        for directory in (self.local, self.remote):
            (directory / 'RCLONE_TEST').touch()
        for number in range(5):
            (self.local / f'keep-{number}.txt').write_text(f'original {number}\n')

    def helper(self, *arguments):
        return subprocess.run(['/usr/bin/bash', str(SCRIPT), *arguments], env=self.env,
                              capture_output=True, text=True, timeout=20)

    def initialize(self):
        result = subprocess.run([RCLONE, 'bisync', str(self.local), 'proton:LinuxSync',
                                 '--workdir', str(self.state), '--check-access',
                                 '--protondrive-enable-caching=false', '--resync'],
                                env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stderr)

    def tree(self, directory):
        return {str(path.relative_to(directory)): path.read_bytes()
                for path in directory.rglob('*') if path.is_file()}

    def test_uninitialized_sync_does_not_copy_or_reinitialize(self):
        before = self.tree(self.remote)
        result = self.helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(self.remote), before)

    def test_new_files_sync_in_both_directions(self):
        self.initialize()
        (self.local / 'from laptop.txt').write_text('local change\n')
        (self.remote / 'from cloud.txt').write_text('remote change\n')
        result = self.helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tree(self.local), self.tree(self.remote))
        self.assertTrue((self.local / 'from cloud.txt').is_file())
        self.assertTrue((self.remote / 'from laptop.txt').is_file())

    def test_dry_run_preserves_files_and_sync_baseline(self):
        self.initialize()
        (self.local / 'keep-0.txt').unlink()
        (self.remote / 'new.txt').write_text('remote change\n')
        local_before, remote_before = self.tree(self.local), self.tree(self.remote)
        baseline = {path.name: path.read_bytes() for path in self.state.glob('*.lst')}
        self.assertTrue(baseline)
        result = self.helper('--dry-run')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.tree(self.local), local_before)
        self.assertEqual(self.tree(self.remote), remote_before)
        self.assertEqual({path.name: path.read_bytes() for path in self.state.glob('*.lst')},
                         baseline)

    def test_local_deletion_propagates_to_cloud(self):
        self.initialize()
        (self.local / 'keep-0.txt').unlink()
        result = self.helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.remote / 'keep-0.txt').exists())
        self.assertTrue((self.remote / 'keep-1.txt').exists())

    def test_missing_access_marker_blocks_changes_on_either_side(self):
        self.initialize()
        for directory in (self.local, self.remote):
            with self.subTest(directory=directory):
                (directory / 'RCLONE_TEST').unlink()
                local_before, remote_before = self.tree(self.local), self.tree(self.remote)
                result = self.helper()
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(self.tree(self.local), local_before)
                self.assertEqual(self.tree(self.remote), remote_before)
                (directory / 'RCLONE_TEST').touch()

    def test_resync_and_arbitrary_flags_are_rejected(self):
        for arguments in (('--resync',), ('--force',), ('--dry-run', '--resync')):
            with self.subTest(arguments=arguments):
                before = self.tree(self.remote)
                result = self.helper(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.tree(self.remote), before)


if __name__ == '__main__':
    unittest.main()
