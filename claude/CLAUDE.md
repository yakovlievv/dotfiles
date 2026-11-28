## My vault
My whole life lives in an org-roam vault (projects, businesses, systems, knowledge, tutoring, journal). Every Claude I use reaches it through the `vault` connector: vault_search, vault_read, vault_guide, vault_create_note, vault_append.
- If a conversation touches my projects, businesses, plans, health, learning or ideas, check the vault before answering or asking me to explain. The tool descriptions say how; follow them.
- When something worth keeping comes up, offer to save it to the vault. Only write after I say yes, and call vault_guide before your first write in a conversation.
- Use the vault tools even when ~/org is on the same disk (Claude Code). Don't grep or edit the files directly, so you behave the same on every device.
- If it is a big rewrite of something you shall interact with vault directly through disk, not through MCP as it gives you only limited access and that's not ideal for bigger tasks
## How I want work done (every project)
- One git worktree per task, from a fresh origin/main, so you don't clash with background agents.
- Routine changes: once checks pass, merge into main and push yourself. No PR unless the change is risky or I ask.
  If you do open one, watch it until CI is green with no conflicts; fix and push if not.
- Every task gets a ticket in the project's vault note (format: vault note "Project management").
  STRT when you start, PROPEN when a PR is open, DONE when it's merged or finished. No note for the project → propose one.
- Every change updates the docs (README, CLAUDE.md, docs/, the project's vault note) so they mirror the project as it is now.

## This machine
@~/.claude/machine.md
