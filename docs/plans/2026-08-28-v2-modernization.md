# claude-code-toolkit v2.0 — modernize for Claude 5 / Claude Code 2.1.250

**Tier:** T4 (architectural, 6 sequential PRs)
**Team:** architect, coder, code-reviewer, tester
**Gate:** `bash scripts/verify-template-consistency.sh && bash scripts/test-hooks.sh`
Challenge 1 (scope) and Challenge 2 (correctness) performed by architect 2026-08-28 — see "Challenge record" below.

## Context

Six weeks of transcripts (2026-07-18 → 08-28; 9 sessions, 849 subagent sidechains, 161,698 assistant turns, 75,163 tool calls) plus the current Anthropic docs/blog show the v1.5 toolkit optimizing for a Claude Code that no longer exists:

| Evidence | Toolkit assumption it breaks |
|---|---|
| Every "sub-agent stalled/idle" complaint (07-25, 07-29, 08-01, 08-22) traces to **named teammates**; 1,777 Agent-tool spawns never stalled. Anthropic: teams experimental, OFF by default, `TeamCreate/TeamDelete` gone, `team_name` deprecated, "check whether a lighter option does the job first" | AGENT_TEAM.md teammate protocol, TeammateIdle hook, liveness ledgers |
| `block-bash-vcs.sh` burned **1,240 turns**; PreToolUse Bash hooks can now parse `git commit/push`, `gh pr merge` | MCP git-tools mandate exists only so hooks can key on MCP tool names |
| Main thread = Opus 5 (Fable 2.5%); workers `sonnet`→deepseek via cc-proxy; built-in Explore now **inherits main model** (219 spawns at Opus cost); Haiku 92 turns | No model/effort policy anywhere; `model: "haiku"` snippets assume old Explore |
| `ctx_batch_execute` (mandated PRIMARY tool) fails **28.6%**; 164 dead `ctx_execute` calls from subagents that lack it; routing block loaded 3× per turn | context-mode as mandatory routing layer |
| Toolkit's 12 skills: **0 invocations**; 23 commands ≈ unused (sync-template 22, challenge 10); all 493 skill calls were superpowers/karpathy. Anthropic merged commands into skills; `skill-creator` plugin does evals | commands/ + skills/ + /skill-eval + /skill-improve |
| Read = 62.6 MB of tool results, 5,032/10,336 Reads with no `limit`; 152 compactions; `.claude/rules/` (path-scoped, re-injected on compaction) unused; consumer CLAUDE.md 17–39 KB | single always-loaded CLAUDE.md; `read-size-gate.sh` unwired in 0/6 variants |
| Template ships `dontAsk` + `Bash(*)` + `WebFetch(*)`; user runs `auto` | allow rules bypass the auto classifier → shipped config makes auto mode moot |
| ~400 calls to tools the caller doesn't have (`dotnet-tools` 87/87 fail: advertised in body, absent from `tools:`) | no invariant that prose ⊆ allowlist |

Anthropic's 2026-06-18 "Steering Claude Code" rule set (CLAUDE.md = facts; "every time X" → hook; "never X" → deterministic guardrail; procedures → skills) is the design principle for v2.0.

**User decisions (2026-08-28, confirmed via AskUserQuestion):**
1. Subagents-only; retire teams machinery. **Keep "PO never hands-on at any tier"** + `enforce-delegation.sh`.
2. Native git CLI; port the three git hooks to Bash-parsing; drop `block-bash-vcs` + MCP git mandate.
3. Alias-based tiered model strategy (opus/fable orchestrator, `sonnet` workers, `haiku` Explore) + per-role `effort`; custom `Explore` agent; keep aliases (cc-proxy reroutes them).
4. context-mode demoted to optional; native hooks replace routing prose.
5. Commands → skills; cull to sync-template, contribute-upstream, challenge, sprint, commit, mcp-usage, karpathy-guidelines.
6. `.claude/rules/` for conventions; CLAUDE.md for facts (≤6 KB project CLAUDE.md).
7. `permissions.defaultMode: auto`; `autoMode.environment` at user level (docs: autoMode is **User/managed scope only**).
8. v2.0 in ~6 phased PRs; migration via `/sync-template`; deprecated hooks stay one release as no-ops.
9. (08-25 request) lightweight self-improvement: retro ledger of subagent failures.

Research artifacts: web brief `C:\Users\DarkNite\.claude\plans\eager-wobbling-clover-agent-aweb-research-b22fa63c91e3ddd3.md` (KB labels `cc-docs-*`, `anthropic-blog-steering`); mining raw `…\2d0e43d1-…\scratchpad\session-mining-results.md`.

## Verified facts that shape implementation
- context-mode block is **not in any template** (0 hits in `templates/*/CLAUDE.md`, 53 agent files). It lives in `user-level-reference/CLAUDE.md:71-135`, toolkit root `CLAUDE.md:1-60`, `hooks/read-size-gate.sh:80-91`, `hooks/allow-ctx-plan.sh`. Consumer repos got it from the plugin's own install → downstream migration note, not a template edit.
- `autoMode.*` = User/managed scope; `permissions.defaultMode` = any file. `"$defaults"` keeps built-in rules. Allow rules still bypass the classifier → drop `Bash(*)`/`WebFetch(*)`. Deny/ask evaluated before classifier → keep `deny: Read(.env*)`.
- Agent frontmatter fields: `model`, `effort` (not `effortLevel`), `background`, `isolation`, `memory`, `permissionMode`, `maxTurns`, `skills`. `mode: bypassPermissions` in 8 agents is **not a documented field** → delete. A project agent named `Explore` overrides the built-in.
- PreToolUse `updatedInput` replaces the **whole** input object. PostToolUse supports `updatedToolOutput`. SubagentStop stdin: `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`.
- `[1m]` refs: 0 in repo (nothing to remove). Explore `model:` on the Agent call is honored (`resolvedModel`), custom agent sets the default.
- Manifest v2 (`setup-project.sh:545-580`) is flat `files{}`; new dirs need no schema change; `template_sync_mcp.py:255-267` rglob surfaces them as `new_template_files`. `setup-project.{sh,ps1}` copy `.claude/` recursively (`:342-349` / `:301-308`) and run `apply_replacements` on every file.
- Existing agent-id hooks (`enforce-delegation.sh:58`, `agent-budget-warn.sh`, `enforce-agent-contract.sh`) key on `agent_id`/`agent_type` — valid for Agent-tool subagents, no change. `tier-before-coder.sh`/`require-skills-block.sh` read `subagent_type`/`prompt` — no team coupling.

## Challenge record (architect two-pass, 2026-08-28)
Accepted: drop unconditional rules files (no token saving); retro ledger → auto-memory dir, not `docs/retro.md`; PR1 = sole `settings.json` editor; delete MCP git matchers now (dead once `tools:` drops them); PR5 must sweep 40+ skill references; resolve git deadlock (drop PO git hardening — PO does git I/O for tool-less agents, `AGENT_TEAM.md:46-51`); hook regexes must match inside `bash -c`/`sh -lc`/`pwsh -Command` wrappers and `git -c` forms; `updatedInput` must carry `pages` and honor `offset`; verify counts 61→**68** computed by glob; auto mode needs `Bash(bash hooks/run-gate.sh*)` allow for subagents; migration note must cover settings.json **key** removal; add missing items (effortLevel/advisorModel guidance, remove `model: "haiku"` TL;DR snippet, MEMORY.md cap, superpowers blocks referencing culled skills).
Rejected (docs confirm): agent `effort:` frontmatter exists (model-config, sub-agents `--agents` list); PostToolUse `updatedToolOutput` exists (hooks); project agent named `Explore` overrides built-in (sub-agents, v2.1.198 note); SubagentStop stdin has `agent_transcript_path` (hooks). `bash-output-guard.sh` kept but marked optional.

## PR plan (dependency order)

Every PR: `bash scripts/verify-template-consistency.sh` green; `cp` general→5 variants for byte-identical files (AGENT_TEAM.md, settings.json; LF); CHANGELOG entry with `### Downstream migration` section; commit the plan as `docs/plans/2026-08-28-v2-modernization.md` in PR1. PRs are sequential (each rebased on the previous merge).

### PR1 — git-native hooks + consolidated settings.json (decisions 2, 7-project)
- `hooks/pre-commit-test.sh`, `hooks/no-push-main.sh`, `hooks/gate-before-merge.sh`: rewrite for `tool_name` Bash/PowerShell, parsing `tool_input.command`. Split on `&&|\|\||;|\n`; **match unanchored inside each segment and inside quoted wrapper payloads** (`bash -c "…"`, `sh -lc`, `pwsh|powershell -Command`) — false positives acceptable (fail-closed + kill switch `.claude/git-guard-off`). `bash <script>` indirection is a documented gap. Drop the MCP code paths.
  - pre-commit-test: `\bgit\b(\s+-C\s+(\S+))?(\s+-c\s+\S+)*\s+commit\b`; repo = `-C` arg else stdin `cwd`.
  - no-push-main: `\bgit\b(\s+-C\s+(\S+))?(\s+-c\s+\S+)*\s+push\b(.*)`; block if args match `(^|\s)(refs/heads/)?(main|master)(\s|$)` or `:\s*(refs/heads/)?(main|master)(\s|$)`, or no refspec and `git branch --show-current` ∈ {main,master}. Allow `--tags`, `:branch` deletes, `--force-with-lease origin feature`.
  - gate-before-merge: `\bgh\s+pr\s+merge\b` (any flags) | `\bgit\b(\s+-C\s+\S+)?\s+merge\b` while on main/master | push matching the main-ref pattern. SHA/artifact logic (`:37-55`) unchanged.
  - Confirm PowerShell tool stdin uses `tool_input.command` (fixture) before wiring `PowerShell` in the matcher.
- `hooks/block-bash-vcs.sh` → no-op stub (`exit 0`, header "DEPRECATED v2.0, removed v2.1") — keeps `TEMPLATE_DELETED` and the §13 hook-ref invariant (`:276-293`) quiet.
- `templates/*/.claude/settings.json` — **the only PR that edits it** (edit general, cp ×5): (a) replace Bash→block-bash-vcs entry (`:39-47`) with one `Bash|PowerShell` matcher running the three ported hooks; (b) delete MCP git matchers (`:48-72`); (c) delete `TeammateIdle` block (`:114-123`); (d) wire `hooks/read-size-gate.sh` on PreToolUse `Read`; (e) `permissions.defaultMode` → `"auto"`, drop `Bash(*)` and `WebFetch(*)`, add `Bash(bash hooks/run-gate.sh*)`, keep `deny: Read(.env*)`.
- PO git I/O stays native Bash (no hardening of `enforce-delegation.sh`); `AGENT_TEAM.md:37-53` tool taxonomy rewritten: "agents without Bash return work; PO commits via git CLI".
- Agent frontmatter: delete `if: "Bash(git *)"`/`"Bash(gh *)"` blocks in `coder.md` ×6, `*-coder.md` ×5, `tester.md` ×6, `test-writer.md` ×6, `user-level-reference/agents/{coder,tester,test-writer}.md`; in 11 coders change gate matcher to `"Bash|mcp__MCP_DOCKER__merge_pull_request|mcp__github-tools__github_pr_auto_merge"` (verify `:421-428` still greps `gate-before-merge`). Drop 34 `mcp__git-tools__*` from `tools:`; keep `mcp__MCP_DOCKER__update_pull_request` (verify `:203-208`).
- Prose: `templates/*/CLAUDE.local.md` "Git Operations (MCP) — HARD REQUIREMENT" (general `:27-56`) → "Git Operations (native CLI)"; `templates/*/CLAUDE.md` Commit Workflow (`:144-155`, `git_diff(staged=true)` → `git diff --cached`); `AGENT_TEAM.md` `:37-58`, `:374,395,444,462`, Rule 5 `:648`, `:673`; `user-level-reference/settings.json:48-63`; `user-level-reference/.mcp.json.template` (git-tools → optional); `scripts/check-activation.sh:50,63`; `README.md:24`; `docs/architecture.md`; `docs/hook-enforcement-ideas.md` §1/§5 superseded; `mcp-servers/HOWTO.md`.
- Optional hardening: `enforce-delegation.sh:64-74` main-thread deny gains `git (commit|push|merge)` so "PO never commits" is mechanical.
- New `scripts/test-hooks.sh`: JSON stdin fixtures (see Verification). Kill switch `.claude/git-guard-off`.

### PR2 — subagents-only + retro ledger (decisions 1, 9)
- `hooks/require-teammate-report.sh` → no-op stub keeping the `liveness.log` literal (or rewrite verify `:303-327`). (settings.json block already removed in PR1.)
- `templates/general/AGENT_TEAM.md` → cp ×5: delete `:249-261` Agent Naming Convention; `:599-624` Communication Protocol → "subagent final message / background task notification"; `:670-677` stall runbook → Agent-tool completions (drop `TaskStop`, `git_status`); `:711-740` snippets `SendMessage to main` → "final message must contain…"; `:873` plan template keeps `Team:` field (`tier-before-coder.sh:70-85` greps it), example → subagent types; `:402-428` worktrees → `isolation: worktree`; `:705` Explore row → "custom Explore (haiku)".
- All 61 agent files `## Liveness & Scope` (general coder `:70-74`): SendMessage ping → final-message contract; keep header + `Scope abort:` literals; rename `Team-mode reporting` literal in files. Rewrite verify `:237-257` to **compute counts by glob** (`find templates user-level-reference -path '*/agents/*.md' | wc -l`) instead of hard-coded 42/61.
- `templates/*/CLAUDE.md` Compact Instructions "Team configuration" line (general `:167`, dotnet `:198`, maui `:199`) → delete.
- `user-level-reference/settings.json:4` drop `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; `settings-reference.md`; `scripts/check-activation.sh:45-46,62`; `docs/architecture.md:139`; `docs/templates.md:22`; `docs/template-sync.md:85,97`.
- Retro: new `hooks/retro-ledger.sh` (SubagentStop, no matcher, always exit 0): scan `agent_transcript_path` (documented stdin field) for `tool_result` `is_error:true` matching `No such tool available|BLOCKED:|DELEGATE:|CONTRACT VIOLATION`; append `date | agent_type | agent_id | dead=[tools] | blocks=[hooks]` to **`~/.claude/projects/<proj>/memory/retro.md`** (auto-memory dir — already PO-writable per `enforce-delegation.sh:139-148`, not tracked, no diff churn). New `hooks/retro-brief.sh` (SessionStart) prints last 10 lines as context. CLAUDE.md Session Bootstrap (`:5-13`) +1 step "act on retro brief: fix allowlist/prompt causes or delegate". Add a one-line note to user-level CLAUDE.md: MEMORY.md is capped at 200 lines / 25 KB (InvestmentAdvisor's is 190 lines / 29 KB — over). **Confirm exact `is_error` wording against a real transcript before shipping.**

### PR3 — agents: models, effort, Explore, allowlists, native context hooks (decisions 3, 4)
- New `templates/*/.claude/agents/Explore.md` ×6 + `user-level-reference/agents/Explore.md` (61→**68** agent files): `name: Explore`, `model: haiku`, `effort: low`, `tools: Read, Grep, Glob, Bash`, no hooks (verify `:355-364`); body = breadth contract (quick/medium/very thorough), ≤500-line reads, output ranked `path:line — why`, no edits; include `## Liveness & Scope` + `Scope abort:` so glob-based counts stay uniform. Docs (sub-agents, v2.1.198 note) confirm a project/user agent named `Explore` overrides the built-in and keeps its own `model`.
- `AGENT_TEAM.md` / user-level settings guidance (≤8 lines): `effortLevel: medium` session default; `advisorModel: opus`; "wrong despite full context → bigger model; skipped files/tests → raise effort"; cc-proxy users must not route the auto-mode classifier model or `advisorModel` through the proxy (83 classifier outages).
- Frontmatter: coders `model: sonnet`, `effort: medium`, `isolation: worktree`; tester/test-writer `isolation: worktree`, `effort: medium`; architect/code-reviewer `opus`, `effort: high` (verify `:210-215` needs `^model: opus$`); requirements-engineer/ops `sonnet`/`medium`; doc-generator `haiku`/`low`. Remove `mode:` everywhere. `background:` left to the Agent call.
- `templates/{dotnet,dotnet-maui}/.claude/agents/dotnet-coder.md` `tools:` += `mcp__dotnet-tools__build_and_extract_errors`, `mcp__dotnet-tools__run_tests_summary` (body `:58-60` already advertises them).
- `hooks/read-size-gate.sh` (+ user-level copy): when remaining lines from `offset` (default 0) > 500 and no `limit` → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"file_path":…,"offset":<given|omit>,"limit":500,"pages":<given|omit>},"additionalContext":"Read capped at 500 of N lines from offset X; pass offset to continue"}}` — copy **every** field from `tool_input`, override only `limit`; fix the pre-existing offset bug (`:51-60`); delete ctx advice `:80-91`. (Wired in PR1.)
- Optional: `hooks/bash-output-guard.sh` (PostToolUse `Bash|PowerShell`, documented `updatedToolOutput`): response >12 KB → write full to `$TMPDIR/claude-bash-out/<session>-<n>.log`, output = head 4 KB + tail 4 KB + path; must match Bash's output shape. Ship only if fixture passes; one additive settings.json entry ×6 + user-level.
- `templates/*/CLAUDE.md` Workflow TL;DR: remove the `model: "haiku"` Explore snippet (custom Explore agent carries the model).
- Delete `hooks/allow-ctx-plan.sh` (only ref: toolkit's own `.claude/settings.local.json`).
- New verify §17: every `mcp__[a-z_-]+__[a-z_]+` token in an agent body must appear in that agent's `tools:` line.
- AGENT_TEAM.md / CLAUDE.md model-policy paragraph (≤6 lines): orchestrator opus/fable + `effortLevel` medium default; workers sonnet; Explore haiku; "wrong despite full context → bigger model; skipped files/tests → raise effort" (Anthropic blog 2026-07-07).

### PR4 — `.claude/rules/` + CLAUDE.md diet (decision 6)
- **Only `paths:`-scoped rules** (unconditional rules load at launch at CLAUDE.md priority — no token saving). `# Build & Test Discipline`, `# Verification`, `# Debugging`, `# Commit Workflow`, `## Working Preferences`, `# Compact Instructions` stay in CLAUDE.md, trimmed per the "would removing this cause mistakes?" test. Cut Spawn-Prompt Binding Table (`:45-60`, duplicates `AGENT_TEAM.md:691-710`, hook-enforced; verify §4 checks AGENT_TEAM only). Fix dangling `VERIFICATION_PLAYBOOK.md` reference.
- Path-scoped: dotnet `:109-136` + `:165-173` → `rules/csharp.md` `paths: ["**/*.cs","**/*.csproj","**/*.props","**/*.targets"]`; dotnet-maui same + `rules/xaml.md` `paths: ["**/*.xaml","**/*.xaml.cs"]`; rust-tauri `:132-162`,`:231-240` → `rules/rust.md` `paths: ["**/*.rs","rustfmt.toml"]`, `:242-247` → `rules/frontend.md` `paths: ["src/**/*.ts","src/**/*.tsx","**/*.css",".prettierrc"]`; java `:109-138`,`:167-177` → `rules/java.md` `paths: ["**/*.java","pom.xml","**/build.gradle*","src/main/resources/application.*"]`; python `:109-138`,`:167-178` → `rules/python.md` `paths: ["**/*.py","pyproject.toml","requirements*.txt"]`.
- CLAUDE.md keeps: title, Session Bootstrap, Workflow TL;DR, Open Brain, Superpowers header (verify §3), Quick Start, PROJECT-CUSTOM region. Emphasis: ≤1 IMPORTANT line.
- `{{FORMAT_COMMAND}}` etc. inside rules resolve via `apply_replacements` (`setup-project.sh:481`). Migration note: `/sync-template` will report CLAUDE.md CONFLICT for locally edited projects — "accept template, re-paste customs into PROJECT-CUSTOM; remove the plugin-installed context-mode block".

### PR5 — user-level: commands→skills, CLAUDE.md, settings (decisions 4, 5, 7 user halves)
- Move `user-level-reference/commands/{sprint,commit,challenge}.md` → `skills/<name>/SKILL.md` (add `name`/`description` frontmatter; `$ARGUMENTS` works; `commit` rewritten for native git; `sprint.md:36` ping text per PR2). Delete remaining 20 commands and `skills/{arch-analyze,code-review,explaining-code,fix-errors,impact-analysis,orient,refactor,security-audit}` incl. `evals/`. Keep `contribute-upstream`, `sync-template`, `mcp-usage`, `karpathy-guidelines`. Trim `mcp-usage` description (496 chars) to ~150.
- **Reference sweep (40+ files)**: every mention of a culled skill/command in `templates/*/CLAUDE.local.md` ("the `fix-errors` skill" ×6), `templates/*/CLAUDE.md` + `AGENT_TEAM.md` Superpowers/Required-Skills blocks, 11 coder + 6 code-reviewer agent bodies, `docs/{architecture,verification,templates}.md`, `README.md`, `AGENTS.md`, `user-level-reference/{README.md,settings-reference.md}`. Verify with `grep -rE 'skill-eval|skill-improve|fix-errors|arch-analyze|impact-analysis|security-audit|explaining-code|/orient|/refactor'` → 0 hits. CI `placeholder-parity.yml` checks MCP section only — safe.
- `user-level-reference/CLAUDE.md`: delete context-mode block `:71-135`; rewrite Read & Search table `:25-37` without ctx tools (Read+limit, Grep, Explore subagent, Glob); note "context-mode plugin optional — if installed, its SessionStart hook supplies its own guidance". Toolkit root `CLAUDE.md` → toolkit facts only.
- `user-level-reference/settings.json`: `permissions.defaultMode: "auto"`; add `autoMode.environment: ["$defaults", "<templated trusted-repo / prod-heuristic lines>"]`; drop `Bash(*)`, `WebFetch(*)`, `mcp__git-tools__*`; keep `effortLevel`, `advisorModel`; note the classifier model must not be routed through cc-proxy (83 outages). Recheck `scripts/verify-user-level-drift.sh`.

### PR6 — release (decision 8)
- `setup-project.{sh,ps1}` print the user-level `autoMode.environment` snippet from `{{REPO_URL}}` (pattern of legacy `.mcp.json` warning at `setup-project.sh:586-600`).
- `VERSION` → 2.0; CHANGELOG v2.0 roll-up listing no-op hooks slated for v2.1 removal (`block-bash-vcs`, `require-teammate-report`); `docs/*` sweep (architecture, templates, template-sync, verification, getting-started); README hook table.
- **Downstream migration note** (consolidated): (1) `/sync-template` — accept template for CLAUDE.md, AGENT_TEAM.md, agents, settings.json; re-paste customs into PROJECT-CUSTOM; (2) manual: delete the plugin-installed `# context-mode — MANDATORY routing rules` block from CLAUDE.md; (3) manual if settings.json was locally modified: remove the `TeammateIdle` block and the `block-bash-vcs` matcher; (4) user-level: copy `autoMode.environment` snippet, drop `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, remove `git-tools` from `~/.claude.json` if unused.

## Verification (end-to-end)
1. `bash scripts/verify-template-consistency.sh` after every PR (counts computed by glob after PR2; 68 agent files after PR3; renamed literals).
2. `bash scripts/test-hooks.sh` fixtures: `{"tool_name":"Bash","tool_input":{"command":"git push origin HEAD:main"},"cwd":…}` → exit 2; `git push origin feature/x` → 0; `git -C repo commit -m x` → runs pre-commit-test; `gh pr merge 12` without fresh `.gate/last-pass.json` → 2; Read of a 600-line file → JSON with `limit:500` and original `file_path`; Bash result 20 KB → truncated `updatedToolOutput` + log path; SubagentStop fixture with a dead-tool error → one `docs/retro.md` line, exit 0.
3. `python tools/measure-context-bloat.py --project-filter <proj> --top-n 15` before/after PR3–5; baseline always-loaded 32,538 B (general); target project CLAUDE.md ≤6 KB, always-loaded ≤20 KB.
4. `bash setup-project.sh --variant dotnet --target-dir "$SCRATCH/t"` (dry-run then real): assert `.claude/rules/*.md`, `.claude/agents/Explore.md` present, manifest lists them; `bash scripts/check-activation.sh "$SCRATCH/t"`.
5. `pytest G:/git/mcp-dev-servers/tests/test_template_sync_*.py` unchanged.
6. Per PR, run `/sync-template` in one downstream repo (penumbra or panoscribe): `new_template_files` lists rules/Explore, `deleted_template_files` empty, PROJECT-CUSTOM preserved.
7. Live smoke on a consumer repo after PR3: spawn Explore → `resolvedModel` haiku; Read large file → capped; `git push origin main` from a coder → blocked.
8. Re-mine transcripts 2 weeks after rollout (reuse `mine*.py` in scratchpad): block-bash-vcs 0, dead-tool calls ↓, Read-without-limit ↓, stall complaints 0.

## Risks / rollback
- PR1 false-positive on exotic push forms (`--all`, `--mirror`) → `.claude/git-guard-off` kill switch; settings hot-reload makes revert immediate.
- PR2 retro hook must never exit non-zero at SubagentStop.
- PR3 `updatedInput` whole-object bug could drop `offset` → fixture-tested. Explore quality change → delete file to roll back.
- PR4 CONFLICTs downstream are expected; migration note covers it.
- PR6 auto mode needs a supported plan/model; fallback documented (`/permissions` → `acceptEdits`).

## Outcome

Shipped as six PRs on `main`, 2026-08-28 / 2026-08-29.

| PR | Title | # | SHA |
|---|---|---|---|
| PR1 | gate native git/gh CLI instead of banning it; consolidated settings.json | [#52](https://github.com/dagonet/claude-code-toolkit/pull/52) | `0da3f1d` |
| PR2 | subagents-only workflow; retire agent-teams machinery; retro ledger | [#53](https://github.com/dagonet/claude-code-toolkit/pull/53) | `6b3b144` |
| PR3 | model/effort tiers, custom haiku Explore, allowlist invariant, native context hooks | [#54](https://github.com/dagonet/claude-code-toolkit/pull/54) | `dd2cd8e` |
| PR4 | path-scoped `.claude/rules/` for language conventions; CLAUDE.md diet | [#55](https://github.com/dagonet/claude-code-toolkit/pull/55) | `549453c` |
| PR5 | user-level: commands→skills cull, CLAUDE.md without context-mode, auto-mode settings | [#56](https://github.com/dagonet/claude-code-toolkit/pull/56) | `6f72a06` |
| PR6 | release v2.0 | — | this commit (branch `v2/pr6-release`) |

### Measured before / after

| | before (v1.5) | after (v2.0) |
|---|---|---|
| `hooks/*.sh` | 13 | **15** (incl. 2 no-op stubs; `lib/git-cmd.sh` is a library and does not glob in) |
| agent definitions (6 variants + `user-level-reference/`) | 61 | **68** |
| skills | 12 | **7** |
| slash commands | 23 | **0** |
| `templates/general/CLAUDE.md` | 13,892 B | **10,362 B** |
| `scripts/verify-template-consistency.sh` assertions | 131 | **174** |
| `scripts/test-hooks.sh` fixtures | 0 (script did not exist) | **133** |

Always-loaded bytes per variant (`CLAUDE.md` + `CLAUDE.local.md` + user-level `CLAUDE.md` + `PROJECT_CONTEXT.md`):

| Variant | after |
|---|---|
| general | **29,358** |
| java | 30,625 |
| python | 30,540 |
| dotnet | 32,049 |
| rust-tauri | 32,527 |
| dotnet-maui | 33,617 |

The only pre-trim baseline that was ever measured per file is `general`'s **41,167 B**, so `41,167 → 29,358 (−29%)` is the one before/after claim this plan is entitled to make; the other five variants have no baseline-era measurement and are reported as absolutes.

### Corrections to this plan

- **The `VERIFICATION_PLAYBOOK.md` "dangling reference" premise was wrong, and the fix was not applied.** The file ships in all six variants and `setup-project.sh` copies it, so the reference resolves in a generated project. Mentions of it in `README.md` and the templates were kept deliberately.
- **`setup-project.sh` takes `--target-path`, not `--target-dir`** (§Verification step 4 above uses the wrong flag).
- **`user-level-reference/hooks/` did not ship the retro hooks**, contrary to an assumption made while planning PR6 — it held only `read-size-gate.sh` and `bash-output-guard.sh`. PR6 mirrored the four fail-closed hooks plus `lib/git-cmd.sh` into it and added a glob-derived byte-identity assertion, which is what raised the assertion count from 167 to 174.
- The `## Verification` targets "project CLAUDE.md ≤ 6 KB, always-loaded ≤ 20 KB" (and PR4's revised ≤ 9 KB) were **not met**; the variants land at 10.3–11.3 KB. No further cut was invented to reach the number.
- `tools/measure-context-bloat.py` requires `PYTHONIOENCODING=utf-8` on Windows.
