#!/usr/bin/env python3
"""Link the managed user.js into an existing default Zen profile."""

import argparse
import configparser
import os
from pathlib import Path
import sys


SOURCE = Path(__file__).resolve().parents[1] / 'zen/.config/zen/user.js'


def read_ini(path):
    config = configparser.ConfigParser(interpolation=None)
    if path.is_file():
        with path.open(encoding='utf-8') as stream:
            config.read_file(stream)
    return config


def existing_profile(root, raw_path, relative=True):
    if not raw_path:
        return None
    profile = Path(raw_path).expanduser()
    if not profile.is_absolute():
        if not relative:
            return None
        profile = root / profile
    return profile if profile.is_dir() else None


def find_profile(home):
    config_home = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config')
    roots = [config_home / 'zen', home / '.zen',
             home / 'Library/Application Support/zen']
    for root in roots:
        installs = read_ini(root / 'installs.ini')
        for section in installs.sections():
            profile = existing_profile(root, installs[section].get('Default'))
            if profile:
                return profile
        profiles = read_ini(root / 'profiles.ini')
        for section in profiles.sections():
            settings = profiles[section]
            if not section.startswith('Profile') or settings.get('Default') != '1':
                continue
            profile = existing_profile(root, settings.get('Path'),
                                       settings.get('IsRelative', '1') != '0')
            if profile:
                return profile
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', '--check', action='store_true',
                       help='preview the link and detect conflicts without changes')
    parser.add_argument('--delete', action='store_true',
                       help='remove only a link pointing to this checkout')
    args = parser.parse_args()
    profile = find_profile(Path.home())
    if profile is None:
        print('Zen: no existing default profile found; launch Zen once and rerun.')
        return 0
    target = profile / 'user.js'
    owned = target.is_symlink() and target.resolve() == SOURCE.resolve()
    if args.delete:
        if owned:
            if not args.dry_run:
                target.unlink()
            print(f"Zen: {'would remove' if args.dry_run else 'removed'} {target}")
        else:
            print(f'Zen: preserved {target}; it is not a link owned by this checkout.')
        return 0
    if owned:
        print(f'Zen: {target} already linked.')
        return 0
    if target.exists() or target.is_symlink():
        print(f'Zen: refusing to replace unmanaged {target}; preserve or move it before retrying.',
              file=sys.stderr)
        return 1
    if not SOURCE.is_file():
        print(f'Zen: managed source is missing: {SOURCE}', file=sys.stderr)
        return 1
    if args.dry_run:
        print(f'Zen: would link {target} to {SOURCE}')
        return 0
    target.symlink_to(os.path.relpath(SOURCE, target.parent))
    print(f'Zen: linked {target}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (OSError, configparser.Error) as error:
        print(f'Zen: {error}', file=sys.stderr)
        sys.exit(1)
