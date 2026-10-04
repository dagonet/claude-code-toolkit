# Slimming the Safety-Check Hooks — Design

Date: 2026-10-04
Status: approved by the user 2026-10-04, with the C2 amendment below
Author: agent-supervisor (agent-dashboard); copied from agent-dashboard `docs/superpowers/specs/2026-10-04-hook-slimming-design.md` at 130a9b7
Builder: the `update-cc-toolkit` session, in claude-code-toolkit (user decision, 2026-10-04)

> **Amendment (user, in the update-cc-toolkit session, 2026-10-04 21:29): "Yes, keep a missing
> check blocking."** This replaces item 3 of C2. Phase C ships in **v4.4.0**, together with Jev and
> the push-hook/speed work. A missing or unreadable check script must still block the tool call with
> exit 2, as it does today. That makes criterion 5 ("not weaker than today") hold literally. The
> mechanism keeps exec form and costs no extra process:
>
> ```json
> {"type":"command","command":"<Git Bash>/bin/bash.exe",
>  "args":["-c","[ -r \"$0\" ] || { echo \"HOOK SCRIPT MISSING: $0 -- enforcement offline\" >&2; exit 2; }; . \"$0\"","<absolute path>/x.sh"]}
> ```
>
> - It is one bash process; there is no shell inside a shell.
> - `[ -r ]` and `.` are builtins, so the script runs in that same process.
> - Verify in the build that `exit N` inside the sourced script sets the process exit code, and that
>   `$0`/`BASH_SOURCE`-relative library paths still resolve.
> - If either breaks, use `exec bash "$0"` after the builtin test instead of `.`. That is one exec
>   and no fork.
> - The SessionStart verification and the doctor check (C2 items 1-2) stay as extra layers.
> - The allow hooks that are never 127-wrapped today (for example `allow-ctx-plan.sh`) and the stop
>   gate (never wrapped) keep their current fail polarity.

## 1. Why

The machine runs about 10 Claude Code sessions at once, and it hung or restarted twice on
2026-10-04. The agent dashboard measured a normal busy afternoon at 300–400 new processes per
minute, and a roll call pushed that to about 2,500 per minute.

A large share of that churn is not the agents' work. It is the safety-check hooks that run around
every tool call.

## 2. Measurements

All measured on 2026-10-04 on this machine. The hooks are the global set in
`~/.claude/settings.json`, which is identical to the claude-code-toolkit sources, plus the
project-level copies in toolkit-based projects.

### 2.1 Hooks that fire for one Bash tool call

- **PreToolUse** (they run in parallel):
  - `no-push-main.sh`
  - `deny-secret-reads.sh`
  - `deny-hang-shapes.sh`
  - `pressure-gate.sh` (agent-dashboard)
- **PostToolUse:** `bash-output-guard.sh`

**Toolkit-based projects** also register project copies:

- `pre-commit-test`
- `no-push-main` again
- `gate-before-merge`
- `deny-secret-reads` again
- `enforce-delegation`
- `deny-hang-shapes`
- `agent-budget-warn`
- PostToolUse `bash-output-guard` again
- PostToolUse `enforce-delegation`

### 2.2 Processes per Bash tool call

These are estimates from reading the scripts (`file:line` references in §8).

| Scenario | Shells | Other processes | of which `node` |
|---|---|---|---|
| Plain project, `ls -la` | ~8 | ~30 | ~15 |
| Plain project, `git status` | ~8 | ~60 | ~15 |
| Toolkit project | ~18 | 100+ | more |
| PowerShell tool call | ~5 | ~25 | |
| Read tool call | 2 | ~8 | 4 |

### 2.3 Time per hook, run as Claude Code runs it

`bash -c "<command>"`, JSON on stdin, `git status`, median of 8 runs:

| Hook | Median |
|---|---|
| `no-push-main` | 1,774 ms |
| `deny-secret-reads` | 1,169 ms |
| `deny-hang-shapes` | 1,012 ms |
| `bash-output-guard` (Post) | 355 ms |
| `pressure-gate` | ~40 ms when green (3.2 s was its deliberate yellow pause) |
| Baseline `bash -c 'exit 0'` | 40 ms |

### 2.4 Where the cost comes from

1. **JSON parsing with node, 4–5 times per hook.** `hooks/lib/json.sh` runs a probe, a validity
   check, then one call per field (`tool_name`, `cwd`, `command`). Each node start costs 50–250 ms
   on Windows.
2. **A shell inside a shell.** Each registration is
   `bash ~/.claude/hooks/x.sh; c=$?; if [ "$c" = "127" ] …`. Claude Code starts a shell for the
   command string, and that shell starts a second bash for the script.
3. **No early exit.** Scripts source the large libraries (`git-cmd.sh`, ~57 ms to source) and run
   `tr|awk|grep` pipelines before deciding the call is irrelevant. For example, `no-push-main` runs
   three `gc_matches_subcommand` pipelines for a plain `git status`.
4. **Duplicates.** In toolkit projects, `no-push-main`, `deny-secret-reads` and `bash-output-guard`
   run twice: once from the global registration and once from the project's own.

### 2.5 Facts verified for Claude Code 2.1.289 on Windows

- **Command hooks run through Git Bash `bash -c`.**
- **"Exec form" starts the program directly with no shell:**
  `{"type":"command","command":"<program>","args":[…]}`.
  - Verified with a probe: the hook ran with no shell parent, received the full JSON on stdin, and
    its `additionalContext` reached the model.
  - `~` is not expanded in `args`, so paths must be absolute.
- **All matching hooks run in parallel.** Results merge with the most restrictive decision winning
  (deny > defer > ask > allow).
- **A non-zero exit other than 2 is a non-blocking error:** the tool call proceeds. HTTP hooks also
  fail open on connection errors.

## 3. Goal and success criteria

**Goal.** Cut the processes and time the safety checks add to every tool call, without weakening
any protection.

| # | Criterion | Phase C target | Phase B target |
|---|---|---|---|
| 1 | Processes started by checks for one Bash call in a plain project (`git status`) | ≤ 50 % of today | ≤ 2 |
| 2 | Same, in a toolkit project | ≤ 50 % of today | ≤ 3 |
| 3 | Check wall time per Bash call on a green machine (slowest hook) | ≤ 400 ms | ≤ 150 ms |
| 4 | Decisions on the equivalence corpus (§6) | identical to today | identical to today |
| 5 | Protection when a check script is missing or broken | not weaker than today | not weaker than today |

## 4. Phase C — quick wins (one toolkit release: v4.4.0)

**C1. Exec-form registration.**

- Register each hook in exec form. For the protections, use the fail-closed form in the amendment
  at the top of this file.
- The toolkit's setup script writes the absolute paths and the Git Bash path it finds.
- This removes one shell per hook.

**C2. Replace the missing-script safety net.** Today's wrapper turns exit 127 ("script missing")
into exit 2, which blocks the tool call. Plain exec form loses that, because bash's 127 is
non-blocking. The replacement:

1. **SessionStart check.** A `SessionStart` hook verifies that every registered hook script exists
   and parses (`bash -n`). If any is missing, it injects a prominent warning into the session's
   context and the session's first reply must surface it.
2. **Doctor check.** The toolkit's existing consistency/doctor check gets the same verification.
3. ~~Decision (user, 2026-10-04): use the SessionStart warning plus the doctor check. All hooks,
   the protections included, move to exec form; there is no shell wrapper. A missing script then
   fails open, but loudly at session start.~~ **Superseded by the amendment at the top:** a missing
   script still blocks (exit 2), through a builtin existence test inside the same exec-form bash
   process.

**C3. Parse JSON once per hook.**

- `json.sh` gains a single entry point that extracts all needed fields in one `node` call.
- The fields come back NUL-separated into shell variables.
- `probe`, `json_valid` and the per-field calls are folded into that one call.
- This keeps exactly today's parsing semantics; no hand-written JSON parser in this phase.

**C4. Early exit with builtins.**

- Each script decides "not my business" before sourcing big libraries or spawning anything, using
  `[[ =~ ]]` on the raw input.
- `no-push-main` exits unless the command can contain `push`, `checkout`, `switch`, `branch` or a
  script runner it already scans for.
- `deny-secret-reads` exits unless a reader verb or a secret-looking filename appears.
- `deny-hang-shapes` exits unless `<<`, `sleep` or a leading `cd` appears.
- The check must over-match, never under-match: when in doubt, continue to the full check.

**C5. No duplicates.**

- In toolkit projects, each check runs once.
- The global copy exits immediately (builtin `[ -f "$CLAUDE_PROJECT_DIR/hooks/x.sh" ]`) when the
  project registers its own copy.
- This is the pattern `deny-hang-shapes` and `model-floor` already use, extended to `no-push-main`,
  `deny-secret-reads` and `bash-output-guard`.

**Expected after C.**

- **Plain project, `git status`:** about 5 hook processes plus about 3 node, down from ~8 shells and
  ~60 others.
- **Toolkit project:** roughly half of today.
- **Slowest hook:** about 150–300 ms instead of 1.8 s.

## 5. Phase B — one combined check per event (next toolkit release)

**B1. Two dispatchers.**

- `pre-tool.sh` (PreToolUse, matcher `Bash|PowerShell|Read|Agent`) and `post-tool.sh`
  (PostToolUse).
- Both are registered in exec form, at user level only. Project settings register no tool hooks.
- The dispatcher discovers project checks under `$CLAUDE_PROJECT_DIR/hooks/`.

**B2. Builtin-only input.**

- The dispatcher reads stdin once (`read -r -d ''`).
- It extracts `tool_name`, `cwd`, `session_id`, `tool_input.command`, `tool_input.file_path` and
  `tool_input.subagent_type` / `model` with `[[ =~ ]]`.
- A JSON-string unescape function handles `\" \\ \/ \b \f \n \r \t \uXXXX`, including surrogate
  pairs, using `printf`.
- If anything unparseable shows up, it falls back to the C3 node call for that one input.

**B3. Checks as functions.**

- Each check becomes a function with a fixed contract. It gets the parsed fields from shell
  variables and sets `CHECK_DECISION` (allow/ask/deny), `CHECK_REASON` and `CHECK_CONTEXT`.
- The dispatcher runs all checks that match the tool, in a fixed order, in one process.
- It combines results like Claude Code's own merge: the most restrictive decision wins, reasons
  from denying checks are joined, contexts are concatenated.
- It then prints one JSON object.
- A check that needs an external tool (for example `git` for the push target) calls it only on its
  slow path.

**B4. Compatibility for project hooks not yet converted.**

- If `$CLAUDE_PROJECT_DIR/hooks/x.sh` does not define the function contract (no
  `check_<name>` function after sourcing in a subshell-free probe), the dispatcher runs it as a
  child process with the original stdin and maps its exit code and JSON output.
- Converted checks cost nothing extra; legacy ones cost what they cost today.

**B5. The pressure gate as a check function.**

- agent-dashboard's `pressure-gate.sh` gets a function mode: `pressure_gate_check` follows the B3
  contract when sourced, and keeps its standalone behaviour when run.
- agent-supervisor makes that change in agent-dashboard when B starts.
- The gate's `sleep` for yellow and red stays inside the function. It is the intended delay.

**B6. Fail-safe.**

- The dispatcher must never block on its own errors except for protections. If a protection check
  function errors, the dispatcher denies with "safety check failed: <name>"; that is today's
  fail-closed intent.
- Any other check erroring is logged and skipped.
- The SessionStart verification from C2 also covers the dispatcher.

**Expected after B.** One process per PreToolUse event and one per PostToolUse, plus an external
tool only when a check truly needs it, for example a real `git push`. The slowest path stays under
150 ms on green.

## 6. Verification (both phases)

**Equivalence corpus.** A fixed set of at least 80 tool-call payloads covering:

- Bash: pushes to main, master and protected branches via plain `git`, aliases, `-C` paths,
  scripts and chained commands; `.env` and secret reads in all reader forms; heredocs into files;
  sleep loops; leading `cd` chains; harmless commands
- PowerShell equivalents
- Read of secret and non-secret files
- Agent calls with and without model fields
- PostToolUse outputs over and under the 12,000-character guard
- payloads with escapes: quotes, backslashes, newlines, `\uXXXX`, non-ASCII

Old and new hook sets must produce the same decision class (allow, deny, ask or context) for every
payload, and the same reason category for denies. The toolkit's existing `scripts/test-hooks.sh`
keeps passing.

**Cost.**

- The timing harness agent-supervisor used (`bash -c` per hook, median of 8) and a process counter
  run before and after. The counter counts processes created during one simulated tool call, using
  the dashboard's process snapshot before and after each hook run, with an idle machine.
- Targets are those in §3.

**Live check.**

- The dashboard's new-processes-per-minute gauge, on a comparable busy afternoon, before and after.

## 7. Rollout and back-out

- **Release flow.** Phase C ships through the toolkit's normal branch, review and release flow, in
  v4.4.0 ("faster checks"). Phase B ships in the release after.
- **Distribution.** Both reach this machine through the toolkit's setup and sync, which rewrite
  `~/.claude/settings.json` and the project copies.
- **Back-out.** The previous `settings.json` hooks block is backed up by the setup script. Restoring
  it and re-syncing projects returns to today's behaviour.
- **Interference.** The dashboard's pressure gate registration (`bash ~/.claude/hooks/pressure-gate.sh`)
  is owned by agent-dashboard's installer. In Phase C it switches to exec form there. In Phase B it
  is removed from settings and sourced by the dispatcher (B5). agent-supervisor coordinates both
  steps with update-cc-toolkit.

## 8. References

From the read-only script analysis of 2026-10-04 (line numbers in `~/.claude/hooks`, identical to the
toolkit sources at v4.3.0):

- `no-push-main.sh:21` — dirname
- `no-push-main.sh:66-67` — fast-exit grep
- `lib/git-cmd.sh:274, 410, 468, 481, 483, 593, 659, 1504, 1529` — `cat`, `sed`, `tr`, `head` and
  `tr|awk|grep` in `gc_matches_subcommand`
- `lib/json.sh:247, 264, 275` — sourcing cost, `cat` + `awk` join
- `deny-secret-reads.sh:108, 128, 132, 182, 188, 211`
- `deny-hang-shapes.sh:11, 18`
- `bash-output-guard.sh:45, 50, 52`
- `pressure-gate.sh` — builtin-only reference implementation for B2

## 9. Out of scope

- **Running checks over HTTP inside the dashboard** (approach A). It would mean zero processes per
  call, but every protection silently switches off whenever the monitor is down, and the check
  logic would move out of the toolkit. It may be revisited for non-protection checks only.
- **Sharing MCP servers across sessions**, which is about 29 helper processes per idle session.
  That is a separate follow-up.
