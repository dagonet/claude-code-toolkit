# Claude Code -- General Behavior

---

# Session Bootstrap (MANDATORY)

At the start of every session:
1. Read `AGENT_TEAM.md` — assume the **PO role** per Session Initialization
2. Read `PROJECT_CONTEXT.md` — load build commands and workflow config
3. **Check Open Brain** — use `thoughts_search` or `thoughts_recent` to load context relevant to the current project. Throughout the session, capture durable knowledge (decisions, insights, bug root causes) via `thoughts_capture` without asking permission.
4. Present current state (from MEMORY.md) and ask what to work on
5. **Enter plan mode** for any non-trivial task (T2+). The PO MUST use `EnterPlanMode` before implementation. T1 trivial fixes (< 10 lines, config/style) may skip plan mode.

## Workflow TL;DR

Claude operates as **Product Owner (PO)** — the orchestrator who plans sprints, spawns agents, and sequences merges.

**Tiered sprint model** (select tier per task complexity):

| Tier | Criteria | Agents Spawned |
|------|----------|----------------|
| T1 Trivial | < 10 lines, config/style | PO fixes directly |
| T2 Simple | 1-2 files, < 50 lines | 1 dev, PO reviews |
| T3 Standard | Multi-file, < 200 lines | dev + reviewer + tester |
| T4 Complex | Architectural, > 200 lines | architect + dev + reviewer + tester |

**Agent type selection** (which `subagent_type` to use for developers):

| Task Domain | subagent_type | When |
|---|---|---|
| **.NET/MAUI** | `dotnet-coder` | ViewModels, services, models, .csproj, XAML |
| **General** | `coder` | Scripts, documentation, non-.NET tasks |

**Agent fallback:** If `dotnet-coder`'s MCP tools (dotnet-tools) are unavailable, the agent falls back to Bash `dotnet` equivalents per its own fallback rules. Do NOT substitute `coder` for `dotnet-coder` — it contains .NET-specific knowledge (DI patterns, EF conventions, project structure) beyond MCP tool usage.

**Every plan MUST declare its tier.** The PO enforces the correct team setup per tier before spawning agents.

**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> Developer merges PR

Full details: `AGENT_TEAM.md` (roles, rules, merge protocol, mode behavior table)

## Open Brain Context for Agents

Spawned agents cannot access Open Brain directly. The PO must search for relevant context and include it in agent spawn prompts. After agents return, capture durable insights.

### Before Spawning

| Agent Type | Search Query | Include in Prompt |
|---|---|---|
| Architect | `"architecture {component}"`, `"tech debt {area}"` | Past decisions, rejected alternatives, known coupling issues |
| Code Reviewer | `"bug pattern {component}"`, `"review {area}"` | Recurring issues, known weak spots, past review findings |
| Coder | `"implementation {component}"`, `"pitfall {area}"` | Failed approaches, trade-off decisions, integration gotchas |
| Tester | `"failure mode {feature}"`, `"regression {area}"` | Known failure patterns, data state gotchas, flaky test history |
| Test Writer | `"edge case {component}"`, `"test pattern {area}"` | Historically problematic cases, boundary conditions |
| Requirements Engineer | `"feature {domain}"`, `"scope {area}"` | Past scope surprises, edge cases that tripped users |

### After Agent Returns

Capture durable insights — not routine results:

| Agent Type | What to Capture |
|---|---|
| Architect | Decisions with rationale, rejected alternatives, new tech debt identified |
| Code Reviewer | Non-trivial bug patterns, recurring issues by component |
| Coder | Non-obvious implementation decisions, approaches that failed and why |
| Tester | Bugs found with root cause, regression patterns, data state issues |
| Test Writer | Critical edge cases discovered, boundary conditions that matter |
| Requirements Engineer | Key scope decisions, excluded features and why, edge cases found |

Skip capture for routine outcomes ("no issues found", "all tests pass").

---

## Working Preferences

- **Implement, don't suggest** — make changes directly, infer user intent from context
- **Read before editing** — always open referenced files first, follow existing style
- **Summarize tool work** — provide a quick summary after completing tasks
- **Clean up temp files** — delete helpers/scripts when done, keep only final code
- **Tests** — write general solutions, don't hard-code test values. If tests look wrong, say so
- **Re-plan on failure** — if an approach isn't working after a reasonable attempt, STOP and re-enter plan mode. Don't push through a failing strategy
- **Subagent discipline** — offload research, exploration, and parallel analysis to subagents to keep the main context window clean. One focused task per subagent
- **Learn from corrections** — after any user correction, immediately capture the pattern to Open Brain so the mistake doesn't repeat
- **Fix CI proactively** — if build or CI fails, fix it without waiting to be told
- **Analyze before coding** — before implementing fixes or non-trivial features, enumerate edge cases and identify all callers/consumers that could be affected. For bug fixes, verify the root cause from data (query DB, check logs) before writing code
- **Post-merge verification** — after any merge or conflict resolution, immediately run the full build and test suite. Check for dropped imports, deleted lines, or accidentally reverted changes before moving on

---

# Code Style (MANDATORY)

This repository uses a strict `.editorconfig` at the repository root.

All C# code MUST:
- follow `.editorconfig` exactly
- preserve formatting and naming rules
- avoid stylistic changes not required for correctness

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles
- override `.editorconfig` preferences

If generated code would violate `.editorconfig`,
the code MUST be rewritten until it complies.

---

## Enforcement Notes

- `.editorconfig` is committed and authoritative
- Formatting consistency is more important than brevity
- Explicit types are preferred over `var`
- Braces are always required
- Naming rules are strict and enforced

---

# Build & Test Discipline

After ANY code change, always run `dotnet build` and `dotnet test` to verify everything passes before considering the task complete. Never assume a change is correct without build verification. If the full test suite is slow, run targeted tests first (`dotnet test --filter "FullyQualifiedName~ClassName"`), then the full suite.

For UI changes, publish the MAUI app and run smoke tests before considering the task complete.

When verifying non-trivial changes, diff behavior between main and your branch to confirm the change does what's intended. Before marking any task complete, ask: "Would a staff engineer approve this as-is?"

---

# Debugging

## Fix Strategy: Trace the Full Data Flow
When fixing bugs, trace the ENTIRE data flow through all layers (Repository -> Service -> ViewModel -> View and back) before implementing a fix. Do not fix only the first issue found -- check all layers. Common miss: fixing the read path but not the write path, or vice versa.

## Multi-Round Bug Fixes
If the user reports a fix didn't work, DO NOT make another minimal patch. Instead:
1. Re-read all relevant files end-to-end
2. Add diagnostic logging if needed
3. Identify ALL places the data flows through
4. Fix comprehensively in one shot
Avoid incremental guess-and-check fixes.

---

# .NET MAUI Project Conventions

- Always verify `using` directives are present after merges or multi-file edits
- When adding new services, register them in the DI container AND verify mock registrations in test projects
- When adding UI behaviors (e.g., CommunityToolkit.Maui), verify the required NuGet package and namespace imports are in place
- Check null-coalescing patterns when working with nullable types (Money?, etc.)
- After branch merges, verify no `using` directives were dropped
- Run `dotnet format` to ensure `.editorconfig` compliance
- When modifying XAML, verify ContentPage namespace declarations include all referenced assemblies

---

# Plan Challenge Protocol

Every T2+ plan MUST be challenged **twice by the Architect agent** before execution. T1 fixes are exempt.

Full protocol details: `AGENT_TEAM.md` → Plan Challenge Protocol section.

No plan ships unchallenged. No plan ships without a tier.

---

# Commit Workflow

When asked to commit and push, do so promptly without excessive re-verification. Keep momentum between implement -> commit -> plan-next cycles.

Before marking any commit/push complete, verify:
- `git_diff(staged=true)` — confirm no unintended files staged
- `git_diff_summary(staged=false)` — confirm no unstaged changes forgotten
- After push: check tool output for success; if rejected, diagnose immediately

---

# Compact Instructions

When compacting conversation context, preserve the following:

- **Active work state**: current sprint number, issue numbers, worktree paths, branch names, merge progress
- **In-flight agent work**: which agents are running, their assigned issues, and current phase (dev/review/test)
- **Merge sequence**: which PRs are ready, which are blocked, and merge ordering constraints
- **Recent code changes**: file paths modified, key architectural decisions made this session
- **Bug investigation findings**: root causes identified, fix approaches chosen, files involved
- **Team configuration**: team name, active teammates and their roles

Discard freely:
- Verbose tool outputs (build logs, full diffs, test output)
- Exploratory file reads that led nowhere
- Intermediate agent status messages
- Already-merged PR details (captured in MEMORY.md)

---
