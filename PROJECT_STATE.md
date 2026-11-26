# claude-code-toolkit — Project State

## Now

v7.0.0 is released (PR #221) and live on agent-host-1 and the PC (drift 0). v7.0.1 (B-6, B-15, B-16, B-11) is being built; v7.1.0 (B-18, B-7, B-12, B-10) follows. Ranking by the user, 2026-11-26.

## Backlog

### Untriaged

_none_

### Ranked

- B-6 [in progress] (v7.0.1) deny-hang-shapes: `tail --f`/`--fol` (getopt prefixes of `--follow`) pass and can hang a session (a reviewer rated it Important); unquoted-glob and `$p` quoting edge cases
- B-15 (v7.0.1) Backlog check refuses a PR title holding an arrow (`v6.2.0 -> v7.0.0`: the arrow is read as a flag-shaped word); hit by open-brain in the v7.0.0 sync. Let `->` through in a quoted title, or have the sync skill's title and examples say "to"
- B-16 (v7.0.1) sync-template SKILL.md: no advice when PR creation fails with a GitHub 5xx after the push (retry later; the branch is pushed, nothing to undo)
- B-11 (v7.0.1) sync-template: the SKILL.md sample report lines ("all 12 hooks enforcing", "6 node-only hooks inactive") predate v7 and need a measured count; the scanned-kinds paragraph misses the new kinds
- B-18 (v7.1.0) Once-class wording never reaches existing projects: a sync shows a changed `PROJECT_CONTEXT.md` line only as a `once_notes_changed` INFO (panoscribe). Have the sync present each pending once-note hunk as an adopt/skip choice. The Ollama line is fixed by hand in 5 of 6 consumers (2026-11-26); MM-Agent follows in its own PR
- B-7 (v7.1.0) Retro counter: the stale question flag can drop a real correction (reset after each typed user row); missing two-sided fixtures
- B-12 (v7.1.0) Model ladder leftovers: "at fable, stop and tell the user" (about 30 B, needs a cut: 28 B headroom); Jev skill review-floor wording; stale `jev_ctl.py` off message; comment nits; the next self-review notes that `spawns` rows are now `start_models` rows
- B-10 (v7.1.0) Plugin split leftovers: check 88 label anchoring; check 76 vacuity guard covers only cct-helpers; `jev_ctl.py` says `routing: no` without `CLAUDE_PLUGIN_ROOT`; stale `am_plugin_loaded` comments; crashed-session marker after a cct-jev uninstall; doc wording nits (CLAUDE.md RETRO step, architecture.md antecedent, challenge skill description)
- B-8 (parked: with related work) Backlog guard edge cases: B-03 vs B-3, an open copy under an unlisted subsection counts as moved, a glob in the verb, a setsid gh child outlives `timeout 3`, the mawk title cap counts bytes
- B-9 (parked: with related work) Contract notes: an indentation-trimmed contract passes with no note; the tester template line fires an empty note; one missing pin row
- B-13 (parked: with related work) Windows suite counts 7412 assertions vs Linux 7413: one skip differs on Git Bash, not traced
- B-14 (parked: with related work) Installer: no regression row for the marketplace-already-present path

### Done

- B-17 Gate artifact 24 h window expired during a ~1-day GitHub outage: closed without a change (re-run the gate; a longer window would weaken the merge check)
- B-5 Docs consistent with v7.0.0 (README, AGENTS.md, docs/, MCP plugin setup)
- B-1 v7.0.0 release (PR #221)
- B-2 Model ladder (cheap-first model choice, step-up note) (PR #221)
- B-3 Backlog discipline (PR #221)
- B-4 Plugin split (slim core) (PR #221)
