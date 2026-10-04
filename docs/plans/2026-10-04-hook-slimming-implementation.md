# Hook slimming, Phase C (v4.4.0) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is sized for one sonnet implementer and one opus reviewer.

**Goal:** Cut the processes and wall time the safety-check hooks add to every tool call, and weaken no protection. Phase C has five parts. C1 registers hooks so that no shell runs inside a shell. C2 makes a missing check still block (exit 2) and adds SessionStart and doctor verification. C3 parses JSON with one parser call per hook. C4 adds builtin early exits that over-match. C5 runs each check once in toolkit projects. The test is a ≥ 80-payload equivalence corpus, run old against new under node, python3-only and jq-only, with **zero decision changes**.

**Architecture:** Each registration starts **one** bash, and that bash runs the hook in place:
- **User-level** (`~/.claude/settings.json`): exec form, `"command": "<absolute Git Bash usr/bin/bash.exe>"`, `"args": ["-c", "<wrapper>", "<absolute hook path>"]`. The wrapper is the amendment's builtin `[ -r "$0" ]` test followed by `. "$0"`. A new `scripts/render-user-hooks.sh` writes the two absolute paths (setup scripts do not write user settings today).
- **Project templates** (machine-independent, committed, byte-identical): shell form, `f="${CLAUDE_PROJECT_DIR:-.}/hooks/x.sh"; [ -r "$f" ] || {…; exit 2; }; exec bash "$f"`. This choice is **Decision D1**; the recommendation and its reasons are in the Decisions section.

Under both forms, the old wrapper's "exit 127 → exit 2" mapping moves **into** each fail-closed hook as one `trap … EXIT` line, so polarity stays exactly as it is today (probe P1-g). The global copies of `no-push-main`, `deny-secret-reads`, `bash-output-guard`, `deny-hang-shapes` and `model-floor` step aside only when the project both **has** and **registers** its own copy (C5). The registration check is a builtin read of `.claude/settings.json`, so a project that ships a hook but does not register it never loses the check. `hooks/lib/json.sh` gains `json_fields`, a field-list version of `json_payload` (one interpreter run). The remaining multi-call hooks switch to it.

**Tech Stack:** bash ≥ 3.2 syntax (Git Bash 5.2 on Windows; no `${v,,}`, no `declare -A`; case-insensitive tests use `shopt -s nocasematch`), node / python3 / jq parser parity, Claude Code hook exec form (`command` + `args`), python3 and pytest for the server test and for the equivalence harness's registration reader.

**Spec:** `docs/plans/2026-10-04-hook-slimming-design.md`. It is binding, **including the amendment at its top**. Phase C only (§4 C1–C5, §6 verification, §7 rollout); Phase B (§5) is out of scope. Read it whole before Task 1.

## Global Constraints

- **Base.** Execute on the **v4.4 integration branch**: `feat/v4.3.2` (design and plan in `docs/plans/2026-10-04-v4.3.2-*.md` there), with Jev and the push-hook/speed work merged in. Its pushed head may be stale, so the controller names the exact base commit in Task 0, and this plan never cites line numbers. Every edit is located by **function name or named block**. `WT` below is the integration worktree the controller names in Task 0. Use Git Bash spelling and spell it out in every command, because Bash state does not persist between calls.
- **Files both efforts touch:** `hooks/lib/json.sh`, `hooks/lib/git-cmd.sh`, `hooks/pre-commit-test.sh`, `hooks/no-push-main.sh`, `hooks/gate-before-merge.sh` and `scripts/test-hooks.sh`, plus `scripts/verify-template-consistency.sh` and `setup-project.sh`/`.ps1` (v4.3.2 P3). Before each task that touches one of them, run `git -C $WT log --oneline -3 -- <file>`. If v4.3.2 changed it after Task 0's base, re-read the named function before editing. Never resolve a conflict by dropping a v4.3.2 hunk.
- **KISS** is a standing user rule. Each task does what it names and nothing more.
- **Fail closed.** A protection that cannot determine the answer refuses. Phase C adds **zero new allows**. The equivalence corpus (Task 1) is the proof: same decision class and same reason category for every payload, in all three parser configurations.
- **Never** run the full `scripts/test-hooks.sh` (about 55 min; it runs at the release gate only, with the user's go-ahead). Run single blocks through the block harness. Never run the parser matrix outside Task 13.
- **Commit discipline.** Write the message with the Write tool to a file **outside** the repo (your scratchpad). Run `git -C $WT add <explicit paths>` and `git -C $WT commit -F <file>` as two separate calls, each with timeout 600000 (the pre-commit hook runs the consistency script). Never `add -A`, amend, stash, push, or pass `--no-verify`. Never create `.claude/git-guard-off`. End each message with the `Co-Authored-By:` line for your own model. Implementers spawn no subagents.
- **LF only.** Use the Edit/Write tools. Never rewrite a file containing non-ASCII through PowerShell.
- **`deny-hang-shapes`** refuses heredocs into files and a leading `cd` chain. Use absolute paths, `git -C` and `run-in.sh`, and write files with the Write tool.
- **Byte-identical sets** (check 21 and the variant census): `hooks/X.sh` ≡ `user-level-reference/hooks/X.sh` for every mirrored hook (`cp` then `cmp` after each edit). `hooks/lib/*.sh` ≡ `user-level-reference/hooks/lib/*.sh`. `templates/*/.claude/settings.json` are six identical copies: edit `templates/general` first, then `cp` to the other five. The new `verify-hooks.sh` is mirrored (Task 9) and does **not** join `HOOKS_NO_MIRROR`.
- **Fixture blocks.** `# ---- v4.4.0 C<n>: <title>` … `# ---- end v4.4.0 C<n>`. Insert each one immediately before the final tally line `echo "----------------------------------------------------------------"` of `scripts/test-hooks.sh`, after the last `# ---- end v4.3.2 …` block. The harness pulls in lines 1–50 and every top-level function defined before line 400 (`mkrepo`, `mkjson`, `jesc`, `check`, `check_msg`, `check_nomsg`, `expect`, `skip`, …). Define anything else inside the block.
- **Block harness.** Reuse v4.3.2's `run-block.sh` and `run-in.sh` (v4.3.2 plan, Global Constraints). Copy them into `$WT/.superpowers/sdd/2026-10-04-hook-slimming/` and set the default `VER` to `v4.4.0`. `RB <block>` runs one block; `RI <cmd>` runs a repo script.
- **Full consistency run** = `RI bash scripts/verify-template-consistency.sh` (timeout 600000). The last line must be `ALL CHECKS PASSED`.
- **Equivalence run** = `RI bash scripts/hook-equivalence.sh` (Task 1). The last line must be `EQUIVALENCE: 0 decision changes`. Run it at the end of every task from Task 2 on.
- **New check numbers.** The highest check on `feat/v4.3.2` is 64 (`# Check 64`). The numbers are reserved: 65 for v4.4 (Jev), 66–68 for v4.5, and 69 for v4.3.2 P (pre-push). This plan uses **70** (Task 9, doctor) and **71** (Task 10, registration polarity). Before writing either one, run `grep -n '^# Check 7[01]' scripts/verify-template-consistency.sh`; it must print nothing, and the controller confirms the numbers.

## The polarity table (binding; every task preserves it)

These are today's registrations, with what each does when the script is missing and what it becomes. "Missing" means the path is absent or unreadable.

| Hook | Where registered | Missing today | Phase C form | Missing after |
|---|---|---|---|---|
| `pre-commit-test` (with `"timeout": 3360`), `no-push-main`, `gate-before-merge` (Bash and MCP-merge groups), `deny-secret-reads`, `deny-claude-md-writes`, `require-skills-block`; root `.claude/settings.json` copies; `coder.md` frontmatter `gate-before-merge` | templates, root, agent | **exit 2** (127 wrapper) | `F` = fail-closed | **exit 2** |
| `no-push-main`, `deny-secret-reads` | user | **exit 2** | `UF` = user fail-closed + step-aside | **exit 2** (or step aside, C5) |
| `read-size-gate`, `enforce-delegation` (Edit and Bash groups), `agent-budget-warn` | templates | WARN, **exit 0** | `W` = fail-open WARN | WARN, exit 0 |
| `model-floor`, `deny-hang-shapes` | templates, root | silent **exit 0** (`[ -f ] \|\| exit 0`) | `O` = fail-open silent | exit 0 |
| `model-floor`, `deny-hang-shapes` | user | silent exit 0, plus step-aside | `UO` = user fail-open + step-aside | exit 0 |
| `bash-output-guard`, `post-edit-build`, `enforce-agent-contract` (SubagentStop, **the stop gate**), `retro-ledger`, `retro-brief` | templates, root | unwrapped: bash 127, **non-blocking** | `U` = unwrapped (`exec bash`) | non-blocking error |
| `bash-output-guard` | user | unwrapped, non-blocking | `UU` = user unwrapped + step-aside | non-blocking error |
| `verify-hooks` (new, Task 9) | templates, user | — | `U` / `UU` | non-blocking |
| UserPromptSubmit `date`, PreCompact `echo` | user, templates | inline | **unchanged** (check 62 pins the date hook) | — |

**Allow hooks.** No allow hook ships today. `allow-ctx-plan.sh` was removed in v2.0 PR3 (`settings-reference.md`). Check 71 records the rule anyway: a hook that can emit `permissionDecision: "allow"` is registered `U`/`UU`, never `F`/`UF`, because a 127-to-2 wrap would turn its absence into a block. The stop gate (`enforce-agent-contract`) stays `U`.

### Exact registration strings (copy them; checks 70/71 and the fixtures grep for them)

`X` is the hook's basename without `.sh`. `<MSG>` is the hook's **current** offline phrase, kept per hook (`enforcement offline`, `secrets protection offline`, `CLAUDE.md protection offline`, `Read size gate offline`, `delegation enforcement offline`, `tool-call budget offline`). The JSON escaping shown is what goes in the file.

- **F** (project fail-closed):
  `"command": "f=\"${CLAUDE_PROJECT_DIR:-.}/hooks/X.sh\"; [ -r \"$f\" ] || { echo \"HOOK SCRIPT MISSING: $f -- <MSG>. Check that hooks/ exists at the project root.\" >&2; exit 2; }; exec bash \"$f\""`
- **W** (project fail-open WARN):
  `"command": "f=\"${CLAUDE_PROJECT_DIR:-.}/hooks/X.sh\"; [ -r \"$f\" ] || { echo \"WARN: $f missing -- <MSG>. Check that hooks/ exists at the project root.\" >&2; exit 0; }; exec bash \"$f\""`
- **O** (project fail-open silent):
  `"command": "f=\"${CLAUDE_PROJECT_DIR:-.}/hooks/X.sh\"; [ -r \"$f\" ] || exit 0; exec bash \"$f\""`
- **U** (project unwrapped):
  `"command": "exec bash \"${CLAUDE_PROJECT_DIR:-.}/hooks/X.sh\""`
- **User-level** (exec form). In `user-level-reference/settings.json` the program is the literal token `@BASH@` and the hook directory is `@HOOKS@`. `render-user-hooks.sh` substitutes both (Task 8):
  `{"type": "command", "command": "@BASH@", "args": ["-c", "<SA_X><TAIL>", "@HOOKS@/X.sh"]}`
  - `<SA_X>` (C5 step-aside; empty for `verify-hooks`, which has its own rule, see Task 9):
    `p=${CLAUDE_PROJECT_DIR:-.}; if [ -f \"$p/hooks/X.sh\" ] && [ -r \"$p/.claude/settings.json\" ]; then IFS= read -r -d '' s < \"$p/.claude/settings.json\"; case $s in *'}/hooks/X.sh'*) exit 0 ;; esac; fi; unset p s; `
  - `<TAIL>` for **UF**: `[ -r \"$0\" ] || { echo \"HOOK SCRIPT MISSING: $0 -- <MSG>.\" >&2; exit 2; }; . \"$0\"`
  - `<TAIL>` for **UO**: `[ -r \"$0\" ] || exit 0; . \"$0\"`
  - `<TAIL>` for **UU**: `. \"$0\"`
- **Fail-closed hook trap.** This is the first executable line, directly after the header comment, of each hook marked F/UF: `pre-commit-test`, `no-push-main`, `gate-before-merge`, `deny-secret-reads`, `deny-claude-md-writes`, `require-skills-block`.
  `trap '[ "$?" = 127 ] && exit 2' EXIT   # v4.4.0 C2: the old registration wrapper's 127->2, now in-hook (exec/source forms cannot wrap)`

Why `'}/hooks/X.sh'`: the template form spells the path `${CLAUDE_PROJECT_DIR:-.}/hooks/X.sh`, so the `}` anchors the match to a **project** registration. The user-level rendered path (`…/.claude/hooks/X.sh`) cannot match it. That matters when a session's project dir is `$HOME`.

## Decisions needed (the user decides; the plan proceeds on the recommendation)

- **D1 — the project-template form (P3).** The six variant `settings.json` files are committed, byte-identical, machine-independent, and replaced **wholesale** by the sync server (template ownership class). So they cannot carry an absolute Git Bash path, and a `setup-project` rewrite would be undone at the next sync.
  - **(a) Recommended: shell form + `exec bash` (strings F/W/O/U above).** It is machine-independent. The `sh` on Linux and macOS (dash, measured here) only runs `[ -r ]` and `exec`, so no bash-isms are needed. On Linux it is one PID per hook, down from two; the probe measured 2 fewer forks and 1 fewer exec per hook. On Windows, Claude Code runs the string in Git Bash. MSYS2 emulates `exec` by starting a new Windows process, so it **saves the fork** (the expensive Cygwin operation) but may not save the process slot. **To verify on Windows at release** (Task 13).
  - **(b) Exec form with a bare `"command": "bash"`.** That is one process, in place. The docs say exec form resolves `command` through PATH. On Windows, `C:\Windows\System32\bash.exe` (the WSL launcher) usually comes before Git's `usr\bin` on PATH. WSL bash without a distro exits non-zero but not 2, so **every protection would fail open**. Rejected unless a Windows probe proves PATH resolution inside Claude Code reaches Git Bash. Even then, a user PATH change would silently re-open the hole.
  - **(c) Unchanged project registrations.** This has zero risk, but toolkit projects keep two shells per project hook. C3–C5 still apply.
  - Cost per Bash call in a toolkit project (about 9 project hook entries): (a) about 9 forks fewer than today on Linux, Windows to be measured; (b) about 9 processes fewer, but fails open on a WSL PATH; (c) 0.
- **D2 — the user-level form.** The spec and the amendment say exec form with the absolute Git Bash path written by setup. Today neither setup script writes `~/.claude/settings.json`: the reference is copied by hand, and the setup scripts print snippets. The plan therefore adds `scripts/render-user-hooks.sh` (print or `--write` with a backup) rather than giving setup a new job. The alternative is the D1(a) shell form with `$HOME` at user level too. It needs no render script, but it is not the exec form the user approved. **Recommendation: follow the spec (exec form + render script).**
- **D3 — C5 registration check (a refinement of spec C5).** The spec's step-aside is `[ -f "$CLAUDE_PROJECT_DIR/hooks/x.sh" ]`. That is a **gate bypass** wherever a project ships the file but does not register it. This very repo is an example: its root `.claude/settings.json` registers neither `deny-secret-reads` nor `bash-output-guard`, but `hooks/` carries both. The plan adds a builtin read of `.claude/settings.json` (no fork; probe P2-c). The global steps aside only when the file exists **and** a `}/hooks/X.sh` registration is present. **Recommendation: accept.** The same rule is applied to `deny-hang-shapes` and `model-floor`, whose step-aside today is file-only. For them it can only make the global run **more** often.
- **D4 — consistency check numbers 70/71** (see Global Constraints).

## Plan-level refinements of the spec

- **R-1 (amendment, exit codes).** Probe P1 shows that `bash -c '[ -r "$0" ] || …; . "$0"' x.sh` gives the same exit code as `bash x.sh` for `exit 0/2/7`, a falling-through failing command, an `exit` inside a function, a syntax error (2 in both cases), stdin of 200 kB, `$0`/`BASH_SOURCE`/`dirname "$0"`/lib sourcing, `set -euo pipefail` with a trap, and functions. **Two differences:** (i) a top-level `return` ends a sourced script with its status, while `bash x.sh` prints an error and continues; (ii) a `set -u` abort exits 127 under `-c` and 1 as a script. Task 2 proves that neither shape exists in a registered hook. Check 71 then pins "no top-level `return`" for the hooks that are sourced (user-level `UF`/`UO`/`UU`). (ii) only affects `set -u` hooks (`agent-budget-warn`, `post-edit-build`, `retro-*`). None is sourced: they are project-only `W`/`U` and run through `exec bash`. So the `exec bash "$0"` fallback is not needed.
- **R-2 (the 127 mapping).** The old wrapper turned **any** 127 into a block. That includes a hook whose last command was not found, not only a missing script. Neither new form can wrap the script's exit, so the mapping moves into the hook as an EXIT trap. Probe P1-g shows it reproduces the old wrapper for six shapes. No registered hook sets an EXIT trap (`pre-commit-test` traps only `TERM INT HUP`; `run-gate.sh`'s EXIT trap is not a registered hook), and check 71 pins that. A `$(…)` subshell does not inherit the trap (P1-g, row 5).
- **R-3 (C3 is partly shipped).** v4.3.1 S6b already gave the three git gates one parser run (`json_payload`, through `gc_read_stdin`). Phase C generalises it (`json_fields`) and converts the hooks that still spawn 3–5 runs (P1 count: `deny-secret-reads` 4 node, `deny-hang-shapes` 4, plus `model-floor`, `require-skills-block` and `deny-claude-md-writes`). The node-only hooks (`bash-output-guard`, `enforce-delegation`, `read-size-gate`, `retro-*`, `enforce-agent-contract`) keep `json_require_node`. Their saving is C4's early exit, not C3.
- **R-4 (C4 placement).** Early exits that run **before** parsing are allowed only in hooks whose unparseable-payload branch already exits 0 (`deny-hang-shapes`, `bash-output-guard`). In a fail-closed hook, an invalid payload must still block, so its early exit runs **after** the one parser call and before the expensive library or pipelines (`no-push-main`, `gate-before-merge`, `deny-secret-reads`). `pre-commit-test`'s fast path belongs to v4.3.2 F1/F2 and is **not** touched here.
- **R-5 (sync server).** `server/src/template_sync` treats `.claude/settings.json` as a whole-file template blob (`v3.apply_file_v3`, template branch: a wholesale write, and a LOCAL_EDITED file is backed up first; `mcp._three_way_merge`: line-level, JSON-unaware). No hook-aware merge exists, so a changed `command` string reaches consumers as a replacement and never as a duplicate. The risk is the reverse: a template that **drops** a matcher group silently removes that gate from every consumer. Check 71 freezes the (event, matcher, script, form) set of every registration, so a removal goes red. Task 11 adds server tests for the replacement and the three-way paths. The sync-template skill extracts hook paths by **path** (its rule 1b), so it is form-agnostic.

## Review Focus

1. **Polarity.** Every row of the polarity table, checked against the strings in the diff: F/UF exit 2 when missing, W/O/UO exit 0, U/UU non-blocking. The stop gate is never wrapped, and no allow-capable hook is wrapped.
2. **Zero new allows.** Every early exit (Tasks 5–7) is a provable superset of the slow path's refusals, and the equivalence corpus is green in all three parser configurations.
3. **C5 bypass.** A project that ships but does not register a hook keeps the global check (this repo is the fixture).
4. **Exec-form semantics.** Sourcing in place changes nothing a hook can observe (R-1). The trap reproduces 127→2 (R-2).
5. **Parser parity.** `json_fields` gives byte-identical fields and verdicts across node, python3 and jq, including escapes, NUL, a BOM, non-ASCII, `null`/`false`, and multiple documents.

---

### Task 0: Base, worktree and harness (controller)

**Files:** none tracked.

- [ ] **Step 1.** The controller names `WT` and the base commit (`PHASEC_BASE`, the integration tip before Task 1) and writes both into `$WT/.superpowers/sdd/2026-10-04-hook-slimming/base.txt`. Run `git -C $WT log --oneline -1`.
- [ ] **Step 2.** Copy `run-block.sh`/`run-in.sh` (Global Constraints) and set `VER="${3:-v4.4.0}"`.
- [ ] **Step 3.** Confirm the check numbers: `grep -n '^# Check 6[5-9]\|^# Check 7[0-9]' $WT/scripts/verify-template-consistency.sh`. 70 and 71 must be absent. If v4.3.2 or Jev used them, take the next two free numbers and replace `70`/`71`/`c70_`/`c71_` throughout this plan's tasks.
- [ ] **Step 4.** Check that the files this plan touches are where it expects them: `grep -n '^json_payload()\|^json_read_payload()' $WT/hooks/lib/json.sh` and `grep -n '^gc_read_stdin()' $WT/hooks/lib/git-cmd.sh` must each print one line.

### Task 1: The equivalence corpus and harness (the safety net, written first)

**Files:**
- Create: `scripts/hook-equivalence.sh`
- Create: `scripts/fixtures/hook-equivalence/corpus.tsv`
- Create: `scripts/fixtures/hook-equivalence/README.md`

**What it does.** The harness runs every corpus payload through the **old** hook set (the hooks and registrations at `PHASEC_BASE`, taken with `git archive`) and the **new** set (the working tree). It does this **as Claude Code would**. It reads each `settings.json`, keeps the registrations whose event and matcher apply to the payload, and runs each one in its own form:
- Shell form: `sh -c "<command>"`.
- Exec form: `"<command>" "<args>…"`, with `${CLAUDE_PROJECT_DIR}` substituted as a plain string and `@BASH@`/`@HOOKS@` rendered as Task 8 renders them.

Each payload's results are merged the way Claude Code merges them: deny > ask > context > allow.
- **Decision class:** `deny` (exit 2, or JSON `permissionDecision: "deny"` / `decision: "block"`); `ask`; `context` (exit 0 with `additionalContext` or other non-empty stdout on PostToolUse/SessionStart); `error` (another non-zero exit); `allow`.
- **Reason category:** the **set** of hook names that denied. It is a set because C5 removes duplicate runs. Each name is the first token after `BLOCKED: `/`HOOK SCRIPT MISSING: `, normalised to the hook basename.

**Scenarios** (each payload runs in all three):
- **S1, plain project:** `CLAUDE_PROJECT_DIR` is a temp git repo with no `hooks/`; user-level hooks only.
- **S2, toolkit project:** a temp project bootstrapped by `setup-project.sh --variant general`, plus user-level hooks.
- **S3, this repo:** the repo's own root `.claude/settings.json`, which registers only some hooks. This is the C5 bypass fixture.

**Parser configurations:** `full`, `python3-only`, `jq-only`. The hooks run with `PATH` restricted the way `scripts/test-hooks-parser-matrix.sh` restricts it (reuse its shim-directory function by copying the function body; do not source the matrix script). The harness itself uses python3 to read `settings.json`, outside the restricted PATH.

**Missing-script rows** run each scenario once more with every **protection** script renamed away (old and new alike). They prove that F/UF blocks, W/O/UO allow and U/UU give `error`, identically.

- [ ] **Step 1: Corpus (≥ 80 rows; tab-separated `id<TAB>event<TAB>tool<TAB>payload-json`).** It must contain at least these rows (the ids are the contract):
  - **Bash push and branch, 18 rows:** `git push origin main`, `git push origin HEAD:main`, `git push -f origin master`, `git push origin :main`, `git push --delete origin main`, `git -C /x push origin main`, `GIT_DIR=x git push origin main`, `git.exe push origin main`, `"git" push origin main`, `cd /repo && git push`, `ls; git push origin main`, `bash push.sh` (a script that pushes main, created in the scenario), `sh ./push.sh`, `. ./push.sh`, `git checkout main`, `git switch -c feature`, `git branch -D main`, `gh pr merge 1`.
  - **Commit and merge gate, 6 rows:** `git commit -m x`, `git merge feature`, `git pull --ff-only`, `git pull`, `git status --short`, `git log --grep=commit`.
  - **Secret reads, 14 rows:** Bash `cat .env`, `head -1 ./.env.local`, `sed -n 1p .env.production`, `grep KEY .env`, `cp .env /dev/stdout`, `curl -F f=@.env x`, `cat .e*v`, `source .env`, `. .env`, `cat .env.example` (allowed), `cat .environment` (allowed); Read `.env`, Read `config/.env.staging`, Read `README.md`.
  - **Hang shapes, 8 rows:** `cat > f.txt <<EOF`…, `cat <<'EOF' > f`, `git commit -F- <<EOF` (allowed), `while true; do sleep 5; done`, `sleep 30 && ls`, `cd /x && ls && pwd`, `cd /x && ls` (allowed), `ls <<<"x"` (allowed).
  - **PowerShell, 8 rows:** `git push origin main`, `& git push origin main`, `Get-Content .env`, `gc .env`, `cat .env`, `& .\push.ps1`, `Get-ChildItem`, `git status`.
  - **Agent, 5 rows:** no model with subagent_type `general-purpose`; `model: "sonnet"`; subagent_type `Explore`; a prompt without a skills block; a prompt with one.
  - **Edit/Write, 4 rows:** Write `CLAUDE.md`, Edit `src/a.txt`, Write `docs/plans/x.md`, NotebookEdit `n.ipynb`.
  - **PostToolUse, 4 rows:** a Bash output of 11,999 chars, 12,001 chars, 6,001 four-byte emoji (12,002 UTF-16 units), and 3,000 `\u00e9` escapes.
  - **Escapes and harmless commands, 14 rows:** `ls -la`, `echo "done. ok"`, `npm test`, `pwd`; `\"git\" push origin main` with escaped quotes; `gi\\\nt push origin main` (a backslash-newline continuation); `\u0067it push origin main`; `cat \u002eenv`; a command with a literal TAB and a newline; `echo "Grüße" && git push origin main`; a 20 kB harmless command; empty `command`; a payload that is `null`; truncated JSON.
  - **Malformed and edge, 4 rows:** empty stdin, a BOM-prefixed payload, two concatenated JSON documents, `tool_input.command` given as an array.
- [ ] **Step 2: Harness.** `scripts/hook-equivalence.sh [--base <sha>] [--only <id-glob>] [--config full|python3|jq]`. It prints one line per difference (`DIFF <scenario> <config> <id>: old=<class>{<cats>} new=<class>{<cats>}`) and ends with `EQUIVALENCE: <n> decision changes`. Exit 0 only when n = 0. It also prints a per-class tally so a reader can see that both `deny` and `allow` rows occur. A corpus where everything allows would prove nothing, so the harness **fails** if any scenario/config has fewer than 25 deny rows or fewer than 25 allow rows. `--base` defaults to the sha in `base.txt`.
- [ ] **Step 3: Self-test (RED/GREEN of the harness itself).** (a) Run with new = old (before any Phase C change). It must print `EQUIVALENCE: 0 decision changes`. (b) Control: in a scratch copy, make the new `no-push-main.sh` `exit 0` on its first line. The harness must report ≥ 10 `DIFF` lines and exit non-zero. Record both results in the README.
- [ ] **Step 4.** `bash -n scripts/hook-equivalence.sh`, then a full consistency run. If a census (for example the scripts list in `docs/`) names scripts, add the new one in this commit.
- [ ] **Step 5: Commit** `test(v4.4.0): C-verify -- hook equivalence corpus (old vs new, three parsers)`; paths: the three new files (and any census file).

### Task 2: The in-hook 127 trap, and proof of R-1

**Files:**
- Modify: `hooks/{pre-commit-test,no-push-main,gate-before-merge,deny-secret-reads,deny-claude-md-writes,require-skills-block}.sh` (one line each)
- Mirror: `user-level-reference/hooks/{pre-commit-test,no-push-main,gate-before-merge,deny-secret-reads}.sh` (`cp`)
- Test: `scripts/test-hooks.sh`, new block `C2a`

- [ ] **Step 1: RED.** Block `C2a`. For each of the six hooks:
  - (i) `grep -c '^trap .\[ "\$?" = 127 \] && exit 2. EXIT' <hook>` = 1.
  - (ii) A behavioural row. Build a temp hook from the trap line extracted from the hook (`grep -m1 '^trap ' <hook>`) followed by `nosuch_cct_cmd`. Run it with `bash -c '[ -r "$0" ] || exit 2; . "$0"' <tmp>`. It must exit 2. The same file with `exit 0` must exit 0.
  - (iii) Run `bash <hook>` with an `exit 1` shape that has no 127 (an existing fixture payload) and confirm it is unchanged.
  - `RB C2a` must fail on (i) and (ii).
- [ ] **Step 2.** Add the trap line (exact text in Exact strings) as the first executable line of each hook. `cp` the four mirrored ones, then `cmp`.
- [ ] **Step 3: R-1 audit, recorded in the block as rows.**
  - For every hook in the polarity table, `awk` lists any `return` outside a function body. The expected count is 0 for each. Use the brace-depth awk from the Appendix, P1-f.
  - `grep -l 'trap .* EXIT' hooks/*.sh` must list only the six hooks above.
  - `grep -n '^set -[a-z]*u' hooks/*.sh` must list only `agent-budget-warn`, `post-edit-build`, `retro-brief` and `retro-ledger`, none of which is sourced.
- [ ] **Step 4: GREEN.** `RB C2a` → 0 failed. Regression: `grep -rn 'exit 127\|= 127\|"127"' scripts/test-hooks.sh` lists every fixture that expects a 127. Run each block it names; a fixture expecting a hook's own 127 now sees 2. That is the old registered behaviour, so update the expectation and say so in the commit message. Then run the equivalence run and the full consistency run.
- [ ] **Step 5: Commit** `fix(v4.4.0): C2 -- fail-closed hooks map their own exit 127 to 2 (wrapper semantics in-hook)`.

### Task 3: `json_fields`, one parser run for any field list (C3)

**Files:**
- Modify: `hooks/lib/json.sh` (functions `json_read_payload`, `json_payload`; new `json_fields`). Mirror `user-level-reference/hooks/lib/json.sh`.
- Test: `scripts/test-hooks.sh`, new block `C3`

**Design.** `json_read_payload <backend> <json> [field…]` reads the field list from its argv. With no fields it defaults to `tool_name cwd tool_input.command`, so `json_payload` and `gc_read_stdin` are unchanged. The node, python3 and jq programs loop over the argv list in place of the hard-coded `f = [...]` / `("tool_name", "cwd", "tool_input.command")` / three `rd(...)` calls. jq takes them as `--args` → `$ARGS.positional`.

`json_fields <json> <field>…` contains `json_payload`'s loop: canary, `V`/`I` verdict, the backend fallback order and the `JSON_PARSER` memo. It fills the indexed array `JF` (`JF[0]` = first field) with exactly `json_payload`'s per-field post-processing (NUL removal by the backend, trailing-newline strip). It returns 0 for valid, 1 for invalid (empty included) and 2 for no working parser. `json_payload` becomes `json_fields "$1" tool_name cwd tool_input.command` plus `JP_TOOL=${JF[0]}` and the other two assignments, so there is one implementation.

- [ ] **Step 1: RED.** Block `C3`. For each backend B in node, python3 and jq (force it by setting `JSON_PARSER=B` before the call; a backend that is absent → `skip`, so the matrix's in-band skip counts stay as they are: these rows skip exactly where the existing S6b parity rows skip):
  - Over 14 payloads, `json_fields "$p" tool_name cwd tool_input.command tool_input.file_path tool_input.subagent_type tool_input.model`. The payloads cover a plain one, `\"`, `\\`, `\n`, `\t`, `\u0000`, `\u00e9`, `\ud83d\ude00`, a BOM, `null`, `false`, two documents, an empty string, a number-valued field and an object-valued field.
  - Each result must equal the old per-field `json_valid` + `json_get` answer: rc 0 ⇔ `json_valid` true, each `JF[i]` = `$(json_get "$p" <field>)`. And `json_payload` must be identical to before (`JP_*` vs the same `json_get`s).
  - Also assert one interpreter spawn per `json_fields` call: wrap `node`/`python3`/`jq` in a counting shim on PATH, as the S6b spawn-count rows do.
- [ ] **Step 2.** Implement. Keep the jq `null`/`false`/multi-document verdict exactly as in the current `json_read_payload` jq arm.
- [ ] **Step 3: GREEN.** `RB C3` → 0 failed. Regression: `RB S6b v4.3.1` and every block that names `json_payload` (`grep -n 'json_payload' scripts/test-hooks.sh`). Then `cmp hooks/lib/json.sh user-level-reference/hooks/lib/json.sh`, the equivalence run (all three configs) and the full consistency run.
- [ ] **Step 4: Commit** `perf(v4.4.0): C3 -- json_fields: any field list in one parser run`.

### Task 4: Convert the multi-call hooks to `json_fields` (C3)

**Files:** `hooks/{deny-secret-reads,deny-hang-shapes,model-floor,require-skills-block,deny-claude-md-writes}.sh`; mirrors for the first three. Test: block `C3` (append rows).

**Mapping (polarity preserved exactly).** Each hook keeps its own branches. Only the calls change:
- `json_have || A` + `json_valid "$J" || B` + `X=$(json_get "$J" f)` becomes `json_fields "$J" f1 f2 …; rc=$?`, then `[ "$rc" = 2 ] && A`, `[ "$rc" = 1 ] && B`, `X=${JF[i]}`.
- `deny-secret-reads`: A and B are its two exit-2 BLOCKED blocks (unchanged text). Fields: `tool_name tool_input.file_path tool_input.command`.
- `deny-hang-shapes`: A and B are `exit 0`. Fields: `cwd tool_input.command`.
- `model-floor`: A and B are `exit 0`. Fields: `tool_name tool_input.model tool_input.subagent_type cwd`. Keep its BOM strip and its env checks **before** the parse, as today.
- `require-skills-block`: A is its `json_warn_no_parser … ; exit 0`. Read its current `json_valid` branch and keep it as B. Fields: `tool_name tool_input.prompt tool_input.subagent_type`.
- `deny-claude-md-writes`: payload fields `tool_name tool_input.<field> cwd`. The field depends on the tool, so fetch both `tool_input.file_path` and `tool_input.notebook_path` and pick as today. The manifest-content parse (`DCM_MCONTENT`) stays a separate `json_valid`/`json_get`: it is a different document.

- [ ] **Step 1: RED.** Append spawn-count rows to `C3`: per hook, on one Bash or Read or Agent payload, exactly one interpreter run (counting shim). Today 3–5 → fail.
- [ ] **Step 2.** Convert, one hook at a time. `bash -n` each. `cp` the mirrors and `cmp`.
- [ ] **Step 3: GREEN.** `RB C3`. Regression: every existing block that drives these five hooks (`grep -n 'deny-secret-reads\|deny-hang-shapes\|model-floor\|require-skills-block\|deny-claude-md-writes' scripts/test-hooks.sh | grep '^.*# ----'` lists the block headers). Run each named block. Then the equivalence run (all configs) and the full consistency run.
- [ ] **Step 4: Commit** `perf(v4.4.0): C3 -- five hooks parse their payload once`.

### Task 5: Builtin early exits before parsing, in the fail-open hooks (C4)

**Files:** `hooks/deny-hang-shapes.sh`, `hooks/bash-output-guard.sh`; mirrors. Test: new block `C4`.

**deny-hang-shapes** (advisory; it already exits 0 on any doubt, so a pre-parse exit adds no allow). Directly after the lib is sourced, replace `DH_JSON=$(cat)` with the same read, then:

```bash
# v4.4.0 C4: every refusal needs `<<`, `sleep` or a leading `cd` in the DECODED
# command. Without a backslash in the raw payload, decoded == raw for those
# substrings (no \uXXXX, no \n, no continuation), so their absence here is final.
# Over-matches on purpose: any backslash, any case of SLEEP or CD, continues.
shopt -s nocasematch
case "$DH_JSON" in *'\'*|*'<<'*|*sleep*|*cd*) ;; *) exit 0 ;; esac
shopt -u nocasematch
```

Before writing it, the implementer reads `dh_norm` and the three shape tests and confirms that every refusal path needs one of those substrings **in the decoded command**. If a fourth shape exists on the integration branch, add its literal and say so.

**bash-output-guard.** Directly after `TOOL_INPUT=$(cat)`, add:

```bash
# v4.4.0 C4: the engine truncates only when the output string is longer than
# THRESHOLD UTF-16 units. Each unit costs at least one byte of the JSON text
# (BMP: 1-3 bytes, or 2-6 escaped; astral: 4 bytes or 12 escaped for 2 units),
# so a payload of <= THRESHOLD bytes cannot hold such an output.
_bog_lc=${LC_ALL-}; LC_ALL=C; _bog_n=${#TOOL_INPUT}; LC_ALL=$_bog_lc
[ "$_bog_n" -le "$THRESHOLD" ] && exit 0
```

(Restore `LC_ALL`: if it was unset, keep it unset. Use `${LC_ALL+x}` to tell the cases apart.) Before writing it, the implementer reads the embedded node program and confirms that the **only** stdout-producing path is the `out.length > threshold` branch, and lists the fields it measures. If the program concatenates several fields (stdout and stderr, for example), the bound still holds, because all of them are inside the payload. Note it in the comment.

- [ ] **Step 1: RED.** Block `C4`:
  - Spawn-count rows: `deny-hang-shapes` on `ls -la` → 0 interpreter runs (today 4); `bash-output-guard` on an 11,999-char output → 0 node runs (today 2).
  - Decision rows, with the expected codes taken from the old hooks: the 8 hang-shape corpus rows, plus `SLEEP 5; while :; do :; done` and `\u003c\u003cEOF`; outputs of 12,001 chars, 6,001 emoji and 3,000 `\u00e9`.
- [ ] **Step 2.** Implement both. Mirrors: `cp` and `cmp`.
- [ ] **Step 3: GREEN.** `RB C4`, then the existing `deny-hang-shapes` and `bash-output-guard` blocks, then the equivalence run (all configs) and the full consistency run.
- [ ] **Step 4: Commit** `perf(v4.4.0): C4 -- builtin early exits for deny-hang-shapes and bash-output-guard`.

### Task 6: Early exit in `deny-secret-reads`, after its one parse (C4)

**Files:** `hooks/deny-secret-reads.sh` + mirror. Test: block `C4` (append).

The early exit sits **after** `json_fields` and its two BLOCKED branches (an unparseable payload still blocks). It sits **before** the `tr` token pipelines, in the `Bash|PowerShell)` arm only. The `Read)` arm is already cheap.

```bash
# v4.4.0 C4: a Bash/PowerShell refusal needs a token dsr_is_secret accepts --
# `.env…` or a `.e` glob (`.e*`, `.e?v`, `.[e]nv`) -- after quote stripping and
# continuation joining. Quote stripping deletes characters, so in the RAW command
# such a token still shows `.e`/`.E`, `.[`, `.?` or `.*`, or `env` split by
# quotes. A backslash, `$` or backtick can build any of them, so those continue too.
shopt -s nocasematch
case "$DSR_CMD" in
  *'.e'*|*'.['*|*'.?'*|*'.*'*|*env*|*'\'*|*'$'*|*'`'*) ;;
  *) shopt -u nocasematch; exit 0 ;;
esac
shopt -u nocasematch
```

Before writing it, the implementer reads `dsr_is_secret`, `DSR_SECRET_RE`, the argument loop and every other deny path in the arm (the transmit verbs, the copy to a std stream, `source`/`.`), and lists the token shapes each one can deny. The predicate must contain a literal for each shape. If a deny path does not need a secret-shaped token, there is no early exit for it: drop the exit and report back.

- [ ] **Step 1: RED.** Append to `C4`: a spawn-count row (`ls -la` via Bash → 0 `tr` runs; today 3+), and decision rows for all 14 secret corpus rows plus `cat ".e"nv`, `cat .\env`, `cat $HOME/.env`, `cat .ENV`.
- [ ] **Step 2–3.** Implement, then the GREEN runs and regressions as in Task 5.
- [ ] **Step 4: Commit** `perf(v4.4.0): C4 -- deny-secret-reads skips its token walk when no secret shape can occur`.

### Task 7: Early exit in `no-push-main` and `gate-before-merge`, before `git-cmd.sh` (C4)

**Files:** `hooks/no-push-main.sh`, `hooks/gate-before-merge.sh`, `hooks/lib/git-cmd.sh` (function `gc_read_stdin` only); mirrors. Test: block `C4` (append). **Shared with v4.3.2:** re-read `gc_read_stdin` and both hooks' heads on the integration branch first. v4.3.2's design left exactly this out ("a verb pre-filter for no-push-main and gate-before-merge … candidate for later").

**Design (one parse, unchanged polarity).**
- `gc_read_stdin` gains a pre-parsed entry. If `GC_PREPARSED` is set (its value is `json_payload`'s rc), it skips `GC_JSON=$(cat)` and `json_payload` and continues from `gc_rc=$GC_PREPARSED`. All its refusal branches (rc 2, rc ≠ 0) stay as they are.
- Each hook's head becomes:
  1. The trap (Task 2).
  2. Source `lib/json.sh` (`[ -f ] || BLOCKED exit 2`, the same message shape as the git-cmd lib check).
  3. `GC_JSON=$(cat)`; `json_payload "$GC_JSON"`; `GC_PREPARSED=$?`.
  4. The early exit: only when `GC_PREPARSED = 0`, `JP_TOOL` is `Bash` or `PowerShell`, `JP_CMD` is non-empty, and the predicate below finds no candidate.
  5. Otherwise source `git-cmd.sh` and continue exactly as today (`gc_read_stdin` uses the pre-parsed state).
- The guard-off file, the MCP-tool-name case and `gc_cmd_unreadable` all need either an `rc ≠ 0` payload or a non-Bash tool, so the early exit cannot reach past them.
- Predicate (an over-match; derive the final list from the code, see below):

```bash
# v4.4.0 C4: refusal needs a git or gh word in the typed text, or in a script body
# gc_collect_bodies reads (a runner word, or a path ending .sh/.ps1, or a lone `.`).
# A backslash (continuation, escape) or `$`/backtick may build either, so continue.
shopt -s nocasematch
case "$JP_CMD" in
  *git*|*gh*|*sh*|*source*|*ps1*|*'\'*|*'$'*|*'`'*|.|.' '*|*' .'|*' . '*|*';.'*|*'&.'*|*'|.'*|*'(.'*) ;;
  *) shopt -u nocasematch; exit 0 ;;
esac
shopt -u nocasematch
```

`gate-before-merge` adds its own verbs to the continue list, read from its classifier (`a6_classify_cmd` and its callers): at least `merge`, `pull`, `checkout`, `switch`, `rebase`, `reset`, `cherry-pick` and `gh`. Every one of them needs a `git`/`gh` word anyway; add them only if the reading shows a path that does not.

Before writing it, the implementer lists every recogniser in `gc_collect_bodies`, `gc_script_body`, `gc_seg_is_ps` and `gc_dir_rule` (on the integration branch) and maps each to a predicate literal. A recogniser with no literal is a bug in the predicate. In particular, check whether a bare `./x.sh`, `x.cmd`, `python x.py` or `node x.js` is ever scanned. If one is, add `.sh`, `.cmd`, `py`, `js` or whatever its literal is.

- [ ] **Step 1: RED.** Append to `C4`:
  - Spawn-count rows: `ls -la` → `git-cmd.sh` not sourced. Assert it with a temp hooks copy whose `lib/git-cmd.sh` begins with `echo SOURCED >&2`, and expect no `SOURCED`. And exactly one parser run. `git status` must still be sourced.
  - Decision rows: all 24 push/commit/merge corpus rows, both hooks, plus `GiT push origin main`, `x=1;. ./p.sh`, `(.  ./p.sh)`, `echo|sh`, `pwsh -File p.ps1`, a truncated payload (must still block: rc 1), an empty payload (block), and the no-parser configuration (block).
- [ ] **Step 2.** Implement `gc_read_stdin`'s pre-parsed entry first and run every existing `gc_read_stdin` fixture block. Then the two hook heads. Mirror `lib/git-cmd.sh`, `no-push-main.sh` and `gate-before-merge.sh`, then `cmp`.
- [ ] **Step 3: GREEN.** `RB C4`. Regressions: the v4.3.1 G1–G6, S6, S6b blocks and the v4.3.2 V1 and V2 blocks (`grep -n '^# ---- v4.3.[12] ' scripts/test-hooks.sh`), every block naming `no-push-main` or `gate-before-merge`, then the equivalence run (all configs) and the full consistency run.
- [ ] **Step 4: Commit** `perf(v4.4.0): C4 -- git gates exit before sourcing git-cmd.sh when no git, gh or script word can occur`.

### Task 8: Register user-level hooks in exec form (C1, user level), with the render script

**Files:**
- Modify: `user-level-reference/settings.json` (the `hooks` block only), `user-level-reference/settings-reference.md` (the hooks section)
- Create: `scripts/render-user-hooks.sh`
- Modify: `setup-project.sh`, `setup-project.ps1` (one *Next step* line each)
- Test: new block `C1`

**Reference entries.** These are the UF/UO/UU strings from *Exact strings*, with `@BASH@`/`@HOOKS@`:
- PreToolUse `Bash|PowerShell`: `no-push-main` UF.
- `Read|Bash`: `deny-secret-reads` UF.
- `Bash`: `deny-hang-shapes` UO.
- `Agent`: `model-floor` UO.
- PostToolUse `Bash|PowerShell`: `bash-output-guard` UU.
- SessionStart: `verify-hooks` UU (added in Task 9; leave a slot).

The matchers are unchanged. UserPromptSubmit `date` is **unchanged** (check 62).

**`render-user-hooks.sh [--print|--write] [--settings <path>]`** (default `--print`; default settings `$HOME/.claude/settings.json`):
- `BASH_EXE`: on `MINGW*|MSYS*|CYGWIN*`, `cygpath -m /usr/bin/bash` (for example `C:/Program Files/Git/usr/bin/bash.exe`). **Never** `bin/bash.exe`: Git's `bin\bash.exe` is a launcher that starts `usr\bin\bash.exe` as a second process. Elsewhere, `command -v bash`, made absolute. The script refuses (exit 1) if the path does not exist or ends in `System32/bash.exe`.
- `HOOKS_DIR`: `$HOME/.claude/hooks` (`cygpath -m` on Windows).
- Substitute into the reference's `hooks` value. Escape the strings for JSON with the same parser chain as `json.sh` (node → python3 → jq). With none of them, refuse.
- `--print` writes the rendered `hooks` object to stdout.
- `--write` does three things. It copies the live file to `settings.json.bak-<UTC yyyymmddThhmmssZ>`. It replaces **only** the top-level `hooks` key (every other key stays byte-for-byte equivalent as JSON). Then it re-reads the file and checks that every `args[2]` path exists. If the live file does not parse, it refuses. This is the spec §7 back-out: restore the `.bak`.
- On `--write`, also check that the `hooks` keys this toolkit does not own are not dropped. A live `hooks` entry whose command names no `@HOOKS@` path, for example agent-dashboard's `pressure-gate.sh`, is **kept**: render merges by (event, matcher), appends foreign entries after the toolkit's, and prints `kept foreign hook: <command>`.

**Setup scripts.** After the summary, each prints `Next step (user-level hooks, once per machine): bash <toolkit>/scripts/render-user-hooks.sh --write`. They do not run it: setup has never written user settings, and writing them is the user's call.

- [ ] **Step 1: RED.** Block `C1`, all with `HOME` set to a temp dir holding a copy of `user-level-reference/hooks`:
  - (a) `--print` output parses, and contains no `@BASH@`/`@HOOKS@` and no `~`.
  - (b) For each user entry, run the rendered argv exactly (exec, no shell) with a deny payload and an allow payload. The exit codes must equal the old shell-form registration's under `sh -c`.
  - (c) With the script renamed away: UF exits 2 with `HOOK SCRIPT MISSING`; UO exits 0; UU is non-zero but not 2.
  - (d) `--write` on a temp settings file holding an extra key and a foreign `pressure-gate` hook: the backup exists, the extra key and the foreign hook survive, and re-running is idempotent (same bytes on the second run).
  - (e) A refusal when `BASH_EXE` resolves to a `System32/bash.exe` stub. Use a PATH shim and an `OSTYPE` override hook in the script, `RUH_TEST_BASH`.
- [ ] **Step 2.** Implement the reference change, the script and the two setup lines. Update `settings-reference.md`'s hooks section: the exec form, why the args are absolute (`~` is not expanded in exec form), the render step, and the polarity table rows for the user level.
- [ ] **Step 3: GREEN.** `RB C1`. Regressions: check 60 and check 62 (full consistency run). Bootstrap fixtures: `scripts/test-setup-project.sh` runs as consistency check 27, so the full consistency run covers it. Then the equivalence run.
- [ ] **Step 4: Commit** `feat(v4.4.0): C1 -- user-level hooks in exec form, rendered with absolute paths`.

### Task 9: SessionStart verification hook and doctor check 70 (C2 items 1–2)

**Files:**
- Create: `hooks/verify-hooks.sh`, mirrored as `user-level-reference/hooks/verify-hooks.sh`
- Modify: `templates/*/.claude/settings.json` (SessionStart: add `verify-hooks` U after `retro-brief`), `user-level-reference/settings.json` (SessionStart `verify-hooks` UU, with its own step-aside: exit 0 when the project registers `}/hooks/verify-hooks.sh`), `scripts/verify-template-consistency.sh` (check 70), `scripts/verify-user-level-drift.sh`
- Test: new block `C2b`

**`verify-hooks.sh [--report]`.** Fail-open: a diagnostic never blocks.
- Inputs: `$HOME/.claude/settings.json`, `$CLAUDE_PROJECT_DIR/.claude/settings.json` and `…/settings.local.json`, those that exist.
- Collect every hook script path with one `grep -oE` per file, over-collecting by path exactly as sync-template rule 1b does: `[^"[:space:]]*hooks/[A-Za-z0-9_.-]+\.sh`. Resolve `${CLAUDE_PROJECT_DIR:-.}`, `${CLAUDE_PROJECT_DIR}`, `$HOME` and `~`. Rendered absolute paths stay as they are. Drop `hooks/run-gate.sh` (a permission pattern, not a registration).
- For each unique path: missing or unreadable → `MISSING`. Otherwise `bash -n` fails → `BROKEN`.
- Default (SessionStart) mode: if anything is wrong, print to stdout (plain text is injected into context) one block:
  `HOOK CHECK FAILED -- <n> registered hook script(s) missing or broken:` / one line per problem / `Tell the user this in your first reply, before anything else. Protections stay fail-closed (a missing protection blocks its tool calls); fix with /sync-template or re-run scripts/render-user-hooks.sh --write.`
  When all is well, print nothing. Always exit 0.
- `--report` mode: the same list on stdout, then exit 1 if there were problems.
- Cost: one `grep` per settings file plus one `bash -n` per script, once per session.

**Check 70 (doctor, repo side).** For every registration in the six variant settings, the root `.claude/settings.json`, every `templates/*/.claude/agents/*.md` frontmatter and `user-level-reference/settings.json` (with `@HOOKS@` → `user-level-reference/hooks`), the named script exists and passes `bash -n`. It also asserts that `verify-hooks.sh --report` against a fixture project with one hook deleted lists that hook and exits 1. That last part is the control, so the check is not green by construction.

**Live side (the delivery probe).** `verify-user-level-drift.sh` gains a key-scoped section with two parts. (1) Run `bash ~/.claude/hooks/verify-hooks.sh --report` with `CLAUDE_PROJECT_DIR` unset; each problem is one drift. (2) Compare the live `hooks` object, minus foreign entries, to `render-user-hooks.sh --print`; a difference is one drift, naming the event and matcher. This is how "a release is not done until 0 drift" covers the new registrations.

- [ ] **Step 1: RED.** Block `C2b`:
  - A temp HOME and project with all hooks present → no output, exit 0.
  - One protection script deleted → the block names it, still exit 0, and `--report` exits 1.
  - A script with a syntax error → `BROKEN`.
  - A rendered user path with spaces (`C:/Program Files/...` style under a temp dir with a space) is resolved.
  - `run-gate.sh` in permissions is not reported.
- [ ] **Step 2.** Implement the hook and its mirror (`cmp`), the registrations (templates: edit `general`, `cp` ×5, `md5sum` all six), check 70 and the drift-script section.
- [ ] **Step 3: GREEN.** `RB C2b`. Full consistency run (check 70 PASS; the control row FAILs as designed inside the check). `RI bash scripts/verify-user-level-drift.sh` against a temp `DRIFT_LIVE_*` root rendered from the branch → 0 drift. Equivalence run (SessionStart rows: class `allow`/`context` unchanged when healthy).
- [ ] **Step 4: Commit** `feat(v4.4.0): C2 -- SessionStart hook verification and doctor check 70`.

### Task 10: Project registrations in the new forms, C5 step-aside, check 71 (C1 project, C5)

**Files:**
- Modify: `templates/general/.claude/settings.json`, then `cp` to the other five; root `.claude/settings.json`; `templates/general/.claude/agents/coder.md` (frontmatter `gate-before-merge` → F), then the variant copies of `coder.md`
- Modify: `user-level-reference/settings.json` (add `<SA_X>` to the five user entries, if Task 8 left it out), `scripts/verify-template-consistency.sh` (update section 13's path extraction if needed, section 24's `ABS_FORM` census, section 21c-3e and check 64's adjacency; add check 71)
- Test: new block `C5`

**D1 applies.** If the user chose D1(c), skip the template string changes, but still add check 71 and the C5 step-aside. If the user chose D1(b), use `"command": "bash", "args": ["-c", "<tail with $0>", "${CLAUDE_PROJECT_DIR}/hooks/X.sh"]` with the same polarity tails as UF/UO/UU and no step-aside.

**Strings.** F/W/O/U exactly as in *Exact strings*, row by row from the polarity table. `pre-commit-test` keeps `"timeout": 3360` on the line directly after its command (check 64's `grep -A1`). Matcher groups, their order and their membership stay unchanged.

**Consistency updates** (each one an existing assertion re-aimed, not deleted):
- Section 24: `ABS_FORM` becomes the set {F, W, O, U} prefixes (`f=\"${CLAUDE_PROJECT_DIR:-.}/hooks/` or `exec bash \"${CLAUDE_PROJECT_DIR:-.}/hooks/`). The count must still equal `hookcmd_total`. `NOFALLBACK_FORM` and the cwd-relative ban stay.
- 21c-3e: `hooks/$gh\.sh.*HOOK SCRIPT MISSING.*exit 2` still matches F (same line), so it should need no change. Confirm it.
- Section 13's `grep -o 'hooks/[A-Za-z0-9_-]*\.sh'` is form-agnostic. Confirm it.

**Check 71 (registration polarity, frozen set).**
- (1) A literal table in the check, `event|matcher|script|form` for every registration in `templates/general`, root and `user-level-reference`, equals the extracted set. **A removed or added matcher group, or a changed form, is red** (R-5).
- (2) Every F/UF hook carries the Task 2 trap line, and no registered hook other than those six has a `trap … EXIT`.
- (3) No hook that can print `"permissionDecision": "allow"` (grep) is registered F/UF.
- (4) `enforce-agent-contract` is U.
- (5) For each C5 hook, the template registers it under a matcher whose alternatives (split on `|`) are a superset of the user-level matcher's. Otherwise stepping aside would drop coverage for a tool.
- (6) Hooks that are sourced (UF/UO/UU) have no top-level `return` (Task 2's awk).
- (7) A control: the same extraction run on a mutated copy (one F turned into W) must go red.

- [ ] **Step 1: RED.** Block `C5`, with a temp HOME holding rendered user hooks:
  - Toolkit-project scenario: on `git push origin main`, `no-push-main` runs once. Count the runs with a temp hooks copy that appends `>>$T/runs` on its first line. Today it runs 2×.
  - Plain project: 1× (the global).
  - **This repo's root settings: `deny-secret-reads` and `bash-output-guard` global copies still run** (the bypass row).
  - A project with `hooks/no-push-main.sh` but no registration: the global runs and refuses.
  - A project with the registration but no file: the global runs.
  - Missing-script rows for F/W/O/U, exactly as the polarity table says.
- [ ] **Step 2.** Edit `templates/general/.claude/settings.json`, `cp` ×5, `md5sum`; root settings; `coder.md` and its copies; the consistency updates; check 71.
- [ ] **Step 3: GREEN.** `RB C5`; `RB C1`; full consistency run (sections 13, 24, 21c-3e, 64, 70, 71 PASS); equivalence run (all scenarios, all configs: `EQUIVALENCE: 0 decision changes`).
- [ ] **Step 4: Commit** `feat(v4.4.0): C1+C5 -- project hooks run in one bash; global copies step aside only for a registered project copy`.

### Task 11: Sync server, settings replacement paths (C1 distribution)

**Files:** `server/tests/test_template_sync_settings_hooks.py` (new). No server source change is expected. If a test fails, stop and report: do not patch the server inside this task.

- [ ] **Step 1.** Tests, using the existing v3 apply fixtures as the pattern (`test_template_sync_v3_apply.py`):
  - (a) An unedited consumer `settings.json` at the old (`PHASEC_BASE`) template content, applied to the new template → the file equals the new template byte-for-byte. No line carries `c=$?; if [ \"$c\" = \"127\" ]`.
  - (b) LOCAL_EDITED (an extra `permissions.allow` line): apply without `backup_dir` refuses; with it, a backup is written and the result equals the template.
  - (c) The `three_way` diff path (`_three_way_merge`) with that local edit → the merged text parses as JSON (`json.loads`), contains every new F string, and contains the local line.
  - (d) The matcher-group set of the result equals the template's. Use the same frozen table as check 71, imported from a small JSON fixture `server/tests/fixtures/hook-registrations-v4.4.0.json`. Check 71 reads the same file, so there is one source of truth: move check 71's table into that fixture in this task and point the check at it.
- [ ] **Step 2.** `RI bash scripts/test-server.sh` → all pass. Full consistency run.
- [ ] **Step 3: Commit** `test(v4.4.0): C1 -- sync replaces settings hook strings wholesale, never duplicates or drops a matcher`.

### Task 12: Measurement on Linux (cost criteria 1–3)

**Files:** `scripts/count-hook-procs.sh` (new; it is the probe's `count.sh` from the Appendix, generalised); `scripts/time-hook.sh` (two arms).

- [ ] **Step 1.** `count-hook-procs.sh [--base <sha>]` runs one simulated Bash call (`git status`, `ls -la`) through **all** registrations that apply, old and new, in scenarios S1 and S2. It counts with `strace -f` (forks without `CLONE_THREAD`, execs, node execs) and skips with a message when `strace` is absent (Windows: there the dashboard counter is used, see Task 13). Output: a table of old, new and ratio per scenario.
- [ ] **Step 2.** `time-hook.sh`: add the arms `git status` and `ls -la` for the user-level `no-push-main`, `deny-secret-reads`, `deny-hang-shapes` and `bash-output-guard`, run through their registrations, with the existing control arm, at `RUNS=10`.
- [ ] **Step 3.** Run both on the final tip (Linux). Record in the CHANGELOG draft (Task 13): processes per Bash call for S1 and S2, old → new; each hook's median ms, old → new; and the control arm's drift. **Acceptance on Linux** is the **ratio** for criteria 1–2 (new ≤ 50 % of old, S1 and S2). The absolute 400 ms of criterion 3 is a Windows target (Task 13).
- [ ] **Step 4: Commit** `test(v4.4.0): C-verify -- process counter and timing arms for the per-call checks`.

### Task 13: CHANGELOG v4.4.0, downstream migration, release-gate steps (controller)

**Files:** `CHANGELOG.md` (the v4.4.0 entry, shared with Jev and v4.3.2: add a **"Faster checks (hook slimming, Phase C)"** section), `docs/architecture.md` / `README.md` (only where they describe hook registration; the context-budget columns belong to the release owner, and Phase C changes none of the always-loaded files' bytes).

- [ ] **Step 1: CHANGELOG lines** (fill the numbers from Task 12 and name the commit):
  - `C1`: hooks start one bash instead of two. User level: exec form, rendered by `scripts/render-user-hooks.sh`. Projects: `exec bash` (D1 as decided).
  - `C2`: a missing protection script still blocks (exit 2). The old wrapper's 127→2 is now in the hook. A new SessionStart `verify-hooks.sh` reports missing or broken scripts. Check 70 is the doctor; the drift script covers the live copy.
  - `C3`: `json_fields`, one parser run per hook (`deny-secret-reads` 4→1, `deny-hang-shapes` 4→1, …).
  - `C4`: builtin early exits (list the four hooks and their predicates in one line each).
  - `C5`: each check runs once in toolkit projects. The global copy steps aside only for a **registered** project copy.
  - Measured: the Task 12 table.
  - Known limits:
    - (a) A project copy older than the global one now runs alone (C5).
    - (b) On Windows, `exec` in the project form may not save the process slot (D1(a)), so read the Windows column.
    - (c) A hook whose path holds a `"` or a newline is not supported by the render script.
    - (d) `disableAllHooks` in a project's local settings is not inspected by the step-aside.
- [ ] **Step 2: Downstream migration (numbered):**
  1. Pull or sync the toolkit.
  2. `bash scripts/render-user-hooks.sh --print` and review it, then `--write`. A backup `~/.claude/settings.json.bak-<ts>` is written; restoring it backs the change out.
  3. Copy `user-level-reference/hooks/` (including the new `verify-hooks.sh` and `lib/`) to `~/.claude/hooks/`, as each release does.
  4. In every toolkit project, run `/sync-template`. `.claude/settings.json` is replaced. A LOCAL_EDITED one is backed up first, so re-apply local lines from the backup.
  5. **Restart every running Claude Code session.** Settings hooks load at session start, and a running session keeps the old strings.
  6. Run `bash scripts/verify-user-level-drift.sh` → 0 drift.
  7. agent-dashboard: its installer switches the `pressure-gate.sh` registration to exec form (spec §7, agent-supervisor's step). `render-user-hooks.sh --write` keeps that foreign entry as it is.
- [ ] **Step 3: Release gate (the user's go-ahead, one at a time):**
  1. The full gate (`bash hooks/run-gate.sh`).
  2. The parser matrix (`bash scripts/test-hooks-parser-matrix.sh`, ~90 min; required because Phase C touches `hooks/lib/json.sh` and node-embedding hooks). C3's new rows skip exactly where the S6b parity rows skip. If a configuration's skip count moves out of band, update the matrix's expected-skip constant **in the same commit as the count**, record the old and new count in the CHANGELOG, and explain which rows moved. A config reporting **zero** skips is a failure, never an improvement (CLAUDE.md).
  3. The equivalence run on the final tip, all configurations.
  4. `bash scripts/verify-user-level-drift.sh` → 0.
- [ ] **Step 4: Measure on Windows at release** (the controller, on the user's machine, in idle Git Bash, 10-run medians, the v4.3.1 protocol):
  - (a) The spec §6 timing harness and the dashboard process counter on one `git status` Bash call, plain and toolkit project, old against new.
  - (b) **D1 verification:** does `exec bash` inside the Git Bash shell form save a Windows process (count `bash.exe` in the dashboard snapshot during one hook)?
  - (c) The exec-form user entries run with no shell parent.
  - (d) A deliberately missing `no-push-main.sh` blocks a Bash call (exit 2, message shown).
  - Targets: criterion 1–2 ≤ 50 % of today's processes; criterion 3 slowest hook ≤ 400 ms; criterion 4 equivalence 0; criterion 5 the missing-script row blocks. A miss is reported with its number. It is not waived.
- [ ] **Step 5: Commit** `docs(v4.4.0): CHANGELOG -- faster checks (hook slimming Phase C), downstream migration`.

---

## Appendix: probes run for this plan (Linux, 2026-10-04, at `8c118a8` = `feat/v4.3.1` + spec)

Environment: Linux 6.18, `GNU bash 5.2.21`, `/bin/sh` → `dash`, node v22.22.0, Python 3.11.15, jq 1.7, strace present. Scratch files lived in the session scratchpad. Anything Windows-only is labelled **to verify on Windows at release**.

### P1: exec-form semantics of the amendment's wrapper

Wrapper `W='[ -r "$0" ] || { echo "HOOK SCRIPT MISSING: $0 -- enforcement offline" >&2; exit 2; }; . "$0"'`. Each case compares `printf '%s' "$in" | bash "$f"` with `printf '%s' "$in" | bash -c "$W" "$f"`:

| Case | Script | `bash x.sh` | `bash -c W x.sh` |
|---|---|---|---|
| a | missing file | — | **2**, message on stderr |
| b | `exit 0` / `exit 2` / `exit 7` / `true; false` | 0 / 2 / 7 / 1 | 0 / 2 / 7 / 1 |
| c | `x=$(cat)` on a 200,008-byte payload | len 200008 | len 200008 |
| d | prints `$0`, `BASH_SOURCE[0]`, `dirname "$0"`, sources `$(dirname "$0")/lib/l.sh` | the path, the path, the dir, `lib=ok` | identical |
| e | `set -euo pipefail`, an EXIT trap, a function returning 3, `false` | 1, trap ran, `f=3` | identical |
| e2 | `set -u; echo "$undefined_var"` | **1** | **127** (both non-blocking; see R-1) |
| f | top-level `return 5` between two echoes | **0**: error, then "after" | **5**: stops after "before" (see R-1) |
| g | `$#`, `$1` | `n=0 one=` | identical |
| h | `exit 2` inside a function | 2 | 2 |
| i | `exit 2` inside a pipeline subshell | 0 (`rc=2` printed) | identical |
| j | syntax error on line 2 | 2 | 2 |
| k | `FUNCNAME`, `BASH_SOURCE[1]`, `LINENO` | empty, none, 1 | identical |
| l | path is a directory | (bash: 126) | `.`: is a directory → 1 (both non-blocking) |

Top-level-`return` audit command (no hits at `8c118a8`):
`awk 'FNR==1{d=0} /^[a-zA-Z_][a-zA-Z0-9_]*\(\) *\{|^function /{d=1} /^\}/{d=0} !d && /^[[:space:]]*return\b/{print FILENAME":"FNR": "$0}' hooks/*.sh hooks/lib/*.sh`.

EXIT-trap audit: `grep -n "trap" hooks/*.sh`. Only `pre-commit-test.sh` traps (TERM INT HUP), and `run-gate.sh` (EXIT, not a registered hook). `set -u` hooks: `agent-budget-warn`, `post-edit-build`, `retro-brief`, `retro-ledger`.

**P1-g: the in-hook 127 trap.** The script starts with `trap '[ $? = 127 ] && exit 2' EXIT`. Results are old wrapper (`bash "$0"; c=$?; [ $c = 127 ] && exit 2; exit $c`) / trap + `bash x.sh` / trap + `bash -c W`:

| Body | Old | Trap + script | Trap + source |
|---|---|---|---|
| `nosuchcmd_xyz` | 2 | 2 | 2 |
| `echo ok; exit 0` | 0 | 0 | 0 |
| `exit 2` | 2 | 2 | 2 |
| `true; false` | 1 | 1 | 1 |
| `x=$(nosuchcmd_xyz); echo sub` | 0 | 0 | 0 |
| `f(){ nosuchcmd_xyz; }; f` | 2 | 2 | 2 |

Conclusion: the amendment's `. "$0"` form holds. The `exec bash "$0"` fallback is not needed (R-1, R-2).

### P2: project hooks and `${CLAUDE_PROJECT_DIR}`

- Exec form `args` are not shell-expanded. Per the Claude Code hooks reference (code.claude.com/docs/en/hooks), exec form substitutes **path placeholders such as `${CLAUDE_PROJECT_DIR}` as plain strings**, and special characters pass through verbatim. `~` is not expanded. So in D1(b), the hook path could be `args[2]` = `${CLAUDE_PROJECT_DIR}/hooks/X.sh`, and `$0` would be the real path (simulated: `bash -c "$W" "$S/proj/hooks/x.sh"` → `$0`, `BASH_SOURCE`, `dirname` and lib sourcing all resolve, rc 0). The `:-.` default form is **not** a documented placeholder, so D1(b) would have to drop the fallback (section 24's `NOFALLBACK_FORM` ban would need an exception). **To verify on Windows at release** if D1(b) is chosen.
- D1(a), the shell form, under dash: `CLAUDE_PROJECT_DIR=$S/proj sh -c 'f="${CLAUDE_PROJECT_DIR:-.}/hooks/x.sh"; [ -r "$f" ] || { echo "HOOK SCRIPT MISSING: $f" >&2; exit 2; }; exec bash "$f"'` → the script ran with `$0` = the path, `dirname` = the hooks dir, `lib=ok`, rc 0. With a missing dir → `HOOK SCRIPT MISSING: …/none/hooks/x.sh`, rc **2**. Because `exec bash "$f"` gives `$0` = the path, **no hook needs a `$0` → `BASH_SOURCE` change**. That is why D1(a) is preferred over sourcing inside the project string, which would leak `f` and would need bash, not dash.
- Fail-open wrapper `[ -r "$0" ] || exit 0; . "$0"` with a missing file → rc 0.
- **P2-c, the C5 builtin registration check (no fork):** with `p=${CLAUDE_PROJECT_DIR:-.}; if [ -f "$p/hooks/no-push-main.sh" ] && [ -r "$p/.claude/settings.json" ]; then IFS= read -r -d "" s < "$p/.claude/settings.json"; [[ $s == *"/hooks/no-push-main.sh"* ]] && exit 0; fi; echo RUN-GLOBAL`:
  - registered + file → steps aside (rc 0, no output);
  - no project → `RUN-GLOBAL`;
  - file but settings removed → `RUN-GLOBAL`.

  The plan's final string uses `case` (bash 3.2-safe) and the `}/hooks/` anchor.
- Hooks using `$(dirname "$0")` (all work under both forms, so no change): `bash-output-guard`, `deny-claude-md-writes`, `deny-hang-shapes`, `deny-secret-reads`, `enforce-agent-contract`, `enforce-delegation`, `gate-before-merge`, `no-push-main` (through `lib=`), `pre-commit-test`, `model-floor`, `require-skills-block`, `read-size-gate`, `retro-*`.

### P3: the `command` program

- Docs (code.claude.com/docs/en/hooks, hooks-guide):
  - Shell form runs under `sh -c` on macOS and Linux, and under Git Bash on Windows (PowerShell when Git Bash is absent), with no other wrapper.
  - Exec form resolves `command` through **PATH**.
  - A command that cannot be spawned (ENOENT) is a **non-blocking** error. So a mis-resolved exec-form program fails **open** for every protection, which is why D1(b) is rejected without a Windows proof.
  - The version that introduced exec form is not documented. The spec §2.5 verified it on Claude Code 2.1.289, Windows.
- On Windows, a bare `bash` on PATH commonly resolves to `C:\Windows\System32\bash.exe` (the WSL launcher). Git for Windows adds `Git\cmd` to PATH by default, not `Git\usr\bin`. **To verify on Windows at release.**
- Git's `C:\Program Files\Git\bin\bash.exe` is a launcher that starts `usr\bin\bash.exe`. The reference's `CLAUDE_CODE_SHELL` already uses `usr\bin\bash.exe`, and the render script must too (Task 8).
- Setup today: `setup-project.sh`/`.ps1` copy `templates/<v>/.claude/**` verbatim (an existing file is skipped unless `--force`) and **never write** `~/.claude/settings.json`; they print snippets. Neither has any Git Bash detection. The sync server replaces `.claude/settings.json` wholesale (R-5).
- Process cost per hook entry, Linux, measured: today's `sh -c "bash x.sh; c=$?…"` vs exec + source: **2 fewer forks and 1 fewer exec per entry** for every hook measured (`no-push-main` 66→64 forks on `ls -la`, `deny-secret-reads` 30→28, `deny-hang-shapes` 27→25, `bash-output-guard` 17→15, `pre-commit-test` 46→44, `gate-before-merge` 66→64; node runs unchanged at 1/4/4/2/1/1). The wrapper alone is a small part. The bulk is inside the hooks, which is what C3–C5 target.

### Baseline (Linux, `8c118a8`, for Task 12's "old" column)

Command: `bash <scratchpad>/count.sh` (strace `-f -e trace=execve,fork,vfork,clone,clone3`; forks counted without `CLONE_THREAD`, +1 for the root). Payload cwd = repo:

| Hook (old registration) | `git status`: procs / execs / node | `ls -la`: procs / execs / node |
|---|---|---|
| no-push-main | 81 / 37 / 1 | 66 / 26 / 1 |
| deny-secret-reads | 30 / 13 / 4 | 30 / 13 / 4 |
| deny-hang-shapes | 27 / 10 / 4 | 27 / 10 / 4 |
| bash-output-guard | 17 / 10 / 2 | 17 / 10 / 2 |
| pre-commit-test | 46 / 21 / 1 | 46 / 21 / 1 |
| gate-before-merge | 92 / 41 / 1 | 66 / 26 / 1 |

For a plain project (user-level set: `no-push-main` + `deny-secret-reads` + `deny-hang-shapes` + `bash-output-guard`), one `git status` Bash call is about **155 processes, 11 of them node**, on Linux at this base.
