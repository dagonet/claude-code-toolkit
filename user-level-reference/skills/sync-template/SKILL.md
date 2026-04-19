---
name: sync-template
description: Pull template updates into the current project. Triggers on /sync-template.
---

# Sync Template (Downstream)

Pull updates from the claude-code-toolkit template repo into the current project.

**Requires:** `template-sync-tools` MCP server registered and running.

## Workflow

### 1. Load Manifest

Call `template_load_manifest(project_path=".")`.

- If `valid` is false, stop and show the errors to the user.
- If `warnings` mentions v1 migration, inform the user their manifest will be upgraded to v2.

### 2. Compute Status

Call `template_compute_status(project_path=".")`.

Show the summary to the user:
```
Sync Status: {variant} @ {template_commit} (last synced: {last_synced_commit})

  Auto-update:  {summary.auto_update} files (template changed, project unchanged)
  Conflicts:    {summary.conflict} files (both changed — needs review)
  Up to date:   {summary.up_to_date} files
  Project-only: {summary.project_custom} files
  New files:    {len(new_template_files)} available
  Deleted:      {summary.template_deleted} warnings
```

If everything is up-to-date and no new files, report "Already in sync" and finalize.

### 3. Auto-Update Files

For each file with status `AUTO_UPDATE`:

Call `template_apply_file(project_path=".", file_path=F, source="template")`.

Collect all results. Report the list of auto-updated files.

### 4. Resolve Conflicts

For each file with status `CONFLICT`:

1. Call `template_get_diff(project_path=".", file_path=F, diff_type="three_way")`
2. Check the `merge_result`:
   - If `has_conflicts` is **false**: show the `auto_merged` content and tell the user "Three-way merge resolved cleanly — no conflicts." Offer to apply.
   - If `has_conflicts` is **true**: show the conflict markers and the `unified_diff`. Ask the user how to resolve:
     - **Accept merged** (if they edit the merged content)
     - **Accept template** (discard local changes)
     - **Keep mine** (acknowledge template change but keep project version)
3. Apply the user's choice:
   - Accept merged/template: `template_apply_file(source="provided", content=...)` or `template_apply_file(source="template")`
   - Keep mine: `template_apply_file(source="skip")`

### 5. Handle New Files

For each file in `new_template_files`:

Ask the user whether to add it. If yes:

Call `template_apply_file(project_path=".", file_path=F, source="template")`.

### 6. Handle Template-Deleted Files

For each file with status `TEMPLATE_DELETED`:

Warn: "Template no longer contains `{file}`. Your project copy is preserved."

Do NOT delete project files.

### 7. Finalize

Call `template_finalize_sync(project_path=".", applied_files=<JSON array of all template_apply_file results>)`.

### 8. Report

```
Sync complete: {variant} @ {new_commit}

  Auto-updated: [list]
  Merged:       [list]
  Skipped:      [list]
  New files:    [list]
  Warnings:     [list]
```

## Rules

- NEVER auto-update a `CONFLICT` file without user confirmation
- NEVER delete project files, even if the template removed them
- ALWAYS call `template_finalize_sync` at the end, even if no files changed (updates `lastSynced`)
- All hashing, diffing, and placeholder replacement is handled by the MCP tools — do NOT compute hashes or apply placeholders manually
