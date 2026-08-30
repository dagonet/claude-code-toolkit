[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/dagonet/claude-code-toolkit)

# Claude Code Toolkit

> **Bootstrap a project with a production-ready [Claude Code](https://docs.anthropic.com/en/docs/claude-code) workflow in one command.** Six template variants drop in an opinionated agent team, skills, MCP permissions, and workflow-enforcement hooks — so `/commit`, `/sprint`, and the `bash hooks/run-gate.sh` build/test gate work the moment you're done.

```bash
./setup-project.sh --variant python --project-name MyApp --target-path ../my-app
# Windows: .\setup-project.ps1 -Variant python -ProjectName MyApp -TargetPath ..\my-app
```

✅ **For:** Claude Code users on Windows / macOS / Linux working in .NET, Java, Python, Rust+Tauri, .NET MAUI — or any other language (`general`).

---

## What you get

- **6 template variants** (`general`, `dotnet`, `dotnet-maui`, `rust-tauri`, `java`, `python`) with language-specific build hooks, format gates, and conventions baked in.
- **9–10 agents per variant** — Explore, architect, code-reviewer, coder, doc-generator, ops, requirements-engineer, test-writer, tester, plus a language-specific `dotnet-coder` / `rust-coder` / `java-coder` / `python-coder` where it helps. Each one declares its own `model:` and `effort:`, so exploration runs on haiku and review on opus without the caller thinking about it.
- **8 user-level skills**, no slash-command directory: `/challenge`, `/commit`, `/sprint`, `/sync-template`, `/contribute-upstream`, `/retro-review`, plus `mcp-usage` and `karpathy-guidelines` which auto-trigger. Anthropic merged custom commands into skills, so the toolkit ships one artifact type; the `Gate:` mechanism (`hooks/run-gate.sh`) replaced the old `/build` and `/test` commands, and the official `skill-creator` plugin replaced `/skill-eval` + `/skill-improve`.
- **Pre-wired MCP permissions** for git, github, dotnet, rust, ollama, sqlite, windows-mcp, searxng, open-brain, and more — registered once per scope, not per project.
- **Workflow enforcement hooks**: the git/`gh` CLI is allowed and *gated* — the hooks parse the command and stop a red-gate commit, a push to main, and an ungated merge; plus skills-in-spawn-prompt, delegation enforcement (the orchestrator never edits code or runs builds), a `Read` size gate, an agent tool-call budget, and a retro ledger that records subagent failures and replays them at the next session start.

### Model & effort policy

Every agent file declares its own `model:` and `effort:`, so cost follows the job instead of the session. The **session** effort level ships unset — Opus 5 / Fable 5 pick their own default per step; raise it per role with the agent's `effort:`, or `/effort` for one session. The orchestrator model is a `/model` choice at session start: `fable` for T3/T4 (multi-file or architectural) work, `opus` for T1/T2.

| Agents | `model:` | `effort:` | Notes |
|---|---|---|---|
| `Explore` | `haiku` | `low` | Overrides the built-in `Explore`, which would otherwise inherit the session model |
| `doc-generator` | `haiku` | `low` | |
| `coder`, `*-coder`, `tester`, `test-writer` | `sonnet` | `medium` | Run with `isolation: worktree` |
| `ops`, `requirements-engineer` | `sonnet` | `medium` | |
| `architect`, `code-reviewer` | `opus` | `xhigh` | Judgement work, not throughput work |

**Aliases only** (`sonnet` / `opus` / `haiku` / `fable` / `inherit`) — a pinned `claude-*` id bypasses a model proxy, and the verify script rejects one. **Do not pass `model:` in an Agent call**: it silently overrides the agent file. The diagnostic rule, stated once in `AGENT_TEAM.md` → *Model & Effort Policy*: wrong despite full context → bigger model; skipped files or tests not run → raise effort.

## Context engineering for Claude 5 generation models

Anthropic's [*The new rules of context engineering for Claude 5 generation models*](https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models) (2026-07-24) argues that newer models are hurt, not helped, by large prescriptive system prompts — Anthropic removed **over 80% of Claude Code's own system prompt** with no measurable loss on their coding evals. The guidance: unhobble the model, delete conflicting directives, disclose procedures progressively, and put tool instructions in tool descriptions rather than the prompt.

This toolkit is designed around the same idea, and the numbers are measured rather than asserted:

| Blog principle | How the toolkit applies it |
|---|---|
| **Progressive disclosure** | `AGENT_TEAM.md` is **53,288 B and is *not* read at session start** — the bootstrap loads it only when spawning a sprint, writing a spawn brief, or answering merge/escalation questions. `VERIFICATION_PLAYBOOK.md` and all **8 skills** load on trigger, not up front. Language conventions live in path-scoped `.claude/rules/*.md` files that load only when Claude touches a matching file — **1.2–2.3 KB per project** (7 files, 8,564 B across all six variants). |
| **Mechanism over mandate** | **12 hook scripts** enforce the rules that prose used to repeat — tests before a commit, no push to main, skills-in-spawn-prompt, merge gate, delegation, subagent budget, and a retro ledger of subagent failures replayed at session start. **261 consistency assertions** and **327 hook fixtures** keep them from drifting (327 is the whole suite on every host; what varies is the split — the fixtures for the six node-only hooks, and the per-backend encoding cases, SKIP where that interpreter is absent, so a node-less box reports `224 passed, 0 failed, 103 skipped (327 assertions)`). Where a hook enforces a rule, the prose does not need to shout it. |
| **Tool instructions live with the tools** | MCP usage rules point at the tool catalog instead of duplicating schemas; `CLAUDE.local.md` says *when* to prefer a server, not what its parameters are. |
| **Let the model use judgement** | Tier tables are **caps, not targets** — "pick the lowest defensible tier and justify escalation, not restraint." Question-shaped turns spawn at most one agent. |

**The trim pass, measured.** The always-loaded surface went **41,167 B → 25,999 B (−36.8%)** on the `general` variant, across v1.4, v1.5, v2.0, and v2.1:

| File | Baseline | v1.4 | v1.5 | pre-PR4 | v2.0 | **v2.1** |
|---|---|---|---|---|---|---|
| `CLAUDE.md` | 17,871 | 15,281 | 13,735 | 13,892 | 10,362 | **10,560** |
| `CLAUDE.local.md` | 13,845 | **9,352** | 9,352 | 9,413 | 9,417 | 9,417 |
| user-level `CLAUDE.md` | 8,505 | 8,505 | 8,505 | 8,637 | 5,089 | **5,076** |
| `PROJECT_CONTEXT.md` | 946 | 946 | 946 | 946 | 946 | 946 |
| **total** | **41,167** | 34,084 | 32,538 | 32,888 | 25,814 | **25,999** |

Per-variant now: general **25,999** · python 27,181 · java 27,266 · dotnet 28,685 · rust-tauri 29,168 · dotnet-maui 30,253.

v2.1 spent 185 B rather than saving them: the *Pick the session model* bootstrap step and the `use a workflow` line are both decisions the PO takes before any file is open, which is the one place always-loaded text earns its cost. No cut was invented elsewhere to keep the −37% headline round.

Every v2.0 figure is `wc -c` on the shipped file, not an arithmetic carry-forward. The **pre-PR4** column exists because PR1–PR3 moved two of these files for reasons unrelated to the trim: `CLAUDE.md` drifted 13,735 → 13,892 and `CLAUDE.local.md` 9,352 → 9,413, which is why the v2.0-pr4 CHANGELOG entry starts its cut at 13,892 rather than at the v1.5 number. The user-level row's drop is PR5 deleting the context-mode routing block (8,637 → 5,089 B).

**v1.4 relocated rather than deleted.** Ten MCP procedures (Ollama warm-up, digesting large inputs, structured extraction, orientation, quality/security sweeps, Context7, headless batch, performance, default workflow) moved into a new **`mcp-usage` skill**; the per-agent Open Brain tables moved into `AGENT_TEAM.md`, which is already on-demand; the Superpowers block keeps its hard triggers and points at the user-level copy for the rest. The on-demand side grew accordingly — `AGENT_TEAM.md` 47,968 → 49,724 B, skills 11 → 12.

**v1.5 deleted, because a mechanism already covers it.** *Working Preferences* went from 18 bullets to 11 (3,939 → 2,393 B). Seven were dropped: five that a hook or the harness already enforces — reading before editing, running tests before commit, never pushing to main, `Read` size limits, keeping the PO out of hands-on work — and two with no behavioural content. In their place, one line naming where the enforcement lives, so the omission reads as deliberate rather than as an oversight. This is the unhobbling move: state that a mechanism exists instead of repeating the rule it enforces. The `"22% of total context"` statistic also collapsed from **7 files to 1**.

**v2.0-pr4 scoped, because the rule only applies to some files.** Every variant's *Code Style (MANDATORY)*, *Enforcement Notes*, and *Project Conventions* sections moved verbatim into `.claude/rules/*.md` with a `paths:` frontmatter glob list — a C# style rule now enters context when Claude opens a `.cs` file and not before, and is re-injected after compaction. Rules **without** `paths:` load at launch at CLAUDE.md cost, so the toolkit ships scoped rules only. The duplicated Spawn-Prompt Binding Table (already in `AGENT_TEAM.md` and enforced by a hook) went with it.

A second round routed two more sections by **audience** rather than by topic. *Open Brain Context for Agents* duplicated `AGENT_TEAM.md` §Open Brain, which is on-demand and more detailed — CLAUDE.md keeps a pointer. *Working Preferences* binds developer agents, not the PO, and every coder preloads `karpathy-guidelines` via `skills:` — so its 11 bullets moved into that skill and now reach the agents that act on them at spawn time, costing nothing on turns that spawn no one. Only the hook-enforcement line stayed, because it is PO-relevant. `general` variant CLAUDE.md: 13,892 → **10,362 B**; `rust-tauri`, now the largest, 16,749 → **11,296 B**.

**v2.1 unhobbled three more places, and each one removed a rule rather than adding one.** The plan gate is gone — a coder spawn no longer needs a `docs/plans/` file carrying `Tier:` and challenge evidence, because Boris Cherny's *"I don't use plan mode anymore … it just doesn't need it"* describes the models this toolkit targets; what replaces it is the task brief in the spawn prompt, which is prose, not a second mechanism. The session-level `effortLevel: medium` is gone too: `xhigh` is the documented default for Opus 4.7 and later, so pinning a level capped the model below its own default on every turn — effort is now raised only on `architect` and `code-reviewer`, where judgement happens, and model choice is a written policy (`/model fable` for T3/T4) rather than a setting. And the tier table gained an exit: work too big for one pass is answered with **"use a workflow"**, letting Claude script its own fan-out instead of the PO hand-decomposing it. Two rules deleted, one judgement call added — the direction the blog argues for.

Every literal a hook greps is pinned by `scripts/verify-template-consistency.sh` (**209 assertions**), so none of the cuts could silently break enforcement — including the exact Superpowers header, the `superpowers:` token the checks require, and (new in PR4) that every rules file is genuinely path-scoped and that the relocated developer preferences survive in the skill that now carries them.

If you are adopting the toolkit and want Anthropic's own verdict on your `CLAUDE.md` and skills, run `/doctor`.

## 5-minute quickstart

1. **Install prerequisites:** `git`, one JSON parser for the hooks (`node`, `python3` or `jq` — native Claude Code installs ship no `node`), and Claude Code CLI (`npm install -g @anthropic-ai/claude-code`). Variant-specific extras (.NET SDK, Rust, JDK, Python) are listed in [`docs/getting-started.md`](docs/getting-started.md).
2. **Clone:**
   ```bash
   git clone https://github.com/dagonet/claude-code-toolkit
   cd claude-code-toolkit
   ```
3. **Run the setup script** against your project directory:
   ```bash
   ./setup-project.sh --variant <variant> --project-name <name> --target-path <path>
   ```
   Every variant accepts `--build-cmd`, `--test-cmd`, `--format-cmd`, `--lint-cmd`, `--gate-cmd`, `--worktree-base`, `--log-path`, and `--default-branch`; an explicit flag always wins over the value a variant would derive. Add `--wrap-existing-claude-md` to keep an existing `CLAUDE.md` — its full content moves into the template's `PROJECT-CUSTOM` region instead of the file being skipped. Run with `--dry-run` first: it now prints the same "Remaining placeholders to fill manually" report as the real run.

   See [`docs/setup.md`](docs/setup.md) for per-variant flags and full examples.
4. **(Optional) Install MCP servers** for tool-accelerated workflows: [`mcp-servers/HOWTO.md`](mcp-servers/HOWTO.md).
5. **Open your project in Claude Code** and try `/sprint` or `bash hooks/run-gate.sh`.

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
| Reference for `~/.claude/` (agents, skills, hooks, settings) | [`user-level-reference/README.md`](user-level-reference/README.md) |

## Related projects

- [**mcp-dev-servers**](https://github.com/dagonet/mcp-dev-servers) — seven custom MCP servers (95 tools) for git, GitHub, .NET, Rust, Ollama, Python, and template-sync. Used by every variant.
- [**open-brain**](https://github.com/dagonet/open-brain) — persistent memory MCP server for storing decisions, insights, and context across sessions.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues: [`SECURITY.md`](SECURITY.md).

## License

MIT — see [`LICENSE`](LICENSE).
