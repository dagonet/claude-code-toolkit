# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Tech stack**: {{TECH_STACK}}
- **Repository**: {{REPO_URL}}
- **Solution file**: `{{SOLUTION_FILE}}`
- **MAUI project**: `{{MAUI_PROJECT}}`
- **Test project**: `{{TEST_PROJECT}}`
- **Branch strategy**: feature branches per task, PR into `{{DEFAULT_BRANCH}}` (see AGENT_TEAM.md Mode Behavior Table for naming convention). Prose for humans — **no hook reads this line**; the enforced set is `**Protected branches**:` directly below.
<!-- THE line the protection hooks read; space- or comma-separated names.
     EDIT THIS if your trunk is not main/master — nothing fills it in for you,
     and a trunk that is not named here is NOT protected.
     Absent, empty, or an unfilled {{...}} all fall back to `main master`;
     `none` protects nothing (branch rules only; a PR merge stays gated). -->
- **Protected branches**: main master

## Commands

- **Build**: {{BUILD_COMMAND}}
- **Run**: `dotnet build {{MAUI_PROJECT}} -f net9.0-windows10.0.19041.0 -t:Run`
- **Test**: {{TEST_COMMAND}}
- **Format**: `dotnet format {{SOLUTION_FILE}}`
- **Lint**: `dotnet format {{SOLUTION_FILE}} --verify-no-changes`
- **Gate**: `dotnet format {{SOLUTION_FILE}} --verify-no-changes && dotnet build {{SOLUTION_FILE}} && dotnet test`

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
