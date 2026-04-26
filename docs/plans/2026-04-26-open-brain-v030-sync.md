# Sync MCP tool references for Open Brain v0.3.0

**Date:** 2026-04-26
**Branch:** `chore/open-brain-v030-sync`
**Upstream:** https://github.com/dagonet/open-brain/pull/7 (squash-merged 00e269a)

Inspired-by: karpathy/442a6bf555914893e9891c11519de94f (gist) via Nate B Jones (youtu.be/dxq7WtWxi44)

## Context

Open Brain shipped v0.3.0 on 2026-04-26. The MCP server bumped from 8 tools to 14, adding a write-time wiki layer and an on-demand contradiction audit on top of the existing thoughts store:

- **Wiki tools:** `wiki_get`, `wiki_list`, `wiki_refresh`
- **Contradictions tools:** `contradictions_list`, `contradictions_resolve`, `contradictions_audit`

Existing `thoughts_*` tools and `system_status` are unchanged. The MCP server also gained a per-repo opt-out env var: `OPEN_BRAIN_TOOLS_DISABLED=wiki,contradictions` filters those families from `tools/list`.

Templates bootstrapped from this toolkit don't yet know about the new tools. This PR syncs the references across all 6 variants and the user-level-reference mirror without disrupting the existing three-layer enforcement structure (CLAUDE.md bootstrap → MCP server instructions → CLAUDE.local.md hard requirement).

## Constraints

- **Preserve three-layer enforcement** (captured decision `4c1c376c` in Open Brain): no hedge that gives Claude an excuse to skip the unconditional `thoughts_search` mandate at session start. The wiki-first sentence is *appended* to bootstrap step 3 as conditional follow-up guidance — it does not replace the existing directive.
- **Wiki-first rule is intentionally conditional**: only fires when a wiki page exists for the topic and the response is not stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days).
- **CI placeholder parity** (`.github/workflows/placeholder-parity.yml`): user-level-reference must stay in sync with templates. Every template-side change has a mirror in `user-level-reference/`.
- **Inspiration trailer** must appear in every commit message, the PR body, the CHANGELOG entry, and any README updates touching this work.

## Files modified

### Per-variant (× 6: general, dotnet, dotnet-maui, rust-tauri, java, python)

- `templates/<v>/CLAUDE.md` — Session Bootstrap step 3: append the conditional wiki-first sentence after the existing `thoughts_search`/`thoughts_recent` mandate.
- `templates/<v>/CLAUDE.local.md`:
  - Server registry line: bump tool count `8 → 14`, list new tool names alongside existing thoughts_*.
  - `## Open Brain Memory -- HARD REQUIREMENT` section: insert two new subsections (`### Wiki Tools` and `### Contradictions Tools`) **between** `### During the Session` and `### Forbidden`, so `### Forbidden` remains the section's last word.

### User-level mirror

- `user-level-reference/CLAUDE.md` — same bootstrap-step-3 appended sentence as templates.
- `user-level-reference/README.md` — add a short paragraph near the existing `{{OPEN_BRAIN_COMMAND}}` / `{{OPEN_BRAIN_ARGS}}` placeholder docs explaining the per-repo opt-out (`OPEN_BRAIN_TOOLS_DISABLED=wiki,contradictions`) and how to set it via the open-brain server's `env` block in `.mcp.json`.
- `mcp-servers/HOWTO.md` — Open Brain section (~line 279): list the 14 tools (replacing the 8-tool listing) and document the per-repo opt-out.

### Documentation

- `docs/architecture.md` — bootstrap-summary line (~line 51): append same conditional wiki-first follow-up as CLAUDE.md.

### Out of scope (verified)

- `templates/<v>/.claude/settings.json` — uses `mcp__open-brain__*` wildcard. New tools already permitted. No edit.
- `user-level-reference/settings-reference.md` — same wildcard. No edit.
- `user-level-reference/.mcp.json.template` — strict JSON (no comments). Opt-out documented in README.md / HOWTO.md only.
- Skill files under `user-level-reference/skills/` — none reference Open Brain capabilities. Verified empty grep.
- `AGENT_TEAM.md × 6` — Open Brain section is byte-identical across variants but doesn't enumerate tool names; no tool-name update needed there.

### New files

- `CHANGELOG.md` (root) — single entry for the v0.3.0 sync with the inspiration trailer.

## Verification (pre-push)

1. `git diff main...HEAD --stat` — confirm only the files listed above appear.
2. `grep -rn '(8 tools)' templates/ user-level-reference/ mcp-servers/` — should be empty after edits.
3. `bash scripts/verify-template-consistency.sh` — must pass.
4. `bash scripts/verify-user-level-drift.sh` — must pass.
5. Manual check: each `templates/<v>/CLAUDE.local.md` still contains all three subsections `### At Session Start (MANDATORY)`, `### During the Session`, `### Forbidden` in the `## Open Brain Memory -- HARD REQUIREMENT` section, in that order, unchanged.

## PR

- Title: `chore: sync MCP tool references for Open Brain v0.3.0`
- Body includes: upstream link, inspiration trailer, summary of files touched, verification checklist outcome.
