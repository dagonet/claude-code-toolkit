# Self-review report (stage 1) — design

Status: draft for the user's approval. Origin: the user's brief in the PC chat, 2026-11-19 07:09-07:28, relayed by cc-toolkit-windows. Decisions taken on the agent dashboard: approach A (#38), report only, no with/without test (#36), stage 1 before stage 2 (#37).

## 1. Intent

The toolkit grows by adding rules, and nothing tells us when a rule has stopped paying for itself. Every new model or Claude Code release may make a rule unnecessary, or make something newly possible. The user's drivers, in their words: "cost, quality in terms of missing self improvement and adoption to harness changes or new models".

Stage 1 is a regular report: a short, ranked list of suggestions for the toolkit, built from what our sessions actually did and from what changed in Claude Code. The user approves each item, and approved items ship through the normal release. Nothing changes on its own.

Stage 2, designed later, is a per-project improvement loop. Its first step only notes what failed and what helped in each project. Stage 1 fixes the format of those notes (§6) and reads them, so stage 2 plugs in without changing the report.

## 2. Goals, non-goals, anti-goals

- **Goals:**
  - A report at every release, and on demand when a new model or Claude Code version ships.
  - At most 10 ranked suggestions. Each has evidence (numbers), the proposed change, its expected effect on cost or quality, and its risk.
  - Uses the data of both machines.
  - Repeatable: the counting is a script, so two runs over the same window give the same numbers.
- **Non-goals:**
  - Applying any change.
  - With/without tests of a rule or skill (rejected for now, #36; stage 2 builds that machinery and stage 1 can reuse it later).
  - Per-project improvement (stage 2).
  - A dashboard or a chart.
- **Anti-goals:**
  - **Conversation text leaves the machine.** Only counts and short behaviour kinds cross between machines or into the repo.
  - **Private project names in the public repo.** The committed report is aggregated per machine; per-project detail stays in a local, uncommitted file.
  - **The report becomes a cost itself.** The counting must not call a model; one model pass writes the ranking.
  - **Noise.** Ten items the user can act on beat fifty observations.

## 3. Constraints

- KISS (standing user rule).
- Read-only on transcripts; stdlib Python only, like `scripts/measure-process.py`.
- Runs on Linux and Windows (Git Bash, `python` or `python3`).
- No subagent is needed for the counting; the main toolkit session writes the ranking.
- Per the gate rule, the counter is light, but it reads up to several GB: run it on an idle machine, never beside a gate or the parser matrix.

## 4. Approaches

- **A. A counting script on each machine plus one command that writes the report.** Chosen (#38). The counting is repeatable and costs no model time; only the ranking uses a model.
- **B. Claude reads the session records directly.** Rejected: this server alone holds about 6.7 GB of session records in about 1,200 project folders. It would be slow, expensive and different every run.
- **C. A scheduled cloud job.** Rejected: the records must stay on the machine.

## 5. The design

### 5.1 The counter: `scripts/self-review-count.py`

Read-only, stdlib only, never shipped to consumers. It reuses `measure-process.py`'s transcript reading (import or shared helper, builder's choice).

```
python3 scripts/self-review-count.py [--since YYYY-MM-DD] [--root DIR] --out FILE
```

- **Window:** `--since`, default 30 days ago, matched on each row's timestamp (a session that spans the window start counts only its rows inside it). Jev events by their own timestamp.
- **Input:** `~/.claude/projects/**` (main and subagent transcripts), the Jev events under the clones (`jev-tally.py`'s source), and any project notes files (§6) under the clone root (`~/git` here, `G:/git` on the PC).
- **Output:** one JSON file with only counts. It contains no conversation text, no paths below the clone root, no env values. Per-project detail and the correction candidates go to a second, local-only file (`<out>.local.json`). **My call:** both files live in `~/.cache/cct-self-review/`, outside every repo, so neither can be committed by accident.

Measures (each across the window, per machine):

1. **Model per spawn:** spawns by agent type × model, and the tokens and cost share of each model. Source: Agent `tool_use` inputs, subagent transcript `model` fields, Jev events.
2. **Unused toolkit parts:** each cct skill and agent with its call or spawn count. Zero means unused.
3. **Hook blocks:** blocks per toolkit hook, from the tool results that carry `BLOCKED: <hook>`. **My call:** counts only. Telling friction from protection is left to the ranking pass and the user, not to a heuristic that would produce confident but false numbers.
4. **Subagent token share:** main vs subagent tokens (input, cache read, output), as in `measure-process.py`.
5. **Repeated corrections:** user turns that correct the agent.
   - The counter picks candidates with a fixed pattern list and writes their text only to the local-only file. The JSON gets the candidate count.
   - Then the Claude session on that same machine reads the local file and groups the candidates into behaviour kinds, for example "ran a long job without asking" or "asked a question it could answer itself". That session is the toolkit session on Linux and the PC helper on the PC.
   - The session adds `"correction_kinds": [{"kind": "...", "count": N}]` to the JSON before it is used or sent.
   - A kind describes agent behaviour, never project content.

The always-loaded context size is not counted here: the ranking pass reads it from the release's Context Budget column in `docs/architecture.md`.

### 5.2 The command: `/self-review`, local to the toolkit repo

- **Where:** `.claude/skills/self-review/SKILL.md` in this repo, re-included in `.gitignore` the way `.claude/settings.json` is. **My call:** not in the cct plugin. A plugin skill's description loads in every session of every project, and only the toolkit session needs this one. `disable-model-invocation: true`: the user, or the release step, starts it.
- **Steps:**
  1. Run the counter on this machine.
  2. Ask the PC helper (cc-toolkit-windows) to run it on the PC, add its correction kinds, and send back the finished JSON. **My call:** a cross-session message, since it carries counts and kinds only. No file is committed or copied between machines. If the helper is offline, the report says so and covers this machine only, rather than waiting.
  3. Read the Claude Code changelog and what's-new pages since the version named in the previous report: new settings, skill frontmatter fields, hook events and built-ins (for example a built-in usage view) that make one of our rules redundant or newly possible.
  4. Write the ranked report to `docs/self-review/YYYY-MM-DD.md`.
- **Report header:** the date, the window, the Claude Code version and models seen, which machines contributed, and the previous report it compares with ("first report" when there is none).
- **Key numbers:** one small table with one column per machine and a total. It holds the figures of measures 1-5, aggregated, with no project names. The next report compares against this table, so the counter itself stores no history.
- **Body:** at most 10 items, ranked by expected cost saved or quality gained. Each item names the evidence, the change, the effect, the risk, and the files it would touch. A short "since last report" line follows on whether earlier approved items moved their numbers.
- **Only the Markdown report is committed.** The JSON files stay in `~/.cache/cct-self-review/` on each machine.
- **Then:** the user approves items one by one. Each approved item becomes a backlog item and ships in a release.

### 5.3 When it runs

- **Every release:** a fixed release step. It goes in the root `CLAUDE.md` next to the Context Budget rule; the report ships in the release PR.
- **On demand:** when a new model or Claude Code version appears, the user types `/self-review`.
- **My call:** no automatic detection of a new model or version (no hook). The user hears of new models first, and the release step guarantees at least one run per release.

## 6. The notes format stage 2 will write (fixed now, read now)

A project may hold `.claude/improvement-notes.jsonl`. Each line is one object:

```json
{"date": "2026-11-19", "kind": "helped|recurring_failure|rule_unused", "surface": "<rule, skill, hook or file name>", "summary": "<one line, no secrets, no conversation text>", "count": 3}
```

The counter reads every such file under the clone root and puts counts per kind and surface into the local-only file. It puts aggregated kinds, without project names, into the JSON. A surface seen in 2-3 projects becomes a candidate suggestion to promote into the template. Stage 2 decides who writes the file and whether it is tracked; until then no file exists and the counter reports none.

## 7. Tests

- **Counter:** a `--self-test` with fixture transcripts, as `measure-process.py` has. It covers one row per measure, plus these two-sided cases:
  - no conversation text in the JSON (a fixture with a unique marker string, which must not appear in the output);
  - an unreadable or partial transcript is skipped and counted, not fatal;
  - an absent notes file gives zero notes.
- **Skill:** a consistency check that the skill is not in the plugin's `skills/` and is re-included in `.gitignore`.

## 8. Left to the builder

- Sharing code with `measure-process.py`: import it, or split out a small helper.
- The correction pattern list: start small, and record its precision on the first real run in the report.
- The cost figures: whether to price by model from a table in the script or report tokens only. Tokens only is acceptable for the first version.
- Whether Claude Code's built-in usage view (`/insights` or similar) can replace one of the counts. If it can, use it and drop that count.
