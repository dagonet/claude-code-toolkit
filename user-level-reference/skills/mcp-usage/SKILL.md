---
name: mcp-usage
description: MCP tool preferences and preprocessing procedures — Ollama warm-up, digesting large inputs, structured extraction, project orientation, code-quality and security sweeps, Context7 lookups, headless batch runs, and the default MCP-first workflow. Triggers when about to digest a large file or log, extract structured data from prose, orient in an unfamiliar repo, look up an unfamiliar library API, run a batch operation across repos, or when unsure which MCP server to prefer over a shell command.
---

# MCP Usage

Procedures that used to live inline in every project's `CLAUDE.local.md`. They are needed occasionally, not on every turn, so they load on demand.

`CLAUDE.local.md` keeps only what binds every turn: which servers are registered, the git/GitHub MCP-only requirement, Open Brain, trust/verification, and failure handling.

## Ollama availability & warm-up

Before `local_first_pass` or `extract_json`:

1. `ollama_health` — is the server up?
2. `ollama_list_models` — are the required models present?
3. `warm_models` (optional) — pre-load for faster first inference.

If Ollama is unavailable: say so, proceed without local preprocessing when the task is small, and do **not** retry indefinitely or fail silently.

## Large inputs / context digestion

For any input over ~200 lines, or complex regardless of length (requirements, logs, architecture, policy):

1. `local_first_pass` to compress or plan.
2. **Verify important details against the original** — the summary is assistive, not authoritative.
3. Only then implement or answer.

## Structured information extraction

When the task needs structured data — errors, TODOs, requirements, entities, acceptance criteria, cause/effect:

1. `extract_json` with an explicit schema.
2. Treat the returned JSON as the authoritative structure.
3. Act on it (prioritize, implement, fix).

Do not hand-infer structure when extraction is available. If `extract_json` returns invalid JSON, retry through the tool — never continue on a guessed structure.

## Project orientation

Orienting in a repo: call `map_project_structure` (or `map_dotnet_structure` in .NET repos) and let the returned structure decide which files to open. Avoid repeated manual directory walks and opening files without structural justification.

The `orient` skill wraps this in a fuller workflow (structure mapping, architecture detection, issue identification).

## Code quality & security sweeps

Prefer the dedicated skills over ad-hoc reading:

| Need | Skill |
|---|---|
| Refactoring workflow | `refactor` |
| Review checklist (correctness, design, security, performance) | `code-review` |
| Architecture patterns + dependency rules | `arch-analyze` |
| Secrets scan + OWASP Top 10 patterns | `security-audit` |

In .NET repos, `analyze_method_complexity`, `find_god_classes`, and `find_large_files` give complexity hotspots; `nuget_check_vulnerabilities` and `nuget_list_outdated` cover dependencies.

## Context7 library documentation

For unfamiliar library APIs: `resolve-library-id`, then `query-docs`, then verify the code against what came back before committing.

**Use it for** unfamiliar framework APIs and controls, third-party patterns, and any library whose surface has changed recently. **Skip it for** well-known standard-library APIs and patterns already established in the codebase — follow the existing pattern first.

## Headless mode for batch operations

For repeatable non-interactive work across repos or variants, use `claude -p`:

```bash
# Single-variant template sync
claude -p "Run /sync-template, resolve merge conflicts, commit and push"

# Multi-variant propagation
for variant in general dotnet dotnet-maui rust-tauri java python; do
  claude -p "Apply the same change to templates/$variant/ — implement, verify, commit, push"
done
```

**Use when** the pipeline is well-defined and repeatable — template propagation, release steps, batch syncs. **Do not use** for multi-step sprints needing checkpoints, debugging sessions, or first-time operations whose pattern has not been validated.

> On Windows, run headless commands from Git Bash.

## Performance guidance

Prefer MCP tools for preprocessing and automation. Do not dump logs, directory trees, or full diffs into the conversation. Reserve reasoning budget for design decisions, code changes, test logic, and architectural trade-offs.

## Default workflow pattern

Unless told otherwise: MCP preprocessing → plan from tool output → verify against sources → implement → re-run build/tests → update issues if relevant → commit → summarize.
