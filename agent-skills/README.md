# Shared agent tools

Agent setup is optional and separate from configuration linking:

```sh
./agent-skills/setup.sh
```

Install Codex and/or Claude Code separately through their official installers.
This setup initializes the pinned Caveman and i-have-adhd submodules, links
their 23 shared skills into `~/.agents/skills/` and `~/.claude/skills/`, and
links three Claude agent presets. Both agents use the same upstream sources.
Personal Claude skills have an additional Stow package.

The Caveman submodule records the same upstream revision previously vendored
here: `d262ab3882952a59312ff3537cd86d894523c5ab`. Upstream code and licensing
stay in that repository; this checkout records one gitlink rather than copied
skill files.

Global guidance starts new sessions with ultracave and i-have-adhd both on.
i-have-adhd decides what a reply contains (next action first, numbered steps,
a progress line, one closing next action); ultracave decides the wording. Both
shape chat replies only, not commits, docs, or subagent reports. Say
`stop caveman` or `stop adhd mode` to turn one off for the current session, or
`normal mode` to turn both off. Existing personal guidance and unrelated skills
are preserved; conflicts are backed up outside skill discovery.

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

The [i-have-adhd](https://github.com/ayghri/i-have-adhd) skill cannot start
itself: the global guidance loads it at session start, and `/i-have-adhd` in
Claude Code or `$i-have-adhd` in Codex turns it back on after an opt-out. Its
upstream plugin and always-on hook are not installed; existing native plugin
entries are disabled, as for Caveman, so the skill is not exported twice.
Skill names must be unique across both sources.

To update Caveman or i-have-adhd, select and review an upstream revision inside
its submodule, then run both agent configuration test files:

```sh
python3 -m unittest tests.test_agent_skills tests.test_codex_config -v
```

Then commit the updated gitlink. Keep each revision shared across agents.
