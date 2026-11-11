#!/usr/bin/env python3
"""Configure Git identity without replacing existing global settings."""

import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def git_config(*arguments, allowed=(0,)):
    result = subprocess.run(['git', 'config', *arguments], capture_output=True, text=True)
    if result.returncode not in allowed:
        raise ValueError(result.stderr.strip() or 'git config failed')
    return result.stdout.rstrip('\n')


def global_files(config_home):
    selected = os.environ.get('GIT_CONFIG_GLOBAL')
    if selected is not None:
        return [Path(selected)]
    candidates = [config_home / 'git/config', Path.home() / '.gitconfig']
    # Git reads both files in this order, but --global queries only one of them.
    return [path for path in candidates if path.exists() or path.is_symlink()] or [candidates[1]]


def identity_value(variable, key, label, configs):
    value = os.environ.get(variable)
    if not value:
        for config in configs:
            existing = git_config('--file', str(config), '--includes', '--get', key,
                                  allowed=(0, 1))
            if existing:
                value = existing
    value = value or ''
    if not value.strip() and sys.stdin.isatty():
        value = input(f'{label}: ')
    if not value.strip():
        raise ValueError(f'{variable} is required when Git has no existing {key}; set it and rerun')
    return value


def write_identity(path, values):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        descriptor, name = tempfile.mkstemp(prefix=f'.{path.name}.', dir=path.parent)
        os.close(descriptor)
        temporary = Path(name)
        for key, value in values.items():
            git_config('--file', str(temporary), key, value)
        temporary.chmod(0o600)
        if path.is_file() and path.read_bytes() == temporary.read_bytes():
            path.chmod(0o600)
            return
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def include_defaults(configs, personal):
    # Generate the include with Git so paths containing quotes are escaped correctly.
    with tempfile.TemporaryDirectory(prefix='dotfiles-git-include-') as directory:
        header = Path(directory) / 'config'
        git_config('--file', str(header), '--add', 'include.path', str(personal))
        prefix = header.read_bytes()
    seen = set()
    for index, config in enumerate(configs):
        target = config.resolve()
        if target in seen:
            continue
        seen.add(target)
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + '.lock')
        # Git follows config symlinks and locks the resolved target. Hold that
        # same lock from the snapshot through replacement, leaving other locks intact.
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            os.close(descriptor)
            original = config.read_bytes() if config.exists() else b''
            bom = b'\xef\xbb\xbf' if original.startswith(b'\xef\xbb\xbf') else b''
            includes = git_config('--file', str(config), '--get-all', 'include.path',
                                  allowed=(0, 1)).splitlines()
            count = includes.count(str(personal))
            if index == 0 and original.removeprefix(bom).startswith(prefix) and count == 1:
                continue
            if index > 0 and not count:
                continue
            temporary.write_bytes(original)
            # Move only our own include. Other includes and their order stay intact.
            git_config('--file', str(temporary), '--fixed-value', '--unset-all',
                       'include.path', str(personal), allowed=(0, 5))
            content = bom + (prefix if index == 0 else b'') + temporary.read_bytes().removeprefix(bom)
            temporary.write_bytes(content)
            git_config('--file', str(temporary), '--get-regexp', '.', allowed=(0, 1))
            current = config.read_bytes() if config.exists() else b''
            if config.resolve() != target or current != original:
                raise ValueError('global Git configuration changed during setup; rerun without concurrent edits')
            if target.exists():
                temporary.chmod(target.stat().st_mode & 0o7777)
            os.replace(temporary, target)
            temporary = None
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    if not shutil.which('git'):
        raise ValueError('Git is required; install it and rerun')

    config_home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    configs = global_files(config_home)
    # Unlike --list, --get-regexp accepts a missing global config with status 1.
    # Validate all included settings before creating or changing any files.
    for config in configs:
        git_config('--file', str(config), '--includes', '--get-regexp', '.', allowed=(0, 1))
    name = identity_value('GIT_NAME', 'user.name', 'Git name', configs)
    email = identity_value('GIT_EMAIL', 'user.email', 'Git email', configs)
    work_email = os.environ.get('GIT_WORK_EMAIL', '')

    personal = config_home / 'git/dotfiles'
    work = config_home / 'git/dotfiles-work'
    write_identity(personal, {'user.name': name, 'user.email': email})
    if work_email:
        write_identity(work, {'user.email': work_email})
        print(f'Work identity saved to {work}; include it explicitly where needed.')

    # Updates are atomic and follow an existing ~/.gitconfig symlink, retaining
    # its target and unrelated configuration. Existing identities take precedence.
    include_defaults(configs, personal)
    print(f'Git identity defaults configured through {personal}; existing settings take precedence.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, EOFError) as error:
        sys.exit(f'error: {error}')
