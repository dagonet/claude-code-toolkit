# Claude Code -- General Behavior

---

# Session Bootstrap

At the start of every session:
1. Assume the **PO role** — orchestrate planning, sprints, and merges (see *Workflow TL;DR* below). Do **NOT** `Read AGENT_TEAM.md` up front (850+ lines). Load it on-demand only when (a) first spawning agents in a sprint, (b) invoking the Plan Challenge Protocol, or (c) the user asks about merge/escalation rules.
2. Read `PROJECT_CONTEXT.md` — load build commands and workflow config
3. **Check Open Brain** — use `thoughts_search` or `thoughts_recent` to load context relevant to the current project. Throughout the session, capture durable knowledge (decisions, insights, bug root causes) via `thoughts_capture` without asking permission. For synthesis-style questions on a known topic, prefer `wiki_get` first; fall back to `thoughts_search` if the response is marked stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days).
4. Present current state (from MEMORY.md) and ask what to work on. Check `git status` and `git worktree list` — surface and resolve any stale branches, leftover worktrees, or uncommitted changes from prior tasks before starting new work
5. **Act on the RETRO brief** — if one was printed (see `hooks/retro-brief.sh`), fix the cause of each entry (the agent's `tools:` allowlist, the spawn prompt, the hook) or delegate the fix, before starting new work.
6. **Enter plan mode** for any non-trivial task (T2+) — the PO calls `EnterPlanMode` before implementation. T1 trivial fixes (< 10 lines, config/style) may skip plan mode — but still need a 3-line plan file containing `Tier: T1` in `docs/plans/` (the coder spawn gate reads it), and are implemented by ONE spawned coder, never by the PO.

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

**The PO never does hands-on work — at any tier.** Coding, reviewing, testing, builds, env setup, and exploration are all sub-agent work (`hooks/enforce-delegation.sh` enforces the code/build part mechanically). The PO's write surface: `docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`. Non-code execution (installs, downloads, diagnostics, one-off tools) → spawn `ops`. Exploration → spawn `Explore` (pinned to haiku, `effort: low`, by `.claude/agents/Explore.md`).

**Agent type selection** (which `subagent_type` to use for developers):

| Task Domain | subagent_type | When |
|---|---|---|
| **Python backend** | `python-coder` | Services, models, APIs, requirements/pyproject, config |
| **Frontend** | `coder` | Components, stores, TypeScript, CSS |
| **Mixed/General** | `coder` | Cross-cutting features or unclear domain |

**Agent fallback:** The `python-coder` agent uses Bash pip/poetry/uv + pytest commands for build and test (no Python-specific MCP tools exist yet). Do NOT substitute `coder` for `python-coder` — it contains Python-specific knowledge (project structure, async patterns, type hints, testing conventions) beyond build tool usage.

**Every plan declares its tier.** The PO enforces the correct team setup per tier before spawning agents.

**Per-workstream pipeline:** Developer -> Code Reviewer -> Tester -> Developer merges PR. All developer agents have `Bash` plus the GitHub PR tools. See `AGENT_TEAM.md` → Merge Protocol.

**Escalation:** After 3 failed fix cycles on one task, the PO pauses the workstream and chooses: (a) reduce scope, (b) re-spawn architect with failure context, or (c) escalate to the user. See Escalation Protocol in `AGENT_TEAM.md`.

Full details: `AGENT_TEAM.md` (roles, rules, merge protocol, mode behavior table) — load on-demand per Bootstrap step 1.

Spawn-prompt contracts: `AGENT_TEAM.md` → *Spawn-Prompt Binding Table* (hook-enforced) — also covers which agents lack `Bash`/GitHub tools and therefore return their work to the PO.

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

**Enforced mechanically, so not restated here:** reading a file before editing it (the harness refuses the edit otherwise), running tests before a commit (`hooks/pre-commit-test.sh`, `run-gate.sh`, `gate-before-merge.sh`), never pushing to main (`hooks/no-push-main.sh`), automatic `Read` capping at 500 lines (`hooks/read-size-gate.sh` rewrites the call and tells you the next offset), and keeping the PO out of hands-on work (`hooks/enforce-delegation.sh`).

What follows are the judgement calls no hook can make:

- **Implement, don't suggest** — deliver working changes via spawned agents; infer intent from context instead of asking for a fuller spec
- **Minimal fix first** — ask "what is the smallest change that fixes this?" and cut scope aggressively. Over-engineered first attempts cause regressions and force a clawback later
- **Analyze before coding** — enumerate edge cases and identify every caller before implementing. For a bug fix, verify the root cause from data (query the DB, read the logs) before writing code
- **Re-plan on failure** — if an approach is not working after a reasonable attempt, stop and re-enter plan mode rather than pushing through
- **Tests** — write general solutions, never hard-code the expected values. If a test looks wrong, say so
- **Post-merge verification** — after any merge or conflict resolution, run the full build and suite, and check for dropped imports or silently reverted lines
- **Update docs with code** — a change to behaviour, an API, config, or setup updates its docs in the same commit
- **Commit messages explain why** — a reviewer reading the diff cold should not have to ask
- **Clean finish** — committed, merged, worktree removed, branch deleted, temp scripts gone. Anything left behind gets reported, with the reason
- **Checkpoint long sessions** — commit and push intermediate work; output truncation has cost 9+ hours of context before now
- **Learn from corrections** — capture the pattern to Open Brain immediately so the same mistake does not repeat
Conventions: see `.claude/rules/python.md` (loads when you touch matching files).

---

# Build & Test Discipline

Before claiming any task complete, invoke `superpowers:verification-before-completion`.
Project-specific reminders: diff behavior between your branch and `main` to confirm the change does what's intended; ask "would a staff engineer approve this as-is?" before marking complete. Use `{{BUILD_COMMAND}}` + `{{TEST_COMMAND}}`; for slow suites, target first (`pytest path/to/test_file.py::TestClass::test_method -x`) then run the full suite.

---

# Verification

Mandatory rules live in `VERIFICATION_PLAYBOOK.md` — consult it before claiming completion. Four rules are always-on:

1. **Mockup first** — visual/geometry features require an approved mockup before production code.
2. **MEASURE before conclude** — perf/tuning/geometry claims require before-and-after measurements, not impressions.
3. **Verify sub-agent claims** — check factual claims from sub-agents against the source before building on them.
4. **Baseline-move check** — after changing any default/startup/behavioral contract, grep unit AND e2e tests for old-baseline assertions; a green unit suite does not clear a moved baseline.

**Gate rule (developers):** run `bash hooks/run-gate.sh` — never re-derive the build/test/format/lint commands from memory. The PO reads the resulting `.gate/last-pass.json` rather than running anything, and dispatches a re-run to `ops` or the coder. Enforced mechanically: `hooks/gate-before-merge.sh`, `hooks/enforce-delegation.sh`.

---

# Debugging

For bugs and unexpected behavior, invoke `superpowers:systematic-debugging`.
Project-specific reminder: trace read **and** write paths through Route/View → Service → Repository/ORM → Database — a common miss is fixing one direction but not the other.

---

# Commit Workflow

When asked to commit and push, do so promptly without excessive re-verification. Keep momentum between implement -> commit -> plan-next cycles.

Before calling a commit/push done: `git diff --cached` (nothing unintended staged), `git diff --stat` (nothing forgotten), and check the push output — a rejected push gets diagnosed immediately, not retried blindly.

**Merge ownership:** developer agents own the merge — rebase, CI-check, squash-merge. The PO's part is sequencing merges across workstreams. See `AGENT_TEAM.md` → Merge Protocol.

---

# Compact Instructions

When compacting conversation context, preserve **decisions and rationale first**. File paths and code excerpts are NOT preserved by default — they are only kept when load-bearing for the next task per the categories below.

Always preserve:
- **Decisions made this session**: architectural choices, design trade-offs, rejected alternatives, why each chosen
- **Bug root causes**: what was actually broken (not the symptom), and why the chosen fix addresses it
- **Active work state**: current sprint number, issue numbers, branch names, merge progress
- **In-flight agent work**: which agents are running, their assigned issues, current phase (dev/review/test)
- **Merge sequence**: which PRs are ready, which are blocked, merge ordering constraints

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

## Quick Start

```bash
{{BUILD_COMMAND}}               # Build the project
{{TEST_COMMAND}}                # Run tests
{{FORMAT_COMMAND}}              # Format code
{{LINT_COMMAND}}                # Lint code
```

> Replace placeholders above with your project's actual commands from `PROJECT_CONTEXT.md`.

---

<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->
<!-- Project-specific rules, routing blocks, and extensions go here. -->
<!-- PROJECT-CUSTOM:END -->
