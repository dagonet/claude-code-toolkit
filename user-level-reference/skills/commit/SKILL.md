---
name: commit
description: Stage and commit changes with native git, after showing the user exactly what will be committed. Triggers on /commit.
disable-model-invocation: true
---

# Commit

Execute a proper commit workflow using native git (PR1 removed the MCP-git mandate — the guard hooks gate git rather than ban it).

## Workflow

1. **Check status**
   - `git status --short`
   - If there are no changes, tell the user and stop

2. **Review changes**
   - `git diff --stat` for unstaged changes
   - `git diff --cached --stat` for already-staged changes

3. **Check recent commit style** (optional)
   - `git log --oneline -5`
   - Match the existing commit message style

4. **Stage files**
   - `git add <path> [<path> ...]` with explicit paths — never `.` or `*`

5. **Summarize what will be committed**
   - `git diff --cached --stat` again, and list the files in a short bullet list
   - Explain the purpose of the changes

6. **Template drift check** (requires template-sync-tools MCP)
   - If `.claude/template-manifest.json` exists in the repo root:
     1. Call `template_compute_status(project_path=".")`
     2. If any files have status `PROJECT_CUSTOM` or `CONFLICT`, append after the commit: **"Template drift detected: X file(s) modified locally. Run `/contribute-upstream` to push generalizable changes back, or `/sync-template` to pull latest template updates."**
     3. If any files have status `AUTO_UPDATE`, append after the commit: **"Template updates available for X file(s). Run `/sync-template` to apply."**
   - If no manifest exists or template-sync-tools MCP is unavailable: skip silently

7. **Commit**
   - `git commit -m "<message>"` — clear, concise, following repo conventions

## Verification checklist

Before reporting the commit as done, confirm each of these:

- [ ] `git diff --cached --stat` was shown to the user before committing
- [ ] Only the intended files are staged — nothing swept in by a wildcard
- [ ] `git status --short` after the commit shows a clean tree (or only deliberately-left files)
- [ ] `git log --oneline -1` shows the new commit with the intended message
- [ ] No secrets, `.env` files, or local-only config are in the commit

## Rules

- MUST NOT commit without showing the user what will be committed
- MUST NOT include files the user didn't intend to commit
- If unsure which files to include, ASK the user
- Template drift check is informational only — never block a commit
- All manifest operations use MCP template-sync-tools — do NOT read/modify the manifest manually
