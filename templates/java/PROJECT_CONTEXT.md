# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Repository**: {{REPO_URL}}
- **Tech Stack**: {{TECH_STACK}}

## Build System

- **Build Command**: {{BUILD_COMMAND}}
- **Test Command**: {{TEST_COMMAND}}
- **Format Command**: {{FORMAT_COMMAND}}
- **Lint Command**: {{LINT_COMMAND}}
- **Gate Command**: {{GATE_COMMAND}}
- **Java Version**: {{JAVA_VERSION}}

## Paths

- **Source Root**: src/main/java  <!-- adjust for multi-module projects -->
- **Test Root**: src/test/java
- **Resources**: src/main/resources
- **Worktree Base**: {{WORKTREE_BASE}}
- **Log Path**: {{LOG_PATH}}

## Workflow Configuration

- **Task source**: `plan-files`
- **Branch strategy**: feature branches per task, PR into `{{DEFAULT_BRANCH}}` (see AGENT_TEAM.md Mode Behavior Table for naming convention). Prose for humans — **no hook reads this line**; the enforced set is `**Protected branches**:` directly below.
<!-- THE line the protection hooks read; space- or comma-separated names. Absent, empty, or still a {{PLACEHOLDER}} -> `main master`. `none` protects nothing (branch rules only; a PR merge stays gated). -->
- **Protected branches**: {{DEFAULT_BRANCH}}
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
