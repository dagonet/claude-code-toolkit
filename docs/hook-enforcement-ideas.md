# Hook Enforcement Ideas for AGENT_TEAM.md Workflows

Claude Code hooks can intercept tool calls (`PreToolUse`) and block them with a message.
This document analyzes which AGENT_TEAM.md workflow conventions could be technically enforced
via hooks, versus which are better left as convention.

---

## Enforcement vs Convention

AGENT_TEAM.md defines a tiered sprint workflow (T1-T4) with roles, plan challenges,
worktree isolation, and merge sequencing. All rules are currently convention-only —
enforced by instructions in CLAUDE.md and AGENT_TEAM.md, not by code.

Hooks can enforce **tool-level invariants** (blocking specific tool calls based on arguments).
They cannot enforce **conversation-level state** (e.g., "did the architect challenge happen?").

### What hooks are good at

- Pattern matching on tool arguments (command strings, branch names, file paths)
- Running a shell check before allowing a tool call (build passes? format clean?)
- Blocking dangerous operations unconditionally

### What hooks cannot do

- Track multi-turn conversation state
- Count events across agent lifetimes
- Coordinate between parallel workstreams

---

## All Proposals Evaluated

### 1. No Bash git commands

**Status: ALREADY DONE**

`.claude/settings.json` already blocks `Bash(git ...)` via permission rules, forcing MCP git tools.

### 2. No push to main/master

**Status: ACCEPTED**

| Field | Value |
|-------|-------|
| Hook type | `PreToolUse` on `mcp__git-tools__git_push` |
| Logic | Reject if target branch is `main` or `master` |
| Edge cases | Must resolve implicit branch (when branch param is omitted, check current branch in the worktree). Needs escape hatch for initial repo setup or hotfix scenarios |

**Implementation notes:**
- The hook script receives the tool input as JSON on stdin
- Check `branch` field; if absent, run `git -C <repo_path> branch --show-current` to resolve
- Block with message: "Direct push to main/master is blocked. Use a feature branch and PR."

### 3. Format before commit

**Status: REJECTED**

Running `prettier --check .` on every commit adds latency across all tiers.
Blocks WIP commits, TDD failing-test-first commits, and partial saves during multi-file refactors.
The correct enforcement point is pre-merge (CI), not pre-commit.

### 4. Build must pass before commit

**Status: REJECTED**

Same problems as #3 — blocks legitimate development workflows:
- TDD: write failing test, commit, then implement
- Multi-file refactors where the build is temporarily broken
- WIP saves on feature branches

Directly conflicts with the worktree-based parallel model where developers work independently.
Enforce at pre-merge (CI or merge hook), not pre-commit.

### 5. No `gh` CLI

**Status: ALREADY DONE**

`.claude/settings.json` already blocks `Bash(gh ...)` via permission rules, forcing MCP GitHub tools.

### 6. Plan mode before implementation

**Status: DEFERRED**

A `PreToolUse` hook on `Edit`/`Write` could check for a plan file or `EnterPlanMode` marker.
Problems:
- T1 tasks are exempt, requiring tier awareness the hook doesn't have
- Temp marker files are fragile across sessions and worktrees
- Would fire on ALL file writes: MEMORY.md, plan files, settings, docs — needs a large fragile allowlist
- CLAUDE.md instructions already enforce this effectively

Marginal gain over convention. Revisit if plan-skipping becomes a recurring problem.

### 7. Tier + challenge + team + freshness before coder spawns

**Status: IMPLEMENTED** (tightened in PR B, 2026-04-12)

| Field | Value |
|-------|-------|
| Hook type | `PreToolUse` on `Agent` |
| Logic | Coder-variant spawns are blocked unless at least one plan in `docs/plans/` or `$HOME/.claude/plans/` satisfies all four: tier declaration, two-pass challenge literals, team-matches-tier line, mtime within 14 days |
| Edge cases | Only `coder`, `dotnet-coder`, `java-coder`, `python-coder`, `rust-coder` subagent types are gated — all other agent types (including architect, code-reviewer, tester, requirements-engineer) pass through unconditionally |

**Validation rules:**
1. **Tier declaration** — `Tier: T1`-`T4` or `**Tier:** T1`-`T4` (markdown-bold tolerated)
2. **Two-pass challenge** — both `Challenge 1` and `Challenge 2` literals must appear in the plan file
3. **Team declaration** —
   - T1/T2: `Team:` line optional
   - T3: must include `coder`, `code-reviewer`, `tester`
   - T4: must include `architect`, `coder`, `code-reviewer`, `tester`
4. **Freshness** — plan file mtime within last 14 days

**OR semantics:** at least one plan file must pass all four checks. Failures aggregate into a consolidated diagnostic listing every plan and its first failure reason.

**Diagnostic example** (single-challenge plan in `docs/plans/bad.md`):
```
BLOCKED: No plan passed tier-before-coder checks. Each plan must satisfy:
  1. 'Tier: T1'-'T4' declaration
  2. Both 'Challenge 1' and 'Challenge 2' literals
  3. 'Team:' line matching tier (T3: coder, code-reviewer, tester; T4: + architect)
  4. mtime within last 14 days
Plan failures:
  docs/plans/bad.md: missing 'Challenge 2' literal (two-pass challenge required)
```

**Implementation:** `hooks/tier-before-coder.sh`. See the "Grep-based enforcement: strengths and limits" section below for the spoofability caveat.

### 8. Post-rebase test verification before merge

**Status: REJECTED**

`merge_pull_request` operates on the remote via GitHub API. A local test suite tests
whatever is checked out locally, which may not match the PR branch state (especially
in worktree setups after rebases). This gives false confidence.

Additionally, between a local test pass and the `merge_pull_request` call, another PR
can merge to main, making results stale.

The correct enforcement point is **GitHub Actions CI** as a required status check.

### 9. No force-push

**Status: ACCEPTED** (identified during architect challenge)

| Field | Value |
|-------|-------|
| Hook type | `PreToolUse` on `mcp__git-tools__git_push` |
| Logic | Reject if push arguments contain `--force` or `-f` flags |
| Edge cases | Force-push is legitimate after interactive rebase on feature branches. Could allow force-push on non-main branches, or require explicit user confirmation |

**Implementation notes:**
- Can be combined with hook #2 (same tool, same hook script)
- Check for force-related flags in the tool input
- Block with message: "Force-push is blocked. If this is intentional (e.g., after rebase on a feature branch), ask the user to confirm."

---

## Grep-based enforcement: strengths and limits

PR B (2026-04-12) moved two items — "Two architect challenges" and "Correct team composition per tier" — from "Not Practical" into the enforced set by narrowing their scope. The hook does NOT prove that two challenge passes actually happened in the conversation or that the declared team will actually be spawned. It only verifies that the **plan file's declared state** matches the tier's rules.

**What this gives you:**
- Forgetfulness is caught. A PO who skips a challenge pass and forgets to write the second-pass section gets blocked.
- Shape-correct plans become the path of least resistance. Writing a fraudulent plan takes more keystrokes than writing a real one.
- Spoofing moves from passive to active. The current audit gate treats "missed it" and "faked it" as the same failure; the new gate requires the PO to deliberately invent `Challenge 1` / `Challenge 2` markers and a `Team:` line that never reflected reality.

**What this does NOT give you:**
- Proof that the challenges occurred. A PO who writes both `Challenge 1` and `Challenge 2` sections with no real critique passes.
- Proof that the team will be spawned. A plan can declare `Team: coder, code-reviewer, tester` and then spawn only a coder; the hook has no visibility into subsequent spawns.
- Cross-spawn state. The hook fires per `Agent` invocation; it cannot count fix cycles, merges, or reviewer round-trips.

Grep-based enforcement is a higher wall than pure convention, not a guarantee. Escalations from grep to true stateful enforcement are tracked under **Future Work → Workflow state tracking**.

---

## Not Practical for Hooks (current)

These conventions require conversation-level or cross-agent state tracking that hooks still cannot provide:

| Convention | Why hooks can't enforce it |
|---|---|
| Max 3 fix cycles per task | Requires counting review round-trips across agent lifetimes |
| Merge ordering (first-ready, first-merge) | Cross-workstream coordination with no single tool call to intercept |
| Proof that challenges actually occurred | Hook only sees the plan file, not the conversation history |
| Proof that the declared team was spawned | Hook fires per-spawn; no state across spawns |

These remain convention-only, enforced by AGENT_TEAM.md instructions.

---

## Summary

| # | Proposal | Status | Reason |
|---|----------|--------|--------|
| 1 | No Bash git | Already done | settings.json |
| 2 | No push to main | **Implemented** | `hooks/no-push-main.sh` |
| 3 | Format before commit | Reject | Wrong enforcement point, blocks workflows |
| 4 | Build before commit | Reject | Wrong enforcement point, blocks TDD |
| 5 | No `gh` CLI | Already done | settings.json |
| 6 | Plan before edit | Defer | Too fragile, marginal gain |
| 7 | Tier + two-challenge + team + freshness before coder spawns | **Implemented (PR B)** | `hooks/tier-before-coder.sh` — grep-based, see "strengths and limits" |
| 8 | Test before merge | Reject | Wrong architecture, use CI |
| 9 | No force-push | **Dropped** | `git_push` MCP tool has no `force` parameter; `Bash(git *)` already blocked |

---

## Future Work

The following enforcement ideas were evaluated and deferred. They require conversation-level state tracking that hooks cannot provide without additional infrastructure:

- **Workflow state tracking**: A persistent state file (e.g., `.claude/workflow-state.json`) maintained at key milestones (tier assignment, challenge completion, fix cycles). Challenge: convention-maintained state has a bootstrap problem — the AI that skips conventions also skips state updates. Needs a dedicated design pass for who writes state and how it's validated.
- **Commit-time workflow verification**: The `/commit` skill could read workflow state and warn if challenges were skipped or fix cycles exceeded. Depends on reliable state tracking above.
- **Sprint retrospective**: A `/retrospective` skill that reviews workflow compliance after each sprint and surfaces recurring violations. Would drive the self-improvement loop below.
- **Self-improving enforcement**: Auto-promote repeated convention violations to hook candidates. Pattern: retrospective identifies recurring skip → new hook proposed → implemented → convention becomes enforcement. Requires retrospective infrastructure first.
