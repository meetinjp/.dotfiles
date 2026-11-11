#!/usr/bin/env bash
# Explicit GPG signing and SSH-agent setup. Private key material stays outside Git.
set -euo pipefail
# shellcheck source=scripts/setup-common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/setup-common.sh"
git_global_value() {
	git config --global --includes --get "$1" 2>/dev/null && return
	# --global selects only ~/.gitconfig when both global files exist. Git's
	# normal lookup also reads the earlier XDG file; use it as the fallback.
	if [[ -z "${GIT_CONFIG_GLOBAL:-}" && -e "$HOME/.gitconfig" ]]; then
		git config --file "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" --includes --get "$1" 2>/dev/null
	fi
}
GIT_NAME="${GIT_NAME:-$(git_global_value user.name || true)}"
GIT_EMAIL="${GIT_EMAIL:-$(git_global_value user.email || true)}"
if [[ -z "$GIT_NAME" || -z "$GIT_EMAIL" ]]; then
	echo "Configure identity first with ./setup.sh git." >&2
	exit 1
fi
GPG="$(command -v gpg || true)"
[[ -n "$GPG" ]] || { echo "Install GnuPG before configuring keys." >&2; exit 1; }
GPG_TTY="$(tty 2>/dev/null || echo /dev/tty)"
export GPG_TTY
mkdir -p "$HOME/.gnupg"
chmod 700 "$HOME/.gnupg"
gpg_keyid_for() {
	"$GPG" --list-secret-keys --with-colons --fingerprint "$1" | awk -F: '/^fpr:/ {print $10; exit}'
}
# Stage gpg-agent BEFORE we try to use it. On a fresh box without a populated
# graphical session, /usr/bin/pinentry's dispatcher can hang silently when
# gpg-agent first asks for a passphrase — the dispatcher tries to pick a GUI
# variant and waits forever for a display that isn't there. pinentry-curses
# draws inline in the TTY and works regardless of session state, so we pin it
# up-front. Idempotent. (~/.gnupg already prepared at top of script.)
if ! grep -q '^pinentry-program' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
	# Resolve the pinentry binary dynamically (honors the Homebrew prefix on
	# macOS — /opt/homebrew or /usr/local — instead of a hardcoded /usr/bin).
	# macOS prefers pinentry-mac (GUI, Keychain-aware); Linux uses
	# pinentry-curses, which draws inline in the TTY and works regardless of
	# graphical-session state (avoids the dispatcher hang on a fresh box).
	if is_macos; then
		PINENTRY="$(command -v pinentry-mac || command -v pinentry-curses || command -v pinentry || true)"
	else
		PINENTRY="$(command -v pinentry-curses || command -v pinentry || true)"
	fi
	if [[ -n "$PINENTRY" ]]; then
		echo "pinentry-program $PINENTRY" >> ~/.gnupg/gpg-agent.conf
		echo "  pinned pinentry-program = $PINENTRY"
		gpgconf --kill gpg-agent 2>/dev/null || true
	else
		echo "  no pinentry found — install pinentry-mac (macOS) / pinentry (Linux) and rerun."
	fi
else
	echo "  pinentry-program already set."
fi

# One GPG key for everything:
#   - primary [C] (certify) + [S] subkey: commit/tag signatures
#   - [A] subkey: SSH auth, served by gpg-agent's ssh-agent socket
if "$GPG" --list-secret-keys "$GIT_EMAIL" &>/dev/null; then
	KEYID="$(gpg_keyid_for "$GIT_EMAIL")"
	echo "  existing key for $GIT_EMAIL (keyid=$KEYID) — using it."
else
	if confirm "No key for $GIT_EMAIL. Generate Ed25519, 2y validity? [Y/n]"; then
		"$GPG" --quick-gen-key "$GIT_NAME <$GIT_EMAIL>" ed25519 default 2y
		KEYID="$(gpg_keyid_for "$GIT_EMAIL")"
		[[ -n "${GIT_WORK_EMAIL:-}" ]] && \
			"$GPG" --quick-add-uid "$KEYID" "$GIT_NAME <$GIT_WORK_EMAIL>"
		echo "  generated keyid=$KEYID."
	fi
fi

if [[ -n "${KEYID:-}" ]]; then
	# Keep default signing settings before user includes so conditional profiles
	# retain precedence. Validate the complete candidate before changing Git state.
	python3 - "$KEYID" "$GPG" <<'PY'
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

home = Path.home()
xdg = Path(os.environ.get('XDG_CONFIG_HOME') or home / '.config') / 'git/config'
if os.environ.get('GIT_CONFIG_GLOBAL'):
    global_paths = [Path(os.environ['GIT_CONFIG_GLOBAL']).expanduser()]
else:
    global_paths = [path for path in (xdg, home / '.gitconfig')
                    if path.exists() or path.is_symlink()] or [home / '.gitconfig']
global_path = global_paths[0]
target = global_path.resolve()
target.parent.mkdir(parents=True, exist_ok=True)
lock = target.with_name(target.name + '.lock')
validation = None
evaluation = None
settings = {'user.signingkey': sys.argv[1], 'gpg.format': 'openpgp',
            'commit.gpgsign': 'true', 'tag.gpgsign': 'true',
            'gpg.program': sys.argv[2], 'gpg.openpgp.program': sys.argv[2]}


def config(*arguments, env=None, allowed=(0,)):
    result = subprocess.run(['git', 'config', *arguments], env=env,
                            capture_output=True, text=True)
    if result.returncode not in allowed:
        raise ValueError(result.stderr.strip() or 'git config failed')
    return result.stdout.rstrip('\n')


try:
    descriptor = os.open(lock, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
except FileExistsError:
    sys.exit(f'error: {lock} already exists; Git signing settings were not changed')
try:
    original = global_path.read_bytes() if global_path.exists() else b''
    with os.fdopen(descriptor, 'wb') as stream:
        stream.write(original)
    for key in settings:
        config('--file', str(lock), '--unset-all', key, allowed=(0, 5))
    remainder = lock.read_bytes()
    lock.write_bytes(b'')
    for key, value in settings.items():
        config('--file', str(lock), key, value)
    with lock.open('ab') as stream:
        stream.write(b'\n' + remainder)

    # Git resolves relative includes against the logical config path, even when
    # ~/.gitconfig is a symlink to a file in another directory.
    global_path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix='.dotfiles-signing-', dir=global_path.parent)
    os.close(descriptor)
    validation = Path(name)
    validation.unlink()
    validation.symlink_to(lock)
    descriptor, name = tempfile.mkstemp(prefix='.dotfiles-signing-', dir=global_path.parent)
    os.close(descriptor)
    evaluation = Path(name)
    # Normal Git lookup reads XDG first and ~/.gitconfig second. Evaluate both
    # with the candidate substituted, without loading repository/system values.
    for path in [validation, *global_paths[1:]]:
        config('--file', str(evaluation), '--add', 'include.path', str(path.absolute()))
    environment = dict(os.environ, GIT_CONFIG_GLOBAL=str(evaluation))
    for key, value in settings.items():
        arguments = ['--global', '--includes']
        if key in ('commit.gpgsign', 'tag.gpgsign'):
            arguments.append('--type=bool')
        if config(*arguments, '--get', key, env=environment) != value:
            raise ValueError('included signing settings override the selected OpenPGP key or program; '
                             'reconcile those settings before rerunning; Git configuration was not changed')
    current = global_path.read_bytes() if global_path.exists() else b''
    if current != original:
        raise ValueError('global Git configuration changed during setup; rerun without concurrent edits')
    lock.chmod(stat.S_IMODE(target.stat().st_mode) if target.exists() else 0o600)
    os.replace(lock, target)
except (OSError, ValueError) as error:
    sys.exit(f'error: {error}')
finally:
    if validation is not None:
        validation.unlink(missing_ok=True)
    if evaluation is not None:
        evaluation.unlink(missing_ok=True)
    lock.unlink(missing_ok=True)
PY

	# Add [A] authentication subkey if missing.
	if ! "$GPG" --list-keys --with-colons "$KEYID" | awk -F: '$1=="sub" && $12 ~ /a/{found=1} END{exit !found}'; then
		if confirm "No [A] subkey on $KEYID. Add one (ed25519, 2y) for SSH-over-GPG? [Y/n]"; then
			"$GPG" --quick-add-key "$KEYID" ed25519 auth 2y
			echo "  added [A] subkey."
		fi
	else
		echo "  [A] subkey already present."
	fi
fi

# ---------------------------------------------------------------------------
banner "5/10  SSH-over-GPG (gpg-agent serves the auth subkey)"
# ---------------------------------------------------------------------------
AUTH_KEYGRIP=""
if [[ -n "${KEYID:-}" ]]; then
	# ~/.gnupg already exists with 700 perms (hoisted at top).
	if ! grep -q '^enable-ssh-support' ~/.gnupg/gpg-agent.conf 2>/dev/null; then
		echo 'enable-ssh-support' >> ~/.gnupg/gpg-agent.conf
		echo "  enabled ssh-support in ~/.gnupg/gpg-agent.conf"
	else
		echo "  ssh-support already enabled in ~/.gnupg/gpg-agent.conf"
	fi

	AUTH_KEYGRIP="$("$GPG" --list-keys --with-colons --with-keygrip "$KEYID" | awk -F: '
		/^sub:/ { cap=$12; next }
		/^grp:/ { if (cap ~ /a/) { print $10; exit } }
	')"
	if [[ -n "$AUTH_KEYGRIP" ]]; then
		touch ~/.gnupg/sshcontrol
		if ! grep -q "^$AUTH_KEYGRIP" ~/.gnupg/sshcontrol; then
			echo "$AUTH_KEYGRIP" >> ~/.gnupg/sshcontrol
			echo "  registered keygrip $AUTH_KEYGRIP in ~/.gnupg/sshcontrol"
		else
			echo "  keygrip $AUTH_KEYGRIP already in ~/.gnupg/sshcontrol"
		fi
		gpgconf --kill gpg-agent 2>/dev/null || true
		echo "  gpg-agent reloaded."
	else
		echo "  no [A] subkey present — SSH-over-GPG not configured."
	fi
fi


if [[ -n "${KEYID:-}" ]]; then
	echo "Register the public signing key at https://github.com/settings/gpg/new:"
	"$GPG" --armor --export "$KEYID"
	if [[ -n "$AUTH_KEYGRIP" ]]; then
		echo "Register the public SSH key at https://github.com/settings/ssh/new:"
		"$GPG" --export-ssh-key "$GIT_EMAIL"
	fi
fi
