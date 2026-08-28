# User-Level Claude Code Configuration Reference

This directory contains reference copies of the user-level (`~/.claude/`) configuration for Claude Code. These files document the full setup of agents, commands, skills, MCP server configuration, and settings used across all projects on this machine.

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

4. **Copy commands to `~/.claude/commands/`**
   Copy all `.md` files from `commands/` in this directory to `~/.claude/commands/`. These define slash commands (`/build`, `/test`, `/commit`, etc.) available in every project.

5. **Copy skills to `~/.claude/skills/`**
   Copy the skill directories from `skills/` in this directory to `~/.claude/skills/`, preserving the folder structure (each skill lives in its own subdirectory with a `SKILL.md` file).

6. **Configure MCP servers**
   `.mcp.json.template` holds the user-scope server definitions. **It is a snippet, not a file to drop in place.** Merge its `mcpServers` object into **`~/.claude.json`** (note: `~/.claude.json`, a sibling of the `~/.claude/` directory — *not* `~/.claude/.mcp.json`, which Claude Code does not read, and *not* `~/.claude/settings.json`, where an `mcpServers` key is silently ignored). Equivalently, run `claude mcp add --scope user …`, which writes to the same place. Replace the placeholder values with real paths and tokens for your machine. See also [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md).

7. **Configure settings.json**
   Copy **`settings.json`** from this directory to `~/.claude/settings.json`. Hook commands use `~/.claude/hooks/…`; **`~` and `$HOME` both expand inside a hook `command` string** (verified empirically — a probe bound at both forms fired and resolved to the real absolute path), so no path editing is needed.

   Two things to decide before copying, because they are permissive and this file is a starting point, not a policy:
   - `permissions.allow` contains **`Bash(*)`** — every Bash command runs without a prompt. Narrow it if you want per-command review.
   - `env.CLAUDE_CODE_SHELL` points at Git Bash on Windows. Remove it on macOS/Linux.

   Personal additions are deliberately excluded: no `statusLine`, no third-party marketplaces or their plugins, no project-specific permission entries. `settings-reference.md` explains every setting in detail.

## What's Included

### Agents (9)

Models and effort below are the values in each `agents/*.md` frontmatter — keep this table in step with the files. Aliases only: a model proxy reroutes them, a pinned `claude-*` id bypasses it.

| Agent | Model | Effort | Description |
|-------|-------|--------|-------------|
| `Explore` | haiku | low | Read-only codebase search. Overrides the built-in `Explore`, which otherwise inherits the session model. Returns ranked `path:line` findings, never whole files. |
| `architect` | opus | high | Reviews architecture, provides implementation guidance, maintains ADRs and docs. Does not write application code. |
| `code-reviewer` | opus | high | Reviews code for quality, style, structure, and test coverage. Posts categorized findings. Does not write code. |
| `coder` | sonnet | medium | General-purpose software engineer for implementing changes with high-quality engineering standards. Runs with `isolation: worktree`. |
| `doc-generator` | haiku | low | Generates documentation for code changes (public APIs, usage examples). |
| `ops` | sonnet | medium | Non-code execution: environment setup, installs, binary/file operations, one-off diagnostics, log collection, re-running the project gate. Keeps the orchestrator out of hands-on work. |
| `requirements-engineer` | sonnet | medium | Refines feature ideas into detailed specs with user stories, acceptance criteria, and edge cases. |
| `test-writer` | sonnet | medium | Writes comprehensive tests for new code, focusing on behavior and edge cases. Runs with `isolation: worktree`. |
| `tester` | sonnet | medium | QA tester that verifies features via UI automation (FlaUI), database inspection, and log analysis. Runs with `isolation: worktree`. |

> **User-level agents are not template agents.** A user-level agent applies in *every* repo and its frontmatter `hooks:` travel with it, so it may only reference scripts and paths that exist everywhere. The copies here deliberately omit the `hooks/gate-before-merge.sh` PreToolUse hooks that `templates/*/.claude/agents/coder.md` carries — those fail closed (`127` → `exit 2`) in any repo without a `hooks/` directory, which would make PR merges impossible. `scripts/verify-template-consistency.sh` asserts both halves of this rule. Body prose may still mention `hooks/run-gate.sh`, because that is conditional on the project's `Gate` field and the agent simply skips it when absent.

### Commands (23)

#### Development
| Command | Description |
|---------|-------------|
| `/build` | Build project and iteratively fix errors |
| `/test` | Run tests and fix failures |
| `/commit` | Stage and commit changes via MCP git tools |
| `/new-feature` | Scaffold a new feature with proper architecture patterns |
| `/add-tests` | Generate unit tests for existing code |
| `/godot-run` | Run a Godot project and capture debug output |
| `/sprint` | Execute a sprint with parallel agent workstreams |

#### Architecture
| Command | Description |
|---------|-------------|
| `/arch-doc` | Generate architecture documentation from code analysis |
| `/api-design` | Review or design REST API contracts |
| `/challenge` | Challenge a plan, approach, or design with two structured passes |
| `/dependency-audit` | Find circular dependencies, orphan projects, and framework mismatches |

#### Quality
| Command | Description |
|---------|-------------|
| `/dotnet-analyze` | Analyze .NET code quality (complexity, god classes, large files) |
| `/coverage-report` | Analyze test coverage and identify gaps |
| `/tech-debt` | Assess and quantify technical debt with remediation roadmap |
| `/pre-release` | Comprehensive pre-release validation checklist |

#### .NET Specific
| Command | Description |
|---------|-------------|
| `/nuget-audit` | Check NuGet packages for vulnerabilities and updates |
| `/ef-check` | Check Entity Framework migration status and DB sync |

#### Requirements
| Command | Description |
|---------|-------------|
| `/user-story` | Generate user stories with acceptance criteria |
| `/spec-to-issues` | Convert a specification document into GitHub issues |
| `/traceability` | Build requirements-to-code-to-tests traceability matrix |

#### Skill Evaluation
| Command | Description |
|---------|-------------|
| `/skill-eval` | Run eval test cases against a skill and report pass/fail results |
| `/skill-improve` | Autonomous Karpathy-style improvement loop: eval → change → re-eval → keep/revert |

#### Integration
| Command | Description |
|---------|-------------|
| `/issue-create` | Create a properly formatted GitHub issue via MCP tools |

### Skills (12)

| Skill | Auto-triggers When |
|-------|-------------------|
| `arch-analyze` | Asking about architecture, layers, or dependency graphs |
| `code-review` | Reviewing PRs, branches, or code changes |
| `explaining-code` | Asking "how does this work?" or requesting code explanations |
| `fix-errors` | Build failures, compilation errors, or pasted error output |
| `impact-analysis` | Planning changes or asking "what will be affected?" |
| `karpathy-guidelines` | Writing any new code (feature or fix) — mechanically enforced on `coder`/*-coder spawns via `hooks/require-skills-block.sh` |
| `orient` | Exploring a new codebase or asking about project structure |
| `refactor` | Requesting code cleanup, improvements, or refactoring |
| `security-audit` | Asking about security vulnerabilities or requesting an audit |
| `sync-template` | Running `/sync-template` to pull template updates into the project |
| `contribute-upstream` | Running `/contribute-upstream` to push project improvements back to the template |
| `mcp-usage` | About to digest a large input, extract structured data, orient in a new repo, look up a library API, or run a batch operation — the occasional MCP procedures moved out of `CLAUDE.local.md` |

### Skill Evals Convention

Skills can have evaluation test cases for automated quality measurement. To add evals to a skill:

1. The skill must be in directory format: `skills/<name>/SKILL.md`
2. Create `skills/<name>/evals/evals.json` with test cases following this schema:
   ```json
   {
     "skill_name": "<name>",
     "evals": [
       {
         "id": 1,
         "prompt": "Self-contained test prompt with inline code/diffs/errors",
         "expected_output": "Brief description of expected output",
         "expectations": [
           "Binary assertion 1 (pass/fail, evaluated by LLM grader)",
           "Binary assertion 2"
         ]
       }
     ]
   }
   ```
3. Run `/skill-eval <name>` to test, `/skill-improve <name>` to auto-improve

Skills with evals: `code-review` (3 tests, 16 assertions), `fix-errors` (3 tests, 13 assertions), `orient` (2 tests, 10 assertions).

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
- Environment variables (agent teams, shell override)
- Permission rules (allow, deny, ask, defaultMode)
- Custom status line configuration
- Enabled plugins with descriptions
- Extended thinking, MCP auto-enable, and context compaction settings
