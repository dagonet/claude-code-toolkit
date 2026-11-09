[Back to README](../README.md)

# MCP Server Installation Guide

MCP servers in this toolkit are split into two tiers:

- **User-level servers** are registered once in `~/.claude.json` and loaded in every project. These are tools you need universally — git, github, ollama, open-brain, etc.
- **Project-level servers** live in a repo's `.mcp.json` (repo root) and only load in that project. These are language/framework-specific tools — dotnet, rust, sqlite, windows-mcp — that would bloat the context window if loaded globally.

This guide is split accordingly. For the **why**, see `docs/architecture.md` → *MCP Layering*.

---

## Prerequisites

| Scope | Requirement | Used by |
|---|---|---|
| User | **Python** 3.11+ (in PATH) | All `mcp-dev-servers` python servers, and this repo's own `template-sync-tools` server (`server/`) |
| User | **GitHub CLI** (`gh`) installed + authenticated | `github-tools` |
| User | **GitHub Personal Access Token** (`GITHUB_PERSONAL_ACCESS_TOKEN` env var) | Official GitHub plugin |
| User | **Node.js** 18+ | SearXNG MCP, Open Brain |
| Project (dotnet) | **.NET SDK** 8.0+ | `dotnet-tools` |
| Project (rust-tauri) | **Rust toolchain** (rustup, cargo, rustc) | `rust-tools` |
| Project (optional) | **Docker Desktop** running | `sqlite` |
| Project (dotnet-maui / rust-tauri) | **uv/uvx** in PATH | `windows-mcp` |

## MCP server plugins (mcp-dev-servers)

The custom Python MCP servers live in a separate repository, https://github.com/dagonet/mcp-dev-servers (see its README for the full tool reference). Since toolkit v6.1 they install as six plugins from this repo's `dagonet` marketplace, pinned to mcp-dev-servers v0.4.0. There is no clone, no venv and no `claude mcp add`.
`template-sync-tools` is not one of them: it lives in this repo's own `server/` (see the Template Sync Tools section below).

**Once per machine:**

1. Install [uv](https://docs.astral.sh/uv/) so `uvx` is on PATH.
2. Add the marketplace if you have not (`/plugin marketplace add dagonet/claude-code-toolkit#<tag>`, see the README).
3. Install the plugins you want: `claude plugin install <name>@dagonet` for `git-tools`, `github-tools`, `dotnet-tools`, `ollama-tools`, `rust-tools`, `python-tools`. Each works alone; none is enabled for you.
4. Warm the `uvx` cache once so the first session does not wait on the download (a Windows cold start took about 10 s, near the MCP connect timeout):
   `uvx --from "mcp-dev-servers @ git+https://github.com/dagonet/mcp-dev-servers@0a20b97dd42733c629e369e16f4e79af81f93d47" mcp-git-tools </dev/null`

**Where a server is on.** The install enables the plugin in every project (user scope). To have it in some projects only, run `claude plugin disable <name>@dagonet`, then in each clone `claude plugin enable <name>@dagonet --scope local` (writes the gitignored `.claude/settings.local.json`). Each enabled server costs about 15-27 MB of memory per session. macOS: expected to work, untested.

**Tool names.** A plugin server's tools are named `mcp__plugin_<name>_<name>__<tool>` (for example `mcp__plugin_github-tools_github-tools__github_pr_auto_merge`), not `mcp__<name>__<tool>`. The toolkit's allow lists, deny lists, merge-gate matcher and agent `tools:` lists name both forms.

> **Upgrading from a manual install:** after installing the plugin, remove your `claude mcp add` registration (`claude mcp remove --scope user <name>`) and any per-project `.mcp.json` entry for it, or the server runs twice. The old venv under `mcp-dev-servers/.venv` is no longer used and can be deleted.

---

# User-Level Servers

Register these **once** with `claude mcp add --scope user`. They load in every project.

## Ollama Tools (6 tools)

Local LLM preprocessing: health check, model management, text compression, JSON extraction, project mapping.

**Tools:** `ollama_health`, `ollama_list_models`, `warm_models`, `local_first_pass`, `extract_json`, `map_project_structure`

**Install:** `claude plugin install ollama-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

**Options** (asked once at install, kept by Claude Code; change them by reinstalling the plugin):

| Option | Default | Meaning |
|---|---|---|
| Ollama URL | `http://127.0.0.1:11434` | Base URL of the running Ollama server |
| First-pass model | `mistral:7b-instruct-q4_K_M` | Model for `local_first_pass` |
| JSON extraction model | `qwen2.5:7b-instruct-q4_K_M` | Model for `extract_json` |

## Git Tools (34 tools) — optional since v2.0

> **Optional.** Since v2.0 the toolkit drives git through the native `git` CLI and gates it with hooks; no template, agent or hook requires this server. Register it only if you prefer structured JSON over CLI output — the gates fire on `Bash`/`PowerShell` commands, so work done through these MCP tools is **not** gated.

Git operations via MCP: status, diff, log, add, commit, tag, branch, checkout, push, pull, fetch, reset, rebase, stash, restore, worktree, config, archive, describe, revert, reflog, clean-dry-run.

**Key tools:** `git_status`, `git_add`, `git_rm`, `git_commit`, `git_diff`, `git_diff_summary`, `git_log`, `git_branch_list`, `git_branch_create`, `git_branch_delete`, `git_checkout`, `git_pull`, `git_push` (with `--tags` support), `git_fetch`, `git_reset`, `git_rebase` (non-interactive only), `git_stash`, `git_remote_list`, `git_tag_list`, `git_tag_create`, `git_tag_delete`, `git_describe`, `git_revert`, `git_archive`, `git_config_get`, `git_config_set`, `git_restore`, `git_clean_dry_run`, `git_reflog`, `git_show`, `git_worktree_list`, `git_worktree_add`, `git_worktree_remove`, `git_env_info`

**Install:** `claude plugin install git-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

## GitHub Tools (17 tools)

Custom GitHub utilities not covered by the official plugin — release management, workflow dispatch/monitoring, PR hygiene, and more.

**Tools:** `gh_repo_from_origin`, `gh_workflow_list`, `github_release_create` (draft by default), `github_release_edit` (use `draft=false` to publish), `github_release_delete` (name-match guard), `github_release_upload_asset`, `github_release_delete_asset`, `github_workflow_dispatch`, `github_workflow_run_wait`, `github_workflow_run_rerun`, `github_workflow_run_cancel`, `github_check_runs_for_sha`, `github_branch_protection_get`, `github_pr_label_add`, `github_pr_label_remove`, `github_pr_request_review`, `github_pr_auto_merge`

**Requires:** GitHub CLI (`gh`) installed and authenticated

**Install:** `claude plugin install github-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

## Python Tools (7 tools)

Python development workflows: wheel and sdist inspection, smoke install (throwaway venv), pytest with typed output, ruff (lint + format), uv build, coverage.

**Tools:** `wheel_inspect`, `sdist_inspect`, `python_smoke_install`, `uv_build`, `pytest_run`, `ruff` (mode: check/format), `coverage` (merged collect + report)

**Requires:** `uv`, `pytest`, `ruff`, `coverage` in the project environment; Python 3.11+

**Install:** `claude plugin install python-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

## Official GitHub Plugin (40+ tools)

For issue / PR / release / code-search operations, the **official GitHub plugin** (`github@claude-plugins-official`) wraps GitHub's hosted MCP server at `https://api.githubcopilot.com/mcp/` and exposes the full toolset.

**Install:**

```bash
claude plugins install github@claude-plugins-official
```

**Required environment variable:**

Create a fine-grained Personal Access Token at https://github.com/settings/personal-access-tokens and set `GITHUB_PERSONAL_ACCESS_TOKEN` in your user environment.

- **Windows (user env var):**
  ```powershell
  [System.Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', 'ghp_yourtoken', 'User')
  ```
- **Linux / macOS:** add `export GITHUB_PERSONAL_ACCESS_TOKEN="ghp_yourtoken"` to your shell profile.

**Restart Claude Code** after setting the variable — the plugin's MCP server only loads when the token is present.

**Tool prefix:** `mcp__MCP_DOCKER__*` (e.g. `mcp__MCP_DOCKER__issue_read`, `mcp__MCP_DOCKER__create_pull_request`).

**Troubleshooting:** if no github tools show up in `ToolSearch`, the token is likely unset or invalid. The plugin's MCP server fails silently when auth fails — you will see no error, just no tools.

## Template Sync Tools (10 tools)

Deterministic template syncing: manifest management and migration, file status computation, three-way merge, placeholder replacement/reversal, cross-variant propagation, and the consumer-side consistency check. Used by the `/cct:sync-template` and `/cct:contribute-upstream` skills and by `scripts/verify-consumers.sh`.

**Tools:** `template_load_manifest`, `template_migrate_manifest`, `template_compute_status`, `template_get_diff`, `template_apply_file`, `template_finalize_sync`, `template_verify`, `template_reverse_placeholders`, `template_check_cross_variant`, `template_propagate_to_variants` (the registered set is `grep -c '@mcp.tool' server/src/template_sync/mcp.py`)

**Since v4.0.0 this server ships from `server/` in this repo (`claude-code-toolkit`), not from `mcp-dev-servers`.** The contract it implements lives at [`docs/template-sync-migration-contract.md`](../docs/template-sync-migration-contract.md). `mcp-dev-servers` still gates `dotnet-tools` and `rust-tools` via `--mcp-dev-servers-path` — only template-sync-tools moved.

**Install (from a `claude-code-toolkit` checkout):**

**Windows (PowerShell):**

```powershell
server\install.ps1
```

**Linux / macOS:**

```bash
bash server/install.sh
```

Either script creates `server/.venv` and prints the console-script exe path as its ONLY line of stdout.

**Migrate (three steps — never reinstall to fix skew, restart instead):**

1. **Install:** run the install script above; capture the printed exe path.
2. **Re-register:** point `template-sync-tools` in `~/.claude.json` at the printed exe path — replacing any prior `mcp-dev-servers` entry. `setup-project.{sh,ps1}` now does this registration for new projects automatically.

   **Windows (PowerShell):**
   ```powershell
   claude mcp add --scope user --transport stdio template-sync-tools `
     -- "<your-path>\claude-code-toolkit\server\.venv\Scripts\mcp-template-sync-tools.exe"
   ```

   **Linux / macOS:**
   ```bash
   claude mcp add --scope user --transport stdio template-sync-tools \
     -- ~/repos/claude-code-toolkit/server/.venv/bin/mcp-template-sync-tools
   ```
3. **Restart the MCP server (a session restart also does it)** — the server re-imports at spawn, so a restart alone picks up the move. Reinstalling into a running venv is not the fix for skew; it is the one measured way to break it (locked launcher executables, no shim mid-flight).

`mcp-template-sync-tools` from mcp-dev-servers 0.3.x keeps working until you re-register; 0.4.0 of that package removes it. **The rollback target is mcp-dev-servers 0.3.9**, not 0.3.8, if the in-repo server regresses: 0.3.9 carries the `mcp<2` pin and installs cleanly, while 0.3.8 resolves `mcp` 2.x from a clean environment and fails to import (mcp 2.x ships `mcp/server/fastmcp.py` as a tombstone).

## SearXNG (Web Search)

SearXNG is a self-hosted, privacy-respecting metasearch engine that aggregates results from multiple search providers without tracking users.

- **Project:** https://docs.searxng.org/
- **Requires:** A running SearXNG instance (Docker or native installation)

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio searxng `
  -e SEARXNG_URL=http://localhost:8888 `
  -- npx -y searxng-mcp-server
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio searxng \
  -e SEARXNG_URL=http://localhost:8888 \
  -- npx -y searxng-mcp-server
```

**Note:** Replace `http://localhost:8888` with your SearXNG instance URL. You must have a running SearXNG instance — see the [SearXNG docs](https://docs.searxng.org/admin/installation.html) for setup via Docker or native install.

## Open Brain (Persistent Memory)

Open Brain is a persistent memory MCP server that provides a "second brain" for Claude — storing decisions, insights, and context across sessions in your own Supabase project, with semantic search over them.

- **Project:** https://github.com/dagonet/open-brain
- **Install, keys and the tool list:** [open-brain `docs/mcp.md`](https://github.com/dagonet/open-brain/blob/main/docs/mcp.md). The tool list is deliberately not copied here: it grows with every Open Brain release, and a copy goes stale.

The server is built from a clone of that repository (`npm ci` and `npm run build` in `mcp-server/`) and run with `node <clone>/mcp-server/dist/index.js`; it is not installed with `npx`. Register it at user level as that doc describes, with its keys in the server's `env` block.

**Per-repo settings.** A project's `.mcp.json` (at the repo root) can carry its own `open-brain` entry. That entry replaces the user-level one of the same name in that project, so it needs the keys too. `.mcp.json` is usually committed, so reference the keys as `${VAR}` (Claude Code expands them from your environment) and never write them in literally:

```json
{
  "mcpServers": {
    "open-brain": {
      "command": "node",
      "args": ["/absolute/path/to/open-brain/mcp-server/dist/index.js"],
      "env": {
        "SUPABASE_URL": "${SUPABASE_URL}",
        "SUPABASE_SERVICE_ROLE_KEY": "${SUPABASE_SERVICE_ROLE_KEY}",
        "OPENAI_API_KEY": "${OPENAI_API_KEY}",
        "OPEN_BRAIN_DEFAULT_PROJECT": "my-repo-name"
      }
    }
  }
}
```

- `OPEN_BRAIN_DEFAULT_PROJECT` is the project scope used when a call omits `project`, so sessions in this repo see only its own memories.
- `OPEN_BRAIN_TOOLS_DISABLED` (comma-separated: `wiki`, `contradictions`, `tasks`, `entities`) hides those tool families in this project, for example in a sensitive client repo. The `thoughts_*` tools and `system_status` stay available.

## Context Mode Plugin — not recommended

Context Mode is a third-party Claude Code plugin that offloads tool output to a sandbox and indexes it for search. **As of v3.1.5 the toolkit does not recommend it**, on measurement rather than preference:

- Its routing guidance is delivered **three times per turn** through its own hooks (`SessionStart`, `UserPromptSubmit`) plus a tip on every tool call (`PreToolUse`). The block it also appends to `CLAUDE.md` is a fourth copy of the same text.
- `ctx_batch_execute`, which that guidance names the PRIMARY tool, **failed 28.6 % of calls** across six weeks of measured sessions. **164 dead `ctx_execute` calls** came from subagents that received the guidance but do not have the tools.
- Its MCP launcher (`start.mjs`) **appends a 63-line block to `<project>/CLAUDE.md` on every server spawn** — every session start and every `/mcp` reconnect — unless the file already contains the substring `context-mode`. Under template ownership that is an unauthored out-of-region edit that every sync discards and every spawn re-creates.
- It **blocks `WebFetch`, `curl` and `wget`** to create the need that `ctx_fetch_and_index` fills.
- Its sandbox runs on `/tmp` paths that `git -C` cannot see, so the sync skill already forbids using it for this repo's main job.
- Its post-compaction "session guide" was measured naming the wrong plan file and the wrong mode, the one time it fired in an 11-hour session.

**If you run it anyway, the toolkit is defended.** Every template `CLAUDE.md` and this repo's root carry the literal `context-mode` — the plugin's own idempotency guard — and consistency check 37 asserts the sentinel in all seven files and re-measures the guard predicate in both of the plugin's writers wherever it is installed. `permissions.allow` keeps the tool prefix `mcp__plugin_context-mode_context-mode__*` as a harmless no-op.

**To remove it:** `claude plugins uninstall context-mode@context-mode`, then **restart the session** — a running session keeps the hooks it loaded at startup. `WebFetch` comes back; nothing the toolkit ships calls a `ctx_*` tool.

## Context7 Plugin

The Context7 plugin provides up-to-date library documentation lookup.

- **Install:** `claude plugins install context7@claude-plugins-official`
- **Tools:**
  - `mcp__plugin_context7_context7__resolve-library-id` — find library ID
  - `mcp__plugin_context7_context7__query-docs` — query documentation

---

# Project-Level Servers

These servers are **not** registered at user level. They go into per-project `.mcp.json` files (repo root) so they only load in repos that actually need them — the user-level context stays small.

`setup-project.{sh,ps1}` can generate `.mcp.json` automatically for the dotnet, dotnet-maui, and rust-tauri variants. Pass `--mcp-dev-servers-path <path>` so the script knows where your local `mcp-dev-servers` checkout lives. Optional: `--sqlite-db-path <path>` adds a sqlite entry. See `docs/templates.md` for the per-variant matrix.

If you register these manually instead, the commands below show what each entry looks like.

## SQLite (optional, any variant)

Read-only database inspection via Docker.

**Tools:** `read_query`, `write_query`, `create_table`, `list_tables`, `describe_table`, `append_insight`

**Requires:** Docker Desktop running

**`.mcp.json` entry (Windows):**

```json
{
  "mcpServers": {
    "sqlite": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "C:\\path\\to\\db\\directory:/data:ro",
        "mcp/sqlite-mcp-server",
        "--db-path", "/data/your-database.db"
      ]
    }
  }
}
```

**`.mcp.json` entry (Linux / macOS):**

```json
{
  "mcpServers": {
    "sqlite": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-v", "/home/user/data:/data:ro",
        "mcp/sqlite-mcp-server",
        "--db-path", "/data/your-database.db"
      ]
    }
  }
}
```

**Note:** All templates include the `mcp__sqlite__*` permission in `settings.json`, so no per-project permission changes are needed.

## .NET Tools (19 tools) — dotnet / dotnet-maui variants

.NET build, test, NuGet, EF Core, code metrics. Requires .NET SDK.

**Tools:** `build_and_extract_errors`, `run_tests_summary`, `analyze_namespace_conflicts`, `nuget_list_outdated`, `nuget_check_vulnerabilities`, `nuget_dependency_tree`, `parse_csproj`, `analyze_project_references`, `check_framework_compatibility`, `ef_migrations_status`, `ef_pending_migrations`, `ef_dbcontext_info`, `analyze_method_complexity`, `find_large_files`, `find_god_classes`, `parse_stack_trace`, `parse_coverage_report`, `run_coverage`, `map_dotnet_structure`

**Install:** `claude plugin install dotnet-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

To have it in .NET projects only, enable it per clone (`claude plugin enable dotnet-tools@dagonet --scope local`); `setup-project` does this for the `dotnet` and `dotnet-maui` variants when the plugin is installed.

## Rust Tools (4 tools) — rust-tauri variant

Cargo build, test, and clippy with structured diagnostics. Requires Rust toolchain (rustup).

**Tools:** `cargo_env_info`, `cargo_build`, `cargo_test`, `cargo_clippy`

**Install:** `claude plugin install rust-tools@dagonet` (needs `uv`; see *MCP server plugins* above).

To have it in Rust projects only, enable it per clone (`claude plugin enable rust-tools@dagonet --scope local`); `setup-project` does this for the `rust-tauri` variant when the plugin is installed.

## Windows-MCP — dotnet-maui / rust-tauri variants

Desktop automation for Windows: click, type, screenshot, window management. Used by `tester` agent for UI smoke tests in desktop variants.

**Install via uvx:**

```bash
# uvx must be on PATH — install uv first: https://docs.astral.sh/uv/
uvx --help
```

**`.mcp.json` entry:**

```json
{
  "mcpServers": {
    "windows-mcp": {
      "command": "uvx",
      "args": ["windows-mcp"]
    }
  }
}
```

**Note:** Only useful on Windows. On Linux/macOS this entry is a no-op — the setup script skips it for non-Windows runs.

## Godot Tools (14 tools) — custom setup

Godot game engine editor, scenes, nodes. Not covered by any template variant (there is no godot variant). Listed here for completeness — register manually in a project-level `.mcp.json` (repo root) if you need it.

**Tools:** `launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `get_godot_version`, `list_projects`, `get_project_info`, `create_scene`, `add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `get_uid`, `update_project_uids`

**Requires:** Node.js and Godot 4.x.

**`.mcp.json` entry:**

```json
{
  "mcpServers": {
    "godot-tools": {
      "command": "node",
      "args": ["<your-path>/mcp-godot/godot-mcp/build/index.js"]
    }
  }
}
```

---

## Management Commands

These commands work the same on all platforms:

```bash
# List all registered MCP servers (user + project)
claude mcp list

# Remove a user-level server
claude mcp remove ollama-tools
claude mcp remove git-tools
claude mcp remove github-tools
claude mcp remove template-sync-tools
claude mcp remove searxng
claude mcp remove open-brain
```

Project-level servers are removed by editing or deleting the project's `.mcp.json`.

## Troubleshooting

### Common Issues

1. **MCP server fails to start:** For an mcp-dev-servers plugin: check that `uv` is on PATH, run the warm-up command from *MCP server plugins* once to see the error, and look at `/mcp`. For a venv-based server (template-sync-tools): verify the venv path and that it has `mcp[cli]` and `httpx` installed.
2. **Ollama tools timeout:** Ensure Ollama is running (`ollama --version`) and accessible at `http://127.0.0.1:11434`.
3. **GitHub Tools fail:** Run `gh auth status` to verify GitHub CLI authentication.
4. **Official GitHub plugin shows no tools:** `GITHUB_PERSONAL_ACCESS_TOKEN` is unset, expired, or lacks the required scopes. Set it and restart Claude Code.
5. **dotnet-tools errors in a dotnet project:** Confirm `dotnet --version` returns a valid SDK version (8.0+) and that your `.mcp.json` points at the right `mcp-dev-servers` path.
6. **windows-mcp not loading on a non-Windows machine:** The setup script skips `windows-mcp` on Linux/macOS; if you see an error, check that you regenerated `.mcp.json` after cloning to a new OS.
7. **`uvx: command not found` when loading windows-mcp:** Install `uv` (which provides `uvx`) — see https://docs.astral.sh/uv/.
