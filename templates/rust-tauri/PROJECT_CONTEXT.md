# Project Context

## Project

- **Name**: {{PROJECT_NAME}}
- **Tech stack**: {{TECH_STACK}}
- **Repository**: {{REPO_URL}}
- **Branch strategy**: `main` is protected; feature branches per task (see AGENT_TEAM.md Mode Behavior Table for naming convention)

## Commands

- **Build**: `cargo build --manifest-path src-tauri/Cargo.toml`
- **Test (backend)**: `cargo test --manifest-path src-tauri/Cargo.toml`
- **Test (frontend)**: `npm test`
- **Format (backend)**: `cargo fmt --manifest-path src-tauri/Cargo.toml`
- **Format (frontend)**: `npm run format`
- **Lint (backend)**: `cargo clippy --manifest-path src-tauri/Cargo.toml -- -D warnings`
- **Lint (frontend)**: `npm run lint`

## Paths

- **Worktree base**: {{WORKTREE_BASE}}
- **Architecture docs**: `README.md`, `docs/`
- **Log location**: stdout (structured logging via `log` crate)

## Workflow Configuration

- **Task source**: `plan-files`
- **Max parallel workstreams**: 5
- **Commit convention**: `feat:`, `fix:`, `chore:`, `test:`, `docs:` prefixes
- **Issue labels** (github-issues mode only): `feature`, `bug`, `tech-debt`

## Preprocessing

- **Ollama**: available (MCP: `ollama-tools`) -- see CLAUDE.local.md for usage rules
- **Context7**: available (MCP: `context7`)
