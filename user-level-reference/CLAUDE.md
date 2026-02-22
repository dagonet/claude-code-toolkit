# User-Level Rules (All Projects)

## Platform: Windows + Git Bash

This machine runs Windows 11 with Git Bash as the shell.

- Use Unix commands (ls, cp, rm, mkdir -p) — Git Bash supports them
- Avoid Windows-only commands (dir, type, copy, del) — they fail in bash
- Path separators: forward slashes work everywhere in bash
- Avoid `cat` in Bash commands — fails on Windows paths with spaces. Use the Read tool for file reading, MCP tools for release notes
- Avoid `grep -r` — use the Grep tool instead
- GitHub releases: use MCP GitHub tools, not `gh release create`

## Sub-Agent File Write Discipline

- Do NOT delegate file writes to sub-agents for files with complex escaping
  (regex, nested quotes, template literals, TOML/YAML with special chars)
- Sub-agents are excellent for: read-only exploration, code review, test execution
- When a sub-agent write fails with escaping issues, rewrite the file directly
- For multi-file batches: prefer writing files sequentially over delegating to one agent

## New Project Setup

After creating a CLI tool or installable package, always include setup/install instructions in the output and README before considering the task complete.
