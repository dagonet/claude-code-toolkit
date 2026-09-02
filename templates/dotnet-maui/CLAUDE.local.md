# Claude Code -- MCP Usage Rules

This repository may be configured with local MCP servers that provide
**local-first preprocessing, automation, and integration tools**
to reduce token usage, improve determinism, and avoid fragile shell workflows.

Claude MUST follow the rules below.

---

## MCP Servers (each applies only if registered)

Tool schemas and full parameter signatures load on-demand via Claude Code's MCP catalog — don't duplicate them here. See *Mandatory Tool Usage Rules* below for when to prefer each server over Bash/shell alternatives. Every server listed here is optional: a rule that names one applies **only if that server is registered** (`~/.claude.json`, or the project's `.mcp.json`). If it is not registered, use the Bash fallback the rule names.

- **`ollama-tools`** — local LLM preprocessing: `local_first_pass`, `extract_json`, `map_project_structure`, plus health/model mgmt.
- **`dotnet-tools`** — structured .NET workflows:
  - Build/test: `build_and_extract_errors`, `run_tests_summary`, `run_coverage`
  - Project analysis: `map_dotnet_structure`, `parse_csproj`, `analyze_project_references`, `check_framework_compatibility`, `analyze_namespace_conflicts`
  - NuGet: `nuget_list_outdated`, `nuget_check_vulnerabilities`, `nuget_dependency_tree`
  - EF Core: `ef_migrations_status`, `ef_pending_migrations`, `ef_dbcontext_info`
  - Code quality: `analyze_method_complexity`, `find_god_classes`, `find_large_files`
  - Debugging: `parse_stack_trace`, `parse_coverage_report`
- **`MCP_DOCKER`** — official GitHub MCP (Docker Desktop): issues, PRs, comments, search, file ops, releases.
- **`github-tools`** — repo + workflow utilities: `gh_repo_from_origin`, `gh_workflow_list`.
- **`windows-mcp`** — Windows desktop automation: `Click`, `Type`, `Scroll`, `Snapshot`, `App`, `Shell`, `Clipboard`, `Process`.
  > Tester uses `Snapshot()` for ad-hoc visual evidence of the running MAUI app. Not a replacement for FlaUI — use FlaUI for structural verification.
- **`open-brain`** — persistent memory: `thoughts_search`/`recent`/`capture`/`review`/`people`/`topics`/`delete`, `system_status`, plus wiki tools (`wiki_get`/`wiki_list`/`wiki_refresh`) and contradictions tools (`contradictions_list`/`contradictions_resolve`/`contradictions_audit`) (14 tools).
- **`sqlite`** — DB access: `read_query`, `write_query`, `list_tables`, `describe_table`, `append_insight`.
  > DB mounted at `/data/{{DB_FILENAME}}` from `{{DB_DIRECTORY}}`. Configured at user-level `~/.claude.json`.

---

## Mandatory Tool Usage Rules

## Git Operations (native CLI)

Git runs through the **git CLI** (`Bash(git ...)`), and `gh` covers the GitHub
gaps the MCP servers do not. MCP wrappers for git are no longer required.

> **Scope:** every agent with `Bash` in its `tools:` frontmatter does its own git
> I/O. `architect` has no `Bash`, so it returns its work product and the PO
> performs the git operation on its behalf.

### Gates — enforced by hooks, not by policy

| Command | Hook | Effect |
|---|---|---|
| `git commit` | `hooks/pre-commit-test.sh` | runs the project gate first; a red gate blocks the commit |
| `git push` to main/master | `hooks/no-push-main.sh` | blocked (exit 2) |
| `gh pr merge`, `git merge` on main, a push to main | `hooks/gate-before-merge.sh` | requires a fresh, SHA-matching `.gate/last-pass.json` |

The gates parse the command itself, so wrappers (`bash -c "..."`) and
`git -C <path>` are covered too. `<repo>/.claude/git-guard-off` disables all
three for the rare case that genuinely needs it.

### Required Workflow
1. `git status` -- check for untracked files before staging
2. `git diff` / `git diff --cached` -- review what is about to be committed
3. `git log` (optional, to review recent commit style)
4. `git add <paths>` (explicit file paths only)
5. Brief explanation of what will be committed (short bullet list)
6. `git commit` (commit message written by Claude)

## GitHub Operations

Use the **MCP GitHub tools when registered** (`mcp__MCP_DOCKER__*` for issues, PRs and
comments; `mcp__github-tools__*` for `gh_repo_from_origin` and `gh_workflow_list`),
otherwise the `gh` CLI (the gates cover `gh pr merge`). Direct REST or GraphQL calls stay
out of scope either way.

> **Scope:** `architect` has neither GitHub MCP tools nor `Bash`, so it returns
> its work to the PO, which performs the GitHub operation.

Read before you write: discover the issue or PR first, state what will change, then run
the write tool.

---

## Build & Compilation Failures -- MUST

If a build is required or build errors are suspected:

Claude MUST:
1. Call `build_and_extract_errors`
2. Use ONLY the returned JSON for diagnosis
3. Fix errors in priority order (first error first)
4. Re-run the build until clean

Claude MUST NOT:
- Paste raw build output
- Diagnose from partial logs

**Skill available:** `superpowers:systematic-debugging` — hypothesis-driven diagnosis
before changing code; re-run `bash hooks/run-gate.sh` to verify the fix.

---

## Test Execution & Failures -- MUST

If tests are run or test failures are suspected:

Claude MUST:
1. Call `run_tests_summary`
2. Use ONLY the returned summary JSON
3. Fix failing tests first
4. Re-run tests to confirm resolution

Claude MUST NOT:
- Paste full test output
- Reason from noisy test logs

---

## Duplicate Types & Namespace Conflicts -- MUST

If duplicate types or namespace conflicts are suspected:

Claude MUST:
1. Call `analyze_namespace_conflicts`
2. Use the results to resolve conflicts explicitly

Claude MUST NOT:
- Guess causes of duplicate symbol errors
- Read many files manually to discover duplicates

---

## NuGet Security & Updates -- SHOULD

When reviewing dependencies or before releases:

Claude SHOULD:
1. Call `nuget_check_vulnerabilities` to find security issues
2. Call `nuget_list_outdated` to find available updates
3. Report findings with severity and recommendations

**Skill available:** `/code-review` (bundled `code-review` plugin) runs a security pass —
NuGet vulnerabilities, secrets scanning, and OWASP Top 10 code pattern checks.

---

## Entity Framework Migrations -- SHOULD

When working with EF Core:

Claude SHOULD:
1. Call `ef_migrations_status` to understand current state
2. Call `ef_pending_migrations` before deployments
3. Warn if database appears out of sync

---

## SQLite Database Queries -- CONDITIONAL

> **Skip this section** if the project does not use a local SQLite database (check PROJECT_CONTEXT.md for DB_PATH).

If the project uses a local SQLite database, Claude SHOULD prefer the SQLite MCP
(`mcp__sqlite__`) over Bash `sqlite3` commands. Skip this rule if the project does not use SQLite.

### Preferred
- `read_query` -- structured SELECT queries with typed results
- `list_tables` / `describe_table` -- schema exploration
- `append_insight` -- store findings for later reference

- **No SQL comments** — never use `--` comments inside MCP SQLite queries. They cause parse failures. Use bare queries only.

### When to use Bash sqlite3 instead
- SQLite MCP is unavailable (Docker not running)
- Need to run `.dump`, `.schema`, or other dot-commands
- Write operations needed on the live database (use with extreme caution)

### Required Workflow (Tester/Verification)
1. `list_tables` -- discover available tables
2. `describe_table` -- understand schema before querying
3. `read_query` -- execute targeted verification queries
4. Report findings in structured format

---

## Windows Desktop Automation -- SHOULD

The Windows-MCP server provides desktop automation tools for the tester agent.

### Primary Use Cases
- **Screenshot capture**: `Snapshot()` to capture the running MAUI app for PO visual review
- **App management**: `App("launch", "{{PROJECT_NAME}}")` to start/stop the app
- **Process cleanup**: `Process("kill", "{{PROJECT_NAME}}.MAUI.exe")` after testing

### NOT a Replacement for FlaUI
- FlaUI provides UIA3-based element inspection (AutomationId, Name, properties)
- Windows-MCP provides coordinate-based interaction (Click, Type) and screenshots
- Use FlaUI for **structural verification** (element exists, text correct)
- Use Windows-MCP for **visual evidence** (screenshots for PO review)

### Forbidden
- Using Windows-MCP Click/Type for test automation (fragile, coordinate-dependent)
- Modifying application data via Windows-MCP Shell

---

## Trust & Verification -- MUST

- MCP tool outputs are **assistive**, not ground truth
- Claude MUST verify critical facts against source files
- Claude MUST NOT trust summaries blindly
- If tool output is ambiguous or incomplete, Claude must say so

---

## Failure Handling -- MUST

- If `extract_json` fails or returns invalid JSON:
  - Retry via the tool
  - Do NOT continue with guessed structure
- If a command-based tool fails:
  - Report the failure reason
  - Do NOT infer missing output
- If required input is missing, Claude MUST ask explicitly

---

## Open Brain Memory

**If `open-brain` is registered:** Open Brain (`mcp__open-brain__*`) is the user's persistent memory system, and the rules in this section bind every turn. If it is not registered, skip the section entirely.

### At Session Start

Claude MUST call **at least one** of the following before any other work:
- `thoughts_search` with a query relevant to the current project or task
- `thoughts_recent` to review what was recently captured

With the server registered this is not optional: do not skip it, do not defer it.

### During the Session

Claude MUST use `thoughts_capture` to record:
- Architectural decisions and their rationale
- Bug root causes and fix approaches
- User preferences discovered during work
- Action items and commitments
- Key insights that would be useful in future sessions

Claude MUST NOT ask permission before capturing. Capture first, mention briefly.

Claude MUST NOT capture:
- Routine implementation details (already in git)
- Temporary debugging state
- Information already in commit messages
- Anything the user marks as private

### Wiki Tools

For synthesis-style questions on a known topic, prefer the wiki layer:

- `wiki_list` — cheap probe (`{limit:1}`) to confirm any wiki pages exist for this user
- `wiki_get` — fetch a compiled wiki page for a topic
- `wiki_refresh` — recompile a stale page on demand

Treat the page as stale and fall back to `thoughts_search` if any of the following hold: `stale_since_n_thoughts > 5`, `open_contradictions_count > 0`, or `compiled_at` older than 7 days. The wiki-first rule is intentionally conditional — it does not replace the session-start `thoughts_search` mandate above.

### Contradictions Tools

When durable knowledge appears to conflict, surface and resolve via:

- `contradictions_list` — review open contradictions
- `contradictions_resolve` — record a resolution decision
- `contradictions_audit` — request an on-demand contradiction audit over recent thoughts

### Forbidden
- Skipping the session-start read
- Completing a session without capturing any durable knowledge
- Asking "should I save this to Open Brain?" — just do it

---

## Additional MCP Servers (Pre-Permitted)

The following MCP servers are pre-permitted in `settings.json` but require user-level registration (`~/.claude.json` or `claude mcp add`) before they become available:

- **Playwright** (`mcp__plugin_playwright_playwright__*`) -- Browser automation for web testing
- **SearXNG** (`mcp__searxng__*`) -- Privacy-respecting web search aggregation

These are no-ops if not registered. Add documentation to your project-level `CLAUDE.local.md` when you enable them.

---

## Occasional MCP Procedures — On Demand

Ollama warm-up, digesting large inputs, structured extraction, project orientation,
code-quality and security sweeps, Context7 lookups, headless batch runs, and the
default MCP-first workflow now live in the **`mcp-usage`** skill. It loads when the
situation calls for it rather than on every turn.

What stays inline above is what binds every turn: which servers are registered, the
GitHub tool-or-`gh` contract, Open Brain, trust/verification, and failure handling.
