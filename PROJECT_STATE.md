# claude-code-toolkit — Project State

## Now

v7.0.1 is released (PR #226) and live on agent-host-1 and the PC (drift 0). v7.1.0 (B-18, B-7, B-12, B-10) is ready for release. Ranking by the user, 2026-11-26.

## Backlog

### Untriaged

- B-21 sync-template SKILL.md: a placeholder-sweep hit in a once-class file the project already held gets "Fill it or delete the line" and "NEVER edit a once-class file the project already holds" at the same time (seen in the v7.1.0 review; older than v7.1.0)
- B-22 sync-template SKILL.md: the "Already in sync" shortcut finalizes without step 6b, although the Rules forbid a finalize without it (seen in the v7.1.0 review; older than v7.1.0)
- B-23 Retro counter: `BLOCKED_TEXT_RE` has no word boundary, so `UNBLOCKED: x` matches (seen while building B-7)

### Ranked

- B-8 (parked: with related work) Backlog guard edge cases: B-03 vs B-3, an open copy under an unlisted subsection counts as moved, a glob in the verb, a setsid gh child outlives `timeout 3`, the mawk title cap counts bytes
- B-9 (parked: with related work) Contract notes: an indentation-trimmed contract passes with no note; the tester template line fires an empty note; one missing pin row
- B-13 (parked: with related work) Windows suite counts 7412 assertions vs Linux 7413: one skip differs on Git Bash, not traced
- B-14 (parked: with related work) Installer: no regression row for the marketplace-already-present path
- B-20 (parked: with related work) Leftovers of B-10 and B-12, left open on purpose in v7.1.0: `jev_ctl.py status` prints "routing spawns in this checkout: no" in the toolkit checkout when `CLAUDE_PLUGIN_ROOT` is unset; a crashed session's marker after a `cct-jev` uninstall lets the model floor step aside with no router; the RETRO step in the template `CLAUDE.md` reads as always-on (a template change, which v7.1.0 avoids)

### Done

- B-18 Once-class lines: the sync offers the changed lines of a once-class file (`PROJECT_CONTEXT.md`) that the project still holds in their old form, adopt or skip (v7.1.0)
- B-7 Retro counter: the question flag is reset after a typed user row; two-sided fixtures pin the rows (v7.1.0)
- B-12 Model ladder: at fable, stop and tell the user; the Jev skill names the review floor difference; the other leftovers were already fixed or moved to B-20 (v7.1.0)
- B-10 Plugin split: check 88 strips table lines only and prints one line per missing file; check 76 guards every plugin with skills; the other leftovers were already fixed or moved to B-20 (v7.1.0)
- B-6 deny-hang-shapes: a quoted `sed -n` range rewrite and a literal `SEDN` word are refused in a cd chain (v7.0.1)
- B-15 Backlog check: the refusal for a PR title word starting with `-` says to write "to" instead of "->"; the sync title reads `vX to vY` (v7.0.1)
- B-16 sync-template SKILL.md: advice for a GitHub 5xx on PR creation after the push (v7.0.1)
- B-11 sync-template SKILL.md: sample `Gates:` lines without a hook count, node-only hooks listed by plugin, every scanned kind listed (v7.0.1)
- B-19 Backlog check: the base-shape refusal says the `Item: none` trailer must sit in the last paragraph of the commit message (MM-Agent report, 2026-11-27) (v7.0.1)
- B-17 Gate artifact 24 h window expired during a ~1-day GitHub outage: closed without a change (re-run the gate; a longer window would weaken the merge check)
- B-5 Docs consistent with v7.0.0 (README, AGENTS.md, docs/, MCP plugin setup)
- B-1 v7.0.0 release (PR #221)
- B-2 Model ladder (cheap-first model choice, step-up note) (PR #221)
- B-3 Backlog discipline (PR #221)
- B-4 Plugin split (slim core) (PR #221)
