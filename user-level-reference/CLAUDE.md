# User-Level Rules (All Projects)

## Platform: Windows + Git Bash

This machine runs Windows 11 with Git Bash as the shell.

- Use Unix commands (ls, cp, rm, mkdir -p) — Git Bash supports them
- Avoid Windows-only commands (dir, type, copy, del) — they fail in bash
- Path separators: forward slashes work everywhere in bash
- Avoid `cat` in Bash commands — fails on Windows paths with spaces. Use the Read tool for file reading
- Avoid `grep -r` in Bash — pick the search tool from the Read & Search Tool Selection table below
- **PO / main thread only** (subagents do not have MCP servers — never route these to a spawn): read release notes via the MCP GitHub tools, and cut GitHub releases with them rather than `gh release create`
- PowerShell 5.1 reads BOM-less UTF-8 as ANSI — never rewrite files containing non-ASCII via PS `Get-Content`/`WriteAllText` (mojibakes `—` into `â€”`). Use Bash/the Edit tool, or read with `[IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)`
- Multi-line/compound Bash commands can be conservatively blocked by guard hooks (unparseable → fail-closed). Write the logic to a script file and run `bash <path>` — a simple command line always parses clean
- context-mode sandbox `/tmp` paths are invisible to native `git -C` ("cannot change to ..."). Run git-dependent scripts and fixtures via the Bash tool (real Git Bash), not `ctx_execute`

## Sub-Agent File Write Discipline

- Do NOT delegate file writes to sub-agents for files with complex escaping
  (regex, nested quotes, template literals, TOML/YAML with special chars)
- Sub-agents are excellent for: read-only exploration, code review, test execution
- When a sub-agent write fails with escaping issues, rewrite the file directly
- For multi-file batches: prefer writing files sequentially over delegating to one agent

## Read & Search Tool Selection

`Read` loads file contents directly into the main context window (measured at **22% of total context** across recent claude-code-toolkit sessions — the largest actionable bucket after bulk `assistant_tool_use` and `assistant_thinking`). `hooks/read-size-gate.sh` now enforces the limit mechanically: it caps a `Read` at 500 lines, rewrites the call, and tells you the next `offset`. Use `Read` only for files you will immediately Edit or Write. Route everything else by this table — it supersedes any other search/read guidance:

| Need | Tool |
|------|------|
| Find where X is defined/used (needle search) | Grep tool |
| Read a file you will Edit/Write | Read |
| Analyze/summarize one file (no edit) | Read with `limit`/`offset`, or an Explore subagent if the file is large |
| Multi-file research/gathering | Explore subagent (haiku, `effort: low`) — returns ranked `path:line` findings, not file contents |
| Open-ended codebase exploration | Explore subagent |
| Browse directory contents | Glob |

## Auto-Memory

Auto-memory `MEMORY.md` loads only its first 200 lines / 25 KB — keep it an index; move detail into topic files.

## New Project Setup

After creating a CLI tool or installable package, always include setup/install instructions in the output and README before considering the task complete.

When the user asks to "set up a new project" or "bootstrap a project" from the `claude-code-toolkit` repo, read `AGENTS.md` at the toolkit repo root and follow it — it drives variant selection + Q&A + `setup-project.sh`/`.ps1` invocation. Do not attempt to derive build/test commands yourself; pass the user's answers as flags.

## Superpowers Skills — MUST Invoke Before Responding

Requires the [superpowers plugin](https://github.com/anthropics/claude-plugins-official/tree/main/superpowers). Invoke via the Skill tool.

### Hard triggers (MUST)

These are not optional. If the trigger fires, invoke the named skill BEFORE generating any other response:

- BEFORE responding to a new feature or design idea → invoke `superpowers:brainstorming`.
- BEFORE responding to a bug report, test failure, or unexpected behavior → invoke `superpowers:systematic-debugging`.
- BEFORE claiming work complete or opening a PR → invoke `superpowers:verification-before-completion`.

### Strong triggers (SHOULD)

Apply unless another skill already covers the same ground:

- Multi-step implementation about to start → invoke `superpowers:writing-plans`, then `superpowers:executing-plans` once the plan is approved.
- Writing production code → invoke `superpowers:test-driven-development` together with `karpathy-guidelines`.
- Requesting / digesting code review → `superpowers:requesting-code-review` / `superpowers:receiving-code-review`.

### Meta skills (no explicit trigger)

- `superpowers:using-superpowers` — auto-loaded at session start; establishes skill-use protocol.
- `superpowers:writing-skills` — invoke only when creating or editing a skill.

## context-mode plugin

context-mode is optional. If installed, its SessionStart hook injects its own guidance; do not duplicate it here.
Subagents do not have `ctx_*` tools — never instruct them to use `ctx_*`.
