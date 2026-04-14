[Back to README](../../README.md)

# Plan: Wire Superpowers Skills Into Templates and User-Level Reference

**Date:** 2026-04-12
**Status:** Approved, pending implementation
**Related:** [workflow-audit.md](../workflow-audit.md) — current workflow shape + weaknesses this plan addresses (W15-W17) vs. defers (W1-W14).

## Context

The `claude-code-toolkit` templates currently contain zero mention of the superpowers plugin's skills in any `CLAUDE.md` variant (verified across all 6: general, dotnet, dotnet-maui, rust-tauri, java, python). `AGENT_TEAM.md` has a descriptive "Superpowers Skills Integration" section that maps skills to workflow phases, but the binding is inert: spawn prompts don't inject skill names, and CLAUDE.md never points Claude at any skill when triggers fire.

Meanwhile, the CLAUDE.md files carry home-grown narratives for Debugging and Build & Test Discipline that are mostly shadowed by `superpowers:systematic-debugging` and `superpowers:verification-before-completion` — but those narratives also contain project-specific wisdom from a prior `/insights` improvement cycle (read/write path symmetry, main-vs-branch diff, staff-engineer check) that the skills don't carry.

**Goal:** make skill invocation actionable and discoverable in both solo-PO mode and spawned-agent mode, while preserving the project-specific wisdom the earlier improvement cycle captured. Opinionated compression, not blanket deletion.

**Pre-flight verifications done in plan mode:**

- All 6 `templates/*/CLAUDE.md` files contain zero `superpowers:` mentions.
- The literal at `templates/general/AGENT_TEAM.md` line ~757 is the **plan-file template** (Appendix), not a spawn-prompt template — spawn prompts are constructed ad-hoc by the PO from the AGENT_TEAM.md rules. The correct place to wire spawn-side skill injection is a new PO responsibility bullet near line 52 (mirroring the existing Open Brain context mediation bullet), plus a Spawn-Prompt Binding Table in the Superpowers section.
- `receiving-code-review` skill verified: it's for the code author digesting review findings, not for the reviewer performing the review. Coder gets it; code-reviewer does not.
- `user-level-reference/CLAUDE.md` verified to be lean global rules (Platform, Sub-Agent File Write Discipline, New Project Setup). It does NOT contain Debugging, Build & Test Discipline, or Plan Challenge Protocol sections — those only live in `templates/*/CLAUDE.md`.

## Decisions (locked after four challenge rounds)

- **AGENT_TEAM.md wins** on overlaps with skills. Skills are implementation mechanics used *within* the lifecycle AGENT_TEAM.md defines (tier model, workstream pipeline, merge protocol). The Spawn-Prompt Binding Table only covers skills that aren't already handled by existing AGENT_TEAM.md constructs.
- **Thin pointers**, not deletion. Home-grown Debugging and Build & Test Discipline sections compress to ~2-3 lines each: a skill pointer plus the project-specific one-liner the skill doesn't carry. Plan Challenge Protocol pointer section in CLAUDE.md gets cut (substance stays in AGENT_TEAM.md).
- **Core 8 actionable skills + 2 meta notes** in the CLAUDE.md matrix. The 4 overlapping skills (`using-git-worktrees`, `finishing-a-development-branch`, `dispatching-parallel-agents`, `subagent-driven-development`) stay in AGENT_TEAM.md's Binding/phase table as reference only — no CLAUDE.md trigger entries.
- **No agent file edits.** Spawn-prompt injection is the binding; agent files would duplicate it and drift.
- **No hook changes.** `tier-before-coder.sh` and `no-push-main.sh` stay as-is. Hook hardening is deferred to follow-up PR B (see [workflow-audit.md](../workflow-audit.md#follow-up-pr-b--hook-hardening)).
- **No `<EXTREMELY-IMPORTANT>` emphasis wrapper.** Plain markdown for the Required Skills block. Add emphasis later only if subagents empirically skip it.
- **Manual propagation** across 6 variants + user-level-reference. `template_propagate_to_variants` behavior with variant-specific sections is unverified — safer to apply a shared patch 13 times.
- **user-level-reference/CLAUDE.md gets a leaner mirror** — solo triggers only, no Spawn-Prompt Binding cross-reference.

## Scope explicitly excluded

- Agent file edits (`.claude/agents/*.md`)
- Hook changes (`hooks/*.sh`) — see follow-up PR B
- `<EXTREMELY-IMPORTANT>` emphasis wrappers
- Session Bootstrap modifications
- `/sprint` and other user-level commands/skills
- `setup-project.{sh,ps1}` prerequisite notes
- `template_propagate_to_variants` tool behavior verification
- Line-757 plan-file template appendix in AGENT_TEAM.md (different artifact)
- Weaknesses W1-W14 surfaced by the workflow audit — see [workflow-audit.md](../workflow-audit.md#follow-up-pr-roadmap) for the follow-up PR roadmap.

## Deliverables

### Deliverable 1 — `templates/*/CLAUDE.md` (×6)

**Replace** `## Debugging` (Fix Strategy + Multi-Round Bug Fixes subsections, ~15 lines) with a ~3-line thin pointer:

```markdown
## Debugging
For bugs and unexpected behavior, invoke `superpowers:systematic-debugging`.
Project-specific reminder: trace read **and** write paths — a common miss is fixing one but not the other.
```

**Replace** `# Build & Test Discipline` (~8 lines) with a ~3-line thin pointer:

```markdown
# Build & Test Discipline
Before claiming any task complete, invoke `superpowers:verification-before-completion`.
Project-specific reminders: diff behavior between your branch and `main` to confirm the change does what's intended; ask "would a staff engineer approve this as-is?" before marking complete.
```

**Delete** the `# Plan Challenge Protocol` pointer section (3 lines) — substance stays in AGENT_TEAM.md, Session Bootstrap already directs Claude to read AGENT_TEAM.md at session start.

**Preserve verbatim:**

- `# Session Bootstrap (MANDATORY)`
- `## Workflow TL;DR`
- `## Open Brain Context for Agents`
- `## Working Preferences`
- `## Quick Start`
- `# Commit Workflow`
- `# Compact Instructions`
- **All variant-specific sections**: `.NET Conventions` (dotnet), `MAUI Conventions` (dotnet-maui), `Rust/Tauri Specific` + `Code Style (MANDATORY)` (rust-tauri), `Java/Spring Specific` + `Code Style (MANDATORY)` (java), `Python Specific` + `Code Style (MANDATORY)` (python)

**Add** new section `## Superpowers Skills — When to Invoke` placed after `## Open Brain Context for Agents`, before `## Working Preferences`:

```markdown
## Superpowers Skills — When to Invoke

Requires the [superpowers plugin](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers). Invoke via the Skill tool.

### Solo PO trigger matrix

| Trigger (user action / session event) | Skill to invoke |
|---|---|
| User describes a new feature or design idea | `superpowers:brainstorming` |
| Design is accepted, need to break into tasks | `superpowers:writing-plans` |
| Plan approved, starting implementation | `superpowers:executing-plans` |
| Writing any new code (feature or fix) | `superpowers:test-driven-development` |
| User reports a bug, test failure, or unexpected behavior | `superpowers:systematic-debugging` |
| Before claiming work complete or opening a PR | `superpowers:verification-before-completion` |
| Requesting review from the code-reviewer agent | `superpowers:requesting-code-review` |
| Digesting code review findings | `superpowers:receiving-code-review` |

**Chain note:** `writing-plans` produces a plan. The **Plan Challenge Protocol** in `AGENT_TEAM.md` validates any plan (regardless of source) before execution — independent gate, not a side-effect of `writing-plans`.

**When spawning agents:** see `AGENT_TEAM.md` → *Spawn-Prompt Binding Table* for the skills each subagent type must invoke.

### Meta skills (no explicit trigger)

- `superpowers:using-superpowers` — auto-loaded at session start; establishes skill-use protocol.
- `superpowers:writing-skills` — invoke only when creating or editing a skill.
```

### Deliverable 2 — `templates/*/AGENT_TEAM.md` (×6)

**Rewrite** the existing `## Superpowers Skills Integration` section (starts ~L621):

- **Keep** the one-paragraph intro ("When the superpowers plugin is installed...") but trim to a single sentence.
- **Delete** the existing phase-mapping table, the 5 rules, and the 12-step example walkthrough.
- **Add** the new **Spawn-Prompt Binding Table**:

```markdown
## Superpowers Skills Integration

When the [superpowers plugin](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers) is installed, its skills handle implementation mechanics (how to code efficiently) while AGENT_TEAM.md owns quality gates (tier, workstream, review, test, merge). Skills are tools used within the lifecycle defined here, not replacements for it.

### Spawn-Prompt Binding Table

When spawning an agent, include in the spawn prompt a `## Required Skills` block listing the skills below for the target subagent type. The spawned agent must invoke each skill via the Skill tool before beginning task work.

| subagent_type | Required Skills |
|---|---|
| `coder` (and all variant coders: `dotnet-coder`, `rust-coder`, `java-coder`, `python-coder`) | `test-driven-development`, `verification-before-completion`, `requesting-code-review`, `receiving-code-review` |
| `code-reviewer` | *(none — review is the agent's core job)* |
| `tester` | `systematic-debugging`, `verification-before-completion` |
| `test-writer` | `test-driven-development` |
| `architect` | `writing-plans`, `brainstorming` |
| `requirements-engineer` | `brainstorming` |
| `doc-generator` | *(none)* |

**Reference-only skills** (handled by existing AGENT_TEAM.md constructs, not injected via spawn prompt): `using-git-worktrees` (Worktree Naming), `finishing-a-development-branch` (Merge Protocol), `dispatching-parallel-agents` (Tier Model workstreams), `subagent-driven-development` (plan-files mode execution).

**Chain note:** `writing-plans` produces a plan. The Plan Challenge Protocol (below) validates any plan before execution — independent gate, not a side-effect of `writing-plans`.
```

**Add** a new PO responsibility bullet near the existing Open Brain context mediation bullet (currently ~L52 in general variant). Insert immediately after the Open Brain bullet:

````markdown
- **Spawn-prompt skill injection**: When constructing any spawn prompt, look up the target `subagent_type` in the Spawn-Prompt Binding Table (Superpowers Skills Integration section) and include a `## Required Skills` block in the prompt listing the skills to invoke via the Skill tool. Required Skills block looks like:

  ```markdown
  ## Required Skills
  Invoke these skills via the Skill tool before beginning task work:
  - superpowers:test-driven-development
  - superpowers:verification-before-completion
  ```

  Omit the block for `code-reviewer` and `doc-generator` spawns (no required skills).
````

### Deliverable 3 — `user-level-reference/CLAUDE.md`

This file is lean global rules (Platform, Sub-Agent File Write Discipline, New Project Setup). It does NOT contain Debugging, Build & Test Discipline, or Plan Challenge Protocol sections — those only live in `templates/*/CLAUDE.md`. So there are **no thin pointers to write** here; this is an **append-only** edit.

**Append** a new `## Superpowers Skills — When to Invoke` section at the end of the file, containing:

- The Solo PO trigger matrix (same 8 triggers as Deliverable 1)
- The Meta skills subsection (`using-superpowers`, `writing-skills`)

**Omit**:

- The "When spawning agents" cross-reference to AGENT_TEAM.md (user-level has no team workflow file)
- The chain note about Plan Challenge Protocol (not applicable user-level)

**Sync note:** `user-level-reference/CLAUDE.md` is a reference copy of `~/.claude/CLAUDE.md`. After committing the repo edit, the live user-level file at `~/.claude/CLAUDE.md` should be updated to match — but that is a post-merge manual step, not part of this repo PR.

### Deliverable 4 — `docs/workflow-audit.md`

Already written as part of this planning round (see [workflow-audit.md](../workflow-audit.md)). Contains:

- Mermaid workflow diagram with hook-enforced vs. documented-only distinction.
- Weaknesses inventory W1-W17 organized into five buckets.
- Follow-up PR roadmap (PR A: doc-consistency; PR B: hook-hardening; PR C: MCP expansion) plus deferred items.
- Source footer noting the audit origin.

### Deliverable 5 — `README.md` link

Add two lines under the existing docs list in `README.md`:

- `docs/workflow-audit.md` — *"Current workflow diagram + known enforcement gaps + follow-up PR roadmap."*
- `docs/plans/2026-04-12-wire-superpowers-skills.md` — *"Plan for wiring superpowers skills into templates and user-level reference."*

## Critical files to modify

| File | Variant | Edit |
|---|---|---|
| `templates/general/CLAUDE.md` | general | thin pointers + new Superpowers section |
| `templates/dotnet/CLAUDE.md` | dotnet | same |
| `templates/dotnet-maui/CLAUDE.md` | dotnet-maui | same |
| `templates/rust-tauri/CLAUDE.md` | rust-tauri | same |
| `templates/java/CLAUDE.md` | java | same |
| `templates/python/CLAUDE.md` | python | same |
| `templates/general/AGENT_TEAM.md` | general | rewrite Superpowers section + PO bullet |
| `templates/dotnet/AGENT_TEAM.md` | dotnet | same |
| `templates/dotnet-maui/AGENT_TEAM.md` | dotnet-maui | same |
| `templates/rust-tauri/AGENT_TEAM.md` | rust-tauri | same |
| `templates/java/AGENT_TEAM.md` | java | same |
| `templates/python/AGENT_TEAM.md` | python | same |
| `user-level-reference/CLAUDE.md` | user-level | **append-only** solo-PO Superpowers section |
| `docs/workflow-audit.md` | repo-wide | **already written** as part of planning |
| `docs/plans/2026-04-12-wire-superpowers-skills.md` | repo-wide | **this file** (persistent plan) |
| `README.md` | repo-wide | add two link lines under existing docs list |

Total: **16 files** (13 skills-wiring + audit doc + plan doc + README link).

## Reused infrastructure

- **Existing phase-mapping reference** in `AGENT_TEAM.md` L621-650 (will be replaced by the Binding Table — same location).
- **Open Brain context mediation bullet** near L52 in each AGENT_TEAM.md — precedent for how the new "Spawn-prompt skill injection" bullet is shaped and placed.
- **Existing plan-file-template directive** at L757 (`> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans...`) — stays unchanged; demonstrates the precedent pattern for skill references in AGENT_TEAM.md templates. The new `## Required Skills` block in spawn prompts is a compatible extension, not a conflict.
- **Session Bootstrap** in each CLAUDE.md — already directs Claude to read AGENT_TEAM.md, so the cross-reference from the CLAUDE.md Superpowers section to the AGENT_TEAM.md Binding Table works without adding a new step.

## Implementation order

1. Write `templates/general/CLAUDE.md` edits (thin pointers + new section).
2. Write `templates/general/AGENT_TEAM.md` edits (Binding Table + PO bullet).
3. Apply the same CLAUDE.md pattern to dotnet, dotnet-maui, rust-tauri, java, python.
4. Apply the same AGENT_TEAM.md pattern to dotnet, dotnet-maui, rust-tauri, java, python.
5. Append solo-only Superpowers section to `user-level-reference/CLAUDE.md` (no thin pointers — file lacks those sections).
6. `docs/workflow-audit.md` and `docs/plans/2026-04-12-wire-superpowers-skills.md` — **already written** as part of the planning round.
7. Add two link lines to `README.md` under the existing docs list.
8. Run the verification grep suite (below).
9. Dry-run the setup script against a scratch directory.
10. Capture W3-W7 and W11 to Open Brain as individual thoughts (one `thoughts_capture` call each) so deferred items are discoverable in future sessions.
11. Commit and PR.

After each of steps 3 and 4 (per variant), re-verify the variant-specific sections are intact before moving to the next variant.

## Verification

End-to-end checks after all edits are applied:

1. **Section-length check** (the thin-pointer headings reuse the old headings, so we check section *length*, not heading presence): after each `## Debugging` and `# Build & Test Discipline` heading in `templates/*/CLAUDE.md`, the next non-blank lines should total ≤ 5 lines before the next heading. (Skip `user-level-reference/CLAUDE.md` — no such sections.)

2. **Plan Challenge Protocol pointer removed from templates:**
   ```
   grep -c "^# Plan Challenge Protocol$" templates/*/CLAUDE.md
   ```
   → All 6 report 0.

3. **Skill references present in every variant:**
   ```
   grep -c "superpowers:" templates/general/CLAUDE.md templates/dotnet/CLAUDE.md templates/dotnet-maui/CLAUDE.md templates/rust-tauri/CLAUDE.md templates/java/CLAUDE.md templates/python/CLAUDE.md
   grep -c "superpowers:" templates/general/AGENT_TEAM.md templates/dotnet/AGENT_TEAM.md templates/dotnet-maui/AGENT_TEAM.md templates/rust-tauri/AGENT_TEAM.md templates/java/AGENT_TEAM.md templates/python/AGENT_TEAM.md
   grep -c "superpowers:" user-level-reference/CLAUDE.md
   ```
   → Every line reports ≥ 1.

4. **New section header present in every CLAUDE.md:**
   ```
   grep -c "^## Superpowers Skills — When to Invoke$" templates/*/CLAUDE.md user-level-reference/CLAUDE.md
   ```
   → All 7 report 1.

5. **Spawn-Prompt Binding Table present in every AGENT_TEAM.md:**
   ```
   grep -c "^### Spawn-Prompt Binding Table$" templates/*/AGENT_TEAM.md
   ```
   → All 6 report 1.

6. **PO responsibility bullet present:**
   ```
   grep -c "Spawn-prompt skill injection" templates/*/AGENT_TEAM.md
   ```
   → All 6 report 1.

7. **Variant-specific sections preserved:**
   - Read tail of `templates/dotnet/CLAUDE.md` — `.NET Conventions` present.
   - Read tail of `templates/dotnet-maui/CLAUDE.md` — `.NET Conventions` + `MAUI Conventions` present.
   - Read tail of `templates/rust-tauri/CLAUDE.md` — `Rust/Tauri Specific` + `Code Style (MANDATORY)` present.
   - Read tail of `templates/java/CLAUDE.md` — `Java/Spring Specific` + `Code Style (MANDATORY)` present.
   - Read tail of `templates/python/CLAUDE.md` — `Python Specific` + `Code Style (MANDATORY)` present.

8. **Plan Challenge Protocol substance still in each AGENT_TEAM.md:**
   ```
   grep -c "Plan Challenge Protocol" templates/*/AGENT_TEAM.md
   ```
   → All 6 report ≥ 1.

9. **Setup script dry-run:**
   ```
   mkdir /tmp/scratch-setup && bash setup-project.sh --variant general --dir /tmp/scratch-setup --dry-run
   ```
   → Exits clean, no placeholder errors, new sections present in dry-run output.

10. **Cross-variant consistency:**
    Diff the Superpowers section of each variant's CLAUDE.md against `templates/general/CLAUDE.md` — should be byte-identical modulo variant-specific surrounding sections.
    Diff the Superpowers Skills Integration section of each AGENT_TEAM.md against general — should be byte-identical.

11. **Expected behavior** (not a regression): projects that previously applied any template variant will see sync conflicts on CLAUDE.md and AGENT_TEAM.md on their next `/sync-template` run. Users resolve via the skill's three-way merge workflow.

12. **Audit doc present and linked:**
    - `test -f docs/workflow-audit.md` exits 0.
    - `grep -c "workflow-audit.md" README.md` reports ≥ 1.
    - Audit doc contains a mermaid block and all 17 weakness IDs (W1-W17) at least once.

13. **Open Brain deferred items captured:** after `thoughts_capture` calls in implementation step 10, `mcp__open-brain__thoughts_search` with query "claude-code-toolkit workflow weakness W3 W4 W5 W6 W7 W11" returns ≥ 6 results.
