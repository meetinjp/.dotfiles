---
name: conventional-commits
description: Use whenever writing a git commit message, in any repo - format the message per Conventional Commits and avoid internal project codenames/jargon in the subject line
---

# Conventional Commits

Every commit message subject line MUST follow Conventional Commits:

```
<type>(<optional scope>): <description>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. Use `!` after the type/scope (e.g. `feat!:`) or a
`BREAKING CHANGE:` footer for breaking changes.

Rules:
- Subject line: lowercase type, imperative mood, no trailing period, ideally
  under ~72 chars.
- Body (optional, blank line after subject): explain *why*, not *what* - the
  diff already shows what changed.
- Don't use internal project codenames, phase/ring labels, or team-only
  jargon (e.g. "Ring A", sprint names, ticket-only shorthand) in the subject
  line - a stranger reading `git log` with zero project context should
  understand what changed. Codenames are fine in the body if truly needed
  for traceability, never in the headline.
- Footers: `Refs: #123`, `BREAKING CHANGE: ...`, etc. as needed. No
  `Co-Authored-By` trailers for AI agents - see the `no-coauthor` skill.
