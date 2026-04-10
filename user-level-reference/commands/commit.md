# /commit - Stage and Commit Changes

Execute a proper git commit workflow using MCP git tools.

## Workflow

1. **Check status**
   - Call `git_status(repo_path, include_untracked=true)`
   - If no changes, inform user and stop

2. **Review changes**
   - Call `git_diff_summary(repo_path, staged=false)` for unstaged changes
   - Call `git_diff_summary(repo_path, staged=true)` for already staged changes

3. **Check recent commit style** (optional)
   - Call `git_log(repo_path, limit=5, oneline=true)`
   - Match the existing commit message style

4. **Stage files**
   - Call `git_add(repo_path, paths)` for files to include
   - Use explicit file paths, not `.` or `*`

5. **Summarize what will be committed**
   - List files being committed in a short bullet list
   - Explain the purpose of the changes

6. **Template drift check** (requires template-sync-tools MCP)
   - If `.claude/template-manifest.json` exists in the repo root:
     1. Call `template_compute_status(project_path=".")`
     2. If any files have status `PROJECT_CUSTOM` or `CONFLICT`:
        - After the commit, append: **"Template drift detected: X file(s) modified locally. Run `/contribute-upstream` to push generalizable changes back, or `/sync-template` to pull latest template updates."**
     3. If any files have status `AUTO_UPDATE`:
        - After the commit, append: **"Template updates available for X file(s). Run `/sync-template` to apply."**
   - If no manifest exists or template-sync-tools MCP is unavailable: skip silently

7. **Commit**
   - Call `git_commit(repo_path, message)`
   - Write a clear, concise commit message following repo conventions

## Rules

- MUST use MCP git tools, NOT Bash git commands
- MUST NOT commit without showing the user what will be committed
- MUST NOT include files the user didn't intend to commit
- If unsure which files to include, ASK the user
- Template drift check is informational only — never block a commit
- All manifest operations use MCP template-sync-tools — do NOT read/modify the manifest manually
