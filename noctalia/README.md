# Noctalia settings

The Ubuntu provisioner pins the compatible Qt/QML engine and shell.
`./noctalia/apply.sh` applies Gruvbox Material Hard, disables animations, and
sets idle actions to screen-off at 20 minutes, lock at 25, and suspend at 60.
These times count from the last input; locking before suspend is enabled.
Unrelated live settings remain application-owned.

## Optional Codex sleep protection

```sh
./noctalia/setup-work-keep-awake.sh
```

The service observes live Codex turn metadata and holds a sleep inhibitor only
during active work. A local QML plugin pauses Noctalia's suspend monitor without
changing screen-off or locking. It does not cover other AI clients.

Inspect with `work-keep-awake --status`. Disable with:

```sh
systemctl --user disable --now work-keep-awake.service
```

Reload Noctalia once after first plugin installation. The observer uses Codex
rollout events and the plugin uses Noctalia internals; rerun checks and verify
behavior after either application changes. Ordinary manual suspend is also
blocked while the sleep inhibitor is held.

Power management remains owned by the installed OS. An installed package alone
does not establish which power-profile service should be enabled.
