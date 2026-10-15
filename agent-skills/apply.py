#!/usr/bin/env python3
"""Install the shared Caveman skills and reconcile their global defaults."""

import argparse
import json
import os
from pathlib import Path
import stat
import sys
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parent
START = '<!-- dotfiles:caveman:start -->'
END = '<!-- dotfiles:caveman:end -->'
GUIDANCE = f'''{START}
# Caveman defaults

Start each new session in `ultracave` mode. Read `~/.agents/CAVEMAN.md` and
follow its skill instructions. Honor explicit mode changes, including
`stop caveman` and `normal mode`, for the rest of the session.
{END}'''


def merge_guidance(text):
    if START not in text and END not in text:
        separator = '' if not text or text.endswith('\n\n') else '\n' if text.endswith('\n') else '\n\n'
        return text + separator + GUIDANCE + '\n'
    if text.count(START) != 1 or text.count(END) != 1 or text.index(START) > text.index(END):
        raise ValueError('malformed dotfiles Caveman guidance markers; leaving the file unchanged')
    start, end = text.index(START), text.index(END) + len(END)
    return text[:start] + GUIDANCE + text[end:]


def write_text(path, text):
    # Resolve a pre-existing file symlink so personal config links stay intact.
    path = path.resolve()
    if path.exists() and path.read_text(encoding='utf-8') == text:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(text)
        temporary.chmod(mode)
        os.replace(temporary, path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    return True


def link(source, target, backup_dir):
    if target.is_symlink() and target.resolve() == source.resolve():
        return False
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_name(f'.{target.name}.dotfiles-{uuid.uuid4().hex}')
    try:
        # Create the replacement first: Windows may lack symlink privileges.
        temporary.symlink_to(source, target_is_directory=source.is_dir())
        if target.exists() or target.is_symlink():
            # Backups must stay outside skill/agent discovery directories.
            backup_dir.mkdir(parents=True, exist_ok=True)
            backup = backup_dir / f'{target.name}.bak.{time.time_ns()}'
            target.rename(backup)
            print(f'backed up {target} -> {backup}')
        os.replace(temporary, target)
    finally:
        if temporary.is_symlink():
            temporary.unlink()
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--home', type=Path, help='use an isolated home, ignoring config-directory environment overrides')
    args = parser.parse_args()
    home = args.home.expanduser().resolve() if args.home else Path.home()
    codex = home / '.codex'
    claude = home / '.claude'
    config = home / '.config'
    if not args.home:
        codex = Path(os.environ.get('CODEX_HOME') or codex).expanduser()
        claude = Path(os.environ.get('CLAUDE_CONFIG_DIR') or claude).expanduser()
        if os.environ.get('XDG_CONFIG_HOME'):
            config = Path(os.environ['XDG_CONFIG_HOME']).expanduser()
        elif sys.platform == 'win32':
            config = Path(os.environ.get('APPDATA') or home / 'AppData/Roaming')

    skills = sorted((ROOT / 'caveman/skills').glob('*/SKILL.md'))
    agents = sorted((ROOT / 'caveman/agents').glob('cavecrew-*.md'))
    if not skills or not (ROOT / 'CAVEMAN.md').is_file():
        raise ValueError('shared Caveman skill sources are missing')

    # Validate existing user files before making any changes.
    guidance = {}
    for path in (codex / 'AGENTS.md', claude / 'CLAUDE.md'):
        guidance[path] = merge_guidance(path.read_text(encoding='utf-8') if path.exists() else '')
    config_path = config / 'caveman/config.json'
    raw_config = config_path.read_text(encoding='utf-8') if config_path.exists() else '{}'
    settings = json.loads(raw_config)
    if not isinstance(settings, dict):
        raise ValueError(f'{config_path} must contain a JSON object')
    # Both old and current upstream hooks recognize "ultra" as ultracave.
    settings['defaultMode'] = 'ultra'

    linked = 0
    backups = home / '.agents/backups/caveman'
    for skill in skills:
        for directory, label in ((home / '.agents/skills', 'codex-skills'), (claude / 'skills', 'claude-skills')):
            linked += link(skill.parent, directory / skill.parent.name, backups / label)
    for agent in agents:
        linked += link(agent, claude / 'agents' / agent.name, backups / 'claude-agents')
    linked += link(ROOT / 'CAVEMAN.md', home / '.agents/CAVEMAN.md', backups / 'guidance')
    for path, text in guidance.items():
        write_text(path, text)
    # Preserve formatting too when the managed value is already correct.
    if json.loads(raw_config).get('defaultMode') != settings['defaultMode']:
        write_text(config_path, json.dumps(settings, indent=2) + '\n')
    print(f'Caveman: {len(skills)} shared skills per host, {linked} links updated; default ultracave.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError) as error:
        sys.exit(f'error: {error}')
