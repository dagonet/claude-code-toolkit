# Changelog

## v2.0-pr4 — 2026-08-28

**CLAUDE.md is facts; conventions are path-scoped.** A C# style rule was being loaded on every turn of every session, including the ones that never opened a `.cs` file. `.claude/rules/*.md` files with a `paths:` frontmatter glob list load only when Claude reads or edits a matching file, and are re-injected after compaction — so the conventions arrive exactly when they are actionable.

### Path-scoped rules (new, 7 files)

- `templates/dotnet/.claude/rules/csharp.md` — `**/*.cs`, `**/*.csproj`, `**/*.props`, `**/*.targets`, `.editorconfig`.
- `templates/dotnet-maui/.claude/rules/csharp.md` (same globs) + `xaml.md` — `**/*.xaml`, `**/*.xaml.cs`, carrying the CommunityToolkit.Maui / ContentPage-namespace checks and the UI smoke-test reminder.
- `templates/rust-tauri/.claude/rules/rust.md` — `**/*.rs`, `rustfmt.toml`, `Cargo.toml`; `frontend.md` — `src/**/*.ts`, `src/**/*.tsx`, `**/*.css`, `.prettierrc`. The single Rust+TypeScript *Code Style* section was split along the language boundary so each half is scoped to the files it governs.
- `templates/java/.claude/rules/java.md` — `**/*.java`, `pom.xml`, `**/build.gradle*`, `src/main/resources/application.*`.
- `templates/python/.claude/rules/python.md` — `**/*.py`, `pyproject.toml`, `requirements*.txt`, `ruff.toml`.
- **Only `paths:`-scoped rules ship.** An unconditional rule loads at launch at CLAUDE.md cost — it is always-loaded context wearing a `rules/` filename, and buys nothing. `general` has no language of its own and therefore ships no rules; its CLAUDE.md says where conventions belong instead.
- `{{FORMAT_COMMAND}}` / `{{LINT_COMMAND}}` placeholders survive the move: `setup-project.sh` / `.ps1` walk `.claude/` recursively and run `apply_replacements` on every copied file, so rules are populated and manifest-tracked like any other template file.

### CLAUDE.md diet (×6)

- **Spawn-Prompt Binding Table deleted.** It duplicated `AGENT_TEAM.md` → *Spawn-Prompt Binding Table* and is enforced by `hooks/require-skills-block.sh`, which reads neither copy. One pointer line remains.
- *Code Style (MANDATORY)*, *Enforcement Notes*, and the per-variant *Project Conventions* sections moved verbatim into rules, each replaced by `Conventions: see .claude/rules/<name>.md (loads when you touch matching files).`
- Gate rule and commit checklist compressed to name the enforcing hook once instead of restating what it does.
- Emphasis rationed: `# Session Bootstrap (MANDATORY)` → `# Session Bootstrap`, "The PO MUST use `EnterPlanMode`" → "the PO calls `EnterPlanMode`", "Every plan MUST declare its tier" → "Every plan declares its tier". The one surviving shouted line is the Superpowers header, which two hooks and the verify script pin.
- **Bytes:** general 13,892 → 12,522 · dotnet 15,450 → 12,772 · dotnet-maui 15,699 → 12,728 · rust-tauri 16,749 → 13,456 · java 16,378 → 13,105 · python 16,299 → 13,131. Always-loaded total on `general`: **32,888 → 31,518 B**, and **41,167 → 31,518 (−23%)** against the pre-trim baseline.
- The **6 KB / 7 KB targets in the plan were not met and are not reachable** by this route: the sections the plan also lists as *keep* (Session Bootstrap, Workflow TL;DR, Open Brain, Superpowers, Working Preferences, Verification, Compact Instructions) account for ~11 KB on their own. Cutting further means deleting content the plan protects; the honest number is reported instead.

### Verification

- `scripts/verify-template-consistency.sh` §19 (new, 3 assertion groups, all glob-derived): every non-`general` variant ships ≥ 1 `.claude/rules/*.md`; every rules file carries a `paths:` list with at least one glob; every such variant's CLAUDE.md still points at `.claude/rules/`. 148 → 159 assertions.
- The dangling-`VERIFICATION_PLAYBOOK.md` fix in the plan was **not applied — the premise was wrong.** The file ships in all 6 variants and `setup-project.sh` copies it; the reference resolves in a generated project.

### Downstream migration

- `/sync-template` reports `CLAUDE.md` as **CONFLICT** for any project with local edits outside the `PROJECT-CUSTOM` region. Accept the template version, then re-paste your customisations between the `PROJECT-CUSTOM:BEGIN/END` markers — that region is preserved verbatim by the sync server.
- The new `.claude/rules/*.md` arrive as `new_template_files`; accept them. If your project already had language conventions pasted into CLAUDE.md, delete them there once the rules land, or the same text loads twice.
- If a plugin-installed context-mode routing block is still present in your CLAUDE.md, delete it (removed toolkit-side in PR3).

## v2.0-pr3 — 2026-08-28

**Every agent now declares what it costs.** Transcripts showed the orchestrator on Opus, workers on `sonnet`, Haiku almost unused, and the *built-in* `Explore` inheriting the session model — 219 exploration spawns at Opus prices. In the same window ~400 tool calls hit tools the calling agent did not have (`dotnet-tools`: 87 of 87 failed, advertised in the body and absent from `tools:`), and 5,032 of 10,336 `Read` calls passed no `limit`.

### Model & effort routing

- Every agent file carries `model:` and `effort:`: coders `sonnet` / `medium` / `isolation: worktree`; `tester` + `test-writer` keep their model and gain `effort: medium` + `isolation: worktree`; `architect` + `code-reviewer` `opus` / `high`; `requirements-engineer` + `ops` `sonnet` / `medium`; `doc-generator` `haiku` / `low`.
- **Aliases only** (`sonnet` / `opus` / `haiku` / `fable` / `inherit`) — a model proxy reroutes aliases, and a pinned `claude-*` id bypasses it. Asserted by the verify script.
- `mode: bypassPermissions` is removed from all 61 pre-existing agent files: it is not a documented subagent field and was silently ignored.
- New `## Model & Effort Policy` section in `AGENT_TEAM.md` (×6) with the diagnostic rule: wrong despite full context → bigger model; skipped files or tests not run → raise effort.

### Custom `Explore` agent (new, ×7)

- `.claude/agents/Explore.md` in all 6 variants + `user-level-reference/` overrides the built-in `Explore` and pins it to `haiku`, `effort: low`, `tools: Read, Grep, Glob, Bash`. It carries a breadth contract (`quick` / `medium` / `very thorough`), a 500-line-per-`Read` rule, and a fixed output shape: ranked `path:line — why it matters` plus a ≤5-line synthesis.
- The `model: "haiku"` spawn snippets are gone from `CLAUDE.md` (×6) and the three `AGENT_TEAM.md` spots — the agent file carries the model now, and passing one in the Agent call overrides it.

### Skills actually reachable

- `Skill` added to `tools:` for all 54 agent files that are told to invoke skills. Without it a subagent cannot run the `## Required Skills` block the PO injects — the block had been dead for coders.
- All 12 coders preload `skills: [karpathy-guidelines]`, so the house style is in context from turn one, and all 12 gain `Write`: a coder that cannot create a file is not a coder (44 `Write` calls died on the allowlist in the mined sessions).
- `dotnet-coder` (dotnet, dotnet-maui) gains `mcp__dotnet-tools__build_and_extract_errors` + `mcp__dotnet-tools__run_tests_summary` in `tools:` — the body already told it to use them.

### Native context hooks

- `hooks/read-size-gate.sh` **caps instead of blocking**: an unbounded `Read` whose remaining length exceeds 500 lines is rewritten via `hookSpecificOutput.updatedInput` to carry `limit: 500`, with `additionalContext` naming the next offset. `updatedInput` replaces the whole input object, so `tool_input` is copied wholesale (`pages` and future fields survive). Silent when `limit` is set, the file is short, or the extension is `png|jpg|jpeg|gif|pdf|ipynb`. Fixes the pre-existing bug where `offset` was ignored. The context-mode advice in the old block message is gone.
- `hooks/bash-output-guard.sh` (new, `PostToolUse` on `Bash|PowerShell`, registered unwrapped ×6 + user-level): `tool_response.stdout` **and** `stderr` are checked independently; a stream over 12,000 chars is written whole to `$TMPDIR/claude-bash-out/<session_id>-<epoch>[-stderr].log` and replaced by head 4,000 + a marker naming the log + tail 4,000 via `updatedToolOutput`. Payload shape observed from a real event: `{stdout, stderr, interrupted, isImage, noOutputExpected}`; the sibling fields are copied, not re-invented.
- Both hooks pipe the payload to `node` on **stdin**, never in argv (Linux caps one argument at 128 KiB, Windows CreateProcess caps the command line at 32,767 chars — an argv-passed 200 KB build log would fail to exec and slip through untruncated). `read-size-gate.sh` also runs a single node process per Read instead of five, and decides from `stat` alone above 10 MB rather than scanning the file to count lines.
- `hooks/allow-ctx-plan.sh` deleted. context-mode is an optional plugin from here on, not a routing mandate.

### Verification

- `scripts/verify-template-consistency.sh`: new check **17** (tool-allowlist invariant — every `mcp__server__tool` named in an agent body must be in that agent's `tools:` line; files without `tools:` inherit everything and are exempt) and check **18** (Explore ×7 on haiku, no `claude-*` ids, no `mode:`, `Skill` in all 47 skill-invoking agents, `karpathy-guidelines` preloaded in all 11 coders). Agent count is now 68.
- `scripts/test-hooks.sh`: 101 → 125 fixtures — the Read cap (field-level assertions on `updatedInput`, offset handling, image skip) and the output guard (shape, head/tail, log file, pass-through).

### Downstream migration

1. Run `/sync-template`. `Explore.md` appears as a **new template file** in every variant; accept the agent definitions (`model` / `effort` / `Skill` / `mode:` removal), `AGENT_TEAM.md`, `CLAUDE.md` and `settings.json`.
2. If your `settings.json` is locally modified, add the one new entry by hand: `PostToolUse` matcher `Bash|PowerShell` → `bash hooks/bash-output-guard.sh`, **without** the 127 wrapper. Nothing else in `settings.json` changed.
3. **Delete the plugin-installed `# context-mode — MANDATORY routing rules` block from your project `CLAUDE.md`** if present. The context-mode plugin is optional now; the Read cap and the output guard do the same job natively, without a routing contract the model has to remember.
4. Delete `~/.claude/hooks/allow-ctx-plan.sh` and its matcher group from `~/.claude/settings.json` if you installed it.
5. Do **not** pass `model:` in Agent calls any more — it overrides the agent file's routing silently.

## v2.0-pr2 — 2026-08-28

**Agent teams are retired; parallelism comes from the Agent tool.** Every "sub-agent stalled / went idle without returning" complaint in six weeks of transcripts traced back to a *named teammate*; the 1,777 Agent-tool spawns in the same window never stalled. Agent teams are experimental and off by default, `TeamCreate`/`TeamDelete` no longer exist and `team_name` is deprecated — so the toolkit stops relying on them. What does **not** change: the PO still never does hands-on work at any tier, and `hooks/enforce-delegation.sh` is untouched (it keys on `agent_id`, which Agent-tool subagents provide).

### Retired

- `hooks/require-teammate-report.sh` — the `TeammateIdle` gate becomes a **no-op stub** (header + `exit 0`), removed in v2.1. It stays non-empty so a downstream `settings.json` that still names it does not fail closed on a 127. PR1 already dropped its registration.
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` — gone from `user-level-reference/settings.json` and `settings-reference.md`.
- `AGENT_TEAM.md` — the *Agent Naming Convention* section (`dev-1`, `reviewer-2`, …) is deleted: a workstream is a position in the plan, not an agent name. The *Communication Protocol* is now the final-message contract; long tasks use `background: true` and the task-completion notification. The only surviving use of `SendMessage` is asking a *completed* subagent one follow-up question. The stall runbook is rewritten for Agent-tool completions (a foreground call cannot stall — it returns or errors; a background agent is checked once, then treated as failed) and no longer mentions `TaskStop` or `git status` polling. Worktrees are created with `isolation: worktree`, not by hand.
- All 61 agent definitions: the SendMessage progress-ping bullet becomes the final-message contract, and `Team-mode reporting` is renamed `Subagent reporting`. The `## Liveness & Scope` header and the `Scope abort:` clause are unchanged.

### Retro ledger (new)

- `hooks/retro-ledger.sh` (`SubagentStop`, no matcher) parses the finished subagent's own transcript and appends one line per failing run to the project's auto-memory `memory/retro.md`: `date | agent_type | agent_id | dead=[…] | blocks=[…] | errors=n`. A failure is a `tool_result` matching `No such tool available|BLOCKED:|DELEGATE:|CONTRACT VIOLATION|hook error`.
- `hooks/retro-brief.sh` (`SessionStart`, no matcher) prints the last 10 entries; SessionStart stdout is injected as session context, and the Session Bootstrap in every `CLAUDE.md` now has a step that says to fix the cause (agent `tools:` allowlist, prompt, hook) or delegate it before starting new work.
- Both are registered **unwrapped** — no exit-127 fail-closed wrapper. They cannot block anything: every failure path (missing node, missing transcript, unparseable payload, unwritable dir) exits 0. Wrapping a hook that cannot block would only invent a failure mode, exactly as with the other stop-style hooks.
- `scripts/test-hooks.sh`: 71 → 92 fixtures, including a round-trip case (ledger writes, brief reads) that catches the two hooks computing different project slugs — the one way this feature silently does nothing.

### Downstream migration

1. Run `/sync-template` — accept `AGENT_TEAM.md`, the agent definitions, `CLAUDE.md` and `settings.json`.
2. Delete `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"` from your `~/.claude/settings.json`.
3. **Named-teammate spawns are no longer required.** Use plain Agent calls (several in parallel for parallel workstreams) and read each subagent's final message. If your `settings.json` is locally modified, add the two new entries by hand: `SubagentStop` → `bash hooks/retro-ledger.sh` and `SessionStart` → `bash hooks/retro-brief.sh`, both **without** the 127 wrapper.
4. The retro ledger lands in `~/.claude/projects/<project-slug>/memory/retro.md`, next to `MEMORY.md` — the slug is your project path with every `:` `\` `/` `.` `_` replaced by `-` (`G:\git\foo` → `G--git-foo`). Delete the file to reset the ledger.

## v2.0-pr1 — 2026-08-28

**The git ban is over; the git gates stay.** `hooks/block-bash-vcs.sh` blocked **1,240 turns in 6 weeks** of transcripts to buy nothing — the three git gates keyed on the `mcp__git-tools__*` tool names only because Bash git was banned in the first place. Claude Code 2.1.250 PreToolUse hooks can read `tool_input.command` and deny with exit 2, so the gates now fire on the command itself and the CLI is allowed.

### Hooks

- `hooks/lib/git-cmd.sh` (new) — shared parsing: split the command on `&&`, `||`, `;`, `|` and newlines, unwrap `bash -c "…"` / `sh -lc` / `pwsh -Command` payloads, match **unanchored** per segment (a false positive on `echo "git push origin main"` is the accepted cost of failing closed). `git -C <path>` retargets the repo; `<cwd>/.claude/git-guard-off` is the escape hatch for all three gates.
- `hooks/pre-commit-test.sh` — fires on `git commit` (any `-C` / `-c` prefix, any wrapper). Unchanged behaviour otherwise.
- `hooks/no-push-main.sh` — fires on `git push` to an explicit `main`/`master` ref (including `HEAD:main` and `refs/heads/main`) **or** on a refspec-less push while the checkout is on main. `git push origin feature/x`, `--force-with-lease`, `--tags` and `origin :feature/x` are not blocked.
- `hooks/gate-before-merge.sh` — adds `gh pr merge`, `git merge` while on main, and a push targeting main. The MCP branch for `mcp__MCP_DOCKER__merge_pull_request` / `mcp__github-tools__github_pr_auto_merge` is unchanged (those are GitHub tools, not git-tools). Artifact freshness logic untouched.
- `hooks/block-bash-vcs.sh` — no-op stub for one release, removed in v2.1.
- `scripts/test-hooks.sh` (new) — 46 stdin fixtures over throwaway git repos, including every must-NOT-block case.

### settings.json (all 6 variants + `user-level-reference`)

One `PreToolUse` entry `"Bash|PowerShell"` runs the three gates in order; the `mcp__git-tools__git_commit` / `git_push` entries and the `block-bash-vcs` entry are gone. `Read` gains `hooks/read-size-gate.sh` with a **fail-open** wrapper (127 → exit 0). The `TeammateIdle` block is removed. `permissions.defaultMode` `dontAsk` → `auto`; `Bash(*)`, `WebFetch(*)` and `mcp__git-tools__*` drop out of `allow`, `Bash(bash hooks/run-gate.sh*)` comes in.

### Agents

The `Bash(git *)` / `Bash(gh *)` frontmatter blocks are gone from all 26 coder/tester/test-writer definitions, and the 19 `mcp__git-tools__*` entries leave every coder's `tools:`. The coder merge gate now matches `Bash|mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`, so `gh pr merge` is gated exactly like the MCP tools.

### Downstream migration

1. Run `/sync-template` — it accepts the new `settings.json` and agent definitions.
2. **If your `settings.json` was locally modified**, sync will not rewrite it. Delete the whole `TeammateIdle` block and the `PreToolUse` matcher that invokes `block-bash-vcs.sh` by hand, then add the `"Bash|PowerShell"` entry from `templates/general/.claude/settings.json`. Leaving the old `block-bash-vcs` entry in place is safe but pointless — the script is now a no-op stub.
3. Agents may use the `git` and `gh` CLIs. The **`git-tools` MCP server becomes optional**: nothing in the toolkit requires it, and git work done through it bypasses the gates, which key on `Bash`/`PowerShell` commands.

## v1.5 — 2026-07-29

Closes the item v1.4 recorded as outstanding: `CLAUDE.md`'s *Working Preferences* section restating rules that hooks already enforce.

**18 bullets → 11. 3,939 → 2,393 B per variant.** Always-loaded config on `general`: **34,084 → 32,538 B**, and **41,167 → 32,538 (−20%)** against the pre-trim baseline.

### What was cut, and what enforces it instead

| Bullet | Enforced by |
|---|---|
| Read before editing | the harness — `Edit` fails without a prior `Read` |
| Test after every change | `hooks/pre-commit-test.sh`, `run-gate.sh`, `gate-before-merge.sh` |
| Never push to main | `hooks/no-push-main.sh` (PreToolUse on `git_push`) |
| Read tool discipline | `hooks/read-size-gate.sh` + the routing table in `~/.claude/CLAUDE.md` |
| Subagent discipline | `hooks/enforce-delegation.sh` — the PO cannot edit or build |
| Summarize tool work | no behavioural content |
| Fix CI proactively | no behavioural content beyond "fix the failure" |

In their place, one line naming where the enforcement lives, so the omission reads as deliberate rather than as an oversight. Stating that a mechanism exists, instead of repeating the rule it enforces, is the unhobbling move the Claude 5 context-engineering guidance argues for.

**Kept (11)** — the judgement calls no hook can make: implement-don't-suggest, minimal fix first, analyze before coding, re-plan on failure, tests, post-merge verification, update docs with code, commit messages explain why, clean finish, checkpoint long sessions, learn from corrections. The *Actor note* preamble is kept verbatim: it assigns these to developer agents and is load-bearing for the delegate-everything model.

**Duplication:** the `"22% of total context"` statistic went from **7 files to 1** — the single authoritative copy in `user-level-reference/CLAUDE.md`, which already carries the full Read & Search routing table.

### Why this cut was safe

Nothing under `hooks/` or `scripts/` greps any of this section — verified before editing, not after. That is the opposite of the Superpowers block in v1.4, where two consistency assertions depended on an exact header and a token. Deleting prose a mechanism enforces is safe in a way that deleting an unenforced rule is not.

### Verification

131 assertions green. The section is byte-identical across all six variants before *and* after (single md5), so this was one rewrite applied six times. All seven cut phrases return zero hits across `templates/`. The six enforcing hooks are present and untouched. Section boundaries intact — `general`/`rust-tauri` are followed by `## Quick Start`, the other four by `# Code Style (MANDATORY)`, and the extraction had to stop at any `^#` rather than `^## ` to handle both.

## v1.4 — 2026-07-29

Closes the two items v1.3 left open: the context trim, and a copyable user-level `settings.json`.

### Context trim — measured, and a relocation rather than a deletion

Always-loaded config on the `general` variant: **41,167 B → 34,084 B (−17%)**.

| File | Before | After |
|---|---|---|
| `templates/general/CLAUDE.md` | 17,871 | **15,281** |
| `templates/general/CLAUDE.local.md` | 13,845 | **9,352** |
| user-level `CLAUDE.md` | 8,505 | 8,505 |
| `PROJECT_CONTEXT.md` | 946 | 946 |

Per-variant after: general 34,084 · java 37,254 · python 37,064 · dotnet 38,083 · rust-tauri 39,176 · dotnet-maui 39,861.

Nothing was dropped — three moves, each to a surface that loads on demand:

- **New `mcp-usage` skill** takes ten procedures out of every `CLAUDE.local.md`: Ollama warm-up, large-input digestion, structured extraction, project orientation, code-quality and security sweeps, Context7 lookups, headless batch runs, performance guidance, and the default MCP-first workflow. All ten were present in 6/6 variants and are needed occasionally, so they were pure always-on cost. What stays inline is what binds every turn: registered servers, the git/GitHub MCP-only requirement, Open Brain, trust/verification, failure handling. Skills 11 → 12.
- **Open Brain per-agent tables** (1,750 B of search-query and capture guidance, only relevant while spawning) moved into `AGENT_TEAM.md`, which is already on-demand — appended identically to all six so the §7 byte-identity invariant still holds (47,968 → 49,724 B).
- **Superpowers block** keeps its exact header, its three hard triggers, and a `superpowers:` token, and points at the user-level copy for strong triggers, plugin defaults, and meta skills.

The on-demand side growing while the always-loaded side shrinks is the intended direction, not an accident.

**Guardrail:** `verify-template-consistency.sh` checks 2 and 3 assert the exact `## Superpowers Skills — MUST Invoke Before Responding` header *and* a `superpowers:` token in `CLAUDE.md` and `AGENT_TEAM.md`. Both survived the reduction — verified at 1 exact header and 10 tokens per variant. 131 assertions, all green.

**Still on the list:** `CLAUDE.md`'s 17-bullet *Working Preferences* (~3.9 KB) still restates rules that `no-push-main.sh`, `enforce-delegation.sh`, and the gate now enforce mechanically.

### A copyable user-level `settings.json`

`user-level-reference/` previously shipped only prose. The blocker was whether `~` survives inside a hook `command` string — untested, and a wrong answer would have produced silently dead hooks.

**Measured, not assumed:** a probe bound at both `bash ~/.claude/hooks/…` and `bash $HOME/.claude/hooks/…` fired, and `$0` resolved to the real absolute path in both. So the shipped file uses `~`.

Sanitised: no machine paths (only `CLAUDE_CODE_SHELL`, which is documented as Windows-only), no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries. Two permissive settings are called out in the README rather than left for a copier to discover — `Bash(*)` in `permissions.allow`, and the Windows shell path. Two new assertions check the file is valid JSON and that no hook command uses an absolute home path.

## v1.3 — 2026-07-29

Two correctness fixes, both of the same shape: **config that was built correctly and wired to a path nothing reads.**

- **`user-level-reference/` made safe and accurate as a `~/.claude/` source** (#47). Its `coder.md` was a copy of the *template* coder, carrying `PreToolUse` hooks that run `hooks/gate-before-merge.sh` with a `127 → exit 2` fallback. A user-level agent applies in every repo and its frontmatter hooks travel with it: measured, **11 of 20 local repos fall back to user-level agents and 10 have no `hooks/` directory**, so copying it as-is would have made PR merges impossible in 10 repos. Template copies keep the gate; the user-level copy does not; `verify-template-consistency.sh` asserts both halves.
- **Project MCP config now written to `<project-root>/.mcp.json`** (#48) — the only path Claude Code reads for project scope. `dotnet-tools` / `rust-tools` / `windows-mcp` had never loaded in any generated project. Includes a migration warning, an activation check, and a repo-wide correction of the user-scope path to `~/.claude.json`.
- **README documents the toolkit's stance on context engineering for Claude 5 generation models**, with measured numbers on both sides of the ledger: what is already progressive-disclosed (`AGENT_TEAM.md`, 47,968 B, not auto-loaded; 11 on-trigger skills; 13 hooks doing enforcement instead of prose) and what is not yet trimmed (~41 KB always-loaded across 4 files, 11–14 directives/100 lines, known cross-layer duplication).

129 consistency assertions, all green. Detail for each change is in the entries below.

## 2026-07-29 — project MCP servers were written to a path Claude Code never reads

`setup-project.{sh,ps1}` generated `<target>/.claude/.mcp.json`. **Claude Code reads project-scope MCP servers only from `<project-root>/.mcp.json`** — `<project>/.claude/.mcp.json` is an open upstream feature request, not current behaviour (anthropics/claude-code #43296, #3321).

For `dotnet`, `dotnet-maui`, and `rust-tauri` that file was the **sole** registration of `dotnet-tools` / `rust-tools` / `windows-mcp`. Those servers have therefore **never loaded in any project this toolkit set up**. `enableAllProjectMcpServers: true` does not help — it governs auto-approval, not file discovery.

Corroborated locally, independent of the docs: 7 repos keep a working root `.mcp.json`; `InvestmentAdvisor`'s generated `.claude/.mcp.json` (`sqlite`, 2026-02-22) was superseded by a root file (`sqlite, windows-mcp, playwright`, 2026-04-12); in `Yutraffic-Challenge` the `windows-mcp` entry sits only in `.claude/` and is not loaded.

### Changes

- Both setup scripts now write **`<target>/.mcp.json`**, and **never clobber an existing root file** without `--force` (several repos already keep a hand-maintained one) — they print which servers the variant *would* have added instead.
- Both **warn when they find a legacy `.claude/.mcp.json`**, naming it as a path that is not read.
- `scripts/check-activation.sh` gained a *project MCP wiring* section: root file + servers, stale `.claude/` copy, and the exact `mv` to run.
- Root `/.mcp.json` is gitignored in all 6 variants — the generated file carries machine-specific paths (sqlite DB path, `mcp-dev-servers` venv). The legacy line stays so migrating projects don't suddenly start tracking it.
- User-scope path corrected repo-wide to **`~/.claude.json`** (`~/.claude/.mcp.json` is not a concept; an `mcpServers` key in any `settings.json` is silently ignored).
- 12 new consistency assertions pin the write path, the legacy warning, and the gitignore entries (129 checks, all green).

### Migration — required for existing projects

```bash
git mv .claude/.mcp.json .mcp.json     # or merge into an existing root .mcp.json
bash scripts/check-activation.sh .     # confirms wiring
```

### Verification

End-to-end against real setup runs, not just greps: dry-run announces the root path; a real `rust-tauri` run puts `rust-tools, windows-mcp` in root `.mcp.json` as valid JSON with **no** `.claude/.mcp.json`; a pre-existing hand-made root file survives untouched; a planted legacy file triggers the warning.

## 2026-07-29 — v1.2: liveness caps corrected after four days of production exposure

v1.1's two liveness hooks were installed in a real project on 2026-07-25 11:41 and ran for four days. They worked — and both were mis-sized. This release fixes the sizing, adds an audit trail, and adds a way to answer "is it on?" without a transcript investigation.

### What the production data showed

Project `Motorsport-Manager-AI-Agent`, one 208 MB / 10-day transcript. The hooks' own state directories are written on every run, so they are direct proof of execution: the liveness ledger held exactly **3** `.blocked` markers and the budget directory held **150** counter files.

- **The liveness gate exhausted itself in 21 hours.** Its three blocks landed 07-25 18:24, 07-26 13:43 and 07-26 15:49, hitting the session-wide `MAX_BLOCKS=3`. From that point it returned 0 for every subsequent idle — and **618 idle notifications** followed over the next three days.
- **The budget's single block does not stop a runaway.** Across 150 tracked agents: median **15** calls, **35 over 60**, **19 over 120**, worst **417**. Blocking once at 120 and warning thereafter left the 417-call agent running.
- **Neither hook was observable.** Their stderr goes to the agent or teammate, not the lead transcript, and nothing was logged. Grepping the transcript for the hooks' own output returns zero — which is exactly why an initial analysis concluded, wrongly, that the fix had never activated.

### Changes

- **`hooks/require-teammate-report.sh`** — the session-wide `MAX_BLOCKS` cap is **deleted**, not retuned. The per-teammate marker (one block per teammate, ever) is now the only throttle; it already bounds the total at the number of teammates that qualify. An intermediate design added a daily cap and was cut: the measured worst day is 10, so it could never bind.
- **`hooks/agent-budget-warn.sh`** — blocks now **escalate**: 120, 180, 240, and every 60 thereafter, instead of blocking once. Every threshold test is `-eq`, never `-ge`, so calls between thresholds pass and a blocked agent can still deliver its partial report.
- **Audit trail** — both hooks append to `.claude/liveness.log` (gitignored in every variant). **Threshold events only**: the budget hook runs on every tool call, so logging passes would add a second hot-path write and ~10,000 lines of no signal per session. Writes are best-effort and can never change an exit code.
- **`scripts/check-activation.sh`** (new) — reports, for any project: hook bindings in `settings.json`, hook scripts on disk, kill switches, `.claude/liveness.log` contents, and the ledger directories that prove execution.

### Measured effect

Replayed the **shipped** script over the same 208 MB transcript, feeding each of the 250 qualifying triggers the transcript prefix it would have seen in production:

| | blocks | worst day |
|---|---|---|
| v1.1 (`MAX_BLOCKS=3`) | **3** | — |
| v1.2 (no session cap) | **41** | 10 |

That is the whole claim. It does not say teammates now report reliably — it says the gate stays armed for the life of a long session instead of 21 hours.

### Rollout — required, and not automatic

**A template is a source, not a shipment.** v1.1 was merged to `templates/` and reached exactly **one of 15** projects; the rest have no `TeammateIdle` binding and mostly no `hooks/` directory, so for them the fix has never existed. Getting v1.2 into a project needs both halves:

1. the scripts in `<project>/hooks/`, and
2. the bindings in `<project>/.claude/settings.json`.

`/sync-template` installs both. Verify with `bash scripts/check-activation.sh <path-to-project>`. These hooks are deliberately **not** registered at user level: their commands are `bash hooks/…`, resolved relative to the project root.

### Verification

21 hook assertions plus the replay gate, all passing. Notable cases: a 4th distinct teammate blocks (v1.1's cap suppressed it) and 10 more after that; a teammate that reported is never blocked (guards the escape-tolerant regex against JSON-escaped tags); calls 121–179 all pass between block thresholds; the budget log contains exactly 4 lines after 250 calls, not 250.

## 2026-07-25 — Agent liveness, part 2: TeammateIdle report gate + tool-call budget

Part 2 binds the two hooks part 1 deferred, after verifying every mechanism against live hook stdin rather than documentation. **Also corrects a number reported in part 1.**

### Correction to part 1

Part 1 claimed "64 of 90 teammates never sent a substantive message." **That figure was wrong — the true count is 4 of 90.** The mining pass that produced it only parsed `message.content` when it was a string, so it missed every teammate message delivered as array-form content. Re-measured over the full transcript: 90 teammates, 279 bare idle notifications, **305** substantive messages, and 86 of 90 teammates reported at least once.

The pain point is real but has a different shape than reported. It is not "teammates never report" — it is **teammates idling repeatedly between reports**. Worst observed run: `m13-coder` with the sequence `R R I I I I I I I I I I R …` — ten consecutive idles with no output. That reframing changed the trigger: a "never reported" gate would have fired for 4 of 90 teammates and been useless.

### Verified hook contracts (measured, not documented)

A log-only probe captured real stdin for every candidate event:

- **`TeammateIdle`** carries `teammate_name`, `team_name`, `session_id`, `transcript_path` (the **lead's** transcript, where teammate messages land), `cwd`, `prompt_id`, `permission_mode`. `exit 2` **blocks the idle**, and the stderr text is delivered **to the teammate** — confirmed end-to-end: a probe teammate read the block message and converted its silent idle into a report. It has **no loop guard**; it fired twice for the same teammate 9 s apart, so a hook here must carry its own ledger.
- **`PreToolUse` fires for named teammates and carries `agent_id` plus `agent_type`.** This was the open question that gated the budget hook: teammates are separate sessions, and `agent_id` is documented as subagent-only. It is present, so the agents that actually run away are reachable.
- **`Stop`** carries `last_assistant_message` and `background_tasks`, but `background_tasks` reported `status: "running"` for a teammate that had idled 12 s earlier and carries no `teammate_name` — useless for idle detection. **`TaskCompleted`** carries no `teammate_name` and no task result, so it cannot attribute a completion to a teammate or judge report substance.
- Hook config **hot-reloads**; the "read at session start" note added in part 1 was wrong and is corrected here.
- `"*"` is not a match-all matcher (malformed regex); omitting `matcher` is. Per-hook `if` filters work, verified firing exactly once on a narrow pattern.

### New hooks

- **`hooks/require-teammate-report.sh`** (`TeammateIdle`, **not** 127-wrapped — a missing stop-style gate must never trap teammates in a loop). Blocks when a teammate has **2 recorded unreported idles**, i.e. this is at least its second idle with no report in between — the point at which the existing Escalation Protocol runbook says to act. On the measured transcript that selects 14 of 90 teammates; a threshold of 1 would have selected 84 of 90 and fired on healthy report-then-idle cycles. Append-only ledger keyed `session_id` + `teammate_name` (never deleted — deleting on a second idle, the pattern `enforce-agent-contract.sh` safely uses for a once-per-agent `SubagentStop`, would loop block→pass→block forever here), one block per teammate, max 3 per session, `.claude/liveness-off` kill switch, fail-open on every unexpected condition. A teammate absent from the transcript fails open: absence of evidence is not evidence of silence.
- **`hooks/agent-budget-warn.sh`** (`PreToolUse`, no matcher, WARN-on-127 wrapper). Advisory WARN at 60 tool calls, blocks **once** at 120, then warns every 60. Not a hard wall — the goal is one deliberate reconsideration, since a wall would break legitimate large tasks. Pure-shell hot path (one `grep`, no `node`) and an immediate `exit 0` on the main thread, because it runs on every agent tool call. Counters are per-`agent_id` under a per-session directory.

### Verification

32 assertions across two suites, all passing: trigger thresholds (report-then-one-idle does not block; two idles do; a report resets the streak), ledger non-deletion across repeated idles, per-session cap, fail-open paths (missing/malformed/absent), budget thresholds and per-agent counter isolation, and the kill switch. Both hooks were then replayed against the real 167-hour transcript and agreed with hand-verified ground truth on every teammate tested; whole-file scan of 68 MB costs ~0.6 s and only runs on a teammate idle.

Two bugs were caught by testing and are worth recording. The report detector originally required bare `"` in the message tags, but transcript tags are JSON-encoded (`from=\"name\"`), so every reporting teammate read as silent — the patterns are now escape-tolerant. And an apostrophe inside the `node -e` script terminated its single-quoted shell string, making bash parse the JavaScript and exit 2 on every call, which masqueraded as the gate working.

### Downstream migration
- Re-run `/sync-template`, then **restart the session** (or rely on hot-reload) so the two new hook bindings load. `settings.json` changes in all 6 variants: one `TeammateIdle` entry and one matcher-less `PreToolUse` entry.
- Both hooks fail open and both honour `.claude/liveness-off` if you need them off.
- Tune `IDLE_STREAK_BEFORE_BLOCK`, `MAX_BLOCKS`, `WARN_AT`, and `BLOCK_AT` at the top of each script.

## 2026-07-25 — Agent liveness & right-sizing, part 1: prose contracts + hook-event reference

Session-mining round 6, from a 167-hour Motorsport-Manager-AI-Agent transcript (18,237 lines, 107 user turns). Two reported pain points — sub-agents going stale without reporting, and long phases for small issues — were measured rather than assumed, and the measurement contradicted the obvious fix.

**What the data showed.** There are two agent populations and only one fails. `Agent`-tool sub-agents: **35 of 35 completed and reported**, with every `<result>` payload ≥1,606 chars (median 8,371) and zero stall-like finals — the notification carries the report inline, so a sub-agent that stops properly reports automatically. Named teammates (separate sessions, `teammate-message` protocol): **64 of 90 never sent a substantive message**, against 145 bare idle notifications and 43 real ones. Widening the `SubagentStop` contract matcher — the intuitive fix — was therefore dropped: it targets a population with a 0% failure rate. Separately, 22 of 107 turns spawned more than 2 agents (6 agents for a read-only question, 5 for `"continue"`), and the worst single spawn ran 565 tool calls over 4.2 hours against a median of 38.

**Landing in this part (prose + docs only — no behavior-gating hooks yet):**
- All **61 agent definitions** (53 template across 6 variants + 8 `user-level-reference/`) gain a `## Liveness & Scope (HARD REQUIREMENT)` block: a progress-ping cadence (one line via SendMessage roughly every 20 tool calls, so silence is distinguishable from work) and a **scope-abort** clause — if the task grows past its stated scope, stop and report partial + blocker rather than expanding inside one spawn. The scope-abort clause targets the runaway spawns directly.
- `AGENT_TEAM.md` (all 6, md5-identical): right-sizing rules in *Tier Selection Guidelines* — lowest defensible tier wins, the tier table is a **cap** on team size rather than a menu, single file/symbol ⇒ T1, question-shaped turns spawn at most one agent, and never spawn `Explore` for a file that is already named. Three new *T1 Examples* rows drawn from the mined incidents. Both spawn-prompt snippets (report agents **and** coders) now carry the ping + scope-abort lines.
- `CLAUDE.md` (all 6): team-size-is-a-maximum note under the tier table.
- `user-level-reference/settings-reference.md`: **corrected a wrong claim** that `SubagentStop` is informational — it blocks with exit 2, which is exactly what `hooks/enforce-agent-contract.sh` depends on. Added the agent-team lifecycle events (`Stop`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`, `SubagentStart`), the full authoritative event enum, `async`/`asyncRewake`, the note that **`"*"` is malformed regex and not a match-all matcher** (omit `matcher` instead), and that hook config is only read at session start.
- `commands/sprint.md`: treat missing pings, not elapsed time, as the stall signal.

**Deliberately deferred to part 2**, because the mechanism must be verified before it is shipped: `TeammateIdle` and `TaskCompleted` are documented, blockable, and bound by nothing in this toolkit — that is where the 64 silent teammates are reachable. A probe is staged locally to capture their real stdin before any gate is written. Note also that the 64-teammate figure proves silence on the *message channel only*; MMAA's work did land on `main`, so any future gate must trigger on "no report **and** no completed task", never on "no report" alone.

### Downstream migration
- Re-run `/sync-template`. Agent definitions, `AGENT_TEAM.md`, and `CLAUDE.md` change in all 6 variants; all changes are additive prose — no hook or settings changes in this part, so nothing needs a restart.
- No new hooks and no `settings.json` changes, so the §13 hook-ref invariant and existing gate behavior are untouched.

## 2026-07-19 — Downstream sync findings: hook-ref invariant, PROJECT-CUSTOM region, migration discipline (#43)

Response to `docs/2026-07-19-sync-template-dotnet-findings.md` (MMAgent's dotnet sync). Toolkit side: consistency §13 asserts every hook referenced by any variant's `settings.json` or agent frontmatter exists non-empty at the toolkit ROOT `hooks/` (root-tracked design — variants do NOT ship `hooks/`; now documented explicitly in `docs/template-sync.md` and `docs/architecture.md`). All 6 `CLAUDE.md` templates ship a `<!-- PROJECT-CUSTOM:BEGIN/END -->` sentinel region for project-owned extensions. `/sync-template` step 6b now materializes missing hook scripts via `template_apply_file(source="template")` (the server resolves root-tracked paths — never hand-copy), surfaces operating-model bumps when `CLAUDE.md`/`AGENT_TEAM.md` are in the change set, builds `applied_files` programmatically only, and re-runs `template_compute_status` after finalize as a corruption self-check. `CONTRIBUTING.md` now requires a CHANGELOG entry with a Downstream-migration subsection for behavior-changing PRs.

Server side (`mcp-dev-servers`): `template_finalize_sync` validates hash fields (`^[0-9a-f]{64}$`) and rejects path traversal; writes are LF-safe on Windows (`write_text(newline="")`); PROJECT-CUSTOM region awareness — when BOTH template and project carry the markers, region-only project edits reclassify to `UP_TO_DATE`, `apply_file(source="template")` splices the project's region into the applied template, and three-way merges exclude/reattach the region. Stored hashes remain full-content (no manifest migration).

### Downstream migration
- Re-run `/sync-template` once after updating: `CLAUDE.md` gains the PROJECT-CUSTOM sentinel — move any project-appended `CLAUDE.md` content INTO the region so future syncs preserve it mechanically.
- Update + restart the `template-sync-tools` server (`pip install -e` in its venv) before the next sync to get region preservation, hash validation, and LF-safe writes.
- No agent/hook behavior changes in this release.

## 2026-07-19 — Delegate-everything workflow (#42)

Operating-model shift: **the PO never does hands-on work at any tier** — coding, reviewing, testing, builds, env setup, and exploration are all sub-agent work on cheaper models (architect and code-reviewer stay opus). New `hooks/enforce-delegation.sh` (PreToolUse on `Edit|Write|NotebookEdit` + `Bash` in every variant) discriminates main-thread vs subagent via the `agent_id` stdin field: main-thread edits outside the orchestration surface (`docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`) and main-thread build/test commands (incl. `hooks/run-gate.sh`) are denied with a delegate message; subagent calls always pass. Deliberately fail-open with a WARN-wrapper; kill-switch `.claude/delegation-off`.

Tier model: T1 = ONE coder via the uniform PR pipeline (a 3-line `Tier: T1` plan file satisfies the spawn gate; the PO direct-commit exception is deleted); T2 adds a code-reviewer (was T3+). New `ops` agent (sonnet) for env setup/downloads/binary ops/diagnostics/gate re-runs. `Explore` added to the roster (pass `model: "haiku"`/`"sonnet"`). Report agents carry a Team-mode reporting mandate (end with a SendMessage to `main`; bare idle = non-report) because the SubagentStop stop-gate does not fire on teammate idle. Stall runbook: never self-perform; dead-coder merge handoff via a fresh coder given the PR URL + branch + worktree.

PR: https://github.com/dagonet/claude-code-toolkit/pull/42

### Downstream migration
- Run `/sync-template`: pulls the new tier tables (`CLAUDE.md`, `AGENT_TEAM.md`), updated agents, and `settings.json` hook registrations.
- Step 6b materializes `hooks/enforce-delegation.sh` and registers it in the manifest; adopt the new `.claude/agents/ops.md`.
- Expect behavior changes: the PO can no longer edit source or run builds/tests (deny messages name the right agent); T1 fixes now spawn a coder; reviewers are spawned from T2 up.
- Escape hatch for emergencies: create `.claude/delegation-off` at the repo root.

## 2026-07-09 — Session-mining round 3: plan-mode friction, config hygiene (#40)

Mined two months of session transcripts plus a full config inventory. Root-caused the recurring plan-mode permission prompts: **plan mode overrides `permissions.allow` for tools it does not classify read-only**, so an allow-listed `mcp__plugin_context-mode_context-mode__*` never stopped the `ctx_*` prompts. Fix: new `hooks/allow-ctx-plan.sh` — a PreToolUse `permissionDecision: "allow"` hook (runs before the permission system) for the nine `ctx_*` tools, with a `PermissionRequest` fallback via `EVENT=permission-request`. Deliberately **not** 127-wrapped — an allow hook must fail open. It is a user-preference hook, documented in `settings-reference.md` and shipped in `hooks/`, but not registered in any template `settings.json`.

Also: `mcp__MCP_DOCKER__update_pull_request` added to all coder agents (the PO no longer edits PR bodies on their behalf); a "Read & Search Tool Selection" decision table in `user-level-reference/CLAUDE.md` replaces three previously contradictory search rules; `/sync-template` step 6b now registers manifest-untracked hook scripts via `template_apply_file(source="skip")` (never `"template"`, which would overwrite local edits), making hook drift visible to `template_compute_status` in consumers bootstrapped before hooks tracking. `verify-template-consistency.sh` gained an `update_pull_request` lock-in check.

Files touched: `hooks/allow-ctx-plan.sh` (new), `templates/*/.claude/agents/coder.md` + variant coders, `user-level-reference/{CLAUDE.md,settings-reference.md,agents/coder.md,skills/sync-template/SKILL.md}`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/40

## 2026-07-09 — Session-mining round 2: SubagentStop stop-gate, fail-closed hooks (#39)

Added `hooks/enforce-agent-contract.sh` — a **SubagentStop stop-gate**: exit-2 blocks a coder from ending without `## Gate Results` + `## Spec Compliance` sections and a reviewer without findings or the literal `clean` (strict equality via a node parse of the last assistant message). A per-session+agent marker file bounds it to one forced continuation; a second non-compliant stop passes with a `CONTRACT-ENFORCER:` stderr signal to the PO. Deliberately fail-open when broken and **not** 127-wrapped (a missing stop-gate must not trap agents in an unstoppable loop).

Hardened the remaining enforcement layer: all PreToolUse script hooks in every variant now carry a 127-wrapper converting a missing script (fail-open by Claude Code design) into a loud `HOOK SCRIPT MISSING → exit 2`, because a synced project with an empty `hooks/` directory otherwise runs with its entire enforcement layer silently absent. `block-bash-vcs.sh` block messages now name the exact MCP replacement per subcommand. `/sync-template` gained a mandatory post-sync hook-script verification step. `verify-template-consistency.sh` repaired (a header rename had left it red on `main`) and extended with settings.json byte-identity checks.

Files touched: `hooks/enforce-agent-contract.sh` (new), `hooks/block-bash-vcs.sh`, `templates/*/.claude/{settings.json,agents/coder.md,agents/code-reviewer.md}`, `templates/*/AGENT_TEAM.md`, `templates/*/VERIFICATION_PLAYBOOK.md`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/39

## 2026-07-09 — Merge gate + agent deliverable contracts (#38)

Weak-model-parity change set: move judgment into mechanism. Projects declare a gate via a `**Gate**:` field in `PROJECT_CONTEXT.md`; `hooks/run-gate.sh` runs it and writes `.gate/last-pass.json` `{sha,branch,ts,status}` on green; `hooks/gate-before-merge.sh` (PreToolUse on `mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge`) hard-blocks a merge without a fresh, SHA-matching artifact. Coder agents gained a `## Deliverable Contract` (grep-auditable `## Gate Results` + `## Spec Compliance` sections); `code-reviewer` is pinned to `opus` with an output contract (findings or the literal `clean`). A `VERIFICATION_PLAYBOOK.md` promotes the recurring incident rules to every template root.

Files touched: `hooks/{run-gate,gate-before-merge,pre-commit-test,no-push-main}.sh`, `templates/*/{PROJECT_CONTEXT.md,CLAUDE.md,AGENT_TEAM.md,VERIFICATION_PLAYBOOK.md,gitignore,.claude/settings.json,.claude/agents/*}`, `setup-project.{sh,ps1}`, `scripts/verify-template-consistency.sh`.

PR: https://github.com/dagonet/claude-code-toolkit/pull/38

## 2026-04-26 — Open Brain v0.3.0 sync

Synced template and reference docs to match Open Brain v0.3.0 (mcp-server@0.3.0, 14 tools): the existing `thoughts_*` and `system_status` tools are joined by a write-time wiki layer (`wiki_get`, `wiki_list`, `wiki_refresh`) and on-demand contradiction surfacing (`contradictions_list`, `contradictions_resolve`, `contradictions_audit`). Documents the per-repo opt-out env var `OPEN_BRAIN_TOOLS_DISABLED=wiki,contradictions`.

The session-bootstrap directive in `CLAUDE.md` keeps the unconditional `thoughts_search`/`thoughts_recent` mandate; the wiki-first rule is appended as an intentionally conditional follow-up for synthesis-style questions on a known topic, gated on the page being non-stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days). The three-layer enforcement structure (`CLAUDE.md` bootstrap → MCP server instructions → `CLAUDE.local.md` hard requirement) is preserved — only extended.

Files touched: `templates/<6 variants>/CLAUDE.md`, `templates/<6 variants>/CLAUDE.local.md`, `user-level-reference/README.md`, `mcp-servers/HOWTO.md`, `docs/architecture.md`. `settings.json` and `settings-reference.md` already use the `mcp__open-brain__*` wildcard, so the new tools are permitted automatically.

Upstream: https://github.com/dagonet/open-brain/pull/7

Inspired-by: karpathy/442a6bf555914893e9891c11519de94f (gist) via Nate B Jones (youtu.be/dxq7WtWxi44)
