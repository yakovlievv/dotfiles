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
- **TICKETS ARE MANDATORY FOR REAL WORK. Use the `task` CLI.** A feature, a fix or anything that changes a
  project and is more than a quick one-off needs a ticket BEFORE you edit. Questions and tiny one-offs don't;
  you decide, and when in doubt, create one.
  - New work: make the worktree, then inside it `task new "short title" --body "the full task as I described it"`
    (`--note NAME` if the repo name isn't the note's title; `--under HEADING` for the current version heading).
    Run `task list` first: if the ticket already exists, join it instead.
  - I gave a ticket ID, or you're helping on an existing ticket: `task join ID` inside your worktree.
  - A watcher sets PROPEN and DONE from the branch's PR or merge. Don't set those by hand.
  - No branch (vault, server, config work) or a squash merge without a PR: run `task done` when it's finished.
  - Never create or change ticket states any other way. Running `task` needs no extra permission from me.
    No vault note for the project → propose one. `task` missing on this machine → say so.
- Every change updates the docs (README, CLAUDE.md, docs/, the project's vault note) so they mirror the project as it is now.

## This machine
@~/.claude/machine.md
