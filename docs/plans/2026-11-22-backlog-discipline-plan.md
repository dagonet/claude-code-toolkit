# Backlog Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every change names its backlog item and closes it on merge, grooming comes before picking work, and the backlog debt is shown at every session start.

**Architecture:**
- One new fail-closed project hook, `hooks/backlog-item-check.sh`, runs at PR creation (MCP tool plus `gh pr create` via the dispatcher) and again at merge. It reads the mode from `PROJECT_CONTEXT.md`, and either a diff of `PROJECT_STATE.md` (file mode) or the PR body (issue mode).
- Three advisory pieces sit around it:
  - `now-brief.sh` widened to every session start;
  - `hooks/agent-result-notes.sh` (PostToolUse `Agent`) for reviewer/tester follow-ups;
  - counter keys.
- Templates gain the backlog shape and the grooming rule.

**Tech Stack:** bash hooks with `hooks/lib/json.sh` and `hooks/lib/git-cmd.sh`, markdown templates, Python 3 (`scripts/self-review-count.py`), and the existing test scripts.

**Spec:** `docs/plans/2026-11-22-backlog-discipline-design.md` (approved by the user 2026-11-22 19:24). Section 10 there holds the builder-check calls; they are binding.

## Global Constraints

- **Base and ship order:**
  - build on a fresh branch `feat/backlog-discipline` cut from `origin/main` at build time;
  - worktree `~/git/.worktrees/claude-code-toolkit/backlog-discipline`;
  - ships after v6.3.0 and the model-ladder release.
- **Release version:** the next minor after whatever has shipped by release time; Task 7 sets it.
- **Item ids:** `B-<n>` matching `B-[0-9]+`, numbered upwards and never reused.
- **File-mode subsections:** exactly `### Untriaged`, `### Ranked` and `### Done` under `## Backlog` in `PROJECT_STATE.md`.
- **Mode values:**
  - `Task source` in the repo root's `PROJECT_CONTEXT.md`, with backticks and spaces trimmed;
  - exactly `plan-files` means file mode, exactly `github-issues` means issue mode;
  - anything else, or missing, means refuse.
- **Closing keywords** (issue mode, case-insensitive): `close`, `closes`, `closed`, `fix`, `fixes`, `fixed`, `resolve`, `resolves` or `resolved`, then whitespace, then `#<n>`. A cross-repo `owner/repo#n` does not count.
- **`Item: none`:**
  - issue mode: a PR-body line that is exactly `Item: none` after trimming;
  - file mode: a commit trailer `Item: none` on any commit in `origin/<base>..HEAD`;
  - accepted from any PR.
- **Every refusal:**
  - exits 2;
  - its stderr starts `BLOCKED: backlog-item-check:` and names the exact fix;
  - cannot-determine always means refuse.
- **Placement:** the hook is class `project`, polarity `closed`. It must not depend on `**Gate**:` being configured.
- **Kill switch:** `<cwd>/.claude/git-guard-off` via `gc_guard_off` (`hooks/lib/git-cmd.sh`).
- **No network** in `backlog-item-check.sh`.
- **Advisory hooks:** `now-brief.sh` and `agent-result-notes.sh` always exit 0.
- **Files:** every file is LF. `AGENT_TEAM.md` and `.claude/settings.json` stay byte-identical across the six variants (edit `templates/general/` first, then `cp`).
- **Privacy:** new counter keys are counts only (R4/R5/R18 unchanged).
- **KISS:** no state files, no new kill switch, no fetch.

## Review Focus

1. **A PR made from a checkout whose branch is not the PR's head** (e.g. the PO's main checkout) must refuse with "run from the PR's own checkout", not compare the wrong tree. Test in Task 2.
2. **A new item added straight into `### Done`** in the same PR (an id absent from base's Untriaged/Ranked) must not count as a move, or the block is bypassed by inventing items. Test in Task 2.
3. **A body given through `$(...)`, a heredoc or `--fill`** on `gh pr create` must refuse with "use --body-file". Test in Task 3.
4. **A project with no `**Gate**:` configured** must still refuse a PR with no item. Test in Task 3 (the merge second line), and run through the dispatcher.
5. **A reviewer whose final message is `clean` plus a follow-ups block** must still pass `enforce-agent-contract` and must produce the note. Test in Task 5.

---

### Task 1: Backlog shape and grooming rule in the templates and this repo

**Files:**
- Modify:
  - `templates/<all six>/PROJECT_STATE.md` (`## Backlog` → three subsections, each with `_none_`);
  - `templates/general/AGENT_TEAM.md`, then `cp` to the other five;
  - `skills/sprint/SKILL.md`;
  - `scripts/verify-template-consistency.sh`.
- Create: root `PROJECT_STATE.md`. It has `## Now`, plus `## Backlog` with the three subsections, holding the toolkit's open items as `B-1..`: the v6.3 items, the model ladder, this work and plugin split part 2.

**Interfaces:**
- Produces:
  - the exact subsection headings;
  - the `B-<n>` line form `- B-<n> [in progress] <title>`, where the state tag is optional and its absence means open;
  - the `AGENT_TEAM.md` heading `## Backlog`, which Tasks 2-4 cite in messages.

- [ ] **Step 1: Add the failing consistency check.** It is named `backlog shape`, numbered as the next free check number.
  - **(a)** All six `PROJECT_STATE.md` carry the three headings in order under `## Backlog`.
  - **(b)** `templates/general/AGENT_TEAM.md` contains `## Backlog`, the line `Before picking the next task, groom the backlog`, and `One item = one pull request`.
  - **(c)** The root `PROJECT_STATE.md` passes (a).
  - **(d) Control:** a temp copy with `### Ranked` removed is reported.
- [ ] **Step 2: Run** `bash scripts/verify-template-consistency.sh`. Expected: FAIL on the new check only.
- [ ] **Step 3: Edit the templates.** The `AGENT_TEAM.md` `## Backlog` block holds:
  - the shape (spec §4);
  - the grooming rule, verbatim lead sentence: "Before picking the next task, groom the backlog: close finished items, rank every untriaged item, re-check the top three.";
  - "One item = one pull request: an item that needs several PRs is split into several items when ranked.";
  - the PR rule: "Every PR names its item (issue mode: `Closes #N`; file mode: the PR moves the item into `### Done`), or carries `Item: none` (T1 only; counted)".

  Other edits:
  - **Mode Behavior Table:** the rows "Close task", "Tech debt tracking" and "Sprint state" point at the backlog instead of MEMORY.md.
  - **PO role line** "maintains/prioritizes the backlog" links to `## Backlog`.
  - **`skills/sprint/SKILL.md`:** a new step 1 "Groom the backlog (AGENT_TEAM.md § Backlog)" before any spawn.
- [ ] **Step 4: Copy** `AGENT_TEAM.md` to the five variants. Run the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(templates): backlog shape, grooming rule, one item per PR`.

### Task 2: `backlog-item-check.sh` for MCP PR creation

**Files:**
- Create: `hooks/backlog-item-check.sh`.
- Modify:
  - `hooks/lib/hook-class.sh` (`backlog-item-check` → `cls=project; pol=closed`);
  - `hooks/hooks.json` (new PreToolUse entry with matcher `mcp__MCP_DOCKER__create_pull_request`, wrapped like the merge entry; the merge matcher entry gains a second hook `backlog-item-check`);
  - `scripts/test-hooks.sh`.

**Interfaces:**
- Consumes: Task 1's headings and line form.
- Produces, as shell functions inside the hook:
  - `bic_mode` prints `file`, `issue` or nothing;
  - `bic_file_ok <base_ref>` returns 0 when an id moved into Done, or when an `Item: none` trailer is present;
  - `bic_body_ok <body>` returns 0 on a closing keyword or `Item: none`.
- Task 3 calls these for the `gh` shapes.

- [ ] **Step 1: Write the failing test rows** in `scripts/test-hooks.sh`, using `mkrepo` and an MCP payload whose `tool_input` has `head`, `base` and `body`. Use `check_msg` with needle `backlog-item-check` on refusals.
  - **File mode, allow:** B-3 under `### Ranked` on `origin/main` and under `### Done` on HEAD gives exit 0.
  - **File mode, allow:** no move plus a commit with trailer `Item: none` gives exit 0.
  - **File mode, refuse:** no move and no trailer gives exit 2, needle `### Done`.
  - **File mode, refuse:** B-9 appearing only in HEAD's Done (absent from base) gives exit 2. (Review Focus 2)
  - **File mode, refuse:** base without the three subsections gives exit 2, needle `### Untriaged`.
  - **File mode, refuse:** the cwd branch is not `tool_input.head` gives exit 2, needle `own checkout`. (Review Focus 1)
  - **File mode, refuse:** `origin/<base>` missing gives exit 2, needle `fetch`.
  - **Issue mode, allow:** body `Fixes #12` gives exit 0, and body with the line `Item: none` gives exit 0.
  - **Issue mode, refuse:** body `see #12` gives exit 2. Body `Closes other/repo#12` gives exit 2.
  - **Mode:** `Task source` missing or `jira` gives exit 2, needle `Task source`.
  - **Kill switch:** `.claude/git-guard-off` present gives exit 0.
- [ ] **Step 2: Run** `bash scripts/test-hooks.sh 2>&1 | grep -E 'backlog|^(PASS|FAIL) .*bic'`. Expected: the new rows FAIL.
- [ ] **Step 3: Implement the hook.**
  - **Input:** read stdin through `gc_read_stdin`, set `GC_CWD` from the payload `cwd`, and honour `gc_guard_off` first.
  - **File mode:**
    - parse `## Backlog` subsections with awk from `git show origin/<base>:PROJECT_STATE.md` and from the working tree's HEAD (`git show HEAD:PROJECT_STATE.md`);
    - a move is an id under Untriaged or Ranked in base, and under Done in HEAD;
    - trailers come from `git log --format='%(trailers:key=Item,valueonly)' origin/<base>..HEAD`.
  - **Registrations:** both hooks.json registrations described above.
- [ ] **Step 4: Run** the suite filter again. Expected: all new rows PASS. Then run `bash scripts/verify-template-consistency.sh`. Expected: PASS (check 74's class table covers the new hook).
- [ ] **Step 5: Commit** `feat(hooks): backlog-item-check refuses a PR that names no backlog item`.

### Task 3: `gh pr create` and the merge second line via the dispatcher

**Files:**
- Modify:
  - `hooks/dispatch.sh` (add `backlog-item-check` to the `bash` and `powershell` tables, line 123-124);
  - `hooks/backlog-item-check.sh`;
  - `scripts/test-hooks.sh` (`hk_modes` dispatched list gains the hook);
  - `scripts/verify-template-consistency.sh`.

**Interfaces:**
- Consumes: Task 2's `bic_mode`, `bic_file_ok` and `bic_body_ok`.
- Produces: shape detection on `gh pr create` and on the merge shapes `gate-before-merge.sh` gates (`gh pr merge`, `git merge` on a protected branch, the MCP merge tools).

- [ ] **Step 1: Failing rows** (each also runs `[dispatch]` automatically).
  - **`gh pr create`, file mode:**
    - with the Task 2 allow repo gives exit 0;
    - with no move gives exit 2.
  - **`gh pr create`, issue mode:**
    - `--body "Fixes #4"` gives 0;
    - `-b "Fixes #4"` gives 0;
    - `--body-file <file containing Closes #4>` gives 0;
    - `--fill` gives 2, needle `--body-file`;
    - `--body "$(cat x)"` gives 2, needle `--body-file`. (Review Focus 3)
  - **Merge second line, file mode:**
    - `gh pr merge 5` from a checkout with no move and **no `**Gate**:` line** in `PROJECT_CONTEXT.md` gives 2 (Review Focus 4);
    - the same with a move gives 0.
  - **Merge second line, issue mode:** `gh pr merge 5` gives 0 (no local body; documented).
  - **Not a PR command:** `git status` gives 0.
- [ ] **Step 2: Run** the filtered suite. Expected: the new rows FAIL.
- [ ] **Step 3: Implement.**
  - **Segment detection:** use the existing `gc_segments`/`gc_seg_quoted` helpers.
  - **Body source:** for `gh pr create`, read only `--body`/`-b` literal values and `--body-file`/`-F` paths, which the hook reads. Anything else refuses.
  - **Base:** for `gh pr create`, `--base`/`-B`, else `main`.
  - **Consistency check:** assert `backlog-item-check` appears in both dispatcher tables **and** in both hooks.json matchers, two-sided with a control that removes one.
- [ ] **Step 4: Run** `bash scripts/test-hooks.sh` (full). Expected: 0 FAIL. Run the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): backlog check on gh pr create and as the merge second line`.

### Task 4: Session-start backlog line

**Files:**
- Modify:
  - `hooks/now-brief.sh`;
  - `hooks/hooks.json` (the `now-brief` entry moves from matcher `compact` to the unmatched SessionStart group, timeout 10);
  - `scripts/test-hooks.sh`.

**Interfaces:**
- Consumes: Task 1's subsections.
- Produces stdout:
  - file mode: `backlog: <u> untriaged, <p> in progress, top: B-<n> <title>`, where `top` is the first `### Ranked` line, or `top: none`;
  - issue mode: `backlog: <u> untriaged, <o> open` from `gh issue list --state open --json labels --limit 200`, run under `timeout 3` (untriaged = no `priority:` label).

- [ ] **Step 1: Failing rows.**
  - **`source: startup`, file mode:** a fixture with 2 untriaged, 1 in progress and top B-4 gives stdout containing `backlog: 2 untriaged, 1 in progress, top: B-4`, and does **not** contain `Re-shown after compaction`.
  - **`source: compact`:** gives both the `## Now` block and the backlog line.
  - **Issue mode** with `gh` absent from PATH gives exit 0 and no backlog line.
  - **No `PROJECT_STATE.md`:** exit 0.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement.** Keep the `## Now` block compact-only, and append the backlog line for every source.
- [ ] **Step 4: Run** the suite and the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): now-brief shows the backlog debt at every session start`.

### Task 5: Follow-ups note

**Files:**
- Create: `hooks/agent-result-notes.sh` (class `project`, polarity `open`).
- Modify:
  - `hooks/hooks.json` (PostToolUse matcher `Agent`);
  - `hooks/lib/hook-class.sh`;
  - `agents/code-reviewer.md` and `agents/tester.md` (report contract);
  - `hooks/enforce-agent-contract.sh` (reviewer `clean` rule);
  - `scripts/test-hooks.sh`.

**Interfaces:**
- **Contract line:** a block starting with a line exactly `Follow-ups:`, followed by `- <item>` lines. It is optional: absent means none.
- **Reviewer rule** (ruling, it deviates from spec §6's "Follow-ups: none"): the strict `clean` rule stays, so a reviewer with nothing to follow up still ends with exactly `clean`. `enforce-agent-contract` also accepts a first line `clean` followed only by a `Follow-ups:` block.
- **Note:** for `tool_input.subagent_type` in `cct:code-reviewer|code-reviewer|cct:tester|tester` whose result text holds `Follow-ups:` with at least one `- ` line, print JSON `hookSpecificOutput.additionalContext` = `Add these follow-ups to the backlog as untriaged items.` Otherwise print nothing.
- **Later:** the model-ladder step-up note joins this script as a second rule.

- [ ] **Step 1: Failing rows.**
  - A reviewer result with `clean\nFollow-ups:\n- B: retry export` gives the note. `enforce-agent-contract` on the same text as the last message gives exit 0. (Review Focus 5)
  - A reviewer `clean` alone gives no note.
  - A coder result with `Follow-ups:` gives no note.
  - An unreadable payload gives exit 0 and no output.
- [ ] **Step 2: Run.** Expected: FAIL.
- [ ] **Step 3: Implement**, and update both agent contracts with the optional block.
- [ ] **Step 4: Run** the suite and the consistency script. Expected: PASS.
- [ ] **Step 5: Commit** `feat(hooks): reviewer/tester follow-ups prompt a backlog entry`.

### Task 6: Counter keys and docs

**Files:**
- Modify:
  - `scripts/self-review-count.py` and `scripts/fixtures/self-review/**`;
  - `docs/architecture.md` (hooks table rows for `backlog-item-check` and `agent-result-notes`, and the widened `now-brief`);
  - `docs/verification.md`;
  - `CHANGELOG.md` (unreleased section with a downstream-migration note: add the three subsections or the `priority:1..3` labels once, or the first PR is refused).

**Interfaces:**
- **Shared JSON keys:**
  - `backlog_item_none`: int, `Item: none` occurrences in PR-create tool inputs in main transcripts;
  - `backlog_refusals`: `{"<mode>/<reason>": int}`, with reason in `no-item`, `body-unreadable`, `no-subsections`, `wrong-checkout`, `no-base`, `mode`, keyed from the `BLOCKED: backlog-item-check:` messages;
  - `followup_notes`: int.

- [ ] **Step 1: Add failing fixture rows** with one of each, and exact expected counts.
- [ ] **Step 2: Run** the counter's fixture test (as check 82 runs it). Expected: FAIL.
- [ ] **Step 3: Implement**; message reasons map by fixed substrings.
- [ ] **Step 4: Run** the full gate: `bash hooks/run-gate.sh` (foreground, timeout 600000). Expected: GATE PASS.
- [ ] **Step 5: Commit** `feat(self-review): count backlog refusals, Item: none and follow-up notes` and the docs commit.

### Task 7: Release (on the user's go)

- [ ] **Version:** bump `VERSION` and `.claude-plugin/plugin.json` to the next minor. Finish the CHANGELOG with the counts.
- [ ] **Measurements:** take the Context Budget column (`docs/architecture.md`) with `wc -c`.
- [ ] **Self-review:** run `/self-review` and ship its report.
- [ ] **Parser matrix:** run `scripts/test-hooks-parser-matrix.sh` (announced; machine-wide), then the gate.
- [ ] **PR:** the user merges. Tag, release notes via MCP, live update on the user's go, drift 0 on both machines.
