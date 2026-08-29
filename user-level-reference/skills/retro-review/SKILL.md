---
name: retro-review
description: Review the local subagent-failure retro ledger, user-level config drift, and which consumer repos are behind the toolkit version. Triggers on /retro-review.
disable-model-invocation: true
argument-hint: "[project-dir]"
---

# Retro Review

The **local** counterpart to the `toolkit-nightly-check` routine. A cloud routine runs
over a *clone* and cannot see `~/.claude`, this machine's other checkouts, or anything
uncommitted — which is exactly what this skill reads. That is why it is a skill you run
here, not a routine.

Target project: `$ARGUMENTS`, or the current working directory if empty.

## Steps

1. **Read the retro ledger.** Slug the absolute project path exactly as
   `hooks/retro-ledger.sh` does — replace every `:`, `\`, `/`, `.` and `_` with `-` —
   then read `~/.claude/projects/<slug>/memory/retro.md`. No file means no subagent has
   failed there; say so and continue. Group the entries by cause (a wrong `tools:`
   allowlist, an under-briefed spawn prompt, a hook), not by date.
2. **Check user-level drift.** From the `claude-code-toolkit` checkout, run
   `bash scripts/verify-user-level-drift.sh`. It compares `user-level-reference/` with
   the live `~/.claude/`; the reference leads and the live copy follows, so DRIFT means
   "sync is pending", not "broken". List the drifted files.
3. **Check consumer repos.** For each `G:/git/*/.claude/template-manifest.json`, read
   its recorded template version and compare with line 1 of `VERSION` in the toolkit
   checkout. List only repos strictly behind it, worst first.
4. **Write the summary** to `~/.claude/projects/<slug>/memory/retro-summary.md`:
   **at most 30 lines**, overwriting any previous run. One section per step, each a
   short list of concrete next actions ("re-copy `agents/architect.md`", "add `Skill`
   to `tester.md` tools:"). Drop any section that found nothing. If all three are clean,
   write a single line saying so.

## Running it unattended

```bash
claude -p "/retro-review" --permission-mode auto      # from the project directory
```

Schedule that with Windows Task Scheduler or cron. It is a **local** headless session,
not a cloud routine: it needs this machine's `~/.claude` and its sibling checkouts, so
it cannot be moved to `/schedule`. Keep it read-only — this skill reports, and the fixes
are a separate, deliberate act.
