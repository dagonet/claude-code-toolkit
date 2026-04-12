# PR A — Workflow Documentation Consistency

**Date:** 2026-04-12
**Tier:** T3 (multi-file, 6 variants + user-level-reference, doc-only)
**Status:** Challenged (2 passes) — executing

## Context

Follow-up PR A from `docs/workflow-audit.md`. Closes four doc-inconsistency gaps identified in the workflow audit:

- **W8** — Escalation Protocol exists in AGENT_TEAM.md (Rule 8 + dedicated section) but is invisible to a PO who skims only CLAUDE.md. Risk: PO loops on fix cycles indefinitely.
- **W9** — "Developer owns the merge" (AGENT_TEAM.md Rule 5) is silent in CLAUDE.md. Risk: PO merges on the coder's behalf, breaking the workstream handoff model.
- **W10** — Plan Challenge Protocol says architect shuts down after challenge, but T4 architect lifecycle says "standby". SubagentStop fires per-message and can be misread as a shutdown signal.
- **W12** — Tester agent has `Write` / `Edit` permissions for test files only, but nothing in the agent file forbids writes to `src/`. Pure doc/discipline note (no hook change).

**Challenge 1 (scope):** folded W9 into Commit Workflow section (not TL;DR) — closer to where merging happens, avoids bloating the TL;DR. W8 stays in TL;DR because escalation is a mental model PO needs early, not at commit time. W12 is an agent-file note, not a CLAUDE.md edit — agent files are authoritative for per-agent discipline.

**Challenge 2 (correctness):** W10 fix anchors at the "Transition rules:" bullet list after the architect lifecycle diagram (not a new section). Adds one bullet explicitly addressing SubagentStop misinterpretation. Does not contradict existing text — clarifies it.

## Scope (in)

1. **W8 — Escalation in CLAUDE.md TL;DR**: one sentence in each of 6 × `templates/*/CLAUDE.md`, placed before the "Full details: `AGENT_TEAM.md`" line.
2. **W9 — Merge ownership in Commit Workflow**: one paragraph in each of 6 × `templates/*/CLAUDE.md`, appended to the existing `# Commit Workflow` section.
3. **W10 — T4 architect SubagentStop clarification**: one bullet added to the "Transition rules:" list in each of 6 × `templates/*/AGENT_TEAM.md`.
4. **W12 — Tester write-scope note**: one paragraph added to each of 6 × `templates/*/.claude/agents/tester.md` + `user-level-reference/agents/tester.md` (7 total).

**Total: 25 files** (12 CLAUDE.md + AGENT_TEAM.md across 6 variants + 6 tester.md template variants + 1 user-level-reference tester).

Wait — 6 CLAUDE.md + 6 AGENT_TEAM.md + 6 tester.md + 1 user-level-reference tester = **19 files**.

## Scope (out)

- **No hook changes.** W1, W2 enforcement work is PR B.
- **No agent-file permission changes.** Tester still has `Write` / `Edit` — W12 is a discipline note, not a tool strip. A future PR could scope the Write tool via `if:` matchers, but PR A is doc-only.
- **No new sections in CLAUDE.md.** W8 is a one-liner in TL;DR; W9 is a paragraph in Commit Workflow.
- **No dotnet-maui / rust-tauri specific variants** for tester.md — maui and rust-tauri have variant-specific tester content (FlaUI, Windows-MCP) but the write-scope note applies universally. Apply the same patch to all 7 tester files.
- W11 (CI/format recovery role) deferred — needs a new agent.

## Deliverables

### W8 — CLAUDE.md TL;DR escalation line

Insert immediately before `Full details: AGENT_TEAM.md`:

```markdown
**Escalation:** After 3 failed fix cycles on one task, the PO pauses and chooses: (a) reduce scope, (b) re-spawn architect with failure context, or (c) escalate to the user. See Escalation Protocol in `AGENT_TEAM.md`.
```

### W9 — CLAUDE.md Commit Workflow merge ownership

Append to the existing `# Commit Workflow` section:

```markdown
**Merge ownership:** the developer who implemented the task owns the merge — rebase, CI-check, and squash-merge are the developer's job, not the PO's. The PO sequences merges across workstreams but does not merge on behalf of coders. See `AGENT_TEAM.md` → Merge Protocol.
```

### W10 — AGENT_TEAM.md Transition rules bullet

Append a fourth bullet to the "Transition rules:" list:

```markdown
- **SubagentStop fires per-invocation, not per-shutdown.** At T4, the architect stays in STANDBY after replying to a guidance request — do NOT interpret a SubagentStop event as a shutdown signal. The architect shuts down explicitly only after the last T4 task is guided and merged.
```

### W12 — tester.md write-scope note

Insert after the opening "You are a QA tester..." persona line:

```markdown
**Write/Edit scope:** you may ONLY create or modify files under the project's test directory (as specified in `PROJECT_CONTEXT.md`). Writing to `src/`, application code, or project config is forbidden. If a test needs a fixture or mock that doesn't exist yet, add it under the test tree — never edit production code to make a test pass.
```

## Critical files

- 6× `templates/*/CLAUDE.md` — W8 + W9
- 6× `templates/*/AGENT_TEAM.md` — W10
- 6× `templates/*/.claude/agents/tester.md` + 1× `user-level-reference/agents/tester.md` — W12

**Total: 19 files.**

## Implementation order

1. General variant first — CLAUDE.md (W8 + W9), AGENT_TEAM.md (W10), tester.md (W12).
2. Apply identical patches to the other 5 template variants.
3. Apply W12 to `user-level-reference/agents/tester.md`.
4. Verification grep suite.
5. Commit.

## Verification

1. `grep -c "Escalation:" templates/*/CLAUDE.md` → all 6 report ≥ 1.
2. `grep -c "Merge ownership:" templates/*/CLAUDE.md` → all 6 report 1.
3. `grep -c "SubagentStop fires per-invocation" templates/*/AGENT_TEAM.md` → all 6 report 1.
4. `grep -c "Write/Edit scope" templates/*/.claude/agents/tester.md user-level-reference/agents/tester.md` → all 7 report 1.
5. Cross-variant consistency: diff the added lines against the general variant — should be byte-identical.
