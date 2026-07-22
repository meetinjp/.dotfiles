---
name: no-coauthor
description: Use whenever creating or amending a git commit - governs commit trailer/attribution content, not just this session's attribution setting
---

# No Co-Author Trailers

Git commit policy: do NOT add a `Co-Authored-By:` trailer crediting yourself
(or any AI agent) on commits you create in this repo. The `Co-Authored-By`
footer should list only the human author(s) who directed the work -
typically just the committer, so omit the trailer entirely unless the user
explicitly names a human co-author.

This applies to new commits, amends, squashes, cherry-picks, and rebased
commits, and holds regardless of the `attribution.commit` setting in any
particular `settings.json` - don't rely solely on that config being present.
