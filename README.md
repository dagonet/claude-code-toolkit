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
- **8–9 agents per variant** — architect, code-reviewer, coder, doc-generator, ops, requirements-engineer, test-writer, tester, plus a language-specific `dotnet-coder` / `rust-coder` / `java-coder` / `python-coder` where it helps.
- **23 user-level slash commands** for the daily loop: `/build`, `/test`, `/commit`, `/sprint`, `/challenge`, `/code-review`, `/new-feature`, `/sync-template`, …
- **11 auto-triggering skills** that load themselves based on what you're doing (debugging, refactoring, exploring a new codebase, …).
- **Pre-wired MCP permissions** for git, github, dotnet, rust, ollama, sqlite, windows-mcp, searxng, open-brain, and more — registered once per scope, not per project.
- **Workflow enforcement hooks**: `Bash(git/gh *)` blocked in favor of MCP, commit-time format gates, no-push-to-main, tier-before-coder, delegation enforcement (the orchestrator never edits code or runs builds), and agent liveness (a teammate cannot idle twice without reporting; a single agent spawn cannot run away unbounded).

## Context engineering for Claude 5 generation models

Anthropic's [*The new rules of context engineering for Claude 5 generation models*](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) (2026-07-24) argues that newer models are hurt, not helped, by large prescriptive system prompts — Anthropic removed **over 80% of Claude Code's own system prompt** with no measurable loss on their coding evals. The guidance: unhobble the model, delete conflicting directives, disclose procedures progressively, and put tool instructions in tool descriptions rather than the prompt.

This toolkit is designed around the same idea, and the numbers are measured rather than asserted:

| Blog principle | How the toolkit applies it |
|---|---|
| **Progressive disclosure** | `AGENT_TEAM.md` is **47,968 B / 930 lines and is *not* read at session start** — the bootstrap loads it only when spawning a sprint, invoking the Plan Challenge Protocol, or answering merge/escalation questions. `VERIFICATION_PLAYBOOK.md` and all **11 skills** load on trigger, not up front. |
| **Mechanism over mandate** | **13 hook scripts** enforce the rules that prose used to repeat — MCP-only git, no push to main, tier-before-coder, skills-in-spawn-prompt, merge gate, delegation, agent liveness. **129 consistency assertions** keep them from drifting. Where a hook enforces a rule, the prose does not need to shout it. |
| **Tool instructions live with the tools** | MCP usage rules point at the tool catalog instead of duplicating schemas; `CLAUDE.local.md` says *when* to prefer a server, not what its parameters are. |
| **Let the model use judgement** | Tier tables are **caps, not targets** — "pick the lowest defensible tier and justify escalation, not restraint." Question-shaped turns spawn at most one agent. |

**What is not done yet — stated plainly.** The always-loaded surface is still **~41 KB across 4 files** (`CLAUDE.md` 17.9 KB, `CLAUDE.local.md` 13.8 KB, user-level `CLAUDE.md` 8.5 KB, `PROJECT_CONTEXT.md` 0.9 KB), at a measured **11–14 directives per 100 lines**, with known duplication across layers (the Superpowers block, the Read-discipline statistic, the spawn-prompt table, the Open Brain mandates). A measured trim-and-relocate pass — moving rarely-needed MCP procedures into a skill and cutting duplication — is planned and **has not landed**. Anything that is load-bearing for a hook is pinned by `scripts/verify-template-consistency.sh` so the cut cannot silently break enforcement.

If you are adopting the toolkit and want Anthropic's own verdict on your `CLAUDE.md` and skills, run `/doctor`.

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
| Where MCP servers actually live (`~/.claude.json`, `<root>/.mcp.json`) | [`docs/architecture.md` → MCP Layering](docs/architecture.md) |
| Verify your setup works | [`docs/verification.md`](docs/verification.md) |
| Keep projects in sync with the templates | [`docs/template-sync.md`](docs/template-sync.md) |
| Reference for `~/.claude/` (agents, commands, skills, settings) | [`user-level-reference/README.md`](user-level-reference/README.md) |

## Related projects

- [**mcp-dev-servers**](https://github.com/dagonet/mcp-dev-servers) — seven custom MCP servers (95 tools) for git, GitHub, .NET, Rust, Ollama, Python, and template-sync. Used by every variant.
- [**open-brain**](https://github.com/dagonet/open-brain) — persistent memory MCP server for storing decisions, insights, and context across sessions.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues: [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
