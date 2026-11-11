import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/link-zen.py'
SOURCE = ROOT / 'zen/.config/zen/user.js'


class ZenProfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='zen profile ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'))

    def run_helper(self, *arguments):
        return subprocess.run(['python3', str(SCRIPT), *arguments], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def install_default(self, root, name='Personal profile'):
        profile = root / name
        profile.mkdir(parents=True)
        (root / 'installs.ini').write_text(f'''[Install]
Default={name}
''')
        return profile

    def assert_linked(self, profile):
        target = profile / 'user.js'
        self.assertTrue(target.is_symlink())
        self.assertEqual(target.resolve(), SOURCE)
        self.assertFalse(os.readlink(target).startswith('/'))

    def test_existing_config_profile_with_spaces_is_linked_once(self):
        profile = self.install_default(self.home / '.config/zen')
        for _ in range(2):
            result = self.run_helper()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assert_linked(profile)

    def test_install_default_takes_precedence_over_profile_default(self):
        root = self.home / '.config/zen'
        chosen = self.install_default(root)
        other = root / 'Other'
        other.mkdir()
        (root / 'profiles.ini').write_text('[Profile0]\nPath=Other\nDefault=1\n')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(chosen)
        self.assertFalse((other / 'user.js').exists())

    def test_profiles_ini_absolute_path_is_honored(self):
        root = self.home / '.config/zen'
        root.mkdir(parents=True)
        profile = self.home / 'External browser profile'
        profile.mkdir()
        (root / 'profiles.ini').write_text(
            f'[Profile0]\nIsRelative=0\nPath={profile}\nDefault=1\n')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(profile)

    def test_absolute_install_path_is_honored(self):
        root = self.home / '.config/zen'
        root.mkdir(parents=True)
        profile = self.home / 'Absolute install profile'
        profile.mkdir()
        (root / 'installs.ini').write_text(f'[Install]\nDefault={profile}\n')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(profile)

    def test_alternate_root_is_used_when_first_root_is_empty(self):
        (self.home / '.config/zen').mkdir(parents=True)
        profile = self.install_default(self.home / '.zen')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(profile)

    def test_macos_profile_root_is_discovered(self):
        profile = self.install_default(self.home / 'Library/Application Support/zen',
                                       'Profiles/Personal profile')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(profile)

    def test_xdg_config_home_is_honored(self):
        self.env['XDG_CONFIG_HOME'] = str(self.home / 'Custom config')
        profile = self.install_default(Path(self.env['XDG_CONFIG_HOME']) / 'zen')
        result = self.run_helper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked(profile)

    def test_preview_does_not_create_links_or_directories(self):
        profile = self.install_default(self.home / '.config/zen')
        before = set(self.home.rglob('*'))
        for flag in ['--dry-run', '--check']:
            result = self.run_helper(flag)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('would link', result.stdout)
            self.assertEqual(set(self.home.rglob('*')), before)
            self.assertFalse((profile / 'user.js').exists())

    def test_missing_profiles_are_skipped_without_phantom_directories(self):
        for flag in [[], ['--dry-run'], ['--delete']]:
            result = self.run_helper(*flag)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('no existing default profile', result.stdout)
            self.assertEqual(list(self.home.iterdir()), [])

    def test_delete_removes_only_owned_link(self):
        profile = self.install_default(self.home / '.config/zen')
        extra = profile / 'keep.txt'
        extra.write_text('preserve\n')
        self.assertEqual(self.run_helper().returncode, 0)
        result = self.run_helper('--delete')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((profile / 'user.js').is_symlink())
        self.assertEqual(extra.read_text(), 'preserve\n')

    def test_conflicting_real_file_and_unrelated_link_are_preserved(self):
        profile = self.install_default(self.home / '.config/zen')
        target = profile / 'user.js'
        target.write_text('personal preferences\n')
        for flag in [[], ['--dry-run'], ['--delete']]:
            result = self.run_helper(*flag)
            self.assertEqual(result.returncode, 0 if '--delete' in flag else 1)
            self.assertEqual(target.read_text(), 'personal preferences\n')
        target.unlink()
        other = self.home / 'other.js'
        other.write_text('different source\n')
        target.symlink_to(other)
        for flag in [[], ['--dry-run'], ['--delete']]:
            result = self.run_helper(*flag)
            self.assertEqual(result.returncode, 0 if '--delete' in flag else 1)
            self.assertEqual(target.resolve(), other)
            self.assertEqual(other.read_text(), 'different source\n')


if __name__ == '__main__':
    unittest.main()
