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
   Use `.mcp.json.template` as a starting point. Replace the placeholder values with real paths and tokens for your machine. See also [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) for MCP server installation and setup instructions.

7. **Configure settings.json**
   Copy the settings to `~/.claude/settings.json`, adjusting paths and preferences for your environment. See `settings-reference.md` for detailed explanations of every setting.

## What's Included

### Agents (7)

| Agent | Model | Description |
|-------|-------|-------------|
| `architect` | opus | Reviews architecture, provides implementation guidance, maintains ADRs and docs. Does not write application code. |
| `coder` | opus | General-purpose software engineer for implementing changes with high-quality engineering standards. |
| `code-reviewer` | sonnet | Reviews code for quality, style, structure, and test coverage. Posts categorized findings. Does not write code. |
| `doc-generator` | haiku | Generates documentation for code changes (public APIs, usage examples). |
| `requirements-engineer` | sonnet | Refines feature ideas into detailed specs with user stories, acceptance criteria, and edge cases. |
| `test-writer` | sonnet | Writes comprehensive tests for new code, focusing on behavior and edge cases. |
| `tester` | sonnet | QA tester that verifies features via UI automation (FlaUI), database inspection, and log analysis. |

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

### Skills (11)

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

`.mcp.json.template` -- A templatized version of `~/.claude/.mcp.json` with placeholders for machine-specific paths and configuration:
- `{{PYTHON_VENV_PATH}}` -- Path to the Python virtual environment binary directory (e.g., `<your-path>\mcp-dev-servers\.venv\Scripts` on Windows, `~/repos/mcp-dev-servers/.venv/bin` on Linux/macOS)
- `{{OLLAMA_MODEL_FIRST_PASS}}` -- Ollama model for text compression (e.g., `mistral:7b-instruct-q4_K_M`)
- `{{OLLAMA_MODEL_EXTRACT_JSON}}` -- Ollama model for JSON extraction (e.g., `qwen2.5:7b-instruct-q4_K_M`)
- `{{OPEN_BRAIN_COMMAND}}` -- Command to launch the Open Brain MCP server (replace with your installation path)
- `{{OPEN_BRAIN_ARGS}}` -- Arguments for the Open Brain server (replace with your configuration)
- `{{SEARXNG_COMMAND}}` -- Command to launch the SearXNG MCP server
- `{{SEARXNG_ARGS}}` -- Arguments for the SearXNG server
- `{{SEARXNG_INSTANCE_URL}}` -- URL of your SearXNG instance (e.g., `http://localhost:8888`)

**Related configuration (not in this template):**
- **GitHub Personal Access Token** -- read by the official GitHub plugin from the `GITHUB_PERSONAL_ACCESS_TOKEN` system environment variable, not via template substitution. See [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) → *Official GitHub Plugin* for setup.
- **SQLite MCP** -- a project-level entry, generated into `<project>/.claude/.mcp.json` by `setup-project.sh --sqlite-db-path <path>` (or the `.ps1` equivalent). Not part of the user-level template.

### Settings Reference

`settings-reference.md` -- Full annotated documentation of `~/.claude/settings.json` covering:
- Environment variables (agent teams, shell override)
- Permission rules (allow, deny, ask, defaultMode)
- Custom status line configuration
- Enabled plugins with descriptions
- Extended thinking, MCP auto-enable, and context compaction settings
