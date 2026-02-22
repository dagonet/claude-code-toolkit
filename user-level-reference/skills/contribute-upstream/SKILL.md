---
name: contribute-upstream
description: Push project improvements back to the template repo. Triggers on /contribute-upstream. Reads .claude/template-manifest.json, finds locally modified template-sourced files, helps generalize and write changes back to the template.
---

# Contribute Upstream

Push improvements from the current project back to the claude-code-toolkit template.

## Prerequisites

- `.claude/template-manifest.json` must exist in the project root
- The `templateRepo` path must point to a valid claude-code-toolkit checkout
- At least one file in manifest must have `locallyModified: true`

## Workflow

### 1. Load Manifest and Find Candidates

Read `.claude/template-manifest.json`. Collect all files where `locallyModified: true`.

If none: "No locally modified template files. Nothing to contribute."

Skip files that are inherently project-specific:
- `PROJECT_CONTEXT.md` — always project-specific (contains project values)

Present the list of candidates with their `reason` field:
```
Locally modified template files:
1. .claude/agents/architect.md — "Added MVVM details"
2. CLAUDE.md — "Added custom debugging section"
3. .claude/agents/code-reviewer.md — "Added MAUI/MVVM review section"
```

### 2. For Each Candidate: Diff and Classify

For each file:

1. **Read project version** (current file in the project)
2. **Read template version** from `{templateRepo}/templates/{variant}/{file}`
3. **Apply placeholder replacement** to template version using `manifest.placeholders`
4. **Show the diff** between the replaced template and the project version

Classify each change as:
- **Project-specific**: Contains project name, paths, domain terms unique to this project. NOT suitable for template.
- **Generalizable**: Structural improvements, new sections, better wording, new review criteria. ANY project using this variant would benefit.

Present classification to user for confirmation.

### 3. Generalize and Write Back

For changes confirmed as generalizable:

1. **Start from the project version** of the file
2. **Reverse placeholder replacement** — substitute concrete values back to `{{PLACEHOLDER}}`:
   - Sort placeholders by value length DESCENDING (longest first) to avoid partial matches
   - For each placeholder in `manifest.placeholders`, replace the concrete value with `{{KEY}}`
   - Example: `MyApp.sln` → `{{SOLUTION_FILE}}` before `MyApp` → `{{PROJECT_NAME}}`
3. **Write the generalized file** to `{templateRepo}/templates/{variant}/{file}`

### 4. Cross-Variant Propagation

Check if the file is identical across all template variants. Files known to be shared:
- `AGENT_TEAM.md`
- `PROJECT_STATE.md`
- `.claude/settings.json`

For shared files:
1. Read the same file from all other variant directories
2. If they are identical to the OLD template version (pre-change), apply the same change to all variants
3. If they differ, only update the current variant and warn:
   > "`{file}` differs across variants. Only updated `{variant}`. Check other variants manually."

For variant-specific files (CLAUDE.md, CLAUDE.local.md, agents): only update the current variant.

### 5. Update Manifest

After contributing, the project file now matches the template again:
- Update `templateHash` to the hash of the new template version (post-replacement)
- Set `locallyModified: false` (project is back in sync with template)
- Remove `reason` field

### 6. Report

```
## Contribution Report

Contributed to template ({variant}):
- .claude/agents/code-reviewer.md — generalized and written to template
- CLAUDE.md — generalized and written to template (also propagated to: general, dotnet)

Skipped (project-specific):
- .claude/agents/architect.md — MVVM details are variant-specific, kept as project customization

Changes are staged in {templateRepo}. Review and commit when ready.
```

## Reverse Placeholder Order

CRITICAL: Replace longest concrete values first to avoid partial matches.

1. Compound values: `DB_PATH` (full path = directory + filename)
2. Long strings: `REPO_URL`, `TECH_STACK`, `SOLUTION_FILE`, `MAUI_PROJECT`, `TEST_PROJECT`
3. Medium strings: `DB_DIRECTORY`, `DB_FILENAME`, `WORKTREE_BASE`, `LOG_PATH`
4. Short strings: `PROJECT_NAME` (most common, must be last to avoid stomping)
5. Derived: `PROJECT_NAME_LOWER`

## Rules

- NEVER write to the template repo without showing the diff first
- NEVER auto-classify — always confirm with user whether a change is project-specific or generalizable
- ALWAYS reverse placeholders before writing to template
- ALWAYS check cross-variant propagation for shared files
- Do NOT commit in the template repo — stage only, let user review and commit
- Do NOT modify `PROJECT_CONTEXT.md` in the template (always project-specific)
