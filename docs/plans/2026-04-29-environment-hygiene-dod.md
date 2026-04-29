# Plan: Environment Hygiene — Clean Start / Clean Finish

## Context

No general environment-hygiene instruction existed in the templates. The Merge Protocol (AGENT_TEAM.md) covers worktree/branch cleanup for team sprints. The DoD table tracks "Worktree cleaned up." The `Clean up temp files` preference only covered helper scripts. What was missing: a standing instruction to start clean and finish clean, applicable to both solo and team workflows.

## Changes Applied (3 edits, 6 template variants + 1 doc)

### 1. Session Bootstrap step 4 — Add env check

**Files:** `templates/{general,dotnet,dotnet-maui,rust-tauri,java,python}/CLAUDE.md`, line 11

```
4. Present current state (from MEMORY.md) and ask what to work on. Check `git_status` and `git_worktree_list` — surface and resolve any stale branches, leftover worktrees, or uncommitted changes from prior tasks before starting new work
```

### 2. Working Preferences — Replace narrow cleanup with broad "Clean finish"

**Files:** Same as above, line 132

```
- **Clean finish** — after completing work: all changes committed, PR merged, worktree removed, branch deleted. Delete temp helpers/scripts, keep only final code. Any leftover artifact that can't be cleaned up must be reported to the user with a reason
```

### 3. Working Preferences — Update docs with code

**Files:** Same as above, line 133

```
- **Update docs with code** — when changing behavior, APIs, config, or setup, update affected docs (README, CLAUDE.md, PROJECT_CONTEXT.md) in the same commit
```

### 4. docs/architecture.md — Sync step 4

Updated the documented Session Bootstrap step 4 to match the new text.

## What was deliberately NOT changed

- **AGENT_TEAM.md DoD table** — already has "Worktree cleaned up" at T2+. The Merge Protocol already defines the cleanup procedure.
- **AGENT_TEAM.md Merge Protocol** — already covers worktree removal + branch deletion.
- **User-level CLAUDE.md** — template CLAUDE.md covers template-bootstrapped projects.
- **Sprint command** — separate concern from template hygiene.

## Commit

`e31f9bc` on main, 7 files changed, 19 insertions, 13 deletions.
