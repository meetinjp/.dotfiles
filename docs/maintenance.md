# Maintenance

## Update configuration

Pull repository changes, initialize the submodules you use, preview the selected
profile, then apply it. Submodules stay at the revisions recorded by the parent
repository; `git pull` alone does not update an initialized submodule checkout.
The full check suite requires both submodules, including Caveman when installing
only the core profile. It reports the initialization command if a source is missing.

```sh
git pull --ff-only
git submodule update --init --recursive
./install.sh --dry-run
./install.sh
./scripts/check.sh
```

Use `--profile desktop` when updating the Linux desktop configuration.
To update an upstream submodule deliberately, choose and review a revision,
run the relevant checks, and commit the new gitlink in this repository.

## Conflicts and rollback

Installation refuses to replace unmanaged files. Compare a conflicting target
with the package source and back up your existing configuration before moving
it. Do not delete a target merely because Stow reports a conflict.

Absolute symlinks that resolve to this exact checkout are normalized to relative
links. Other links are preserved. Preview mode does not change either kind.
External directory symlinks in target parents are refused; resolve the layout
explicitly before retrying. Existing Stow directory links are supported.

`./install.sh --delete PACKAGE` removes managed links for that package. Package
installation, Git configuration, generated keys, browser state, and separately
enabled services are not undone. Keep personal backups outside the repository.

## Identity and keys

`./setup.sh git` uses `GIT_NAME` and `GIT_EMAIL`, or existing global identity.
It creates an included config under `${XDG_CONFIG_HOME:-~/.config}/git/` without
replacing unrelated global Git settings. These defaults precede existing settings,
so explicit identities and conditional work identities keep their precedence.
Optional `GIT_WORK_EMAIL` is saved to
an unincluded work file; enable it explicitly where appropriate.

`./setup.sh keys` enables signing only after finding or creating a signing key.
Included signing profiles keep precedence. Conflicting included settings stop
setup before it changes Git configuration; reconcile those settings and rerun.
Register its printed public signing and SSH keys with your Git host. Back up
private keys securely; dotfiles are not a private-key backup.

## Machine-local data

Keep authentication, browser profiles, AI sessions, plugin caches, runtime
installations, and Proton data/state outside Git. The repository manages selected
preferences and source configuration, not an export of your home directory.

Use `~/.zshrc.local` and Ghostty's `config.local` for local overrides. Both are
optional and ignored. Review host-specific desktop settings before sharing them.

CI verifies configuration linking in temporary homes, existing Python tests,
and shell syntax/static checks. It does not validate a full OS installation,
cloud authentication, macOS behavior, or graphical-session upgrades.
