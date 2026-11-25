# claude-code-toolkit — Project State

## Now

v7.0.0 is released (PR #221) and live on agent-host-1 and the PC (drift 0). The v7.0.0 leftovers wait for ranking.

## Backlog

### Untriaged

- B-6 deny-hang-shapes: `tail --f`/`--fol` (getopt prefixes of `--follow`) pass and can hang a session (a reviewer rated it Important); unquoted-glob and `$p` quoting edge cases
- B-7 Retro counter: the stale question flag can drop a real correction (reset after each typed user row); missing two-sided fixtures
- B-8 Backlog guard edge cases: B-03 vs B-3, an open copy under an unlisted subsection counts as moved, a glob in the verb, a setsid gh child outlives `timeout 3`, the mawk title cap counts bytes
- B-9 Contract notes: an indentation-trimmed contract passes with no note; the tester template line fires an empty note; one missing pin row
- B-10 Plugin split leftovers: check 88 label anchoring; check 76 vacuity guard covers only cct-helpers; `jev_ctl.py` says `routing: no` without `CLAUDE_PLUGIN_ROOT`; stale `am_plugin_loaded` comments; crashed-session marker after a cct-jev uninstall; doc wording nits (CLAUDE.md RETRO step, architecture.md antecedent, challenge skill description)
- B-11 sync-template: the SKILL.md sample report lines ("all 12 hooks enforcing", "6 node-only hooks inactive") predate v7 and need a measured count; the scanned-kinds paragraph misses the new kinds
- B-12 Model ladder leftovers: "at fable, stop and tell the user" (about 30 B, needs a cut: 28 B headroom); Jev skill review-floor wording; stale `jev_ctl.py` off message; comment nits; the next self-review notes that `spawns` rows are now `start_models` rows
- B-13 Windows suite counts 7412 assertions vs Linux 7413: one skip differs on Git Bash, not traced
- B-14 Installer: no regression row for the marketplace-already-present path

### Ranked

_none_

### Done

- B-5 Docs consistent with v7.0.0 (README, AGENTS.md, docs/, MCP plugin setup)
- B-1 v7.0.0 release (PR #221)
- B-2 Model ladder (cheap-first model choice, step-up note) (PR #221)
- B-3 Backlog discipline (PR #221)
- B-4 Plugin split (slim core) (PR #221)
