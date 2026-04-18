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

## Read Tool Discipline

`Read` loads file contents directly into the main context window (measured at **22% of total context** across recent claude-code-toolkit sessions — the largest actionable bucket after bulk `assistant_tool_use` and `assistant_thinking`). Use `Read` only for files you will immediately Edit or Write.

- Exploration, pattern searches, "how does X work", or reading large files for analysis → delegate to an **Explore subagent** (results return as compressed summaries, not raw file contents)
- Single-file analysis that doesn't need contents in context → use `mcp__plugin_context-mode_context-mode__ctx_execute_file`
- Browsing directory contents → use `Glob`, not `Read` on each file

## New Project Setup

After creating a CLI tool or installable package, always include setup/install instructions in the output and README before considering the task complete.

## Superpowers Skills — When to Invoke

Requires the [superpowers plugin](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers). Invoke via the Skill tool.

### Solo PO trigger matrix

| Trigger (user action / session event) | Skill to invoke |
|---|---|
| User describes a new feature or design idea | `superpowers:brainstorming` |
| Design is accepted, need to break into tasks | `superpowers:writing-plans` |
| Plan approved, starting implementation | `superpowers:executing-plans` |
| Writing any new code (feature or fix) | `karpathy-guidelines` + `superpowers:test-driven-development` |
| User reports a bug, test failure, or unexpected behavior | `superpowers:systematic-debugging` |
| Before claiming work complete or opening a PR | `superpowers:verification-before-completion` |
| Requesting review from the code-reviewer agent | `superpowers:requesting-code-review` |
| Digesting code review findings | `superpowers:receiving-code-review` |

### Meta skills (no explicit trigger)

- `superpowers:using-superpowers` — auto-loaded at session start; establishes skill-use protocol.
- `superpowers:writing-skills` — invoke only when creating or editing a skill.
