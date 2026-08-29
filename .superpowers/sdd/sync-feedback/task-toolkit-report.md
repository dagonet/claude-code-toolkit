# PR10 — sync-template consumer feedback (toolkit side)

Branch: `worktree-agent-ad4fef27a86f63aee` (the intended `v2/pr10-sync-feedback` is
checked out by the shared worktree at `G:/git/claude-code-toolkit`, which a
worktree-isolated agent may not touch — the controller merges this branch).

Skills invoked: `superpowers:test-driven-development`, `karpathy-guidelines`,
`superpowers:verification-before-completion`.

## Commits

| SHA | Subject |
|---|---|
| `fa0a1a6` | fix(hooks): git gates fail closed on a missing lib and on a pre-v2 MCP matcher |
| `a262810` | fix(settings): deny git-tools MCP write ops; matchers own the coder shape, not the list |
| `6e20aab` | docs(sync-template): close the semantic gaps three consumer syncs found |
| `48298fe` | release: v2.1.1 — consumer sync feedback, fail-closed gates, git-tools deny |
| (fixup)   | CHANGELOG corrections (`LOG_FILE=` not `LOCK_FILE=`; dead consumer anchors removed) |

## TDD evidence

### A — fail-closed gates (RED, before any hook edit)

```
=== git gates: fail-closed contracts ===
FAIL  no-push-main without lib/                  (want 2 + "run /sync-template step 6b", got 0: .../nolib/no-push-main.sh: line 11: .../nolib/lib/git-cmd.sh: No such file or directory)
FAIL  pre-commit-test without lib/               (want 2 + "run /sync-template step 6b", got 0: ...)
FAIL  gate-before-merge without lib/             (want 2 + "run /sync-template step 6b", got 0: ...)
FAIL  no-push-main via mcp git_push              (want 2 + "settings.json predates this hook", got 0: )
FAIL  no-push-main via mcp git_commit            (want 2 + "settings.json predates this hook", got 0: )
FAIL  pre-commit via mcp git_commit              (want 2 + "settings.json predates this hook", got 0: )
FAIL  pre-commit via mcp git_push                (want 2 + "settings.json predates this hook", got 0: )
PASS  no-push-main: unrelated MCP tool           (exit 0)
PASS  pre-commit: unrelated MCP tool             (exit 0)
PASS  Bash push still blocked on main            (exit 2)
PASS  Bash commit still runs tests               (exit 2)

test-hooks.sh: 135 passed, 7 failed
```

Full RED capture: `.superpowers/sdd/sync-feedback/red-evidence.txt`.

GREEN after the hook edits: `test-hooks.sh: 142 passed, 0 failed`.

### H — pre-commit-test Gate fallback (RED)

```
PASS  Gate-only context, gate passes             (exit 0)
FAIL  Gate-only context, gate fails              (want 2, got 0)
PASS  Test wins over Gate when both              (exit 0)
FAIL  no Test/Gate warns, allows                 (want 0 + "WARN: pre-commit-test: no Test/Gate command in PROJECT_CONTEXT.md", got 0: )
FAIL  no PROJECT_CONTEXT warns too               (want 0 + "...", got 0: )
test-hooks.sh: 144 passed, 3 failed
```

GREEN: `147 passed, 0 failed`.

### F — require-skills-block binds any `<lang>-coder` (RED)

```
FAIL  cpp-coder without skills block             (want 2, got 0)
FAIL  go-coder without skills block              (want 2, got 0)
test-hooks.sh: 154 passed, 2 failed
```

GREEN: `156 passed, 0 failed`.

## Fixtures added (25: 131 -> 156)

New helper `check_msg` (exit code + ASCII stderr substring; takes an absolute
hook path so a copy under `$TMPROOT` can be exercised).

**Section `=== git gates: fail-closed contracts ===` (11)**
1. no-push-main without lib/
2. pre-commit-test without lib/
3. gate-before-merge without lib/
4. no-push-main via mcp git_push
5. no-push-main via mcp git_commit
6. pre-commit via mcp git_commit
7. pre-commit via mcp git_push
8. no-push-main: unrelated MCP tool (fail open)
9. pre-commit: unrelated MCP tool (fail open)
10. Bash push still blocked on main (regression anchor)
11. Bash commit still runs tests (regression anchor)

**pre-commit-test.sh Gate fallback (5)**
12. Gate-only context, gate passes
13. Gate-only context, gate fails
14. Test wins over Gate when both
15. no Test/Gate warns, allows
16. no PROJECT_CONTEXT warns too

**Section `=== hooks/require-skills-block.sh ===` (9, new section — this hook had none)**
17. cpp-coder without skills block
18. go-coder without skills block
19. cpp-coder with skills block
20. coder without skills block
21. rust-coder without skills block
22. tester without skills block
23. code-reviewer is unbound
24. coder-helper is not a coder (over-match guard)
25. unknown subagent_type passes

New fixture repo builders: `commitgateok`, `commitgatebad`, `commitboth`,
`commitnofields`; new payload builder `mkspawn`.

## Consistency assertions added (20: 172 -> 192)

**Check 22 — git-tools MCP write ops denied (7)**: one per variant (6) asserting all
six `mcp__git-tools__git_{push,commit,merge,rebase,reset,push_tags}` deny entries,
plus `user-level-reference/settings.json`.

**Check 23 — SubagentStop matchers cover project coders (13)**: per variant (6),
exactly 2 matchers of shape `^([a-z0-9]+-)?coder$`; per variant (6), the enumerated
`"matcher": "coder|dotnet-coder` is gone; plus 1 asserting
`hooks/require-skills-block.sh` binds `coder|*-coder`.

## Notes / observations (not changed — out of the stated scope)

- `templates/rust-tauri/.claude/agents/architect.md:28,32` and `rust-coder.md:72`
  still name SolidJS / `@solidjs/testing-library`. Item I scoped the de-SolidJS
  work to `rules/frontend.md`; those two load only on that agent's spawn.
- The git-tools MCP server (`G:/git/mcp-dev-servers/src/mcp_dev_servers/git_mcp.py`)
  exposes `git_push`, `git_commit`, `git_reset` — not `git_merge`, `git_rebase`
  or `git_push_tags`. Those three deny entries are pre-emptive no-ops.
- `mcp__git-tools__git_merge` was never a shipped matcher (`git log -S` across all
  refs and a grep of CHANGELOG/templates/user-level-reference: zero hits), so no
  restart block was added for it to `gate-before-merge.sh`, per the brief.
- Item K lookup: `~/.claude/plugins/cache/context-mode/context-mode/1.0.162/` —
  the routing block comes from `configs/claude-code/CLAUDE.md`, re-appended by the
  plugin's SessionStart auto-injection. No opt-out env var or config toggle found
  in its README or `hooks/*.mjs`; `claude plugin disable context-mode@context-mode`
  is the only fix.
- `hooks/require-skills-block.sh` was edited but has **no** `user-level-reference/hooks/`
  mirror, by design: `user-level-reference/settings.json` does not register it, and
  `settings-reference.md` §"Optional User-Level Install" tells the user to copy it
  from the repo-root `hooks/` directly. Check 21 walks the mirror, so nothing broke;
  the mirror set stays the six files it was.
- No git tag is created (this branch is never pushed); `VERSION` is `2.1.1` while the
  last tag remains `v2.1` at `d7251b9`. Tagging is the controller's step.
- Deviation on item F: the brief said set *both* SubagentStop matchers to the same
  regex. The second matcher (`enforce-agent-contract.sh`) never covered
  `tester`/`architect`, so it got `^([a-z0-9]+-)?coder$|^code-reviewer$` — same
  coder-shape fix, original scope preserved.
