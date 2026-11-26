# OneDrive

`~/work/ai/OneDrive/` is the deliberate sync boundary: put only files you want
in OneDrive there. It is an ordinary directory outside this repository, never a
Stow package. Manual `onedrive-sync` runs synchronize it in both directions with
the dedicated `LinuxSync` folder in OneDrive. No timer or background sync is
installed or enabled. Keep a separate backup: two-way sync propagates deletions
from either side.

Sync uses [rclone's OneDrive backend](https://rclone.org/onedrive/). The desktop
profile links `onedrive-sync`; it does not install rclone. Install it with
`sudo apt install rclone` or the [official installer](https://rclone.org/install/).

## Authenticate and initialize (once per machine)

Configure an rclone remote:

```sh
rclone config
```

Create a remote named **`onedrive`**, choose storage type **`onedrive`**, sign
in through the browser, and pick the account's OneDrive (business or personal).
Keep credentials in rclone's machine-local configuration (normally
`~/.config/rclone/rclone.conf`); never copy it into this repository or print it.
Confirm access with `rclone lsd onedrive:`. If the token later expires, run
`rclone config reconnect onedrive:`.

Start with a new, empty cloud folder named `LinuxSync`. The following creates
it and places a small `RCLONE_TEST` access marker on each side. Keep both markers
in place: sync checks them to guard against a missing or inaccessible folder.

```sh
mkdir -p ~/work/ai/OneDrive
rclone mkdir onedrive:LinuxSync
touch ~/work/ai/OneDrive/RCLONE_TEST
rclone copyto ~/work/ai/OneDrive/RCLONE_TEST onedrive:LinuxSync/RCLONE_TEST
```

Put your chosen files in `~/work/ai/OneDrive`, then preview the first sync:

```sh
rclone bisync ~/work/ai/OneDrive onedrive:LinuxSync \
  --workdir "${XDG_STATE_HOME:-$HOME/.local/state}/rclone/bisync" \
  --check-access --create-empty-src-dirs --verbose \
  --resync --dry-run
```

Review the output, then initialize using the same command without `--dry-run`.
Initialization merges the two trees and prefers local versions when the same
path differs, which is why a new cloud folder is recommended.

## Normal use and recovery

```sh
onedrive-sync --dry-run  # Preview changes.
onedrive-sync            # Apply changes in both directions.
```

The helper refuses to run without the local folder and access marker. Bisync
state lives in `${XDG_STATE_HOME:-$HOME/.local/state}/rclone/bisync`; preserve
that directory between runs. Synced files downloaded from OneDrive and the
bisync state are private to your user (`umask 077`).

`onedrive-sync` accepts only `--dry-run` and `--help`; it never automatically
reinitializes sync. If rclone requires a resync after an error or lost state,
inspect both sides and keep a backup before repeating the initialization
commands. A resync can overwrite newer cloud files with local versions.
Read the [bisync recovery guidance](https://rclone.org/bisync/#error-handling)
before proceeding. Do not delete the state directory to fix a failed run.
