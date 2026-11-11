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

    def apply(self):
        result = subprocess.run(['bash', str(SCRIPT)], input='', env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
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


if __name__ == '__main__':
    unittest.main()
