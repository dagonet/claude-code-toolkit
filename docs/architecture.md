# Architecture

[Back to README](../README.md)

## Layered Configuration

Claude Code supports layered configuration: **project-level `.claude/` overrides user-level `~/.claude/`** for same-named items.

- **User-level agents** (`~/.claude/agents/`): 8 generic agents -- architect, code-reviewer, coder, doc-generator, ops, requirements-engineer, test-writer, tester.
- **Template agents** override user-level when working in that project. Generic agents in general/rust-tauri templates are identical to user-level. Dotnet/MAUI templates specialize architect, code-reviewer, requirements-engineer, and tester for their tech stack.
- **Domain-specific coders** (`dotnet-coder`, `rust-coder`, `java-coder`, `python-coder`) live at project-level only -- they have no user-level counterpart.

## AGENT_TEAM.md v2.0 -- Dual-Mode Workflow

The v2.0 workflow separates **project-specific config** (`PROJECT_CONTEXT.md`) from the **shared workflow definition** (`AGENT_TEAM.md`). AGENT_TEAM.md is identical across all six template variants -- only PROJECT_CONTEXT.md varies.

### Key Files

| File | Purpose | Varies per template? |
|------|---------|---------------------|
| `PROJECT_CONTEXT.md` | Tech stack, commands, paths, task source mode | Yes |
| `AGENT_TEAM.md` | Roles, tiers, mode table, worktrees, merge, rules | No (identical) |
| `PROJECT_STATE.md` | Sprint state tracking (github-issues mode) | No |

### Task Source Modes

Each project chooses ONE mode via the `task-source` field in `PROJECT_CONTEXT.md`:

| Mode | Task Definition | Branch Naming | Commit Convention |
|------|----------------|---------------|-------------------|
| `github-issues` | GitHub Issues with AC | `feature/issue-{number}` | `issue-{number}: description` |
| `plan-files` | `docs/plans/sprint-N-*.md` | PO specifies per task | `feat:` / `fix:` / `chore:` prefixes |

The **Mode Behavior Table** in AGENT_TEAM.md maps 12 workflow actions (task definition, architect guidance, review findings, closing tasks, etc.) to mode-specific targets.

## Tiered Sprint Model

| Tier | Scope | Agents | Testing |
|------|-------|--------|--------|
| T1 Trivial | < 10 lines, config/style | 1 coder (solo, uniform PR pipeline) | Coder runs gate (build + existing suite) |
| T2 Simple | 1-2 files, < 50 lines | coder + code-reviewer | Tests if logic changes; coder runs gate |
| T3 Standard | Multi-file, < 200 lines | coder + reviewer + tester | TDD required, >= 80% coverage |
| T4 Complex | Architectural, > 200 lines | architect + coder(s) + reviewer + tester | Full BDD/TDD, >= 80% coverage |

**Delegate-everything model:** the PO never does hands-on work at any tier — coding, reviewing, testing, builds, env setup (`ops` agent), and exploration (`Explore` agent) are all sub-agent work, enforced by `hooks/enforce-delegation.sh`. The PO's write surface is limited to orchestration files (`docs/plans/`, `PROJECT_STATE.md`, `PROJECT_CONTEXT.md`, `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`).

## Context Budget

Anthropic's [context-engineering guidance for Claude 5 generation models](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) favours progressive disclosure and mechanical enforcement over long prescriptive prompts. Measured state of this repo (general variant, 2026-07-29):

| | Baseline | v1.4 | v1.5 | Loaded |
|---|---|---|---|---|
| `templates/general/CLAUDE.md` | 17,871 | 15,281 | **13,735** | every session |
| `templates/general/CLAUDE.local.md` | 13,845 | **9,352** | 9,352 | every session |
| user-level `CLAUDE.md` | 8,505 | 8,505 | 8,505 | every session |
| `PROJECT_CONTEXT.md` | 946 | 946 | 946 | every session |
| **always-loaded total** | **41,167** | 34,084 | **32,538 (−20%)** | |
| `AGENT_TEAM.md` | 47,968 | 49,724 | 49,724 | **on demand only** |
| `VERIFICATION_PLAYBOOK.md` | 2,519 | 2,519 | 2,519 | on demand |
| skills | 11 | **12** | 12 | on trigger |

Per-variant always-loaded totals now: general 32,538 · java 35,708 · python 35,518 · dotnet 36,537 · rust-tauri 37,630 · dotnet-maui 38,315.

The largest single document in the repo is deliberately *not* in the always-loaded set. The two passes used different mechanisms:

- **v1.4 moved** — ten MCP procedures into the `mcp-usage` skill, the per-agent Open Brain tables into `AGENT_TEAM.md`. The on-demand side growing while the always-loaded side shrinks is the intended direction.
- **v1.5 deleted** — *Working Preferences* 18 bullets → 11, because five were already enforced by a hook or by the harness itself and two carried no behavioural content. Deleting prose that a mechanism enforces is safe in a way that deleting an unenforced rule is not; the section now names the enforcing hooks instead of restating their rules.

Every literal a hook greps is pinned by `scripts/verify-template-consistency.sh` (131 assertions), so a cut cannot silently disable enforcement — notably the exact `## Superpowers Skills — MUST Invoke Before Responding` header and the `superpowers:` token that checks 2 and 3 require, both of which survived the Superpowers-block reduction.

## Session Bootstrap

CLAUDE.md enforces a lightweight bootstrap sequence at the start of every session. `AGENT_TEAM.md` (~850 lines) is **not** read up front -- CLAUDE.md inlines a condensed Spawn-Prompt Binding Table so agent spawns still satisfy the `require-skills-block.sh` hook, and the PO loads the full file only when needed.

1. Assume the PO role. Load `AGENT_TEAM.md` on-demand when first spawning agents in a sprint, invoking the Plan Challenge Protocol, or answering questions about merge/escalation rules
2. Read `PROJECT_CONTEXT.md` -- load build commands and workflow config
3. Check Open Brain (`thoughts_search` / `thoughts_recent`) for project context. For synthesis-style questions on a known topic, prefer `wiki_get` first; fall back to `thoughts_search` if the response is marked stale (`stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days)
4. Present current state (from MEMORY.md) and ask what to work on. Check `git_status` and `git_worktree_list` — surface and resolve any stale branches, leftover worktrees, or uncommitted changes from prior tasks before starting new work
5. Enter plan mode for any non-trivial task (T2+)

### Agent Type Selection

Each CLAUDE.md and AGENT_TEAM.md includes a variant-specific table mapping task domains to `subagent_type`:

| Variant | Task Domain | Agent |
|---------|-------------|-------|
| General | Any code task | `coder` |
| Dotnet | .NET backend | `dotnet-coder` |
| Dotnet-MAUI | .NET backend / MAUI UI | `dotnet-coder` |
| Rust-Tauri | Rust/Tauri backend | `rust-coder` |
| Java | Java/Spring backend | `java-coder` |
| Python | Python backend | `python-coder` |
| All | Frontend / docs / other | `coder` |

## MCP Permissions & Hooks

All templates grant permissions for **all** known MCP servers (git, github, ollama, dotnet-tools, rust-tools, windows-mcp, sqlite, searxng, playwright, context7, open-brain, template-sync-tools). If a server is not registered in the active scope, the permission is a harmless no-op.

`CLAUDE.local.md` contains MCP usage rules (e.g., "prefer `cargo_build` over Bash `cargo build`"). This file is gitignored because it references machine-specific paths.

### MCP Layering

MCP servers are registered at two scopes, chosen to keep the user-level context minimal and load language-specific tooling only where it's needed:

| Scope | Where | Servers | When loaded |
|-------|-------|---------|-------------|
| **User-level** | **`~/.claude.json`** (top-level `mcpServers`) | Universal: `git-tools`, `github-tools`, `MCP_DOCKER`, `ollama-tools`, `template-sync-tools`, `searxng`, `open-brain` (+ plugins: `context7`, `playwright`, `context-mode`) | Every session, every repo |
| **Project-level** | **`<project-root>/.mcp.json`** | Language/framework: `dotnet-tools`, `rust-tools`, `windows-mcp`, `sqlite`, `godot-tools` | Only in repos that register them |

> **Path correctness (2026-07-29).** These are the only two files Claude Code reads for MCP servers. `~/.claude/.mcp.json` does **not** exist as a concept — `claude mcp add --scope user` writes `~/.claude.json`. An `mcpServers` key inside any `settings.json` is silently ignored. `<project>/.claude/.mcp.json` is an open upstream feature request, not current behaviour.
>
> **Migration (projects set up before 2026-07-29).** Earlier setup scripts wrote `<target>/.claude/.mcp.json`, which is never loaded. For `dotnet`, `dotnet-maui`, and `rust-tauri` that file was the sole registration of `dotnet-tools` / `rust-tools` / `windows-mcp`, so **those servers were never active** in affected projects. Fix by moving it to the repo root:
>
> ```bash
> git mv .claude/.mcp.json .mcp.json     # or merge into an existing root .mcp.json
> ```
>
> `scripts/check-activation.sh` reports this, and the setup scripts now warn when they find the legacy file. `enableAllProjectMcpServers` does not help — it governs auto-approval, not file discovery.

The project-level file is **generated by `setup-project.{sh,ps1}`** per variant at setup time. Variants that need `mcp-dev-servers` (dotnet, dotnet-maui, rust-tauri) accept `--mcp-dev-servers-path`; `--sqlite-db-path` is available for any variant. See `docs/templates.md` for the per-variant matrix and `mcp-servers/HOWTO.md` for server details.

The universal-permissions model still holds: `settings.json` permission entries for project-level servers are no-ops in repos that don't register them, and become active when they do — no per-project permission edits required.

### Hooks

**Hook scripts are root-tracked**: they live once at the toolkit ROOT `hooks/` — variants do NOT ship a `hooks/` directory. Setup scripts copy from the root; the sync server resolves manifest `hooks/` paths against the root; consistency §13 asserts every referenced script exists there. See `docs/template-sync.md` → "Hooks Are Root-Tracked".

All templates include hooks in `.claude/settings.json` that enforce workflow rules mechanistically:

| Hook Event | Purpose | Templates |
|------------|---------|-----------|
| **PreToolUse** on `Bash` | `hooks/block-bash-vcs.sh` — blocks a Bash command only when a sub-command's first token is exactly `git` or `gh`, enforcing MCP-only git/GitHub operations without false-positiving on names that merely contain those substrings (e.g. `npx playwright test`) | All |
| **PreToolUse** on `Edit\|Write\|NotebookEdit` + `Bash` | `hooks/enforce-delegation.sh` — main-thread (PO) discrimination via the `agent_id` stdin field (present only inside subagents): denies PO edits outside the orchestration write surface and PO build/test-runner Bash (incl. `run-gate.sh` — the PO verifies via the gate artifact). Subagent calls always pass. Deliberately fail-open with a WARN-wrapper (a 127-wrap would paralyze subagent edits when the script is missing); kill-switch `.claude/delegation-off` | All |
| **PreToolUse** on `mcp__git-tools__git_commit` | `hooks/pre-commit-test.sh` — runs the project's Test command (from `PROJECT_CONTEXT.md`) before allowing a commit; blocks on failure. No-op while `TEST_COMMAND` is an unset placeholder | All |
| **PreToolUse** on `mcp__MCP_DOCKER__merge_pull_request\|mcp__github-tools__github_pr_auto_merge` | `hooks/gate-before-merge.sh` — hard-blocks PR merge/auto-merge without a fresh, SHA-matching `.gate/last-pass.json` (written by the non-hook runner `hooks/run-gate.sh` from the `**Gate**:` command in PROJECT_CONTEXT.md; no-op while Gate is unset). Also duplicated inline in merge-owning coder agents' frontmatter | All |
| **PreToolUse** on `mcp__windows-mcp__Click\|Type` | Blocks Click/Type for test automation (use FlaUI) | dotnet-maui |
| **PostToolUse** on `Edit\|Write` | Runs build/lint check after edits for immediate feedback | dotnet, dotnet-maui, rust-tauri, python |
| **SubagentStop** | Two hooks fire: a pipeline echo nudging the PO to advance the workstream when an agent finishes, and `hooks/enforce-agent-contract.sh` — a stop-gate that exit-2 blocks a coder from ending without `## Gate Results` + `## Spec Compliance` and a reviewer from ending without findings or the literal word `clean`. A marker file bounds it to one forced continuation; a second non-compliant stop passes with a `CONTRACT-ENFORCER:` stderr signal to the PO. Deliberately fail-open when broken and **never** 127-wrapped (a missing stop-gate must not trap agents in an unstoppable loop) | All |
| **TeammateIdle** | `hooks/require-teammate-report.sh` — blocks a named teammate from going idle a second time with no report in between, and the stderr is delivered to the teammate, which turns a silent idle into a report. Append-only ledger, **one block per teammate and no session-wide cap** (v1.1 shipped `MAX_BLOCKS=3`; replayed against a real 208 MB / 10-day transcript it exhausted itself in 21 h and left ~500 further idles ungated — removing it takes coverage from 3 blocks to 41, worst day 10). `.claude/liveness-off` kill switch, fail-open, logs blocks to `.claude/liveness.log`, and **never** 127-wrapped — `TeammateIdle` has no loop guard, so a missing gate must not trap teammates | All |
| **PreToolUse** (no matcher) | `hooks/agent-budget-warn.sh` — per-`agent_id` tool-call budget: WARN once at 60, then **block on every threshold crossing** — 120, 180, 240, … Bounds the runaway single spawn (measured: median 15 calls, 35 of 150 agents over 60, 19 over 120, worst 417 — a single block does not stop a runaway). Every test is `-eq`, never `-ge`, so calls between thresholds pass and a blocked agent can still report. Named teammates DO fire this and DO carry `agent_id`. Pure-shell hot path, threshold events only in `.claude/liveness.log`; WARN-on-127 | All |
| **PreCompact** | Snapshots worktree and branch state before context compaction | All |

Additionally, all agents with Bash access (coders, testers, test-writers — 23 total) carry MCP enforcement hooks in their `.md` frontmatter as a belt-and-suspenders measure, since subagent hook inheritance from `settings.json` is not documented.

## Repository Structure

```
claude-code-toolkit/
├── README.md
├── setup-project.ps1                      # Automated setup (Windows)
├── setup-project.sh                       # Automated setup (Linux/macOS)
├── docs/
│   ├── getting-started.md                 # Prerequisites, adoption tiers, MCP servers
│   ├── setup.md                           # Setup walkthrough (Windows + Linux/macOS)
│   ├── templates.md                       # Template details and placeholder reference
│   ├── architecture.md                    # This file
│   ├── verification.md                    # Post-setup verification checklist
│   └── template-sync.md                   # Keeping projects in sync with templates
├── templates/
│   ├── general/                           # Any project, any language
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (8 agents)
│   │   ├── CLAUDE.md
│   │   ├── CLAUDE.local.md
│   │   ├── AGENT_TEAM.md                  # v2.0 (shared across all variants)
│   │   ├── PROJECT_CONTEXT.md
│   │   ├── PROJECT_STATE.md
│   │   └── gitignore
│   ├── dotnet/                            # .NET projects
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (9 agents)
│   │   ├── .editorconfig
│   │   ├── CLAUDE.md
│   │   ├── CLAUDE.local.md
│   │   ├── AGENT_TEAM.md
│   │   ├── PROJECT_CONTEXT.md
│   │   ├── PROJECT_STATE.md
│   │   └── gitignore
│   ├── dotnet-maui/                       # .NET MAUI desktop apps
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (9 agents)
│   │   ├── .editorconfig
│   │   ├── CLAUDE.md
│   │   ├── CLAUDE.local.md
│   │   ├── AGENT_TEAM.md
│   │   ├── PROJECT_CONTEXT.md
│   │   ├── PROJECT_STATE.md
│   │   └── gitignore
│   ├── rust-tauri/                        # Rust/Tauri v2 desktop apps
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (9 agents)
│   │   ├── rustfmt.toml                   # Rust formatter config
│   │   ├── .prettierrc                    # TypeScript/CSS formatter config
│   │   ├── CLAUDE.md
│   │   ├── CLAUDE.local.md
│   │   ├── AGENT_TEAM.md
│   │   ├── PROJECT_CONTEXT.md
│   │   ├── PROJECT_STATE.md
│   │   └── gitignore
│   └── python/                            # Python projects
│       ├── .claude/
│       │   ├── settings.json
│       │   └── agents/ (9 agents)
│       ├── .editorconfig
│       ├── CLAUDE.md
│       ├── CLAUDE.local.md
│       ├── AGENT_TEAM.md
│       ├── PROJECT_CONTEXT.md
│       ├── PROJECT_STATE.md
│       └── gitignore
├── mcp-servers/
│   └── HOWTO.md                           # MCP server installation guide
└── user-level-reference/                  # ~/.claude/ reference for new machines
    ├── agents/                            # 7 generic agent definitions
    ├── commands/                          # 21 slash commands
    ├── skills/                            # 11 auto-invoked skills
    ├── .mcp.json.template                 # MCP server config template
    └── settings-reference.md              # Annotated settings reference
```
