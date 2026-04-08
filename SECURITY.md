# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, use one of these methods:

1. **GitHub Private Security Advisory** (preferred): Go to the [Security tab](https://github.com/dagonet/claude-code-toolkit/security/advisories/new) and create a private advisory.
2. **Email**: Contact the maintainer directly via GitHub profile.

## What to Include

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Response Timeline

- Acknowledgment within 48 hours
- Status update within 7 days
- Fix timeline depends on severity

## Scope

This policy covers:
- Template files shipped to downstream projects (CLAUDE.md, agents, settings)
- Setup scripts (setup-project.ps1, setup-project.sh)
- MCP server configuration and permission grants

Out of scope:
- Vulnerabilities in Claude Code itself (report to [Anthropic](https://www.anthropic.com/))
- Vulnerabilities in third-party MCP servers (report to their maintainers)
