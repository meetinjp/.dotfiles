import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'bin/.local/bin/onedrive-sync'
RCLONE = shutil.which('rclone')


@unittest.skipUnless(RCLONE, 'Install rclone to exercise sync with local folders.')
class OneDriveSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='onedrive sync ')
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.home = root / 'home'
        self.local = self.home / 'work/ai/OneDrive'
        self.remote = root / 'cloud/LinuxSync'
        self.local.mkdir(parents=True)
        self.remote.mkdir(parents=True)
        self.state = root / 'state/rclone/bisync'
        config = root / 'rclone.conf'
        config.write_text(f'[onedrive]\ntype = alias\nremote = {self.remote.parent}\n')
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
        result = subprocess.run([RCLONE, 'bisync', str(self.local), 'onedrive:LinuxSync',
                                 '--workdir', str(self.state), '--check-access',
                                 '--create-empty-src-dirs', '--resync'],
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
        for flag in ('--dry-run', '-n'):
            with self.subTest(flag=flag):
                result = self.helper(flag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.tree(self.local), local_before)
                self.assertEqual(self.tree(self.remote), remote_before)
                self.assertEqual({path.name: path.read_bytes()
                                  for path in self.state.glob('*.lst')}, baseline)

    def test_missing_local_folder_or_marker_is_refused(self):
        self.initialize()
        (self.local / 'RCLONE_TEST').unlink()
        result = self.helper()
        self.assertEqual(result.returncode, 1)
        self.assertIn('scripts/onedrive/README.md', result.stderr)
        shutil.rmtree(self.local)
        remote_before = self.tree(self.remote)
        result = self.helper()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.tree(self.remote), remote_before)

    def test_missing_remote_marker_blocks_changes(self):
        self.initialize()
        (self.remote / 'RCLONE_TEST').unlink()
        local_before, remote_before = self.tree(self.local), self.tree(self.remote)
        result = self.helper()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.tree(self.local), local_before)
        self.assertEqual(self.tree(self.remote), remote_before)

    def test_help_prints_usage_and_exits_cleanly(self):
        for flag in ('--help', '-h'):
            with self.subTest(flag=flag):
                result = self.helper(flag)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('Usage: onedrive-sync', result.stdout)

    def test_resync_and_arbitrary_flags_are_rejected(self):
        for arguments in (('--resync',), ('--force',), ('--dry-run', '--resync')):
            with self.subTest(arguments=arguments):
                before = self.tree(self.remote)
                result = self.helper(*arguments)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(self.tree(self.remote), before)


if __name__ == '__main__':
    unittest.main()
