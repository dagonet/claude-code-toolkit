# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Tech stack**: {{TECH_STACK}}
- **Repository**: {{REPO_URL}}
- **Branch strategy**: feature branches per task, PR into `{{DEFAULT_BRANCH}}` (see AGENT_TEAM.md Mode Behavior Table for naming convention). Prose for humans — **no hook reads this line**; the enforced set is `**Protected branches**:` directly below.
<!-- THE line the protection hooks read; space- or comma-separated names. Absent, empty, or still a {{PLACEHOLDER}} -> `main master`. `none` protects nothing (branch rules only; a PR merge stays gated). -->
- **Protected branches**: {{DEFAULT_BRANCH}}

## Commands

- **Build**: {{BUILD_COMMAND}}
- **Test**: {{TEST_COMMAND}}
- **Format**: {{FORMAT_COMMAND}}
- **Lint**: {{LINT_COMMAND}}
- **Gate**: {{GATE_COMMAND}}

## Paths

- **Worktree base**: {{WORKTREE_BASE}}
- **Architecture docs**: `README.md`, `docs/`
- **Log location**: {{LOG_PATH}}

## Workflow Configuration

- **Task source**: `plan-files`
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
