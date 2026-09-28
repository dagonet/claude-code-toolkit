# Agent time sinks — design (v4.3.0)

**Status:** spec for review. Branch `feat/agent-time-sinks` (worktree `G:/git/.worktrees/claude-code-toolkit/agent-time-sinks`), cut from `main` b43b140; to be rebased onto `main` once v4.2.0 merges. Nothing lands on `main` until the user merges.
**Origin:** the Motorsport-Manager-AI-Agent session measured 28 subagents over ~16 h: running tests (commit hook, merge gate, iteration) took ~43 % of all logged agent time (~709 of 1,642 min), plus two unattended hangs (165 min, 25 min) and two runaway wait loops. Evidence: `G:/git/Motorsport-Manager-AI-Agent/docs/plans/2026-09-27-agent-time-findings.md` (branch `m117-session-2026-09-06`). Each item below was verified against this repo's hook sources before design (toolkit backlog "agent time sinks", T1–T6).

## Goal

Stop agents paying for test runs that prove nothing new, stop the budget brake from destroying finished work, and stop the command shapes that hang unattended agents — without making any gate easier to bypass by accident.

## Success criteria

1. A merge gate never re-runs the `**Test**` legs on a tree whose commit-hook run already passed them (same Test command, same environment, still fresh) — in a project that opts in.
2. A commit whose staged paths all fall outside a project's declared code paths skips its test run — in a project that opts in — and the merge gate still tests it in full.
3. A subagent at its tool-call budget can still commit.
4. The three command shapes behind the observed hangs and runaway loops are refused before they run, each with one line of advice; every legitimate look-alike still runs.
5. With every new key unset, every existing project behaves exactly as today.

## Decisions (user, 2026-09-28)

| # | Decision |
|---|---|
| D1 | Docs-only skip (T2): **opt-in per project** via a new `**Test paths**:` key; unset = test everything. |
| D2 | Gate reuse (T1): **split the Gate** — a new optional `**Gate extra**:` key holds only the legs beyond Test. |
| D3 | Budget (T3): **let commits through** — the budget hook never blocks a `git commit` call. |
| D4 | Command shapes (T4/T5): **a hook** refusing three shapes with advice, plus one line of prose each for the dotnet rule (T6) and the user-level `CLAUDE.md`. |

## Part A — gate mechanics

### A1. `**Test paths**:` — skip docs-only commits (T2)

- New optional `PROJECT_CONTEXT.md` key, read by `hooks/pre-commit-test.sh` with the same field grammar as the existing keys (list markers, `**X**:`, backticks tolerated): a space-separated list of git pathspecs, e.g. `**Test paths**: hooks/ scripts/ server/ templates/`.
- Decision rule: `git diff --cached --name-only -z -- <pathspecs>` (git does the matching, deletions and renames included). Non-empty → run the Test line as today. Empty → skip the suite, print one line: `pre-commit-test: no staged path matches **Test paths** — tests skipped for this commit (the merge gate still runs in full)`, exit 0.
- **A skipped commit writes no pass record** (A2 must never reuse a run that did not happen).
- Fail-closed: key unset, empty, an unfilled `{{placeholder}}`, or git failing to evaluate the pathspecs → run the Test line (today's behaviour). The key can only narrow when tests run, never switch the Test line off for a matching path.
- This repository leaves the key **unset** (every file here is either code or a document a check reads).

### A2. `**Gate extra**:` — the merge gate reuses a passed Test run (T1)

- The commit hook's pass record `<common git dir>/gate/last-precommit.<tree>.json` gains two fields: `test_sha256` (SHA-256 of the exact `**Test**` command it ran) and `env` (the `gc_gate_env` fingerprint the merge gate already computes). Records without them are never reused.
- New optional `PROJECT_CONTEXT.md` key `**Gate extra**:` — the gate legs beyond `**Test**` (this repository: the hook suite and the server suite).
- `hooks/run-gate.sh` reuses the Test legs when ALL hold, else runs the full `**Gate**` exactly as today:
  1. `**Gate extra**` is set;
  2. a pass record exists for `HEAD^{tree}` with `rc` 0 and the `path` value `pre-commit-test.sh` writes when the Test line actually ran and passed (the implementation plan names the exact literal from the hook source; any other `path` — a skip, a no-op, an unresolved path — is never reused);
  3. its `test_sha256` equals the SHA-256 of the current `**Test**` line;
  4. its `env` equals the current `gc_gate_env`;
  5. it is fresh under the rule `gate-before-merge.sh` already applies to gate artifacts (3600 s; up to 24 h on tree + environment identity).
- On reuse, run-gate runs only `**Gate extra**`; on its success the written gate artifact carries `"reused_test": "<record file name>"` and the output says `GATE PASS <sha> (Test legs reused from <record>)`.
- Any doubt (unreadable record, parser missing, field absent) → full Gate.

### A3. Commits pass the budget brake (T3)

- `hooks/agent-budget-warn.sh` detects a `git commit` segment with the shared detection in `hooks/lib/git-cmd.sh` (covers `git -C x commit`, `-c k=v`, `bash -c "…"` / `sh -lc` wrappers).
- At a block threshold (`BLOCK_AT`, then every `BLOCK_EVERY`), a call carrying a commit segment is **not** blocked: the hook prints its budget warning and exits 0. Every other call — including `git push` and merges — is blocked exactly as today.
- Rationale: hooks run in parallel (Claude Code docs), so blocking a commit after the test hook ran wastes the run AND loses the work; at budget exhaustion the commit is the one call worth allowing.

## Part B — command shapes

### B1. `hooks/deny-hang-shapes.sh` (T4, T5)

PreToolUse on `Bash`, in all six variants' settings and mirrored to `user-level-reference/hooks/` + the user-level settings (the hangs are machine-wide). Reads the command through `hooks/lib/json.sh` (with `cmd_join_continuations`). Refuses — exit 2, one line of advice on stderr — exactly:

| Refused shape | Allowed look-alikes (each a fixture) | Advice |
|---|---|---|
| a heredoc whose output is redirected into a file: `cat > f <<'EOF'`, `cat <<EOF > f`, `cat <<EOF >> f`, `tee f <<EOF` | `git commit -m "$(cat <<'EOF' … EOF)"`; `python - <<EOF`; a heredoc piped into a command | `Write files with the Write tool (a heredoc into a file can hang an unattended agent).` |
| a wait loop: `while`/`until` … `sleep` … `done` in one command | `sleep 5` alone; `for f in …; do …; done` without `sleep` | `End your turn instead of waiting in a loop; you are re-invoked when the background job finishes.` |
| a leading `cd <dir>` followed by `&&` or `;` and further commands | `cd <dir>` alone; `cd` inside `bash -c '…'` | `Use absolute paths, git -C <dir>, or env -C <dir> <cmd> instead of a leading cd.` |

- Advisory, not a safety gate: no parser available, or an unparseable payload → exit 0. Registered with the silent wrapper `[ -f "$f" ] && bash "$f"; …` so a missing script is silent (the context-mode stale-hook lesson). Honours `.claude/git-guard-off`.
- `env -C <dir> <cmd>` verified working in Git Bash (GNU coreutils 8.32, 2026-09-28).

### B2. One line of prose each (T4, T6)

- `templates/dotnet/.claude/rules/csharp.md` and `templates/dotnet-maui/.claude/rules/csharp.md` (path-scoped): `Run dotnet format with a relative path (or none): a forward-slash absolute path checks 0 files and exits 0 -- a vacuous pass.`
- `user-level-reference/CLAUDE.md`, the platform bullet that says to write compound logic to a script file: add `-- write that file with the Write tool, never a heredoc`. Always-loaded bytes grow; measured in the release tables.

## Checks and tests

- `scripts/test-hooks.sh` fixtures, two-sided:
  - A1: matching / non-matching / mixed staged sets; deletion-only; key unset; placeholder; malformed pathspec → runs.
  - A2: reuse on an exact match; full run on a changed Test line, a changed environment, a stale record, a record without the new fields, `rc` ≠ 0, `**Gate extra**` unset.
  - A3: commit at the threshold → exit 0 with warning; `git push` at the threshold → exit 2; wrapped commit → exit 0.
  - B1: every refused shape → exit 2; every look-alike → exit 0; kill switch → exit 0; no parser → exit 0.
- `scripts/verify-template-consistency.sh`: existing mirror (21/21a) and registration checks cover B1 automatically; add assertions that the two new keys are documented in every variant's `PROJECT_CONTEXT.md` template as commented, unset examples, and that no variant sets them.
- The parser matrix runs before tagging (B1 and A3 read the payload through the parser layer).

## Release

Minor release **v4.3.0** after v4.2.0. Templates change (six settings, six `PROJECT_CONTEXT.md` documentation lines, two dotnet rules, a new hook) → consumers receive it through `/sync-template`; the CHANGELOG migration section says the new keys are opt-in and inert until set, and that the user-level hook needs the user-level settings entry.

## Non-goals

- No change to what `**Test**` or `**Gate**` run for a project that sets neither new key.
- No automatic docs detection (D1 rejected it: markdown here is read by checks).
- No parsing of the `**Gate**` command into legs (D2 rejected per-leg records).
- The MM-Agent project-owned items (its no-amend fix rounds, its Test-line composition) stay theirs.
