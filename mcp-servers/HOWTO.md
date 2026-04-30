[Back to README](../README.md)

# MCP Server Installation Guide

MCP servers in this toolkit are split into two tiers:

- **User-level servers** are registered once in `~/.claude/.mcp.json` and loaded in every project. These are tools you need universally — git, github, ollama, open-brain, etc.
- **Project-level servers** live in a repo's `.claude/.mcp.json` and only load in that project. These are language/framework-specific tools — dotnet, rust, sqlite, windows-mcp — that would bloat the context window if loaded globally.

This guide is split accordingly. For the **why**, see `docs/architecture.md` → *MCP Layering*.

---

## Prerequisites

| Scope | Requirement | Used by |
|---|---|---|
| User | **Python** 3.10+ (in PATH) | All `mcp-dev-servers` python servers |
| User | **GitHub CLI** (`gh`) installed + authenticated | `github-tools` |
| User | **GitHub Personal Access Token** (`GITHUB_PERSONAL_ACCESS_TOKEN` env var) | Official GitHub plugin |
| User | **Node.js** 18+ | SearXNG MCP, Open Brain |
| Project (dotnet) | **.NET SDK** 8.0+ | `dotnet-tools` |
| Project (rust-tauri) | **Rust toolchain** (rustup, cargo, rustc) | `rust-tools` |
| Project (optional) | **Docker Desktop** running | `sqlite` |
| Project (dotnet-maui / rust-tauri) | **uv/uvx** in PATH | `windows-mcp` |

## Python MCP Servers Source

The custom Python MCP servers live in a separate repository:

- **Repository:** https://github.com/dagonet/mcp-dev-servers
- **95 tools** across 7 servers
- See that repo's README for full tool reference

## Python Virtual Environment Setup

All custom Python MCP servers (user-level and project-level alike) run from a shared Python virtual environment. `pip install -e ".[ollama]"` installs `mcp-dev-servers` in editable mode and exposes 7 console scripts (`mcp-git-tools`, `mcp-github-tools`, `mcp-dotnet-tools`, `mcp-ollama-tools`, `mcp-rust-tools`, `mcp-template-sync-tools`, `mcp-python-tools`) inside the venv. The `[ollama]` extra pulls `httpx`; drop it if you don't run Ollama.

> **Invariant:** the venv MUST live at `<mcp-dev-servers>/.venv/` (the literal directory name `.venv` inside the repo root). Both `setup-project.{ps1,sh}` and the user-level `.mcp.json.template` hardcode this relative path. Naming the venv `env/`, placing it outside the repo, or installing via `pipx` will break project-level MCP registration silently.

**Windows (PowerShell):**

```powershell
git clone https://github.com/dagonet/mcp-dev-servers.git <your-path>\mcp-dev-servers
cd <your-path>\mcp-dev-servers
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -e ".[ollama]"
```

**Linux / macOS:**

```bash
git clone https://github.com/dagonet/mcp-dev-servers.git ~/repos/mcp-dev-servers
cd ~/repos/mcp-dev-servers
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[ollama]"
```

---

## Migrating from pre-packaging install

If you set up `mcp-dev-servers` **before 2026-04-21** (when it became a packaged Python project), module paths have changed and the install command is different. Update your local clone:

```bash
cd <your-mcp-dev-servers-path>
git pull
# activate the venv first
#   Windows: .\.venv\Scripts\Activate.ps1
#   Linux:   source .venv/bin/activate
pip install -e ".[ollama]"
```

Then:

- **Project-level `.claude/.mcp.json`** files: re-run `setup-project.{sh,ps1}` against each project to regenerate them with the new console-script paths.
- **User-level registrations**: for each server you added with `claude mcp add`, run `claude mcp remove <name> -s user` and re-add it using the `mcp-<name>-tools(.exe)` console-script path shown in the install snippets below.

Old paths like `<path>/src/git_mcp.py` no longer exist — Claude Code will report each affected server as `Failed to connect` until re-registered.

---

## Ollama Setup

### Installation

1. Download and install from https://ollama.com/
2. Verify: `ollama --version`
3. Check loaded models: `ollama list`

### Recommended Models

```bash
# Default model
ollama pull llama3.2:latest

# Optimized models (recommended)
ollama pull qwen2.5:7b-instruct-q4_K_M    # JSON extraction
ollama pull mistral:7b-instruct-q4_K_M     # Text compression
ollama pull phi3:mini                       # Fast inference

# Vision model (for screenshot analysis)
ollama pull llava:7b
```

### Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `OLLAMA_KEEP_ALIVE` | `1h` (or `-1` for always loaded) | How long models stay in VRAM |
| `OLLAMA_MAX_LOADED_MODELS` | `3` | Max concurrent models in VRAM |
| `OLLAMA_NUM_PARALLEL` | `1` | Parallel request handling |

**Windows:** Set as User environment variables via System Properties > Environment Variables, or:

```powershell
[System.Environment]::SetEnvironmentVariable('OLLAMA_KEEP_ALIVE', '1h', 'User')
[System.Environment]::SetEnvironmentVariable('OLLAMA_MAX_LOADED_MODELS', '3', 'User')
[System.Environment]::SetEnvironmentVariable('OLLAMA_NUM_PARALLEL', '1', 'User')
```

**Linux / macOS:** Add to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.):

```bash
export OLLAMA_KEEP_ALIVE="1h"
export OLLAMA_MAX_LOADED_MODELS="3"
export OLLAMA_NUM_PARALLEL="1"
```

---

# User-Level Servers

Register these **once** with `claude mcp add --scope user`. They load in every project.

## Ollama Tools (6 tools)

Local LLM preprocessing: health check, model management, text compression, JSON extraction, project mapping.

**Tools:** `ollama_health`, `ollama_list_models`, `warm_models`, `local_first_pass`, `extract_json`, `map_project_structure`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio ollama-tools `
  -e OLLAMA_URL=http://127.0.0.1:11434 `
  -e OLLAMA_MODEL_FIRST_PASS=mistral:7b-instruct-q4_K_M `
  -e OLLAMA_MODEL_EXTRACT_JSON=qwen2.5:7b-instruct-q4_K_M `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\mcp-ollama-tools.exe"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio ollama-tools \
  -e OLLAMA_URL=http://127.0.0.1:11434 \
  -e OLLAMA_MODEL_FIRST_PASS=mistral:7b-instruct-q4_K_M \
  -e OLLAMA_MODEL_EXTRACT_JSON=qwen2.5:7b-instruct-q4_K_M \
  -- ~/repos/mcp-dev-servers/.venv/bin/mcp-ollama-tools
```

## Git Tools (34 tools)

Git operations via MCP: status, diff, log, add, commit, tag, branch, checkout, push, pull, fetch, reset, rebase, stash, restore, worktree, config, archive, describe, revert, reflog, clean-dry-run.

**Key tools:** `git_status`, `git_add`, `git_rm`, `git_commit`, `git_diff`, `git_diff_summary`, `git_log`, `git_branch_list`, `git_branch_create`, `git_branch_delete`, `git_checkout`, `git_pull`, `git_push` (with `--tags` support), `git_fetch`, `git_reset`, `git_rebase` (non-interactive only), `git_stash`, `git_remote_list`, `git_tag_list`, `git_tag_create`, `git_tag_delete`, `git_describe`, `git_revert`, `git_archive`, `git_config_get`, `git_config_set`, `git_restore`, `git_clean_dry_run`, `git_reflog`, `git_show`, `git_worktree_list`, `git_worktree_add`, `git_worktree_remove`, `git_env_info`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio git-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\mcp-git-tools.exe"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio git-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/mcp-git-tools
```

## GitHub Tools (17 tools)

Custom GitHub utilities not covered by the official plugin — release management, workflow dispatch/monitoring, PR hygiene, and more.

**Tools:** `gh_repo_from_origin`, `gh_workflow_list`, `github_release_create` (draft by default), `github_release_edit` (use `draft=false` to publish), `github_release_delete` (name-match guard), `github_release_upload_asset`, `github_release_delete_asset`, `github_workflow_dispatch`, `github_workflow_run_wait`, `github_workflow_run_rerun`, `github_workflow_run_cancel`, `github_check_runs_for_sha`, `github_branch_protection_get`, `github_pr_label_add`, `github_pr_label_remove`, `github_pr_request_review`, `github_pr_auto_merge`

**Requires:** GitHub CLI (`gh`) installed and authenticated

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio github-tools `
  -e GH_PROMPT_DISABLED=1 `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\mcp-github-tools.exe"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio github-tools \
  -e GH_PROMPT_DISABLED=1 \
  -- ~/repos/mcp-dev-servers/.venv/bin/mcp-github-tools
```

## Python Tools (7 tools)

Python development workflows: wheel and sdist inspection, smoke install (throwaway venv), pytest with typed output, ruff (lint + format), uv build, coverage.

**Tools:** `wheel_inspect`, `sdist_inspect`, `python_smoke_install`, `uv_build`, `pytest_run`, `ruff` (mode: check/format), `coverage` (merged collect + report)

**Requires:** `uv`, `pytest`, `ruff`, `coverage` in the project environment; Python 3.11+

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio python-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\mcp-python-tools.exe"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio python-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/mcp-python-tools
```

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

## Template Sync Tools (8 tools)

Deterministic template syncing: manifest management, file status computation, three-way merge, placeholder replacement/reversal, cross-variant propagation. Used by the `/sync-template` and `/contribute-upstream` skills.

**Tools:** `template_load_manifest`, `template_compute_status`, `template_get_diff`, `template_apply_file`, `template_finalize_sync`, `template_reverse_placeholders`, `template_check_cross_variant`, `template_propagate_to_variants`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio template-sync-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\mcp-template-sync-tools.exe"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio template-sync-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/mcp-template-sync-tools
```

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

Open Brain is a persistent memory MCP server that provides a "second brain" for Claude — storing decisions, insights, and context across sessions.

- **Project:** https://github.com/dagonet/open-brain (check for latest installation instructions)
- **Tools (14 total):**
  - **Thoughts:** `thoughts_capture`, `thoughts_search`, `thoughts_topics`, `thoughts_people`, `thoughts_recent`, `thoughts_review`, `thoughts_delete`, `system_status`
  - **Wiki:** `wiki_get`, `wiki_list`, `wiki_refresh`
  - **Contradictions:** `contradictions_list`, `contradictions_resolve`, `contradictions_audit`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio open-brain `
  -- npx -y open-brain-mcp
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio open-brain \
  -- npx -y open-brain-mcp
```

**Note:** Check the project repository for the latest installation method — the command and package name may vary. Open Brain stores data locally and provides semantic search over captured thoughts.

**Per-repo opt-out (v0.3.0+):** if a particular project shouldn't see the wiki and contradictions tool families, add `"OPEN_BRAIN_TOOLS_DISABLED": "wiki,contradictions"` to the open-brain server's `env` block in that project's `.mcp.json`. The MCP server filters those families from `tools/list`; the `thoughts_*` tools and `system_status` remain available.

## Context Mode Plugin

Context Mode is a Claude Code plugin that offloads large tool outputs to a sandbox, keeping the context window clean and reducing token usage. It intercepts tool calls that would produce large outputs and processes them externally, returning only concise summaries to the conversation.

- **Install:** `claude plugins install context-mode@context-mode`

**Key tools:**
- `ctx_execute(language, code)` — Run code in sandbox, return summary
- `ctx_execute_file(path, language, code)` — Run code against a file in sandbox
- `ctx_search(queries)` — Search indexed content with multiple queries
- `ctx_batch_execute(commands, queries)` — Run commands + search in one call
- `ctx_fetch_and_index(url)` — Fetch and index a URL for later searching
- `ctx_index(label, content)` — Index content for later searching
- `ctx_stats()` — Show context savings statistics
- `ctx_doctor()` — Diagnose installation and configuration

**Tool prefix:** `mcp__plugin_context-mode_context-mode__*`

## Context7 Plugin

The Context7 plugin provides up-to-date library documentation lookup.

- **Install:** `claude plugins install context7@claude-plugins-official`
- **Tools:**
  - `mcp__plugin_context7_context7__resolve-library-id` — find library ID
  - `mcp__plugin_context7_context7__query-docs` — query documentation

---

# Project-Level Servers

These servers are **not** registered at user level. They go into per-project `.claude/.mcp.json` files so they only load in repos that actually need them — the user-level context stays small.

`setup-project.{sh,ps1}` can generate `.claude/.mcp.json` automatically for the dotnet, dotnet-maui, and rust-tauri variants. Pass `--mcp-dev-servers-path <path>` so the script knows where your local `mcp-dev-servers` checkout lives. Optional: `--sqlite-db-path <path>` adds a sqlite entry. See `docs/templates.md` for the per-variant matrix.

If you register these manually instead, the commands below show what each entry looks like.

## SQLite (optional, any variant)

Read-only database inspection via Docker.

**Tools:** `read_query`, `write_query`, `create_table`, `list_tables`, `describe_table`, `append_insight`

**Requires:** Docker Desktop running

**`.claude/.mcp.json` entry (Windows):**

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

**`.claude/.mcp.json` entry (Linux / macOS):**

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

**`.claude/.mcp.json` entry:**

```json
{
  "mcpServers": {
    "dotnet-tools": {
      "command": "<mcp-dev-servers-path>/.venv/bin/mcp-dotnet-tools"
    }
  }
}
```

Replace `<mcp-dev-servers-path>` with the absolute path to your local `mcp-dev-servers` repo. On Windows use `<path>\.venv\Scripts\mcp-dotnet-tools.exe`.

## Rust Tools (4 tools) — rust-tauri variant

Cargo build, test, and clippy with structured diagnostics. Requires Rust toolchain (rustup).

**Tools:** `cargo_env_info`, `cargo_build`, `cargo_test`, `cargo_clippy`

**`.claude/.mcp.json` entry:**

```json
{
  "mcpServers": {
    "rust-tools": {
      "command": "<mcp-dev-servers-path>/.venv/bin/mcp-rust-tools"
    }
  }
}
```

## Windows-MCP — dotnet-maui / rust-tauri variants

Desktop automation for Windows: click, type, screenshot, window management. Used by `tester` agent for UI smoke tests in desktop variants.

**Install via uvx:**

```bash
# uvx must be on PATH — install uv first: https://docs.astral.sh/uv/
uvx --help
```

**`.claude/.mcp.json` entry:**

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

Godot game engine editor, scenes, nodes. Not covered by any template variant (there is no godot variant). Listed here for completeness — register manually in a project-level `.claude/.mcp.json` if you need it.

**Tools:** `launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `get_godot_version`, `list_projects`, `get_project_info`, `create_scene`, `add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `get_uid`, `update_project_uids`

**Requires:** Node.js and Godot 4.x.

**`.claude/.mcp.json` entry:**

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

Project-level servers are removed by editing or deleting the project's `.claude/.mcp.json`.

## Troubleshooting

### Common Issues

1. **MCP server fails to start:** Verify the Python virtual environment path is correct and the `.venv` has `mcp[cli]` and `httpx` installed.
2. **Ollama tools timeout:** Ensure Ollama is running (`ollama --version`) and accessible at `http://127.0.0.1:11434`.
3. **GitHub Tools fail:** Run `gh auth status` to verify GitHub CLI authentication.
4. **Official GitHub plugin shows no tools:** `GITHUB_PERSONAL_ACCESS_TOKEN` is unset, expired, or lacks the required scopes. Set it and restart Claude Code.
5. **dotnet-tools errors in a dotnet project:** Confirm `dotnet --version` returns a valid SDK version (8.0+) and that your `.claude/.mcp.json` points at the right `mcp-dev-servers` path.
6. **windows-mcp not loading on a non-Windows machine:** The setup script skips `windows-mcp` on Linux/macOS; if you see an error, check that you regenerated `.claude/.mcp.json` after cloning to a new OS.
7. **`uvx: command not found` when loading windows-mcp:** Install `uv` (which provides `uvx`) — see https://docs.astral.sh/uv/.
