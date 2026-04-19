# Context Token Optimization — Templates & user-level-reference

**Date:** 2026-04-19
**Status:** Implemented 2026-04-19 — items 1, 3, 4 shipped; item 2 dropped; item 5 deferred.

## Outcome

| Item | Result |
|------|--------|
| (1) AGENT_TEAM.md on-demand + inline Binding Table | Shipped across 6 variants (~15 lines added, ~8.5K tokens/session saved at boot). |
| (2) Hoist universal blocks to user-level | Dropped (per challenge). |
| (3) Compress CLAUDE.local.md MCP tool overview | Shipped across all 6 variants. Net: **-436 lines** (~8,700 tokens) across templates. |
| (4) Trim skill descriptions (≤130 chars) | Shipped for 5 skills in `user-level-reference/skills/`; synced to `~/.claude/skills/` for runtime effect. |
| (5) Shared agents directory | Deferred — no runtime impact, maintenance-only; revisit if drift becomes painful. |

Cumulative per-session boot savings: **~9,000–10,000 tokens** (vs. ~14–16K baseline).

## Context

Prior baseline work (`docs/plans/2026-04-14-context-baseline.md`) identified `Read` as the biggest runtime bucket (22% of session context). This plan addresses the *other* lever: **auto-loaded setup context** — what every new session pays before the first user message.

Current per-session auto-load totals (CLAUDE.md + CLAUDE.local.md + AGENT_TEAM.md-on-boot):

| Variant      | Lines | Tokens (~)  |
|--------------|-------|-------------|
| general      |   562 |       5,620 |
| dotnet       |   692 |       6,920 |
| java         |   632 |       6,320 |
| python       |   634 |       6,340 |
| rust-tauri   |   679 |       6,790 |
| dotnet-maui  |   751 |       7,510 |

Add the mandated `Read AGENT_TEAM.md` on session bootstrap (~8.5K tokens) and the real floor is **14–16K tokens before the first prompt**.

## Goals

1. Cut per-session auto-loaded context (CLAUDE.md + CLAUDE.local.md + mandated AGENT_TEAM.md read) by **~55–65%** per variant — 14–16K tokens → 5–7K tokens at boot.
2. Remove the mandatory boot-time read of `AGENT_TEAM.md` while keeping the `require-skills-block.sh` hook enforceable.
3. Compress redundant MCP tool enumerations in CLAUDE.local.md where not load-bearing.
4. Tighten skill descriptions (auto-loaded into the skill list) to ≤ 130 chars, preserving invocation triggers.

## Recommended Approach

### 1. Stop mandating `Read AGENT_TEAM.md` at session start  *(biggest win — ~8.5K tokens/session)*

**Problem:** Every variant's `CLAUDE.md` Session Bootstrap step 1 says "Read `AGENT_TEAM.md`". This pulls 852 lines into context before any user request.

**Change:**
- Inline the ~40-line operating essentials (PO role, tier table, pipeline, merge ownership) — most already present in CLAUDE.md.
- **Also inline a condensed ~15-line Spawn-Prompt Binding Table snippet into CLAUDE.md** so the PO can satisfy the `hooks/require-skills-block.sh` PreToolUse hook (which blocks spawns without a `## Required Skills` block) without re-reading AGENT_TEAM.md on every sprint.
- Rewrite Bootstrap step 1 with *concrete* on-demand triggers (not vague "reference when needed"): *"Do not Read AGENT_TEAM.md at session start. Read on-demand when (a) first spawning agents in a sprint, (b) invoking the Plan Challenge Protocol, or (c) the user asks about merge/escalation rules."*

**Files:** `templates/*/CLAUDE.md` (Bootstrap section + Binding Table snippet, all 6 variants).
**Expected saving:** ~8,500 tokens/session when no sprint runs; ~7,000 tokens when one does (still a net win).

### 2. ~~Hoist universal CLAUDE.md blocks to user-level~~  *(DROPPED after challenge)*

**Verdict from challenge:** Poor ROI (~900 tokens saved) vs. real breakage risk. User-level `~/.claude/CLAUDE.md` is machine-local — projects cloned by a teammate, headless CI runs, or machines without the toolkit's user-level config would silently lose the Open Brain tables, Superpowers trigger matrix, Working Preferences, and Compact Instructions. The duplication cost (6 copies in the template tree) is already mitigated by `mcp__template-sync-tools__template_check_cross_variant`.

**Decision:** Keep universal blocks inline in each variant's CLAUDE.md. Rely on `template_check_cross_variant` to detect drift.

### 3. Compress CLAUDE.local.md MCP tool overview  *(~1,000–1,500 tokens/session on eligible variants)*

**Problem:** Every variant's CLAUDE.local.md opens with 150–200 lines of per-tool enumeration duplicating what the MCP servers already advertise via their tool catalogs.

**Change:**
- Replace per-tool bullet lists with a short "MCP Servers Available" registry + usage-rule summary (~40 lines).
- Keep the *rules* (Rule 1–N: "prefer X over Y because Z") — those are the actionable content.
- Drop parameter signatures that Claude sees in the tool catalog anyway.

**Caveat (from challenge):** `dotnet-tools` parameter signatures in `dotnet/` and `dotnet-maui/` CLAUDE.local.md are referenced by the `dotnet-coder` agent's fallback rules. Before trimming those two variants, verify the fallback rules don't rely on inlined parameter docs; if they do, keep the `dotnet-tools` section unchanged and trim only the other MCP enumerations.

**Files:** `templates/general/CLAUDE.local.md`, `templates/java/CLAUDE.local.md`, `templates/python/CLAUDE.local.md`, `templates/rust-tauri/CLAUDE.local.md` — safe to trim. `templates/dotnet/CLAUDE.local.md`, `templates/dotnet-maui/CLAUDE.local.md` — trim with the dotnet-tools caveat.
**Expected saving:** ~150 lines × safe variants ≈ 1,500 tokens/session on general/java/python/rust-tauri; ~80 lines on dotnet/dotnet-maui if dotnet-tools block is preserved.

### 4. Trim over-long skill descriptions  *(~300 tokens session-start)*

Skill `description:` frontmatter is loaded into every session's skill list. Current offenders:
- `karpathy-guidelines` — 233 chars
- `contribute-upstream` — 206 chars
- `sync-template` — 182 chars
- `explaining-code` — 170 chars
- `code-review` — 169 chars

**Change (revised from challenge):** Cap at **≤ 130 chars** (not 120 — the tighter cap risks dropping the trigger clause that causes Claude to *invoke* the skill). For `karpathy-guidelines`, preserve the first sentence + "writing, reviewing, or refactoring code" trigger; move the "avoid overcomplication, make surgical changes…" tail into the SKILL.md body.

**Files:** `user-level-reference/skills/*/SKILL.md` (5 skills).

### 5. Dedupe per-variant repeated boilerplate  *(maintenance, not runtime — DEFERRED)*

Agents `code-reviewer.md` (105 lines), `coder.md` (43 lines), `architect.md` (41 lines) are identical across all 6 variants. A shared-agents directory would cut the 6-way maintenance cost but adds regression risk to `setup-project.ps1`.

**Defer** unless maintenance pain is real. No runtime impact (only one variant is used per project).

## Expected Totals (revised)

| Change                                | Tokens/session | Risk          |
|---------------------------------------|----------------|---------------|
| (1) No-boot-read AGENT_TEAM.md        | ~7,000–8,500   | Low (w/ snippet inlining) |
| (2) ~~Hoist universal blocks~~        | *dropped*      | —             |
| (3) Compress MCP tool lists           | ~1,000–1,500   | Low (dotnet caveat) |
| (4) Trim skill descriptions           | ~300           | None          |
| **Cumulative**                        | **~8,300–10,300** |             |

Item 1 alone delivers ~80% of the benefit — ship it first, measure, then decide whether 3 and 4 are still worth the effort. Takes each variant from 14–16K boot to **~5–7K boot**.

## Critical Files

- `templates/general/CLAUDE.md`, `templates/general/CLAUDE.local.md` — reference/starting point
- `templates/dotnet-maui/CLAUDE.local.md` — 545 lines, biggest offender
- `templates/*/CLAUDE.md` — Bootstrap section + inline Binding Table snippet (Item 1)
- `user-level-reference/skills/karpathy-guidelines/SKILL.md` — description trim
- `user-level-reference/skills/contribute-upstream/SKILL.md` — description trim
- `scripts/` (if any) / `setup-project.ps1` — no change needed for items 1–4

## Existing Utilities to Reuse

- `mcp__template-sync-tools__*` — already handles cross-variant propagation; use `template_propagate_to_variants` when editing shared sections.
- `template_check_cross_variant` — use after edits to verify variants stay in sync where intended and diverge where intended.

## Out of Scope

- Changes to `Read` discipline (covered by `docs/plans/2026-04-14-context-baseline.md` and `docs/plans/2026-04-14-read-size-gate.md`).
- Command file trimming — commands are on-demand, not auto-loaded; low ROI.
- Agent file consolidation (item 5 above) — defer unless maintenance pain grows.

## Verification

After each change:

1. **Line-count delta** — `wc -l templates/*/CLAUDE.md templates/*/CLAUDE.local.md` before/after; record in a follow-up plan entry.
2. **Cross-variant drift check** — `template_check_cross_variant` on shared sections to confirm they stayed identical.
3. **Cold-start session test** — open a fresh session in a project using each variant, confirm `/context` reports reduced system-prompt / memory-file tokens.
4. **Skill list check** — `/skills` still shows all skills with their trimmed descriptions readable, and Claude still *invokes* `karpathy-guidelines` on code-writing triggers (regression risk from description trim).
5. **Bootstrap regression test** — start a new session, verify the PO can still operate (agents spawn, plan mode triggers) without the mandatory `AGENT_TEAM.md` read. Confirm it loads on-demand when a sprint is planned.
6. **Spawn-hook dry-run** — after Item 1 ships, spawn a dev agent in a fresh session with no prior AGENT_TEAM.md read. Confirm `hooks/require-skills-block.sh` fires correctly based on the inlined Binding Table snippet (if PO omits `## Required Skills`, hook blocks; if included, spawn succeeds).
7. **Dotnet-coder fallback check** — for Item 3, confirm `dotnet-coder` agent's Bash fallback rules in `templates/dotnet/.claude/agents/dotnet-coder.md` and `templates/dotnet-maui/.claude/agents/dotnet-coder.md` don't depend on parameter signatures being inlined in CLAUDE.local.md before trimming those two variants.

## Sequencing (revised)

Do items in this order (each ships independently, each verifiable):

1. **(4) Skill descriptions** — smallest, near-zero risk, immediate win. Ship first as warm-up and to de-risk `karpathy-guidelines` trigger-preservation.
2. **(1) AGENT_TEAM.md on-demand + inline Binding Table snippet** — the main event. Deliver the ~8K/session reduction. Ship with the full verification suite (steps 5, 6 above).
3. **Measure.** Run `/context` on a fresh session per variant; record deltas. Decide whether Item 3 is still worth the effort given Item 1's gains.
4. **(3) MCP tool overview compression** — per-variant. Start with `general` / `java` / `python` / `rust-tauri` (safe). Only tackle `dotnet` / `dotnet-maui` after verification step 7.
5. **(5) Shared agents directory** — stays deferred.
