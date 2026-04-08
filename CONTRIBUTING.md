# Contributing to Claude Code Toolkit

Thanks for your interest in contributing! Here's how to get started.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed
- Git
- PowerShell 5.1+ (Windows) or Bash (Linux/macOS)

## Development Setup

1. Fork and clone the repository
2. Review the [architecture docs](docs/architecture.md) to understand the layered config model
3. Pick a template variant to test against (see [docs/templates.md](docs/templates.md))

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `templates/{variant}/` | Template files for each variant (6 variants) |
| `docs/` | User-facing documentation (hub-and-spoke) |
| `mcp-servers/` | MCP server installation guide |
| `user-level-reference/` | Reference copy of `~/.claude/` config (agents, commands, skills) |
| `setup-project.ps1` | Automated setup script (Windows) |
| `setup-project.sh` | Automated setup script (Linux/macOS) |

## Making Changes

1. Create a feature branch from `main`
2. Make your changes
3. Test by running the setup script against a temp directory:
   ```bash
   # Bash
   ./setup-project.sh --variant general --project-name TestProject --target-path /tmp/test --dry-run

   # PowerShell
   .\setup-project.ps1 -Variant general -ProjectName TestProject -TargetPath C:\temp\test -DryRun
   ```
4. Commit with a clear message describing what and why
5. Open a pull request

## Types of Contributions

- **New template variant**: Add `templates/<name>/` with full file set (see existing variants)
- **Agent improvements**: Edit agent definitions in `templates/*/. claude/agents/` and `user-level-reference/agents/`
- **New commands or skills**: Add to `user-level-reference/commands/` or `user-level-reference/skills/`
- **Documentation**: Improve docs in `docs/` or template READMEs
- **Setup script improvements**: Enhance `setup-project.ps1` / `setup-project.sh`

## Pull Request Guidelines

- Keep PRs focused -- one concern per PR
- Describe what changed and why in the PR description
- If changing a template, verify the setup script still works end-to-end
- If changing shared files (AGENT_TEAM.md, settings.json), update all variants that share them
- Maintain cross-platform compatibility (Windows + Linux/macOS)

## Reporting Issues

- Use [GitHub Issues](https://github.com/dagonet/claude-code-toolkit/issues) for bug reports and feature requests
- Include your OS, Claude Code version, and template variant in bug reports
- Check existing issues before opening a new one
