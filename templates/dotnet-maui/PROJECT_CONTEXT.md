# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Tech stack**: {{TECH_STACK}}
- **Repository**: {{REPO_URL}}
- **Solution file**: `{{SOLUTION_FILE}}`
- **MAUI project**: `{{MAUI_PROJECT}}`
- **Test project**: `{{TEST_PROJECT}}`
- **Branch strategy**: `main` is protected; feature branches per task (see AGENT_TEAM.md Mode Behavior Table for naming convention)

## Commands

- **Build**: {{BUILD_COMMAND}}
- **Run**: `dotnet build {{MAUI_PROJECT}} -f net9.0-windows10.0.19041.0 -t:Run`
- **Test**: {{TEST_COMMAND}}
- **Format**: `dotnet format {{SOLUTION_FILE}}`
- **Lint**: `dotnet format {{SOLUTION_FILE}} --verify-no-changes`

## Paths

- **Worktree base**: {{WORKTREE_BASE}}
- **Architecture docs**: `README.md`, `docs/`
- **Database directory**: `{{DB_DIRECTORY}}`  <!-- optional: remove if project doesn't use SQLite -->
- **Database file**: `{{DB_PATH}}`  <!-- optional: remove if project doesn't use SQLite -->
- **Log location**: {{LOG_PATH}}

## Workflow Configuration

- **Task source**: `plan-files`
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
