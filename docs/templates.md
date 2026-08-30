# Template Variants

[Back to README](../README.md)

## Comparison Table

| Feature | General | .NET | .NET MAUI | Rust/Tauri | Java | Python |
|---------|---------|------|-----------|------------|------|--------|
| Language/Framework | Any | C#/.NET | .NET MAUI Desktop | Rust + TypeScript (Tauri v2) | Java (Spring Boot) | Python |
| Default Task Source | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` |
| User-level MCP (universal) | git, github, ollama, template-sync, searxng, open-brain (+ plugins) | same | same | same | same | same |
| Project-level MCP (auto-generated) | none (unless `--sqlite-db-path`) | `dotnet-tools` | `dotnet-tools`, `windows-mcp` | `rust-tools`, `windows-mcp` | none (unless `--sqlite-db-path`) | none (unless `--sqlite-db-path`) |
| Agents | 9 | 10 (+dotnet-coder) | 10 (+dotnet-coder, full FlaUI tester) | 10 (+rust-coder) | 10 (+java-coder) | 10 (+python-coder) |
| Code Style | No | .editorconfig | .editorconfig | rustfmt.toml + .prettierrc | .editorconfig | .editorconfig |
| Build/Test Integration | Generic | dotnet build/test | + publish, FlaUI | cargo + npm | Maven or Gradle | pytest + ruff |
| Post-Edit Build Hook | No | `dotnet build` on Edit/Write | `dotnet build` on Edit/Write | `cargo check` on Edit/Write | No | `ruff check` on Edit/Write |
| Pre-Commit Format Gate | No | `dotnet format --verify-no-changes` | `dotnet format --verify-no-changes` | `cargo fmt --check` + `npm format --check` | `spotless:check` (Maven/Gradle) | `ruff format --check` + `ruff check` |
| MCP Enforcement Hook | `Bash(git/gh *)` blocked | `Bash(git/gh *)` blocked | `Bash(git/gh *)` blocked | `Bash(git/gh *)` blocked | `Bash(git/gh *)` blocked | `Bash(git/gh *)` blocked |
| Workflow Enforcement | No push to main + skills-in-spawn-prompt | No push to main + skills-in-spawn-prompt | No push to main + skills-in-spawn-prompt | No push to main + skills-in-spawn-prompt | No push to main + skills-in-spawn-prompt | No push to main + skills-in-spawn-prompt |
| Pipeline Hook | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge |
| Delegation Enforcement | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds |
| Agent Liveness | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget |
| CLAUDE.md Behavior | Session Bootstrap, Debugging, Task Brief — identical across variants; language conventions live in `.claude/rules/` | same | same | same | same | same |
| Path-scoped rules (`.claude/rules/`) | none | `csharp.md` | `csharp.md`, `xaml.md` | `rust.md`, `frontend.md` | `java.md` | `python.md` |
| Database Tools | No | No | SQLite MCP (optional) | No | No | SQLite MCP (optional) |
| Desktop Automation | No | No | Windows-MCP | Windows-MCP | No | No |

## What Is in a Template

Each template variant provides the following files:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Session bootstrap, workflow TL;DR, verification/debugging/commit rules. **Facts only** — anything that applies to a subset of files belongs in `.claude/rules/` |
| `.claude/rules/` | Path-scoped language conventions (v2.0 PR4). Each `*.md` carries a `paths:` frontmatter glob list and loads **only** when Claude reads or edits a matching file, and is re-injected after compaction. A rule without `paths:` loads at launch at CLAUDE.md cost, so the toolkit ships only scoped rules. `general` ships none (no language of its own); `dotnet` → `csharp.md`, `dotnet-maui` → `csharp.md` + `xaml.md`, `rust-tauri` → `rust.md` + `frontend.md`, `java` → `java.md`, `python` → `python.md` |
| `CLAUDE.local.md` | MCP usage rules (gitignored, contains machine-specific paths) |
| `AGENT_TEAM.md` | v2.0 dual-mode workflow (identical across all variants) |
| `PROJECT_CONTEXT.md` | Per-project config: tech stack, build/test commands, task source mode |
| `PROJECT_STATE.md` | Sprint state tracking |
| `.claude/settings.json` | MCP permissions + workflow hooks (MCP enforcement, format gates, pipeline, compaction) |
| `.claude/agents/` | 9 generic agents (incl. the custom `Explore`, which overrides the built-in one and pins it to haiku) + variant-specific coders |
| `hooks/` | Workflow enforcement scripts, tracked once at the toolkit ROOT and shared across all variants (variants do **not** ship a `hooks/` directory): `no-push-main`, `pre-commit-test`, `read-size-gate`, `require-skills-block`, `run-gate` + `gate-before-merge`, `enforce-agent-contract`, `enforce-delegation`, `agent-budget-warn`, `retro-ledger` + `retro-brief`, `bash-output-guard`, plus the shared parser `lib/git-cmd.sh`. The two DEPRECATED v2.0 no-op stubs were deleted in v2.1, as announced; `allow-ctx-plan` was deleted in v2.0 PR3 with the context-mode routing rules |
| `gitignore` | Template for .gitignore (copied or merged by the setup script) |
| `.editorconfig` | Code style for dotnet, dotnet-maui, java, and python variants |
| `rustfmt.toml` + `.prettierrc` | Code style for rust-tauri variant only |

## Variant Details

### General

The simplest starting point, suitable for any language or framework. Ships with 9 generic agents (Explore, architect, code-reviewer, coder, doc-generator, ops, requirements-engineer, test-writer, tester). No build hook or code style files, but includes the three git gates on `Bash|PowerShell` (tests before a commit, no push to main, no ungated merge), the `Read` cap, SubagentStop pipeline hooks, delegation enforcement, the agent tool-call budget, and PreCompact state snapshots. No language-specific conventions in CLAUDE.md. Use this when your project does not match one of the specialized variants.

### Dotnet

Extends the general template for C#/.NET projects. Adds the `dotnet-coder` agent (10 agents total), an `.editorconfig` for code style, and .NET conventions in `.claude/rules/csharp.md` (implicit usings, DI patterns, null-coalescing, `dotnet format` compliance) scoped to `**/*.cs`, `**/*.csproj`, `**/*.props`, `**/*.targets`, and `.editorconfig`. Includes a PostToolUse build hook that runs `dotnet build --no-restore -v q` after every Edit or Write operation, catching compilation errors immediately. A PreToolUse format gate blocks commits if `dotnet format --verify-no-changes` detects violations.

### Dotnet-MAUI

Extends the dotnet template for .NET MAUI desktop applications. Adds MAUI-specific conventions in `.claude/rules/xaml.md` (CommunityToolkit.Maui references, XAML namespace checks), scoped to `**/*.xaml` and `**/*.xaml.cs`, alongside the shared `csharp.md`. The tester agent is specialized for FlaUI desktop testing via Windows-MCP. A PreToolUse hook blocks Windows-MCP `Click`/`Type` tools (forbidden for test automation per CLAUDE.local.md -- use FlaUI for structural verification). SQLite MCP support is optional and configured through `PROJECT_CONTEXT.md` placeholders. Database-related fields (`{{DB_DIRECTORY}}`, `{{DB_FILENAME}}`, `{{DB_PATH}}`) can be left empty if the project does not use SQLite.

### Java

Adds the `java-coder` agent (10 agents total) with Maven/Gradle build discipline. Ships a Java-focused `.editorconfig` for whitespace and indent rules (the project formatter — Spotless, Checkstyle, or google-java-format — is authoritative for Java style). `.claude/rules/java.md` carries the "Code Style (MANDATORY)" block plus Java/Spring conventions (constructor injection, `Optional` for nullable returns, `@ComponentScan` verification), scoped to `**/*.java`, `pom.xml`, `**/build.gradle*`, and `src/main/resources/application.*`. The `java-coder` agent uses Bash `mvn`/`gradle` commands directly — no Java-specific MCP tools exist yet. A PreToolUse format gate auto-detects Maven vs Gradle and blocks commits if `spotless:check` / `spotlessCheck` fails. The setup script accepts `--build-tool` (maven or gradle, default: maven) and `--java-version` (default: 21) to auto-derive build, test, format, and lint commands.

### Python

Adds the `python-coder` agent (10 agents total) with pytest/ruff discipline. Ships a Python-focused `.editorconfig` for whitespace and indent rules. `.claude/rules/python.md` carries the "Code Style (MANDATORY)" block plus Python conventions (type hints, `pathlib`, `logging` over `print`), scoped to `**/*.py`, `pyproject.toml`, `requirements*.txt`, and `ruff.toml`. The `python-coder` agent uses Bash `pytest` / `ruff` commands directly -- no Python-specific MCP tools exist yet. Includes a PostToolUse hook running `ruff check` after edits (sub-second overhead) and a PreToolUse format gate blocking commits unless both `ruff format --check` and `ruff check` pass. The setup script accepts `--package-manager` (pip, poetry, or uv, default: pip) and `--python-version` (default: 3.12) to auto-derive build, test, format, and lint commands. SQLite MCP support is optional.

### Rust-Tauri

Adds the `rust-coder` agent (10 agents total) with cargo/clippy/fmt discipline. Ships `rustfmt.toml` and `.prettierrc` for Rust and TypeScript formatting. `.claude/rules/rust.md` (scoped to `**/*.rs`, `rustfmt.toml`, `Cargo.toml`) and `.claude/rules/frontend.md` (scoped to `src/**/*.ts`, `src/**/*.tsx`, `**/*.css`, `.prettierrc`) carry the "Code Style (MANDATORY)" blocks plus the backend/frontend conventions. The tester agent uses Windows-MCP for desktop UI testing. CLAUDE.local.md includes Rule 12 (prefer `cargo_build`/`cargo_test`/`cargo_clippy` MCP tools over Bash). Includes a PostToolUse hook running `cargo check` after edits and a PreToolUse format gate requiring both `cargo fmt --check` and `npm run format --check` to pass before commits.

## Project-Level MCP Matrix

The setup script generates `<project-root>/.mcp.json` per variant at setup time, based on the variant and optional CLI flags. Language/framework MCP servers are **not** registered at user level — they only load in repos that explicitly need them.

| Variant | Always generated | Optional (via flag) | Required flag |
|---|---|---|---|
| general | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |
| dotnet | `dotnet-tools` | `sqlite` | `--mcp-dev-servers-path` |
| dotnet-maui | `dotnet-tools`, `windows-mcp` | `sqlite` | `--mcp-dev-servers-path` |
| rust-tauri | `rust-tools`, `windows-mcp` | `sqlite` | `--mcp-dev-servers-path` |
| java | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |
| python | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |

**Flag notes:**

- `--mcp-dev-servers-path <path>` — points at a local clone of [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers). Required for variants that register `dotnet-tools` or `rust-tools`. If omitted, the setup script prints a warning and skips the affected entries (no default).
- `--sqlite-db-path <path>` — optional for any variant. Accepts absolute or relative (resolved against caller CWD).
- `windows-mcp` is hard-coded to `uvx windows-mcp` — assumes `uvx` is on PATH.
- If no entries would be written for a variant, `.mcp.json` is not created.

See `docs/architecture.md` → MCP Layering and `mcp-servers/HOWTO.md` → Project-Level Servers for rationale and per-server details.

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{PROJECT_NAME}}` | Project name | MyProject |
| `{{PROJECT_NAME_LOWER}}` | Lowercase project name | myproject |
| `{{REPO_URL}}` | GitHub repository URL | https://github.com/user/myproject |
| `{{SOLUTION_FILE}}` | Main build file path (.NET) | MyProject.sln |
| `{{BUILD_COMMAND}}` | Build command | dotnet build MyProject.sln |
| `{{RUN_COMMAND}}` | Run command | dotnet run --project src/MyProject |
| `{{TEST_COMMAND}}` | Test command | dotnet test |
| `{{FORMAT_COMMAND}}` | Format command | dotnet format |
| `{{LINT_COMMAND}}` | Lint command | dotnet format --verify-no-changes |
| `{{GATE_COMMAND}}` | Gate command (`hooks/run-gate.sh` runs it) | dotnet format --verify-no-changes && dotnet test |
| `{{DB_DIRECTORY}}` | Database directory (MAUI) | c:\Users\...\Data |
| `{{DB_FILENAME}}` | Database filename (MAUI) | myproject.db |
| `{{DB_PATH}}` | Full database path (MAUI) | c:\Users\...\Data\myproject.db |
| `{{JAVA_VERSION}}` | Java version (Java) | 21 |
| `{{PYTHON_VERSION}}` | Python version (Python) | 3.12 |
| `{{LOG_PATH}}` | Log file location | c:\Users\...\Logs\ |
| `{{WORKTREE_BASE}}` | Git worktree base | g:/git/.worktrees |
| `{{TECH_STACK}}` | Technology stack description | .NET 10, MAUI, SQLite |
| `{{MAUI_PROJECT}}` | MAUI project path (MAUI) | src/MyApp.MAUI |
| `{{TEST_PROJECT}}` | Test project path | tests/MyApp.Tests |

## Template Manifest (v2)

The setup script generates `.claude/template-manifest.json` in each target project. The v2 format tracks:

- **Version**: schema version (`2`)
- **Variant**: which template was applied (general, dotnet, dotnet-maui, rust-tauri, java, python)
- **Template repo path**: absolute path to the claude-code-toolkit repo on disk
- **Last synced commit**: git commit hash at time of setup/sync
- **Placeholder values**: the concrete values used during setup (for reverse-mapping by `/contribute-upstream`)
- **Per-file hashes**: `templateHash` (after placeholder replacement), `templateRawHash` (before replacement), `localHash` (project file at last sync)
- **Modification status**: whether each file has been locally modified since initial setup

The `templateRawHash` detects template changes without recomputing placeholder replacement. The `localHash` serves as the common ancestor for three-way merge during conflict resolution.

The manifest is consumed by the **template-sync-tools** MCP server, which powers the `/sync-template` and `/contribute-upstream` skills. See [`template-sync.md`](template-sync.md) for the full workflow.

## Next Steps

- [Setup walkthrough (Windows + Linux/macOS)](setup.md)