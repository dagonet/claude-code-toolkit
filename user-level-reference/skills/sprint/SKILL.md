---
name: sprint
description: Run a sprint backlog as parallel subagent workstreams with rebase-before-merge and gate enforcement. Triggers on /sprint.
disable-model-invocation: true
argument-hint: "[sprint plan file or backlog description]"
---

# Sprint

You are the Product Owner for this sprint. Execute the sprint backlog using parallel **subagents** — there are no named teammates and no progress channel.

> **Output style:** summary mode by default. The user must reply `show details` (or any paraphrase like *drill in*, *show me the code*) to switch to drill-in mode for file paths, line numbers, and code.

## Sprint Execution Workflow

### 1. Read the sprint plan

- Read the sprint plan or backlog provided by the user (`$ARGUMENTS`, a plan file under `docs/plans/`, or the backlog in context)
- Identify all work items and their dependencies
- Determine which workstreams can run in parallel

### 2. Create tracking items

- In `github-issues` mode: search for existing issues first to avoid duplicates, then create one issue per work item with clear acceptance criteria
- In `plan-files` mode: record the workstreams in the plan file instead

### 3. Dispatch parallel subagents

- **If the sprint is a single T4-sized task that is too big for one pass** (multi-module migration, a sweep across many files, competing hypotheses), say **"use a workflow"** first: Claude builds a script-orchestrated dynamic workflow — waves of implementers → two verifiers → a fixer per task — and runs it in the background under auto mode. Come back to this loop for the merge. Fan-out below is for a backlog of independent items.
- Max 3 parallel workstreams to avoid rate limits
- Each subagent gets a clear, self-contained scope and its own worktree
- Assign independent workstreams first; queue dependent ones
- Spawn long-running workstreams with `background: true` so the sprint loop is not blocked on a single Agent call

### 4. Per-workstream lifecycle

For each workstream:

1. The coder subagent implements the feature/fix in a worktree
2. It runs the gate (`bash hooks/run-gate.sh`, or the configured Build/Test/Format/Lint commands if `Gate:` is unset) — must pass
3. It opens a PR when green
4. A code-reviewer subagent reviews the PR
5. The coder fixes review findings, re-runs the gate, and reports

Each subagent reports in its **final message** — there is no progress channel, and you must not expect or request pings. A foreground Agent call cannot stall: it returns or it errors. For a `background: true` spawn, act on the task-completion notification; past the agent's tool-call budget with no completion, treat the run as failed and re-dispatch with a tighter brief rather than polling.

### 5. Merge sequence

- Before merging any PR, **rebase it onto the latest main**
- Re-run the gate after the rebase — the gate artifact must match the rebased HEAD
- Merge PRs **one at a time** in dependency order
- After each merge, verify main is green
- Never merge without a passing gate

### 6. Handle failures

- **Rate limit hit**: save full state (each workstream's status, branch name, next step) and notify the user
- **Gate failure after merge**: fix immediately on main before merging the next PR
- **Subagent returns without a deliverable**: treat the run as failed, re-dispatch with a tighter brief — do not retry the same prompt
- **Branch conflicts**: rebase and resolve; don't force-push shared branches

### 7. Finalize

- After all PRs merge, run the gate on main
- Update sprint state files and the Definition of Done
- Commit state updates
- Report a completion summary with per-workstream status

## Rules

- Max 3 parallel workstreams to avoid rate limits
- A workflow does not bypass the merge rules below — its branch rebases and gates like any other
- Rebase before every merge — never merge without rebasing
- Merge PRs sequentially, never in parallel
- A passing gate is required before any merge
- Subagents report only in their final message — never build the loop on progress pings
- If blocked, save full state and report — don't spin
