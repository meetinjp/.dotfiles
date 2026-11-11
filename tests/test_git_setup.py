import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/setup-git.py'


class GitSetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='git setup ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        GIT_CONFIG_NOSYSTEM='1',
                        GIT_NAME='Personal Name', GIT_EMAIL='personal@example.test')
        for key in list(self.env):
            if key.startswith('GIT_CONFIG_') and key != 'GIT_CONFIG_NOSYSTEM':
                self.env.pop(key)
        self.env.pop('GIT_WORK_EMAIL', None)
        self.global_config = self.home / '.gitconfig'
        self.personal = self.home / '.config/git/dotfiles'

    def apply(self, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT)], input='', env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def git(self, *arguments):
        result = subprocess.run(['git', 'config', '--includes', *arguments], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.rstrip('\n')

    def test_literal_identity_values_and_blank_work_email(self):
        self.env['GIT_NAME'] = 'R&D | "quoted" \\ Name'
        self.env['GIT_EMAIL'] = 'a&b|quoted@example.test'
        self.env['GIT_WORK_EMAIL'] = ''
        self.apply()
        self.assertEqual(self.git('--global', '--get', 'user.name'), self.env['GIT_NAME'])
        self.assertEqual(self.git('--global', '--get', 'user.email'), self.env['GIT_EMAIL'])
        self.assertEqual(self.personal.stat().st_mode & 0o777, 0o600)
        self.assertFalse((self.home / '.config/git/dotfiles-work').exists())
        result = subprocess.run(['git', 'config', '--global', '--get', 'commit.gpgsign'],
                                env=self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)

    def test_existing_configuration_and_include_survive_reruns(self):
        extra = self.home / 'personal.inc'
        extra.write_text('[alias]\n  mine = status --short\n')
        self.global_config.write_text(f'''# Personal settings
[include]
  path = {extra}
[credential]
  helper = test-helper
[commit]
  gpgsign = false
[user]
  signingkey = EXISTING-KEY
''')
        self.apply()
        first = self.global_config.read_bytes(), self.personal.read_bytes()
        self.apply()
        self.assertEqual((self.global_config.read_bytes(), self.personal.read_bytes()), first)
        self.assertEqual(self.git('--global', '--get', 'alias.mine'), 'status --short')
        self.assertEqual(self.git('--global', '--get', 'credential.helper'), 'test-helper')
        self.assertEqual(self.git('--global', '--get', 'commit.gpgsign'), 'false')
        self.assertEqual(self.git('--global', '--get', 'user.signingkey'), 'EXISTING-KEY')
        includes = self.git('--global', '--get-all', 'include.path').splitlines()
        self.assertEqual(includes.count(str(self.personal)), 1)
        self.assertIn(str(extra), includes)
        self.assertIn('# Personal settings', self.global_config.read_text())

    def test_symlinked_global_config_stays_a_symlink(self):
        target = self.home / 'existing-config'
        target.write_text('[alias]\n  personal = status\n')
        self.global_config.symlink_to(target)
        self.apply()
        self.assertTrue(self.global_config.is_symlink())
        self.assertEqual(self.global_config.resolve(), target)
        self.assertIn(str(self.personal), target.read_text())
        self.assertEqual(self.git('--global', '--get', 'alias.personal'), 'status')

    def test_existing_identity_is_used_without_environment_values(self):
        self.env.pop('GIT_NAME')
        self.env.pop('GIT_EMAIL')
        identity = self.home / 'existing-identity.inc'
        identity.write_text('[user]\n  name = Existing Name\n  email = existing@example.test\n')
        self.global_config.write_text(f'[include]\n  path = {identity}\n')
        self.apply()
        self.assertEqual(self.git('--file', str(self.personal), '--get', 'user.name'), 'Existing Name')
        self.assertEqual(self.git('--file', str(self.personal), '--get', 'user.email'),
                         'existing@example.test')

    def test_missing_required_identity_fails_before_writing(self):
        self.env.pop('GIT_NAME')
        self.apply(success=False)
        self.assertFalse(self.personal.exists())
        self.assertFalse(self.global_config.exists())

    def test_invalid_global_config_fails_before_changes(self):
        original = '[invalid\n'
        self.global_config.write_text(original)
        self.apply(success=False)
        self.assertEqual(self.global_config.read_text(), original)
        self.assertFalse(self.personal.exists())

    def test_invalid_included_config_fails_before_changes(self):
        invalid = self.home / 'invalid.inc'
        invalid.write_text('[invalid\n')
        self.global_config.write_text(f'[include]\n  path = {invalid}\n')
        original = self.global_config.read_bytes()
        self.apply(success=False)
        self.assertEqual(self.global_config.read_bytes(), original)
        self.assertFalse(self.personal.exists())

    def test_optional_work_identity_is_never_automatically_included(self):
        self.env['GIT_WORK_EMAIL'] = 'work@example.test'
        self.apply()
        work = self.home / '.config/git/dotfiles-work'
        self.assertEqual(self.git('--file', str(work), '--get', 'user.email'), 'work@example.test')
        self.assertEqual(work.stat().st_mode & 0o777, 0o600)
        self.assertNotIn(str(work), self.git('--global', '--get-all', 'include.path').splitlines())
        self.assertEqual(self.git('--global', '--get', 'user.email'), 'personal@example.test')

    def test_xdg_config_home_and_existing_xdg_global_are_respected(self):
        config_home = self.home / 'configuration with spaces'
        self.env['XDG_CONFIG_HOME'] = str(config_home)
        config = config_home / 'git/config'
        config.parent.mkdir(parents=True)
        config.write_text('[alias]\n  existing = status\n')
        self.apply()
        personal = config_home / 'git/dotfiles'
        self.assertTrue(personal.is_file())
        self.assertFalse(self.global_config.exists())
        self.assertEqual(self.git('--global', '--get-all', 'include.path'), str(personal))
        self.assertEqual(self.git('--global', '--get', 'alias.existing'), 'status')

    def test_explicit_global_config_is_respected(self):
        original = '[alias]\n  untouched = status\n'
        self.global_config.write_text(original)
        selected = self.home / 'selected-global'
        selected.write_text('[alias]\n  selected = diff\n')
        self.env['GIT_CONFIG_GLOBAL'] = str(selected)
        self.apply()
        self.assertEqual(self.global_config.read_text(), original)
        self.assertIn(str(self.personal), selected.read_text())
        self.assertEqual(self.git('--global', '--get', 'alias.selected'), 'diff')

    def work_identity(self, config):
        work = self.home / 'work'
        work.mkdir()
        result = subprocess.run(['git', 'init', '--quiet', str(work)], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        identity = self.home / 'work.inc'
        identity.write_text('[user]\n  email = work@example.test\n')
        config.write_text(f'[includeIf "gitdir:{work}/"]\n  path = {identity}\n')
        return work

    def email_at(self, directory):
        result = subprocess.run(['git', '-C', str(directory), 'config', '--get', 'user.email'],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_conditional_identity_keeps_precedence(self):
        work = self.work_identity(self.global_config)
        original = self.global_config.read_bytes()
        self.assertEqual(self.email_at(work), 'work@example.test')
        self.apply()
        self.assertEqual(self.email_at(work), 'work@example.test')
        self.assertEqual(self.git('--global', '--get', 'user.email'), 'personal@example.test')
        self.assertIn(original, self.global_config.read_bytes())

    def test_nested_conditional_identity_keeps_precedence(self):
        extra = self.home / 'extra.inc'
        work = self.work_identity(extra)
        original = extra.read_bytes()
        self.global_config.write_text(f'[include]\n  path = {extra}\n')
        self.apply()
        self.assertEqual(self.email_at(work), 'work@example.test')
        self.assertEqual(extra.read_bytes(), original)

    def test_old_appended_managed_include_is_moved_before_conditional_identity(self):
        work = self.work_identity(self.global_config)
        self.personal.parent.mkdir(parents=True)
        self.personal.write_text('[user]\n  name = Old Name\n  email = old@example.test\n')
        self.git('--global', '--add', 'include.path', str(self.personal))
        self.assertEqual(self.email_at(work), 'old@example.test')
        self.apply()
        self.assertEqual(self.email_at(work), 'work@example.test')
        original = self.global_config.read_bytes()
        self.apply()
        self.assertEqual(self.global_config.read_bytes(), original)
        self.assertEqual(self.git('--global', '--get-all', 'include.path').splitlines().count(str(self.personal)), 1)

    def test_existing_explicit_identity_overrides_managed_defaults(self):
        self.global_config.write_text('[user]\n  name = Host Name\n  email = host@example.test\n')
        self.apply()
        self.assertEqual(self.git('--global', '--get', 'user.name'), 'Host Name')
        self.assertEqual(self.git('--global', '--get', 'user.email'), 'host@example.test')
        self.assertEqual(self.git('--file', str(self.personal), '--get', 'user.email'),
                         'personal@example.test')

    def test_existing_identity_is_read_from_both_global_files(self):
        self.env.pop('GIT_NAME')
        self.env.pop('GIT_EMAIL')
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        xdg.write_text('[user]\n  name = XDG Name\n  email = xdg@example.test\n')
        self.global_config.write_text('[alias]\n  personal = status\n')
        self.apply()
        self.assertEqual(self.git('--file', str(self.personal), '--get', 'user.name'), 'XDG Name')
        self.assertEqual(self.git('--file', str(self.personal), '--get', 'user.email'),
                         'xdg@example.test')

    def test_xdg_conditional_identity_keeps_precedence_with_both_global_files(self):
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        work = self.work_identity(xdg)
        self.global_config.write_text('[alias]\n  personal = status\n')
        self.apply()
        self.assertEqual(self.email_at(work), 'work@example.test')
        self.assertEqual(self.email_at(self.home), 'personal@example.test')

    def test_old_include_is_moved_from_home_to_existing_xdg_global(self):
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        work = self.work_identity(xdg)
        self.personal.write_text('[user]\n  name = Old Name\n  email = old@example.test\n')
        self.global_config.write_text(f'[include]\n  path = {self.personal}\n')
        self.apply()
        self.assertEqual(self.email_at(work), 'work@example.test')
        self.assertNotIn(str(self.personal), self.global_config.read_text())
        self.assertIn(str(self.personal), xdg.read_text())

    def test_invalid_xdg_global_is_validated_when_home_global_exists(self):
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        xdg.write_text('[invalid\n')
        original = '[alias]\n  personal = status\n'
        self.global_config.write_text(original)
        self.apply(success=False)
        self.assertEqual(self.global_config.read_text(), original)
        self.assertFalse(self.personal.exists())

    def test_global_paths_pointing_to_one_file_keep_the_default_include(self):
        xdg = self.home / '.config/git/config'
        xdg.parent.mkdir(parents=True)
        xdg.write_text('[alias]\n  personal = status\n')
        self.global_config.symlink_to(xdg)
        self.apply()
        self.assertEqual(self.email_at(self.home), 'personal@example.test')
        original = xdg.read_bytes()
        self.apply()
        self.assertEqual(xdg.read_bytes(), original)
        self.assertTrue(self.global_config.is_symlink())

    def test_utf8_bom_stays_at_start_and_setup_is_idempotent(self):
        original = b'\xef\xbb\xbf[alias]\n  personal = status\n'
        self.global_config.write_bytes(original)
        self.assertEqual(self.git('--global', '--get', 'alias.personal'), 'status')
        self.apply()
        content = self.global_config.read_bytes()
        self.assertTrue(content.startswith(b'\xef\xbb\xbf'))
        self.assertEqual(content.count(b'\xef\xbb\xbf'), 1)
        self.assertEqual(self.git('--global', '--get', 'alias.personal'), 'status')
        self.assertEqual(self.git('--global', '--get', 'user.email'), 'personal@example.test')
        self.apply()
        self.assertEqual(self.global_config.read_bytes(), content)

    def test_held_git_config_lock_preserves_global_configuration(self):
        for symlinked in (False, True):
            with self.subTest(symlinked=symlinked):
                if self.global_config.exists() or self.global_config.is_symlink():
                    self.global_config.unlink()
                target = self.home / 'personal-config' if symlinked else self.global_config
                original = b'[alias]\n  personal = status\n'
                target.write_bytes(original)
                if symlinked:
                    self.global_config.symlink_to(target)
                lock = target.with_name(target.name + '.lock')
                held = b'held by another Git writer\n'
                lock.write_bytes(held)
                try:
                    native = subprocess.run(['git', 'config', '--global', 'alias.concurrent', 'status'],
                                            env=self.env, capture_output=True, text=True, timeout=10)
                    self.assertNotEqual(native.returncode, 0, native.stderr)
                    result = self.apply(success=False)
                    self.assertIn(str(lock), result.stderr)
                    self.assertEqual(target.read_bytes(), original)
                    self.assertEqual(lock.read_bytes(), held)
                finally:
                    lock.unlink()
                self.apply()
                self.assertEqual(self.git('--global', '--get', 'alias.personal'), 'status')
                self.assertEqual(self.global_config.is_symlink(), symlinked)
                self.assertFalse(lock.exists())

    def interleave_writer(self, cooperative):
        commands = self.home / 'commands'
        commands.mkdir()
        wrapper = commands / 'git'
        wrapper.write_text('''#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys

record = Path(os.environ['HOME']) / 'interleaved-writer'
if '--unset-all' in sys.argv and not record.exists():
    if os.environ['COOPERATIVE_WRITER'] == '1':
        result = subprocess.run([os.environ['REAL_GIT'], 'config', '--global',
                                 'alias.concurrent', 'status --short'], capture_output=True)
        record.write_text(str(result.returncode))
    else:
        with (Path(os.environ['HOME']) / '.gitconfig').open('a') as stream:
            stream.write('[alias]\\n  concurrent = status --short\\n')
        record.write_text('0')
os.execv(os.environ['REAL_GIT'], [os.environ['REAL_GIT'], *sys.argv[1:]])
''')
        wrapper.chmod(0o755)
        self.env.update(REAL_GIT=shutil.which('git'), COOPERATIVE_WRITER=str(int(cooperative)),
                        PATH=f'{commands}:{self.env["PATH"]}')
        return self.home / 'interleaved-writer'

    def test_git_writer_is_blocked_during_config_snapshot_and_replacement(self):
        self.global_config.write_text('[alias]\n  personal = status\n')
        record = self.interleave_writer(cooperative=True)
        self.apply()
        self.assertNotEqual(record.read_text(), '0')
        self.assertEqual(self.git('--global', '--get', 'alias.personal'), 'status')
        self.assertEqual(self.git('--global', '--get', 'user.email'), 'personal@example.test')
        self.assertFalse(self.global_config.with_name('.gitconfig.lock').exists())

    def test_noncooperating_writer_changes_are_not_overwritten(self):
        original = '[alias]\n  personal = status\n'
        self.global_config.write_text(original)
        self.interleave_writer(cooperative=False)
        result = self.apply(success=False)
        self.assertIn('changed during setup', result.stderr)
        self.assertEqual(self.global_config.read_text(), original + '[alias]\n  concurrent = status --short\n')
        self.assertEqual(self.git('--global', '--get', 'alias.concurrent'), 'status --short')
        self.assertFalse(self.global_config.with_name('.gitconfig.lock').exists())


if __name__ == '__main__':
    unittest.main()
