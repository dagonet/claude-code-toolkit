# PM-level Reporting (v4.2.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a switchable, default-on product-manager reporting style for every session: an output style, an inline time hook, and a backlog-board skill, all user-level.

**Architecture:** Three user-level artifacts under `user-level-reference/` (the copy source for `~/.claude/`): `output-styles/pm-report.md`, two entries in `settings.json` (`outputStyle`, a `UserPromptSubmit` command), and `skills/backlog-board/{SKILL.md,board.html}`. Four new consistency checks (59–62) pin the properties that fail silently at runtime; one hook-suite fixture proves the time command; the drift probe learns `output-styles/**`. No project template changes.

**Tech Stack:** bash (Git Bash on Windows), markdown, one static HTML page with the Artifact `db` capability.

**Spec:** `docs/plans/2026-09-27-pm-reporting-design.md` (accepted 2026-09-27). Read it before any task.

## Global Constraints

- Branch `feat/pm-reporting`, worktree `G:/git/.worktrees/claude-code-toolkit/pm-reporting`. Nothing lands on `main` until the user merges the PR.
- **No change under `templates/`** (spec: user-level only, zero consumer churn).
- Every file LF. Author files with the Edit/Write tools; never rewrite a non-ASCII file through PowerShell.
- `git add <explicit paths>` and `git commit -F <message file outside the repo>` as **separate** calls; never `git add -A`/`.`/`commit -a`; never amend, never push, never `git stash`. Implementers never spawn subagents.
- Commit trailer: `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_01NvifYANnzWGoxgL7wqc7RH` (an implementer uses its own model name, R-16 precedent).
- Exact literals (copy verbatim):
  - style name `pm-report`; frontmatter line `keep-coding-instructions: true`
  - time command `LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'`
  - the seven state labels, in this order: `Done, In progress, Testing live, Needs rework, Open, Waiting on you, Blocked`
  - state keys `done, progress, testing, rework, open, waiting, blocked`
  - board placeholder `__PROJECT_NAME__`
- New consistency checks are numbered **59, 60, 61, 62** and inserted directly after check 58 (ends at `scripts/verify-template-consistency.sh:3718`), in check 58's style: header comment block, `echo`, `note "Check N: ..."`, then `ok`/`ko` with a `check N:` prefix. An empty read refuses (`ko`), never passes.
- The pre-commit hook runs the consistency script on every commit (≈1–2 min); a red script blocks the commit — read the message, it is almost always a real red.

## Review Focus

1. **Non-English locale.** The user's machine may carry `LANG=de_DE.UTF-8`; `date +%a` would print `Sa`, not `Sat`, and the time line's shape would depend on the locale. The command forces `LC_ALL=C`; Task 2's fixture runs it under a German locale and requires the English form.
2. **The keep-coding-instructions line lost or softened** (`false`, `"true"`, removed, or indented). The style would silently drop Claude Code's engineering instructions. Check 59 accepts only the exact line; Task 1 perturbs it both ways.
3. **The state list drifting between its two copies** (style vs board page), including a wrapped or re-ordered style line. Check 61 compares the full sets and refuses an empty or partial read; Task 3 perturbs one label.
4. **`outputStyle` naming a style that is not shipped** (renamed file, typo, `name:` differing from the file name). Claude Code would silently fall back. Check 60 requires the file AND a matching `name:` line.
5. **A board row without `order`, an unpinned update, a republish for data.** Rows vanish, writes are refused, versions churn. The skill states the three rules as exact sentences; check 61 arm (b) pins them.

---

### Task 1: Output style `pm-report` + checks 59, 60

**Files:**
- Create: `user-level-reference/output-styles/pm-report.md`
- Modify: `user-level-reference/settings.json` (add top-level `"outputStyle": "pm-report"`)
- Modify: `scripts/verify-template-consistency.sh` (insert checks 59 and 60 after line 3718)

**Interfaces:**
- Produces: the style file path and its rule 5 line `5. **States (exactly these):** Done, In progress, Testing live, Needs rework, Open, Waiting on you, Blocked` (Task 3's check 61 reads this exact line shape); the settings key `outputStyle`.

- [ ] **Step 1: Write the failing checks.** Insert after `scripts/verify-template-consistency.sh:3718` (the `fi` closing check 58):

```bash

# ---------------------------------------------------------------------------
# Check 59 -- the pm-report output style keeps Claude Code's engineering
# instructions (v4.2.0). A custom output style DROPS the built-in software-
# engineering instructions unless its frontmatter says
# `keep-coding-instructions: true` (Claude Code output-styles docs). Losing
# the line is silent at runtime, so it must be loud here. Only the exact bare
# line passes; a missing file or empty frontmatter refuses.
# ---------------------------------------------------------------------------
echo
note "Check 59: output style pm-report.md keeps 'keep-coding-instructions: true'"
c59_f=user-level-reference/output-styles/pm-report.md
c59_fm=""
[ -f "$c59_f" ] && c59_fm=$(awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$c59_f")
if [ -z "$c59_fm" ]; then
  ko "check 59: $c59_f missing or has no frontmatter"
elif printf '%s\n' "$c59_fm" | grep -qx 'keep-coding-instructions: true'; then
  ok "check 59: $c59_f keeps keep-coding-instructions: true"
else
  ko "check 59: $c59_f frontmatter lacks the exact line 'keep-coding-instructions: true' -- the style would drop Claude Code's engineering instructions"
fi

# ---------------------------------------------------------------------------
# Check 60 -- the reference default output style is one this repo ships
# (v4.2.0). Claude Code falls back silently when `outputStyle` names a style
# it cannot find, so a rename or typo would switch the default off unnoticed.
# The file must exist AND its frontmatter `name:` must equal the setting.
# ---------------------------------------------------------------------------
echo
note "Check 60: user-level-reference/settings.json outputStyle names a shipped style"
c60_name=$(grep -o '"outputStyle": *"[^"]*"' user-level-reference/settings.json | head -1 | sed 's/^"outputStyle": *"//; s/"$//')
c60_f="user-level-reference/output-styles/$c60_name.md"
if [ -z "$c60_name" ]; then
  ko "check 60: user-level-reference/settings.json sets no outputStyle"
elif [ ! -f "$c60_f" ]; then
  ko "check 60: outputStyle is '$c60_name' but $c60_f does not exist"
elif awk 'NR==1&&/^---/{inb=1;next} inb&&/^---/{exit} inb{print}' "$c60_f" | grep -qx "name: $c60_name"; then
  ok "check 60: outputStyle '$c60_name' -> $c60_f (name: matches)"
else
  ko "check 60: $c60_f exists but its frontmatter 'name:' is not '$c60_name'"
fi
```

- [ ] **Step 2: Run to verify both fail.**
Run: `bash scripts/verify-template-consistency.sh 2>&1 | grep -E 'check (59|60):'`
Expected: `FAIL  check 59: user-level-reference/output-styles/pm-report.md missing or has no frontmatter` and `FAIL  check 60: user-level-reference/settings.json sets no outputStyle`.

- [ ] **Step 3: Create the style** `user-level-reference/output-styles/pm-report.md`, exactly:

```markdown
---
name: pm-report
description: Plain-language, state-change reporting for a product-manager reader; the technical style is `/output-style default`.
keep-coding-instructions: true
---

# Reporting to the user

The user reads as a product manager: they care what changed for the project goal, not how.

1. **Timestamp.** Start every message with `[HH:MM]`, taken from the "Current local time" line in this turn's context. If this turn has already made more than 10 tool calls, or you cannot tell, run `date` first and use that. Never estimate the time.
2. **Plain words.** No commit ids, file paths, test counts, agent names or internal task labels unless the user asks. If a technical term is unavoidable, explain it in a few words.
3. **Post on state change only.** A state change: an item finished, went to live testing, bounced back, became blocked, or now waits on the user. Routine progress is at most one line, or waits for the next update. Work finishing in parallel must not produce one message per step.
4. **Shape of an update.** One or two sentences: what happened and what it means for the goal. Once 2-3 items have changed state since the last table -- or when the user asks for status -- add the backlog as a short table (about 10 rows, one plain line per capability, one state each). End with a plain question if a decision is needed.
5. **States (exactly these):** Done, In progress, Testing live, Needs rework, Open, Waiting on you, Blocked
   Something that passed a first check and then failed is **Needs rework** -- never hidden under "In progress".
6. **Questions first.** A direct question gets a direct answer first; no table unless a state changed.
7. **Details on request.** Details live in the repo and in memory; end with "ask for details on X" when useful.
8. **A colleague, not a log.** Ask when something is unclear, push back when a request looks wrong, suggest ideas.
9. **Board.** If this project has a backlog board (its address is in this project's memory), update it on every state change using the `backlog-board` skill. If not, and the project has a backlog, offer one once.

The user can switch to the detailed technical style with `/output-style default`.
```

- [ ] **Step 4: Add the setting.** In `user-level-reference/settings.json`, add `"outputStyle": "pm-report",` as a top-level key immediately before `"hooks": {` (keep valid JSON; 2-space indent like its neighbours).

- [ ] **Step 5: Run to verify both pass, then perturb (two-sided).**
Run: `bash scripts/verify-template-consistency.sh 2>&1 | grep -E 'check (59|60):|ALL CHECKS|FAILED'`
Expected: `PASS  check 59: ...` and `PASS  check 60: ... (name: matches)`, and `ALL CHECKS PASSED`.
Then, one at a time, each followed by a re-run that must show `FAIL  check 59` / `FAIL  check 60`, then restore with the Edit tool: (a) change the line to `keep-coding-instructions: false`; (b) change it to `keep-coding-instructions: "true"`; (c) change `"outputStyle": "pm-report"` to `"pm-reports"`; (d) change the style's `name: pm-report` to `name: pm`. Record the four FAIL lines in the report. After restoring, re-run: `ALL CHECKS PASSED`.

- [ ] **Step 6: Commit.**
```bash
git add user-level-reference/output-styles/pm-report.md user-level-reference/settings.json scripts/verify-template-consistency.sh
git commit -F <message file outside the repo>   # "feat(user-level): pm-report output style, default on (checks 59, 60)"
```

---

### Task 2: Time hook (inline `UserPromptSubmit`) + check 62 + fixture

**Files:**
- Modify: `user-level-reference/settings.json` (add `UserPromptSubmit` under `"hooks"`)
- Modify: `scripts/verify-template-consistency.sh` (insert check 62 after check 60 from Task 1 — number 61 is Task 3's, inserted between them later; order in the file is 59, 60, 62 until Task 3)
- Modify: `scripts/test-hooks.sh` (one fixture block immediately before the final tally, `echo "----...` near line 7202)
- Modify: `docs/plans/2026-09-27-pm-reporting-design.md` (Component 2 command gains `LC_ALL=C`)

**Interfaces:**
- Consumes: Task 1's `outputStyle` key placement (the `hooks` object follows it).
- Produces: the exact command literal `LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'` in the reference settings.

- [ ] **Step 1: Write the failing check 62** (insert after check 60's closing `fi`):

```bash

# ---------------------------------------------------------------------------
# Check 62 -- the reference UserPromptSubmit time hook is the exact inline
# command the v4.2.0 spec names. Inline on purpose: no script file means no
# stale-path noise (the context-mode incident, 2026-09-26) and nothing for
# check 21's mirror walk to orphan. `LC_ALL=C` keeps `%a` English on a
# non-English machine, so the line's shape never depends on the locale.
# ---------------------------------------------------------------------------
echo
note "Check 62: user-level-reference/settings.json registers the exact UserPromptSubmit time command"
c62_want="LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'"
if ! grep -q '"UserPromptSubmit"' user-level-reference/settings.json; then
  ko "check 62: user-level-reference/settings.json has no UserPromptSubmit hook"
elif grep -qF "\"command\": \"$c62_want\"" user-level-reference/settings.json; then
  ok "check 62: UserPromptSubmit runs: $c62_want"
else
  ko "check 62: the UserPromptSubmit command is not exactly: $c62_want"
fi
```

- [ ] **Step 2: Write the failing fixture** in `scripts/test-hooks.sh`, immediately before the line `echo "----------------------------------------------------------------"` that precedes the final tally (uses the file's existing `expect "<label>" "<want>" "<got>"` helper and `$ROOT`):

```bash
# ---- v4.2.0: the user-level UserPromptSubmit time hook (inline command) ----
# The command is read FROM the reference settings, not retyped here, so this
# proves what ships. Run under a German locale: LC_ALL=C must win.
UPS_CMD=$(grep -o "LC_ALL=C date '+Current local time: [^']*'" "$ROOT/user-level-reference/settings.json" | head -1)
expect "time hook: command present in reference settings" "yes" "$([ -n "$UPS_CMD" ] && echo yes || echo no)"
UPS_RE='^Current local time: [0-2][0-9]:[0-5][0-9] \([0-9]{4}-[0-9]{2}-[0-9]{2}, [A-Z][a-z]{2}\)$'
for UPS_LOC in C de_DE.UTF-8; do
  UPS_OUT=$(LANG="$UPS_LOC" LC_TIME="$UPS_LOC" bash -c "$UPS_CMD" 2>/dev/null); UPS_RC=$?
  UPS_LINES=$(printf '%s\n' "$UPS_OUT" | wc -l | tr -d ' ')
  expect "time hook: one well-formed line, exit 0 (LANG=$UPS_LOC)" "0 1 match" \
    "$UPS_RC $UPS_LINES $(printf '%s' "$UPS_OUT" | grep -qE "$UPS_RE" && echo match || echo "no-match[$UPS_OUT]")"
done
```

- [ ] **Step 3: Run to verify both fail.**
Run: `bash scripts/verify-template-consistency.sh 2>&1 | grep 'check 62:'` → `FAIL  check 62: user-level-reference/settings.json has no UserPromptSubmit hook`.
Run: `bash scripts/test-hooks.sh 2>&1 | grep 'time hook'` → `FAIL` on "command present" (and the two format lines fail with an empty command). The full suite takes long; if it exceeds the tool timeout, run it with `timeout: 600000` in the foreground, never backgrounded.

- [ ] **Step 4: Add the hook.** In `user-level-reference/settings.json`, inside `"hooks": { ... }`, after the `"PostToolUse": [ ... ]` array, add (comma-separate correctly):

```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'"
          }
        ]
      }
    ]
```

- [ ] **Step 5: Amend the spec.** In `docs/plans/2026-09-27-pm-reporting-design.md` Component 2, change the command in the JSON block to `"LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'"` and add one bullet: `- \`LC_ALL=C\` keeps \`%a\` English (\`Sat\`, not \`Sa\`) on a non-English machine, so the line's shape never depends on the locale (found while planning).`

- [ ] **Step 6: Run to verify both pass.**
`bash scripts/verify-template-consistency.sh 2>&1 | grep -E 'check 62:|ALL CHECKS'` → `PASS  check 62: ...`, `ALL CHECKS PASSED`.
`bash scripts/test-hooks.sh 2>&1 | grep -E 'time hook|ALL HOOK'` → three `PASS` lines for the time hook, `ALL HOOK FIXTURES PASSED`. Record the suite's final tally line in the report.
Perturb once: remove `LC_ALL=C ` from the command in settings → check 62 FAIL, and the fixture's "command present" FAIL; restore; re-run green.

- [ ] **Step 7: Commit.**
```bash
git add user-level-reference/settings.json scripts/verify-template-consistency.sh scripts/test-hooks.sh docs/plans/2026-09-27-pm-reporting-design.md
git commit -F <message file outside the repo>   # "feat(user-level): inline UserPromptSubmit time hook (check 62, locale-proof fixture)"
```

---

### Task 3: `backlog-board` skill + check 61

**Files:**
- Create: `user-level-reference/skills/backlog-board/board.html` (from `G:/git/.worktrees/claude-code-toolkit/pm-board-source.html`, 171 lines, outside every repo)
- Create: `user-level-reference/skills/backlog-board/SKILL.md`
- Modify: `scripts/verify-template-consistency.sh` (insert check 61 between check 60's closing `fi` and check 62's header)

**Interfaces:**
- Consumes: Task 1's style rule 5 line (exact shape above).
- Produces: `board.html` whose `STATES` object carries the seven `label: "..."` entries; SKILL.md's three pinned sentences.

- [ ] **Step 1: Write the failing check 61:**

```bash

# ---------------------------------------------------------------------------
# Check 61 -- the seven report states are ONE list in two files (v4.2.0).
# (a) The pm-report style's rule-5 line and board.html's STATES labels must be
#     the same set of exactly seven -- two copies of one list drift apart
#     silently otherwise. Empty or partial reads refuse.
# (b) The backlog-board skill states the three data rules whose breach fails
#     silently at runtime (rows without `order` vanish, unpinned writes are
#     refused, republishing churns versions without touching data).
# ---------------------------------------------------------------------------
echo
note "Check 61: report states identical in pm-report.md and board.html; board data rules stated"
c61_style=$(grep -m1 '^5\. \*\*States (exactly these):\*\* ' user-level-reference/output-styles/pm-report.md 2>/dev/null \
  | sed 's/^5\. \*\*States (exactly these):\*\* //' | tr -d '\r' | sed 's/, /\n/g' | sort)
c61_board=$(grep -o 'label: "[^"]*"' user-level-reference/skills/backlog-board/board.html 2>/dev/null \
  | sed 's/^label: "//; s/"$//' | sort)
c61_ns=$(printf '%s\n' "$c61_style" | grep -c .)
c61_nb=$(printf '%s\n' "$c61_board" | grep -c .)
if [ "$c61_ns" -ne 7 ] || [ "$c61_nb" -ne 7 ]; then
  ko "check 61a: expected 7 states on each side, read style=$c61_ns board=$c61_nb"
elif [ "$c61_style" = "$c61_board" ]; then
  ok "check 61a: the 7 report states match between pm-report.md and board.html"
else
  ko "check 61a: state labels differ -- style: [$(printf '%s;' $c61_style)] board: [$(printf '%s;' $c61_board)]"
fi
c61_skill=user-level-reference/skills/backlog-board/SKILL.md
c61_missing=""
for c61_lit in 'Every row needs an `order`' 'if_version' 'Never republish the page for a data change'; do
  grep -qF "$c61_lit" "$c61_skill" 2>/dev/null || c61_missing="$c61_missing [$c61_lit]"
done
if [ -z "$c61_missing" ]; then
  ok "check 61b: backlog-board SKILL.md states the order / if_version / no-republish rules"
else
  ko "check 61b: $c61_skill missing:$c61_missing"
fi
```

- [ ] **Step 2: Run to verify it fails.** `bash scripts/verify-template-consistency.sh 2>&1 | grep 'check 61'` → `FAIL  check 61a: expected 7 states on each side, read style=7 board=0` and `FAIL  check 61b: ... missing: [...] [...] [...]`.

- [ ] **Step 3: Create board.html.** `cp G:/git/.worktrees/claude-code-toolkit/pm-board-source.html user-level-reference/skills/backlog-board/board.html` (if the copy is refused from an isolated worktree, report NEEDS_CONTEXT — the controller copies it in). Then four edits with the Edit tool:
  1. `<title>Pit Wall Board</title>` → `<title>Backlog Board</title>`
  2. `<div class="eyebrow">Motorsport Manager agent &middot; team backlog</div>` → `<div class="eyebrow">__PROJECT_NAME__ &middot; backlog</div>`
  3. `<h1>Pit Wall Board</h1>` → `<h1>Backlog Board</h1>`
  4. `"testing": {label: "Testing in the game", cls: "s-testing"},` → `"testing": {label: "Testing live", cls: "s-testing"},`
  5. `<footer>States: Done, In progress, Testing in the game, Needs rework, Open, Waiting on you, Blocked. Claude updates this board whenever an item changes state.</footer>` → `<footer>Claude updates this board whenever an item changes state.</footer>` (removes a third copy of the list instead of pinning it).
  Verify: `grep -c 'Pit Wall\|Motorsport\|in the game' user-level-reference/skills/backlog-board/board.html` → `0`; `file` / `git ls-files --eol` after staging shows LF.

- [ ] **Step 4: Create SKILL.md** `user-level-reference/skills/backlog-board/SKILL.md`, exactly:

```markdown
---
name: backlog-board
description: Create or update a project's live backlog board (a private web page with a colour-coded state per item). Use when a project with a backlog has no board yet (offer once), or after any backlog item changes state.
---

# Backlog board

A private page showing the project's backlog: one row per capability with a colour-coded state, a one-line note, a tally, and the latest headline. It pairs with the `pm-report` output style; where a board exists it is the source of truth for the backlog and the chat table mirrors it.

## States

| key | label |
|---|---|
| `done` | Done |
| `progress` | In progress |
| `testing` | Testing live |
| `rework` | Needs rework |
| `open` | Open |
| `waiting` | Waiting on you |
| `blocked` | Blocked |

## Create -- once per project, only after the user says yes

1. Load the `artifact-capabilities` skill (required before passing `capabilities`).
2. Copy `~/.claude/skills/backlog-board/board.html` into the session scratchpad and replace `__PROJECT_NAME__` with the project's plain name.
3. Publish it with the Artifact tool: `capabilities: {"db": {}}`, icon `list`, a one-sentence description. It is private by default.
4. Seed the data with ONE `ArtifactData` `batch` of `set` writes (new documents, so no `if_version`): collection `backlog`, doc ids `item-01`, `item-02`, ..., data `{order, title, state, note}`; and collection `meta`, doc `latest`, data `{headline, updated}`. Every row needs an `order` -- the page sorts by it and silently drops a row without one. `updated` is an ISO 8601 string from `date -Iseconds`.
5. Record the page address in this project's auto-memory as a `project` memory ("Backlog board: <url>"). Never in a committed file.

## Update -- on every state change

1. `ArtifactData` `list` on collection `backlog` and `get` on `meta/latest`; each result carries the document's `version`.
2. ONE `batch`: an `update` per changed row plus `meta/latest` (new `headline`, `updated` from `date -Iseconds`), each entry pinned with `if_version` = the version just read. A new item is a `set` with the next `order`.
3. If the batch is refused because a document changed since the read, re-read and redo it -- never drop the pin.
4. Never republish the page for a data change: republishing does not touch the data and only churns versions.

## Rules

- Notes are one plain sentence; the page renders them as text, so no HTML or markdown.
- Plain words only: no paths, commit ids, secrets or internal labels on the page.
- If the Artifact tools are not available in this session, report in chat only and say so once.
- Previews and thumbnails show an offline note (no live data there) -- expected, not a fault.
```

- [ ] **Step 5: Run to verify it passes, then perturb.**
`bash scripts/verify-template-consistency.sh 2>&1 | grep -E 'check 61|ALL CHECKS'` → `PASS  check 61a`, `PASS  check 61b`, `ALL CHECKS PASSED`.
Perturb one at a time, re-run, expect FAIL, restore: (a) board label `Testing live` → `Testing` (61a FAIL, sets differ); (b) delete `, Blocked` from the style's rule-5 line (61a FAIL, style=6); (c) delete the sentence containing `if_version` in Update step 2 (61b FAIL). Record the three FAIL lines. Re-run: `ALL CHECKS PASSED`.

- [ ] **Step 6: Commit.**
```bash
git add user-level-reference/skills/backlog-board/SKILL.md user-level-reference/skills/backlog-board/board.html scripts/verify-template-consistency.sh
git commit -F <message file outside the repo>   # "feat(user-level): backlog-board skill (check 61 pins the state list)"
```

---

### Task 4: Drift probe covers `output-styles/**`

**Files:**
- Modify: `scripts/verify-user-level-drift.sh:4`, `:55` (comments), `:160`, `:180` (`for sub in hooks skills agents; do`), `:341` (`find user-level-reference/hooks user-level-reference/skills user-level-reference/agents -type f`)

**Interfaces:**
- Consumes: Task 1's `user-level-reference/output-styles/pm-report.md`.

- [ ] **Step 1: Write the failing probe (two-sided, isolated HOME).** Create `C:/…/scratchpad/drift-probe.sh` (outside the repo):

```bash
#!/usr/bin/env bash
# Two-sided: a live tree missing the output style must report it; a complete one must not.
set -u
cd "$1" || exit 1                      # $1 = the worktree
T=$(mktemp -d)
mkdir -p "$T/.claude"
cp -r user-level-reference/. "$T/.claude/"
rm -f "$T/.claude/output-styles/pm-report.md"
out_missing=$(HOME="$T" bash scripts/verify-user-level-drift.sh --worktree 2>&1)
cp user-level-reference/output-styles/pm-report.md "$T/.claude/output-styles/pm-report.md"
out_full=$(HOME="$T" bash scripts/verify-user-level-drift.sh --worktree 2>&1)
printf '%s\n' "$out_missing" | grep -q 'output-styles/pm-report.md' && echo "MISSING-CASE: reported" || echo "MISSING-CASE: NOT reported"
printf '%s\n' "$out_full" | grep -E 'files checked' 
rm -rf "$T"
```

- [ ] **Step 2: Run it before the change.** `bash <scratchpad>/drift-probe.sh G:/git/.worktrees/claude-code-toolkit/pm-reporting`
Expected: `MISSING-CASE: NOT reported` (the probe does not look at `output-styles/` yet). Record the `files checked` line.

- [ ] **Step 3: Implement.** Line 160 and line 180: `for sub in hooks skills agents; do` → `for sub in hooks skills agents output-styles; do`. Line 341: add `user-level-reference/output-styles` to the `find` list. Line 4: `{CLAUDE.md,hooks/**,skills/**,agents/**}` → `{CLAUDE.md,hooks/**,skills/**,agents/**,output-styles/**}`. Line 55: `CLAUDE.md + hooks/ + skills/ + agents/` → `CLAUDE.md + hooks/ + skills/ + agents/ + output-styles/`.

- [ ] **Step 4: Run the probe again.** Expected: `MISSING-CASE: reported`, and the full case's `files checked` line shows **one more file checked** than Step 2 and `0 drift`. Record both lines. (A `settings.json` note about `autoMode.environment` may print; it is unrelated.)

- [ ] **Step 5: Commit.**
```bash
git add scripts/verify-user-level-drift.sh
git commit -F <message file outside the repo>   # "feat(drift): verify-user-level-drift covers output-styles/**"
```

---

### Task 5: Release docs — CHANGELOG, VERSION, context tables

**Files:**
- Modify: `VERSION`, `CHANGELOG.md` (new top section), `README.md:53-66` (*The trim pass, measured*), `docs/architecture.md` (*Context Budget* table)

**Interfaces:**
- Consumes: Tasks 1–4 merged on the branch; measured figures.

- [ ] **Step 1: Measure, never carry forward.**
```bash
wc -c templates/general/CLAUDE.md user-level-reference/CLAUDE.md templates/general/.claude/rules/project.md templates/general/.claude/project-instructions.md templates/general/PROJECT_CONTEXT.md user-level-reference/output-styles/pm-report.md
for v in general dotnet dotnet-maui rust-tauri java python; do wc -c templates/$v/CLAUDE.md templates/$v/PROJECT_CONTEXT.md templates/$v/.claude/rules/project.md templates/$v/.claude/project-instructions.md; done
grep -m1 '^description:' user-level-reference/skills/backlog-board/SKILL.md | wc -c
```
Every template figure must equal v4.1.2's (no template changed); if one differs, stop and report — a template changed that the spec says must not.

- [ ] **Step 2: VERSION** → two lines: `4.2.0` and `PM-level reporting: a switchable, default-on pm-report output style, an inline UserPromptSubmit time hook and a backlog-board skill, all user-level (checks 59-62, drift covers output-styles/**).`

- [ ] **Step 3: CHANGELOG** — new top section `## v4.2.0 — <today, YYYY-MM-DD>` above `## v4.1.2`, containing: a one-paragraph summary; `### Added` (the style with `keep-coding-instructions: true`, the inline time hook with `LC_ALL=C`, the backlog-board skill, checks 59–62, the drift extension, the fixture); counts **measured at the release tip** (consistency PASS count, hook-suite `passed/failed/skipped (assertions)`, server suite) — never estimated; the signed line `**Floor reviewed: unchanged — the sync-template skill body is untouched by this release; v4.2.0 adds user-level files only.**` (check 56 requires a `Floor reviewed:` line); `### Downstream migration` (1. copy `user-level-reference/output-styles/pm-report.md` → `~/.claude/output-styles/`, `user-level-reference/skills/backlog-board/` → `~/.claude/skills/backlog-board/`; 2. add `"outputStyle": "pm-report"` and the `UserPromptSubmit` entry to `~/.claude/settings.json` — diff live vs reference first, the live file carries machine-specific entries; 3. the default applies to NEW sessions; `/output-style default` switches a session back; 4. no `/sync-template` needed — no template changed; 5. run `bash scripts/verify-user-level-drift.sh` → 0 drift).

- [ ] **Step 4: Context tables.** README: add a column `**v4.2.0**` (un-bold `v4.1.2`), and a new row after `user-level CLAUDE.md`: `user-level output style \`pm-report\` (default on; \`/output-style default\` removes it)` with `—` for every older column and the measured bytes for v4.2.0; recompute the **harness-injected** and **at the end of bootstrap** v4.2.0 cells as sums of that column's rows (the style counts as injected: it enters the system prompt at session start). Append one prose sentence to the paragraph at `README.md:66` stating the v4.2.0 growth figure (style bytes), that the time hook adds ~45 B per user message and the skill description ~<measured> B to the skill listing, and that no template file changed. Apply the same column/row/sum change to `docs/architecture.md`'s *Context Budget* table for every variant it lists.

- [ ] **Step 5: Verify.** `bash scripts/verify-template-consistency.sh 2>&1 | tail -3` → `ALL CHECKS PASSED` (checks 56/57 read the new top section). `grep -n 'v4.2.0' README.md docs/architecture.md CHANGELOG.md VERSION | head`.

- [ ] **Step 6: Commit.**
```bash
git add VERSION CHANGELOG.md README.md docs/architecture.md
git commit -F <message file outside the repo>   # "docs(release): v4.2.0 -- CHANGELOG, VERSION, measured context tables"
```

---

### Task 6 (controller only, main thread — needs the user at two points)

1. **Gate, with the user's say-so** (it slows the whole machine): `bash hooks/run-gate.sh` from the worktree, foreground, timeout 600000; announce start and end times. Green = consistency, hook suite, server suite.
2. **Outside review:** the mcp-dev-servers session reviews the branch at its exact sha with a named scope; findings are fixed on the branch.
3. **Live install — ask the user first** (it edits the live `~/.claude/settings.json`): copy the style and the skill, add the two settings entries after diffing live vs reference; `bash scripts/verify-user-level-drift.sh --worktree` → 0 drift.
4. **Live acceptance** (spec): a fresh session's first message starts with `[HH:MM]` within a minute of `date`; `/output-style default` switches to the technical style and back; in a scratch project, create a board, change one row via a pinned `batch`, see the page update, no republish.
5. Open the PR `feat/pm-reporting` → `main`; the user runs the merge. Tag `v4.2.0` and the GitHub release after the merge, as for v4.1.2.

---

## Execution notes (2026-09-27)

Three corrections made during execution, against this plan as written above; the plan's own code blocks are left as originally written (they are a record of what was drafted, not what shipped) — the shipped text is in the files at the commits below.

- **R-3 (`99f50ca`):** check 60's name match is `grep -Fqx`, not `grep -qx` as Task 1 Step 1 wrote it above. A plain `-qx` is a regex match, so `pm.report` (the `.` an unquoted-regex wildcard) matches the literal `pm-report`, which the check's third arm reads as `name:` agreeing with `outputStyle` when the two strings actually differ. `-F` makes the comparison literal, closing that gap.
- **R-4 (`6e12866`):** the fixture regex and the spec's own command have no comma between the date and the weekday — `\([0-9]{4}-[0-9]{2}-[0-9]{2} [A-Z][a-z]{2}\)`. Task 2 Step 2 above wrote the regex with `, ` (`\([0-9]{4}-[0-9]{2}-[0-9]{2}, [A-Z][a-z]{2}\)`), which never matched the actual command's output (`date '+... (%Y-%m-%d %a)'` prints no comma) and would have failed the fixture the moment it ran for real, not just on perturbation.
- **R-5 (`5c35ec2`):** check 61b's literal for the update rule is pinned as `each entry pinned with \`if_version\``, not the bare `if_version` string Task 3 Step 1 wrote above. The bare string also matches SKILL.md's Create step, which explicitly notes new documents need "no `if_version`" — so a check written against the bare token stayed green even after the Update step's own pinning sentence was deleted, which is exactly the silent-drift shape check 61 exists to catch. The fix pins the fuller phrase so it can only match the Update rule. Check 61a's diagnostic message was fixed in the same commit to keep multi-word labels whole (`printf '%s;' $c61_style` word-splits on the unquoted expansion, corrupting any label with an internal space in the FAIL message) rather than changing the check's pass/fail logic.
