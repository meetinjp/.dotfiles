#!/usr/bin/env bash
# Ubuntu desktop and development tools. Run explicitly after reviewing the
# package list; config linking does not need this script. Hardware drivers,
# the display manager, and power-management policy stay with the installed OS.
# Optional tools log warnings and continue; desktop prerequisites fail before
# package or system changes. Use --check for a read-only compatibility check.
set -uo pipefail

GO_VER="${GO_VER:-1.26.2}"                 # https://go.dev/dl/
NVM_TAG="${NVM_TAG:-v0.40.5}"              # https://github.com/nvm-sh/nvm/tags
NIRI_TAG="${NIRI_TAG:-v26.04}"             # https://github.com/YaLTeR/niri/tags
# Keep the Qt/QML shell compatible with this repo's Noctalia plugin and IPC.
# The newer native Noctalia releases use a different configuration contract.
NOCTALIA_QS_TAG="${NOCTALIA_QS_TAG:-v0.0.12}"
NOCTALIA_SHELL_TAG="${NOCTALIA_SHELL_TAG:-v4.7.7}"

log()  { printf '  \033[1m%s\033[0m\n' "$*"; }
warn() { printf '  \033[33m! %s\033[0m\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

is_ubuntu() {
	[[ "$(uname -s)" == Linux && -r /etc/os-release ]] || return 1
	local ID='' ID_LIKE=''
	# shellcheck disable=SC1091
	. /etc/os-release
	[[ "$ID" == ubuntu || " $ID_LIKE " == *" ubuntu "* ]]
}

noctalia_engine_ready() {
	have qs && [[ "$(qs --version 2>/dev/null)" == noctalia-qs[[:space:]]* ]]
}

check_noctalia_requirements() {
	if have qs; then
		if noctalia_engine_ready; then
			log "Noctalia engine: $(qs --version)"
			return 0
		fi
		warn "The existing qs is not noctalia-qs. Select the compatible engine on PATH; no binary was replaced."
		return 1
	fi
	local qtver='' candidate=''
	if have qmake6; then
		qtver="$(qmake6 --version 2>/dev/null | sed -n 's/.*Qt version \([0-9][0-9.]*\).*/\1/p' | head -1)"
	elif have pkg-config; then
		qtver="$(pkg-config --modversion Qt6Core 2>/dev/null || true)"
	fi
	if { [[ ! "$qtver" =~ ^[0-9]+\.[0-9]+ ]] || ! dpkg --compare-versions "$qtver" ge 6.6; } && have apt-cache; then
		candidate="$(LC_ALL=C apt-cache policy qt6-base-dev 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
		candidate="${candidate#*:}"
		if [[ -z "$qtver" ]] || { [[ "$candidate" =~ ^[0-9]+\.[0-9]+ ]] && dpkg --compare-versions "$candidate" ge 6.6; }; then
			qtver="$candidate"
		fi
	fi
	if [[ ! "$qtver" =~ ^[0-9]+\.[0-9]+ ]] || ! dpkg --compare-versions "$qtver" ge 6.6; then
		warn "Noctalia's Qt/QML engine requires Qt >= 6.6; found ${qtver:-no installed or available Qt}."
		warn "Stock Ubuntu 24.04 Qt is too old. Provide compatible Qt packages or an existing noctalia-qs before provisioning."
		return 1
	fi
	log "Noctalia build dependency: Qt $qtver (minimum 6.6)."
}

install_noctalia_shell() {
	local root="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
	local target="$root/noctalia-shell" stage backup=''
	if [[ -s "$target/shell.qml" ]]; then
		log "Noctalia shell already installed."
		return 0
	fi
	mkdir -p "$root" || return 1
	stage="$(mktemp -d "$root/.noctalia-shell.XXXXXXXX")" || return 1
	mkdir "$stage/shell" || { rm -rf "$stage"; return 1; }
	if ! curl --fail --show-error --location \
		"https://github.com/noctalia-dev/noctalia/archive/refs/tags/${NOCTALIA_SHELL_TAG}.tar.gz" \
		-o "$stage/source.tar.gz" \
		|| ! tar -xzf "$stage/source.tar.gz" --strip-components=1 -C "$stage/shell" \
		|| [[ ! -s "$stage/shell/shell.qml" ]]; then
		warn "Noctalia shell download is incomplete or incompatible; existing files were preserved. Rerun to retry."
		rm -rf "$stage"
		return 1
	fi
	# An incomplete earlier installation may contain user files; preserve it.
	if [[ -e "$target" || -L "$target" ]]; then
		backup="$target.incomplete.$(date +%s).$$"
		mv "$target" "$backup" || { rm -rf "$stage"; return 1; }
	fi
	if ! mv "$stage/shell" "$target"; then
		[[ -z "$backup" ]] || mv "$backup" "$target"
		rm -rf "$stage"
		return 1
	fi
	rm -rf "$stage"
	log "Installed Noctalia shell $NOCTALIA_SHELL_TAG."
	[[ -z "$backup" ]] || log "Preserved incomplete installation at $backup."
}

install_noctalia() {
	check_noctalia_requirements || return 1
	if ! noctalia_engine_ready; then
		# Ubuntu may mount /tmp in RAM; keep large builds on disk by default.
		local -x TMPDIR="${TMPDIR:-/var/tmp}"
		local stage
		stage="$(mktemp -d)" || return 1
		log "Building noctalia-qs $NOCTALIA_QS_TAG."
		if ! git clone --depth 1 --branch "$NOCTALIA_QS_TAG" \
			https://github.com/noctalia-dev/noctalia-qs "$stage/noctalia-qs" \
			|| ! ( cd "$stage/noctalia-qs" \
				&& cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
					-DCMAKE_INSTALL_PREFIX=/usr/local -DDISTRIBUTOR=dotfiles \
				&& cmake --build build \
				&& sudo cmake --install build ); then
			warn "noctalia-qs build failed."
			rm -rf "$stage"
			return 1
		fi
		rm -rf "$stage"
		noctalia_engine_ready || { warn "Installed noctalia-qs is not available on PATH."; return 1; }
	fi
	install_noctalia_shell
}

install_keyd() {
	if have keyd || have keyd.rvaiya; then
		log "keyd already installed."
		return 0
	fi
	log "installing keyd from Ubuntu packages…"
	sudo apt-get install -y keyd
}

install_starship() {
	have starship && { log "starship already installed."; return 0; }
	log "installing starship…"
	mkdir -p "$HOME/.local/bin" || return 1
	curl -fsS https://starship.rs/install.sh | sh -s -- -y -b "$HOME/.local/bin"
}

# Sourcing exposes the compatibility and installer functions without provisioning.
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
	return 0
fi
case "${1:-}" in
	--help|-h)
		echo 'Usage: ubuntu/provision.sh [--check]'
		echo 'Install Ubuntu desktop/development tools, or only check compatibility.'
		exit 0 ;;
	''|--check) ;;
	*) echo "Unknown argument: $1" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Expected at most one argument.' >&2; exit 2; }
if ! is_ubuntu || ! have apt-get; then
	echo 'Ubuntu or an Ubuntu-derived distribution is required.' >&2
	exit 1
fi
check_noctalia_requirements || exit 1
[[ "${1:-}" != --check ]] || exit 0
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
	libnotify-bin fwupd udisks2
	zsh zsh-autosuggestions zsh-syntax-highlighting tmux ripgrep eza fd-find fzf
	gnupg pinentry-curses gh python3 python3-venv python3-pip
	fonts-firacode fonts-noto-core fonts-noto-color-emoji fonts-noto-cjk locales
	software-properties-common
	# pyenv build deps (compiling a Python from source needs these headers —
	# see https://github.com/pyenv/pyenv/wiki#suggested-build-environment).
	libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev
	libncurses-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
)
log "apt: updating + installing base/desktop/CLI packages…"
sudo apt-get update -y || warn "apt update failed"
sudo apt-get install -y "${APT_PKGS[@]}" || warn "some apt packages failed (continuing)"

# fd ships as `fdfind` on Ubuntu — add a `fd` shim on PATH (nvim/yazi expect fd).
if have fdfind && ! have fd; then
	mkdir -p "$HOME/.local/bin"
	ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
	log "linked fd → fdfind"
fi

# ── 2. Ghostty PPA and Ubuntu keyd package (niri is built in § 3b) ────────
add_ppa() {  # add_ppa <ppa> <apt-pkg> [check-cmd]
	local ppa="$1" pkg="$2" check="${3:-$2}"
	have "$check" && { log "$pkg already installed."; return; }
	log "adding $ppa + installing $pkg…"
	sudo add-apt-repository -y "$ppa" || { warn "add-apt-repository $ppa failed"; return; }
	sudo apt-get update -y || true
	sudo apt-get install -y "$pkg" || warn "$pkg install failed"
}
add_ppa ppa:mkasberg/ghostty-ubuntu ghostty
# Ubuntu's keyd package may name the binary `keyd.rvaiya` (service: `keyd`).
# setup.sh step 6 detects either name, writes /etc/keyd/default.conf, and
# restarts the service. No extra repository is needed for this package.
install_keyd || warn "keyd install failed; check Ubuntu package availability"

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
	# Candidate asset names: handles the historical nvim-linux64 → nvim-linux-x86_64
	# rename so this keeps resolving whichever name upstream publishes.
	local assets=()
	case "$ARCH_DEB" in
		amd64) assets=(nvim-linux-x86_64.tar.gz nvim-linux64.tar.gz) ;;
		arm64) assets=(nvim-linux-arm64.tar.gz) ;;
		*) warn "nvim: no official tarball for $ARCH_DEB — installing apt neovim"; sudo apt-get install -y neovim; return ;;
	esac
	local d ok="" a; d="$(mktemp -d)"
	for a in "${assets[@]}"; do
		if curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/$a" -o "$d/nvim.tar.gz" 2>/dev/null \
			&& tar -xzf "$d/nvim.tar.gz" -C "$d" 2>/dev/null; then ok=1; break; fi
	done
	if [[ -n "$ok" ]]; then
		local ex; ex="$(find "$d" -maxdepth 1 -type d -name 'nvim-linux*' | head -1)"
		mkdir -p "$HOME/.local/opt" "$HOME/.local/bin"
		rm -rf "$HOME/.local/opt/nvim"; mv "$ex" "$HOME/.local/opt/nvim"
		ln -sfn "$HOME/.local/opt/nvim/bin/nvim" "$HOME/.local/bin/nvim"
		# The prebuilt binary needs a fairly modern glibc; on an older base it
		# extracts fine but won't exec. Verify it actually RUNS — if not, drop the
		# tarball and fall back to apt so we never leave a broken nvim behind.
		if "$HOME/.local/opt/nvim/bin/nvim" --version >/dev/null 2>&1; then
			log "installed neovim $("$HOME/.local/opt/nvim/bin/nvim" --version | head -1)"
		else
			warn "prebuilt nvim won't run here (glibc too old?) — reverting to apt neovim"
			rm -rf "$HOME/.local/opt/nvim" "$HOME/.local/bin/nvim"; sudo apt-get install -y neovim
		fi
	else
		warn "nvim tarball download failed — falling back to apt neovim"; sudo apt-get install -y neovim
	fi
	rm -rf "$d"
}
install_nvim

# tree-sitter CLI — nvim-treesitter's `main` branch shells out to `tree-sitter`
# to compile parsers; without it nvim throws `ENOENT (cmd): 'tree-sitter'`. Not
# usefully packaged in apt — install the prebuilt single binary from upstream.
install_treesitter() {
	have tree-sitter && { log "tree-sitter CLI already installed."; return; }
	local ts
	case "$ARCH_DEB" in
		amd64) ts=tree-sitter-linux-x64.gz ;;
		arm64) ts=tree-sitter-linux-arm64.gz ;;
		*) warn "tree-sitter: no prebuilt for $ARCH_DEB — trying cargo"; have cargo && cargo install --locked tree-sitter-cli; return ;;
	esac
	local d; d="$(mktemp -d)"
	if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/latest/download/${ts}" -o "$d/ts.gz" \
		&& gunzip -c "$d/ts.gz" > "$d/tree-sitter" && chmod +x "$d/tree-sitter" \
		&& "$d/tree-sitter" --version >/dev/null 2>&1; then
		mkdir -p "$HOME/.local/bin"; mv "$d/tree-sitter" "$HOME/.local/bin/tree-sitter"
		log "installed tree-sitter CLI $("$HOME/.local/bin/tree-sitter" --version)"
	else
		warn "tree-sitter prebuilt failed — trying cargo"
		have cargo && cargo install --locked tree-sitter-cli || warn "tree-sitter CLI not installed"
	fi
	rm -rf "$d"
}
install_treesitter

# xwayland-satellite is NOT published on crates.io — a bare `cargo install
# xwayland-satellite` fails with "could not find ... in registry". Install it
# from git instead (needs xcb-cursor at build time → libxcb-cursor-dev, above).
if ! have xwayland-satellite; then
	log "cargo install xwayland-satellite (from git)…"
	cargo install --locked --git https://github.com/Supreeeme/xwayland-satellite.git \
		xwayland-satellite || warn "xwayland-satellite install failed"
fi

# ── 3b. niri (built from source) ────────────────────────────────────────────
# Build the pinned niri release for a consistent session and portal setup.
# Build the pinned release from source — every C dep is in APT_PKGS above — and
# install the binary + SDDM session + portal config + user units by hand. niri
# then appears as a selectable "Niri" session in the existing display manager.
build_niri() {
	have niri && { log "niri already installed."; return; }
	have cargo || { warn "cargo missing — cannot build niri"; return; }
	local -x TMPDIR="${TMPDIR:-/var/tmp}"
	local d; d="$(mktemp -d)" || return 1
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
		log "niri ${NIRI_TAG} installed (pick 'Niri' in your display manager)."
	else
		warn "niri build failed — see output above."
	fi
	rm -rf "$d"
}
build_niri

# ── 4. starship prompt ──────────────────────────────────────────────────────
install_starship || warn "starship install failed"

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

# ── 8. Zen browser (per-user installation) ─────────────────────────────────
if [[ ! -x "$HOME/.local/bin/zen" ]]; then
	log "installing Zen browser (per-user)…"
	curl -fsSL https://github.com/zen-browser/updates-server/raw/refs/heads/main/install.sh | bash \
		|| warn "Zen install failed"
fi
# The niri config spawns `zen-browser`, but the per-user tarball installs the
# binary as `zen`. Provide the command name used by the desktop config.
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
	# Register Zen as an http/https handler (the tarball's .desktop omits MimeType,
	# so it never counts as a browser for xdg).
	grep -q '^MimeType=' "$ZEN_DESKTOP" || printf 'MimeType=text/html;text/xml;application/xhtml+xml;x-scheme-handler/http;x-scheme-handler/https;\n' >> "$ZEN_DESKTOP"
	rm -f "$HOME"/.local/share/applications/userapp-Zen-*.desktop
	have update-desktop-database && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
	# Make Zen the actual default browser. xdg-settings sets the desktop default,
	# but the per-scheme handlers (http/https/text-html) are independent and on
	# existing desktops may retain a different browser unless set explicitly.
	have xdg-settings && xdg-settings set default-web-browser zen.desktop 2>/dev/null || true
	have xdg-mime && xdg-mime default zen.desktop x-scheme-handler/http x-scheme-handler/https text/html 2>/dev/null || true
	log "patched zen.desktop + set Zen as default browser"
fi

# ── 8b. Brave browser (official apt repo, release channel) ──────────────────
# Work browser, installed alongside Zen (Zen stays the default). Keyring and
# deb822 .sources are fetched verbatim from Brave's own install docs.
if ! have brave-browser; then
	log "installing brave-browser (official repo)…"
	if sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
			https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
		&& sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-release.sources \
			https://brave-browser-apt-release.s3.brave.com/brave-browser.sources; then
		sudo apt-get update -y || true
		sudo apt-get install -y brave-browser || warn "brave-browser install failed"
	else
		warn "Brave keyring/sources fetch failed"
	fi
fi

# ── 9. uv / pyenv / nvm / bun (per-user runtime managers; cross-distro) ─────
have uv  || { log "installing uv…";  curl -LsSf https://astral.sh/uv/install.sh | sh || warn "uv failed"; }
[[ -d "$HOME/.pyenv/bin" ]] || { log "installing pyenv…"; curl -fsSL https://pyenv.run | bash || warn "pyenv failed"; }
[[ -s "$HOME/.nvm/nvm.sh" ]] || { log "installing nvm ${NVM_TAG}…"; curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_TAG}/install.sh" | bash || warn "nvm failed"; }
[[ -x "$HOME/.bun/bin/bun" ]] || { log "installing bun…"; curl -fsSL https://bun.com/install | bash || warn "bun failed"; }

# ── 10. Noctalia (engine and shell installed independently) ────────────────
install_noctalia || exit 1

echo "Ubuntu provisioning done (review any '!' warnings above)."
