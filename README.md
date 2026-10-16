[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/dagonet/claude-code-toolkit)

# Claude Code Toolkit

**Install one plugin and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) gets a team of specialist agents, safety guard rails and handy commands.**

The `cct` plugin is for people who run Claude Code on real projects. You want it to work in a team and stay inside the lines, without building the setup by hand.
Optional project templates then put a working setup into your repo. Windows, macOS and Linux; any language, with ready-made setups for .NET, Java, Python and Rust.

## What you get

### A team of agents

Claude hands work to specialists instead of doing everything itself. Call them as `cct:<name>`. Each one has its own model and effort, so search is cheap and review is thorough.

| Agent | What it does |
|---|---|
| `cct:coder` | Implements a change in its own git worktree, so your working copy stays clean |
| `cct:dotnet-coder`, `cct:java-coder`, `cct:python-coder`, `cct:rust-coder` | The same, with the habits of that language |
| `cct:tester` | Checks a feature against its acceptance criteria with tests and logs |
| `cct:code-reviewer` | Reviews code and posts sorted findings. Never edits |
| `cct:architect` | Reviews design and keeps the architecture notes. Never writes application code |
| `cct:ops` | Setup, installs, one-off tool runs, diagnostics and log collection |
| `cct:Explore` | Read-only search. Returns file and line pointers, never whole files |

### Guard rails

Hooks are small scripts that Claude Code runs around its actions. The plugin ships them. In a project set up from the templates they:

- stop a push to `main` and a merge until the build and tests pass (`cct-gate`, your own gate command);
- stop a commit while the tests are red;
- refuse reads of secret files such as `.env`;
- keep the lead session delegating: it plans and reviews, the agents edit code and run builds;
- guard against oversized file reads, runaway agents and shell habits that stall a session.

### A plain report style

`cct:pm-report` makes Claude report like a status update for a product manager: what changed and why, not a wall of technical detail.
Select it with `"outputStyle": "cct:pm-report"` in `~/.claude/settings.json`. `/output-style default` switches back.

### Skills

Slash commands you can run in any session.

| Skill | What it does |
|---|---|
| `/cct:commit` | Shows you exactly what will be committed, then commits |
| `/cct:sprint` | Runs a backlog as parallel agent workstreams, with a rebase and the gate before each merge |
| `/cct:challenge` | Questions a plan in two passes (is it needed, is it right) before you run it |
| `/cct:sync-template` | Pulls template updates into your project and keeps your own edits |
| `/cct:contribute-upstream` | Sends an improvement from your project back to the toolkit templates |
| `/cct:retro-review` | Reviews agent failures, config drift and which projects are behind |
| `/cct:jev` | Switches the optional model routing on or off (below) |

Two more start by themselves when they fit: `mcp-usage` (steps for large inputs and MCP servers) and `karpathy-guidelines` (habits that avoid common coding mistakes).

### Project templates

Six variants give a project its instructions, workflow, tool permissions and build gate: `general`, `dotnet`, `dotnet-maui`, `rust-tauri`, `java` and `python`.
Which one fits, and what each adds: [`docs/templates.md`](docs/templates.md).

### Optional: model routing with Jev

Off by default. `/cct:jev on` lets the Jev service pick the model and effort for each agent launch. The `jev` skill explains what is sent.

## Install

In Claude Code, once per machine (the same on Windows, macOS and Linux), then restart the session:

```
/plugin marketplace add dagonet/claude-code-toolkit#v5.1.0
/plugin install cct@dagonet
```

Optional: copy [`user-level-reference/CLAUDE.md`](user-level-reference/CLAUDE.md) to `~/.claude/CLAUDE.md` for the user-level rules.
Its `settings.json` needs merging, not copying: see [`user-level-reference/README.md`](user-level-reference/README.md).

- **Upgrading from v4.x?** Windows PC: [`docs/plugin-migration-windows.md`](docs/plugin-migration-windows.md).
  Linux: `bash scripts/install-user-level-linux.sh` from a checkout. The CHANGELOG has the migration notes.
- **Cloud sessions** (claude.ai/code, routines) load no local plugins. Add this to the environment's setup script:
  `claude plugin marketplace add dagonet/claude-code-toolkit#v5.1.0 && claude plugin install cct@dagonet`
- **Moving to a new release:** a pinned install does not advance by itself. Run `claude plugin marketplace remove dagonet`,
  add the new `#tag` the same way, run `claude plugin install cct@dagonet`, restart, then run `/cct:sync-template`.
  Without the `#tag`, the add tracks the default branch and `claude plugin update cct@dagonet` advances it.
- A project set up from the templates refuses every tool call while the plugin is off in the session. Only the `/plugin` commands still work.

## Start a project

You need `git`, Claude Code, and one JSON reader for the hooks (`node`, `python3` or `jq`).

```bash
git clone https://github.com/dagonet/claude-code-toolkit && cd claude-code-toolkit
./setup-project.sh --variant python --project-name MyApp --target-path ../my-app
# Windows: .\setup-project.ps1 -Variant python -ProjectName MyApp -TargetPath ..\my-app
```

Add `--dry-run` to preview. Open the new project in Claude Code and try `/cct:sprint` or `cct-gate`.
Prefer a guided walk-through? Ask Claude, Cursor or Copilot to follow [`AGENTS.md`](AGENTS.md).

**Keep it current:** run `/cct:sync-template` in the project. It brings in newer template files and leaves the files you own alone.

## Learn more

- [`docs/getting-started.md`](docs/getting-started.md): prerequisites and how much of the setup to adopt
- [`docs/setup.md`](docs/setup.md): setup flags and examples for every platform
- [`docs/templates.md`](docs/templates.md): the six variants, placeholders and the manifest
- [`docs/architecture.md`](docs/architecture.md): how the layers, hooks, model policy and context budget fit together
- [`docs/template-sync.md`](docs/template-sync.md): how template updates reach your project
- [`docs/verification.md`](docs/verification.md): check that your setup works
- [`mcp-servers/HOWTO.md`](mcp-servers/HOWTO.md): optional MCP servers
- [`docs/history.md`](docs/history.md) and [`CHANGELOG.md`](CHANGELOG.md): how it got here and what changed in each release

Related: [**mcp-dev-servers**](https://github.com/dagonet/mcp-dev-servers) (MCP servers for git, GitHub, .NET, Rust, Ollama, Python)
and [**open-brain**](https://github.com/dagonet/open-brain) (memory across sessions).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues: [`SECURITY.md`](SECURITY.md).

## License

MIT, see [`LICENSE`](LICENSE).
