import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts/setup-keys.sh'
FINGERPRINT = '0123456789ABCDEF0123456789ABCDEF01234567'
KEYGRIP = 'ABCDEF0123456789ABCDEF0123456789ABCDEF01'


@unittest.skipUnless(os.name == 'posix' and shutil.which('git'), 'Git and Bash required.')
class KeySetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='dotfiles fake key setup ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'commands'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin',
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        GIT_CONFIG_NOSYSTEM='1', DOTFILES_YES='0')
        for key in list(self.env):
            if key.startswith('GIT_CONFIG_') and key != 'GIT_CONFIG_NOSYSTEM':
                self.env.pop(key)
        for key in ['GIT_NAME', 'GIT_EMAIL', 'GIT_WORK_EMAIL', 'KEYID', 'GNUPGHOME']:
            self.env.pop(key, None)
        self.identity = self.home / '.config/git/dotfiles'
        self.identity.parent.mkdir(parents=True)
        self.identity.write_text('[user]\n  name = Included Identity\n  email = included@example.test\n')
        self.config = self.home / '.gitconfig'
        self.config.write_text(f'[include]\n  path = {self.identity}\n')
        self.gnupg = self.home / '.gnupg'
        self.gnupg.mkdir()
        # Existing harmless fixture config avoids selecting a system pinentry.
        (self.gnupg / 'gpg-agent.conf').write_text('pinentry-program /fixture/pinentry\nenable-ssh-support\n')
        self.fingerprint_record = ':'.join(['fpr'] + [''] * 8 + [FINGERPRINT])
        self.auth_record = ':'.join(['sub'] + [''] * 10 + ['a'])
        self.grip_record = ':'.join(['grp'] + [''] * 8 + [KEYGRIP])
        self.command('gpg', '''
case "$1" in
    --list-secret-keys)
        [ ! -e "$HOME/no-key" ] || exit 1
        printf '%s\\n' "$KEY_TEST_FINGERPRINT_RECORD"
        ;;
    --list-keys)
        printf '%s\\n%s\\n' "$KEY_TEST_AUTH_RECORD" "$KEY_TEST_GRIP_RECORD"
        ;;
    --armor) printf 'FAKE PUBLIC SIGNING KEY\\n' ;;
    --export-ssh-key) printf 'FAKE PUBLIC SSH KEY\\n' ;;
    *) printf 'Unexpected fake GPG operation: %s\\n' "$*" >&2; exit 99 ;;
esac
''')
        self.command('gpgconf', 'printf "%s\\n" "$*" >> "$HOME/gpgconf-operations"\n')
        self.env.update(KEY_TEST_FINGERPRINT_RECORD=self.fingerprint_record,
                        KEY_TEST_AUTH_RECORD=self.auth_record,
                        KEY_TEST_GRIP_RECORD=self.grip_record)

    def command(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def git(self, *arguments):
        result = subprocess.run(['git', 'config', '--global', '--includes', *arguments],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.rstrip('\n')

    def apply(self, success=True):
        result = subprocess.run(['bash', str(SCRIPT)], input='', env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        self.assertNotIn('Unexpected fake GPG operation', result.stderr)
        return result

    def test_included_identity_is_accepted_without_environment_values(self):
        result = self.apply()
        self.assertIn('existing key for included@example.test', result.stdout)
        self.assertEqual(self.git('--get', 'user.name'), 'Included Identity')
        self.assertEqual(self.git('--get', 'user.email'), 'included@example.test')
        self.assertEqual(self.git('--get', 'user.signingkey'), FINGERPRINT)
        self.assertEqual(self.git('--get', 'gpg.format'), 'openpgp')
        self.assertIn('FAKE PUBLIC SIGNING KEY', result.stdout)

    def test_selecting_gpg_changes_ssh_signing_coherently(self):
        self.git('gpg.format', 'ssh')
        self.git('user.signingkey', 'ssh-ed25519 fixture-key')
        self.git('commit.gpgsign', 'false')
        self.git('tag.gpgsign', 'false')
        self.git('gpg.ssh.program', '/personal/ssh-sign')
        self.apply()
        self.assertEqual(self.git('--get', 'gpg.format'), 'openpgp')
        self.assertEqual(self.git('--get', 'user.signingkey'), FINGERPRINT)
        self.assertEqual(self.git('--get', 'gpg.program'), str(self.bin / 'gpg'))
        self.assertEqual(self.git('--get', 'commit.gpgsign'), 'true')
        self.assertEqual(self.git('--get', 'tag.gpgsign'), 'true')
        self.assertEqual(self.git('--get', 'gpg.ssh.program'), '/personal/ssh-sign')
        before = self.config.read_bytes()
        self.apply()
        self.assertEqual(self.config.read_bytes(), before)

    def test_skipping_key_generation_preserves_signing_configuration(self):
        (self.home / 'no-key').touch()
        self.git('gpg.format', 'ssh')
        self.git('user.signingkey', 'ssh-ed25519 existing-key')
        self.git('commit.gpgsign', 'false')
        self.git('tag.gpgsign', 'true')
        self.git('gpg.program', '/personal/gpg')
        before = self.config.read_bytes()
        result = self.apply()
        self.assertIn('no TTY, skipping', result.stdout)
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(self.git('--get', 'gpg.format'), 'ssh')
        self.assertEqual(self.git('--get', 'user.signingkey'), 'ssh-ed25519 existing-key')

    def test_conflicting_later_include_fails_before_changing_signing_settings(self):
        conflicting = self.home / 'signing.inc'
        conflicting.write_text('[gpg]\n  format = ssh\n')
        self.config.write_text(f'''[gpg]
  format = ssh
[include]
  path = "{self.identity}"
  path = "{conflicting}"
''')
        before = self.config.read_bytes(), conflicting.read_bytes()
        result = self.apply(success=False)
        self.assertIn('included signing settings', result.stderr)
        self.assertEqual((self.config.read_bytes(), conflicting.read_bytes()), before)
        self.assertEqual(self.git('--get', 'gpg.format'), 'ssh')
        self.assertFalse(self.config.with_name('.gitconfig.lock').exists())

    def test_included_boolean_true_spellings_are_accepted(self):
        identity = self.identity.read_text()
        for value in ['yes', 'on', '1', 'TRUE', None]:
            with self.subTest(value=value):
                setting = 'gpgsign' if value is None else f'gpgsign = {value}'
                self.identity.write_text(f'{identity}[commit]\n  {setting}\n[tag]\n  {setting}\n')
                included = self.identity.read_bytes()
                self.apply()
                self.assertEqual(self.git('--type=bool', '--get', 'commit.gpgsign'), 'true')
                self.assertEqual(self.git('--type=bool', '--get', 'tag.gpgsign'), 'true')
                self.assertEqual(self.git('--get', 'user.signingkey'), FINGERPRINT)
                self.assertEqual(self.identity.read_bytes(), included)

    def test_included_boolean_false_spellings_reject_without_changes(self):
        identity = self.identity.read_text()
        for section in ['commit', 'tag']:
            for value in ['no', 'off', '0', 'false']:
                with self.subTest(section=section, value=value):
                    self.identity.write_text(f'{identity}[{section}]\n  gpgsign = {value}\n')
                    before = self.config.read_bytes(), self.identity.read_bytes()
                    result = self.apply(success=False)
                    self.assertIn('included signing settings', result.stderr)
                    self.assertEqual((self.config.read_bytes(), self.identity.read_bytes()), before)
                    self.assertFalse(self.config.with_name('.gitconfig.lock').exists())

    def test_invalid_included_boolean_rejects_without_changes(self):
        with self.identity.open('a') as stream:
            stream.write('[commit]\n  gpgsign = not-a-boolean\n')
        before = self.config.read_bytes(), self.identity.read_bytes()
        result = self.apply(success=False)
        self.assertIn('boolean', result.stderr)
        self.assertEqual((self.config.read_bytes(), self.identity.read_bytes()), before)
        self.assertFalse(self.config.with_name('.gitconfig.lock').exists())

    def test_conditional_ssh_signing_keeps_precedence_over_new_defaults(self):
        work = self.home / 'work'
        work.mkdir()
        subprocess.run(['git', 'init', '-q', str(work)], env=self.env, check=True,
                       capture_output=True, text=True, timeout=10)
        conditional = self.home / 'work-signing.inc'
        original = '''[user]
  signingkey = ssh-ed25519 work-key
[gpg]
  format = ssh
[gpg "ssh"]
  program = /personal/work-ssh-sign
'''
        conditional.write_text(original)
        with self.config.open('a') as stream:
            stream.write(f'[includeIf "gitdir:{work}/"]\n  path = "{conditional}"\n')
        self.apply()
        self.assertEqual(self.git('--get', 'gpg.format'), 'openpgp')
        for key, expected in [('gpg.format', 'ssh'),
                              ('user.signingkey', 'ssh-ed25519 work-key'),
                              ('gpg.ssh.program', '/personal/work-ssh-sign')]:
            result = subprocess.run(['git', '-C', str(work), 'config', '--get', key],
                                    env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.rstrip('\n'), expected)
        self.assertEqual(conditional.read_text(), original)

    def test_relative_include_and_global_symlink_survive_signing_setup(self):
        actual = self.identity.parent / 'personal-config'
        (self.home / 'identity.inc').write_bytes(self.identity.read_bytes())
        actual.write_text('[include]\n  path = identity.inc\n[alias]\n  mine = status --short\n')
        self.config.unlink()
        self.config.symlink_to(actual)
        self.apply()
        self.assertTrue(self.config.is_symlink())
        self.assertEqual(self.config.resolve(), actual)
        self.assertEqual(self.git('--get', 'user.email'), 'included@example.test')
        self.assertEqual(self.git('--get', 'gpg.format'), 'openpgp')
        self.assertEqual(self.git('--get', 'alias.mine'), 'status --short')
        self.assertFalse(actual.with_name('personal-config.lock').exists())

    def test_split_global_identity_and_conditional_signing_are_preserved(self):
        first = self.identity.parent / 'config'
        first.write_bytes(self.config.read_bytes())
        work = self.home / 'work'
        work.mkdir()
        subprocess.run(['git', 'init', '-q', str(work)], env=self.env, check=True,
                       capture_output=True, text=True, timeout=10)
        profile = self.home / 'work.inc'
        profile.write_text('[gpg]\n  format = ssh\n[user]\n  signingkey = ssh-ed25519 work-key\n')
        with first.open('a') as stream:
            stream.write(f'[includeIf "gitdir:{work}/"]\n  path = "{profile}"\n')
        original = '[alias]\n  mine = status --short\n'
        self.config.write_text(original)
        self.apply()
        self.assertEqual(self.config.read_text(), original)
        for directory, expected in [(self.home, 'openpgp'), (work, 'ssh')]:
            result = subprocess.run(['git', '-C', str(directory), 'config', '--get', 'gpg.format'],
                                    env=self.env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.rstrip('\n'), expected)

    def test_conflicting_later_global_file_fails_without_partial_changes(self):
        first = self.identity.parent / 'config'
        first.write_bytes(self.config.read_bytes())
        self.config.write_text('[gpg]\n  format = ssh\n[user]\n  signingkey = ssh-ed25519 personal-key\n')
        before = first.read_bytes(), self.config.read_bytes()
        result = self.apply(success=False)
        self.assertIn('included signing settings', result.stderr)
        self.assertEqual((first.read_bytes(), self.config.read_bytes()), before)
        self.assertFalse(first.with_name('config.lock').exists())


if __name__ == '__main__':
    unittest.main()
