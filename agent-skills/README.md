# Shared agent tools

Agent setup is optional and separate from configuration linking:

```sh
./agent-skills/setup.sh
```

Install Codex and/or Claude Code separately through their official installers.
This setup initializes the pinned Caveman submodule, links its 22 shared skills
into `~/.agents/skills/` and `~/.claude/skills/`, and links three Claude agent
presets. Both agents use the same upstream source. Personal Claude skills have
an additional Stow package.

The submodule records the same upstream revision previously vendored here:
`d262ab3882952a59312ff3537cd86d894523c5ab`. Upstream code and licensing stay in
that repository; this checkout records one gitlink rather than copied skill files.

Global guidance starts new sessions in ultracave mode. Say `normal mode` or
`stop caveman` to change the current session. Existing personal guidance and
unrelated skills are preserved; conflicts are backed up outside skill discovery.

Codex preferences preserve your model and reasoning selections, authentication,
sessions, trust, and unrelated settings. Existing native Caveman plugin entries
are disabled in favor of the shared skill source, preventing duplicate skill
exports. Plugin caches are left intact. Claude's unrelated plugins stay enabled.
The setup does not install the separate Caveman Cloud gateway or CLI hooks.

To apply only shared skills and guidance, run `python3 agent-skills/apply.py`.
Add `--check` to validate sources and existing user files without changing them.
For an isolated check, pass `--home /tmp/caveman-check`. This standalone skill
installer also supports Windows with Python and symlink privileges; the desktop
installer targets Ubuntu and macOS.

To update Caveman, select and review an upstream revision inside the submodule,
run `python3 -m unittest discover -s tests -p test_agent_skills.py -v`, then commit
the updated gitlink. Keep this revision shared across agents.
