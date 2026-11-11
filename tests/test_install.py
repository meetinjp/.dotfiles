import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.name == 'posix' and shutil.which('stow'), 'GNU Stow required.')
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles install ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / 'home'
        self.home.mkdir()
        self.checkout = self.root / 'projects/personal dotfiles'
        (self.checkout / 'scripts').mkdir(parents=True)
        for name in ['install.sh', 'scripts/link.py', 'scripts/link-zen.py']:
            shutil.copy2(ROOT / name, self.checkout / name)
        (self.checkout / 'profiles').mkdir()
        for name, content in {'core': 'zsh\ntmux\n', 'desktop': 'bin\n',
                              'macos': 'zsh\ntmux\nghostty\n', 'agents': ''}.items():
            (self.checkout / 'profiles' / name).write_text(content)
        self.sources = {}
        for package, relative in [('zsh', '.zshrc'), ('tmux', '.config/tmux/tmux.conf'),
                                  ('bin', '.local/bin/niri-screenshot'),
                                  ('ghostty', '.config/ghostty/config'),
                                  ('ghostty', '.config/ghostty/config-macos.conf')]:
            source = self.checkout / package / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text(f'managed {package} configuration\n')
            self.sources[relative] = source
        self.bin = self.root / 'commands'
        self.bin.mkdir()
        self.log = self.root / 'unexpected-operations'
        for name in ['sudo', 'curl', 'wget', 'git', 'apt', 'apt-get', 'brew', 'winget']:
            command = self.bin / name
            command.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$INSTALL_TEST_LOG"\nexit 99\n')
            command.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f'{self.bin}:/usr/bin:/bin', INSTALL_TEST_LOG=str(self.log))

    def install(self, *arguments):
        result = subprocess.run(['bash', str(self.checkout / 'install.sh'), *arguments],
                                cwd=self.checkout.parent, env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertFalse(self.log.exists(), result.stdout + result.stderr)
        return result

    def install_macos(self, *arguments):
        # Mock the platform in the child only; filesystem operations and Stow
        # remain real and isolated in this fixture's temporary home.
        code = '''
import runpy
import sys
from unittest.mock import patch
sys.argv = sys.argv[1:]
with patch.object(sys, 'platform', 'darwin'):
    runpy.run_path(sys.argv[0], run_name='__main__')
'''
        result = subprocess.run([sys.executable, '-c', code,
                                 str(self.checkout / 'scripts/link.py'), *arguments],
                                cwd=self.checkout.parent, env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertFalse(self.log.exists(), result.stdout + result.stderr)
        return result

    def snapshot(self, directory):
        result = {}
        for parent, dirs, files in os.walk(directory, followlinks=False):
            for path in [Path(parent), *(Path(parent) / name for name in dirs + files)]:
                stat = path.lstat()
                kind = 'link' if path.is_symlink() else 'directory' if path.is_dir() else 'file'
                value = os.readlink(path) if path.is_symlink() else path.read_bytes() if path.is_file() else None
                result[str(path.relative_to(directory))] = (kind, value, stat.st_mode, stat.st_mtime_ns)
        return result

    def assert_linked(self, relative):
        target = self.home / relative
        self.assertEqual(target.resolve(), self.sources[relative])
        self.assertTrue(target.is_symlink())
        self.assertFalse(os.path.isabs(os.readlink(target)))

    def test_checkout_location_does_not_change_home_target(self):
        result = self.install('zsh', 'tmux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked('.zshrc')
        self.assert_linked('.config/tmux/tmux.conf')
        self.assertFalse((self.checkout.parent / '.zshrc').exists())
        self.assertFalse((self.checkout.parent / '.config').exists())

    def test_default_core_profile_is_selective(self):
        result = self.install()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked('.zshrc')
        self.assert_linked('.config/tmux/tmux.conf')
        self.assertFalse((self.home / '.local').exists())

    def test_dry_run_does_not_normalize_or_create_anything(self):
        target = self.home / '.zshrc'
        target.symlink_to(self.sources['.zshrc'])
        before_home, before_source = self.snapshot(self.home), self.snapshot(self.checkout)
        for arguments in [('--dry-run', 'zsh', 'tmux'),
                          ('--dry-run', '--delete', 'zsh', 'tmux')]:
            result = self.install(*arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.snapshot(self.home), before_home)
            self.assertEqual(self.snapshot(self.checkout), before_source)
            self.assertTrue(os.path.isabs(os.readlink(target)))

    def test_repeated_installation_is_idempotent(self):
        result = self.install('zsh', 'tmux')
        self.assertEqual(result.returncode, 0, result.stderr)
        before = self.snapshot(self.home)
        result = self.install('zsh', 'tmux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(self.home), before)

    @unittest.skipUnless(os.name == 'posix' and os.uname().sysname == 'Linux', 'Linux bin package.')
    def test_delete_removes_managed_links_and_preserves_unrelated_files(self):
        result = self.install('zsh', 'tmux', 'bin')
        self.assertEqual(result.returncode, 0, result.stderr)
        extra = self.home / '.config/tmux/history'
        extra.write_text('personal history\n')
        helper = self.home / '.local/bin/personal-helper'
        helper.write_text('personal command\n')
        before_source = self.snapshot(self.checkout)
        result = self.install('--delete', 'zsh', 'tmux', 'bin')
        self.assertEqual(result.returncode, 0, result.stderr)
        for relative in self.sources:
            self.assertFalse((self.home / relative).is_symlink())
        self.assertEqual(extra.read_text(), 'personal history\n')
        self.assertEqual(helper.read_text(), 'personal command\n')
        self.assertEqual(self.snapshot(self.checkout), before_source)

    def test_absolute_same_source_link_is_normalized(self):
        target = self.home / '.zshrc'
        target.symlink_to(self.sources['.zshrc'])
        result = self.install('zsh', 'tmux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked('.zshrc')
        self.assert_linked('.config/tmux/tmux.conf')

    def test_unmanaged_file_blocks_all_packages_before_normalization(self):
        known = self.home / '.zshrc'
        known.symlink_to(self.sources['.zshrc'])
        target = self.home / '.config/tmux/tmux.conf'
        target.parent.mkdir(parents=True)
        target.write_text('personal tmux config\n')
        before = self.snapshot(self.home)
        result = self.install('zsh', 'tmux')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unmanaged targets preserved', result.stderr)
        self.assertEqual(self.snapshot(self.home), before)

    def test_unmanaged_symlink_blocks_all_packages(self):
        extra = self.root / 'personal tmux config'
        extra.write_text('preserve\n')
        target = self.home / '.config/tmux/tmux.conf'
        target.parent.mkdir(parents=True)
        target.symlink_to(extra)
        before = self.snapshot(self.home)
        result = self.install('zsh', 'tmux')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(self.home), before)
        self.assertEqual(extra.read_text(), 'preserve\n')

    def test_file_in_place_of_parent_directory_blocks_all_packages(self):
        (self.home / '.config').write_text('personal file\n')
        before = self.snapshot(self.home)
        result = self.install('zsh', 'tmux')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(self.home), before)

    def test_foreign_parent_symlink_is_not_traversed(self):
        foreign = self.root / 'unmanaged config directory'
        foreign.mkdir()
        (self.home / '.config').symlink_to(foreign, target_is_directory=True)
        (self.home / '.zshrc').symlink_to(self.sources['.zshrc'])
        before_home, before_foreign = self.snapshot(self.home), self.snapshot(foreign)
        result = self.install('zsh', 'tmux')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.snapshot(self.home), before_home)
        self.assertEqual(self.snapshot(foreign), before_foreign)

    def test_existing_tree_folded_owned_directory_is_supported(self):
        config = self.home / '.config'
        config.mkdir()
        target = config / 'tmux'
        target.symlink_to(self.checkout / 'tmux/.config/tmux', target_is_directory=True)
        source_before = self.snapshot(self.checkout)
        result = self.install('zsh', 'tmux')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_linked('.zshrc')
        self.assertEqual((target / 'tmux.conf').resolve(), self.sources['.config/tmux/tmux.conf'])
        if target.is_symlink():
            self.assertFalse(os.path.isabs(os.readlink(target)))
        self.assertEqual(self.snapshot(self.checkout), source_before)

    def test_unknown_package_fails_without_home_changes(self):
        before = self.snapshot(self.home)
        result = self.install('zsh', 'unknown-package')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('unknown packages', result.stderr)
        self.assertEqual(self.snapshot(self.home), before)

    def test_macos_ghostty_delete_preserves_settings_and_permissions(self):
        config = self.home / 'Library/Application Support/com.mitchellh.ghostty/config'
        config.parent.mkdir(parents=True)
        include = f'config-file = {self.home}/.config/ghostty/config-macos.conf'
        original = (f'# Personal preferences\r\nfont-size = 18\r\n'
                    f'# {include}\r\nconfig-file = /personal/other.conf\r\n').encode()
        config.write_bytes(original)
        config.chmod(0o640)
        result = self.install_macos('ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(include.encode(), config.read_bytes().splitlines())
        self.assert_linked('.config/ghostty/config-macos.conf')
        result = self.install_macos('--delete', 'ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_bytes(), original)
        self.assertEqual(config.stat().st_mode & 0o777, 0o640)
        self.assertFalse((self.home / '.config/ghostty/config-macos.conf').is_symlink())

    def test_macos_ghostty_delete_preserves_existing_config_symlink(self):
        config = self.home / 'Library/Application Support/com.mitchellh.ghostty/config'
        config.parent.mkdir(parents=True)
        destination = self.home / 'personal-ghostty-config'
        original = b'font-size = 19\n'
        destination.write_bytes(original)
        destination.chmod(0o600)
        config.symlink_to(destination)
        link = os.readlink(config)
        for arguments in [('ghostty',), ('--delete', 'ghostty')]:
            result = self.install_macos(*arguments)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(config.is_symlink())
            self.assertEqual(os.readlink(config), link)
            self.assertEqual(destination.stat().st_mode & 0o777, 0o600)
        self.assertEqual(destination.read_bytes(), original)

    def test_macos_ghostty_delete_preview_changes_nothing(self):
        result = self.install_macos('ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        before = self.snapshot(self.home)
        result = self.install_macos('--delete', '--dry-run', 'ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.snapshot(self.home), before)

    def test_macos_ghostty_delete_without_owned_include_does_not_rewrite_config(self):
        result = self.install_macos('ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.home / 'Library/Application Support/com.mitchellh.ghostty/config'
        original = b'config-file = /personal/config-macos.conf\n'
        config.write_bytes(original)
        before = config.stat().st_mtime_ns
        result = self.install_macos('--delete', 'ghostty')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(config.read_bytes(), original)
        self.assertEqual(config.stat().st_mtime_ns, before)


if __name__ == '__main__':
    unittest.main()
