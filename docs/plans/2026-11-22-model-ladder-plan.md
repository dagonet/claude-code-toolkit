# Cheap-first Model Ladder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the model choice into a written cheap-first ladder, with an advisory note when a coder-type helper fails, measured by the self-review counter.

**Architecture:**
- **Written rule:** the user-level `CLAUDE.md` section "Sub-Agent Model Choice" is rewritten, and `AGENT_TEAM.md` gets one matching line.
- **Advisory hook:** a new `hooks/agent-result-notes.sh` (PostToolUse `Agent`) prints one `Step-up:` line when a pipeline coder's returned report shows a failure. The backlog plan later adds its follow-ups rule to the same script.
- **Counter:** gains `start_models` and `step_ups`.

**Tech Stack:** bash with `hooks/lib/json.sh` and `hooks/lib/agent-model.sh`, Markdown, Python 3 (`scripts/self-review-count.py`).

**Spec:** `docs/plans/2026-11-22-model-ladder-design.md`, approved via dashboard #54 ("all changes have been discussed in the chat", 2026-11-22). It ships inside v6.3.0 (user ruling 20:09), on branch `feat/v6.3`, worktree `~/git/.worktrees/claude-code-toolkit/v6.3`.

## Global Constraints

- **Ladder order:** `haiku` < `sonnet` < `opus` < `fable`.
  - A model string maps to its family by substring (`claude-sonnet-5-5` → `sonnet`).
  - An unknown family means no note.
- **Note text, exact:**
  - `Step-up: <type> failed on <model> (<reason>). Start the same job again on <next model>.`
  - top rung: `Step-up: <type> failed on fable (<reason>). Report this to the user instead of retrying.`
  - `<reason>` is `brief item <n> failed` for the first `- [fail] <n>.` line, else `gate failed`.
- **Failure means**, in the returned report of an agent whose frontmatter has `pipeline: true` (`hooks/enforce-agent-contract.sh` reads the same key):
  - any line matching `^[[:space:]]*- \[fail\] [0-9]+\.`;
  - or a line starting `Gate:` that contains `GATE FAILED` (the text `hooks/run-gate.sh:905` prints).
- **Which model ran:** `tool_input.model` if present, else `am_resolve <type> <cwd>` → `AM_MODEL` (`hooks/lib/agent-model.sh`). An empty value means no note.
- **Advisory:**
  - class `project`, polarity `open`;
  - always exits 0;
  - no `onFailure`;
  - no state file;
  - any doubt means no output.
- **Output:** JSON `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<note>"}}`, or nothing.
- **Reviewers, tester, architect, Explore and general-purpose get no step-up note** (spec §6). The written rule covers a "needs fixes" review.
- **Privacy:** counter keys follow R4/R5/R18 (toolkit types, built-ins and `other`; allow-listed models only).
- **Files:** LF only. `AGENT_TEAM.md` stays byte-identical across the six variants.
- **Registration lists:** `scripts/verify-template-consistency.sh` check 71 `C71_PLUGIN_ONLY` and `c71_rh_want`, plus `hooks/lib/hook-class.sh`. Locate them by content.
- **Live `~/.claude`:** never touched (the reference copy only). The live update is attended, at release.

## Review Focus

1. **A background spawn** (`run_in_background: true`), whose PostToolUse result is only "started": no note, no error. Task 2.
2. **A coder report quoting the text `[fail]` inside a sentence**, not as a contract line: no note. Task 2.
3. **A spawn with an explicit `model: "claude-opus-5-5"`** that fails: the note names `fable`, not `sonnet`. Task 2.
4. **A Jev-routed spawn** whose input was rewritten: the model in `tool_input` is the one that ran. Task 1 verifies which input PostToolUse receives.
5. **The user-level `CLAUDE.md` byte cap (check 35)** after the rewrite. Task 3.

---

### Task 1: Verify the PostToolUse `Agent` payload in the docs

**Files:** Modify `user-level-reference/settings-reference.md` (next to the recorded Bash shape, ~`:375`).

**Interfaces:** Produces the recorded field names for the returned report text (e.g. `tool_response` and its shape). Also records whether PostToolUse sees the final report for background spawns, and whether `tool_input` is the original or the hook-rewritten input.

- [ ] **Step 1: Read the sources.** These are the Claude Code hooks reference (PostToolUse input, Agent tool) and the changelog entries on `updatedInput`. Quote the source lines in the task report. No live session and no temp HOME with credentials.
- [ ] **Step 2: Record the facts.** Write the field names and the two answers in `settings-reference.md`, with the source URL and date. If the docs do not say, write "not documented". Task 2 then handles both a string and an array-of-blocks shape and stays silent otherwise.
- [ ] **Step 3: Run** the consistency script. Expected: PASS.
- [ ] **Step 4: Commit** `docs(reference): PostToolUse Agent payload shape for the step-up note`.

### Task 2: `agent-result-notes.sh` with the step-up rule

**Files:**
- Create: `hooks/agent-result-notes.sh`.
- Modify:
  - `hooks/hooks.json` (PostToolUse, matcher `Agent`, `bash "${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.sh" agent-result-notes`);
  - `hooks/lib/hook-class.sh`;
  - check 71 lists;
  - `scripts/test-hooks.sh`;
  - `scripts/verify-template-consistency.sh` (new check 84).

**Interfaces:**
- Consumes Task 1's field names, `am_resolve` and `am_fm <file> pipeline`.
- Produces `anr_step_up` (prints the note or nothing), written as one rule function so that the backlog plan can add `anr_followups` beside it.

- [ ] **Step 1: Failing rows**, with stdout asserted.
  - `cct:coder`, model `sonnet`, a report with `- [fail] 2. x — y` gives `Step-up: cct:coder failed on sonnet (brief item 2 failed). Start the same job again on opus.`
  - `Gate: GATE FAILED: ...` on `sonnet` gives `... (gate failed) ... on opus.`
  - Explicit `claude-opus-5-5` gives `... on fable.` (Review Focus 3).
  - `fable` gives the "Report this to the user" form.
  - A clean report (`[pass]` lines, `Gate: GATE PASS abc`) gives no output.
  - Prose "the [fail] marker" gives no output (Review Focus 2).
  - `cct:code-reviewer` with "Severity: critical" gives no output.
  - A background result ("started") gives no output (Review Focus 1).
  - An unknown model `foo` gives no output.
  - An unreadable payload gives exit 0 and no output.
  - Every case exits 0.
- [ ] **Step 2: Check 84.** It asserts `hooks/hooks.json` registers `agent-result-notes` as PostToolUse `Agent` with no `onFailure`. Two-sided: a temp copy with `"onFailure": "block"` added is flagged.
- [ ] **Step 3: Run** both. Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run** the full `scripts/test-hooks.sh` (foreground, timeout 600000) and the consistency script. Expected: 0 FAIL, PASS.
- [ ] **Step 6: Commit** `feat(hooks): step-up note when a pipeline helper fails (model ladder)`.

### Task 3: The written rule

**Files:**
- Modify:
  - `user-level-reference/CLAUDE.md` (section "Sub-Agent Model Choice", ~`:35-39`);
  - `templates/general/AGENT_TEAM.md` (Model & Effort Policy, ~`:55-58`), then `cp` to the five others;
  - `skills/jev/SKILL.md` (the "While on: omit `model`" section now says it is optional and off by default; the user-level rule no longer carries the exception).

**Interfaces:** The section holds exactly these points (spec §4-5):
- the ladder table;
- "Start each job on the cheapest rung that may do it; on a failed result, start the same job again one step up, and say so in your report to the user.";
- "A review that finds the work needs fixes counts as the coder's failure: the fix round's coder starts one step above the model that wrote the code.";
- "Reviews, architecture and safety design start on `opus` and never lower.";
- "A `Step-up:` note from the hook is an instruction to do exactly that.";
- item 7 (moved here from the v6.3 items plan): "A review spawn uses `cct:code-reviewer`, which owns its model, rather than `general-purpose` on `opus`; the same holds for other plugins' review steps when they let you pick the type.";
- every spawn still names `model` unless the type owns one. **The Jev exception sentence is removed.**

`AGENT_TEAM.md` gains one line under Model & Effort Policy: "Model choice follows the user-level ladder: cheap first, one step up on failure; reviewers and the architect never below `opus`."

- [ ] **Step 1: Make the edits.**
- [ ] **Step 2: Run** the consistency script. Expected: PASS, including check 35's byte cap (Review Focus 5) and the six-variant identity. Then run `bash scripts/verify-user-level-drift.sh` read-only. Expected: it reports the new reference differing from live, which is correct until the attended update.
- [ ] **Step 3: Commit** `docs(rules): cheap-first model ladder replaces the Jev exception (self-review item 7 folded in)`.

### Task 4: Counter keys

**Files:** Modify `scripts/self-review-count.py` (`MEASURE_KEYS` ~`:60`, the spawns block ~`:437`, merge) and `scripts/fixtures/self-review/**`.

**Interfaces:** Shared JSON:
- `start_models`: `{type key: {model: n}}`, the existing spawns measure under this name, kept under `spawns` too for one release;
- `step_ups`: `{type key: {"<from>-><to>": n}}`, counted from `Step-up: <type> failed on <from> ... on <to>.` texts in main transcripts, wherever they land. `<to>` is `user` on the top-rung form.

Types and models pass the existing allowlists, or become `other` / `other-model`.

- [ ] **Step 1: Fixture rows.** Two step-ups sonnet→opus for `cct:coder`, one fable→user, one note for a non-toolkit type (→ `other`), with exact expected counts.
- [ ] **Step 2: Run** `python3 scripts/self-review-count.py --self-test`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the self-test (PASS), then the full gate `bash hooks/run-gate.sh` (foreground, timeout 600000). Expected: GATE PASS.
- [ ] **Step 5: Commit** `feat(self-review): start models and step-ups per helper type`.

## Release

Folded into the single v6.3.0 release (the v6.3 items plan, Task 5).
- **Release notes:**
  - Jev is off by default and optional;
  - clones where it is on should run `/cct:jev off`, which the user does, attended;
  - the user-level `CLAUDE.md` changes, so the live update is attended.
