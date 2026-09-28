# PM-level reporting — design (v4.2.0)

**Status:** spec for review. Branch `feat/pm-reporting` (worktree `G:/git/.worktrees/claude-code-toolkit/pm-reporting`); nothing merged to `main` until the user merges it.
**Origin:** the Motorsport-Manager-AI-Agent session, where the user found technical progress logs unreadable and, with that session, worked out a product-manager-level reporting style; the user asked for it to be passed on as a toolkit template idea (2026-09-26).

## Goal

Every session reports to the user the way a product manager wants to read it: a real timestamp, short plain-language updates only when something changes state, a small goal-level backlog table, and optionally a live board page — while the detailed technical style stays one command away.

## Decisions (user, 2026-09-26/27)

| # | Decision |
|---|---|
| D1 | Scope: **switchable, default on** — every project, every session, unless switched off for a session. |
| D2 | Mechanism: Claude Code **output style** + a **time hook** + a **backlog-board skill** (approach A). Rejected: rules in the user-level `CLAUDE.md` (no native switch); `date` per message without a hook (0.5–1.6 s of Bash-hook time per update on this machine). |
| D3 | The backlog board is part of v1. |
| D4 | The goal-level table appears once **2–3 items have changed state** since the last table (or when the user asks for status); a single change gets one or two sentences only. |
| D5 | All work stays on `feat/pm-reporting` until the user merges. |

## Facts this design rests on (Claude Code docs, verified 2026-09-26)

- Output styles: markdown files in `~/.claude/output-styles/` (user) or `.claude/output-styles/` (project); frontmatter `name`, `description`, `keep-coding-instructions`. Default via `outputStyle` in settings; switch with `/output-style <name>` or `/config`, effective from the next message.
- **A custom style drops Claude Code's built-in software-engineering instructions unless `keep-coding-instructions: true`.** This design depends on that flag.
- Output styles do not apply to subagents (except forks) — correct here: subagents report to the orchestrator, not to the user.
- Claude Code does not expose wall-clock time to the model; a `UserPromptSubmit` hook's stdout is added to the context of that turn.
- All matching hooks run in parallel.

## Component 1 — output style `pm-report`

File `user-level-reference/output-styles/pm-report.md` → copied to `~/.claude/output-styles/pm-report.md`.

```markdown
---
name: pm-report
description: Plain-language, state-change reporting for a product-manager reader; the technical style is `/output-style default`.
keep-coding-instructions: true
---

# Reporting to the user

The user reads as a product manager: they care what changed for the project goal, not how.

1. **Timestamp.** Start every message with `[HH:MM]`, taken from the "Current local time" line in
   this turn's context. If this turn has already made more than 10 tool calls, or you cannot tell,
   run `date` first and use that. Never estimate the time.
2. **Plain words.** No commit ids, file paths, test counts, agent names or internal task labels
   unless the user asks. If a technical term is unavoidable, explain it in a few words.
3. **Post on state change only.** A state change: an item finished, went to live testing, bounced
   back, became blocked, or now waits on the user. Routine progress is at most one line, or waits
   for the next update. Work finishing in parallel must not produce one message per step.
4. **Shape of an update.** One or two sentences: what happened and what it means for the goal.
   Once 2–3 items have changed state since the last table — or when the user asks for status —
   add the backlog as a short table (about 10 rows, one plain line per capability, one state each).
   End with a plain question if a decision is needed.
5. **States (exactly these):** Done · In progress · Testing live · Needs rework · Open ·
   Waiting on you · Blocked. Something that passed a first check and then failed is
   **Needs rework** — never hidden under "In progress".
6. **Questions first.** A direct question gets a direct answer first; no table unless a state changed.
7. **Details on request.** Details live in the repo and in memory; end with "ask for details on X"
   when useful.
8. **A colleague, not a log.** Ask when something is unclear, push back when a request looks wrong,
   suggest ideas.
9. **Board.** If this project has a backlog board (its address is in this project's memory), update
   it on every state change using the `backlog-board` skill's update rule. If not, and the project
   has a backlog, offer one once.

The user can switch to the detailed technical style with `/output-style default`.
```

## Component 2 — time hook (inline, no script)

`user-level-reference/settings.json` gains:

```json
"UserPromptSubmit": [
  { "hooks": [ { "type": "command", "command": "LC_ALL=C date '+Current local time: %H:%M (%Y-%m-%d %a)'" } ] }
]
```

- **Inline on purpose:** no file means nothing to go missing (the context-mode stale-hook incident of 2026-09-26 cannot recur), and consistency check 21 — which fails any `user-level-reference/hooks/` file without a root `hooks/` original — is not involved.
- Always exits 0; one process per user message; runs whether or not the style is active (hooks cannot see the active style; a correct clock is harmless in the technical style too). ~45 bytes of context per message.
- Existing hook commands already run through bash on this machine (they use `$?` and `[ ]`), so `date` with a format string works on Windows/Git Bash.
- `LC_ALL=C` keeps `%a` English (`Sat`, not `Sa`) on a non-English machine, so the line's shape never depends on the locale (found while planning).

## Component 3 — skill `backlog-board`

`user-level-reference/skills/backlog-board/` → `~/.claude/skills/backlog-board/`: `SKILL.md` + `board.html`.

- **Model-invocable** (sessions must find it; ~150 B of always-loaded description).
- **Page:** based on the MM-Agent session's ~150-line board (requested from that session at implementation time), made generic (project name instead of "Pit Wall"), theme-aware, no external libraries beyond Google Fonts. Implementation loads the `artifact-design` and `artifact-capabilities` skills before writing the page.
- **Data:** declares the `db` capability. Collection `backlog`: `{order, title, state, note}`; document `meta/latest`: `{headline, updated}`. State keys `done/progress/testing/rework/open/waiting/blocked` map 1:1 to Component 1's seven states. The page renders live from the database.
- **Create:** offered once per project that has a backlog; on yes, published private, and the address recorded in that project's auto-memory (per user — never in committed files).
- **Update rule:** on every state change, read the current rows, then ONE batched, version-pinned write (`if_version`) of the changed rows plus `meta/latest`; never republish the page (an unpinned write to an existing document is refused — observed by the MM-Agent session).
- **Source of truth:** the board when it exists (the chat table mirrors it); otherwise the project's auto-memory.
- **Fallback:** Artifact tools unavailable → chat only, said once.
- **Content:** notes in plain words; no paths, secrets or internal detail on the page.

## Component 4 — toolkit placement, checks, release

- **User-level only.** None of the six project templates change → no `/sync-template` churn for consumers.
- `scripts/verify-user-level-drift.sh`: extend the compared set to `output-styles/**` (currently `CLAUDE.md, hooks/**, skills/**, agents/**`). The release is not done until it reports 0 drift.
- New consistency checks in `scripts/verify-template-consistency.sh`:
  1. `pm-report.md` frontmatter contains `keep-coding-instructions: true` — its loss silently drops the engineering instructions, so it must go red.
  2. The reference `outputStyle` names a file that exists under `user-level-reference/output-styles/`.
  3. The seven state keys are the same set in `pm-report.md` and `board.html` (pinned together: two copies of one list).
  4. The `UserPromptSubmit` command in the reference settings equals the one this spec names.
- `scripts/test-hooks.sh`: execute the inline command; stdout matches `^Current local time: [0-2][0-9]:[0-5][0-9] \([0-9]{4}-[0-9]{2}-[0-9]{2} [A-Z][a-z]{2}\)$`, exit 0.
- Context budget: the style is injected at every session start → new measured row in README *The trim pass, measured* and `docs/architecture.md` *Context Budget* (`wc -c`), plus the skill description; per the per-release rule, a fresh measured column for v4.2.0.
- CHANGELOG v4.2.0 + downstream migration: copy `output-styles/pm-report.md` and `skills/backlog-board/`; add `outputStyle` and the `UserPromptSubmit` entry to `~/.claude/settings.json` (diff live vs reference first — the live file carries machine-specific entries); the default style applies to new sessions; `/output-style default` switches back.

## Acceptance (live, after install)

1. A fresh session's first message starts with `[HH:MM]` within one minute of the clock.
2. `/output-style default` → the next message is in the technical style; `/output-style pm-report` → back.
3. Scratch project: create a board, change one row's state via a version-pinned write → the page shows it; a republish never happens.
4. Gate green (consistency, hook suite, server suite) and drift 0.

## Non-goals

- No change to subagent behaviour or to how subagents report to the orchestrator.
- No per-project templates or `project-instructions.md` edits; a project wanting a different style uses Claude Code's own project-level `outputStyle` override.
- No automation that posts updates on a timer.
