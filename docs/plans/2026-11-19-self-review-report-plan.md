# Self-review report (stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only counter that each machine runs over its own Claude Code session records, and a toolkit-repo-local `/self-review` command that joins both machines' counts with the Claude Code changelog and writes at most 10 ranked suggestions to `docs/self-review/<date>.md`.

**Architecture:**
- `scripts/self-review-count.py` reuses `measure-process.py`'s transcript loader and `jev-tally.py`'s event loader. It writes two files to `~/.cache/cct-self-review/`: a shareable counts-only JSON and a local-only JSON with per-project detail and correction candidates.
- `.claude/skills/self-review/SKILL.md` lives in this repo only, not in the plugin. It drives the run on both machines, the grouping of corrections, the changelog read and the report.
- Consistency check 82 pins the counter's self-test and the skill's placement.

**Tech Stack:** Python 3 stdlib only; bash (`verify-template-consistency.sh`); Markdown skill.

**Spec:** `docs/plans/2026-11-19-self-review-report-design.md` (approved by the user 2026-11-19 17:43).

## Global Constraints

- KISS. No dependency outside the Python stdlib. The counter never calls a model or the network.
- Read-only on transcripts, Jev events and notes files. Writes only to the `--out` path and its `.local.json` sibling.
- The shareable JSON holds no conversation text, no path below the clone root, no project or repo name, and no env value.
- Default output directory: `~/.cache/cct-self-review/`. Default window: 30 days back from today, matched on each row's own timestamp.
- Runs on Linux and on Windows (Git Bash with `python` or `python3`); use `os.path` throughout.
- Never shipped to consumers: nothing in `templates/`, nothing in the plugin's `skills/` or `agents/`.
- Agents never print environment variable values. Run every command with `env -u TYPESAFE_API_KEY`.
- No heredocs in Bash calls. Multi-step shell goes in a script file that is run with `bash <path>`.

## Review Focus

1. **User rows that are not typed by the user** (tool results, `isMeta` rows, `<command-name>`/`<local-command-stdout>`/`<system-reminder>` wrappers, cross-session and agent messages) must never count as correction candidates. Pinned by `test: wrapper rows are not corrections` (Task 2).
2. **Assistant rows with model `<synthetic>` or no `usage`** must count no tokens and no model. Pinned by fixture row `synthetic` (Task 1).
3. **A subagent transcript without `.meta.json`** counts its spawn under agent type `unknown`, without crashing. Pinned by fixture `sub-nometa` (Task 1).
4. **Skill and agent names with or without the `cct:` prefix** count once, under the bare name. Names that are not the toolkit's are not listed. Pinned by fixtures `Skill cct:commit`, `Skill commit` and `Skill other-plugin:x` (Task 1).
5. **An unreadable transcript** (a directory named `*.jsonl`) is counted in `unreadable_files` and is not fatal. Pinned by fixture `broken.jsonl/` (Task 1).

---

### Task 1: Counter core — window, model per spawn, toolkit use, token share

**Files:**
- Create: `scripts/self-review-count.py`
- Create: `scripts/fixtures/self-review/projects/-home-u-git-alpha/*.jsonl`, plus a `<session>/subagents/agent-*.jsonl` (+ `.meta.json`) and `broken.jsonl/.gitkeep`
- Create: `scripts/fixtures/self-review/expected.json`

**Interfaces:**
- Consumes: `load_rows(path) -> list[dict]` and `parse_ts(row) -> datetime | None` from `scripts/measure-process.py`, loaded with `importlib.util.spec_from_file_location` (the file name has a dash). Also `compare(actual, expected, path='') -> list[str]` from the same file.
- Produces:
  - `count(projects_root: str, clone_root: str, toolkit_root: str, since: str, until: str | None, machine: str) -> tuple[dict, dict]`. It returns `(shared, local)`, and later tasks add keys to both.
  - `shared` keys from this task:
    - `schema` (=1), `machine`, `since`, `until`;
    - `claude_code_versions` {version: rows};
    - `spawns` {agent_type: {model: n}};
    - `tokens_by_model` {model: {input, cache_read, output}};
    - `token_share` {main: {input, cache_read, output}, sub: {...}, sub_share: float rounded to 4 places, = sub total / (main + sub) total over all three};
    - `toolkit_use` {skills: {name: n}, agents: {name: n}}, listing every toolkit skill dir and `agents/*.md` name with its count, 0 included;
    - `unreadable_files`.
  - `local` keys from this task: `per_project` {slug: {spawns, tokens}}.
  - CLI: `--since`, `--until`, `--root` (default `~/.claude/projects`), `--clone-root` (default `~/git`), `--toolkit` (default: the repo containing the script), `--machine` (default `platform.system().lower()`), `--out` (default `~/.cache/cct-self-review/<machine>-<today>.json`), `--self-test`.

- [ ] **Step 1: Write the fixtures and `expected.json`.**
  - Two main transcripts. One has rows inside the window and one row dated before `--since`, which must not count.
  - Assistant rows with `message.model` `claude-sonnet-5-5` and `claude-opus-5-5`, and `usage` {input_tokens, cache_read_input_tokens, output_tokens}. One assistant row has model `<synthetic>` and no usage.
  - Rows with `version` `2.1.328`.
  - Skill `tool_use` calls: `cct:commit`, `commit` and `other-plugin:x`.
  - Agent `tool_use` calls: `cct:coder` and `general-purpose`.
  - Two subagent transcripts: one with `.meta.json` `{"agentType": "cct:coder"}`, and one (`sub-nometa`) with no meta.
  - A `broken.jsonl/` directory containing `.gitkeep`.
  - A fake toolkit root in the fixture (`toolkit/skills/commit/`, `toolkit/skills/sprint/`, `toolkit/agents/coder.md`), so the expected counts do not move when the real toolkit gains a skill.
  - `expected.json` holds the exact `shared` dict for `--since 2026-11-01 --until 2026-11-30 --machine fixture`. It includes `toolkit_use.skills` = {commit: 2, sprint: 0}, `toolkit_use.agents` = {coder: 1}, `unreadable_files` = 1, and spawns {`cct:coder`→coder model: 1, `unknown`: {...}: 1}.
- [ ] **Step 2: Implement `--self-test`.** It runs `count()` on the fixtures and compares with `expected.json` via `compare`. It has a control: a deliberately wrong `sub_share` must be reported. It prints `SELF-TEST PASS` or `SELF-TEST FAIL <path>` lines and returns 0 or 1.
  - Run: `python3 scripts/self-review-count.py --self-test`. Expected: FAIL (`count` is not yet implemented).
- [ ] **Step 3: Implement `count()` and `main()`.**
  - Window: per row, via `parse_ts`; rows without a timestamp are skipped.
  - Spawn model: the first non-synthetic `message.model` in the subagent transcript.
  - Names: strip a `cct:` prefix; count only names present in the toolkit lists.
  - Write `shared` to `--out` and `local` to `--out` with `.json` replaced by `.local.json`, both with `indent=2`, `sort_keys=True`, UTF-8 and LF.
  - Run: `python3 scripts/self-review-count.py --self-test`. Expected: `SELF-TEST PASS`.
- [ ] **Step 4: Commit.**
  - Run `git add scripts/self-review-count.py scripts/fixtures/self-review`.
  - Commit message: `feat(self-review): counter core (model per spawn, toolkit use, token share)`.

### Task 2: Hook blocks, correction candidates, notes, Jev

**Files:**
- Modify: `scripts/self-review-count.py`
- Modify: `scripts/fixtures/self-review/` (new rows), `expected.json`
- Create: `scripts/fixtures/self-review/clones/beta/.claude/improvement-notes.jsonl`, `scripts/fixtures/self-review/clones/beta/.git/jev/events/e1.json` and `e2.json`

**Interfaces:**
- Consumes: Task 1's `count()`, and `_load_events(roots, since) -> (list[dict], int)` from `scripts/jev-tally.py` (loaded the same way).
- Produces new keys:
  - `shared.hook_blocks` {hook: n}.
  - `shared.correction_candidates` (int).
  - `shared.notes` {kind: {surface: {"count": summed count, "projects": number of distinct projects}}}, where `kind` ∈ `helped|recurring_failure|rule_unused`. `projects` is what lets the report find a lesson seen in 2-3 projects (spec §6) without naming them.
  - `shared.notes_malformed` (int).
  - `shared.jev` {events, applied, up, down}.
  - `local.corrections` [{project, ts, text}], where `text` is cut to 300 chars.
  - `local.notes` {project: [note, ...]}.

- [ ] **Step 1: Add fixture rows.**
  - Two tool results containing `BLOCKED: gate-before-merge refuses` and one containing `BLOCKED: deny-hang-shapes: use`.
  - Typed user turns:
    - `no, don't run the gate without asking ZZ-PRIVATE-MARKER-7f3a` (a candidate);
    - `that's not what I asked` (a candidate);
    - `thanks, looks good` (not a candidate).
  - Wrapper rows that start with each of: `<command-name>`, `<local-command-stdout>`, `<system-reminder>`, `<cross-session-message`, `<agent-message`, `<task-notification>`; an `isMeta` row; and a `tool_result` row whose text begins `No`. None of them is a candidate.
  - A notes file with two valid lines and one malformed line.
  - Two Jev events, one with `applied: true`.
  - Extend `expected.json`: `hook_blocks` {gate-before-merge: 2, deny-hang-shapes: 1}, `correction_candidates` 2, `notes_malformed` 1, `jev` {events: 2, applied: 1, ...}.
- [ ] **Step 2: Extend `--self-test` with these assertions:**
  - `"ZZ-PRIVATE-MARKER-7f3a" not in json.dumps(shared)`;
  - control: `"ZZ-PRIVATE-MARKER-7f3a" in json.dumps(local)` (proves the fixture reaches the candidate path);
  - `"beta" not in json.dumps(shared)` (no project name).
  - Run the self-test. Expected: FAIL.
- [ ] **Step 3: Implement.**
  - Block regex: `BLOCKED: ([a-z0-9][a-z0-9-]*)` over tool-result text.
  - Correction rule: a `type: user` row, not `isMeta`, whose text is not a tool result. Strip it; skip it if it starts with `<`. It is a candidate when it matches, case-insensitive, `^(no\b|nope\b|don'?t\b|do not\b|stop\b|wrong\b|that'?s (not|wrong)\b|not what\b|i said\b|i told you\b|why did you\b|you (forgot|missed|didn'?t)\b)`.
  - Notes: `<clone_root>/*/.claude/improvement-notes.jsonl`. Jev: `_load_events([clone_root], since)` → events, applied, up, down. Compute `up` and `down` as `jev-tally.tally` does; no repo names.
  - Run the self-test. Expected: `SELF-TEST PASS`.
- [ ] **Step 4: Commit.** Message: `feat(self-review): hook blocks, correction candidates, notes, Jev`.

### Task 3: The `/self-review` command, check 82, the release rule

**Files:**
- Create: `.claude/skills/self-review/SKILL.md`
- Modify: `.gitignore` (after `!/.claude/settings.json`, add `!/.claude/skills/`)
- Modify: `scripts/verify-template-consistency.sh` (append check 82 after check 81)
- Modify: `CLAUDE.md` (root): one Invariants bullet

**Interfaces:**
- Consumes: Task 1's and Task 2's CLI and JSON keys.
- Produces: the command the release step runs.

- [ ] **Step 1: Write `SKILL.md`.**
  - Frontmatter: `name: self-review`, a one-line `description`, `disable-model-invocation: true`.
  - Body, in order:
    1. Run `env -u TYPESAFE_API_KEY python3 scripts/self-review-count.py --since <date of the previous docs/self-review report, else 30 days back>`.
    2. Read the `.local.json` corrections and group them into behaviour kinds (agent behaviour only, never project content). Add `"correction_kinds": [{"kind","count"}]` to the shared JSON. Never copy candidate text anywhere.
    3. Message cc-toolkit-windows with the same two steps for the PC (`--clone-root G:/git`). It must reply with the finished shared JSON only. If it is offline, note "PC not included".
    4. Read the Claude Code changelog (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) from the version named in the previous report's header, looking for features that make a toolkit rule redundant or newly possible.
    5. Write `docs/self-review/<YYYY-MM-DD>.md`.
  - Report template:
    - **Header:** date, window, Claude Code versions and models seen, machines, the previous report or "first report".
    - **Key numbers:** one table, one column per machine plus a total, with the measures in `shared`. Add the Context Budget figure from `docs/architecture.md`'s last column.
    - **At most 10 items**, ranked by cost saved or quality gained. Each gives the evidence, the change, the effect, the risk, and the files touched.
    - **Since last report:** one line.
  - Closing rule: the report is committed in the release PR, and nothing is applied; each item waits for the user's approval.
- [ ] **Step 2: Write check 82 in the style of check 66.**
  - (a) `python3 scripts/self-review-count.py --self-test` passes; skip with a reason when there is no `python3`.
  - (b) `git ls-files .claude/skills/self-review/SKILL.md` is non-empty, and the file contains `disable-model-invocation: true`.
  - (c) `skills/self-review` does not exist (it must not ship in the plugin).
  - Two-sided: for each of (b) and (c), run the predicate on a temp copy that violates it (a SKILL.md without the line; a temp `skills/self-review/` dir), and assert it reports.
  - Run: `bash scripts/verify-template-consistency.sh` (wrapped in a scratchpad script). Expected: `ALL CHECKS PASSED`, check 82 PASS.
- [ ] **Step 3: Add to the root `CLAUDE.md` Invariants:** "**Every release runs `/self-review`** (the repo-local skill in `.claude/skills/self-review/`) and ships its `docs/self-review/<date>.md` in the release PR; nothing in the report is applied without the user's approval of that item."
- [ ] **Step 4: Commit.** Message: `feat(self-review): repo-local /self-review command, check 82, release rule`.

### Task 4: First real report (controller, attended)

Not delegated: this task needs the PC helper, and the grouping step reads private text locally.

- [ ] **Step 1:** Run `/self-review` on this server. It needs an idle machine, so first check that no gate or matrix is running.
- [ ] **Step 2:** Get the PC's JSON from cc-toolkit-windows. That is a light job, but it waits for mm-agent's all-clear and the user's go.
- [ ] **Step 3:** Write `docs/self-review/<date>.md`. Before committing, check it: `grep` for every repo directory name under `~/git` (except `claude-code-toolkit`), and expect no hits.
- [ ] **Step 4:** Commit with message `docs(self-review): first report`, then run the full gate and open the PR.
