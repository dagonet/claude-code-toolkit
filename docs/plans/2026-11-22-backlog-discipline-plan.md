# Backlog Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every change names its backlog item and closes it on merge, grooming lands before work is picked, and backlog debt is shown at every session start.

**Architecture:**
- One new fail-closed project hook, `hooks/backlog-item-check.sh`, runs at PR creation (the MCP tool, and `gh pr create` via the dispatcher) and again at `gh pr merge` / MCP merge. It reads the mode from `PROJECT_CONTEXT.md`, then either a diff of `PROJECT_STATE.md` against the base (file mode) or the PR body (issue mode).
- Advisory pieces:
  - a new `hooks/backlog-brief.sh` (SessionStart, every source);
  - `hooks/agent-result-notes.sh` (PostToolUse `Agent`) for reviewer/tester follow-ups;
  - counter keys.
- Templates and the sprint and sync skills gain the backlog shape and order.

**Tech Stack:** bash hooks on `hooks/lib/json.sh` and `hooks/lib/git-cmd.sh`, markdown templates, Python 3 (`scripts/self-review-count.py`), and the existing test scripts.

**Spec:** `docs/plans/2026-11-22-backlog-discipline-design.md`, approved 2026-11-22 19:24. §10 and §10a are binding; §10a (the challenge round, approved 20:04) wins where they differ.

## Global Constraints

- **Branch:** `feat/v6.3`, worktree `~/git/.worktrees/claude-code-toolkit/v6.3`. It ships inside v6.3.0 (user ruling 2026-11-22 20:09), built after the model-ladder plan.
- **Version:** v6.3.0; Task 7 folds into the v6.3 items plan's release task.
- **Item ids:** `B-[0-9]+`. File-mode subsections are exactly `### Untriaged`, `### Ranked` and `### Done` under `## Backlog`.
- **Mode:** `Task source` in the repo root's `PROJECT_CONTEXT.md`, with backticks and spaces trimmed.
  - Exactly `plan-files` means file mode; exactly `github-issues` means issue mode.
  - Anything else, or missing, means refuse.
- **Closing keywords** (issue mode, case-insensitive): `close(s|d)?`, `fix(es|ed)?` or `resolve(s|d)?`, then whitespace, then `#<n>`. A cross-repo `owner/repo#n` does not count.
- **`Item: none`:**
  - issue mode: a body line that is exactly `Item: none`;
  - file mode: a commit trailer `Item: none` on any commit in `<base>..HEAD`;
  - accepted from any PR.
- **Exempt:** a PR whose `<base>..HEAD` diff touches only `PROJECT_STATE.md` (grooming).
- **Base:** the MCP `tool_input.base`, `gh` `--base`/`-B`, else the local `refs/remotes/origin/HEAD`. If none, refuse with "pass --base".
  - The compared ref is `refs/remotes/origin/<base>`. If it is missing, refuse with "fetch first".
  - `main` is never assumed.
- **Head:** MCP `tool_input.head` (strip an `owner:` prefix), `gh` `--head`/`-H`, else the cwd's current branch.
  - If the cwd's current branch is not the head, refuse with "run from the PR's own checkout".
  - If HEAD is not equal to `refs/remotes/origin/<head>`, refuse with "push first".
- **`gh pr create` bodies:** read only from `--body-file`/`-F` (the hook reads the file). Any other body form, or none, means refuse with "use --body-file".
- **Merge second line:** only `gh pr merge` and `mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge|mcp__plugin_github-tools_github-tools__github_pr_auto_merge`, file mode only. Issue mode merges pass, and this is documented.
- **Every refusal:**
  - exits 2;
  - stderr starts `BLOCKED: backlog-item-check:` and names the exact fix;
  - cannot-determine always means refuse.
- **The fix texts include:**
  - missing subsections: "add the three headings in this PR and commit with trailer `Item: none`";
  - no item: "move the item into `### Done` in this PR, or commit with trailer `Item: none` (T1 only)".
- **Hook class:**
  - `backlog-item-check`: class `project`, polarity `closed`, independent of `**Gate**:`;
  - `backlog-brief` and `agent-result-notes`: class `project`, polarity `open`, always exit 0.
- **Kill switch:** `gc_guard_off` (`<cwd>/.claude/git-guard-off`).
- **No network** in `backlog-item-check.sh`.
- **Every Bash call** runs the guard, so it copies `gate-before-merge.sh`'s cheap early exit before sourcing `git-cmd.sh` (`gate-before-merge.sh:186-216`) and its 127→2 trap (`:171`), with no top-level `return`.
- **Files:** LF only. `AGENT_TEAM.md` and `.claude/settings.json` stay byte-identical across the six variants (edit `templates/general/`, then `cp`).
- **Privacy:** counts only (R4/R5/R18).
- **KISS:** no state files, no new kill switch, no fetch.
- **Registration lists to extend** (else the per-commit Test blocks the commit):
  - `scripts/verify-template-consistency.sh:4739` `C71_PLUGIN_ONLY` (append-only);
  - `:4771` `c71_rh_want` (closed-class entries use the inline plugin-missing form, `:4769-4776`);
  - `:4752` root rows;
  - `:5039-5040` `c74_d2_bash`/`c74_d2_ps` (the guard goes before `pre-commit-test`, matching `dispatch.sh`);
  - `scripts/test-hooks.sh:262` (`hk_modes`), `:12138`, `:12146`, `:12459`, `:12463`, `:12476`.

  Line numbers are as of `4576485`, so re-locate them by content.

## Review Focus

1. **The first PR after the update:** the base has no subsections; the PR adds them with an `Item: none` trailer, giving 0; without the trailer, 2. Task 2.
2. **A new id appearing only in HEAD's `### Done`** (absent from the base's Untriaged/Ranked) does not count as a move, giving 2. Task 2.
3. **A PR from the PO's main checkout** (cwd branch is not the head), giving 2 with "own checkout". Task 2.
4. **`gh pr create --body "Fixes #4"`, `--fill` or `--body "$(cat x)"`** each give 2 with "--body-file". Task 3.
5. **The sync PR** (`/sync-template` flow: commit trailer `Item: none` plus `--body-file` with an `Item: none` line) passes in both modes. Task 3.

---

### Task 1: Backlog shape, order and briefs in templates, skills and this repo

**Files:**
- Modify:
  - `templates/<six>/PROJECT_STATE.md`: `## Backlog` gets the three subsections, each `_none_`;
  - `templates/general/AGENT_TEAM.md`, then `cp` to the five others;
  - `skills/sprint/SKILL.md`;
  - `skills/sync-template/SKILL.md`, around `:1304-1324`: the sync commit carries the trailer `Item: none`, and the PR is created with `--body-file` containing an `Item: none` line, replacing `--fill`;
  - `scripts/verify-template-consistency.sh`.
- Create: root `PROJECT_STATE.md` with `## Now` and `## Backlog` (three subsections). It holds the toolkit's open items as `B-1..`: v6.3, the model ladder, this work, and plugin split part 2.

**Interfaces:**
- Produces the headings and the line form `- B-<n> [in progress] <title>` (the tag is optional; absent means open).
- The `AGENT_TEAM.md` heading `## Backlog` is cited by later messages.

- [ ] **Step 1: Add the failing consistency check** `backlog shape` (the next free number).
  - **(a)** The six `PROJECT_STATE.md` carry the three headings in order under `## Backlog`.
  - **(b)** `templates/general/AGENT_TEAM.md` contains:
    - `## Backlog`;
    - `Before picking the next task, groom the backlog`;
    - `One item = one pull request`;
    - `Grooming lands on the trunk before any helper starts`.
  - **(c)** The root `PROJECT_STATE.md` passes (a).
  - **(d)** `skills/sync-template/SKILL.md` no longer contains `gh pr create --fill`.
  - **(e) Control:** a temp copy without `### Ranked` is reported.
- [ ] **Step 2: Run** `bash scripts/verify-template-consistency.sh`. Expected: only the new check fails.
- [ ] **Step 3: Edit.** The `AGENT_TEAM.md` `## Backlog` block holds:
  - the shape (spec §4);
  - "Before picking the next task, groom the backlog: close finished items, rank every untriaged item, re-check the top three.";
  - "Grooming lands on the trunk before any helper starts: a PR that touches only `PROJECT_STATE.md` needs no item.";
  - "One item = one pull request: an item that needs several PRs is split into several items when ranked.";
  - "Every PR names its item (issue mode: `Closes #N` in the body; file mode: the PR moves the item into `### Done`), or carries `Item: none` (T1 and template sync only; counted).";
  - "Parallel PRs touching `PROJECT_STATE.md` rebase before merge, as every PR does."

  Other edits:
  - **Mode Behavior Table:** the rows "Close task", "Tech debt tracking" and "Sprint state" point at the backlog instead of MEMORY.md.
  - **PO role line:** links "maintains/prioritizes the backlog" to `## Backlog`.
  - **Coder brief templates** (both modes, `AGENT_TEAM.md` ~`:125-150`): add the line `Item: {B-<n> | #N | none}`, and in plan-files mode the workflow step "move the item into `### Done` in `PROJECT_STATE.md`" before commit.
  - **`skills/sprint/SKILL.md`:**
    - new step 1 "Groom the backlog (AGENT_TEAM.md § Backlog) and land it before any spawn";
    - its old "record in the plan file" step (~`:25`) now records in the backlog.
- [ ] **Step 4: Copy** `AGENT_TEAM.md` to the five variants. Run the consistency script. Expected: PASS. Then run `bash scripts/test-setup-project.sh`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(templates): backlog shape, grooming first, one item per PR, sync PRs carry Item: none`.

### Task 2: `backlog-item-check.sh` for MCP PR creation, with the root registration

**Files:**
- Create: `hooks/backlog-item-check.sh`.
- Modify:
  - `hooks/lib/hook-class.sh`: add `backlog-item-check` to the `cls=project; pol=closed` line;
  - `hooks/hooks.json`:
    - a new PreToolUse entry with matcher `mcp__MCP_DOCKER__create_pull_request`, in the inline plugin-missing form the merge entry uses;
    - the merge matcher entry gains `backlog-item-check` after `gate-before-merge`;
  - root `.claude/settings.json`: the same two matchers point at `${CLAUDE_PROJECT_DIR}/hooks/backlog-item-check.sh`, because project-class plugin hooks skip this repo (`hook-class.sh:28`);
  - check 71 lists (Global Constraints);
  - `scripts/test-hooks.sh`.

**Interfaces:**
- MCP payload fields are `tool_input.head`, `tool_input.base` and `tool_input.body` (verified against the tool schema). Read them with `json_fields "$GC_JSON" tool_input.head tool_input.base tool_input.body` (`json.sh:297`; handles multi-line values).
- Produces, in the hook (Task 3 reuses them):
  - `bic_mode`: prints `file`, `issue` or nothing;
  - `bic_refs <base> <head>`: sets `BIC_BASE_REF`, or refuses;
  - `bic_file_ok`: returns 0 on a move, an exempt diff or an `Item: none` trailer;
  - `bic_body_ok <body>`: returns 0 on a closing keyword or `Item: none`.
- **File-mode order** (Review Focus 1):
  1. exempt diff;
  2. `Item: none` trailer;
  3. base subsections present, else refuse with the "add the three headings…" text;
  4. a move;
  5. otherwise refuse with the no-item text.

- [ ] **Step 1: Failing rows** (`mkrepo` plus a pushed `origin/<head>` ref; `check_msg` needle `backlog-item-check` plus the listed fragment).
  - **File mode, allow (exit 0):**
    - B-3 is Ranked in base and in Done in HEAD;
    - an `Item: none` trailer;
    - a diff that touches only `PROJECT_STATE.md`;
    - base without subsections plus a trailer.
  - **File mode, refuse (exit 2):**
    - base without subsections and no trailer (`three headings`);
    - no move and no trailer (`### Done`);
    - B-9 only in HEAD's Done (`### Done`, Review Focus 2);
    - the cwd branch is not the head (`own checkout`, Review Focus 3);
    - HEAD is ahead of `origin/<head>` (`push first`);
    - `origin/<base>` is missing (`fetch first`);
    - no base given and no `origin/HEAD` (`pass --base`).
  - **Issue mode:** `Fixes #12` gives 0; `Item: none` gives 0; `see #12` gives 2; `Closes other/repo#12` gives 2.
  - **Mode:** `Task source` missing gives 2, and `jira` gives 2 (`Task source`).
  - **Kill switch:** gives 0.
  - **No `**Gate**:` line:** a no-item PR still gives 2.
- [ ] **Step 2: Run** `bash scripts/test-hooks.sh 2>&1 | grep -E '(PASS|FAIL) .*backlog'`. Expected: the new rows FAIL.
- [ ] **Step 3: Implement.**
  - **Section parsing:** awk over `git show <ref>:PROJECT_STATE.md` for the base and HEAD.
  - **Trailers:** `git log --format='%(trailers:key=Item,valueonly)' <base>..HEAD`.
  - **Exempt:** `git diff --name-only <base>...HEAD` is exactly `PROJECT_STATE.md`.
- [ ] **Step 4: Run** the filtered rows (PASS), then `bash scripts/verify-template-consistency.sh` (PASS: checks 71 and 74 updated).
- [ ] **Step 5: Commit** `feat(hooks): backlog-item-check refuses a PR that names no backlog item`.

### Task 3: `gh pr create` and `gh pr merge` via the dispatcher

**Files:**
- Modify:
  - `hooks/dispatch.sh` (bash and powershell tables: `backlog-item-check` before `pre-commit-test`);
  - `hooks/backlog-item-check.sh`;
  - root `.claude/settings.json` (Bash|PowerShell matcher);
  - check 74 lists and check 71 root rows;
  - `scripts/test-hooks.sh` (`hk_modes` dispatched list; v6 dispatch (m) rows).

**Interfaces:**
- Consumes Task 2's functions.
- Segment detection uses `gc_segments`, only to find a `gh pr create`/`gh pr merge` segment and its flags (`--base/-B`, `--head/-H`, `--body-file/-F`). Body text never comes from the command line.

- [ ] **Step 1: Failing rows** (each also runs `[dispatch]`).
  - **`gh pr create`, file mode:** the Task 2 move repo gives 0; no move gives 2.
  - **`gh pr create`, issue mode:**
    - `--body-file <file with Closes #4>` gives 0;
    - `-F <same>` gives 0;
    - `--body "Fixes #4"` gives 2;
    - `--fill` gives 2;
    - `--body "$(cat x)"` gives 2, all with `--body-file` (Review Focus 4).
  - **Sync flow:** a commit with trailer `Item: none` plus `--body-file` with an `Item: none` line gives 0 in both modes (Review Focus 5).
  - **`gh pr merge 5`, file mode:** from a move checkout with no `**Gate**:` gives 0; from a no-move checkout gives 2.
  - **`gh pr merge 5`, issue mode:** gives 0.
  - **Other commands:** `git status` and `git merge feature` on main each give 0 (not this hook's shape).
- [ ] **Step 2: Run.** Expected: the new rows FAIL.
- [ ] **Step 3: Implement**, with the early exit (no `gh pr` text present means exit 0 before sourcing `git-cmd.sh`) and the 127→2 trap.
- [ ] **Step 4: Run** `bash scripts/test-hooks.sh` (full, foreground, timeout 600000). Expected: 0 FAIL. Then the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): backlog check on gh pr create and gh pr merge`.

### Task 4: `backlog-brief.sh` at every session start

**Files:**
- Create: `hooks/backlog-brief.sh` (class `project`, polarity `open`).
- Modify:
  - `hooks/hooks.json` (the unmatched SessionStart group, timeout 10);
  - `hooks/lib/hook-class.sh`;
  - check 71 lists;
  - `scripts/test-hooks.sh`.
- `now-brief.sh` is **not** touched.

**Interfaces:**
- **Mode:** read with the same rule as `bic_mode`. It is copied into the brief as a 6-line function; a consistency row asserts the two copies are byte-identical.
- **Output:**
  - file mode: `backlog: <u> untriaged, <p> in progress, top: B-<n> <title>`, or `top: none`;
  - subsections missing: `backlog: PROJECT_STATE.md has no ### Untriaged/### Ranked/### Done -- see AGENT_TEAM.md § Backlog`;
  - issue mode: `backlog: <u> untriaged, <o> open`, from `gh issue list --state open --json labels --limit 200` under `timeout 3`. If `timeout` or `gh` is missing, or the call fails, there is no line.

- [ ] **Step 1: Failing rows.**
  - A fixture with 2 untriaged, 1 in progress and top B-4 gives exactly that line, for `source` `startup` and `compact` alike.
  - Missing subsections give the hint line.
  - Issue mode without `gh` on PATH gives exit 0 and no output.
  - No `PROJECT_STATE.md` gives exit 0 and no output.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the suite filter and the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): backlog-brief shows backlog debt at every session start`.

### Task 5: Follow-ups note

**Files:**
- Extend: `hooks/agent-result-notes.sh`, created by the model-ladder plan (Task 2), with a second rule `anr_followups` beside `anr_step_up`; its class and registration already exist.
- Modify:
  - `hooks/hooks.json`, `hooks/lib/hook-class.sh` and check 71 lists: already done by the model-ladder plan; no change unless its registration differs;
  - `agents/code-reviewer.md` and `agents/tester.md` (the optional block in their report contract);
  - `hooks/enforce-agent-contract.sh` (reviewer verdict only, ~`:142-147`);
  - `scripts/test-hooks.sh`.

**Interfaces:**
- **Block:** a line exactly `Follow-ups:`, then `- <item>` lines. It is optional; absent means none.
- **Reviewer verdict:** it also accepts a message whose first line is `clean` and whose remaining lines are exactly one `Follow-ups:` block.
- **Output:** for `tool_input.subagent_type` in `cct:code-reviewer|code-reviewer|cct:tester|tester` whose result holds the block with at least one `- ` line, the hook prints `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"Add these follow-ups to the backlog as untriaged items."}}`. Otherwise it prints nothing.
- **Result text:** read from `tool_response`.
  - **Step 0 first:** use the payload shape the model-ladder plan (Task 1) recorded in `user-level-reference/settings-reference.md`.
  - Check whether a `run_in_background` spawn's payload carries the report. If it does not, document that the note covers foreground spawns only.
- **Shared script:** the step-up rule (model-ladder plan) is already in this script; `anr_followups` is the second rule.

- [ ] **Step 0: Read the payload shape** that the model-ladder plan (Task 1) recorded in `user-level-reference/settings-reference.md`, and use it.
- [ ] **Step 1: Failing rows.**
  - A reviewer result `clean` plus a block gives the note, and `enforce-agent-contract` on that final message gives 0.
  - `clean` alone gives no note.
  - A coder result with a block gives no note.
  - An unreadable payload gives 0 and no output.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement**, and add the optional block to both agent contracts.
- [ ] **Step 4: Run** the suite filter and the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): reviewer/tester follow-ups prompt a backlog entry`.

### Task 6: Counter keys and docs

**Files:**
- Modify:
  - `scripts/self-review-count.py`: `MEASURE_KEYS` (~`:60`) and merge (~`:754`);
  - `scripts/fixtures/self-review/**`;
  - `docs/architecture.md` (hooks table rows for the three new hooks);
  - `docs/verification.md`;
  - `CHANGELOG.md`: the unreleased section's downstream-migration note says:
    - the first PR adds the three subsections or the `priority:1..3` labels with `Item: none`;
    - sync PRs carry `Item: none`;
    - grooming PRs are exempt.

**Interfaces:**
- **Shared keys, counted in main and subagent transcripts:**
  - `backlog_item_none`: an int, from PR-create tool inputs plus commit messages and `-m` texts carrying the trailer `Item: none`;
  - `backlog_refusals`: `{"<mode>/<reason>": int}`. The reasons are `no-item`, `body-unreadable`, `no-subsections`, `wrong-checkout`, `not-pushed`, `no-base` and `mode`, mapped from fixed substrings of `BLOCKED: backlog-item-check:` messages;
  - `followups`: an int, counted from reviewer/tester result texts holding a non-empty `Follow-ups:` block.

- [ ] **Step 1: Failing fixture rows** with exact counts for each key.
- [ ] **Step 2: Run** the counter's fixture test (as check 82 runs it). Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run the full gate** `bash hooks/run-gate.sh` (foreground, timeout 600000). Expected: GATE PASS.
- [ ] **Step 5: Commit** `feat(self-review): count backlog refusals, Item: none and follow-ups`, plus the docs commit.

### Task 7: Release (on the user's go)

- [ ] **Version:** bump `VERSION` and `.claude-plugin/plugin.json`, and finish the CHANGELOG.
- [ ] **Measurements:** take the Context Budget column with `wc -c`.
- [ ] **Self-review:** run `/self-review`.
- [ ] **Parser matrix:** run it (announced; machine-wide), then the gate.
- [ ] **PR:** the user merges. Tag, release notes via MCP, live update on the user's go, drift 0 on both machines.
