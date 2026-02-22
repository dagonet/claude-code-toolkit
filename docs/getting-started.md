[Back to README](../README.md)

# Getting Started

Everything you need to know before running the setup script. This guide covers prerequisites, optional dependencies, and adoption tiers so you can decide how much of the setup to use.

## Core Prerequisites (All Templates)

| Dependency | Min Version | Purpose |
|---|---|---|
| **Claude Code CLI** | Latest | `npm install -g @anthropic-ai/claude-code` |
| **Node.js** | 18+ | Runtime for Claude Code |
| **Git** | Any recent | Version control |
| **GitHub CLI (`gh`)** | Latest | GitHub integration (must be authenticated via `gh auth login`) |
| **PowerShell** | 5.1+ | `setup-project.ps1` — Windows only |
| **Bash** | Any recent | `setup-project.sh` — Linux/macOS only |

> **Cross-platform note**: The setup script has two variants. Windows users run `setup-project.ps1` (PowerShell). Linux/macOS users run `setup-project.sh` (Bash). Both produce identical output.

## Template-Specific Dependencies

Choose the template that matches your project's tech stack. Each may require additional tooling beyond the core prerequisites.

| Template | Additional Dependencies |
|---|---|
| **General** | None beyond core |
| **Dotnet** | .NET SDK 8.0+ |
| **Dotnet-MAUI** | .NET SDK 8.0+ with MAUI workload, Docker Desktop (if using SQLite MCP) |
| **Rust-Tauri** | Rust toolchain via rustup (cargo, rustc, rustfmt, clippy), Tauri CLI |
| **Java** | JDK 17+ (or 21+), Maven 3.9+ or Gradle 8+ |
| **Python** | Python 3.10+, pip/poetry/uv |

## MCP Servers

All templates pre-permit 12+ MCP servers in `settings.json`. These are registered at **user-level** (`~/.claude/.mcp.json`), not shipped in templates. If a server is not registered, the permission is a harmless no-op.

### Custom Python MCP Servers (from [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers))

Private repo -- new users must fork/clone it, or remove references and rely on Bash fallbacks.

| Server | Tools | Requires |
|---|---|---|
| **git-tools** | 16 git operations | Python 3.10+, GitPython |
| **github-tools** | 2 (repo info, workflows) | Python 3.10+, `gh` CLI |
| **dotnet-tools** | 19 (.NET build/test/NuGet/EF) | Python 3.10+, .NET SDK |
| **rust-tools** | 4 (cargo build/test/clippy) | Python 3.10+, Rust toolchain |
| **ollama-tools** | 6 (local LLM, project mapping) | Python 3.10+, Ollama |

### Official/Third-Party MCP Servers

| Server | Source | Required? |
|---|---|---|
| **GitHub MCP** | `github/github-mcp-server` | Strongly recommended (40+ tools) |
| **Context7** | Claude Code plugin | Optional (library doc lookup) |
| **Playwright** | Claude Code plugin | Optional (browser automation) |
| **Windows-MCP** | Third-party | Optional (desktop automation/testing) |
| **SQLite MCP** | Docker-based | Optional (DB inspection) |
| **SearXNG** | Self-hosted | Optional (privacy-focused search) |
| **Open Brain** | Third-party | Optional (persistent memory) |
| **Godot Tools** | Node.js MCP | Optional (Godot 4.x game engine integration) |
| **Context Mode** | Claude Code plugin | Optional (context window optimization) |

### Without MCP Servers

Agents and skills have **Bash fallbacks** for most operations. `dotnet-coder` falls back to `dotnet build` / `dotnet test`, `rust-coder` falls back to `cargo build` / `cargo test`, `java-coder` uses Bash `mvn` / `gradle` commands directly (no Java MCP tools yet), `python-coder` uses Bash `pytest` / `ruff` commands directly (no Python MCP tools yet), and git operations fall back to Bash `git` commands. The `/build` and `/test` skills degrade gracefully. Unregistered servers produce harmless permission warnings in `settings.json`.

See [MCP Server Installation Guide](../mcp-servers/HOWTO.md) for detailed setup instructions.

## Superpowers Skills (Plugin Dependency)

The repo references ~20 `superpowers:*` skills (brainstorming, TDD, debugging, etc.). These are a **separate Claude Code plugin** installed at user-level. New users must either install the superpowers plugin or remove `superpowers:` skill references from agents and CLAUDE.md files.

## Adoption Tiers

You do not need everything installed to get value. Pick the tier that matches your needs.

### Tier 1 -- Bare Minimum

1. Install Claude Code CLI, Git, Node.js 18+
2. Clone this repo and run the setup script targeting your project:
   - **Windows**: `setup-project.ps1`
   - **Linux/macOS**: `setup-project.sh`
3. Ignore MCP permission warnings in `settings.json`

This gives you the full agent team, workflow, and session bootstrap -- just without MCP tool acceleration.

### Tier 2 -- Recommended

Everything in Tier 1, plus:

4. Install GitHub CLI and authenticate (`gh auth login`)
5. Register GitHub MCP server at user-level
6. Install the language SDK for your chosen template (.NET / Rust / Java / Python)

This adds GitHub integration and language-specific build/test support.

### Tier 3 -- Full Experience

Everything in Tier 2, plus:

7. Set up [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers) servers
8. Install Ollama + models for local LLM processing
9. Install the superpowers plugin
10. Set up Windows-MCP, Open Brain, SearXNG as desired

This unlocks every MCP tool, skill, and automation the templates reference.

## Next Steps

Once you have the prerequisites for your chosen tier, proceed to the setup guide for your platform:

- **Windows**: [setup-windows.md](setup-windows.md)
- **Linux/macOS**: [setup-linux-macos.md](setup-linux-macos.md)
- **Comparing templates**: [templates.md](templates.md)
