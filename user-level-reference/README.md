# User-Level Claude Code Configuration Reference

This directory contains the reference copies of the user-level (`~/.claude/`) configuration for Claude Code: `CLAUDE.md`, `settings.json`, the MCP server template and the settings documentation. **Since v5.0 the agents, skills, the `pm-report` output style and the toolkit hooks ship in the `cct` plugin** (this repo is the plugin; install it as `cct@dagonet`), so nothing here is copied into `~/.claude/agents/`, `skills/`, `output-styles/` or `hooks/` any more.

> **Commands were merged into skills.** Anthropic made `.claude/commands/<n>.md` equivalent to `.claude/skills/<n>/SKILL.md`; slash commands still work, but a skill is the forward-compatible artifact. This directory no longer ships a `commands/` directory — delete `~/.claude/commands/` when you sync.

> **Note:** This is part of the [Claude Code Template Repository](../README.md) -- see the main README for full documentation on template variants, setup automation, and project-level configuration.

## New Machine Setup

> **Linux host (agent server):** from a checkout of this repo, `bash scripts/install-user-level-linux.sh` does steps 2, 3 and 5 below, in a safe order: `CLAUDE.md` with a Linux "Platform" section (`scripts/linux/CLAUDE-platform-linux.md`); the plugins (`cct@dagonet` from `$CCT_MARKETPLACE`, default `dagonet/claude-code-toolkit#v<VERSION>`, then superpowers, skill-creator and frontend-design), stopping non-zero before anything is removed unless `claude plugin list` shows `cct@dagonet`; `settings.json` without the Windows-only entries and without the v4.x toolkit hook entries; then every v4.x leftover in `scripts/lib/v4-user-leftovers.txt` moved to `~/.claude/v4-leftovers.bak-<UTC>/`. It never touches `~/.claude.json`, so register MCP servers separately with `claude mcp add --scope user`. Afterwards `bash scripts/verify-user-level-drift.sh` reports 0 drift: the rendered `CLAUDE.md`, `cct@dagonet` at `VERSION`, no leftover.
>
> **Windows PC moving from v4.x:** follow [`../docs/plugin-migration-windows.md`](../docs/plugin-migration-windows.md).

Follow these steps to configure Claude Code on a fresh machine:

1. **Install Claude Code CLI**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Copy CLAUDE.md to `~/.claude/CLAUDE.md`**
   Copy `CLAUDE.md` from this directory to `~/.claude/CLAUDE.md`. This defines user-level rules (platform, sub-agent discipline, setup guidance) that apply across all projects.

3. **Install the cct plugin**
   ```
   /plugin marketplace add dagonet/claude-code-toolkit#v<VERSION>
   /plugin install cct@dagonet
   ```
   It brings every agent (`cct:<name>`), every skill (`/cct:<skill>`), the `pm-report` output style and the toolkit hooks, machine-wide. Delete `~/.claude/commands/` if it still exists — a leftover command file shadows its skill.

4. **Configure MCP servers**
   `.mcp.json.template` holds the user-scope server definitions. **It is a snippet, not a file to drop in place.** Merge its `mcpServers` object into **`~/.claude.json`** (note: `~/.claude.json`, a sibling of the `~/.claude/` directory — *not* `~/.claude/.mcp.json`, which Claude Code does not read, and *not* `~/.claude/settings.json`, where an `mcpServers` key is silently ignored). Equivalently, run `claude mcp add --scope user …`, which writes to the same place. Replace the placeholder values with real paths and tokens for your machine. See also [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md).

5. **Configure settings.json**
   Copy **`settings.json`** from this directory to `~/.claude/settings.json`. Its only hook is the inline `UserPromptSubmit` time hook, and `outputStyle` is `cct:pm-report` (a plugin style loads only under the plugin prefix).

   **If you already have a `~/.claude/settings.json`, merge — do not overwrite.** Your file
   carries personal keys this reference does not (`advisorModel`, `autoCompact*`,
   `contextCompactionThreshold`, `statusLine`, model pins); overwriting drops them silently.
   Take the `permissions.deny` entries only, per the v2.1 migration pattern: a short Python
   script that loads both files as JSON, unions `permissions.deny` and writes your file back.

   Three things to decide before copying, because this file is a starting point, not a policy:
   - `permissions.defaultMode` is **`auto`**, and `permissions.autoMode.environment` describes this machine's trust boundary in prose. Rewrite those sentences for your own environment — they are what the classifier reasons over. `autoMode` is User/managed scope only; a project cannot ship it.
   - `permissions.allow` no longer contains `Bash(*)`, `WebFetch(*)`, or `mcp__git-tools__*`; the git/`gh` CLI is *gated* by hooks rather than blanket-allowed. Widen it only deliberately.
   - `env.CLAUDE_CODE_SHELL` points at Git Bash on Windows. Remove it on macOS/Linux.

   Personal additions are deliberately excluded: no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries. `settings-reference.md` explains every setting in detail.

## What's Included

### Agents

The agents ship in the cct plugin (`agents/` at the repo root) and are named `cct:<name>`; their models and effort are the values in each file's frontmatter. Plugin agents carry no frontmatter `hooks:` (consistency check 75): the plugin registers `gate-before-merge` once, for every caller.

### Skills (9)

Explicit workflows carry `disable-model-invocation: true` so they run only when you type the slash command; the rest auto-trigger from their `description`.

| Skill | Invocation | Purpose |
|-------|-----------|---------|
| `challenge` | `/cct:challenge [target]` only | Two structured passes over a plan or design: scope/necessity, then correctness/completeness. Explicit-only because it may spawn the architect. |
| `commit` | `/cct:commit` only | Stage and commit with native git, after showing the user the staged diff; includes the verification checklist |
| `sprint` | `/cct:sprint [plan]` only | Run a backlog as parallel **subagent** workstreams — rebase before merge, gate before merge, final-message reporting |
| `sync-template` | `/cct:sync-template` only | Pull template updates from claude-code-toolkit into the current project |
| `contribute-upstream` | `/cct:contribute-upstream` only | Push generalizable project improvements back to the template |
| `retro-review` | `/cct:retro-review [project-dir]` only | Local maintenance sweep: the subagent-failure retro ledger, `verify-user-level-drift.sh`, and consumer repos behind the toolkit `VERSION` → a ≤ 30-line summary in auto-memory. The local counterpart to the `toolkit-nightly-check` routine |
| `karpathy-guidelines` | auto | Writing any new code (main thread); the coders carry a digest as `## Working rules`. Carries the *Toolkit working preferences (developer agents)* section |
| `mcp-usage` | auto | Occasional MCP procedures — digesting a large input, extracting structured data, mapping a repo, library lookups, headless batches |
| `jev` | `/cct:jev on\|off\|status\|report` only | Optional, per clone (default off): routes sub-agent spawns that pass no `model` through TypeSafe's Jev -- any model at confidence >= the threshold (0.65), review/architect types never below sonnet and never a lower effort, a confident effort applied unless the call passes one, the project floor on any failure. Sends the redacted, trimmed spawn text off the machine while on. Needs python3 and `TYPESAFE_API_KEY` |

**What replaced the culled artifacts**

| Was | Use instead |
|---|---|
| `/build`, `/test` | `cct-gate` (the `Gate:` mechanism; `bash hooks/run-gate.sh` in this repo itself) |
| `/skill-eval`, `/skill-improve`, plus the toolkit's `evals/evals.json` convention | the official `skill-creator@claude-plugins-official` plugin, which ships eval authoring, grading, and benchmarking |
| `fix-errors` | `superpowers:systematic-debugging` |
| `code-review` | the bundled `/code-review` plugin, or `superpowers:requesting-code-review` / `receiving-code-review` |
| `arch-analyze`, `impact-analysis`, `explaining-code`, `orient` | the `cct:Explore` subagent (haiku) plus `superpowers:brainstorming` / `writing-plans` |
| `security-audit` | `/code-review`'s security pass |
| `refactor` | `karpathy-guidelines` + `superpowers:test-driven-development` |
| `/new-feature`, `/user-story`, `/spec-to-issues`, `/traceability`, `/arch-doc`, `/api-design`, `/tech-debt`, `/coverage-report`, `/dependency-audit`, `/dotnet-analyze`, `/ef-check`, `/nuget-audit`, `/pre-release`, `/godot-run`, `/issue-create`, `/add-tests` | deleted — near-zero measured use; the agent roster (`architect`, `tester`, `coder`, `ops`) covers the same ground. *(The roster named here was `requirements-engineer` / `test-writer` when these commands were deleted; both were retired by absorption in v3.0.0 — into `architect` and `tester` respectively.)* |

### Output styles (1)

| Style | Default? | Purpose |
|-------|----------|---------|
| `pm-report` | yes (`outputStyle` in `settings.json`) | Plain-language, state-change reporting for a product-manager reader; pairs with a status board or dashboard, if one is set up (rule 9). `/output-style default` switches a session back to the technical style. |

### Hooks

None at user level since v5.0, except the inline `UserPromptSubmit` time hook in `settings.json`. The toolkit hooks run from the cct plugin (`hooks/hooks.json` at the repo root). A v4.x machine still carries `~/.claude/hooks/` and six exec-form registrations in `~/.claude/settings.json`; `scripts/lib/v4-user-leftovers.txt` lists every leftover path, the Linux installer removes them, and `docs/plugin-migration-windows.md` is the Windows procedure.

### Routines

`routines/` holds prompt bodies for **cloud** routines (`/schedule`, or
<https://claude.ai/code/routines>) — scheduled Claude Code sessions that run over a
*clone* of a repository plus connectors, with no permission prompts and no access to
this machine's `~/.claude` or uncommitted files. Everything a routine needs must be
committed to the repo it clones, and its prompt must be self-contained. Copy a file's
prompt body into the routine when you create it; nothing here is loaded automatically.

- `toolkit-nightly-check.md` — daily consistency + fixtures + stale-reference + version
  check over `claude-code-toolkit`, silent on success, one rolling GitHub issue on
  failure. Its local counterpart, which reads `~/.claude` and sibling checkouts and so
  cannot be a routine, is the `retro-review` skill.

### MCP Config Template

`.mcp.json.template` -- The user-scope `mcpServers` object, with placeholders for machine-specific paths and configuration. **Merge it into `~/.claude.json`** (or use `claude mcp add --scope user`), which is the only file Claude Code reads for user-scope servers. Placeholders:
- `{{PYTHON_VENV_PATH}}` -- Path to the Python virtual environment binary directory (e.g., `<your-path>\mcp-dev-servers\.venv\Scripts` on Windows, `~/repos/mcp-dev-servers/.venv/bin` on Linux/macOS)
- `{{OLLAMA_MODEL_FIRST_PASS}}` -- Ollama model for text compression (e.g., `mistral:7b-instruct-q4_K_M`)
- `{{OLLAMA_MODEL_EXTRACT_JSON}}` -- Ollama model for JSON extraction (e.g., `qwen2.5:7b-instruct-q4_K_M`)
- `{{OPEN_BRAIN_COMMAND}}` -- Command to launch the Open Brain MCP server (replace with your installation path)
- `{{OPEN_BRAIN_ARGS}}` -- Arguments for the Open Brain server (replace with your configuration)

  > **Per-repo opt-out (Open Brain v0.3.0+):** to disable the wiki and contradictions tool families for a specific project, add an `env` block to that project's `.mcp.json` open-brain entry: `"OPEN_BRAIN_TOOLS_DISABLED": "wiki,contradictions"`. The MCP server filters those tool families from `tools/list` when this env var is set; existing `thoughts_*` tools remain available.

- `{{SEARXNG_COMMAND}}` -- Command to launch the SearXNG MCP server
- `{{SEARXNG_ARGS}}` -- Arguments for the SearXNG server
- `{{SEARXNG_INSTANCE_URL}}` -- URL of your SearXNG instance (e.g., `http://localhost:8888`)

**Related configuration (not in this template):**
- **GitHub Personal Access Token** -- read by the official GitHub plugin from the `GITHUB_PERSONAL_ACCESS_TOKEN` system environment variable, not via template substitution. See [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) → *Official GitHub Plugin* for setup.
- **SQLite MCP** -- a project-level entry, generated into `<project-root>/.mcp.json` by `setup-project.sh --sqlite-db-path <path>` (or the `.ps1` equivalent). Not part of the user-level template.

### Settings Reference

`settings-reference.md` -- Full annotated documentation of `~/.claude/settings.json` covering:
- Environment variables (shell override, 1M context, tool search)
- Permission rules (allow, deny, ask, `defaultMode`, `autoMode.environment`)
- `outputStyle`
- The `UserPromptSubmit` time hook (the toolkit hooks come from the cct plugin since v5.0)
- Enabled plugins with descriptions
- Extended thinking, MCP auto-enable, and context compaction settings
