# PR B — Hook Hardening (W1 + W2)

**Date:** 2026-04-12
**Tier:** T3 (shell script rewrite + doc update + new plan file)
**Team:** coder, code-reviewer, tester
**Status:** Approved, implementing

## Context

Follow-up PR B from `docs/workflow-audit.md`. Closes two hook/enforcement gaps identified in the workflow audit:

- **W1** — `hooks/tier-before-coder.sh` is permissive. Current logic: require a `Tier: T1`-`T4` declaration in any plan file plus a case-insensitive match on `challenge` or `architect`. A plan that mentions the word "architect" once trivially passes; two-pass challenge evidence is not enforced; stale plan files pass indefinitely.
- **W2** — No enforcement that the team declared for a tier matches the tier's rules (T3: coder + code-reviewer + tester; T4: architect + coder + code-reviewer + tester). A T3 task can be authored with a plan that only names a coder; nothing complains.

A prior architectural decision in `docs/hook-enforcement-ideas.md` lists these two as **"Not Practical for Hooks"** on the grounds that they need conversation-level state tracking. The audit re-examination found a narrower enforcement model that does not need conversation state: the hook can enforce that the **plan file's declared state** is shaped correctly, even though it cannot prove the underlying events occurred.

This is a genuinely weaker form of enforcement — a determined PO can spoof the plan file. But the current hook treats forgetfulness and deception identically; the new hook forces deception to be active, which is a higher wall.

## Challenge 1 (scope)

- Folded the plan-freshness check into W1 rather than scoping it as a separate item. It's a two-line addition in the same hook; splitting it would create a PR B.1 for no reason.
- Rejected stateful tracking (`.claude/workflow-state.json`). The original `hook-enforcement-ideas.md` deferred it pending a design pass and that pass has not happened. Ship grep-based enforcement now; revisit state tracking as a future PR if the grep gate proves insufficient.
- Decided NOT to migrate existing plan files (`2026-04-12-mcp-dependency-cleanup.md`, `2026-04-12-pr-a-workflow-doc-consistency.md`, `2026-04-12-wire-superpowers-skills.md`) to the new format. The hook uses OR semantics across plan files — if PR B's own plan file passes, the hook passes. Retroactive migration is cleanup, not enforcement, and belongs in a separate PR.
- `setup-project.sh` / `.ps1` already copy `hooks/*.sh` to target projects, so one edit propagates. No per-variant changes needed.
- No settings.json changes in any template variant. Hook wiring is unchanged; only the script contents change.

## Challenge 2 (correctness)

- Plan-file selection: the hook iterates every `*.md` in `docs/plans/` and `$HOME/.claude/plans/` and passes if **any** file validates. The alternative (pick newest by mtime) is unreliable because git checkout resets mtimes. OR semantics match the user intent: "at least one compliant plan exists for the current work".
- Tier extraction regex: handles both `Tier: T3` and `**Tier:** T3` by matching `^\*?\*?[Tt]ier:` and then extracting `T[1-4]` from that line. Verified against all 3 existing plan files.
- Team line regex: handles `**Team:**` and plain `Team:`. Required members are checked with substring grep, not a strict ordered match — `Team: architect, coder, code-reviewer, tester` and `Team: coder + tester + code-reviewer + architect` both pass T4 validation.
- `stat` invocation: Linux/Git Bash uses `stat -c %Y`, macOS uses `stat -f %m`. Falls back to `echo 0` (treated as "age exceeds limit" → rejection with diagnostic, not silent pass).
- `set -euo pipefail` intentionally NOT enabled. The hook uses explicit exit codes throughout; `set -e` interacts badly with `local var=$(...)` patterns and subshell-captured validate output.
- Freshness window: 14 days. Too short causes friction on long-running plans; too long defeats the point. 14 days matches typical sprint cadence.

## Scope (in)

1. **`hooks/tier-before-coder.sh`** — rewrite with tightened W1 + W2 Option A checks:
   - Require `Tier: T1`-`T4` declaration
   - Require both `Challenge 1` AND `Challenge 2` literal anchors
   - Require `Team:` line matching the declared tier (T3: coder + code-reviewer + tester; T4: + architect; T1/T2: any or none)
   - Require plan mtime within 14 days
   - OR semantics: at least one plan in `docs/plans/` or `$HOME/.claude/plans/` must pass all checks
   - Detailed diagnostic output listing per-file failure reasons on block

2. **`docs/hook-enforcement-ideas.md`** — document the tightening:
   - Update entry #7 with the new validation rules
   - Add a new "Grep-based enforcement: strengths and limits" subsection explicitly calling out spoofability (the hook does not prove events occurred; it only checks the plan file's declaration shape)
   - Move "Two architect challenges" and "Correct team composition per tier" out of the "Not Practical" table into an accepted-with-limits framing, cross-referenced to the new subsection

3. **`docs/plans/2026-04-12-pr-b-hook-hardening.md`** — this plan file (created in scope 3).

## Scope (out)

- **No stateful tracking infrastructure.** `.claude/workflow-state.json`, cross-spawn cycle counters, conversation-level replay — all deferred until a dedicated design PR.
- **No migration of existing plan files.** Three plans predate the new format and will not pass the new hook individually. That is acceptable because (a) hook uses OR semantics, (b) PR B's own plan is compliant, (c) future plans conform going forward, (d) migration is cleanup not enforcement.
- **No settings.json changes.** Hook wiring is unchanged across all 6 template variants.
- **No `no-push-main.sh` changes.** Out of PR B scope.
- **No new agents or role changes.** W11 (CI/format-recovery role) still deferred to PR C or later.

## Deliverables

### D1 — `hooks/tier-before-coder.sh` rewrite

Complete replacement of the hook script. Preserves:
- Matcher: Agent
- Coder-variant allowlist behavior (only blocks `coder`, `dotnet-coder`, `java-coder`, `python-coder`, `rust-coder`)
- Pass-through for all other agent types
- Search paths: `docs/plans/` then `$HOME/.claude/plans/`
- Block message prefix: `BLOCKED:`

Adds:
- `validate_plan()` function that checks all 4 conditions and returns 0 (pass) or 1 (fail + echo diagnostic)
- Iteration over all candidate plan files with OR-pass semantics
- Aggregated failure diagnostic output when no plan passes

### D2 — `docs/hook-enforcement-ideas.md` update

- Entry #7 ("Tier before agents") rewritten with new rules and diagnostic format
- New subsection "Grep-based enforcement: strengths and limits" added before the "Not Practical for Hooks" table
- Rows for "Two architect challenges" and "Correct team composition per tier" moved out of "Not Practical" into a new "Accepted with grep-based limits" section, with explicit caveats
- Summary table row #7 updated to reflect the new rules

### D3 — This plan file

Committed to `docs/plans/2026-04-12-pr-b-hook-hardening.md` per the "plans live in docs/plans" feedback memory.

## Critical files

| File | Edit |
|---|---|
| `hooks/tier-before-coder.sh` | Full rewrite |
| `docs/hook-enforcement-ideas.md` | Entry #7 rewrite + new "grep-based enforcement" subsection + Summary row update |
| `docs/plans/2026-04-12-pr-b-hook-hardening.md` | NEW (this file) |

Total: **3 files**.

## Implementation order

1. Write `hooks/tier-before-coder.sh` (full rewrite).
2. Write `docs/hook-enforcement-ideas.md` updates.
3. Write this plan file (already done at step 0 per workflow requirement).
4. Local hook smoke test:
   - Synthetic JSON input for each subagent_type (pass-through check)
   - Synthetic plan file with missing Tier (block + diagnostic)
   - Synthetic plan file with one Challenge (block)
   - Synthetic plan file with T3 but no Team (block)
   - Synthetic plan file with T3 + Team: coder only (block, missing reviewer/tester)
   - Synthetic plan file with valid T3 (pass)
   - Synthetic plan file with valid T4 (pass)
   - Synthetic plan file older than 14 days via `touch -d` (block)
5. Verify the existing PR B plan file (this one) passes `validate_plan`.
6. Commit.

## Verification

1. **Pass-through for non-coder agents:**
   ```
   echo '{"subagent_type":"architect"}' | bash hooks/tier-before-coder.sh && echo PASS
   echo '{"subagent_type":"code-reviewer"}' | bash hooks/tier-before-coder.sh && echo PASS
   echo '{"subagent_type":"tester"}' | bash hooks/tier-before-coder.sh && echo PASS
   ```
   → All print `PASS`.

2. **Block missing Tier:**
   ```
   mkdir -p /tmp/pr-b-test/docs/plans
   echo "# bad" > /tmp/pr-b-test/docs/plans/bad.md
   cd /tmp/pr-b-test
   echo '{"subagent_type":"coder"}' | bash /g/git/claude-code-toolkit/hooks/tier-before-coder.sh; echo "exit=$?"
   ```
   → Prints `BLOCKED:` diagnostic with `no 'Tier: T1'-'T4' declaration`, exit 2.

3. **Block single Challenge:**
   Plan with Tier + `Challenge 1` but no `Challenge 2` → BLOCKED with `missing 'Challenge 1' or 'Challenge 2' literal`.

4. **Block T3 missing Team:**
   Plan with Tier T3, both challenges, no Team line → BLOCKED with `no 'Team:' declaration`.

5. **Block T3 partial Team:**
   Plan with Tier T3, both challenges, `Team: coder` → BLOCKED with `Team: line missing member 'code-reviewer'`.

6. **Pass valid T3:**
   Plan with Tier T3, both challenges, `Team: coder, code-reviewer, tester` → exit 0.

7. **Block stale plan:**
   Use `touch -d "20 days ago" plan.md` → BLOCKED with `stale (20 days old, limit 14)`.

8. **Self-check:**
   ```
   echo '{"subagent_type":"coder"}' | bash hooks/tier-before-coder.sh; echo "exit=$?"
   ```
   Run from repo root. → exit 0, because `docs/plans/2026-04-12-pr-b-hook-hardening.md` (this file) is compliant.

## Reused infrastructure

- `setup-project.sh` + `setup-project.ps1` already copy `hooks/*.sh` to target projects. No setup-script changes needed for PR B.
- `settings.json` in all 6 variants already wires the hook as `PreToolUse` matcher `Agent`. No settings.json changes.
- Existing `Challenge 1` / `Challenge 2` convention from the Plan Challenge Protocol (AGENT_TEAM.md) is the source of the new literal anchors — no convention change, only enforcement alignment.

## Expected behavior

- Projects that previously relied on the loose challenge check will get hook rejections on next coder spawn until they either add `Challenge 2` to their plan (if missing) or update the plan's Team: line.
- The three existing plans in this repo (`2026-04-12-mcp-dependency-cleanup.md`, `2026-04-12-pr-a-workflow-doc-consistency.md`, `2026-04-12-wire-superpowers-skills.md`) will not individually pass the new hook but are irrelevant because this plan file does. A future cleanup PR can migrate them.
