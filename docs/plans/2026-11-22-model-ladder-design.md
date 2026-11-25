# Cheap-first model ladder for helper spawns — design

Status: draft for the user's approval. Origin: the user's discussion of 2026-11-22, after the first self-review report (`docs/self-review/2026-11-20.md`).

## 1. Intent

In the user's words: "the orchestrator should decide which model/effort should be used based on the cost and complexity to get the best result for minimal cost. But: who decides that for the orchestrator?"

Jev (the optional per-spawn model router) does not deliver this. In 30 days it made 2,311 decisions and applied 52 (2 %); otherwise the fixed default applied anyway. It costs an outside service, a key and a delay on every spawn.

**Who decides, as agreed:** nobody decides once and for all; the loop decides.
- At run time the orchestrator follows a written ladder rule.
- A small hook tells the orchestrator when a helper failed, and on which model.
- Each self-review report measures where cheap-first paid off and where a kind of job climbs anyway. It proposes changes to the rule, and the user approves them.

## 2. Decisions taken with the user

- **Cheap first, step up on failure** (user, 15:47): a job starts on the cheapest model that may do it; if it fails, the same job is started again one step up.
- **Checkers keep a strong floor** (user, 15:54). Reviews and safety-related design start on Opus and never lower, because a cheap checker fails silently.
- **Approach A plus a hook when a helper's result returns** (user, 16:02): a written rule and measurement, plus a hook that reads each returning result and notes a failure with the next model. No hook guesses whether two spawns are "the same job".

## 3. Goals, non-goals, anti-goals

- **Goals:**
  - A written ladder in the instructions the orchestrator reads.
  - A hook that turns a visible failure into a one-line note naming the next model.
  - The self-review counter reports the start model and the step-ups per kind of job.
  - Jev routing is no longer part of the recommended setup.
- **Non-goals:**
  - A hook that re-starts a helper itself. Hooks cannot start helpers, and the orchestrator owns that decision.
  - Guessing whether two spawns are the same job.
  - Changing effort per step; the model is the one dial, and effort stays as the agent file sets it.
  - Moving Jev's code into an optional plugin. That belongs to the "slim core" project (topic #1), so the plugin split is done once.
- **Anti-goals:**
  - **A cheap checker.** The reviewer and architect stay on Opus.
  - **A nudge that blocks.** The hook is advisory: any doubt means no note, and it never refuses anything.
  - **Silent cost growth.** A step-up beyond Opus is named in the note, and a failure on the top rung says "report to the user" instead of naming another model.

## 4. The ladder

Order: `haiku` < `sonnet` < `opus` < `fable`.

| Kind of job | Start | Notes |
|---|---|---|
| Lookups, search, summaries (`cct:Explore`, `general-purpose` used for reading) | haiku | as today |
| Coding, tests and ops from a clear brief (the coders, `cct:tester`, `cct:ops`) | sonnet | as today (agent files) |
| Reviews, architecture, safety design (`cct:code-reviewer`, `cct:architect`) | opus, floor | never lower; a step-up goes to fable |
| Anything else (`general-purpose` for other work) | sonnet | the existing default for untyped spawns |

**My call:** the starting rungs equal today's agent files, so nothing changes until the reports show a kind of job that should start lower or higher. Whether coders could start on haiku is a question for the reports to answer.

## 5. The written rule

The user-level `CLAUDE.md` section "Sub-Agent Model Choice" is rewritten to hold:
- the ladder table;
- "on a failed result, start the same job again one step up, and say so in your report to the user";
- "a review that finds the work needs fixes counts as the coder's failure: the fix round's coder starts one step above the model that wrote the code";
- the reviewer floor;
- "a note from the step-up hook is an instruction to do exactly that".

The Jev exception sentence ("unless Jev routing is on, omit `model`") goes away. `AGENT_TEAM.md` (all six variants) gets one matching line where it states model ownership. The Context Budget column moves, because the user-level `CLAUDE.md` is harness-injected; it is measured at release.

## 6. The step-up hook

- **New:** `hooks/step-up-note.sh`, registered in the plugin `hooks/hooks.json` as **PostToolUse** with the matcher `Agent`. It is advisory: no `onFailure`, and exit 0 always.
- **Input:** the spawn's `tool_input` (`subagent_type`, `model` if given) and the returned result text.
- **The model that ran:** the explicit `model`, else the agent type's own model resolved as `hooks/lib/agent-model.sh` already does, else the untyped default.
- **Failure means, in the returned text** (my call, after the builder check): the fixed contract lines the toolkit's coder-type helpers already must end with. These are the agents with `pipeline: true`, enforced by `hooks/enforce-agent-contract.sh`. Failure is either:
  - any line `- [fail] <n>. …`;
  - a `Gate:` line that names a failing gate.

  Helpers without that contract (Explore, general-purpose, reviewer, tester, architect) get no note. For them the written rule alone applies. There is no fuzzy text matching.
- **Output on failure:** one line of added context for the orchestrator, in exactly this form:

  `Step-up: <type> failed on <model> (<reason>). Start the same job again on <next model>.`

  On the top rung it reads `… failed on fable. Report this to the user instead of retrying.`
- **Reviewer verdicts are not handled by the hook** (my call, KISS). A "needs fixes" review is a failure of the coder's work. The written rule says so: "the fix round's coder starts one step above the model that wrote the code". The hook does not try to link a review to the earlier coder spawn.
- **No other output and no state file.** The note text itself is the record: it lands in the transcript, where the counter finds it.

## 7. Measurement (self-review counter)

New shared keys:
- `start_models` {agent type key: {model: n}}: the existing spawns measure, renamed in the report;
- `step_ups` {agent type key: {"<from>-><to>": n}}: counted from the hook's fixed note text in main transcripts.

The privacy rules R4/R5/R18 apply unchanged: only toolkit types, built-ins, `other`, and allow-listed models. The report ranks the kinds of job whose step-up rate is high (start one rung higher) or zero over many spawns (try one rung lower), as proposals for the user.

## 8. Jev

- **This project:**
  - `/cct:jev` stays available and off by default.
  - The user-level rule no longer mentions it.
  - The live clones where it is on are switched off by the user (`/cct:jev off`), and the release notes say so.
  - `model-floor.sh` keeps its step-aside for Jev, which is harmless when it is off.
- **Topic #1:** moves Jev's code into an optional plugin.

## 9. Tests

- **Hook:** test rows in `scripts/test-hooks.sh`.
  - A coder report with `BLOCKED` on sonnet gives a note naming opus.
  - A reviewer "Needs fixes" gives a note naming the coder's next rung.
  - A clean DONE report gives no note.
  - A failure on fable gives the "report to the user" note.
  - An unreadable payload, an unknown type, or no model knowable gives no note (advisory).
  - A tool other than Agent gives no note.
- **Counter:** fixture rows with notes give exact `step_ups` counts; a non-toolkit type maps to `other`.
- **Check:** the consistency script asserts that the hook is registered as PostToolUse `Agent` with no `onFailure`.

## 10. Size and delivery

- **Size:** one advisory hook, its tests, a registration, a counter measure, the user-level rule text, one `AGENT_TEAM.md` line in six variants, and docs.
- **Release:** v6.4.0, after v6.3.0.
- **Live update:** the user-level `CLAUDE.md` changes, so the update is attended, as usual.

## 11. Calls made after the builder check

- **Background spawns.** A helper started in the background returns only "started" to the orchestrator, and its report arrives later as a notice. First verify in the Claude Code hooks docs:
  - whether PostToolUse on `Agent` sees the final report for background spawns;
  - if it does not, whether SubagentStop can add context for the parent.

  If neither works, ship foreground coverage plus the written rule, and say so in the docs. The counter's note count shows the coverage in each self-review report. **My call:** the written rule is the main mechanism (approach A); the hook is a help, so partial coverage is acceptable.
- **Which model ran.** Use the `tool_input` the hook receives, verifying whether it is the original or the floor-rewritten input. If `model` is absent, resolve it with `hooks/lib/agent-model.sh`, exactly as `model-floor.sh` does. If it cannot be resolved, there is no note.
- **Where the note lands.** Verify how added context appears in the transcript (attachment or system-reminder entry). The counter matches the fixed note text wherever it lands in main transcripts.
- **Release and check numbering.** v6.4.0 builds on v6.3.0, which carries check 83. The registration assertion is a new check 84.

## 12. Left to the builder

- The exact output JSON of the hook, once the docs are verified.
- The test fixture payloads.
