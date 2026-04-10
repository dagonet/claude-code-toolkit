---
name: contribute-upstream
description: Push project improvements back to the template repo. Triggers on /contribute-upstream. Uses template-sync-tools MCP server for deterministic placeholder reversal and cross-variant propagation.
---

# Contribute Upstream

Push improvements from the current project back to the claude-code-toolkit template.

**Requires:** `template-sync-tools` MCP server registered and running.

## Workflow

### 1. Load Manifest and Find Candidates

Call `template_load_manifest(project_path=".")`. If errors, stop.

Call `template_compute_status(project_path=".")`.

Collect files where `locally_modified` is true. Skip `PROJECT_CONTEXT.md` (always project-specific).

If no candidates: "No locally modified template files. Nothing to contribute."

Present the list:
```
Locally modified template files:
1. .claude/agents/architect.md
2. CLAUDE.md
3. .claude/agents/code-reviewer.md
```

### 2. Diff and Classify Each Candidate

For each candidate file:

1. Call `template_get_diff(project_path=".", file_path=F, diff_type="local_changes")`
2. Show the diff to the user
3. Ask: **Generalizable** (benefits any project using this variant) or **Project-specific** (unique to this project)?

Do NOT auto-classify. Always confirm with the user.

### 3. Reverse Placeholders

For each file confirmed as generalizable:

1. Call `template_reverse_placeholders(project_path=".", file_path=F)`
2. Show the `replacements_made` list so the user can verify placeholders were restored correctly
3. Show the `reversed_content` (or a relevant excerpt) for confirmation
4. If the user spots issues, they can provide corrected content

### 4. Check Cross-Variant Propagation

For each confirmed file:

1. Call `template_check_cross_variant(template_repo=..., variant=..., file_path=F)`
2. If `can_propagate` is true (all variants have identical content): offer to propagate to all variants
3. If `can_propagate` is false (variants differ): only update the current variant and warn:
   > "`{file}` differs across variants. Only updating `{variant}`. Check other variants manually."

### 5. Write to Template

For files being propagated to all variants:

Call `template_propagate_to_variants(template_repo=..., file_path=F, content=<reversed_content>, target_variants=<JSON array>)`.

For files only updating current variant:

Call `template_propagate_to_variants(template_repo=..., file_path=F, content=<reversed_content>, target_variants=["<current_variant>"])`.

### 6. Update Manifest

For each contributed file:

Call `template_apply_file(project_path=".", file_path=F, source="skip")` to update the manifest entry (marks the file as back in sync with template).

Call `template_finalize_sync(project_path=".", applied_files=<JSON array of results>)`.

### 7. Report

```
Contribution Report

Contributed to template ({variant}):
  - .claude/agents/code-reviewer.md (propagated to: all variants)
  - CLAUDE.md (updated: {variant} only)

Skipped (project-specific):
  - .claude/agents/architect.md

Changes written to {templateRepo}. Review and commit when ready.
```

## Rules

- NEVER write to the template repo without showing the diff first
- NEVER auto-classify — always confirm with the user whether a change is generalizable or project-specific
- ALWAYS show reversed content for confirmation before writing to template
- Do NOT commit in the template repo — write files only, let the user review and commit
- Do NOT modify `PROJECT_CONTEXT.md` in the template (always project-specific)
- All placeholder reversal is handled by the MCP tools — do NOT reverse placeholders manually
