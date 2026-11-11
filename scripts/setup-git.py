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


def identity_value(variable, key, label):
    value = os.environ.get(variable) or git_config('--global', '--includes', '--get', key,
                                                allowed=(0, 1))
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    if not shutil.which('git'):
        raise ValueError('Git is required; install it and rerun')

    # Unlike --list, --get-regexp accepts a missing global config with status 1.
    # Validate all included settings before creating or changing any files.
    git_config('--global', '--includes', '--get-regexp', '.', allowed=(0, 1))
    name = identity_value('GIT_NAME', 'user.name', 'Git name')
    email = identity_value('GIT_EMAIL', 'user.email', 'Git email')
    work_email = os.environ.get('GIT_WORK_EMAIL', '')

    config_home = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
    personal = config_home / 'git/dotfiles'
    work = config_home / 'git/dotfiles-work'
    write_identity(personal, {'user.name': name, 'user.email': email})
    if work_email:
        write_identity(work, {'user.email': work_email})
        print(f'Work identity saved to {work}; include it explicitly where needed.')

    includes = git_config('--global', '--includes', '--path', '--get-all', 'include.path',
                          allowed=(0, 1))
    if str(personal) not in includes.splitlines():
        # Git updates the selected global file atomically and follows an existing
        # ~/.gitconfig symlink, retaining its target and unrelated configuration.
        git_config('--global', '--add', 'include.path', str(personal))
    print(f'Git identity configured through {personal}.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, EOFError) as error:
        sys.exit(f'error: {error}')
