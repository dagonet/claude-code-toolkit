# Claude Code -- MCP Usage Rules

This repository is configured with local MCP servers that provide
**local-first preprocessing, automation, and integration tools**
to reduce token usage, improve determinism, and avoid fragile shell workflows.

Claude MUST follow the rules below.

---

## Tooling Overview

### Ollama Tools (MCP: `ollama-tools`)
- `ollama_health` -- check if Ollama server is running
- `ollama_list_models` -- list available models
- `warm_models(keep_alive)` -- pre-load models for faster inference
- `local_first_pass(text, goal)` -- compress large inputs via local LLM
- `extract_json(text, schema)` -- extract structured data from text
- `map_project_structure(root, include)` -- list project files (supports glob patterns)

### Git Tools (MCP: `git-tools`)
- `git_status(repo_path, include_untracked)`
- `git_diff_summary(repo_path, staged)`
- `git_diff(repo_path, staged, file_path)` -- full diff output
- `git_log(repo_path, limit, oneline)` -- view commit history
- `git_show(repo_path, ref)` -- show commit details
- `git_add(repo_path, paths)`
- `git_rm(repo_path, paths, cached)`
- `git_commit(repo_path, message)`
- `git_branch_list(repo_path, all_branches)`
- `git_checkout(repo_path, ref, create)`
- `git_pull(repo_path, remote, branch)`
- `git_push(repo_path, remote, branch, set_upstream)`
- `git_stash(repo_path, action, message)`
- `git_remote_list(repo_path)`
- `git_tag_list(repo_path, limit)`
- `git_env_info` -- diagnostic info about git installation

### GitHub Tools

**Official GitHub MCP (`mcp__github__`)** -- Use for most operations:
- `list_issues`, `issue_read`, `issue_write` -- issue management
- `add_issue_comment` -- add comments to issues
- `list_pull_requests`, `pull_request_read` -- PR management
- `create_pull_request`, `merge_pull_request` -- PR operations
- `search_code`, `search_issues`, `search_pull_requests` -- search
- `get_file_contents`, `create_or_update_file` -- file operations
- See full list in MCP server documentation

**Custom GitHub Tools (MCP: `github-tools`)** -- Unique utilities:
- `gh_repo_from_origin(repo_path)` -- get OWNER/REPO from git remote
- `gh_workflow_list(repo, limit)` -- list GitHub Actions workflow runs

### .NET Tools (MCP: `dotnet-tools`)

**Build & Test:**
- `build_and_extract_errors(project_or_sln, configuration)` -- build and extract errors/warnings
- `run_tests_summary(project_or_sln, configuration)` -- run tests and parse TRX results
- `run_coverage(project_or_sln, configuration)` -- run tests with code coverage

**Project Analysis:**
- `map_dotnet_structure(root)` -- categorize .NET project files
- `parse_csproj(csproj_path)` -- extract project metadata
- `analyze_project_references(solution_or_dir)` -- analyze inter-project dependencies
- `check_framework_compatibility(solution_or_dir)` -- check target framework alignment
- `analyze_namespace_conflicts(root, pattern)` -- find duplicate type definitions

**NuGet Management:**
- `nuget_list_outdated(project_or_sln, include_transitive)` -- find outdated packages
- `nuget_check_vulnerabilities(project_or_sln, include_transitive)` -- security audit
- `nuget_dependency_tree(project_or_sln, include_transitive)` -- full dependency graph

**Entity Framework:**
- `ef_migrations_status(project_path, context, startup_project)` -- list migrations
- `ef_pending_migrations(project_path, context, startup_project)` -- check unapplied migrations
- `ef_dbcontext_info(project_path, context, startup_project)` -- database provider info

**Code Quality:**
- `analyze_method_complexity(root, threshold)` -- find complex methods (cyclomatic complexity)
- `find_god_classes(root, method_threshold, field_threshold)` -- detect bloated classes
- `find_large_files(root, line_threshold, pattern)` -- find oversized files

**Debugging:**
- `parse_stack_trace(stack_trace)` -- extract structured frames from .NET stack traces
- `parse_coverage_report(report_path)` -- parse Cobertura XML coverage reports

### Open Brain Memory (MCP: `open-brain`)

**Read tools:**
- `thoughts_search(query, limit?, thought_type?, people?, topics?, days?)` -- semantic search via embeddings
- `thoughts_recent(days?, limit?)` -- list recent thoughts by date
- `thoughts_people(limit?)` -- list unique people mentioned
- `thoughts_topics(limit?)` -- list unique topics mentioned
- `thoughts_review(days?)` -- structured summary over a time period
- `system_status()` -- system health check

**Write tools:**
- `thoughts_capture(text, metadata?)` -- capture thought with auto-classification
- `thoughts_delete(id)` -- soft-delete a thought by UUID

### SQLite Database (MCP: `sqlite`)
- `read_query(sql)` -- execute SELECT queries (read-only)
- `write_query(sql)` -- execute INSERT/UPDATE/DELETE
- `create_table(sql)` -- create new tables
- `list_tables()` -- list all tables in the database
- `describe_table(table_name)` -- show table schema
- `append_insight(insight)` -- store analysis notes

> **Database path**: `/data/{{DB_FILENAME}}` (mounted read-only from `{{DB_DIRECTORY}}`)
> Runs in Docker container `mcp/sqlite-mcp-server`. Configured at user-level `~/.claude/.mcp.json`.

---

## Mandatory Tool Usage Rules

## Git Operations (MCP) -- HARD REQUIREMENT

For **ANY git operation**, Claude MUST use MCP git tools
and MUST NOT use Bash git commands.

### Allowed
- `git_status`, `git_diff_summary`, `git_diff`
- `git_log`, `git_show`
- `git_add`, `git_rm`, `git_commit`
- `git_branch_list`, `git_checkout`
- `git_pull`, `git_push`, `git_stash`
- `git_env_info` (for debugging)

### Forbidden
- `Bash(git …)`
- Shell scripts that invoke git
- "Yes, and don't ask again" commit flows

### Required Workflow
1. `git_status` -- Use `include_untracked=true` when new files may exist
2. `git_diff_summary` (staged/unstaged as needed)
3. `git_log` (optional, to review recent commit style)
4. `git_add` / `git_rm` (explicit file paths only)
5. Brief explanation of what will be committed (short bullet list)
6. `git_commit` (commit message written by Claude)

---

## GitHub Operations (MCP) -- HARD REQUIREMENT

For **ANY GitHub operation**, Claude MUST use MCP GitHub tools
and MUST NOT use shell commands (`gh`, `curl`) or direct HTTP calls.

### For Issues and PRs
Use the **official GitHub MCP** (`mcp__github__`):
- `list_issues` / `issue_read` / `issue_write`
- `add_issue_comment`
- `list_pull_requests` / `pull_request_read`
- `create_pull_request` / `merge_pull_request`

### For Repository Detection
Use **custom github-tools MCP**:
- `gh_repo_from_origin(repo_path)` -- get OWNER/REPO from local git remote

### For GitHub Actions
Use **custom github-tools MCP**:
- `gh_workflow_list(repo, limit)` -- list workflow runs

### Forbidden
- `Bash(gh …)`
- `Bash(curl …)`
- Direct REST or GraphQL calls

### Required Workflow
1. **Get repo** -- Call `gh_repo_from_origin(repo_path)` if repo slug unknown
2. **Read first** -- Use `list_issues` / `issue_read` to discover and understand issues
3. **Propose before writing** -- State which issues will be affected and what will change
4. **Write second** -- Execute write tools only after the proposal

---

## Ollama Availability & Warm-up

Before using Ollama-dependent tools (`local_first_pass`, `extract_json`):

Claude SHOULD:
1. Call `ollama_health` to verify the server is running
2. Call `ollama_list_models` to verify required models are available
3. Optionally call `warm_models` to pre-load models for faster inference

If Ollama is unavailable:
- Claude MUST inform the user that local preprocessing is unavailable
- Claude MAY proceed without local preprocessing if the task is small
- Claude MUST NOT retry indefinitely or fail silently

---

## Large Inputs / Context Digestion

If any input (file, log, spec, pasted text) is:
- longer than ~200 lines, OR
- complex (requirements, logs, architecture, policies)

Claude MUST:
1. Call `local_first_pass`
2. Use the result as a plan or compression
3. VERIFY important details against the original source
4. Only then implement or answer

Claude MUST NOT skip this step.

---

## Structured Information Extraction

If the task requires structured data such as:
- errors / warnings
- TODOs
- requirements
- entities
- acceptance criteria
- causes / effects

Claude MUST:
1. Call `extract_json` with an explicit schema
2. Treat the JSON as authoritative structure
3. Act on the JSON (prioritize, implement, fix)

Claude MUST NOT infer structure manually when extraction is possible.

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

**Skill available:** The `fix-errors` skill provides systematic error parsing,
prioritization by error code, and iterative fixing with rebuild verification.

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

## Project Orientation & Exploration -- MUST

When orienting within the repository:

Claude MUST:
1. Call `map_dotnet_structure` or `map_project_structure`
2. Use the returned structure to decide which files to open or modify

Claude MUST NOT:
- Perform repeated manual directory exploration
- Open random files without structural justification

**Skill available:** The `orient` skill provides a comprehensive orientation workflow
with structure mapping, architecture detection, and issue identification.

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

**Skill available:** The `security-audit` skill provides comprehensive security review
including NuGet vulnerabilities, secrets scanning, and OWASP Top 10 code pattern checks.

---

## Entity Framework Migrations -- SHOULD

When working with EF Core:

Claude SHOULD:
1. Call `ef_migrations_status` to understand current state
2. Call `ef_pending_migrations` before deployments
3. Warn if database appears out of sync

---

## Code Quality Analysis -- SHOULD

When reviewing code quality:

Claude SHOULD:
1. Call `analyze_method_complexity` for complexity hotspots
2. Call `find_god_classes` for maintainability issues
3. Call `find_large_files` for files needing refactoring

**Skills available:**
- `refactor` skill: Full refactoring workflow with analysis, prioritization, and incremental changes
- `code-review` skill: Comprehensive review checklist covering correctness, design, security, performance
- `arch-analyze` skill: Architecture pattern detection and dependency rule validation

---

## Security Review -- SHOULD

When reviewing security or before releases:

Claude SHOULD use available skills for structured security analysis.

**Skill available:** The `security-audit` skill provides comprehensive security review
including secrets scanning and OWASP Top 10 code pattern checks.

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

## Performance Guidance -- SHOULD

- Prefer MCP tools for preprocessing and automation
- Avoid dumping logs, directory trees, or diffs into chat
- Reserve Claude's reasoning budget for:
  - design decisions
  - code changes
  - test logic
  - architectural tradeoffs

---

## Context7 Library Documentation -- SHOULD

When using .NET library APIs or any NuGet library:

Claude SHOULD:
1. Use `mcp__plugin_context7_context7__resolve-library-id` to find the library
2. Use `mcp__plugin_context7_context7__query-docs` to look up current API usage
3. Verify code against retrieved documentation before committing

### When to Use
- Unfamiliar .NET library APIs or controls
- CommunityToolkit.Mvvm patterns (`[ObservableProperty]`, `[RelayCommand]`)
- Any library where API surface has changed recently

### When NOT to Use
- Well-known .NET BCL APIs (LINQ, collections, string manipulation)
- Code patterns already established in the codebase (follow existing patterns first)

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

## Open Brain Memory -- HARD REQUIREMENT

Open Brain (`mcp__open-brain__*`) is the user's persistent memory system.
See Tooling Overview above for the full 8-tool inventory.

### At Session Start (MANDATORY)

Claude MUST call **at least one** of the following before any other work:
- `thoughts_search` with a query relevant to the current project or task
- `thoughts_recent` to review what was recently captured

This is NOT optional. Do NOT skip this step. Do NOT defer it.

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

### Forbidden
- Skipping the session-start read
- Completing a session without capturing any durable knowledge
- Asking "should I save this to Open Brain?" — just do it

---

## Additional MCP Servers (Pre-Permitted)

The following MCP servers are pre-permitted in `settings.json` but require user-level registration (`~/.claude/.mcp.json` or `claude mcp add`) before they become available:

- **Playwright** (`mcp__plugin_playwright_playwright__*`) -- Browser automation for web testing
- **SearXNG** (`mcp__searxng__*`) -- Privacy-respecting web search aggregation

These are no-ops if not registered. Add documentation to your project-level `CLAUDE.local.md` when you enable them.

---

## Default Workflow Pattern

Unless explicitly instructed otherwise, Claude SHOULD follow:

1. MCP preprocessing
2. Plan based on tool output
3. Verify against sources
4. Implement changes
5. Re-run build/tests if relevant
6. Update GitHub issues if appropriate
7. Commit changes
8. Summarize results

---
