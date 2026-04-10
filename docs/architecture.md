# Architecture

[Back to README](../README.md)

## Layered Configuration

Claude Code supports layered configuration: **project-level `.claude/` overrides user-level `~/.claude/`** for same-named items.

- **User-level agents** (`~/.claude/agents/`): 7 generic agents -- architect, code-reviewer, coder, doc-generator, requirements-engineer, test-writer, tester.
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
| T1 Trivial | < 10 lines, config/style | PO only | Run existing suite |
| T2 Simple | 1-2 files, < 50 lines | 1 dev, PO reviews | Tests if logic changes |
| T3 Standard | Multi-file, < 200 lines | Dev + reviewer + tester | TDD required, >= 80% coverage |
| T4 Complex | Architectural, > 200 lines | Architect + dev + reviewer + tester | Full BDD/TDD, >= 80% coverage |

## Session Bootstrap

CLAUDE.md enforces a mandatory bootstrap sequence at the start of every session:

1. Read `AGENT_TEAM.md` -- assume the PO role
2. Read `PROJECT_CONTEXT.md` -- load build commands and workflow config
3. Present current state (from MEMORY.md) and ask what to work on

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

All templates grant permissions for **all** user-level MCP servers (git, github, ollama, dotnet-tools, rust-tools, windows-mcp, sqlite, searxng, playwright, context7, open-brain). If a server is not registered at user-level (`~/.claude/.mcp.json`), the permission is a harmless no-op. Adding a new server to `~/.claude/` makes it instantly available in every project without editing any `settings.json`.

`CLAUDE.local.md` contains MCP usage rules (e.g., "prefer `cargo_build` over Bash `cargo build`"). This file is gitignored because it references machine-specific paths.

### Hooks

All templates include hooks in `.claude/settings.json` that enforce workflow rules mechanistically:

| Hook Event | Purpose | Templates |
|------------|---------|-----------|
| **PreToolUse** on `Bash` | Blocks `Bash(git *)` and `Bash(gh *)` — enforces MCP-only git/GitHub operations | All |
| **PreToolUse** on `mcp__git-tools__git_commit` | Blocks commits if formatter detects violations | dotnet, dotnet-maui, rust-tauri, java, python |
| **PreToolUse** on `mcp__windows-mcp__Click\|Type` | Blocks Click/Type for test automation (use FlaUI) | dotnet-maui |
| **PostToolUse** on `Edit\|Write` | Runs build/lint check after edits for immediate feedback | dotnet, dotnet-maui, rust-tauri, python |
| **SubagentStop** | Nudges PO to advance workstream pipeline when agents finish | All |
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
│   ├── setup-windows.md                   # Windows setup walkthrough
│   ├── setup-linux-macos.md               # Linux/macOS setup walkthrough
│   ├── templates.md                       # Template details and placeholder reference
│   ├── architecture.md                    # This file
│   ├── verification.md                    # Post-setup verification checklist
│   └── template-sync.md                   # Keeping projects in sync with templates
├── templates/
│   ├── general/                           # Any project, any language
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (7 agents)
│   │   ├── CLAUDE.md
│   │   ├── CLAUDE.local.md
│   │   ├── AGENT_TEAM.md                  # v2.0 (shared across all variants)
│   │   ├── PROJECT_CONTEXT.md
│   │   ├── PROJECT_STATE.md
│   │   └── gitignore
│   ├── dotnet/                            # .NET projects
│   │   ├── .claude/
│   │   │   ├── settings.json
│   │   │   └── agents/ (8 agents)
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
│   │   │   └── agents/ (8 agents)
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
│   │   │   └── agents/ (8 agents)
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
│       │   └── agents/ (8 agents)
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
    ├── skills/                            # 10 auto-invoked skills
    ├── .mcp.json.template                 # MCP server config template
    └── settings-reference.md              # Annotated settings reference
```
