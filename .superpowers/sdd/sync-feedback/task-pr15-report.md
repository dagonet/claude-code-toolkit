# PR15 report — v2.2.0 hooks: no-node fail-closed + JSON fallback, protected branches, .env deny

Worktree copy: `G:\git\claude-code-toolkit\.claude\worktrees\agent-af1667fba66054542\.superpowers\sdd\sync-feedback\task-pr15-report.md`
Branch `v2/pr15-hooks-no-node` (from main 527d3f9). Not pushed, no PR, no merge.

## Gates

```
verify-template-consistency.sh: ALL CHECKS PASSED   (230 PASS, 0 FAIL)
test-hooks.sh: 257 passed, 0 failed
ALL HOOK FIXTURES PASSED
```

(Fix round 1 numbers; the first pass was 227 / 243. No SKIPs on this host — node,
python3 and jq are all present.)

## Mirrors (md5, canonical vs user-level-reference)

```
12ea8f9fdd8e1b5f01b4e7d11f3d147f  hooks/lib/json.sh            = user-level-reference/hooks/lib/json.sh
f2333609965c7724e1946a69d144f85c  hooks/lib/git-cmd.sh         = user-level-reference/hooks/lib/git-cmd.sh
788f827fe94b83ebc11d7be3f33c86a1  hooks/no-push-main.sh        = user-level-reference/hooks/no-push-main.sh
f0eab05621bff06bbc1ef60565380ad7  hooks/gate-before-merge.sh   = user-level-reference/hooks/gate-before-merge.sh
f580bf6b50d7f5cc0c7e9ae2bf69c710  hooks/read-size-gate.sh      = user-level-reference/hooks/read-size-gate.sh
8bf78101b9f0ed7cfc33a226f60a5c35  hooks/bash-output-guard.sh   = user-level-reference/hooks/bash-output-guard.sh
238a750fc303773444c440f15d767cbb  hooks/retro-ledger.sh        = user-level-reference/hooks/retro-ledger.sh
868deb25082ba44d37ad001b63b0a3af  hooks/pre-commit-test.sh     = user-level-reference/hooks/pre-commit-test.sh
templates/*/.claude/settings.json (x6): aba86f884c298813202aaf9d2e5f24c5 (one hash across all six)
```

`enforce-agent-contract.sh`, `enforce-delegation.sh`, `require-skills-block.sh`, `retro-brief.sh`,
`agent-budget-warn.sh` have no user-level mirror by design — unchanged.

## Fix round 1 (review of aefa6b5)

| # | Item | Resolution |
|---|---|---|
| 1 | Critical: `enforce-agent-contract.sh` called `json_get` with the lib conditionally sourced | Lib is now REQUIRED: missing → `WARN: enforce-agent-contract: hooks/lib/json.sh missing — enforcement inactive`, exit 0. Same for `require-skills-block.sh` (item 4). Fixtures: both hooks copied to a lib-less dir → exit 0 + WARN; plus an assertion that stderr carries no `command not found`, and `check_env` now fails ANY case whose stderr contains it. |
| 2 | python3/jq fixture blocks go red on a node-only box | `HAVE_PY`/`HAVE_JQ` guards; absent interpreter prints `SKIP  <case> (no python3 on this host)` and is counted neither pass nor fail. |
| 3 | `json.load(sys.stdin)` decodes in the locale encoding | `json.loads(sys.stdin.buffer.read().decode("utf-8-sig","replace"))` + `sys.stdout.buffer.write(...encode("utf-8"))` (the encode side had the same trap). BOM stripped once in `json_get` for all three backends. Fixtures compare the three backends against EACH OTHER on an em-dash payload and a BOM payload, and pin `LC_ALL=C PYTHONIOENCODING=cp1252` (parse + still blocks). |
| 4 | `require-skills-block.sh` silently disabled itself without the lib | WARN line added (see 1). |
| 5 | Nothing asserted `hooks/lib/json.sh` exists | verify check 21b: existence in `hooks/lib/` AND `user-level-reference/hooks/lib/`, plus `git-cmd.sh` still sources it. |
| 6a | Fixtures for the python3-only WARN text and `enforce-agent-contract` with no parser | Added (`node not on PATH (found python3)`, `no JSON parser on PATH`). |
| 6b | WARN once per hook | `json_warn_once` + marker `$TMPDIR/claude-hook-warn-<hook>`; fixture invokes `read-size-gate` 3× with one TMPDIR and asserts exactly 1 WARN. `check_env` gives every case a fresh TMPDIR so the suite stays order-independent. |
| 6c | `bash-output-guard.sh` header said "always silent" | Amended. |
| 6d | BLOCKED message | Now ends `Install one, or create <cwd>/.claude/git-guard-off to opt out.` |
| 6e | `pre-commit-test.sh` header | Documents fail-closed-without-parser like the other two gates. |

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
