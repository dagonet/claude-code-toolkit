# User-Level Claude Code Configuration Reference

This directory contains reference copies of the user-level (`~/.claude/`) configuration for Claude Code. These files document the full setup of agents, skills, hooks, MCP server configuration, and settings used across all projects on this machine.

> **Commands were merged into skills.** Anthropic made `.claude/commands/<n>.md` equivalent to `.claude/skills/<n>/SKILL.md`; slash commands still work, but a skill is the forward-compatible artifact. This directory no longer ships a `commands/` directory — delete `~/.claude/commands/` when you sync.

> **Note:** This is part of the [Claude Code Template Repository](../README.md) -- see the main README for full documentation on template variants, setup automation, and project-level configuration.

## New Machine Setup

Follow these steps to configure Claude Code on a fresh machine:

1. **Install Claude Code CLI**
   ```bash
   npm install -g @anthropic-ai/claude-code
   ```

2. **Copy CLAUDE.md to `~/.claude/CLAUDE.md`**
   Copy `CLAUDE.md` from this directory to `~/.claude/CLAUDE.md`. This defines user-level rules (platform, sub-agent discipline, setup guidance) that apply across all projects.

3. **Copy agents to `~/.claude/agents/`**
   Copy all `.md` files from `agents/` in this directory to `~/.claude/agents/`. These define specialized AI personas that can be invoked for different tasks.

4. **Copy skills to `~/.claude/skills/`**
   Copy the skill directories from `skills/` in this directory to `~/.claude/skills/`, preserving the folder structure (each skill lives in its own subdirectory with a `SKILL.md` file). Then **delete `~/.claude/commands/`** — every surviving command now lives as a skill, and a leftover command file shadows its skill.

5. **Copy hooks to `~/.claude/hooks/`**
   ```bash
   cp -r user-level-reference/hooks/. ~/.claude/hooks/
   ```

   One recursive copy is enough — since v2.0 this directory **mirrors** the fail-closed hooks from the toolkit root, so nothing has to be fetched from a second place. `settings.json` binds `no-push-main.sh` fail-closed (`127` → `exit 2`), so a missing copy blocks every Bash call; copy the hooks before the settings file. `read-size-gate.sh` and `bash-output-guard.sh` cannot block and degrade quietly. `gate-before-merge.sh` and `pre-commit-test.sh` ship here as files only — they are not bound at user level, because their project-level bindings run `bash hooks/…` relative to a project root. `lib/git-cmd.sh` is sourced by the gates via `$(dirname "$0")/lib/…` and must keep its subdirectory — **use `cp -r`, not `cp *.sh`**, which does not recurse. Confirm with `ls ~/.claude/hooks/lib/git-cmd.sh`; without it the gates load nothing and, because the hook file itself exists, the wrapper's `127 → exit 2` fail-closed path never fires.

   The mirror is asserted byte-identical to the toolkit root by `scripts/verify-template-consistency.sh` — edit `hooks/<name>.sh` at the root and re-copy; never edit the mirror.

6. **Configure MCP servers**
   `.mcp.json.template` holds the user-scope server definitions. **It is a snippet, not a file to drop in place.** Merge its `mcpServers` object into **`~/.claude.json`** (note: `~/.claude.json`, a sibling of the `~/.claude/` directory — *not* `~/.claude/.mcp.json`, which Claude Code does not read, and *not* `~/.claude/settings.json`, where an `mcpServers` key is silently ignored). Equivalently, run `claude mcp add --scope user …`, which writes to the same place. Replace the placeholder values with real paths and tokens for your machine. See also [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md).

7. **Configure settings.json**
   Copy **`settings.json`** from this directory to `~/.claude/settings.json`. Hook commands use `~/.claude/hooks/…`; **`~` and `$HOME` both expand inside a hook `command` string** (verified empirically — a probe bound at both forms fired and resolved to the real absolute path), so no path editing is needed.

   **If you already have a `~/.claude/settings.json`, merge — do not overwrite.** Your file
   carries personal keys this reference does not (`advisorModel`, `autoCompact*`,
   `contextCompactionThreshold`, `statusLine`, model pins); overwriting drops them silently.
   Take the `permissions.deny` entries and the `hooks` block only, per the v2.1 migration
   pattern: a short Python script that loads both files as JSON, unions `permissions.deny`,
   replaces `hooks`, and writes your file back.

   Three things to decide before copying, because this file is a starting point, not a policy:
   - `permissions.defaultMode` is **`auto`**, and `permissions.autoMode.environment` describes this machine's trust boundary in prose. Rewrite those sentences for your own environment — they are what the classifier reasons over. `autoMode` is User/managed scope only; a project cannot ship it.
   - `permissions.allow` no longer contains `Bash(*)`, `WebFetch(*)`, or `mcp__git-tools__*`; the git/`gh` CLI is *gated* by hooks rather than blanket-allowed. Widen it only deliberately.
   - `env.CLAUDE_CODE_SHELL` points at Git Bash on Windows. Remove it on macOS/Linux.

   Personal additions are deliberately excluded: no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries. `settings-reference.md` explains every setting in detail.

## What's Included

### Agents (9)

Models and effort below are the values in each `agents/*.md` frontmatter — keep this table in step with the files. Aliases only: a model proxy reroutes them, a pinned `claude-*` id bypasses it. The **session** effort level is left unset (the model's own default); the orchestrator model is picked per session with `/model` — `fable` for T3/T4 work, `opus` for T1/T2.

| Agent | Model | Effort | Description |
|-------|-------|--------|-------------|
| `Explore` | haiku | low | Read-only codebase search. Overrides the built-in `Explore`, which otherwise inherits the session model. Returns ranked `path:line` findings, never whole files. |
| `architect` | opus | xhigh | Reviews architecture, provides implementation guidance, maintains ADRs and docs. Does not write application code. |
| `code-reviewer` | opus | xhigh | Reviews code for quality, style, structure, and test coverage. Posts categorized findings. Does not write code. |
| `coder` | sonnet | medium | General-purpose software engineer for implementing changes with high-quality engineering standards. Runs with `isolation: worktree`. |
| `ops` | sonnet | medium | Non-code execution: environment setup, installs, binary/file operations, one-off diagnostics, log collection, re-running the project gate. Keeps the orchestrator out of hands-on work. |
| `tester` | sonnet | medium | QA tester that verifies features via UI automation (FlaUI), database inspection, and log analysis. Runs with `isolation: worktree`. |

> **User-level agents are not template agents.** A user-level agent applies in *every* repo and its frontmatter `hooks:` travel with it, so it may only reference scripts and paths that exist everywhere. The copies here deliberately omit the `hooks/gate-before-merge.sh` PreToolUse hooks that `templates/*/.claude/agents/coder.md` carries — those fail closed (`127` → `exit 2`) in any repo without a `hooks/` directory, which would make PR merges impossible. `scripts/verify-template-consistency.sh` asserts both halves of this rule. Body prose may still mention `hooks/run-gate.sh`, because that is conditional on the project's `Gate` field and the agent simply skips it when absent.

### Skills (8)

Explicit workflows carry `disable-model-invocation: true` so they run only when you type the slash command; the rest auto-trigger from their `description`.

| Skill | Invocation | Purpose |
|-------|-----------|---------|
| `challenge` | `/challenge [target]` only | Two structured passes over a plan or design: scope/necessity, then correctness/completeness. Explicit-only because it may spawn the architect. |
| `commit` | `/commit` only | Stage and commit with native git, after showing the user the staged diff; includes the verification checklist |
| `sprint` | `/sprint [plan]` only | Run a backlog as parallel **subagent** workstreams — rebase before merge, gate before merge, final-message reporting |
| `sync-template` | `/sync-template` only | Pull template updates from claude-code-toolkit into the current project |
| `contribute-upstream` | `/contribute-upstream` only | Push generalizable project improvements back to the template |
| `retro-review` | `/retro-review [project-dir]` only | Local maintenance sweep: the subagent-failure retro ledger, `verify-user-level-drift.sh`, and consumer repos behind the toolkit `VERSION` → a ≤ 30-line summary in auto-memory. The local counterpart to the `toolkit-nightly-check` routine |
| `karpathy-guidelines` | auto | Writing any new code — mechanically enforced on `coder`/`*-coder` spawns via `hooks/require-skills-block.sh`; carries the *Toolkit working preferences (developer agents)* section |
| `mcp-usage` | auto | Occasional MCP procedures — digesting a large input, extracting structured data, mapping a repo, library lookups, headless batches |

**What replaced the culled artifacts**

| Was | Use instead |
|---|---|
| `/build`, `/test` | `bash hooks/run-gate.sh` (the `Gate:` mechanism) |
| `/skill-eval`, `/skill-improve`, plus the toolkit's `evals/evals.json` convention | the official `skill-creator@claude-plugins-official` plugin, which ships eval authoring, grading, and benchmarking |
| `fix-errors` | `superpowers:systematic-debugging` |
| `code-review` | the bundled `/code-review` plugin, or `superpowers:requesting-code-review` / `receiving-code-review` |
| `arch-analyze`, `impact-analysis`, `explaining-code`, `orient` | the `Explore` subagent (haiku) plus `superpowers:brainstorming` / `writing-plans` |
| `security-audit` | `/code-review`'s security pass |
| `refactor` | `karpathy-guidelines` + `superpowers:test-driven-development` |
| `/new-feature`, `/user-story`, `/spec-to-issues`, `/traceability`, `/arch-doc`, `/api-design`, `/tech-debt`, `/coverage-report`, `/dependency-audit`, `/dotnet-analyze`, `/ef-check`, `/nuget-audit`, `/pre-release`, `/godot-run`, `/issue-create`, `/add-tests` | deleted — near-zero measured use; the agent roster (`architect`, `tester`, `coder`, `ops`) covers the same ground. *(The roster named here was `requirements-engineer` / `test-writer` when these commands were deleted; both were retired by absorption in v3.0.0 — into `architect` and `tester` respectively.)* |

### Hooks

`hooks/` mirrors, byte for byte, the subset of the toolkit-root `hooks/` directory that is useful at user level: the fail-open `bash-output-guard.sh` and `read-size-gate.sh`, the fail-closed `no-push-main.sh` that `settings.json` binds, the two git gates `pre-commit-test.sh` and `gate-before-merge.sh` (files only — not bound at user level), and `lib/git-cmd.sh`, which the gates source. The toolkit root remains the canonical source; `scripts/verify-template-consistency.sh` asserts every file here is identical to `hooks/<same relative path>`, so a drifted mirror is a red build rather than a silently older contract. A hook script missing at runtime exits `127`; the wrappers in `settings.json` translate that to `exit 2` so enforcement fails closed rather than silently off.

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
- The v2.0 hook set
- Enabled plugins with descriptions
- Extended thinking, MCP auto-enable, and context compaction settings
