# User-Level Rules (All Projects)

## Platform: Windows + Git Bash

This machine runs Windows 11 with Git Bash as the shell.

- Use Unix commands (ls, cp, rm, mkdir -p) — Git Bash supports them
- Avoid Windows-only commands (dir, type, copy, del) — they fail in bash
- Path separators: forward slashes work everywhere in bash
- Avoid `cat` in Bash commands — fails on Windows paths with spaces. Use the Read tool for file reading, MCP tools for release notes
- Avoid `grep -r` in Bash — pick the search tool from the Read & Search Tool Selection table below
- GitHub releases: use MCP GitHub tools, not `gh release create`
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

`Read` loads file contents directly into the main context window (measured at **22% of total context** across recent claude-code-toolkit sessions — the largest actionable bucket after bulk `assistant_tool_use` and `assistant_thinking`). Use `Read` only for files you will immediately Edit or Write. Route everything else by this table — it supersedes any other search/read guidance:

| Need | Tool |
|------|------|
| Find where X is defined/used (needle search) | Grep tool |
| Read a file you will Edit/Write | Read |
| Analyze/summarize one file (no edit) | `mcp__plugin_context-mode_context-mode__ctx_execute_file` |
| Multi-command research/gathering | `ctx_batch_execute` (ONE call, never sequential `ctx_execute`) |
| Open-ended codebase exploration | Explore subagent (compressed summaries, not raw contents) |
| Browse directory contents | Glob |

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

Apply unless plan mode or another skill already covers the same ground:

- Multi-step implementation about to start → invoke `superpowers:writing-plans`, then `superpowers:executing-plans` once the plan is approved.
- Writing production code → invoke `superpowers:test-driven-development` together with `karpathy-guidelines`.
- Requesting / digesting code review → `superpowers:requesting-code-review` / `superpowers:receiving-code-review`.

### Meta skills (no explicit trigger)

- `superpowers:using-superpowers` — auto-loaded at session start; establishes skill-use protocol.
- `superpowers:writing-skills` — invoke only when creating or editing a skill.

---

# context-mode — MANDATORY routing rules

> Requires the [context-mode plugin](https://github.com/dagonet/context-mode). Omit this whole section if the plugin is not installed — the `ctx_*` tools it names will not exist.

You have context-mode MCP tools available. These rules are NOT optional — they protect your context window from flooding. A single unrouted command can dump 56 KB into context and waste the entire session.

## BLOCKED commands — do NOT attempt these

### curl / wget — BLOCKED
Any Bash command containing `curl` or `wget` is intercepted and replaced with an error message. Do NOT retry.
Instead use:
- `ctx_fetch_and_index(url, source)` to fetch and index web pages
- `ctx_execute(language: "javascript", code: "const r = await fetch(...)")` to run HTTP calls in sandbox

### Inline HTTP — BLOCKED
Any Bash command containing `fetch('http`, `requests.get(`, `requests.post(`, `http.get(`, or `http.request(` is intercepted and replaced with an error message. Do NOT retry with Bash.
Instead use:
- `ctx_execute(language, code)` to run HTTP calls in sandbox — only stdout enters context

### WebFetch — BLOCKED
WebFetch calls are denied entirely. The URL is extracted and you are told to use `ctx_fetch_and_index` instead.
Instead use:
- `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` to query the indexed content

## REDIRECTED tools — use sandbox equivalents

### Bash (>20 lines output)
Bash is ONLY for: `git`, `mkdir`, `rm`, `mv`, `cd`, `ls`, `npm install`, `pip install`, and other short-output commands.
For everything else, use:
- `ctx_batch_execute(commands, queries)` — run multiple commands + search in ONE call
- `ctx_execute(language: "shell", code: "...")` — run in sandbox, only stdout enters context

### Read (for analysis)
If you are reading a file to **Edit** it → Read is correct (Edit needs content in context).
If you are reading to **analyze, explore, or summarize** → use `ctx_execute_file(path, language, code)` instead. Only your printed summary enters context. The raw file content stays in the sandbox.

### Grep (large results)
Grep results can flood context. Use `ctx_execute(language: "shell", code: "grep ...")` to run searches in sandbox. Only your printed summary enters context.

## Tool selection hierarchy

1. **GATHER**: `ctx_batch_execute(commands, queries)` — Primary tool. Runs all commands, auto-indexes output, returns search results. ONE call replaces 30+ individual calls. Two or more related commands → ONE `ctx_batch_execute` call, never sequential `ctx_execute` calls.
2. **FOLLOW-UP**: `ctx_search(queries: ["q1", "q2", ...])` — Query indexed content. Pass ALL questions as array in ONE call.
3. **PROCESSING**: `ctx_execute(language, code)` | `ctx_execute_file(path, language, code)` — Sandbox execution. Only stdout enters context.
4. **WEB**: `ctx_fetch_and_index(url, source)` then `ctx_search(queries)` — Fetch, chunk, index, query. Raw HTML never enters context.
5. **INDEX**: `ctx_index(content, source)` — Store content in FTS5 knowledge base for later search.

## Subagent routing

When spawning subagents (Agent/Task tool), the routing block is automatically injected into their prompt. Bash-type subagents are upgraded to general-purpose so they have access to MCP tools. You do NOT need to manually instruct subagents about context-mode.

## Output constraints

- Keep responses under 500 words.
- Write artifacts (code, configs, PRDs) to FILES — never return them as inline text. Return only: file path + 1-line description.
- When indexing content, use descriptive source labels so others can `ctx_search(source: "label")` later.

## ctx commands

| Command | Action |
|---------|--------|
| `ctx stats` | Call the `ctx_stats` MCP tool and display the full output verbatim |
| `ctx doctor` | Call the `ctx_doctor` MCP tool, run the returned shell command, display as checklist |
| `ctx upgrade` | Call the `ctx_upgrade` MCP tool, run the returned shell command, display as checklist |
