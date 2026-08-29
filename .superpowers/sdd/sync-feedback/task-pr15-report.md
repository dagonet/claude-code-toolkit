# PR15 report — v2.2.0 hooks: no-node fail-closed + JSON fallback, protected branches, .env deny

Worktree copy: `G:\git\claude-code-toolkit\.claude\worktrees\agent-af1667fba66054542\.superpowers\sdd\sync-feedback\task-pr15-report.md`
Branch `v2/pr15-hooks-no-node` (from main 527d3f9). Not pushed, no PR, no merge.

## Gates

```
verify-template-consistency.sh: ALL CHECKS PASSED   (227 PASS, 0 FAIL)
test-hooks.sh: 243 passed, 0 failed
ALL HOOK FIXTURES PASSED
```

## Mirrors (md5, canonical vs user-level-reference)

```
1c606967b1bbce89642b652cb3856d54  hooks/lib/json.sh            = user-level-reference/hooks/lib/json.sh
58c62599f5fbf1bdddc0401788e65762  hooks/lib/git-cmd.sh         = user-level-reference/hooks/lib/git-cmd.sh
788f827fe94b83ebc11d7be3f33c86a1  hooks/no-push-main.sh        = user-level-reference/hooks/no-push-main.sh
f0eab05621bff06bbc1ef60565380ad7  hooks/gate-before-merge.sh   = user-level-reference/hooks/gate-before-merge.sh
f580bf6b50d7f5cc0c7e9ae2bf69c710  hooks/read-size-gate.sh      = user-level-reference/hooks/read-size-gate.sh
1070257bd244e06e6f36118b8f930420  hooks/bash-output-guard.sh   = user-level-reference/hooks/bash-output-guard.sh
238a750fc303773444c440f15d767cbb  hooks/retro-ledger.sh        = user-level-reference/hooks/retro-ledger.sh
7aa97ff60a926d8daf627caf189de8f9  hooks/pre-commit-test.sh     = user-level-reference/hooks/pre-commit-test.sh
templates/*/.claude/settings.json (x6): aba86f884c298813202aaf9d2e5f24c5 (one hash across all six)
```

`enforce-agent-contract.sh`, `enforce-delegation.sh`, `require-skills-block.sh`, `retro-brief.sh`,
`agent-budget-warn.sh` have no user-level mirror by design — unchanged.

## Deviations

1. Six hooks keep an embedded node *program* (`read-size-gate`, `bash-output-guard`,
   `enforce-delegation`, `retro-ledger`, `retro-brief`, `enforce-agent-contract`'s transcript
   scan). They go through `hooks/lib/json.sh` for the availability check and warn once
   (`WARN: <hook>: node not on PATH (found python3) — enforcement inactive`) instead of being
   ported to three backends — that is a redesign, out of the stated scope.
2. `agent-budget-warn.sh` was listed as a fail-open hook needing a WARN. It never used a JSON
   parser (it greps the raw payload), so enforcement is NOT inactive without one. Left untouched.
3. `user-level-reference/settings-reference.md` (not in the brief's file list) documented the old
   `Read(.env*)` deny in three places; updated so the docs are not stale.
