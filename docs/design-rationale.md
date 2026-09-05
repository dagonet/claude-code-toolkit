# Design rationale — why the template files say what they say

The operative files (`CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`) carry
**facts and instructions only**. Every "why" lives here, keyed by file and
section, so an instruction can be short and its reasoning can still be found.
Check 35 in `scripts/verify-template-consistency.sh` enforces the byte budget
that makes this split necessary.

## Byte table — `templates/<variant>/CLAUDE.md`

Measured at `bf436dc` (before) and after the v3.1 diet (this commit):

| variant | before (bytes) | after (bytes) |
|---|---|---|
| general | 11,649 | 6,143 |
| dotnet | 11,899 | 6,140 |
| dotnet-maui | 11,938 | 6,139 |
| rust-tauri | 12,583 | 6,139 |
| java | 12,232 | 6,135 |
| python | 12,258 | 6,139 |

Budget: `BUDGET_CLAUDE_MD = 6144` (`scripts/verify-template-consistency.sh`).
For the non-`general` variants, language-specific overflow (agent-fallback
detail, build/test/debugging conventions, and — for `rust-tauri` — the
frontend build commands and directory overview) moved into the matching
`.claude/rules/*.md` file(s), which load only on a matching-path touch, not
every turn.

## CLAUDE.md

### Session Bootstrap

The step list keeps only the four load-on-demand triggers for `AGENT_TEAM.md`
as one line each. Cut to the rationale file:

- **Clause (d) history.** A load-on-demand doc is only as good as its trigger
  list: a reader who asked "which agents cannot commit?" once concluded the
  answer existed nowhere, while it sat in `AGENT_TEAM.md` under *CRITICAL:
  Sub-Agent Tool Limitations*. From outside, a missing trigger and a missing
  document are indistinguishable — hence clause (d) covers "editing a file
  naming an agent" broadly rather than listing specific files.
- **Why no line count is given for `AGENT_TEAM.md`'s size.** A figure in prose
  describing another file's shape goes stale the moment that file is edited,
  and nothing detects the drift — an earlier version of this line said
  "850+ lines" and was wrong for most of its life.
- **Open Brain staleness thresholds.** The specific numbers
  (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`,
  `compiled_at` older than 7 days) are implementation detail of the wiki
  layer's staleness heuristic, not something the PO needs to reason about
  turn-by-turn — the action ("fall back to `thoughts_search` if stale") is
  the operative instruction.

### Workflow TL;DR

Cut to the rationale file:

- **Why team size is a ceiling, not a target.** Sprint teams sized to the
  table's maximum by default over-allocate on the common case; the tiers
  describe the largest defensible team for a task shape, and the PO is
  expected to justify escalation upward, not restraint downward.
- **Why `Explore` is never re-spawned on a named file.** Spawning a
  read-only exploration agent for a path the PO or a prior agent has already
  identified duplicates work the assigned developer will do anyway when it
  reads the file — the redundant spawn costs a full agent turn for zero new
  information.
- **Why the write surface is enumerated.** `hooks/enforce-delegation.sh`
  enforces the code/build part of "PO never does hands-on work" mechanically;
  the explicit list of PO-writable paths exists so a PO reading the rule
  doesn't have to infer the boundary from the hook's regex.

### Superpowers Skills — MUST Invoke Before Responding

No cuts — check 3 greps the exact heading text, check 2 greps `superpowers:`,
and check 20 greps `karpathy-guidelines`; the section is short enough
(1,129 bytes) that it fits the post-diet budget unmodified in every variant.

### Working Preferences

Cut to the rationale file: the mechanism behind each enforced preference
(which hook enforces which rule, and how) — `hooks/pre-commit-test.sh`,
`hooks/run-gate.sh`, `hooks/gate-before-merge.sh`, `hooks/no-push-main.sh`,
and `hooks/read-size-gate.sh` collectively enforce read-before-edit,
tests-before-commit, never-push-main, the 500-line `Read` cap, and
delegation. The rule stays in `CLAUDE.md`; the hook names moved here because
which specific hook enforces which rule is diagnostic detail, not something
a session needs to re-derive every turn.

### Quick Start

The section now carries exactly one placeholder-free command
(`bash hooks/run-gate.sh`) plus a pointer to `PROJECT_CONTEXT.md` for the
underlying build/test/format/lint commands, and to `.claude/rules/*.md` for
language conventions. Every `{{BUILD_COMMAND}}`/`{{TEST_COMMAND}}`/
`{{FORMAT_COMMAND}}`/`{{LINT_COMMAND}}` placeholder — previously present in
`general`, `java`, and `python` (the latter two also carried a second,
duplicate placeholder block just above the PROJECT-CUSTOM region, which was
deleted outright as redundant cruft rather than moved) — is gone from every
variant's `CLAUDE.md`. Rationale: a placeholder that survives unresolved into
a real project's `CLAUDE.md` reads as a broken template, and the gate command
already resolves the underlying commands from `PROJECT_CONTEXT.md` without
the agent needing to see them inline.

### Build & Test Discipline / Debugging

No cuts beyond wording tightened for length. For the five non-`general`
variants, the variant-specific build/test and debugging clauses (e.g.
"Use `dotnet build` + `dotnet test`...", "trace paths through Repository →
Service → ViewModel...") moved into the matching `.claude/rules/*.md` file
under a new "Agent Routing and Build/Test Notes" section, because they are
consulted while editing matching files, not on every turn — the general
project-specific reminder stays inline and identical across all six variants.

### Verification

Cut to the rationale file:

- **Why "evidence before claims" instead of a longer explanation.** The
  original text listed the categories of instrument that answer the
  *adjacent* question (e.g. "a passing unit suite proves the suite passes,
  not that the baseline moved correctly") — that catalogue lives in the
  CHANGELOG's verification-instrument entries already; repeating it in
  `CLAUDE.md` duplicated it in the wrong file.
- **Why the PO reads `.gate/last-pass.json` instead of running anything.**
  The gate is dispatched to `ops` or the coder and its result is read, not
  reproduced — this is `hooks/enforce-delegation.sh`'s domain and is
  documented there, not restated per-rule in `CLAUDE.md`.

### Commit Workflow

Cut to the rationale file: the "keep momentum between implement -> commit ->
plan-next cycles" framing was aspirational color around the same instruction
("commit and push promptly, without excessive re-verification") — kept once,
not twice.

### Compact Instructions

Cut to the rationale file: the sub-bullet justifications ("why each chosen",
"and why the chosen fix addresses it") describing *why* each preserved
category matters. The categories themselves (decisions, bug root causes,
active work state, in-flight agent work, merge sequence) are fact-shaped
retention rules and stayed; the parenthetical reasoning for retaining them
is exactly the kind of "why" this file exists to hold.

### PROJECT-CUSTOM region

No cuts. The markers (`<!-- PROJECT-CUSTOM:BEGIN -->` / `<!-- PROJECT-CUSTOM:END -->`)
and the one line above the opening marker containing the literal
`context-mode` survive verbatim in every variant — check 26 pins both the
literal and its position, and the context-mode MCP server's own
`writeRoutingInstructions()` writer checks the file for that literal before
appending its own routing block. Both markers and the sentinel line are
removed together in a later, separate ownership-transfer commit per the
v3.1 plan — not here.

## AGENT_TEAM.md

(populated by Task 3)

## CLAUDE.local.md

(populated by Task 4)
