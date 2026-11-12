# Ubuntu desktop setup

This is an explicit workstation bootstrap, separate from configuration linking.
It installs desktop and development tools using apt, third-party repositories,
source builds, and upstream installers. Review `provision.sh` before running it.

## Compatibility

Run the read-only preflight first:

```sh
./ubuntu/provision.sh --check
```

The Linux target is Ubuntu and Ubuntu-derived distributions identified by
`/etc/os-release`. Ubuntu 26.04.1 was exercised in a cloud-image VM, including
config linking, repeat installs, and niri/Noctalia/Ghostty/Zen in a nested desktop.
Physical hardware and display-manager login were not tested.

The configured desktop uses the Qt/QML Noctalia shell. Its compatible pins are
`noctalia-qs v0.0.12`, Noctalia `v4.7.7`, and niri `v26.04`. The engine needs
Qt >= 6.6. Stock Ubuntu 24.04 packages provide older Qt, so preflight refuses
that combination before changing system packages. Supply compatible Qt packages
or an existing compatible engine; the script does not add a Qt replacement PPA.
New native Noctalia releases use a different configuration and plugin contract.
Do not replace the pinned shell with an unrelated latest release.

## Install

```sh
./ubuntu/provision.sh
./install.sh --profile desktop --dry-run
./install.sh --profile desktop
./noctalia/apply.sh
```

Provisioning keeps existing commands where possible. It installs apt packages,
the Ghostty repository, Ubuntu's keyd package, Rust tools, niri, a compatible
Noctalia engine and shell, browsers, and development runtimes. Starship installs
into `~/.local/bin` without sudo. Some optional tool failures produce
warnings; review those warnings before treating the workstation as complete.
Version pins are at the top of `provision.sh`.

Large niri and Noctalia engine builds use `/var/tmp` instead of memory-backed
`/tmp`, unless you set `TMPDIR`. Allow several GB of disk space. Validation used
8 GiB RAM and four virtual CPUs, with `CARGO_BUILD_JOBS=2` and
`CMAKE_BUILD_PARALLEL_LEVEL=3` to limit build parallelism.

Select the Niri session in your existing display manager. Provisioning leaves
hardware drivers, firmware, display-manager choice, and CPU/fan/battery policy
with the installed operating system. It does not enable autologin. Keep your
existing desktop session as a fallback.

## Personalize

`niri/.config/niri/host.kdl` holds keyboard, pointing-device, and sunset-location
preferences. `kanshi/.config/kanshi/config` alone owns display modes, refresh
rates, positions, and scaling. Review both before using another machine.

After editing display profiles, run `pkill -HUP -u "$(id -u)" -x kanshi`. Niri live-reloads its
own configuration; validate it first with `niri validate`.

Zen preferences are linked into an existing default profile discovered from
its INI metadata. Launch Zen once if no profile exists. An unmanaged `user.js`
is preserved; review and move it yourself before applying the managed file.

`./setup.sh system` optionally configures locale, Caps Lock, zsh, memory-pressure
handling, and sudo feedback. It is never run by config installation. Noninteractive
prompts skip changes unless `DOTFILES_YES=1` is explicitly supplied.
