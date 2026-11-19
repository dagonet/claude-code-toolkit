# Self-review report (stage 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A read-only counter that any toolkit user runs on each of their machines over all of that machine's Claude Code session records, and a toolkit-repo-local `/self-review` command. The command merges however many machines' counts are in its inbox, adds what changed in Claude Code, and writes at most 10 ranked suggestions to `docs/self-review/<date>.md`.

**Architecture:**
- `scripts/self-review-count.py` reuses `measure-process.py`'s transcript loader and `jev-tally.py`'s event loader. It writes two files to `~/.cache/cct-self-review/`: a shareable counts-only JSON and a local-only JSON with per-project detail and correction candidates.
- `--merge DIR` turns any number of shareable JSONs into the key-numbers table.
- `.claude/skills/self-review/SKILL.md` lives in this repo only, not in the plugin. It drives the local run, the grouping of corrections, the collection of other machines' files (manual copy or a peer session, no transport built), the changelog read and the report.
- `docs/self-review/README.md` tells a public user how to run it on one machine or several.
- Consistency check 82 pins the counter's self-test and the skill's placement.

**Tech Stack:** Python 3 stdlib only; bash (`verify-template-consistency.sh`); Markdown skill.

**Spec:** `docs/plans/2026-11-19-self-review-report-design.md` (approved by the user 2026-11-19 17:43).

## Global Constraints

- KISS. No dependency outside the Python stdlib. The counter never calls a model or the network.
- Read-only on transcripts, Jev events and notes files. Writes only to the `--out` path and its `.local.json` sibling.
- The shareable JSON holds no conversation text, no path below the clone root, no project or repo name, and no env value.
- Default output directory: `~/.cache/cct-self-review/`. Default window: 30 days back from today, matched on each row's own timestamp.
- Runs on Linux, macOS and Windows (Git Bash with `python` or `python3`); use `os.path` throughout.
- **Generic, public-repo rule (user, 2026-11-19 17:52):** no code, skill text, fixture or doc names the maintainer's machines, paths (`~/git`, `G:/git`), hostnames or peer sessions. Every default is derived:
  - `--root`: `$CLAUDE_CONFIG_DIR/projects`, else `~/.claude/projects`.
  - `--clone-root` (repeatable): the parent directory of the toolkit checkout.
  - `--machine`: `<platform.system().lower()>-<first 6 hex of sha256(socket.gethostname())>`.
- Never shipped to consumers: nothing in `templates/`, nothing in the plugin's `skills/` or `agents/`.
- Agents never print environment variable values. Run every command with `env -u TYPESAFE_API_KEY`.
- No heredocs in Bash calls. Multi-step shell goes in a script file that is run with `bash <path>`.

## Review Focus

1. **User rows that are not typed by the user** (tool results, `isMeta` rows, `<command-name>`/`<local-command-stdout>`/`<system-reminder>` wrappers, cross-session and agent messages) must never count as correction candidates. Pinned by `test: wrapper rows are not corrections` (Task 2).
2. **Assistant rows with model `<synthetic>` or no `usage`** must count no tokens and no model. Pinned by fixture row `synthetic` (Task 1).
3. **A subagent transcript without `.meta.json`** counts its spawn under agent type `unknown`, without crashing. Pinned by fixture `sub-nometa` (Task 1).
4. **Skill and agent names with or without the `cct:` prefix** count once, under the bare name. Names that are not the toolkit's are not listed. Pinned by fixtures `Skill cct:commit`, `Skill commit` and `Skill other-plugin:x` (Task 1).
5. **An unreadable transcript** (a directory named `*.jsonl`) is counted in `unreadable_files` and is not fatal. Pinned by fixture `broken.jsonl/` (Task 1).
6. **The default machine label** must not contain the hostname, and two different hostnames must give two different labels. Pinned in Task 1's self-test.

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
  - CLI: `--since`, `--until`, `--root`, `--clone-root` (repeatable), `--toolkit` (default: the repo containing the script), `--machine`, `--out` (default `~/.cache/cct-self-review/<machine>-<today>.json`), `--self-test`. The `--root`, `--clone-root` and `--machine` defaults are as in Global Constraints.
  - `default_machine(hostname: str, system: str) -> str`, a pure function so the self-test can call it with fixed inputs.

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
- [ ] **Step 2: Implement `--self-test`.** It runs `count()` on the fixtures and compares with `expected.json` via `compare`. It has a control: a deliberately wrong `sub_share` must be reported. It also asserts that `default_machine('host-a', 'Linux')` matches `^linux-[0-9a-f]{6}$`, does not contain `host-a`, and differs from `default_machine('host-b', 'Linux')`. It prints `SELF-TEST PASS` or `SELF-TEST FAIL <path>` lines and returns 0 or 1.
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
  - Notes: `<each clone root>/*/.claude/improvement-notes.jsonl`. Jev: `_load_events(clone_roots, since)` → events, applied, up, down. Compute `up` and `down` as `jev-tally.tally` does; no repo names.
  - After writing, the CLI prints the two paths and this one line, verbatim, for whoever runs it on another machine: `Next: in a Claude session on this machine, ask it to group the "corrections" in <local path> into agent-behaviour kinds and add "correction_kinds": [{"kind": ..., "count": ...}] to <shared path>; then copy <shared path> to the inbox of the machine that runs /self-review.`
  - Run the self-test. Expected: `SELF-TEST PASS`.
- [ ] **Step 4: Commit.** Message: `feat(self-review): hook blocks, correction candidates, notes, Jev`.

### Task 3: Merge any number of machines

**Files:**
- Modify: `scripts/self-review-count.py`
- Create: `scripts/fixtures/self-review/inbox/linux-aaaaaa.json`, `scripts/fixtures/self-review/inbox/windows-bbbbbb.json`, `scripts/fixtures/self-review/expected-merge.md`

**Interfaces:**
- Consumes: the shared JSON keys of Tasks 1 and 2, plus the optional `correction_kinds`.
- Produces:
  - `merge(paths: list[str]) -> str`: a Markdown table with one row per measure, one column per machine label (sorted) and a `total` column.
  - CLI `--merge DIR`: it reads every `*.json` in `DIR` that is not `*.local.json` and prints the table. A file that fails to parse or has `schema` ≠ 1 is listed below the table as `skipped: <file name>`, and is not fatal.

- [ ] **Step 1: Write the fixtures.** Two shared JSONs with different labels and values, one of them carrying `correction_kinds`. `expected-merge.md` holds the exact table. Rows:
  - spawns per model;
  - tokens per model;
  - `sub_share`;
  - each toolkit skill and agent count;
  - hook blocks per hook;
  - correction candidates and kinds;
  - notes per kind;
  - Jev events/applied;
  - unreadable files.
  - Totals are sums. `sub_share`'s total is recomputed from the summed tokens, never averaged.
- [ ] **Step 2: Extend `--self-test`** with three checks:
  - `merge()` over the fixture inbox equals `expected-merge.md`;
  - a third, malformed file in a temp copy of the inbox appears as `skipped:`;
  - the one-machine case (one file) still has a `total` column.
  - Run it. Expected: FAIL.
- [ ] **Step 3: Implement `merge()` and `--merge`.** Run the self-test. Expected: `SELF-TEST PASS`.
- [ ] **Step 4: Commit.** Message: `feat(self-review): merge any number of machines' counts`.

### Task 4: The `/self-review` command, user docs, check 82, the release rule

**Files:**
- Create: `.claude/skills/self-review/SKILL.md`
- Create: `docs/self-review/README.md`
- Modify: `.gitignore` (after `!/.claude/settings.json`, add `!/.claude/skills/`)
- Modify: `scripts/verify-template-consistency.sh` (append check 82 after check 81)
- Modify: `CLAUDE.md` (root): one Invariants bullet

**Interfaces:**
- Consumes: the CLI of Tasks 1-3 (`--since`, `--out`, `--merge`) and the JSON keys.
- Produces: the command the release step runs, and the docs a public user follows.

- [ ] **Step 1: Write `SKILL.md`.**
  - Frontmatter: `name: self-review`, a one-line `description`, `disable-model-invocation: true`.
  - No machine name, path, hostname or peer-session name of anyone's setup appears anywhere in the file.
  - Body, in order:
    1. Run `python3 scripts/self-review-count.py --since <date of the previous docs/self-review report, else 30 days back> --out ~/.cache/cct-self-review/inbox/<label>.json` (on Windows, `python` if `python3` is absent).
    2. Read the `.local.json` corrections and group them into behaviour kinds (agent behaviour only, never project content). Add `"correction_kinds": [{"kind","count"}]` to the shared JSON. Never copy candidate text anywhere.
    3. Ask the user once which other machines to include. For each one, give the two ways in, then continue with whatever is in the inbox, without waiting:
       - **(a) Manual:** run the same counter there, follow its printed "Next:" line, and copy the shared JSON into this machine's `~/.cache/cct-self-review/inbox/`.
       - **(b) Peer session:** if a Claude session on that machine can be messaged, ask it to do (a) and reply with the shared JSON text only. Write that text to the inbox.
       - A machine label that appears in the previous report's table but not in the inbox is named in the header as "not included this time".
    4. Run `python3 scripts/self-review-count.py --merge ~/.cache/cct-self-review/inbox/` and paste its table unchanged.
    5. Read the Claude Code changelog (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md) from the version named in the previous report's header, looking for features that make a toolkit rule redundant or newly possible.
    6. Write `docs/self-review/<YYYY-MM-DD>.md`.
    7. Before saving, check the report for project or repo names from the `.local.json` files and remove any that appear.
  - Report template:
    - **Header:** date, window, Claude Code versions and models seen, machine labels, the previous report or "first report", and one line that sessions whose records are on no included machine (for example cloud-hosted ones) are not counted.
    - **Key numbers:** the merged table. Add the Context Budget figure from `docs/architecture.md`'s last column.
    - **At most 10 items**, ranked by cost saved or quality gained. Each gives the evidence, the change, the effect, the risk, and the files touched.
    - **Since last report:** one line.
  - Closing rule: nothing is applied, and each item waits for the user's approval. The maintainer commits the report in the release PR. Anyone else keeps theirs in their own checkout, and may offer findings upstream via `contribute-upstream`.
- [ ] **Step 2: Write `docs/self-review/README.md`** (at most about 40 lines) for a public user. It covers:
  - what the report is and what never leaves a machine;
  - one machine: run `/self-review` in a toolkit checkout;
  - several machines: run the counter on each, follow the "Next:" line, and copy the JSON to the inbox;
  - the flags and their defaults.
  - Link it from `README.md`'s docs list, one line.
- [ ] **Step 3: Write check 82 in the style of check 66.**
  - (a) `python3 scripts/self-review-count.py --self-test` passes; skip with a reason when there is no `python3`.
  - (b) `git ls-files .claude/skills/self-review/SKILL.md` is non-empty, and the file contains `disable-model-invocation: true`.
  - (c) `skills/self-review` does not exist (it must not ship in the plugin).
  - (d) None of `SKILL.md`, `docs/self-review/README.md` or the fixtures contains `G:/`, `/home/darknite`, `agent-host` or `cc-toolkit-windows` (the generic rule).
  - Two-sided: for each of (b), (c) and (d), run the predicate on a temp copy that violates it (a SKILL.md without the line; a temp `skills/self-review/` dir), and assert it reports.
  - Run: `bash scripts/verify-template-consistency.sh` (wrapped in a scratchpad script). Expected: `ALL CHECKS PASSED`, check 82 PASS.
- [ ] **Step 4: Add to the root `CLAUDE.md` Invariants:** "**Every release runs `/self-review`** (the repo-local skill in `.claude/skills/self-review/`) and ships its `docs/self-review/<date>.md` in the release PR; nothing in the report is applied without the user's approval of that item."
- [ ] **Step 5: Commit.** Message: `feat(self-review): repo-local /self-review command, user docs, check 82, release rule`.

### Task 5: First real report (controller, attended)

This task is the maintainer's own run, as one instance of the generic flow. It is not delegated: it needs a peer session on a second machine, and the grouping step reads private text locally. The machine names below belong to this run only, never to the shipped files.

- [ ] **Step 1:** Run `/self-review` on the Linux server. It needs an idle machine, so first check that no gate or matrix is running.
- [ ] **Step 2:** Get the PC's shared JSON through route (b), from the PC helper session. That is a light job, but it waits for mm-agent's all-clear and the user's go.
- [ ] **Step 3:** Write `docs/self-review/<date>.md`. Before committing, check it: `grep` for every repo directory name under `~/git` (except `claude-code-toolkit`), and expect no hits.
- [ ] **Step 4:** Commit with message `docs(self-review): first report`, then run the full gate and open the PR.
