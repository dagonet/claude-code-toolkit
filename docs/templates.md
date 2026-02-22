# Template Variants

[Back to README](../README.md)

## Comparison Table

| Feature | General | .NET | .NET MAUI | Rust/Tauri | Java | Python |
|---------|---------|------|-----------|------------|------|--------|
| Language/Framework | Any | C#/.NET | .NET MAUI Desktop | Rust + TypeScript (Tauri v2) | Java (Spring Boot) | Python |
| Default Task Source | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` |
| MCP Servers (documented) | git, github, ollama | + dotnet-tools | + dotnet-tools, sqlite, windows-mcp | + rust-tools, windows-mcp | git, github, ollama | git, github, ollama |
| Agents | 7 | 8 (+dotnet-coder) | 8 (full FlaUI tester) | 8 (+rust-coder) | 8 (+java-coder) | 8 (+python-coder) |
| Code Style | No | .editorconfig | .editorconfig | rustfmt.toml + .prettierrc | .editorconfig | .editorconfig |
| Build/Test Integration | Generic | dotnet build/test | + publish, FlaUI | cargo + npm | Maven or Gradle | pytest + ruff |
| Post-Edit Build Hook | No | `dotnet build` on Edit/Write | `dotnet build` on Edit/Write | No | No | No |
| CLAUDE.md Behavior | Session Bootstrap, Debugging, Plan Challenge | + .NET Conventions | + MAUI Conventions | + Rust/Tauri Conventions, Code Style | + Java/Spring Conventions, Code Style | + Python Conventions, Code Style |
| Database Tools | No | No | SQLite MCP (optional) | No | No | SQLite MCP (optional) |
| Desktop Automation | No | No | Windows-MCP | Windows-MCP | No | No |

## What Is in a Template

Each template variant provides the following files:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Session bootstrap, debugging rules, plan challenge protocol, variant-specific conventions |
| `CLAUDE.local.md` | MCP usage rules (gitignored, contains machine-specific paths) |
| `AGENT_TEAM.md` | v2.0 dual-mode workflow (identical across all variants) |
| `PROJECT_CONTEXT.md` | Per-project config: tech stack, build/test commands, task source mode |
| `PROJECT_STATE.md` | Sprint state tracking |
| `.claude/settings.json` | Universal MCP permissions (pre-permits all known servers) |
| `.claude/agents/` | 7 generic agents + variant-specific coders |
| `gitignore` | Template for .gitignore (copied or merged by the setup script) |
| `.editorconfig` | Code style for dotnet, dotnet-maui, java, and python variants |
| `rustfmt.toml` + `.prettierrc` | Code style for rust-tauri variant only |

## Variant Details

### General

The simplest starting point, suitable for any language or framework. Ships with 7 generic agents (architect, code-reviewer, coder, doc-generator, requirements-engineer, test-writer, tester). No build hook, no code style files, no language-specific conventions in CLAUDE.md. Use this when your project does not match one of the specialized variants.

### Dotnet

Extends the general template for C#/.NET projects. Adds the `dotnet-coder` agent (8 agents total), an `.editorconfig` for code style, and .NET conventions in CLAUDE.md (implicit usings, DI patterns, null-coalescing, `dotnet format` compliance). Includes a PostToolUse build hook that runs `dotnet build --no-restore -v q` after every Edit or Write operation, catching compilation errors immediately.

### Dotnet-MAUI

Extends the dotnet template for .NET MAUI desktop applications. Adds MAUI-specific conventions in CLAUDE.md (CommunityToolkit.Maui references, XAML namespace checks). The tester agent is specialized for FlaUI desktop testing via Windows-MCP. SQLite MCP support is optional and configured through `PROJECT_CONTEXT.md` placeholders. Database-related fields (`{{DB_DIRECTORY}}`, `{{DB_FILENAME}}`, `{{DB_PATH}}`) can be left empty if the project does not use SQLite.

### Java

Adds the `java-coder` agent (8 agents total) with Maven/Gradle build discipline. Ships a Java-focused `.editorconfig` for whitespace and indent rules (the project formatter — Spotless, Checkstyle, or google-java-format — is authoritative for Java style). CLAUDE.md includes a mandatory "Code Style (MANDATORY)" section enforcing formatter compliance, plus Java/Spring-specific conventions (constructor injection, `Optional` for nullable returns, `@ComponentScan` verification). The `java-coder` agent uses Bash `mvn`/`gradle` commands directly — no Java-specific MCP tools exist yet. The setup script accepts `--build-tool` (maven or gradle, default: maven) and `--java-version` (default: 21) to auto-derive build, test, format, and lint commands.

### Python

Adds the `python-coder` agent (8 agents total) with pytest/ruff discipline. Ships a Python-focused `.editorconfig` for whitespace and indent rules. CLAUDE.md includes a mandatory "Code Style (MANDATORY)" section enforcing formatter compliance, plus Python-specific conventions (type hints, virtual environments, dependency management). The `python-coder` agent uses Bash `pytest` / `ruff` commands directly -- no Python-specific MCP tools exist yet. The setup script accepts `--package-manager` (pip, poetry, or uv, default: pip) and `--python-version` (default: 3.12) to auto-derive build, test, format, and lint commands. SQLite MCP support is optional.

### Rust-Tauri

Adds the `rust-coder` agent (8 agents total) with cargo/clippy/fmt discipline. Ships `rustfmt.toml` and `.prettierrc` for Rust and TypeScript formatting. CLAUDE.md includes a mandatory "Code Style (MANDATORY)" section enforcing formatter compliance, plus Rust/Tauri-specific conventions. The tester agent uses Windows-MCP for desktop UI testing. CLAUDE.local.md includes Rule 12 (prefer `cargo_build`/`cargo_test`/`cargo_clippy` MCP tools over Bash).

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

## Template Manifest

The setup script generates `.claude/template-manifest.json` in each target project. This file tracks:

- **Variant**: which template was applied (general, dotnet, dotnet-maui, rust-tauri, java, python)
- **Template repo path**: absolute path to the claude-code-toolkit repo on disk
- **Placeholder values**: the concrete values used during setup (for reverse-mapping by `/contribute-upstream`)
- **Per-file content hashes**: SHA-256 hash of each template-sourced file at time of copy
- **Modification status**: whether each file has been locally modified since initial setup

The manifest enables the `/sync-template` and `/contribute-upstream` skills to detect drift, auto-update unmodified files, and flag conflicts on customized files.

## Next Steps

- [Windows setup guide](setup-windows.md)
- [Linux/macOS setup guide](setup-linux-macos.md)