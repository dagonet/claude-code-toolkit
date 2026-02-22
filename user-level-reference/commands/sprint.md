---
name: sprint
description: /sprint - Execute a Sprint with Parallel Agent Workstreams
---

You are the Product Owner and Scrum Master for this sprint. Execute the sprint backlog using parallel dev agents with resilient orchestration.

## Sprint Execution Workflow

### 1. Read Sprint Plan
- Read the sprint plan or backlog provided by the user
- Identify all work items and their dependencies
- Determine which workstreams can run in parallel

### 2. Create GitHub Issues
- Search for existing issues first to avoid duplicates
- Create issues for each work item with clear acceptance criteria
- Label and assign appropriately

### 3. Spawn Parallel Dev Agents
- Max 3 parallel workstreams to avoid rate limits
- Each agent gets a clear, self-contained scope
- Assign independent workstreams first; queue dependent ones

### 4. Per-Workstream Lifecycle
For each workstream:
1. Dev agent implements the feature/fix in a worktree
2. Run `dotnet build` (or project build command) — must pass
3. Run full test suite — must pass
4. Create PR when green
5. Code review the PR
6. Fix any review findings, rebuild, retest

### 5. Merge Sequence
- Before merging any PR, **rebase it onto the latest main**
- Merge PRs **one at a time** in dependency order
- After each merge, verify main builds clean
- Never merge without a green build

### 6. Handle Failures
- **Rate limit hit**: Save full state (each workstream's status, branch name, next step) and notify user
- **Build failure after merge**: Fix immediately on main before merging next PR
- **Agent idle >2 cycles**: Shut it down and note the gap
- **Branch conflicts**: Rebase and resolve, don't force-push

### 7. Finalize
- After all PRs merge, run the full test suite on main
- Update sprint state files and Definition of Done
- Commit state updates
- Report completion summary with per-workstream status

## Rules

- Max 3 parallel workstreams to avoid rate limits
- Rebase before every merge — never merge without rebasing
- Merge PRs sequentially, never in parallel
- Green build required before any merge
- If blocked, save full state and report — don't spin
