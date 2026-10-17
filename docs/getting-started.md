[Back to README](../README.md)

# Getting Started

The toolkit is a template repository and the Claude Code plugin `cct@dagonet`: the plugin brings the agents, skills, report style and enforcement hooks to every session on your machine, and `setup-project` copies the per-project files (instructions, workflow, rules, MCP permissions, the plugin-off guard, the pre-push hook) into your project and records them in a manifest so `/cct:sync-template` can update them later. It ships no application code. This guide covers everything you need before running the setup script — prerequisites, optional dependencies, and adoption tiers — so you can decide how much of the setup to use.

## Core Prerequisites (All Templates)

| Dependency | Min Version | Purpose |
|---|---|---|
| **Claude Code CLI** | Latest | `npm install -g @anthropic-ai/claude-code` |
| **The cct plugin** | this release | `/plugin marketplace add dagonet/claude-code-toolkit#v5.1.1`, then `/plugin install cct@dagonet`, then restart the session. **Required:** a synced project refuses every tool call until the plugin is active. Upgrading from v4.x: see [Install in the README](../README.md#install) |
| **A JSON parser for the hooks** | `node` 18+, `python3` 3.8+ or `jq` 1.6+ | The enforcement hooks parse their stdin payload with the first one they find. Native Claude Code installs do **not** ship `node`, so on those boxes make sure `python3` or `jq` is on PATH — with none of the three the git gates fail closed (exit 2) and the rest warn that enforcement is inactive. `node` unlocks the full set: `read-size-gate`, `bash-output-guard`, `enforce-delegation`, `enforce-agent-contract` and the retro hooks are node-only. |
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

All templates pre-permit the full set of MCP servers in `settings.json`. Servers are registered at **two scopes** (see `docs/architecture.md` → MCP Layering):

- **User-level** (`~/.claude.json`, top-level `mcpServers` — or just `claude mcp add --scope user`): universal tools loaded in every session.
- **Project-level** (`<project-root>/.mcp.json`): language/framework tools loaded only in repos that register them. Generated per-variant by `setup-project.{sh,ps1}` — see `docs/templates.md` for the matrix.

> These are the only two locations Claude Code reads. `~/.claude/.mcp.json` is not a thing, `<project>/.claude/.mcp.json` is not read either, and an `mcpServers` key inside `settings.json` is silently ignored. See `docs/architecture.md` → *MCP Layering*.

If a server is not registered in the active scope, the permission is a harmless no-op.

### User-Level Servers

Registered once in `~/.claude.json`; universally useful across projects.

#### Custom Python servers from [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers)

Private repo — new users must fork/clone it, or remove references and rely on Bash fallbacks.

| Server | Tools | Requires |
|---|---|---|
| **git-tools** | 34 git operations | Python 3.11+, GitPython — **optional**: nothing in the toolkit requires it, and git work routed through it bypasses the three git gates, which key on `Bash`/`PowerShell` commands |
| **github-tools** | 17 (releases, workflows, PR hygiene) | Python 3.11+, `gh` CLI |
| **python-tools** | 7 (wheel/sdist inspect, pytest, ruff, uv build, coverage) | Python 3.11+, `uv`, `pytest`, `ruff`, `coverage` |
| **ollama-tools** | 6 (local LLM, project mapping) | Python 3.11+, Ollama |

#### `template-sync-tools` (ships with this toolkit, not `mcp-dev-servers`)

This server lives in `server/` in **this** repo — it is not part of the `mcp-dev-servers` clone above, so it needs no fork/clone of that private repo and no `--mcp-dev-servers-path`.

| Server | Tools | Installed by | Requires |
|---|---|---|---|
| **template-sync-tools** | 10 (manifest load/migrate, status, diff, apply, finalize, verify, placeholders, cross-variant) | `bash server/install.sh` (Linux/macOS) or `server\install.ps1` (Windows), run from a `claude-code-toolkit` checkout | Python 3.11+, Git |

The install script creates `server/.venv` and prints the console-script exe path. `setup-project.{sh,ps1}` prints a `template-sync-tools` snippet for `~/.claude.json` and does not write it; add the entry to `~/.claude.json` yourself, pointing it at the printed path. See [`mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) → *Template Sync Tools* for the full install / re-register / restart migration, including moving off an older `mcp-dev-servers`-hosted registration.

#### Official / third-party user-level servers

| Server | Source | Required? |
|---|---|---|
| **GitHub (official plugin)** | `@claude-plugins-official` → hosted at `api.githubcopilot.com/mcp` | Strongly recommended (40+ tools). Requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var. |
| **Context7** | Claude Code plugin | Optional (library doc lookup) |
| **Playwright** | Claude Code plugin | Optional (browser automation) |
| **Context Mode** | Claude Code plugin | Optional (context window optimization) |
| **SearXNG** | Self-hosted | Optional (privacy-focused search) |
| **Open Brain** | Third-party | Optional (persistent memory) |

### Project-Level Servers

Registered in `<project-root>/.mcp.json`, generated by the setup script per variant. Only load in repos that actually need them.

| Server | Used by variants | Tools | Requires |
|---|---|---|---|
| **dotnet-tools** | dotnet, dotnet-maui | 19 (.NET build/test/NuGet/EF) | Python 3.11+, .NET SDK, `--mcp-dev-servers-path` |
| **rust-tools** | rust-tauri | 4 (cargo build/test/clippy) | Python 3.11+, Rust toolchain, `--mcp-dev-servers-path` |
| **windows-mcp** | dotnet-maui, rust-tauri | desktop automation | `uvx` on PATH (auto-installs `windows-mcp` package) |
| **sqlite** | any (opt-in) | DB inspection | `--sqlite-db-path` flag at setup time |
| **godot-tools** | any (opt-in) | Godot 4.x integration | Node.js, Godot 4.x |

### Without MCP Servers

Agents have **Bash fallbacks** for the build-tool servers: `cct:dotnet-coder` falls back to `dotnet build` / `dotnet test`, `cct:rust-coder` to `cargo build` / `cargo test`; `cct:java-coder` and `cct:python-coder` use Bash `mvn` / `gradle` and `pytest` / `ruff` directly by design (the templates register no Java or Python MCP tools). Git and `gh` are native CLI calls in every variant — the hooks parse and gate them, so no git MCP server is involved — and the build/test gate is `cct-gate`, which needs no MCP server at all. Unregistered servers produce harmless permission warnings in `settings.json`.

See [MCP Server Installation Guide](../mcp-servers/HOWTO.md) for detailed setup instructions.

## Superpowers Skills (Plugin Dependency)

The repo references the `superpowers:*` skills (brainstorming, TDD, debugging, etc.). These are a **separate Claude Code plugin** installed at user-level. New users must either install the superpowers plugin or remove `superpowers:` skill references from agents and CLAUDE.md files.

## Adoption Tiers

You do not need everything installed to get value. Pick the tier that matches your needs.

### Tier 1 -- Bare Minimum

1. Install Claude Code CLI, Git, and one JSON parser for the hooks (`node`, `python3` or `jq` — `node` covers all of them)
2. Install the cct plugin (`/plugin marketplace add dagonet/claude-code-toolkit#v5.1.1`, then `/plugin install cct@dagonet`) and restart the session
3. Clone this repo and run the setup script targeting your project:
   - **Windows**: `setup-project.ps1`
   - **Linux/macOS**: `setup-project.sh`
4. Ignore MCP permission warnings in `settings.json`

This gives you the full agent team, workflow, and session bootstrap -- just without MCP tool acceleration.

> **Adopting `user-level-reference/settings.json`: merge, do not overwrite.** Your own
> `~/.claude/settings.json` carries personal keys the reference does not know about
> (`advisorModel`, `autoCompact*`, `contextCompactionThreshold`, `statusLine`, your model
> pins). Copy in only the `permissions.deny` entries, keeping everything else: a short Python
> script that loads both files as JSON, unions `permissions.deny` and writes your file back.
> The hooks, agents and skills are not copied by hand: they come from the cct plugin (step 2 above).

### Tier 2 -- Recommended

Everything in Tier 1, plus:

5. Install GitHub CLI and authenticate (`gh auth login`)
6. Enable the official **github** plugin at user-level and set `GITHUB_PERSONAL_ACCESS_TOKEN`
7. Install the language SDK for your chosen template (.NET / Rust / Java / Python)

This adds GitHub integration and language-specific build/test support.

### Tier 3 -- Full Experience

Everything in Tier 2, plus:

8. Install the toolkit's own `template-sync-tools` server, once per `claude-code-toolkit` checkout: `bash server/install.sh` (Linux/macOS) or `server\install.ps1` (Windows) — see *`template-sync-tools` (ships with this toolkit, not `mcp-dev-servers`)* above for registration details
9. Clone [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers) and pass its path to setup via `--mcp-dev-servers-path` for dotnet/dotnet-maui/rust-tauri variants (generates project-level `dotnet-tools` / `rust-tools`)
10. Install Ollama + models for local LLM processing
11. Install the superpowers plugin
12. Install `uvx` (for windows-mcp auto-config on dotnet-maui/rust-tauri), Open Brain, SearXNG as desired

This unlocks every MCP tool, skill, and automation the templates reference.

## Next Steps

Once you have the prerequisites for your chosen tier, proceed to the setup guide for your platform:

- [Setup walkthrough (Windows + Linux/macOS)](setup.md)
- **Comparing templates**: [templates.md](templates.md)
