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
| **Rust/Tauri only** | `rust-coder` | Services, commands, models, schema, Cargo.toml |
| **Frontend only** | `coder` | Components, stores, TypeScript, CSS |
| **Mixed/General** | `coder` | Cross-cutting features or unclear domain |

**Agent fallback:** If `rust-coder`'s MCP tools (rust-tools) are unavailable, the agent falls back to Bash `cargo` equivalents per its own fallback rules. Do NOT substitute `coder` for `rust-coder` — it contains Rust/Tauri-specific knowledge (IPC patterns, command registration, rusqlite conventions) beyond MCP tool usage.

**Every plan MUST declare its tier.** The PO enforces the correct team setup per tier before spawning agents.

**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> Developer merges PR

**Escalation:** After 3 failed fix cycles on one task, the PO pauses the workstream and chooses: (a) reduce scope, (b) re-spawn architect with failure context, or (c) escalate to the user. See Escalation Protocol in `AGENT_TEAM.md`.

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
- **Read tool discipline** — `Read` loads file contents directly into PO context (measured at **22% of total context** in `docs/plans/2026-04-14-context-baseline.md` — the largest actionable bucket). Use `Read` only for files you will immediately Edit or Write. For exploration, pattern searches, "how does X work", or reading large files for analysis, delegate to an **Explore subagent** — results return as compressed summaries. For single-file analysis that doesn't need contents in context, use `mcp__plugin_context-mode_context-mode__ctx_execute_file`
- **Learn from corrections** — after any user correction, immediately capture the pattern to Open Brain so the mistake doesn't repeat
- **Fix CI proactively** — if build or CI fails, fix it without waiting to be told
- **Analyze before coding** — before implementing fixes or non-trivial features, enumerate edge cases and identify all callers/consumers that could be affected. For bug fixes, verify the root cause from data (query DB, check logs) before writing code
- **Post-merge verification** — after any merge or conflict resolution, immediately run the full build and test suite. Check for dropped imports, deleted lines, or accidentally reverted changes before moving on

---

## Quick Start

```bash
npm install                    # Install frontend deps
npm run dev                    # Vite dev server
npm run tauri dev              # Full Tauri app (Rust + frontend)
npm test                       # Frontend tests
npm run test:rust              # cargo test (backend)
npm run lint:all               # All linting
npm run format                 # All formatting
```

## Directory Overview

```
src/                           # Frontend (TypeScript)
src-tauri/src/                 # Rust backend
e2e/                           # E2E tests
docs/plans/                    # Design docs + sprint plans
```

---

# Code Style (MANDATORY)

This repository uses `rustfmt.toml` (Rust) and `.prettierrc` (TypeScript) at the repository root.

All Rust code MUST:
- pass `cargo fmt --check` without changes
- pass `cargo clippy -- -D warnings` without warnings
- follow `rustfmt.toml` settings exactly

All TypeScript/CSS code MUST:
- pass `npm run format -- --check` (Prettier) without changes
- pass `npm run lint` without errors

Claude agents MUST NOT:
- reformat code that already complies
- introduce alternative styles or override formatter preferences
- suppress clippy warnings without justification

If generated code would violate formatting rules,
the code MUST be rewritten until it complies.

---

## Enforcement Notes

- `rustfmt.toml` and `.prettierrc` are committed and authoritative
- Run `cargo fmt` and `npm run format` before committing
- Treat clippy warnings as errors (`-D warnings`)
- Naming conventions: `snake_case` for Rust, `camelCase` for TypeScript

---

# Build & Test Discipline

After ANY code change, always run `cargo build` and `cargo test` (backend) and `npm test` (frontend) to verify everything passes before considering the task complete. Never assume a change is correct without build verification. Run `cargo clippy -- -D warnings` before committing.

When verifying non-trivial changes, diff behavior between main and your branch to confirm the change does what's intended. Before marking any task complete, ask: "Would a staff engineer approve this as-is?"

---

# Debugging

## Fix Strategy: Trace the Full Data Flow
When fixing bugs, trace the ENTIRE data flow (input -> processing -> storage -> retrieval -> display) before implementing a fix. Do not fix only the first issue found -- check all layers. Common miss: fixing the read path but not the write path, or vice versa.

## Multi-Round Bug Fixes
If the user reports a fix didn't work, DO NOT make another minimal patch. Instead:
1. Re-read all relevant files end-to-end
2. Add diagnostic logging if needed
3. Identify ALL places the data flows through
4. Fix comprehensively in one shot
Avoid incremental guess-and-check fixes.

---

# Plan Challenge Protocol

Every T3+ plan MUST be challenged **twice by the Architect agent** before execution. T1 and T2 tasks are exempt — they go straight to implementation. Plan mode is still required for T2+; only the two-pass architect challenge is lifted.

Full protocol details: `AGENT_TEAM.md` → Plan Challenge Protocol section.

No plan ships without a tier. T3+ plans ship challenged twice.

---

# Commit Workflow

When asked to commit and push, do so promptly without excessive re-verification. Keep momentum between implement -> commit -> plan-next cycles.

Before marking any commit/push complete, verify:
- `git_diff(staged=true)` — confirm no unintended files staged
- `git_diff_summary(staged=false)` — confirm no unstaged changes forgotten
- After push: check tool output for success; if rejected, diagnose immediately

**Merge ownership:** the developer who implemented the task owns the merge — rebase, CI-check, and squash-merge are the developer's job, not the PO's. The PO sequences merges across workstreams but does not merge on behalf of coders. See `AGENT_TEAM.md` → Merge Protocol.

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

# Rust / Tauri Specific

## Backend (Rust)

- Use `cargo test` to run Rust tests, `cargo clippy` for lints, `cargo fmt` for formatting
- Use `impl` blocks in service files (e.g., `*_service.rs`) for business logic
- IPC commands go in `commands.rs` as thin wrappers calling service methods
- Register all commands in `lib.rs`
- Use structured logging via the `log` crate
- Prefer `rusqlite` with `params![]` macro for SQL queries (not string interpolation)

## Frontend (TypeScript/SolidJS)

- Wrap all Tauri IPC calls in typed functions in `src/lib/tauri-api.ts`
- Use `vi.mock("../lib/tauri-api")` pattern in tests to isolate components from Tauri IPC
- Tauri IPC only works in native window -- "Loading..." is expected in browser preview
- Use `npm test` for frontend tests (Vitest + @solidjs/testing-library)
