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
- **12 auto-triggering skills** that load themselves based on what you're doing (debugging, refactoring, exploring a new codebase, …).
- **Pre-wired MCP permissions** for git, github, dotnet, rust, ollama, sqlite, windows-mcp, searxng, open-brain, and more — registered once per scope, not per project.
- **Workflow enforcement hooks**: the git/`gh` CLI is allowed and *gated* — the hooks parse the command and stop a red-gate commit, a push to main, and an ungated merge; plus tier-before-coder, delegation enforcement (the orchestrator never edits code or runs builds), a `Read` size gate, an agent tool-call budget, and a retro ledger that records subagent failures and replays them at the next session start.

## Context engineering for Claude 5 generation models

Anthropic's [*The new rules of context engineering for Claude 5 generation models*](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) (2026-07-24) argues that newer models are hurt, not helped, by large prescriptive system prompts — Anthropic removed **over 80% of Claude Code's own system prompt** with no measurable loss on their coding evals. The guidance: unhobble the model, delete conflicting directives, disclose procedures progressively, and put tool instructions in tool descriptions rather than the prompt.

This toolkit is designed around the same idea, and the numbers are measured rather than asserted:

| Blog principle | How the toolkit applies it |
|---|---|
| **Progressive disclosure** | `AGENT_TEAM.md` is **49,724 B and is *not* read at session start** — the bootstrap loads it only when spawning a sprint, invoking the Plan Challenge Protocol, or answering merge/escalation questions. `VERIFICATION_PLAYBOOK.md` and all **12 skills** load on trigger, not up front. |
| **Mechanism over mandate** | **15 hook scripts** enforce the rules that prose used to repeat — tests before a commit, no push to main, tier-before-coder, skills-in-spawn-prompt, merge gate, delegation, subagent budget, and a retro ledger of subagent failures replayed at session start. **138 consistency assertions** keep them from drifting. Where a hook enforces a rule, the prose does not need to shout it. |
| **Tool instructions live with the tools** | MCP usage rules point at the tool catalog instead of duplicating schemas; `CLAUDE.local.md` says *when* to prefer a server, not what its parameters are. |
| **Let the model use judgement** | Tier tables are **caps, not targets** — "pick the lowest defensible tier and justify escalation, not restraint." Question-shaped turns spawn at most one agent. |

**The trim pass, measured.** The always-loaded surface went **41,167 B → 32,538 B (−20%)** on the `general` variant, across v1.4 and v1.5:

| File | Baseline | v1.4 | v1.5 |
|---|---|---|---|
| `CLAUDE.md` | 17,871 | 15,281 | **13,735** |
| `CLAUDE.local.md` | 13,845 | **9,352** | 9,352 |
| user-level `CLAUDE.md` | 8,505 | 8,505 | 8,505 |
| `PROJECT_CONTEXT.md` | 946 | 946 | 946 |
| **total** | **41,167** | 34,084 | **32,538** |

Per-variant now: general 32,538 · java 35,708 · python 35,518 · dotnet 36,537 · rust-tauri 37,630 · dotnet-maui 38,315.

**v1.4 relocated rather than deleted.** Ten MCP procedures (Ollama warm-up, digesting large inputs, structured extraction, orientation, quality/security sweeps, Context7, headless batch, performance, default workflow) moved into a new **`mcp-usage` skill**; the per-agent Open Brain tables moved into `AGENT_TEAM.md`, which is already on-demand; the Superpowers block keeps its hard triggers and points at the user-level copy for the rest. The on-demand side grew accordingly — `AGENT_TEAM.md` 47,968 → 49,724 B, skills 11 → 12.

**v1.5 deleted, because a mechanism already covers it.** *Working Preferences* went from 18 bullets to 11 (3,939 → 2,393 B). Seven were dropped: five that a hook or the harness already enforces — reading before editing, running tests before commit, never pushing to main, `Read` size limits, keeping the PO out of hands-on work — and two with no behavioural content. In their place, one line naming where the enforcement lives, so the omission reads as deliberate rather than as an oversight. This is the unhobbling move: state that a mechanism exists instead of repeating the rule it enforces. The `"22% of total context"` statistic also collapsed from **7 files to 1**.

Every literal a hook greps is pinned by `scripts/verify-template-consistency.sh` (**138 assertions**), so neither cut could silently break enforcement — including the exact Superpowers header and the `superpowers:` token the checks require.

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
