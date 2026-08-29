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
- **Branch strategy**: `{{DEFAULT_BRANCH}}` is protected; feature branches per task (see AGENT_TEAM.md Mode Behavior Table for naming convention)
<!-- Branch names the protection hooks read; comma-separated. Empty or `none` = no protected branch. -->
- **Protected branches**: {{DEFAULT_BRANCH}}
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
