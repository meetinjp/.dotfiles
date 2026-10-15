# Shared agent skills

`python3 agent-skills/apply.py` installs the same 22 upstream Caveman skills for
Codex (`~/.agents/skills/`) and Claude Code (`~/.claude/skills/`). Both locations
contain symlinks to this checkout, so dotfiles updates reach both agents. The
three Cavecrew presets also link into `~/.claude/agents/`. Existing plugins stay
installed; these unprefixed skills complete the smaller Codex plugin bundle.

The installer runs from `install.sh` on Linux, macOS, and Windows. Windows needs
Python 3 and permission to create symlinks, such as Developer Mode. For an
isolated installation check, use `--home /tmp/caveman-check`.

Global `AGENTS.md` and `CLAUDE.md` guidance starts each new session in
`ultracave` mode and points to [CAVEMAN.md](CAVEMAN.md). The installer preserves
existing guidance outside its marked block. It merges `defaultMode: "ultra"`
into the Caveman config because both old and current plugin hooks understand
that alias. It respects `CODEX_HOME`, `CLAUDE_CONFIG_DIR`, `XDG_CONFIG_HOME`, and
Windows' `APPDATA`; `--home` ignores these overrides for isolation. Explicit
session mode changes, including `stop caveman` and `normal mode`, still win.

Conflicting skill or agent entries move to timestamped `.bak.*` paths under
`~/.agents/backups/caveman/` before replacement. Backups stay outside skill
discovery directories. Unrelated skills and configuration keys remain intact.
Repeated runs do not rewrite unchanged files or create more backups.

Skills become available on the next Codex turn; start a new session to verify
startup defaults. In Codex, invoke `$caveman-review`, `$caveman-commit`,
`$caveman-help`, `$caveman`, `$ultracave`, or `$megacave`. In Claude Code, use
the same names with `/`. The other upstream skills are available when their
task applies. Skills that call the separate Caveman CLI, gateway, or provider
still need their documented runtime and authentication. Installing the skill
files does not install or configure those services.

## Upstream source and updates

The vendored files come from
[JuliusBrussee/caveman at d262ab3882952a59312ff3537cd86d894523c5ab](https://github.com/JuliusBrussee/caveman/tree/d262ab3882952a59312ff3537cd86d894523c5ab).
They include every top-level `skills/*/SKILL.md` directory and its supporting
files, the three Cavecrew presets, and the upstream license and notice files.
[caveman/upstream.json](caveman/upstream.json) records the revision and each
original file's SHA-256 checksum. Keep vendored files unchanged.

To update, install all top-level upstream skill directories at a chosen commit
into a temporary directory with Codex's Skill Installer. Review the diff,
replace the vendored files, refresh the presets and license files from that
same commit, and regenerate `upstream.json`. Then run:

```sh
python3 -m unittest discover -s tests -p 'test_agent_skills.py' -v
python3 agent-skills/apply.py
```

The shared directories follow the documented global skill locations for
[Codex](https://learn.chatgpt.com/docs/build-skills#where-codex-loads-local-skills)
and [Claude Code](https://code.claude.com/docs/en/skills#choose-where-skills-load).
