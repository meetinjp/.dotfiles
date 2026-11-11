#!/usr/bin/env bash
# Optional Linux setup. Download missing tools from their official releases;
# authentication and the first sync remain explicit, manual steps.
set -euo pipefail

if [[ "$(uname -s)" != Linux ]]; then
	echo "Proton Drive setup supports Linux only." >&2
	exit 1
fi

# Version pins and checksums from the official download pages:
# https://downloads.rclone.org/v1.76.0/SHA256SUMS
# https://proton.me/download/drive/cli/index.html
rclone_version=1.76.0
proton_version=0.9.0
case "$(uname -m)" in
	x86_64)
		rclone_arch=amd64
		proton_arch=x64
		rclone_sha256=b00f00b3266c3764413afe599d3ec316f6f43b3e0ea8a0bc1d186d2133e46df7
		proton_sha512=3533025ba69ae112b64e3e01fbcc1ad0688136a4043f6cf6a72886967d85fdcd9ec235479c2e113171614be5225bfba93427509a05ca5aa6071d924fa7e91ca8
		;;
	aarch64|arm64)
		rclone_arch=arm64
		proton_arch=arm64
		rclone_sha256=ee169016675e23a69d77240565133ff7dbc9b33d16fa8f7053d4af39f1eaeb78
		proton_sha512=c8d5a6b174e57f06d05cb5483400b9963faf58e743b6b33706bb73ecff718047ffce6b439994255b94b5b226b90d2e91bef7418ec96c1c3f5d8bf39b6cd01321
		;;
	*) echo "Unsupported CPU architecture: $(uname -m)" >&2; exit 1 ;;
esac

for dependency in curl unzip sha256sum sha512sum; do
	if ! command -v "$dependency" >/dev/null 2>&1; then
		echo "Missing dependency: $dependency. Install it and rerun setup." >&2
		exit 1
	fi
done

dotfiles="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$HOME/.local/bin" "$HOME/ProtonDrive"
export PATH="$HOME/.local/bin:$PATH"

if ! command -v rclone >/dev/null 2>&1; then
	archive="rclone-v${rclone_version}-linux-${rclone_arch}"
	curl --fail --show-error --location --proto '=https' --tlsv1.2 \
		"https://downloads.rclone.org/v${rclone_version}/${archive}.zip" -o "$stage/rclone.zip"
	printf '%s  %s\n' "$rclone_sha256" "$stage/rclone.zip" | sha256sum --check
	unzip -p "$stage/rclone.zip" "$archive/rclone" > "$stage/rclone"
	install -m 755 "$stage/rclone" "$HOME/.local/bin/rclone"
else
	echo "rclone is already installed; leaving it unchanged."
fi

if ! command -v proton-drive >/dev/null 2>&1; then
	curl --fail --show-error --location --proto '=https' --tlsv1.2 \
		"https://proton.me/download/drive/cli/${proton_version}/linux-${proton_arch}/proton-drive" \
		-o "$stage/proton-drive"
	printf '%s  %s\n' "$proton_sha512" "$stage/proton-drive" | sha512sum --check
	install -m 755 "$stage/proton-drive" "$HOME/.local/bin/proton-drive"
else
	echo "proton-drive is already installed; leaving it unchanged."
fi

# Link only this helper: an unrelated local script must not block setup, and
# existing files must never be adopted or overwritten. Normal install.sh runs
# still manage the bin package through Stow.
helper_source="$dotfiles/bin/.local/bin/proton-sync"
helper_target="$HOME/.local/bin/proton-sync"
if [[ ! -e "$helper_target" && ! -L "$helper_target" ]]; then
	ln -s --relative "$helper_source" "$helper_target"
elif [[ ! "$helper_source" -ef "$helper_target" ]]; then
	echo "Refusing to replace existing $helper_target; resolve it manually and rerun setup." >&2
	exit 1
fi
echo "Tools and ~/ProtonDrive are ready. No login or sync has been performed."
echo "Follow the Proton Drive section in $dotfiles/README.md to authenticate and initialize sync."
