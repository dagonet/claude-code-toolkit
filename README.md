[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/dagonet/claude-code-toolkit)

# Claude Code Toolkit

> **Bootstrap a project with a production-ready [Claude Code](https://docs.anthropic.com/en/docs/claude-code) workflow in one command.** Six template variants drop in an opinionated agent team, slash commands, auto-triggered skills, MCP permissions, and workflow-enforcement hooks — so `/build`, `/test`, `/commit`, and `/sprint` work the moment you're done.

```bash
./setup-project.sh --variant python --project-name MyApp --target-path ../my-app
# Windows: .\setup-project.ps1 -Variant python -ProjectName MyApp -TargetPath ..\my-app
```

✅ **For:** Claude Code users on Windows / macOS / Linux working in .NET, Java, Python, Rust+Tauri, .NET MAUI — or any other language (`general`).

---

## What you get

- **6 template variants** (`general`, `dotnet`, `dotnet-maui`, `rust-tauri`, `java`, `python`) with language-specific build hooks, format gates, and conventions baked in.
- **7–8 agents per variant** — architect, code-reviewer, coder, doc-generator, requirements-engineer, test-writer, tester, plus a language-specific `dotnet-coder` / `rust-coder` / `java-coder` / `python-coder` where it helps.
- **23 user-level slash commands** for the daily loop: `/build`, `/test`, `/commit`, `/sprint`, `/challenge`, `/code-review`, `/new-feature`, `/sync-template`, …
- **11 auto-triggering skills** that load themselves based on what you're doing (debugging, refactoring, exploring a new codebase, …).
- **Pre-wired MCP permissions** for git, github, dotnet, rust, ollama, sqlite, windows-mcp, searxng, open-brain, and more — registered once per scope, not per project.
- **Workflow enforcement hooks**: `Bash(git/gh *)` blocked in favor of MCP, commit-time format gates, no-push-to-main, tier-before-coder.

## 5-minute quickstart

1. **Install prerequisites:** `git`, `Node.js 18+`, and Claude Code CLI (`npm install -g @anthropic-ai/claude-code`). Variant-specific extras (.NET SDK, Rust, JDK, Python) are listed in [`docs/getting-started.md`](docs/getting-started.md).
2. **Clone:**
   ```bash
   git clone https://github.com/dagonet/claude-code-toolkit
   cd claude-code-toolkit
   ```
3. **Run the setup script** against your project directory:
   ```bash
   ./setup-project.sh --variant <variant> --project-name <name> --target-path <path>
   ```
   See [`docs/setup.md`](docs/setup.md) for per-variant flags and full examples.
4. **(Optional) Install MCP servers** for tool-accelerated workflows: [`mcp-servers/HOWTO.md`](mcp-servers/HOWTO.md).
5. **Open your project in Claude Code** and try `/sprint` or `/build`.

> Prefer to walk Claude / Cursor / Copilot through the wizard interactively? See [`AGENTS.md`](AGENTS.md).

## Variants at a glance

| Variant | Use when | Extras vs. `general` |
|---|---|---|
| `general` | Any language, no special tooling | — |
| `dotnet` | C#/.NET 8+ | `dotnet-coder`, `dotnet build` post-edit hook, `dotnet format` gate |
| `dotnet-maui` | .NET MAUI desktop | + FlaUI tester, Windows-MCP, optional SQLite |
| `rust-tauri` | Rust + Tauri v2 desktop | `rust-coder`, `cargo check` hook, `cargo fmt` + Prettier gate, Windows-MCP |
| `java` | Java + Maven/Gradle (Spring Boot default) | `java-coder`, Spotless gate |
| `python` | Python 3.11+ (pip / Poetry / uv) | `python-coder`, `ruff check` hook + `ruff format` gate |

Full comparison + project-level MCP matrix: [`docs/templates.md`](docs/templates.md).

## Documentation

| What you want to do | Where to look |
|---|---|
| Walk Claude / Cursor / Copilot through setup | [`AGENTS.md`](AGENTS.md) |
| Detailed setup walkthrough (Windows + Linux/macOS) | [`docs/setup.md`](docs/setup.md) |
| Prerequisites + adoption tiers (start small, grow into it) | [`docs/getting-started.md`](docs/getting-started.md) |
| Compare variants, see placeholders + manifest format | [`docs/templates.md`](docs/templates.md) |
| Install MCP servers | [`mcp-servers/HOWTO.md`](mcp-servers/HOWTO.md) |
| Architecture: layered config, hooks, AGENT_TEAM v2.0 | [`docs/architecture.md`](docs/architecture.md) |
| Verify your setup works | [`docs/verification.md`](docs/verification.md) |
| Keep projects in sync with the templates | [`docs/template-sync.md`](docs/template-sync.md) |
| Reference for `~/.claude/` (agents, commands, skills, settings) | [`user-level-reference/README.md`](user-level-reference/README.md) |

## Related projects

- [**mcp-dev-servers**](https://github.com/dagonet/mcp-dev-servers) — six custom MCP servers (58 tools) for git, GitHub, .NET, Rust, Ollama, and template-sync. Used by every variant.
- [**open-brain**](https://github.com/dagonet/open-brain) — persistent memory MCP server for storing decisions, insights, and context across sessions.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues: [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
