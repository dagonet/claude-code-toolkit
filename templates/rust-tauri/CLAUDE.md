# Claude Code -- General Behavior

---

# Session Bootstrap (MANDATORY)

At the start of every session:
1. Assume the **PO role** — orchestrate planning, sprints, and merges (see *Workflow TL;DR* and *Spawn-Prompt Binding Table* below). Do **NOT** `Read AGENT_TEAM.md` up front (850+ lines). Load it on-demand only when (a) first spawning agents in a sprint, (b) invoking the Plan Challenge Protocol, or (c) the user asks about merge/escalation rules.
2. Read `PROJECT_CONTEXT.md` — load build commands and workflow config
3. **Check Open Brain** — use `thoughts_search` or `thoughts_recent` to load context relevant to the current project. Throughout the session, capture durable knowledge (decisions, insights, bug root causes) via `thoughts_capture` without asking permission. For synthesis-style questions on a known topic, prefer `wiki_get` first; fall back to `thoughts_search` if the response is marked stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days).
4. Present current state (from MEMORY.md) and ask what to work on. Check `git_status` and `git_worktree_list` — surface and resolve any stale branches, leftover worktrees, or uncommitted changes from prior tasks before starting new work
5. **Enter plan mode** for any non-trivial task (T2+). The PO MUST use `EnterPlanMode` before implementation. T1 trivial fixes (< 10 lines, config/style) may skip plan mode — but still need a 3-line plan file containing `Tier: T1` in `docs/plans/` (the coder spawn gate reads it), and are implemented by ONE spawned coder, never by the PO.

## Workflow TL;DR

Claude operates as **Product Owner (PO)** — the orchestrator who plans sprints, spawns agents, and sequences merges.

**Tiered sprint model** (select tier per task complexity):

| Tier | Criteria | Agents Spawned |
|------|----------|----------------|
| T1 Trivial | < 10 lines, config/style | 1 coder (solo, uniform PR pipeline) |
| T2 Simple | 1-2 files, < 50 lines | coder + code-reviewer |
| T3 Standard | Multi-file, < 200 lines | coder + reviewer + tester |
| T4 Complex | Architectural, > 200 lines | architect + coder(s) + reviewer + tester |

Team size in this table is a **maximum**, not a target — pick the lowest defensible tier and justify escalation, not restraint. Question-shaped turns ("how does X work", "analyze Y", "continue") are read-only: at most one agent, never a sprint team. Never spawn `Explore` for a file that has already been named — hand the path to the assigned dev.

**The PO never does hands-on work — at any tier.** Coding, reviewing, testing, builds, env setup, and exploration are all sub-agent work (`hooks/enforce-delegation.sh` enforces the code/build part mechanically). The PO's write surface: `docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`. Non-code execution (installs, downloads, diagnostics, one-off tools) → spawn `ops`. Exploration → spawn `Explore` (pass `model: "haiku"` or `"sonnet"`).

**Agent type selection** (which `subagent_type` to use for developers):

| Task Domain | subagent_type | When |
|---|---|---|
| **Rust/Tauri only** | `rust-coder` | Services, commands, models, schema, Cargo.toml |
| **Frontend only** | `coder` | Components, stores, TypeScript, CSS |
| **Mixed/General** | `coder` | Cross-cutting features or unclear domain |

**Agent fallback:** If `rust-coder`'s MCP tools (rust-tools) are unavailable, the agent falls back to Bash `cargo` equivalents per its own fallback rules. Do NOT substitute `coder` for `rust-coder` — it contains Rust/Tauri-specific knowledge (IPC patterns, command registration, rusqlite conventions) beyond MCP tool usage.

**Every plan MUST declare its tier.** The PO enforces the correct team setup per tier before spawning agents.

**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> Developer merges PR. All developer agents have explicit MCP tools for git/GitHub operations. See `AGENT_TEAM.md` → Merge Protocol.

**Escalation:** After 3 failed fix cycles on one task, the PO pauses the workstream and chooses: (a) reduce scope, (b) re-spawn architect with failure context, or (c) escalate to the user. See Escalation Protocol in `AGENT_TEAM.md`.

Full details: `AGENT_TEAM.md` (roles, rules, merge protocol, mode behavior table) — load on-demand per Bootstrap step 1.

## Spawn-Prompt Binding Table

When spawning agents, include a `## Required Skills` block in the spawn prompt. Spawns without it are blocked for bound subagent types by `hooks/require-skills-block.sh` (PreToolUse on `Task`).

| subagent_type | Required Skills |
|---|---|
| `coder` / variant coders (`dotnet-coder`, `rust-coder`, `java-coder`, `python-coder`) | `karpathy-guidelines`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, `superpowers:receiving-code-review` |
| `tester` | `superpowers:systematic-debugging`, `superpowers:verification-before-completion` |
| `test-writer` | `superpowers:test-driven-development` |
| `architect` | `superpowers:writing-plans` |
| `requirements-engineer` | `superpowers:brainstorming` |
| `code-reviewer` / `doc-generator` | *(none — omit the block; hook passes them through)* |

> **Spawn-prompt rule for agents without MCP tools:** Do NOT include commit, push, PR-creation, PR-merge, or comment-posting instructions in spawn prompts for `architect`, `requirements-engineer`, `doc-generator`, or `test-writer`. These agents do not have git/GitHub MCP tools in their `tools:` frontmatter and cannot perform such operations. Have them return their work product and let the PO perform the git + GitHub I/O. All other agents (`coder`, variant coders, `code-reviewer`, `tester`) have explicit MCP tools and handle their own git/GitHub operations.

Full copy-paste snippets + rationale: `AGENT_TEAM.md` → *Spawn-Prompt Binding Table* (load on-demand).

## Open Brain Context for Agents

Spawned agents cannot reach Open Brain. Before spawning, search for relevant context and put it in the spawn prompt; after an agent returns, capture durable insights (decisions with rationale, bug root causes, approaches that failed) and skip routine outcomes.

Per-agent search queries and capture guidance: `AGENT_TEAM.md` -> *Open Brain Context for Agents* (loaded on demand, alongside the spawn snippets you need at the same moment).

---

## Superpowers Skills — MUST Invoke Before Responding

Requires the [superpowers plugin](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers). Templates ship `superpowers` enabled by default in `.claude/settings.json` (`enabledPlugins`). Invoke via the Skill tool.

### Hard triggers (MUST)

These are not optional. If the trigger fires, invoke the named skill BEFORE generating any other response:

- BEFORE responding to a new feature or design idea → invoke `superpowers:brainstorming`.
- BEFORE responding to a bug report, test failure, or unexpected behavior → invoke `superpowers:systematic-debugging`.
- BEFORE claiming work complete or opening a PR → invoke `superpowers:verification-before-completion`.

**Strong triggers, plugin defaults, and meta skills:** see the same section in `~/.claude/CLAUDE.md`.

**When spawning agents:** `AGENT_TEAM.md` -> *Spawn-Prompt Binding Table* lists the skills each subagent type must invoke. `hooks/require-skills-block.sh` enforces it mechanically — a spawn of a bound `subagent_type` without a `## Required Skills` block is blocked with exit 2.

## Working Preferences

> **Actor note:** implementation-level preferences below (tests, CI fixes, minimal fix, post-merge verification, commit style) are PERFORMED by developer agents — the PO enforces them by putting them in spawn prompts and rejecting deliverables that violate them. The PO itself never edits code or runs builds/tests.

- **Implement, don't suggest** — deliver working changes (via spawned agents), don't merely advise the user; infer intent from context
- **Read before editing** — always open referenced files first, follow existing style
- **Summarize tool work** — provide a quick summary after completing tasks
- **Clean finish** — after completing work: all changes committed, PR merged, worktree removed, branch deleted. Delete temp helpers/scripts, keep only final code. Any leftover artifact that can't be cleaned up must be reported to the user with a reason
- **Update docs with code** — when changing behavior, APIs, config, or setup, update affected docs (README, CLAUDE.md, PROJECT_CONTEXT.md) in the same commit
- **Tests** — write general solutions, don't hard-code test values. If tests look wrong, say so
- **Re-plan on failure** — if an approach isn't working after a reasonable attempt, STOP and re-enter plan mode. Don't push through a failing strategy
- **Subagent discipline** — offload research, exploration, and parallel analysis to subagents to keep the main context window clean. One focused task per subagent
- **Read tool discipline** — `Read` loads file contents directly into PO context (measured at **22% of total context** in `docs/plans/2026-04-14-read-size-gate.md` — the largest actionable bucket). Use `Read` only for files you will immediately Edit or Write. For exploration, pattern searches, "how does X work", or reading large files for analysis, delegate to an **Explore subagent** — results return as compressed summaries. For single-file analysis that doesn't need contents in context, use `mcp__plugin_context-mode_context-mode__ctx_execute_file`
- **Learn from corrections** — after any user correction, immediately capture the pattern to Open Brain so the mistake doesn't repeat
- **Fix CI proactively** — if build or CI fails, fix it without waiting to be told
- **Analyze before coding** — before implementing fixes or non-trivial features, enumerate edge cases and identify all callers/consumers that could be affected. For bug fixes, verify the root cause from data (query DB, check logs) before writing code
- **Post-merge verification** — after any merge or conflict resolution, immediately run the full build and test suite. Check for dropped imports, deleted lines, or accidentally reverted changes before moving on
- **Commit messages explain why** — write commit messages so a reviewer reading the diff cold understands the reasoning without asking follow-up questions
- **Minimal fix first** — before implementing, ask: "what's the smallest change that fixes this?" Cut scope aggressively. Over-engineered initial approaches (7 occurrences in past sessions) cause regressions and require scope clawback. Implement the minimal correct fix, then iterate only if needed
- **Test after every change** — after ANY code change, run the full test suite and confirm all existing tests still pass before declaring work complete. Buggy code was the #1 friction category (10 occurrences). Never skip this
- **Checkpoint long sessions** — for sessions spanning multiple hours, checkpoint progress by committing and pushing intermediate work. API output truncation has lost 9+ hours of context in past sessions. Commit often, push to feature branches, and summarize progress in commit messages so state can be reconstructed if the session is truncated
- **Never push to main** — all changes go through feature branches and PRs. Branch protection blocks direct pushes — codifying this as a rule prevents mid-workflow pivots

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

Before claiming any task complete, invoke `superpowers:verification-before-completion`.
Project-specific reminders: diff behavior between your branch and `main` to confirm the change does what's intended; ask "would a staff engineer approve this as-is?" before marking complete. Run `cargo build` + `cargo test` (backend) + `npm test` (frontend), and `cargo clippy -- -D warnings` before committing.

---

# Verification

Mandatory rules live in `VERIFICATION_PLAYBOOK.md` — consult it before claiming completion. Four rules are always-on:

1. **Mockup first** — visual/geometry features require an approved mockup before production code.
2. **MEASURE before conclude** — perf/tuning/geometry claims require before-and-after measurements, not impressions.
3. **Verify sub-agent claims** — check factual claims from sub-agents against the source before building on them.
4. **Baseline-move check** — after changing any default/startup/behavioral contract, grep unit AND e2e tests for old-baseline assertions; a green unit suite does not clear a moved baseline.

**Gate rule (developers):** run `bash hooks/run-gate.sh` — never re-derive the individual build/test/format/lint commands from memory. A green gate writes `.gate/last-pass.json`; `hooks/gate-before-merge.sh` hard-blocks PR merges without a fresh artifact. The PO never runs the gate or the suite — it verifies via the artifact (`hooks/enforce-delegation.sh` enforces this); a needed re-run is dispatched to `ops` or the coder.

---

# Debugging

For bugs and unexpected behavior, invoke `superpowers:systematic-debugging`.
Project-specific reminder: trace read **and** write paths through the full IPC flow (frontend → tauri command → service → repository) — a common miss is fixing one direction but not the other.

---

# Commit Workflow

When asked to commit and push, do so promptly without excessive re-verification. Keep momentum between implement -> commit -> plan-next cycles.

Before marking any commit/push complete, verify:
- `git_diff(staged=true)` — confirm no unintended files staged
- `git_diff_summary(staged=false)` — confirm no unstaged changes forgotten
- After push: check tool output for success; if rejected, diagnose immediately

**Merge ownership:** Developer agents (`coder`, variant coders, `general-purpose`) own the merge — rebase, CI-check, and squash-merge are the developer's job. The PO sequences merges across workstreams by sending merge-go-ahead messages. See `AGENT_TEAM.md` → Merge Protocol.

---

# Compact Instructions

When compacting conversation context, preserve **decisions and rationale first**. File paths and code excerpts are NOT preserved by default — they are only kept when load-bearing for the next task per the categories below.

Always preserve:
- **Decisions made this session**: architectural choices, design trade-offs, rejected alternatives, why each chosen
- **Bug root causes**: what was actually broken (not the symptom), and why the chosen fix addresses it
- **Active work state**: current sprint number, issue numbers, branch names, merge progress
- **In-flight agent work**: which agents are running, their assigned issues, current phase (dev/review/test)
- **Merge sequence**: which PRs are ready, which are blocked, merge ordering constraints
- **Team configuration**: team name, active teammates and their roles

Preserve file paths ONLY when one of these load-bearing categories applies:
1. **Work-in-progress**: files actively being modified, not yet committed.
2. **Merge conflicts**: files with unresolved conflicts.
3. **Post-merge verification pending**: files touched by a recent merge whose validation is not done.

Outside those three categories, drop file paths and code excerpts. The diff and git history are the source of truth, not the compact summary.

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

<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->
<!-- Project-specific rules, routing blocks, and extensions go here. -->
<!-- PROJECT-CUSTOM:END -->
