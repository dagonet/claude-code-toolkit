# Read Size Gate — User-Level PreToolUse Hook

**Tier: T2**

**Team: (solo, PO-executable)**

Challenge 1 — see "Challenge 1 — Scope & Necessity" section below.
Challenge 2 — see "Challenge 2 — Correctness & Completeness" section below.

## Context

PR #8 measured the context baseline. Read tool accounts for ~22% of total session context — the single largest actionable bucket documented in `docs/plans/2026-04-14-context-baseline.md`. PR #9 dropped the two-pass Architect challenge for T1/T2 (workflow-meta-issues action #4). The remaining workflow-audit tracks (superpowers wiring, rule audit, grep-hook decision, etc.) were re-examined under /challenge in this session and found to be either (a) solving the wrong bucket — superpowers wiring targets CLAUDE.md length, not Read-tool usage — or (b) blocked on a rule usage audit that nobody has started.

A brainstorming pass pinned down the actual goal: the workflow stack itself (tier T1–T4, PO, two-pass challenge, per-workstream pipeline) is **not painful in practice** — the user reports (f) = "ran cleanly; the meta-question is theoretical / context-bloat-metric-driven" on recent T3/T4 sprints in `InvestmentAdvisor` and `Organizer`. The workflow is load-bearing for real target-project work (Q1 answer = (b)) and shouldn't be cut. What *does* matter is the 22% Read-tool metric, and the brainstorm narrowed the right lever to **enforce the existing "use Explore / `ctx_execute_file` instead of Read for analysis" rule via a hook, at user scope, so it applies to the real target-project work where the 22% is being paid**.

This plan ships that hook and nothing else. It deliberately does not touch the workflow stack, does not reshape CLAUDE.md, and does not execute the dormant superpowers-wiring plan — those were solving adjacent problems, not this one. See "Out of scope" below.

## Goal

Drop the Read-tool share of session context by forcing large-file reads to flow through `ctx_execute_file` or Explore subagents instead. Validate with before/after `ctx_stats` measurements across 2–3 representative sessions.

## Architecture

- **Single new script:** `hooks/read-size-gate.sh` in this repo, mirrored at `user-level-reference/hooks/read-size-gate.sh` as the "install from here" canonical copy.
- **Installed at user scope:** `~/.claude/hooks/read-size-gate.sh`, registered as a `PreToolUse` matcher for `Read` in `~/.claude/settings.json`.
- **No project-level install.** Not added to any `templates/*/settings.json` — the 22% is paid in target-project sessions (InvestmentAdvisor, Organizer), so the hook must live at user level to cover them. `claude-code-toolkit` self-maintenance sessions get the benefit as a byproduct.
- **Rollback: one line** — comment the PreToolUse stanza out of `~/.claude/settings.json`.

## Decision rule

For each `Read` call, compute `effective_lines = min(file_line_count, limit_param or file_line_count)`.

| Condition | Action |
|---|---|
| `effective_lines <= 500` | **allow** (exit 0) |
| `effective_lines > 500`  | **block** (exit 2 with diagnostic on stderr) |

Threshold **500** is a gut number for the first ship — explicitly not defended. The log in the next section is what makes it calibratable after real use.

**Behavior table (checked by smoke tests):**

| Call | Effective | Action |
|---|---|---|
| `Read(small_80_line_file.md)` | 80 | allow |
| `Read(big_3000_line_file.py)` | 3000 | **block** |
| `Read(big_file, limit=100)` | 100 | allow |
| `Read(big_file, limit=750)` | 750 | **block** |
| `Read(big_file, offset=500, limit=50)` | 50 | allow |
| `Read(missing_file)` | n/a — file doesn't exist | allow (let Read produce its own error) |
| `Read(relative_path_big.py)` | 800 | **block** (after `realpath` normalization) |

**No bypass mechanism.** Escape routes are the already-preferred tools:
1. `mcp__plugin_context-mode_context-mode__ctx_execute_file` (runs code against the file in sandbox; only the printed summary enters context).
2. Explore subagent (returns compressed summary).
3. Range-targeted `Read(path, offset=X, limit<=500)` (for edit workflows where you already know the target region).

No override flag, no allowlist file, no env var. Any bypass degrades to "Claude reflexively unblocks and the 22% comes back." If post-sprint logging shows the block misfires on legitimate work, the fix is **raise the threshold**, not add a bypass.

**Line counting:** `wc -l < "$path"` for exact count. Normalize relative paths with `realpath` (or `readlink -f` as portable fallback). If the path doesn't exist or isn't readable, exit 0 and let the Read tool produce its normal error — not the hook's job to police existence.

## Diagnostic + logging

**Block diagnostic (stderr):**

```
BLOCKED: Read on <path> (<N> effective lines, threshold=500)

This file is too large to Read directly. Use one of:
  1. mcp__plugin_context-mode_context-mode__ctx_execute_file(path, language, code)
     for analysis — only your printed summary enters context.
  2. Explore subagent — returns a compressed summary.
  3. Read(path, offset=X, limit=<=500) — range-targeted read.

If you are about to Edit this file and need to locate your target region,
run ctx_execute_file with a grep snippet to find the line numbers first,
then use offset/limit to read just that slice.

Hook config: ~/.claude/hooks/read-size-gate.sh (threshold=500)
To disable temporarily: comment the hook in ~/.claude/settings.json.
```

**Log file:** `~/.claude/state/read-size-gate.log`, append-only, one line per non-trivial decision, tab-separated:

```
<ISO8601>\t<BLOCK|ALLOW>\t<effective_lines>\t<file_line_count>\t<has_offset>\t<has_limit>\t<path>
```

- Only log `ALLOW` when `file_line_count > 250` — the "non-trivial allow" tail. Small-file allows are noise.
- Always log `BLOCK`.
- **Graceful failure:** if the state directory is unwritable (permission, disk), the hook still honors its block/allow decision. Log append is best-effort, errors suppressed. Block is functional, logging is diagnostic.

**What the log enables post-sprint:**
- Histogram of `effective_lines` on BLOCK → is 500 the right threshold?
- BLOCK:ALLOW ratio above 250 → is the hook firing meaningfully?
- `has_offset`/`has_limit` distribution on ALLOW → is the range-read escape actually being used?
- Repeat-blocked file paths → which files keep hitting the wall (usually points at a specific large source file being read wrong).

No metrics aggregation command ships in this PR. Post-sprint analysis is done by hand with `awk` or `ctx_execute_file` over the log. A `/read-stats` slash command is a reasonable follow-up only if the log proves worth looking at regularly.

## Critical files

| File | Change | New? |
|---|---|---|
| `hooks/read-size-gate.sh` | New script — parse JSON stdin, compute effective_lines, block/allow, append log | **new** |
| `user-level-reference/hooks/read-size-gate.sh` | Duplicate of above — matches existing `user-level-reference/` mirror pattern | **new** |
| `user-level-reference/settings-reference.md` | Add section "Read Size Gate (PreToolUse)" with the exact JSON stanza to paste into `~/.claude/settings.json` | edit |
| `README.md` | One bullet under install/setup pointing at the settings-reference stanza | edit |
| `docs/plans/2026-04-14-read-size-gate.md` | Commit this plan post-merge for audit trail (rename from `streamed-juggling-tarjan.md`) | **new** |

Total: **4 new files + 1 edit = 5 files**, single commit, single PR.

## Install (manual, once)

1. `cp hooks/read-size-gate.sh ~/.claude/hooks/read-size-gate.sh` (create `~/.claude/hooks/` if needed)
2. `chmod +x ~/.claude/hooks/read-size-gate.sh`
3. Paste the PreToolUse stanza from `user-level-reference/settings-reference.md` into `~/.claude/settings.json`, merging with any existing hooks block
4. Start a new Claude Code session (settings reload is session-scoped)
5. Baseline capture: run representative target-project work, run `ctx_stats`, record Read-tool share

**Why manual and not scripted:** `~/.claude/settings.json` is personal config; automated edits risk clobbering other settings. Same manual-paste pattern as MCP server install in the existing HOWTO. A one-liner installer is a reasonable follow-up only if the hook proves worth keeping.

## Pre-ship verification

**Gate 0 — Edit-internal-Read open question (BLOCKS everything else).** Confirm whether `PreToolUse:Read` fires only on explicit `Read` tool calls or also on the internal file access `Edit` performs to validate state. Check Claude Code hook docs at `docs.claude.com/en/docs/claude-code/hooks`. If ambiguous, run a direct test: create a 600-line file, install the hook, attempt an Edit, observe. **If Edit's internal reads fire the hook, the design is broken** — the hook would block every Edit on a large file. Either (a) find a tool_name discriminator in the JSON payload to exempt Edit's internal reads, or (b) kill the design and pivot to Option B (cumulative budget). No other verification runs until this is settled.

**Gate 1 — shellcheck.** `shellcheck hooks/read-size-gate.sh` — fix any warnings. Use existing `hooks/tier-before-coder.sh` as style reference.

**Gate 2 — smoke tests in a throwaway dir:**

```bash
mkdir -p /tmp/read-gate-test && cd /tmp/read-gate-test
printf '%s\n' {1..100} > small.txt
printf '%s\n' {1..800} > big.txt

# Case 1: small file → allow (exit 0)
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/small.txt"}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 2: big file no params → block (exit 2, stderr mentions ctx_execute_file)
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/big.txt"}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 3: big file small limit → allow
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/big.txt","limit":100}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 4: big file big limit → block
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/big.txt","limit":750}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 5: big file offset + small limit → allow
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/big.txt","offset":300,"limit":50}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 6: missing file → allow (let Read handle it)
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/read-gate-test/nope.txt"}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 7: relative path in cwd → normalize and evaluate
echo '{"tool_name":"Read","tool_input":{"file_path":"big.txt"}}' \
  | bash "$REPO/hooks/read-size-gate.sh"

# Case 8: log was written
test -f ~/.claude/state/read-size-gate.log && tail -5 ~/.claude/state/read-size-gate.log
```

**Gate 3 — log append stress.** Run case 2 twenty times in a loop. Log should grow by 20 lines, no contention errors.

**Gate 4 — log failure graceful degradation.** `chmod 000 ~/.claude/state/read-size-gate.log`, run case 2, confirm exit 2 still honored and no scary error on stderr. Restore permissions.

## Post-install end-to-end verification (after PR merge)

1. **First fresh session** in a target project (InvestmentAdvisor or Organizer). Observe hook firing; pivot naturally to `ctx_execute_file` or Explore; diagnostic should be clear.
2. **Baseline diff.** Before install: capture `ctx_stats` from 2–3 representative target-project sessions (B1, B2, B3). After install and one sprint (~1–2 weeks) of use: capture 2–3 more (A1, A2, A3) doing similar shape of work. Compare mean Read-tool share.
3. **Qualitative journal.** For each hook firing that felt wrong or painful, note the file path and line count in a text file. Review at sprint end.
4. **Append results section** to `docs/plans/2026-04-14-read-size-gate.md` with before/after numbers and the go/no-go call.

## Go / no-go decision criteria (committed ahead of time)

- **Go (keep hook, maybe tune threshold):** Read-tool share drops ≥5 pp AND qualitative journal has <3 "wrong block" incidents per sprint. If only the metric moves or only the journal stays clean, lean toward keeping — downside is soft friction, upside is a measured bucket drop.
- **Tune (keep hook, raise threshold):** Journal shows frequent legit-edit flows blocked. Raise to 750 or 1000, re-measure one more sprint.
- **Kill (revert hook):** After at most two threshold tunings, metric still <5 pp improvement. Means Read isn't the lever; the 22% is paid by a different mechanism (cumulative small reads, subagent churn, etc.). Revert and re-plan from the measurement, not the assumption.

## Out of scope (explicit)

- **Option B (cumulative Read budget hook)** — revisit only if Option A is killed.
- **Option C (hybrid: both hard gate and cumulative)** — same.
- **`/read-stats` slash command** — build only if the log proves worth looking at regularly.
- **Reshaping Read-tool-discipline bullet in `templates/*/CLAUDE.md`** — the existing bullet stays as written; the hook enforces it. Zero text changes.
- **Superpowers wiring** (the dormant plan at `docs/plans/2026-04-12-wire-superpowers-skills.md`) — deprioritized because it targets CLAUDE.md length, not Read-tool usage, which is the measured bucket. Revisit only after this hook ships and Track #5 (re-measure) shows what the next lever should be.
- **Any workflow stack changes** — tier model, PO role, plan challenge protocol, dev→reviewer→tester pipeline — confirmed load-bearing on real target-project work in Q1/Q2 brainstorm answers. Left untouched.
- **Rule usage audit** (the dormant Track #2 from the earlier draft roadmap) — worth doing eventually to unblock the grep-hook decision, but not the next move and not coupled to this PR.
- **PR C / W13–W14 MCP expansion** — cross-repo, no plan file, out of scope here.

## Challenge 1 — Scope & Necessity

1. **Is the hook actually necessary, or is the existing CLAUDE.md bullet ("Read tool discipline") sufficient?** The bullet is already written and Claude has been ignoring it enough to produce the 22% number. Silent rules that aren't followed are the exact pattern the grep-hook decision from workflow-meta Issue #2 is asking about. This hook *is* the answer to that question for one specific rule.
2. **Is 500 lines the right first threshold?** No defense of the number — it's a gut. The logging makes it calibratable. Committed.
3. **Could this be done without a hook, via a `/ctx-stats` reminder command?** Yes, but passively. The 22% came from a session where the user already had `ctx_stats` available. Passive reminders degrade; enforcement doesn't.
4. **Scope kept tight:** 5 files, one PR, no workflow changes, no template-variant edits, no agent edits. Everything out of scope is listed above so future sessions don't re-debate.
5. **No gold-plating:** `/read-stats` command, automated installer, metrics dashboard — all explicitly deferred until the log proves worth the UI.

No changes from Challenge 1.

## Challenge 2 — Correctness & Completeness

1. **Edit-internal-Read open question is the single load-bearing unknown.** Called out as Gate 0 in pre-ship verification — blocks everything else until resolved. This is the one scenario that can kill the design post-commit if missed.
2. **`wc -l` on very large files is O(size) but cheap.** Not a concern for normal source files. For 100 MB+ files, the hook itself becomes a perf tax — but reading a 100 MB file into Claude's context is exactly the case we want to block anyway.
3. **JSON stdin parsing in bash.** Hook needs to parse `{"tool_name":"Read","tool_input":{"file_path":"...","offset":N,"limit":M}}`. Use `jq` if available (standard in Git Bash? worth checking), otherwise fall back to `grep -oP` or a small Python one-liner. Verify jq presence; if absent, document the dependency in install step 1.
4. **Path normalization across platforms.** `realpath` behavior differs between GNU coreutils (`realpath -e`) and BSD/macOS (`realpath` alone). Windows Git Bash uses GNU coreutils — safe. But the hook lives at user level so if the user ever runs Claude Code from a non-Git-Bash environment, this breaks. Document the shell dependency.
5. **Logging race condition.** Single-writer shell append (`>> file`) is atomic for small writes under POSIX. No race. Stress test (Gate 3) confirms.
6. **`docs/plans/2026-04-14-read-size-gate.md` naming.** Post-merge, rename from `streamed-juggling-tarjan.md` to the dated canonical name during the final commit — matches existing plan file naming in `docs/plans/`.
7. **The `$REPO` variable** in the smoke test command block is just shell shorthand for "path to this repo" — real commands would substitute it. Not a bug; call it out so the reader doesn't try to literally run `$REPO`.
8. **"Fresh session" in post-install verification** — Claude Code reloads settings on session start, not hot. The install steps mention restart; the verification section assumes it's been done.

Changes from Challenge 2:
- **Added Gate 0** (Edit-internal-Read check) as an explicit blocking gate, not just an "open question."
- **Added `jq` presence check** to install step 1 if hook uses it, or documented the fallback.
- **Added explicit plan file rename** (`streamed-juggling-tarjan.md` → `docs/plans/2026-04-14-read-size-gate.md`) to the commit steps.
