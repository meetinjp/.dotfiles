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
NIRI_TAG="${NIRI_TAG:-v26.04}"             # https://github.com/YaLTeR/niri/tags (built from source — no apt pkg on noble)

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
	qt6-base-dev qt6-declarative-dev qt6-declarative-private-dev qt6-shadertools-dev
	qt6-svg-dev qt6-wayland qt6-wayland-dev qt6-wayland-private-dev
	spirv-tools libcli11-dev wayland-protocols
	libdrm-dev libjemalloc-dev libpam0g-dev libxcb-cursor-dev libclang-dev
	libpolkit-agent-1-dev libpolkit-gobject-1-dev
	kanshi wlsunset wl-clipboard cliphist grim slurp brightnessctl playerctl
	pamixer pavucontrol xwayland
	xdg-desktop-portal-gnome xdg-desktop-portal-gtk xdg-utils gnome-keyring
	libnotify-bin power-profiles-daemon fwupd udisks2
	zsh zsh-autosuggestions zsh-syntax-highlighting tmux ripgrep eza fd-find fzf
	gnupg pinentry-curses gh python3
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

# ── 2. PPAs: ghostty, keyd (niri is built from source — see § 3b below) ─────
add_ppa() {  # add_ppa <ppa> <apt-pkg> [check-cmd]
	local ppa="$1" pkg="$2" check="${3:-$2}"
	have "$check" && { log "$pkg already installed."; return; }
	log "adding $ppa + installing $pkg…"
	sudo add-apt-repository -y "$ppa" || { warn "add-apt-repository $ppa failed"; return; }
	sudo apt-get update -y || true
	sudo apt-get install -y "$pkg" || warn "$pkg install failed"
}
add_ppa ppa:mkasberg/ghostty-ubuntu ghostty
# keyd: the keyd-team PPA installs the binary as `keyd.rvaiya` (the service is
# still `keyd`). setup.sh step 6 detects either name and writes
# /etc/keyd/default.conf, then restarts the keyd service.
add_ppa ppa:keyd-team/ppa keyd keyd.rvaiya

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
# yazi: prefer the prebuilt release binary — the cargo build pins a very recent
# rustc and can fail on the distro toolchain. Falls back to cargo on non-amd64
# or if the download fails.
install_yazi() {
	have yazi && { log "yazi already installed."; return; }
	if [[ "$ARCH_DEB" == amd64 ]]; then
		local d; d="$(mktemp -d)"
		if curl -fsSL https://github.com/sxyazi/yazi/releases/latest/download/yazi-x86_64-unknown-linux-gnu.zip -o "$d/y.zip" \
			&& unzip -oq "$d/y.zip" -d "$d"; then
			mkdir -p "$HOME/.local/bin"
			find "$d" -type f -name yazi -exec install -m755 {} "$HOME/.local/bin/yazi" \;
			find "$d" -type f -name ya   -exec install -m755 {} "$HOME/.local/bin/ya"   \;
			rm -rf "$d"; log "installed yazi (prebuilt release)."; return
		fi
		rm -rf "$d"; warn "yazi prebuilt download failed — falling back to cargo…"
	fi
	cargo_install yazi yazi-fm yazi-cli
}
install_yazi

# Neovim: noble's apt nvim is ancient (0.9). Install the latest stable from the
# official release tarball into ~/.local (no sudo) — ~/.local/bin precedes
# /usr/bin on PATH so it shadows any apt nvim. amd64/arm64 only; else apt.
install_nvim() {
	have nvim && [[ -x "$HOME/.local/opt/nvim/bin/nvim" ]] && { log "nvim (latest) already installed."; return; }
	local arch
	case "$ARCH_DEB" in
		amd64) arch=x86_64 ;;
		arm64) arch=arm64 ;;
		*) warn "nvim: no official tarball for $ARCH_DEB — installing apt neovim"; sudo apt-get install -y neovim; return ;;
	esac
	local d; d="$(mktemp -d)"
	if curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.tar.gz" -o "$d/nvim.tar.gz" \
		&& tar -xzf "$d/nvim.tar.gz" -C "$d"; then
		local ex; ex="$(find "$d" -maxdepth 1 -type d -name 'nvim-linux*' | head -1)"
		mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
		rm -rf "$HOME/.local/opt/nvim"; mv "$ex" "$HOME/.local/opt/nvim"
		ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
		log "installed neovim $("$HOME/.local/opt/nvim/bin/nvim" --version | head -1)"
	else
		warn "nvim tarball install failed — falling back to apt neovim"; sudo apt-get install -y neovim
	fi
	rm -rf "$d"
}
install_nvim

# xwayland-satellite is NOT published on crates.io — a bare `cargo install
# xwayland-satellite` fails with "could not find ... in registry". Install it
# from git instead (needs xcb-cursor at build time → libxcb-cursor-dev, above).
if ! have xwayland-satellite; then
	log "cargo install xwayland-satellite (from git)…"
	cargo install --locked --git https://github.com/Supreeeme/xwayland-satellite.git \
		xwayland-satellite || warn "xwayland-satellite install failed"
fi

# ── 3b. niri (built from source) ────────────────────────────────────────────
# No usable niri apt package exists on noble (24.04) — niri only entered Ubuntu
# in 24.10. (The original spec pulled it from ppa:avengemedia/danklinux, which
# actually ships DankMaterialShell's `dgop`, not niri, so niri never installed.)
# Build the pinned release from source — every C dep is in APT_PKGS above — and
# install the binary + SDDM session + portal config + user units by hand. niri
# then appears as a selectable "Niri" session at the SDDM screen (KDE stays).
build_niri() {
	have niri && { log "niri already installed."; return; }
	have cargo || { warn "cargo missing — cannot build niri"; return; }
	local d; d="$(mktemp -d)"
	log "building niri ${NIRI_TAG} from source (a few minutes)…"
	if git clone --depth 1 --branch "$NIRI_TAG" https://github.com/YaLTeR/niri.git "$d/niri" \
		&& cargo build --release --locked --manifest-path "$d/niri/Cargo.toml"; then
		local n="$d/niri"
		sudo install -Dm755 "$n/target/release/niri"            /usr/local/bin/niri
		sudo install -Dm755 "$n/resources/niri-session"         /usr/local/bin/niri-session
		sudo install -Dm644 "$n/resources/niri.desktop"         /usr/share/wayland-sessions/niri.desktop
		sudo install -Dm644 "$n/resources/niri-portals.conf"    /usr/share/xdg-desktop-portal/niri-portals.conf
		sudo install -Dm644 "$n/resources/niri.service"         /usr/lib/systemd/user/niri.service
		sudo install -Dm644 "$n/resources/niri-shutdown.target" /usr/lib/systemd/user/niri-shutdown.target
		log "niri ${NIRI_TAG} installed (pick 'Niri' at the SDDM login screen)."
	else
		warn "niri build failed — see output above."
	fi
	rm -rf "$d"
}
build_niri

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
# The niri config spawns `zen-browser`, but the per-user tarball installs the
# binary as `zen`. Alias it so the startup spawn resolves the same as on Arch
# (where the package binary is `zen-browser`).
if [[ -x "$HOME/.local/bin/zen" && ! -e "$HOME/.local/bin/zen-browser" ]]; then
	ln -sfn zen "$HOME/.local/bin/zen-browser"
	log "linked zen-browser → zen"
fi
# The Zen tarball writes a launcher with a literal `Exec=$HOME/...` (the desktop
# spec does NOT expand $HOME, so launchers like Noctalia can't run it) and no
# StartupWMClass — so every Zen window spawns a throwaway userapp-Zen-*.desktop,
# and you end up with several dead "Zen Browser" entries. Patch Exec to an
# absolute path + %u, add StartupWMClass=zen, and clear the auto-gen dupes.
ZEN_DESKTOP="$HOME/.local/share/applications/zen.desktop"
if [[ -f "$ZEN_DESKTOP" ]]; then
	sed -i -e 's#^Exec=\$HOME/#Exec='"$HOME"'/#' -e 's#^Exec=\(.*/zen\)$#Exec=\1 %u#' "$ZEN_DESKTOP"
	grep -q '^StartupWMClass=' "$ZEN_DESKTOP" || printf 'StartupWMClass=zen\n' >> "$ZEN_DESKTOP"
	rm -f "$HOME"/.local/share/applications/userapp-Zen-*.desktop
	have update-desktop-database && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
	log "patched zen.desktop (Exec + StartupWMClass)"
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
			&& cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
				-DCMAKE_INSTALL_PREFIX=/usr/local -DDISTRIBUTOR="meetinjp/.dotfiles" \
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
