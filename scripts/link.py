#!/usr/bin/env python3
"""Preview, link, or remove selected GNU Stow packages without provisioning."""

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[1]


def profile_packages(profile):
    return [line.split('#', 1)[0].strip()
            for line in (ROOT / 'profiles' / profile).read_text().splitlines()
            if line.split('#', 1)[0].strip()]


def ignored(path):
    # These metadata files are excluded by Stow's built-in ignore list too.
    return any(re.match(r'^(?:\.git(?:$|ignore$|attributes$|modules$)|README(?:\..*)?$|COPYING$|LICENSE(?:\..*)?$)',
                        part) for part in path.parts)


def preflight(packages, home):
    normalizations = {}
    conflicts = []
    for package in packages:
        directory = ROOT / package
        if not directory.is_dir():
            raise ValueError(f'Package source is missing: {directory}')
        for source in directory.rglob('*'):
            relative = source.relative_to(directory)
            if ignored(relative) or (source.is_dir() and not source.is_symlink()):
                continue
            target = home / relative
            if target.exists() or target.is_symlink():
                if target.resolve() != source.resolve():
                    conflicts.append(str(target))
                    continue
            # A real file in place of a parent directory must fail before any
            # package is linked. Existing tree-folded links remain valid.
            for parent in relative.parents:
                if str(parent) == '.':
                    continue
                destination = home / parent
                if destination.is_symlink():
                    if destination.resolve() == (directory / parent).resolve():
                        if os.path.isabs(os.readlink(destination)):
                            normalizations[destination] = directory / parent
                    else:
                        conflicts.append(str(destination))
                elif destination.exists() and not destination.is_dir():
                    conflicts.append(str(destination))
            if target.is_symlink() and os.path.isabs(os.readlink(target)):
                normalizations[target] = source
    if conflicts:
        raise ValueError('Unmanaged targets preserved; resolve these conflicts first:\n  '
                         + '\n  '.join(sorted(set(conflicts))))
    return normalizations


def normalize(links):
    for target, source in links.items():
        temporary = target.with_name(f'.{target.name}.dotfiles-{uuid.uuid4().hex}')
        try:
            temporary.symlink_to(os.path.relpath(source, target.parent),
                                 target_is_directory=source.is_dir())
            os.replace(temporary, target)
        finally:
            if temporary.is_symlink():
                temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--profile', choices=['core', 'desktop', 'macos', 'agents'], default='core')
    parser.add_argument('--dry-run', '-n', action='store_true', help='inspect targets without changing files')
    parser.add_argument('--delete', action='store_true', help='remove only the selected managed links')
    parser.add_argument('packages', nargs='*', help='specific packages instead of the selected profile')
    args = parser.parse_args()
    available = {package for profile in ['core', 'desktop', 'macos', 'agents']
                 for package in profile_packages(profile)}
    packages = list(dict.fromkeys(args.packages or profile_packages(args.profile)))
    unknown = set(packages) - available
    if unknown:
        parser.error('unknown packages: ' + ', '.join(sorted(unknown)))
    if sys.platform != 'linux' and set(packages) & {'bin', 'niri', 'kanshi', 'systemd'}:
        parser.error('the desktop packages require Linux')
    if 'nvim' in packages and not (ROOT / 'nvim/.config/nvim/init.lua').is_file():
        raise ValueError('Initialize Neovim first: git submodule update --init nvim/.config/nvim')
    if not shutil.which('stow'):
        raise ValueError('GNU Stow is required. Ubuntu: sudo apt install stow; macOS: brew install stow')
    home = Path.home()
    stow_packages = [package for package in packages if package != 'zen']
    normalizations = preflight(stow_packages, home)
    browser = [sys.executable, str(ROOT / 'scripts/link-zen.py')]
    if args.delete:
        browser.append('--delete')
    if 'zen' in packages:
        subprocess.run(browser + ['--dry-run'], check=True)
    action = 'remove' if args.delete else 'link'
    print(f"{'Would' if args.dry_run else 'Will'} {action}: {', '.join(packages)}", flush=True)
    if normalizations:
        print(f"Normalize {len(normalizations)} absolute link(s) already pointing to this checkout.", flush=True)
    if args.dry_run:
        return
    normalize(normalizations)
    if stow_packages:
        command = ['stow', '--dir', str(ROOT), '--target', str(home), '--no-folding',
                   '--delete' if args.delete else '--stow', *stow_packages]
        subprocess.run(command + ['--simulate'], check=True)
        subprocess.run(command, check=True)
    if 'zen' in packages:
        subprocess.run(browser, check=True)
    if sys.platform == 'darwin' and 'ghostty' in packages:
        # Ghostty reads this platform layer after its shared XDG config.
        target = home / 'Library/Application Support/com.mitchellh.ghostty/config'
        include = f'config-file = {home}/.config/ghostty/config-macos.conf'.encode()
        content = target.read_bytes() if target.exists() else b''
        if args.delete:
            remaining = b''.join(line for line in content.splitlines(keepends=True)
                                 if line.rstrip(b'\r\n') != include)
            if remaining != content:
                # Write through an existing config symlink and retain its mode.
                target.write_bytes(remaining)
        elif include not in content.splitlines():
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('ab') as stream:
                stream.write((b'\n' if content and not content.endswith(b'\n') else b'') + include + b'\n')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
