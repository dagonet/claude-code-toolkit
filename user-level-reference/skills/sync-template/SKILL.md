---
name: sync-template
description: Pull template updates into the current project. Triggers on /sync-template. Reads .claude/template-manifest.json, compares against template repo, auto-updates unmodified files, flags conflicts for modified files.
---

# Sync Template (Downstream)

Pull updates from the claude-code-toolkit template repo into the current project.

## Prerequisites

- `.claude/template-manifest.json` must exist in the project root
- The `templateRepo` path in the manifest must point to a valid claude-code-toolkit checkout

## Workflow

### 1. Load Manifest

Read `.claude/template-manifest.json` from the project root. If it doesn't exist, stop with:
> "No template manifest found. Run `setup-project.ps1` to create one, or create `.claude/template-manifest.json` manually."

Extract: `variant`, `templateRepo`, `lastSynced`, `placeholders`, `files`.

### 2. Validate Template Repo

Check that `{templateRepo}` exists and contains `templates/{variant}/`. If not, stop with:
> "Template repo not found at `{templateRepo}`. Update the `templateRepo` path in `.claude/template-manifest.json`."

Get the current HEAD commit of the template repo:
```bash
git -C {templateRepo} rev-parse --short HEAD
```

### 3. Compute Hashes and Classify Changes

For each file in `manifest.files`:

1. **Read the template version** from `{templateRepo}/templates/{variant}/{filePath}`
   - If the template file doesn't exist: mark as `TEMPLATE_DELETED` and warn
2. **Apply placeholder replacement**: for each key in `manifest.placeholders`, replace `{{KEY}}` with the concrete value in the template content
3. **Hash the replaced content**: compute SHA-256 of the result
4. **Compare** against `manifest.files[filePath].templateHash`

Classify into buckets:

| Template changed? | locallyModified? | Classification |
|---|---|---|
| No | No | `UP_TO_DATE` — skip |
| No | Yes | `PROJECT_CUSTOM` — skip |
| Yes | No | `AUTO_UPDATE` — copy template → project |
| Yes | Yes | `CONFLICT` — show diff, user decides |

### 4. Check for New Template Files

Scan `{templateRepo}/templates/{variant}/` for files NOT in `manifest.files`:
- `.claude/agents/*.md`, `CLAUDE.md`, `AGENT_TEAM.md`, `PROJECT_STATE.md`, etc.
- Exclude: `gitignore`, `PROJECT_CONTEXT.md` (always project-specific)
- Classify as `NEW_FILE` — offer to copy and add to manifest

### 5. Apply Changes

**For `AUTO_UPDATE` files:**
- Read template file, apply placeholder replacement, write to project
- Update `manifest.files[path].templateHash` to the new hash

**For `CONFLICT` files:**
- Show the diff between current project file and the new template version (post-replacement)
- Ask user: "Merge manually / Skip / Overwrite with template"
- If overwrite: copy and update hash, set `locallyModified: false`
- If skip: update `templateHash` to new value (acknowledge template changed, keep local version)

**For `NEW_FILE` files:**
- Copy template file with placeholder replacement
- Add to manifest with `locallyModified: false`

**For `TEMPLATE_DELETED` files:**
- Warn: "Template no longer contains `{file}`. Your project copy is preserved."
- Do NOT delete from project

### 6. Update Manifest

- Set `lastSynced` to the template repo's current HEAD commit hash
- Write updated `.claude/template-manifest.json`

### 7. Report

Print summary:
```
## Sync Report

Template: {variant} @ {newCommit} (was {oldCommit})

Auto-updated: [list of files]
Conflicts: [list — user action needed]
New files added: [list]
Skipped (project-custom): [list]
Skipped (up to date): [list]
Template-deleted warnings: [list]

Manifest updated.
```

## Hash Computation

Use PowerShell or Bash to compute SHA-256. The hash is computed on the template content AFTER placeholder replacement (so it matches what was originally copied to the project).

```bash
echo -n "file content" | sha256sum | cut -d' ' -f1
```

Or read the file and use Python/PowerShell — the exact method doesn't matter as long as it's consistent. Claude should compute the hash by reading file content and using a SHA-256 tool.

**Important:** Use the same encoding (UTF-8, no BOM) for both hashing and file comparison.

## Rules

- NEVER auto-update a `locallyModified: true` file without user confirmation
- NEVER delete project files, even if the template removed them
- ALWAYS apply placeholder replacement before comparing or copying
- ALWAYS update the manifest after sync, even if no files changed (updates `lastSynced`)
- If `templateRepo` path uses backslashes, normalize to forward slashes for cross-platform consistency
