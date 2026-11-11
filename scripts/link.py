#!/usr/bin/env python3
"""Preview, link, or remove selected GNU Stow packages without provisioning."""

import argparse
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[1]


STOW_INSPECT = r'''
use JSON::PP qw(decode_json encode_json);
use File::Spec;
my $script = shift @ARGV;
require $script;
my $request = decode_json(do { local $/; <STDIN> });
my ($options, $unstow, $stow) = main::process_options();
{
    package DotfilesStow;
    our @ISA = ('Stow');
    sub read_a_link {
        my ($self, $path) = @_;
        my $absolute = File::Spec->rel2abs($path);
        return $self->{dotfiles_links}{$absolute}
            if !$self->link_task_action($path) && exists $self->{dotfiles_links}{$absolute};
        return $self->SUPER::read_a_link($path);
    }
}
my $planner = DotfilesStow->new(%$options);
$planner->{dotfiles_links} = $request->{links} || {};
if ($request->{sources}) {
    my %ignored;
    $planner->within_target_do(sub {
        for my $package (keys %{$request->{sources}}) {
            $ignored{$package} = [grep {
                $planner->ignore($planner->{stow_path}, $package, $_)
            } @{$request->{sources}{$package}}];
        }
    });
    print encode_json(\%ignored);
} else {
    $planner->plan_unstow(@$unstow);
    $planner->plan_stow(@$stow);
    my %conflicts = $planner->get_conflicts;
    print encode_json(\%conflicts);
}
'''


def profile_packages(profile):
    return [line.split('#', 1)[0].strip()
            for line in (ROOT / 'profiles' / profile).read_text().splitlines()
            if line.split('#', 1)[0].strip()]


def inspect_stow(command, **request):
    # Load Stow's CLI as its own tests do. This retains its interpreter, library
    # paths, rc options, and Perl ignore semantics without executing any tasks.
    executable = Path(shutil.which('stow')).resolve()
    with executable.open() as stream:
        interpreter = shlex.split(stream.readline().removeprefix('#!').strip())
    result = subprocess.run([*interpreter, '-e', STOW_INSPECT, str(executable), *command[1:]],
                            input=json.dumps(request), capture_output=True, text=True)
    if result.returncode:
        raise ValueError(result.stderr.strip() or 'GNU Stow inspection failed')
    return json.loads(result.stdout)


def preflight(packages, home, available, command):
    normalizations = {}
    conflicts = []
    sources = {}
    for package in packages:
        directory = ROOT / package
        if not directory.is_dir():
            raise ValueError(f'Package source is missing: {directory}')
        sources[package] = list(directory.rglob('*'))
    excluded = inspect_stow(command, sources={
        package: [str(source.relative_to(ROOT / package)) for source in paths]
        for package, paths in sources.items()}) if packages else {}
    for package, paths in sources.items():
        directory = ROOT / package
        ignored = set(excluded[package])
        for source in paths:
            relative = source.relative_to(directory)
            if (any(str(path) in ignored for path in (relative, *relative.parents))
                    or (source.is_dir() and not source.is_symlink())):
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
                    owned = next((ROOT / owner / parent for owner in available
                                  if destination.resolve() == (ROOT / owner / parent).resolve()), None)
                    if owned is not None:
                        if os.path.isabs(os.readlink(destination)):
                            normalizations[destination] = owned
                    else:
                        conflicts.append(str(destination))
                elif destination.exists() and not destination.is_dir():
                    conflicts.append(str(destination))
            if target.is_symlink() and os.path.isabs(os.readlink(target)):
                normalizations[target] = source
    if conflicts:
        raise ValueError('Unmanaged targets preserved; resolve these conflicts first:\n  '
                         + '\n  '.join(sorted(set(conflicts))))
    if packages:
        # Model only the known owned links as relative; Stow can then detect
        # every planning conflict before normalization changes the real target.
        planned = inspect_stow(command, links={
            str(target): os.path.relpath(source, target.parent)
            for target, source in normalizations.items()})
        if planned:
            details = [message for action in planned.values() for messages in action.values()
                       for message in messages]
            raise ValueError('Stow conflicts preserved; resolve these conflicts first:\n  '
                             + '\n  '.join(details))
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
    command = ['stow', '--dir', str(ROOT), '--target', str(home), '--no-folding',
               '--delete' if args.delete else '--stow', *stow_packages]
    normalizations = preflight(stow_packages, home, available, command)
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
