import io
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'ubuntu/provision.sh'


@unittest.skipUnless(os.name == 'posix' and shutil.which('bash'), 'Bash required.')
class NoctaliaProvisionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ubuntu provisioning ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.target = self.home / '.config/quickshell/noctalia-shell'
        self.archive = self.home / 'shell.tar.gz'
        self.env = dict(os.environ, HOME=str(self.home),
                        XDG_CONFIG_HOME=str(self.home / '.config'),
                        PATH=f'{self.bin}:/usr/bin:/bin',
                        NOCTALIA_TEST_ARCHIVE=str(self.archive))
        self.command('qs', "printf 'noctalia-qs 0.0.12\\n'\n")
        self.command('curl', '''
if [ -e "$HOME/fail-download" ]; then exit 22; fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = -o ]; then cp "$NOCTALIA_TEST_ARCHIVE" "$2"; exit; fi
    shift
done
exit 2
''')
        # Any package or source-build operation makes these isolated tests fail.
        for name in ['sudo', 'git', 'cmake']:
            self.command(name, 'echo "unexpected build or system operation" >&2\nexit 99\n')
        self.make_archive()

    def command(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def make_archive(self, entry='shell.qml'):
        with tarfile.open(self.archive, 'w:gz') as archive:
            data = b'import Quickshell\nShellRoot {}\n'
            member = tarfile.TarInfo(f'noctalia-4.7.7/{entry}')
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))

    def call(self, function='install_noctalia'):
        return subprocess.run(['bash', '-c', 'source "$1"; ' + function,
                               'noctalia-test', str(SCRIPT)], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_existing_engine_still_installs_missing_shell(self):
        result = self.call()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('ShellRoot', (self.target / 'shell.qml').read_text())
        self.assertEqual(list(self.target.parent.glob('.noctalia-shell.*')), [])

    def test_existing_complete_shell_is_preserved_without_download(self):
        self.target.mkdir(parents=True)
        existing = self.target / 'shell.qml'
        existing.write_text('existing shell\n')
        (self.home / 'fail-download').touch()
        for _ in range(2):
            result = self.call()
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(existing.read_text(), 'existing shell\n')
        self.assertEqual(list(self.target.parent.glob('*.incomplete.*')), [])

    def test_failed_download_can_retry_and_preserves_existing_files(self):
        self.target.mkdir(parents=True)
        local = self.target / 'personal.txt'
        local.write_text('preserve this\n')
        failure = self.home / 'fail-download'
        failure.touch()
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.target / 'shell.qml').exists())
        self.assertEqual(local.read_text(), 'preserve this\n')
        self.assertEqual(list(self.target.parent.glob('.noctalia-shell.*')), [])
        failure.unlink()
        result = self.call()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.target / 'shell.qml').is_file())
        backups = list(self.target.parent.glob('noctalia-shell.incomplete.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'personal.txt').read_text(), 'preserve this\n')

    def test_archive_without_qml_entrypoint_is_rejected(self):
        self.make_archive('native-binary')
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('incompatible', result.stderr)
        self.assertFalse(self.target.exists())
        self.assertEqual(list(self.target.parent.glob('.noctalia-shell.*')), [])

    def test_unrelated_qs_is_not_overwritten_or_used(self):
        self.command('qs', "printf 'Quickshell 0.2.1\\n'\n")
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('not noctalia-qs', result.stderr)
        self.assertFalse(self.target.exists())
        self.assertIn('Quickshell 0.2.1', (self.bin / 'qs').read_text())

    def test_qt_floor_fails_before_source_or_package_operations(self):
        (self.bin / 'qs').unlink()
        self.command('qmake6', "printf 'Using Qt version 6.4.2 in /qt\\n'\n")
        self.command('apt-cache', "printf '  Candidate: 6.4.2+dfsg-1\\n'\n")
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requires Qt >= 6.6', result.stderr)
        self.assertFalse(self.target.exists())

    def test_compatible_candidate_allows_upgrading_old_installed_qt(self):
        (self.bin / 'qs').unlink()
        self.command('qmake6', "printf 'Using Qt version 6.4.2 in /qt\\n'\n")
        self.command('apt-cache', "printf '  Candidate: 1:6.8.3+dfsg-1\\n'\n")
        result = self.call('check_noctalia_requirements')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Qt 6.8.3', result.stdout)
        self.assertFalse((self.home / '.config').exists())

    def test_missing_candidate_does_not_allow_old_installed_qt(self):
        (self.bin / 'qs').unlink()
        self.command('qmake6', "printf 'Using Qt version 6.4.2 in /qt\\n'\n")
        self.command('apt-cache', "printf '  Candidate: (none)\\n'\n")
        result = self.call('check_noctalia_requirements')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('requires Qt >= 6.6', result.stderr)
        self.assertFalse((self.home / '.config').exists())

    def test_compatible_installed_qt_does_not_require_newer_candidate(self):
        (self.bin / 'qs').unlink()
        self.command('qmake6', "printf 'Using Qt version 6.8.3 in /qt\\n'\n")
        self.command('apt-cache', "printf '  Candidate: 6.4.2+dfsg-1\\n'\n")
        result = self.call('check_noctalia_requirements')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Qt 6.8.3', result.stdout)
        self.assertFalse((self.home / '.config').exists())

    def test_check_only_does_not_install_or_create_config(self):
        result = subprocess.run(['bash', str(SCRIPT), '--check'], env=self.env,
                                capture_output=True, text=True, timeout=10)
        # The distro check may reject a non-Ubuntu test host. Either result is
        # read-only and must not fall through to mocked system operations.
        self.assertIn(result.returncode, (0, 1), result.stderr)
        self.assertNotIn('unexpected build or system operation', result.stderr)
        self.assertFalse((self.home / '.config').exists())

    def prepare_source_build(self):
        (self.bin / 'qs').unlink()
        self.command('qmake6', "printf 'Using Qt version 6.8.3 in /qt\\n'\n")
        # Stop at the download boundary, recording the build's environment.
        self.command('git', 'printf "%s\\n" "$TMPDIR" > "$HOME/build-temp-root"\nexit 1\n')

    def test_source_build_defaults_to_disk_backed_temp(self):
        self.prepare_source_build()
        self.env.pop('TMPDIR', None)
        # Observe mktemp's environment without writing outside the test home.
        self.command('mktemp', '''
printf '%s\n' "$TMPDIR" > "$HOME/mktemp-root"
exec /usr/bin/mktemp -d "$HOME/build.XXXXXXXX"
''')
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / 'mktemp-root').read_text(), '/var/tmp\n')
        self.assertEqual((self.home / 'build-temp-root').read_text(), '/var/tmp\n')
        self.assertEqual(list(self.home.glob('build.*')), [])

    def test_source_build_honors_explicit_temp_directory(self):
        self.prepare_source_build()
        custom = self.home / 'custom build temp'
        custom.mkdir()
        self.env['TMPDIR'] = str(custom)
        result = self.call()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / 'build-temp-root').read_text(), f'{custom}\n')
        self.assertEqual(list(custom.iterdir()), [])


@unittest.skipUnless(os.name == 'posix' and shutil.which('bash'), 'Bash required.')
class ToolProvisionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='ubuntu tool provisioning ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.bin = self.home / 'bin'
        self.bin.mkdir()
        self.env = dict(os.environ, HOME=str(self.home), PATH=f'{self.bin}:/usr/bin:/bin')
        self.command('sudo', '''
printf '%s\n' "$@" > "$HOME/system-arguments"
exit "${PROVISION_TEST_APT_EXIT:-0}"
''')

    def command(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def call(self, function):
        # Installed tool detection must not depend on the test host's tools.
        return subprocess.run(['bash', '-c', '''
source "$1"
have() { [[ -x "$HOME/bin/$1" ]]; }
''' + function, 'tool-test', str(SCRIPT)], env=self.env,
                              capture_output=True, text=True, timeout=10)

    def test_keyd_installs_native_package_without_adding_repository(self):
        result = self.call('install_keyd')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.home / 'system-arguments').read_text().splitlines(),
                         ['apt-get', 'install', '-y', 'keyd'])

    def test_keyd_preserves_either_existing_binary(self):
        for name in ['keyd', 'keyd.rvaiya']:
            with self.subTest(name=name):
                self.command(name, 'exit 0\n')
                result = self.call('install_keyd')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertFalse((self.home / 'system-arguments').exists())
                (self.bin / name).unlink()

    def test_missing_keyd_package_reports_failure_without_ppa_fallback(self):
        self.env['PROVISION_TEST_APT_EXIT'] = '100'
        result = self.call('install_keyd')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((self.home / 'system-arguments').read_text().splitlines(),
                         ['apt-get', 'install', '-y', 'keyd'])

    def test_starship_installs_in_user_bin_without_sudo_or_terminal(self):
        self.command('curl', '''
cat <<'INSTALLER'
[ "$#" -eq 3 ] && [ "$1" = -y ] && [ "$2" = -b ] || exit 2
printf '#!/bin/sh\nexit 0\n' > "$3/starship"
chmod +x "$3/starship"
INSTALLER
''')
        result = self.call('install_starship')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(os.access(self.home / '.local/bin/starship', os.X_OK))
        self.assertFalse((self.home / 'system-arguments').exists())

    def test_starship_preserves_existing_installation(self):
        self.command('starship', 'exit 0\n')
        self.command('curl', 'exit 99\n')
        result = self.call('install_starship')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / '.local').exists())
        self.assertFalse((self.home / 'system-arguments').exists())

    def test_starship_download_failure_is_reported(self):
        self.command('curl', 'exit 22\n')
        result = self.call('install_starship')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / '.local/bin/starship').exists())


if __name__ == '__main__':
    unittest.main()
