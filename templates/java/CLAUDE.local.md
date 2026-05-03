# Claude Code -- MCP Usage Rules

This repository is configured with local MCP servers that provide
**local-first preprocessing, automation, and integration tools**
to reduce token usage, improve determinism, and avoid fragile shell workflows.

Claude MUST follow the rules below.

---

## MCP Servers Registered

Tool schemas and full parameter signatures load on-demand via Claude Code's MCP catalog — don't duplicate them here. See *Mandatory Tool Usage Rules* below for when to prefer each server over Bash/shell alternatives.

- **`ollama-tools`** — local LLM preprocessing: `local_first_pass`, `extract_json`, `map_project_structure`, plus health/model mgmt.
- **`git-tools`** — all git operations: status/diff/log/show, add/rm/commit, branch/checkout, pull/push, stash, tag, remote.
- **`MCP_DOCKER`** — official GitHub MCP (Docker Desktop): issues, PRs, comments, search, file ops, releases.
- **`github-tools`** — repo + workflow utilities: `gh_repo_from_origin`, `gh_workflow_list`.
- **`open-brain`** — persistent memory: `thoughts_search`/`recent`/`capture`/`review`/`people`/`topics`/`delete`, `system_status`, plus wiki tools (`wiki_get`/`wiki_list`/`wiki_refresh`) and contradictions tools (`contradictions_list`/`contradictions_resolve`/`contradictions_audit`) (14 tools).
- **`sqlite`** — DB access: `read_query`, `write_query`, `list_tables`, `describe_table`, `append_insight`.
  > DB mounted at `/data/{{DB_FILENAME}}` from `{{DB_DIRECTORY}}`. Configured at user-level `~/.claude/.mcp.json`.

### Java Build & Test (Bash — no MCP yet)

- **Maven:** `mvn clean verify` (full), `mvn test -pl module -Dtest=ClassName` (targeted), `mvn spotless:apply` / `spotless:check` (format).
- **Gradle:** `./gradlew build` (full), `./gradlew :module:test --tests ClassName` (targeted), `./gradlew spotlessApply` / `spotlessCheck` (format).

---

## Mandatory Tool Usage Rules

## Git Operations (MCP) -- HARD REQUIREMENT

For **ANY git operation**, Claude MUST use MCP git tools
and MUST NOT use Bash git commands.

> **Scope:** this rule binds the **PO main session**. Claude Code strips `mcp__*` from sub-agents with explicit `tools:` lists, so specialized sub-agents (`coder`, `*-coder`, `test-writer`, `tester`, `code-reviewer`) physically cannot call MCP git tools. They return their work to the PO; the PO performs the git operation. The Bash-git block hook in their definitions is intentional — there is no escape hatch by design.

### Allowed
- `git_status`, `git_diff_summary`, `git_diff`
- `git_log`, `git_show`
- `git_add`, `git_rm`, `git_commit`
- `git_branch_list`, `git_checkout`
- `git_pull`, `git_push`, `git_stash`
- `git_worktree_list`, `git_worktree_add`, `git_worktree_remove`
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

> **Scope:** this rule binds the **PO main session**. Specialized sub-agents cannot call `mcp__MCP_DOCKER__*` (dispatch strips it). They return findings/review/verification text to the PO; the PO posts the comment, opens the PR, or merges.

### For Issues and PRs
Use the **official GitHub MCP via Docker Desktop** (`mcp__MCP_DOCKER__`):
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

## Project Orientation & Exploration -- MUST

When orienting within the repository:

Claude MUST:
1. Call `map_project_structure`
2. Use the returned structure to decide which files to open or modify

Claude MUST NOT:
- Perform repeated manual directory exploration
- Open random files without structural justification

**Skill available:** The `orient` skill provides a comprehensive orientation workflow
with structure mapping, architecture detection, and issue identification.

---

## Build Failure Handling -- MUST

If a build fails:

Claude MUST:
1. Parse the Maven/Gradle error output carefully
2. Fix compilation errors first (in dependency order), then test failures
3. Re-run the build until clean

For Maven, errors appear after `[ERROR]` markers. For Gradle, look for `> Task :compile* FAILED` lines.

**Skill available:** The `fix-errors` skill provides systematic error parsing,
prioritization by error code, and iterative fixing with rebuild verification.

---

## Code Quality Analysis -- SHOULD

When reviewing code quality or during refactoring:

Claude SHOULD use available skills for structured analysis.

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

When using unfamiliar library APIs:

Claude SHOULD:
1. Use `mcp__plugin_context7_context7__resolve-library-id` to find the library
2. Use `mcp__plugin_context7_context7__query-docs` to look up current API usage
3. Verify code against retrieved documentation before committing

### When to Use
- Unfamiliar framework APIs (Spring Boot, JPA/Hibernate, etc.)
- Third-party library patterns and conventions
- Any library where API surface has changed recently

### When NOT to Use
- Well-known Java standard library APIs
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
