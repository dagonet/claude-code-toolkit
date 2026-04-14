# Workflow Meta Issues — Context Bloat & Over-Engineering

**Date:** 2026-04-13
**Status:** Discussion note — to be continued next session
**Not a tier/plan:** This is a captured conversation for future triage, not an implementation plan.

## Issue #1 — PO context should not rise above 50%

The PO role (main-session Claude) is structurally context-heavy because it reads plans, writes plans, runs challenges, mediates Open Brain, and holds CLAUDE.md + AGENT_TEAM.md + PROJECT_CONTEXT.md + skill text + tool output. Most context is produced *by* the PO, not by subagents.

**Three levers, ranked by payoff:**

1. **Enable `context-mode` MCP for tool output.** The SessionStart hook already nags about this — it's the single biggest lever. Raw `git` / `find` / `grep` / log output stays in a sandbox; the PO queries it via `ctx_search` / `ctx_execute` instead of loading it into the conversation window. Directly addresses the "big tool result" failure mode.
2. **Push reads into Explore subagents, not just during plan mode.** Any "find all X and summarize" task should be delegated even during implementation. Subagent results return compressed — a single paragraph summary instead of 10 file reads.
3. **Stop invoking skills inside the PO** when the rule is already encoded in CLAUDE.md memory. The spawn-prompt binding pattern (name the skills in the spawn prompt, let the subagent invoke them) is cheaper than the PO running `verification-before-completion` itself. The PO should cite rules from memory, not re-load skill text.

**Secondary levers** (smaller payoff, worth noting):
- Plan files as external memory — reading a plan back costs less than re-deriving it.
- Don't re-read CLAUDE.md / AGENT_TEAM.md mid-session — read once at bootstrap, refer from memory.
- Auto-compact is a symptom, not a fix — reduce production, don't rely on compression.

## Issue #2 — Is the workflow over-engineered?

**Honest read: yes, partially.** The elaboration is scar tissue from real failures — each hook and rule exists because a specific skip happened — but three specific items are probably negative-value at current scale:

1. **Two-pass challenge for T1/T2.** Trivial work doesn't need architect review. Restrict the Plan Challenge Protocol to T3+ and let T1/T2 go straight to implementation. Saves PO context on every small task.
2. **Grep-based hook enforcement (PR B, `tier-before-coder.sh`).** Catches forgetfulness but any *intentional* skip writes a fake plan file. The hook doesn't prove events occurred, only that the plan file's shape is right. This puts us in an awkward middle: not convention, not real state tracking. Pick one — either trust convention (remove the hook) or build real stateful tracking (`.claude/workflow-state.json` with lifecycle updates). The grep layer is enforcement theater against a determined skipper.
3. **PR B's freshness + team-line + double-challenge-literal gate.** Just built 2026-04-12. **Let it run for a sprint before deciding if it's load-bearing.** Don't remove yet — this item is flagged for empirical review, not immediate removal.

**The simplification test**: for each rule in AGENT_TEAM.md and each hook, ask *what did this catch in the last 5 sprints?* Rules that never fired are candidates for removal. Rules that fired once but the failure was harmless are candidates for relaxation. Rules that fired and caught real issues stay.

**What NOT to remove** (still load-bearing):
- The tier model itself (T1-T4). Granularity is useful for scoping; the bucketing decision is separate from the hook enforcement question.
- `no-push-main.sh`. One-line hook, zero friction, catches a destructive mistake.
- The Merge Protocol (squash, rebase-before-merge, developer-owns-merge). Cross-workstream coordination still needs rules.
- Open Brain context mediation. PO is the only place this can live.

## Proposed next-session actions

1. **Turn on `context-mode` MCP** (if not already) and measure PO context-% drop on a representative task.
2. **Audit rule usage.** Go through AGENT_TEAM.md sprint-by-sprint for the last 3-5 sprints and tag each rule as fired / never-fired / fired-harmlessly. This is the input to decision #2.
3. **Decide on the grep-hook question.** Either commit to real stateful tracking (bigger project) or back out `tier-before-coder.sh` to pure convention. Don't stay in the middle.
4. **Drop two-pass challenge requirement for T1/T2.** Low-risk, immediate PO context savings on small work.
5. **Revisit in one sprint** whether PR B's tightened hook was load-bearing or theater.

## Deferred — not in this note

- Any actual edits to hooks, CLAUDE.md, AGENT_TEAM.md, or plan files. This is a discussion note only; the user wants to continue next session before acting.
- PR C (W13/W14 MCP expansion). Still scoped in prior session summary; unchanged.
- W3-W7, W11 deferred items from the workflow audit. Unchanged.

## Source

Captured from a meta-discussion at the end of the 2026-04-13 session, immediately after PR A + PR B merged. User asked both questions directly; this note preserves the analysis so the next session can act on it instead of re-deriving it.

---

# Addendum — Context Bloat Measurement Pass (Design Spec)

**Date:** 2026-04-13 (same session, after brainstorming + two-pass challenge)
**Status:** Design approved. Script implementation pending.

## Why this exists

Issue #1 above lists three "levers ranked by payoff" but the ranking is guessed, not measured. Before intervening (enabling `context-mode`, pushing reads to subagents, or restructuring skill invocation), measure first. This section specifies a one-off measurement pass: a Python script that parses existing Claude Code session JSONLs, buckets bytes by source, and produces a markdown report.

Decision gates taken during brainstorming:
- **Measure first** (not ship-a-fix-first).
- **Retroactive** — parse existing JSONL, not instrument new sessions.
- **Default to claude-code-toolkit sessions** (overridable to all projects via CLI flag) — mixing workflows from unrelated projects dilutes signal.
- **Medium-grained buckets** (6), attributed per content block, not per message.
- **Committed script** in `tools/`, committed baseline snapshot in `docs/plans/`.
- **Data-only report**, no auto-generated intervention recommendations (those drift and editorialize).

## Inputs

- Glob: `%USERPROFILE%/.claude/projects/*/*.jsonl`
- Filter:
  - File path contains `claude-code-toolkit` (overridable via `--project-filter`; pass empty string to include all projects)
  - Size ≥ 500 KB
  - mtime within 30 days
- Take top 10 by file size (overridable via `--top-n`).

Size-based sorting (not message count) because a few huge messages is the exact failure mode being hunted.

## Buckets (6, with precedence)

Attribution is **per content block**, not per message. One assistant message containing text + a tool_use block contributes to two buckets.

| Bucket | Detection rule |
|---|---|
| `claude_md` | `tool_result` block linked (via `tool_use_id`) to a `Read` tool_use whose `file_path` ends with `claude.md` (case-insensitive — Windows FS is case-insensitive) |
| `agent_team_md` | same, but `file_path` ends with `agent_team.md` (case-insensitive) |
| `skill_content` | content block matches any of: contains literal `"Base directory for this skill"`, OR contains `---\nname:` frontmatter inside a `<system-reminder>` wrapper, OR is a tool_result from the `Skill` tool |
| `subagent_result` | `tool_result` linked to an `Agent` tool_use. **Rollup**: includes every tool use, text, and thinking the subagent produced internally — only the final message bubbles up to the parent session. Bucket size reflects the total work the subagent did, not just its summary. |
| `tool_result:<name>` | all other `tool_result` blocks, keyed by the originating tool_use name (Bash, Read, Grep, Glob, Write, Edit, `mcp__*`, etc.) |
| `assistant` | assistant-authored text blocks AND tool_use blocks (the JSON of outgoing tool calls) |

User messages and system-reminder content fold into the relevant surrounding buckets — no dedicated small buckets.

## Token accounting

- **Per-block char count**: `len(json.dumps(block))`. Exact, stdlib-only, cross-platform.
- **Per-session anchor**: `peak_input_tokens = max over all assistant messages of (usage.input_tokens + usage.cache_read_input_tokens + usage.cache_creation_input_tokens)`. This represents the largest prompt snapshot the model actually saw during the session.
- **Known gap to explain to readers**: `sum(bucket_chars) / 4 ≈ peak_input_tokens − system_prompt_size`. Expected shortfall is ~15K tokens — the baseline Claude Code system prompt is not stored in the JSONL. If `(peak_input_tokens) − (sum(bucket_chars) / 4)` is far from ~15K, the script isn't broken; unusual system-prompt mutations or cache behavior could explain it.
- Report reports char counts only. Header notes `tokens ≈ chars / 4`.

## Processing algorithm

Two passes per session, because `tool_result` messages reference their originating `tool_use` by `tool_use_id`, which requires a lookup table built from an earlier pass.

1. **Pass 1**: walk every message, find every `tool_use` content block, build `{tool_use_id: {name, input}}` map.
2. **Pass 2**: walk every message, for each content block:
   - If block is a `tool_result`: look up `tool_use_id` → get tool name + input → apply bucket precedence (claude_md / agent_team_md / skill_content / subagent_result / tool_result:name) → add char count to that bucket.
   - If block is a `tool_use`: attribute char count to `assistant` (representing the size of the outgoing tool call).
   - If block is plain text in an assistant message: attribute to `assistant`.
   - If block is plain text in a user message AND does not match `skill_content` rule: attribute to `assistant`. The name `assistant` is a slight abuse — it means "conversation text that's not a tool result or a skill load". User turns are typically <2% of total chars and not worth a separate bucket. If the baseline shows `assistant` dominant and it turns out to be user-side rather than model-side, split it then.
3. After pass 2, aggregate bucket totals for the session.
4. After all sessions processed, aggregate across sessions weighted by session size.

## Output

Markdown to stdout. User redirects into `docs/plans/2026-04-13-context-baseline.md` on first run.

```
# Context Bloat Baseline — YYYY-MM-DD

(token counts are approximate: tokens ≈ chars / 4)

## Top N sessions by file size

| rank | project | session | size_MB | msgs | peak_input_tokens | sum_bucket_chars |
| 1 | claude-code-toolkit | <short-uuid> | 12.4 | 340 | 178000 | 680000 |
| ... |

## Aggregated buckets across top N (totals)

| bucket | chars | % of total |
| tool_result:Bash | 1234567 | 34.2% |
| subagent_result | 650000 | 18.0% |
| assistant | 530000 | 14.7% |
| skill_content | 398000 | 11.0% |
| claude_md | 160000 | 4.5% |
| ... |

## Per-session detail (top 3 by size)

### 1. claude-code-toolkit / <short-uuid> — 12.4 MB, peak 178K tokens

| bucket | chars | % |
| tool_result:Bash | ... | 42% |
| ... |

### 2. ...
### 3. ...
```

No findings narrative. No recommendations. The user reads the table and decides.

## Script interface

```
py -3 tools/measure-context-bloat.py [--top-n 10] [--project-filter claude-code-toolkit]
```

- Invocation: `py -3` (Windows launcher, more reliable than bare `python` on this machine).
- Stdlib only: `json`, `pathlib`, `argparse`, `collections`, `datetime`, `sys`.
- Estimated length: ~180 lines after the correctness fixes (two-pass + per-block attribution + case-insensitive path matching).
- Exits 0 on success. Exits 1 if no sessions match the filter.

## File locations

| File | What |
|---|---|
| `tools/measure-context-bloat.py` | The script. Create `tools/` directory if it doesn't exist. |
| `docs/plans/2026-04-13-context-baseline.md` | First-run snapshot, committed as a durable before-picture. Produced via `py -3 tools/measure-context-bloat.py > docs/plans/2026-04-13-context-baseline.md`. |
| `docs/plans/2026-04-13-workflow-meta-issues.md` | This file. The design spec (this addendum section) lives here. |

## Scope guardrails

What this script does NOT do:

1. **No timeline / turn-by-turn analysis.** Aggregate only. If the baseline is ambiguous (no single dominant bucket), a follow-up can build the timeline variant.
2. **No cache-vs-fresh token distinction.** Measures content size, not billing cost.
3. **No special handling of compacted sessions.** Pre- and post-compact messages in the same JSONL are treated uniformly.
4. **Does not see the baseline system prompt.** Not in the JSONL. Accounts for ~15K tokens of unexplained gap; documented above.
5. **`subagent_result` is a rollup**, not a discrete bucket. Includes every tool use the subagent made internally. Interpret accordingly when reading the report.

## Critical files to create / modify

| File | Edit |
|---|---|
| `tools/` | NEW directory (check first, create if missing) |
| `tools/measure-context-bloat.py` | NEW — ~180 lines, stdlib only |
| `docs/plans/2026-04-13-context-baseline.md` | NEW — redirected stdout from first run |
| `docs/plans/2026-04-13-workflow-meta-issues.md` | Edit — append this addendum section (done in this session) |

## Implementation order (follow-up session)

1. Create `tools/` directory if missing.
2. Write `tools/measure-context-bloat.py` per this spec. Unit-test locally against one known session JSONL before running the full pass.
3. Run script: `py -3 tools/measure-context-bloat.py > docs/plans/2026-04-13-context-baseline.md`.
4. Review baseline. If the top bucket is obvious (>30% of total), draft the intervention PR. If top-3 buckets together exceed 60% but no single winner, draft multiple parallel interventions. If bloat is diffuse (no bucket >20%), escalate to the Option C timeline variant (turn-by-turn cumulative curves) — structural redesign may be needed.
5. Commit script + baseline snapshot in one PR. Title: "tools: add context bloat audit script + 2026-04-13 baseline".

## Verification

- `test -f tools/measure-context-bloat.py` exits 0.
- `py -3 tools/measure-context-bloat.py --top-n 1` runs in <10 seconds against 1 session and produces a report with at least the aggregated table.
- `py -3 tools/measure-context-bloat.py --project-filter="" --top-n 3` runs across all projects without crashing on non-claude-code-toolkit sessions.
- `test -f docs/plans/2026-04-13-context-baseline.md` after the commit.
- `grep -c "^## Aggregated buckets" docs/plans/2026-04-13-context-baseline.md` returns 1.
- `grep -c "^### " docs/plans/2026-04-13-context-baseline.md` returns 3 (three per-session detail sections).
- `peak_input_tokens − (sum_bucket_chars / 4)` for any session is within ~30K of the expected 15K system-prompt gap. Larger gaps flag a script bug or an unusual session.

## Deferred (not in this measurement pass)

- **Timeline variant.** Per-turn cumulative token curve. Build only if the aggregate pass produces ambiguous results.
- **Cross-project baseline.** `--project-filter=""` gives this as a one-flag change, but the committed snapshot is claude-code-toolkit only.
- **Automated intervention recommendation.** The data-only report deliberately omits this; human interpretation is more reliable than a hardcoded lookup table.
- **Prospective instrumentation.** A hook that snapshots context size at moments of interest. Build later if we need to watch a specific change land.

## Links

- Parent discussion: Issue #1 above.
- Related: `docs/plans/2026-04-12-pr-b-hook-hardening.md` (the previous "measurement before change" discipline applied to hook enforcement).
