import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'codex/apply.sh'


class CodexConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='codex config ')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config_dir = self.home / '.codex'
        self.config_dir.mkdir()
        self.config = self.config_dir / 'config.toml'
        self.env = dict(os.environ, HOME=str(self.home),
                        CODEX_HOME=str(self.config_dir),
                        CODEX_DOTFILES_TARGET_DIR=str(self.config_dir))

    def apply(self, success=True):
        result = subprocess.run(['/usr/bin/bash', str(SCRIPT)], env=self.env,
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_existing_model_reasoning_and_live_state_survive_reruns(self):
        self.config.write_text('''# Personal model choices
model = "my-current-model" # Keep my selection.
model_reasoning_effort = "low"
personality = "friendly"

[projects."/home/example/project"]
trust_level = "trusted"

[mcp_servers.personal]
command = "local-mcp"
args = ["--mode", "local"]

[plugins."personal@local"]
enabled = true

[plugins."caveman@caveman"]
enabled = true
custom = "keep this setting"

[plugins."caveman@dotfiles"]
enabled = true
''')
        auth = self.config_dir / 'auth.json'
        auth.write_text('{"fixture":"keep this unrelated state"}\n')
        session = self.config_dir / 'sessions/fixture.jsonl'
        session.parent.mkdir()
        session.write_text('{"fixture":"keep this session"}\n')
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns)
                  for path in (auth, session)}

        self.apply()
        result = tomllib.loads(self.config.read_text())
        self.assertEqual(result['model'], 'my-current-model')
        self.assertEqual(result['model_reasoning_effort'], 'low')
        self.assertIn('model = "my-current-model" # Keep my selection.',
                      self.config.read_text())
        self.assertEqual(result['projects']['/home/example/project']['trust_level'], 'trusted')
        self.assertEqual(result['mcp_servers']['personal'],
                         {'command': 'local-mcp', 'args': ['--mode', 'local']})
        self.assertTrue(result['plugins']['personal@local']['enabled'])
        self.assertFalse(result['plugins']['caveman@caveman']['enabled'])
        self.assertEqual(result['plugins']['caveman@caveman']['custom'], 'keep this setting')
        self.assertFalse(result['plugins']['caveman@dotfiles']['enabled'])
        self.assertEqual(result['personality'], 'pragmatic')
        self.assertTrue(result['tui']['vim_mode_default'])
        self.assertEqual(result['mcp_servers']['openaiDeveloperDocs']['url'],
                         'https://developers.openai.com/mcp')

        first_run = self.config.read_bytes(), self.config.stat().st_mtime_ns
        self.apply()
        self.assertEqual((self.config.read_bytes(), self.config.stat().st_mtime_ns), first_run)
        for path in (auth, session):
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before[path])

    def test_new_config_uses_application_model_defaults(self):
        self.apply()
        result = tomllib.loads(self.config.read_text())
        self.assertNotIn('model', result)
        self.assertNotIn('model_reasoning_effort', result)
        self.assertEqual(self.config.stat().st_mode & 0o777, 0o600)
        self.assertEqual((self.config_dir / 'AGENTS.md').resolve(), ROOT / 'codex/AGENTS.md')

    def test_malformed_config_is_left_unchanged(self):
        original = 'model = "unterminated\n'
        self.config.write_text(original)
        guidance = self.config_dir / 'AGENTS.md'
        guidance.write_text('# Existing personal guidance\n')
        self.apply(success=False)
        self.assertEqual(self.config.read_text(), original)
        self.assertEqual(guidance.read_text(), '# Existing personal guidance\n')
        self.assertFalse(guidance.is_symlink())

    def test_existing_personal_guidance_remains_active(self):
        guidance = self.config_dir / 'AGENTS.md'
        guidance.write_text('# Personal rules\nKeep these instructions.\n')
        self.apply()
        self.assertEqual(guidance.read_text(), '# Personal rules\nKeep these instructions.\n')
        self.assertFalse(guidance.is_symlink())

    def test_normal_application_never_calls_plugin_cli(self):
        # Use the ordinary CODEX_HOME path so this checks real installation
        # behavior rather than the test-target shortcut used above.
        self.env.pop('CODEX_DOTFILES_TARGET_DIR', None)
        self.env.pop('CODEX_APPLY_SKIP_PLUGINS', None)
        commands = self.home / 'bin'
        commands.mkdir()
        marker = self.home / 'plugin-command-called'
        command = commands / 'codex'
        command.write_text('#!/bin/sh\nprintf "%s\\n" "$*" > "$HOME/plugin-command-called"\nexit 1\n')
        command.chmod(0o755)
        self.env['PATH'] = f'{commands}:{self.env["PATH"]}'
        self.apply()
        self.assertFalse(marker.exists(), marker.read_text() if marker.exists() else '')


if __name__ == '__main__':
    unittest.main()
