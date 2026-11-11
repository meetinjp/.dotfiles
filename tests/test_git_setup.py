import os
from pathlib import Path
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


if __name__ == '__main__':
    unittest.main()
