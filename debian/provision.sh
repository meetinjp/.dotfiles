#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Debian/Ubuntu (TUXEDO OS) package provisioning — the apt analog of macOS's
# `brew bundle`. Called by install.sh when running on a Debian-family distro.
#
# TUXEDO OS = Ubuntu 24.04 LTS + KDE Plasma + SDDM. The niri/Noctalia/Ghostty/
# Zen stack is Arch/AUR-native and mostly NOT in Ubuntu's apt repos, so this
# installs it via PPAs / official scripts / cargo / tarballs.
#
# NOT handled here (TUXEDO OS ships them natively — do NOT reinstall):
#   tuxedo-drivers, Tuxedo Control Center (tccd/tomte), the TUXEDO kernel, fan
#   control, keyboard backlight, battery charge limit, 2.5G ethernet.
#
# ⚠️  UNTESTED on real hardware as written — authored from a verified research
# spec but never run on Tuxedo OS. Items marked [LIVE] need verification on the
# actual box (PPA resolution, Qt floor for Noctalia, exact pin versions).
#
# Resilient by design: NOT `set -e` — one failed optional install logs a
# warning and the rest continues. Idempotent — every step skips when its
# target already exists.
# ---------------------------------------------------------------------------
set -uo pipefail

# ── Point-in-time version pins — bump to current at run time ────────────────
GO_VER="${GO_VER:-1.26.2}"                 # https://go.dev/dl/
NVM_TAG="${NVM_TAG:-v0.40.5}"              # https://github.com/nvm-sh/nvm/tags
NOCTALIA_QS_TAG="${NOCTALIA_QS_TAG:-}"     # pin a tag from noctalia-dev/noctalia-qs (empty = latest tag)

log()  { printf '  \033[1m%s\033[0m\n' "$*"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

if [[ "$(uname -s)" == Darwin ]] || ! have apt-get; then
	echo "debian/provision.sh: not a Debian-family system — skipping."
	exit 0
fi

ARCH_DEB="$(dpkg --print-architecture)"

# ── 1. apt base + desktop + CLI ─────────────────────────────────────────────
# Build deps (cargo, lib*-dev, cmake/ninja, qt6) are here so the cargo-built and
# source-built components (yazi, xwayland-satellite, niri fallback, noctalia-qs)
# can compile. eza/ripgrep/fd-find/fzf/zsh-plugins/neovim ARE in noble apt.
APT_PKGS=(
	git stow build-essential curl ca-certificates unzip pkg-config
	cmake ninja-build cargo rustc gcc clang
	libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev
	libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpipewire-0.3-dev
	libpango1.0-dev libdisplay-info-dev
	qt6-base-dev qt6-declarative-dev qt6-shadertools-dev spirv-tools libcli11-dev
	qt6-wayland wayland-protocols
	kanshi wlsunset wl-clipboard cliphist grim slurp brightnessctl playerctl
	pamixer pavucontrol xwayland
	xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-utils gnome-keyring
	libnotify-bin power-profiles-daemon fwupd udisks2
	zsh zsh-autosuggestions zsh-syntax-highlighting tmux ripgrep eza fd-find fzf
	neovim gnupg pinentry-curses gh python3
	fonts-firacode fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk locales
	software-properties-common
)
log "apt: updating + installing base/desktop/CLI packages…"
sudo apt-get update -y || warn "apt update failed"
sudo apt-get install -y "${APT_PKGS[@]}" || warn "some apt packages failed (continuing)"

# fd ships as `fdfind` on Debian — add a `fd` shim on PATH (nvim/yazi expect fd).
if have fdfind && ! have fd; then
	mkdir -p "$HOME/.local/bin"
	ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
	log "linked fd → fdfind"
fi

# ── 2. PPAs: niri, ghostty, keyd ────────────────────────────────────────────
add_ppa() {  # add_ppa <ppa> <apt-pkg> [check-cmd]
	local ppa="$1" pkg="$2" check="${3:-$2}"
	have "$check" && { log "$pkg already installed."; return; }
	log "adding $ppa + installing $pkg… [LIVE: verify PPA resolves on the box]"
	sudo add-apt-repository -y "$ppa" || { warn "add-apt-repository $ppa failed"; return; }
	sudo apt-get update -y || true
	sudo apt-get install -y "$pkg" || warn "$pkg install failed"
}
# niri ships /usr/share/wayland-sessions/niri.desktop → SDDM lists it; KDE stays.
add_ppa ppa:avengemedia/danklinux niri
add_ppa ppa:mkasberg/ghostty-ubuntu ghostty
# keyd: setup.sh step 6 keys off `command -v keyd` and writes /etc/keyd/default.conf.
add_ppa ppa:keyd-team/ppa keyd

# ── 3. Rust toolchain (for cargo-built tools + niri source fallback) ────────
if ! have rustup; then
	log "installing rustup (rustup.rs)…"
	curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || warn "rustup install failed"
fi
# shellcheck disable=SC1091
[[ -f "$HOME/.cargo/env" ]] && source "$HOME/.cargo/env"
have rustup && rustup default stable >/dev/null 2>&1 || true

cargo_install() {  # cargo_install <bin> <crate...>
	local bin="$1"; shift
	have "$bin" && { log "$bin already installed."; return; }
	have cargo || { warn "cargo missing — cannot install $bin"; return; }
	log "cargo install $* …"
	cargo install --locked "$@" || warn "cargo install $bin failed"
}
cargo_install yazi yazi-fm yazi-cli
cargo_install xwayland-satellite xwayland-satellite

# ── 4. starship prompt ──────────────────────────────────────────────────────
if ! have starship; then
	log "installing starship…"
	curl -sS https://starship.rs/install.sh | sh -s -- -y || warn "starship install failed"
fi

# ── 5. FiraCode Nerd Font (apt fonts-firacode has no Nerd glyphs) ───────────
if ! fc-list 2>/dev/null | grep -qi 'FiraCode Nerd Font'; then
	log "installing FiraCode Nerd Font…"
	mkdir -p "$HOME/.local/share/fonts"
	if curl -fsSL -o /tmp/FiraCode.zip \
		https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.zip; then
		unzip -o /tmp/FiraCode.zip -d "$HOME/.local/share/fonts/" >/dev/null && fc-cache -f >/dev/null
	else
		warn "FiraCode Nerd Font download failed"
	fi
fi

# ── 6. Go toolchain (official tarball; apt golang-go lags ~2y) ──────────────
if [[ ! -x /usr/local/go/bin/go ]]; then
	log "installing Go ${GO_VER} → /usr/local/go… [bump GO_VER if stale]"
	if curl -fsSL "https://go.dev/dl/go${GO_VER}.linux-${ARCH_DEB}.tar.gz" -o /tmp/go.tgz; then
		sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tgz
	else
		warn "Go download failed (check GO_VER / arch)"
	fi
fi

# ── 7. Docker (official apt repo; docker.io lags + lacks compose v2) ────────
if ! have docker; then
	log "installing docker-ce (official repo)…"
	sudo install -m 0755 -d /etc/apt/keyrings
	if sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc; then
		sudo chmod a+r /etc/apt/keyrings/docker.asc
		sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-${VERSION_CODENAME:-noble}}")
Components: stable
Architectures: ${ARCH_DEB}
Signed-By: /etc/apt/keyrings/docker.asc
EOF
		sudo apt-get update -y || true
		sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
			docker-buildx-plugin docker-compose-plugin || warn "docker-ce install failed"
		warn "docker installed. To use without sudo (manual): sudo usermod -aG docker \"\$USER\" && relog."
	else
		warn "docker GPG key fetch failed"
	fi
fi

# ── 8. Zen browser (per-user tarball; profile lives at ~/.zen/, see install.sh) ─
if [[ ! -x "$HOME/.local/bin/zen" ]]; then
	log "installing Zen browser (per-user)…"
	curl -fsSL https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh | bash \
		|| warn "Zen install failed"
fi

# ── 9. uv / nvm / bun (per-user runtime managers; cross-distro) ─────────────
have uv  || { log "installing uv…";  curl -LsSf https://astral.sh/uv/install.sh | sh || warn "uv failed"; }
[[ -s "$HOME/.nvm/nvm.sh" ]] || { log "installing nvm ${NVM_TAG}…"; curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" | bash || warn "nvm failed"; }
[[ -x "$HOME/.bun/bin/bun" ]] || { log "installing bun…"; curl -fsSL https://bun.com/install | bash || warn "bun failed"; }

# ── 10. Noctalia (Quickshell-based niri shell) — GATED on Qt >= 6.6 ─────────
# Upstream quickshell won't run noctalia-shell since v4.6.0; use the fork
# noctalia-qs (binary `qs`). It needs Qt >= 6.6. Stock noble = Qt 6.4 → SKIP
# with a warning; Tuxedo OS backports Qt >= 6.7 → builds. [LIVE: confirm on box]
install_noctalia() {
	have qs && { log "noctalia-qs (qs) already installed."; return; }
	local qtver qtmajor qtminor
	qtver="$(qmake6 --version 2>/dev/null | grep -oE 'Qt version [0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)"
	if [[ -z "$qtver" ]]; then warn "qmake6 not found — skipping Noctalia (install qt6-base-dev / use Tuxedo OS)."; return; fi
	qtmajor="${qtver%%.*}"; qtminor="${qtver#*.}"
	if (( qtmajor < 6 || (qtmajor == 6 && qtminor < 6) )); then
		warn "Qt $qtver < 6.6 — skipping Noctalia (needs >=6.6; Tuxedo OS backports it). Bar/launcher won't run until then."
		return
	fi
	log "building noctalia-qs (Qt $qtver ok)… [LIVE: pin NOCTALIA_QS_TAG]"
	local d branch_arg=(); d="$(mktemp -d)"
	[[ -n "$NOCTALIA_QS_TAG" ]] && branch_arg=(--branch "$NOCTALIA_QS_TAG")
	if git clone --depth 1 "${branch_arg[@]}" \
		https://github.com/noctalia-dev/noctalia-qs "$d/noctalia-qs"; then
		( cd "$d/noctalia-qs" \
			&& cmake -GNinja -B build -DCMAKE_BUILD_TYPE=Release \
			&& cmake --build build \
			&& sudo cmake --install build ) || warn "noctalia-qs build failed"
	else
		warn "noctalia-qs clone failed"
	fi
	rm -rf "$d"
	# Shell config (runs inside the niri session via `qs -c noctalia-shell`).
	if [[ ! -d "$HOME/.config/quickshell/noctalia-shell" ]]; then
		mkdir -p "$HOME/.config/quickshell/noctalia-shell"
		curl -fsSL https://github.com/noctalia-dev/noctalia/releases/latest/download/noctalia-latest.tar.gz \
			| tar -xz --strip-components=1 -C "$HOME/.config/quickshell/noctalia-shell" \
			|| warn "noctalia-shell fetch failed"
	fi
}
install_noctalia

echo "Debian provisioning done (review any '!' warnings above)."
