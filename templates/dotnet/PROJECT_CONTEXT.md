# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Tech stack**: {{TECH_STACK}}
- **Repository**: {{REPO_URL}}
- **Solution file**: `{{SOLUTION_FILE}}`
- **Branch strategy**: `main` is protected; feature branches per task (see AGENT_TEAM.md Mode Behavior Table for naming convention)

## Commands

- **Build**: {{BUILD_COMMAND}}
- **Test**: {{TEST_COMMAND}}
- **Format**: `dotnet format {{SOLUTION_FILE}}`
- **Lint**: `dotnet format {{SOLUTION_FILE}} --verify-no-changes`

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
