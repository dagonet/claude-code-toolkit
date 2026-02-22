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

6. **Template manifest nudge**
   - If `.claude/template-manifest.json` exists in the repo root:
     1. Read the manifest
     2. Check if any staged files appear in `manifest.files`
     3. For each match where `locallyModified` is currently `false`:
        - Update manifest: set `locallyModified: true`
        - Set `reason` to a brief summary of the change (from the diff or commit message)
     4. If any template-sourced files were detected:
        - Stage the updated manifest alongside the other files
        - After the commit, append: **"Template-sourced files modified: [list]. Run `/contribute-upstream` when ready."**
   - If no manifest exists: skip this step silently

7. **Commit**
   - Call `git_commit(repo_path, message)`
   - Write a clear, concise commit message following repo conventions

## Rules

- MUST use MCP git tools, NOT Bash git commands
- MUST NOT commit without showing the user what will be committed
- MUST NOT include files the user didn't intend to commit
- If unsure which files to include, ASK the user
- Template manifest nudge is informational only — never block a commit
