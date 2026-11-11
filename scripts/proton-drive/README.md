# Proton Drive

`~/ProtonDrive/` is the deliberate sync boundary: put only files you want in
the cloud there. It is an ordinary directory outside this repository, never a
Stow package. Manual `proton-sync` runs synchronize it in both directions with
the dedicated `LinuxSync` folder in Proton Drive. No timer or background sync
is installed or enabled.

The [official Proton Drive CLI](https://proton.me/support/drive-cli) provides
uploads, downloads, and sharing. Folder sync uses
[rclone's Proton Drive backend](https://rclone.org/protondrive/), which is
unofficial and remains in beta. The two tools authenticate separately; logging
into the official CLI does not configure rclone. Keep a separate backup:
two-way sync propagates deletions from either side.

## Install the tools

Run this optional setup:

```sh
~/.dotfiles/scripts/proton-drive/setup.sh
```

It installs missing rclone and Proton Drive CLI binaries into `~/.local/bin`
from pinned official releases, verifies their published checksums, links
`proton-sync`, and creates `~/ProtonDrive`. Existing commands are left alone.
It does not log in, create cloud folders, or transfer files. On Linux, the
official CLI also needs `libsecret-1-0` and a running secret service, such as
GNOME Keyring; the desktop provisioning already installs `gnome-keyring`.

The desktop profile also links `proton-sync`; it does not install these tools. Version pins live in
`scripts/proton-drive/setup.sh`. When upgrading, update each version and its
matching checksums together. The installer leaves existing binaries unchanged;
manage upgrades explicitly using the upstream download instructions.

## Authenticate and initialize (once per machine)

For the official CLI, sign in through your browser when ready:

```sh
proton-drive auth login
```

For sync, configure a separate rclone remote:

```sh
rclone config
```

Create a remote named **`proton`**, choose storage type **`protondrive`**, and
complete its authentication prompts. Keep credentials in rclone's machine-local
configuration (normally `~/.config/rclone/rclone.conf`); never copy it into this
repository. Confirm access with `rclone lsd proton:`.

Start with a new, empty cloud folder named `LinuxSync`. The following creates
it and places a small `RCLONE_TEST` access marker on each side. Keep both markers
in place: sync checks them to guard against a missing or inaccessible folder.

```sh
mkdir -p ~/ProtonDrive
rclone mkdir proton:LinuxSync
touch ~/ProtonDrive/RCLONE_TEST
rclone copyto ~/ProtonDrive/RCLONE_TEST proton:LinuxSync/RCLONE_TEST
```

Put your chosen files in `~/ProtonDrive`, then preview the first sync:

```sh
rclone bisync ~/ProtonDrive proton:LinuxSync \
  --workdir "${XDG_STATE_HOME:-$HOME/.local/state}/rclone/bisync" \
  --check-access --protondrive-enable-caching=false --verbose \
  --resync --dry-run
```

Review the output, then initialize using the same command without `--dry-run`:

```sh
rclone bisync ~/ProtonDrive proton:LinuxSync \
  --workdir "${XDG_STATE_HOME:-$HOME/.local/state}/rclone/bisync" \
  --check-access --protondrive-enable-caching=false --verbose \
  --resync
```

Initialization merges the two trees and prefers local versions when the same
path differs, which is why a new cloud folder is recommended. Reusing an
existing cloud folder requires reviewing those conflicts first.

## Normal use and recovery

```sh
proton-sync --dry-run  # Preview changes.
proton-sync            # Apply changes in both directions.
```

The helper refuses to run without the local folder and access marker. It
disables Proton metadata caching so changes made through another client are
visible during the run. Bisync state stays outside the disposable cache in
`${XDG_STATE_HOME:-$HOME/.local/state}/rclone/bisync`; preserve that directory
between runs. Credentials, sync state, and synced data stay outside Git.

`proton-sync` accepts only `--dry-run` and `--help`; it never automatically
reinitializes sync. If rclone requires a resync after an error or lost state,
inspect both sides and keep a backup before repeating the initialization
commands. A resync can overwrite newer cloud files with local versions.
Read the [bisync recovery guidance](https://rclone.org/bisync/#error-handling)
before proceeding. Do not delete the state directory to fix a failed run.

## Cloud-only archive

Keep a sibling cloud folder called `Archive` for files that should not exist
locally. `proton-sync` touches only `LinuxSync`.

To archive a synced item, run `proton-sync` first, move the cloud item from
`LinuxSync` to `Archive` in Proton's web app, and verify the archived copy.
Preview the next sync before applying it: the move should remove the local copy.
Keep `RCLONE_TEST` in `LinuxSync`. Large removals can hit rclone's deletion
limit; inspect the proposed changes instead of blindly using `--resync`.

To upload an independent folder, preview `rclone copy /path/to/folder proton:Archive --dry-run`,
then repeat without `--dry-run`. This copies the folder's contents and does not
establish ongoing synchronization.
