import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'agent-skills/apply.py'
SKILLS = ROOT / 'agent-skills/caveman/skills'


class AgentSkillsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)

    def apply(self, *arguments, success=True):
        result = subprocess.run([sys.executable, str(SCRIPT), '--home', str(self.home), *arguments],
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def put(self, relative, content):
        path = self.home / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def setup_wrapper(self, success=True):
        repository = self.home / 'checkout'
        for relative in ['agent-skills/setup.sh', 'agent-skills/apply.py',
                         'agent-skills/CAVEMAN.md', 'codex/apply.sh',
                         'codex/AGENTS.md', 'claude/apply.sh']:
            target = repository / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / relative, target)
        (repository / 'agent-skills/caveman').symlink_to(SKILLS.parent)
        install = repository / 'install.sh'
        install.write_text('#!/bin/sh\n[ "$*" = "--profile agents" ]\n')
        install.chmod(0o755)
        commands = self.home / 'bin'
        commands.mkdir()
        git = commands / 'git'
        git.write_text('#!/bin/sh\nexit 0\n')
        git.chmod(0o755)
        env = dict(os.environ, HOME=str(self.home),
                   CODEX_HOME=str(self.home / '.codex'),
                   CODEX_DOTFILES_TARGET_DIR=str(self.home / '.codex'),
                   CLAUDE_CONFIG_DIR=str(self.home / '.claude'),
                   XDG_CONFIG_HOME=str(self.home / '.config'),
                   PATH=f'{commands}:{os.environ["PATH"]}')
        for _ in range(2):
            result = subprocess.run(['bash', str(repository / 'agent-skills/setup.sh')],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)

    def test_setup_wrapper_installs_base_guidance_before_caveman_merge(self):
        self.setup_wrapper()
        guide = (self.home / '.codex/AGENTS.md').read_text()
        self.assertEqual(guide, (ROOT / 'codex/AGENTS.md').read_text())
        self.assertIn('# Personal working agreements', guide)
        self.assertEqual(guide.count('<!-- dotfiles:caveman:start -->'), 1)

    def test_setup_wrapper_preserves_existing_personal_guidance(self):
        original = '# My personal agreements\n\nKeep these exact instructions.\n'
        guide = self.put('.codex/AGENTS.md', original)
        self.setup_wrapper()
        self.assertTrue(guide.read_text().startswith(original))
        self.assertNotIn('# Personal working agreements', guide.read_text())
        self.assertEqual(guide.read_text().count('<!-- dotfiles:caveman:start -->'), 1)
        self.assertFalse(guide.is_symlink())

    def test_setup_wrapper_rejects_invalid_inputs_before_disabling_codex_plugins(self):
        cases = [('.claude/settings.json', '{'),
                 ('.claude/settings.json', '{"enabledPlugins": []}'),
                 ('.config/caveman/config.json', '[]'),
                 ('.codex/AGENTS.md', '<!-- dotfiles:caveman:start -->\n')]
        for index, (relative, content) in enumerate(cases):
            with self.subTest(relative=relative, content=content):
                self.home = Path(self.temp.name) / str(index)
                config = self.put('.codex/config.toml',
                                  '[plugins."caveman@caveman"]\nenabled = true\n'
                                  '[plugins."caveman@dotfiles"]\nenabled = true\n')
                invalid = self.put(relative, content)
                before = {path: (path.read_bytes(), path.stat().st_mtime_ns)
                          for path in [config, invalid]}
                self.setup_wrapper(success=False)
                for path, state in before.items():
                    self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), state)
                self.assertFalse((self.home / '.agents').exists())

    def test_check_only_does_not_create_or_change_user_files(self):
        self.apply('--check')
        self.assertEqual(list(self.home.iterdir()), [])
        paths = [self.put('.codex/AGENTS.md', '# Personal rules\n'),
                 self.put('.claude/settings.json', '{"enabledPlugins":{"caveman@caveman":true}}\n'),
                 self.put('.config/caveman/config.json', '{"defaultMode":"off"}\n')]
        before = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in paths}
        self.apply('--check')
        for path, state in before.items():
            self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), state)
        self.assertFalse((self.home / '.agents').exists())

    def test_complete_family_is_discoverable_in_both_hosts(self):
        self.apply()
        expected = {path.parent.name for path in SKILLS.glob('*/SKILL.md')}
        self.assertEqual(len(expected), 22)
        self.assertTrue({'caveman-review', 'caveman-commit', 'caveman-help',
                         'caveman', 'ultracave', 'megacave'} <= expected)
        for directory in ['.agents/skills', '.claude/skills']:
            found = {path.parent.name for path in (self.home / directory).glob('*/SKILL.md')}
            self.assertEqual(found, expected)
            for name in expected:
                self.assertEqual((self.home / directory / name).resolve(), SKILLS / name)
        self.assertEqual(len(list((self.home / '.claude/agents').glob('cavecrew-*.md'))), 3)
        for relative in ['.codex/AGENTS.md', '.claude/CLAUDE.md']:
            self.assertIn('`ultracave`', (self.home / relative).read_text())
        self.assertTrue((self.home / '.agents/CAVEMAN.md').is_file())

    def test_existing_guidance_and_configuration_survive_reruns(self):
        original = '# Personal rules\n\nKeep my exact prose.\n'
        self.put('.codex/AGENTS.md', original)
        self.put('.claude/CLAUDE.md', original)
        config = self.put('.config/caveman/config.json', '{"defaultMode":"off","custom":{"enabled":true}}\n')
        self.apply()
        self.assertEqual(json.loads(config.read_text()), {'defaultMode': 'ultra', 'custom': {'enabled': True}})
        paths = [self.home / name for name in ['.codex/AGENTS.md', '.claude/CLAUDE.md',
                                               '.config/caveman/config.json', '.agents/CAVEMAN.md']]
        for path in paths[:2]:
            path.write_text(path.read_text() + '\n# Later personal rule\nKeep this too.\n')
        before = {path: (path.read_bytes(), path.lstat().st_mtime_ns) for path in paths}
        result = self.apply()
        self.assertIn('0 links updated', result.stdout)
        for path in paths:
            self.assertEqual((path.read_bytes(), path.lstat().st_mtime_ns), before[path])
        for path in paths[:2]:
            self.assertTrue(path.read_text().startswith(original))
            self.assertEqual(path.read_text().count('<!-- dotfiles:caveman:start -->'), 1)
        self.assertEqual(list(self.home.rglob('*.bak.*')), [])

    def test_duplicate_claude_plugins_are_disabled_without_losing_preferences(self):
        original = {
            'enabledPlugins': {'caveman@caveman': True, 'caveman@dotfiles': True,
                               'personal@local': True, 'caveman@personal': True},
            'editorMode': 'vim',
            'permissions': {'allow': ['Read'], 'deny': ['Bash(rm:*)']},
        }
        path = self.put('.claude/settings.json', json.dumps(original) + '\n')
        self.apply()
        expected = dict(original, enabledPlugins=dict(original['enabledPlugins'],
                        **{'caveman@caveman': False, 'caveman@dotfiles': False}))
        self.assertEqual(json.loads(path.read_text()), expected)
        before = path.read_bytes(), path.stat().st_mtime_ns
        self.apply()
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)

    def test_claude_settings_are_not_created_or_reformatted_without_duplicates(self):
        self.apply()
        path = self.home / '.claude/settings.json'
        self.assertFalse(path.exists())
        original = '{ "editorMode" : "vim", "enabledPlugins" : {"personal@local": true} }\n'
        path.write_text(original)
        before = path.read_bytes(), path.stat().st_mtime_ns
        self.apply()
        self.assertEqual((path.read_bytes(), path.stat().st_mtime_ns), before)

    def test_conflicting_directory_and_broken_symlink_are_backed_up(self):
        original = self.put('.agents/skills/caveman-review/personal.txt', 'keep original directory')
        self.put('.agents/skills/caveman-review/SKILL.md', 'original skill')
        broken = self.home / '.claude/skills/caveman-review'
        broken.parent.mkdir(parents=True)
        broken.symlink_to(self.home / 'missing-original')
        unrelated = self.put('.agents/skills/personal/SKILL.md', 'personal skill')
        self.apply()
        backup_root = self.home / '.agents/backups/caveman'
        backups = list((backup_root / 'codex-skills').glob('caveman-review.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / 'personal.txt').read_text(), 'keep original directory')
        backups = list((backup_root / 'claude-skills').glob('caveman-review.bak.*'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(os.readlink(backups[0]), str(self.home / 'missing-original'))
        self.assertEqual(unrelated.read_text(), 'personal skill')
        self.assertEqual(len(list((self.home / '.agents/skills').glob('*/SKILL.md'))), 23)
        self.apply()
        self.assertEqual(len(list((backup_root / 'claude-skills').glob('caveman-review.bak.*'))), 1)

    def test_invalid_user_files_fail_before_installation(self):
        cases = [('invalid-json', '.config/caveman/config.json', '{'),
                 ('json-array', '.config/caveman/config.json', '[]'),
                 ('invalid-claude-json', '.claude/settings.json', '{'),
                 ('claude-json-array', '.claude/settings.json', '[]'),
                 ('claude-plugin-array', '.claude/settings.json', '{"enabledPlugins": []}'),
                 ('bad-guidance', '.claude/CLAUDE.md', '<!-- dotfiles:caveman:start -->\n')]
        for label, relative, content in cases:
            with self.subTest(label=label):
                self.home = Path(self.temp.name) / label
                path = self.put(relative, content)
                self.apply(success=False)
                self.assertEqual(path.read_text(), content)
                self.assertFalse((self.home / '.agents').exists())

    def test_user_file_symlinks_and_permissions_are_preserved(self):
        for relative, body in [('.codex/AGENTS.md', '# My Codex rules\n'),
                               ('.claude/CLAUDE.md', '# My Claude rules\n'),
                               ('.claude/settings.json', '{"enabledPlugins":{"caveman@caveman":true}}\n'),
                               ('.config/caveman/config.json', '{"custom":true}\n')]:
            target = self.put('personal/' + Path(relative).name, body)
            target.chmod(0o640)
            link = self.home / relative
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(target)
        self.apply()
        for relative in ['.codex/AGENTS.md', '.claude/CLAUDE.md', '.claude/settings.json',
                         '.config/caveman/config.json']:
            path = self.home / relative
            self.assertTrue(path.is_symlink())
            self.assertEqual(path.stat().st_mode & 0o777, 0o640)
        self.assertIn('# My Codex rules\n', (self.home / '.codex/AGENTS.md').read_text())


if __name__ == '__main__':
    unittest.main()
