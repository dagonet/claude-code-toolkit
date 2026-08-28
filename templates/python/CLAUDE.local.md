# Claude Code -- MCP Usage Rules

This repository is configured with local MCP servers that provide
**local-first preprocessing, automation, and integration tools**
to reduce token usage, improve determinism, and avoid fragile shell workflows.

Claude MUST follow the rules below.

---

## MCP Servers Registered

Tool schemas and full parameter signatures load on-demand via Claude Code's MCP catalog — don't duplicate them here. See *Mandatory Tool Usage Rules* below for when to prefer each server over Bash/shell alternatives.

- **`ollama-tools`** — local LLM preprocessing: `local_first_pass`, `extract_json`, `map_project_structure`, plus health/model mgmt.
- **`MCP_DOCKER`** — official GitHub MCP (Docker Desktop): issues, PRs, comments, search, file ops, releases.
- **`github-tools`** — repo + workflow utilities: `gh_repo_from_origin`, `gh_workflow_list`.
- **`open-brain`** — persistent memory: `thoughts_search`/`recent`/`capture`/`review`/`people`/`topics`/`delete`, `system_status`, plus wiki tools (`wiki_get`/`wiki_list`/`wiki_refresh`) and contradictions tools (`contradictions_list`/`contradictions_resolve`/`contradictions_audit`) (14 tools).
- **`sqlite`** — DB access: `read_query`, `write_query`, `list_tables`, `describe_table`, `append_insight`.
  > DB mounted at `/data/{{DB_FILENAME}}` from `{{DB_DIRECTORY}}`. Configured at user-level `~/.claude.json`.

### Python Build & Test (Bash — no MCP yet)

Prefix with `poetry run` / `uv run` if using Poetry or uv; plain commands work with pip/venv.

- **Tests:** `python -m pytest`, `python -m pytest path/to/test.py -x` (targeted).
- **Format/lint:** `ruff format .`, `ruff check . --fix`.

---

## Mandatory Tool Usage Rules

## Git Operations (native CLI)

Git runs through the **git CLI** (`Bash(git ...)`), and `gh` covers the GitHub
gaps the MCP servers do not. MCP wrappers for git are no longer required.

> **Scope:** every agent with `Bash` in its `tools:` frontmatter does its own git
> I/O. Agents without `Bash` (`architect`, `requirements-engineer`,
> `doc-generator`) return their work product and the PO performs the git
> operation on their behalf.

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

## GitHub Operations (MCP) -- HARD REQUIREMENT

For **ANY GitHub operation**, Claude MUST use MCP GitHub tools
and MUST NOT use shell commands (`gh`, `curl`) or direct HTTP calls.

> **Scope:** this rule binds the PO and all sub-agents with GitHub MCP tools in their `tools:` frontmatter. Developer agents, code reviewers, and testers have explicit GitHub MCP tools listed. Agents without GitHub MCP tools (`architect`, `requirements-engineer`, `doc-generator`, `test-writer`) return work to the PO; the PO performs the GitHub operation.

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
- `Bash(gh ...)` where an MCP GitHub tool exists -- `gh` is a fallback for the gaps only (e.g. `gh pr merge`, which the merge gate covers)
- `Bash(curl ...)`
- Direct REST or GraphQL calls

### Required Workflow
1. **Get repo** -- Call `gh_repo_from_origin(repo_path)` if repo slug unknown
2. **Read first** -- Use `list_issues` / `issue_read` to discover and understand issues
3. **Propose before writing** -- State which issues will be affected and what will change
4. **Write second** -- Execute write tools only after the proposal

---

## Build Failure Handling -- MUST

If a build or test run fails:

Claude MUST:
1. Parse the Python traceback carefully: look for `Traceback (most recent call last)` and the final error line
2. Fix import errors first (dependency order), then logic errors
3. Re-run the build/tests until clean

**Skill available:** `superpowers:systematic-debugging` — hypothesis-driven diagnosis
before changing code; re-run `bash hooks/run-gate.sh` to verify the fix.

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
git/GitHub MCP-only requirement, Open Brain, trust/verification, and failure handling.
