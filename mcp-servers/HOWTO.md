[Back to README](../README.md)

# MCP Server Installation Guide

## Prerequisites

- **Python** 3.10+ (from python.org or system package manager, must be in PATH)
- **Node.js** 18+ (for Godot MCP only)
- **.NET SDK** 8.0+ (for dotnet-tools)
- **Rust toolchain** (rustup, cargo, rustc) - for rust-tools
- **GitHub CLI** (`gh`) installed and authenticated (for github-tools)
- **Docker** (for SQLite MCP server, any project with SQLite)

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

On Linux with systemd-managed Ollama, you can also set these via `systemctl edit ollama.service`:

```ini
[Service]
Environment="OLLAMA_KEEP_ALIVE=1h"
Environment="OLLAMA_MAX_LOADED_MODELS=3"
Environment="OLLAMA_NUM_PARALLEL=1"
```

## Python MCP Servers Source

The 4 custom Python MCP servers (git-tools, github-tools, dotnet-tools, ollama-tools) live in a separate repository:

- **Repository:** https://github.com/dagonet/mcp-dev-servers
- **47 tools** across 5 servers
- See that repo's README for full tool reference

## Python Virtual Environment Setup

All custom MCP servers run from a shared Python virtual environment.

**Windows (PowerShell):**

```powershell
git clone https://github.com/dagonet/mcp-dev-servers.git <your-path>\mcp-dev-servers
cd <your-path>\mcp-dev-servers
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

**Linux / macOS:**

```bash
git clone https://github.com/dagonet/mcp-dev-servers.git ~/repos/mcp-dev-servers
cd ~/repos/mcp-dev-servers
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## MCP Server Registration

### Ollama Tools (6 tools)

Local LLM preprocessing: health check, model management, text compression, JSON extraction, project mapping.

**Tools:** `ollama_health`, `ollama_list_models`, `warm_models`, `local_first_pass`, `extract_json`, `map_project_structure`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio ollama-tools `
  -e OLLAMA_URL=http://127.0.0.1:11434 `
  -e OLLAMA_MODEL_FIRST_PASS=mistral:7b-instruct-q4_K_M `
  -e OLLAMA_MODEL_EXTRACT_JSON=qwen2.5:7b-instruct-q4_K_M `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\python.exe" "<your-path>\mcp-dev-servers\src\ollama_mcp.py"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio ollama-tools \
  -e OLLAMA_URL=http://127.0.0.1:11434 \
  -e OLLAMA_MODEL_FIRST_PASS=mistral:7b-instruct-q4_K_M \
  -e OLLAMA_MODEL_EXTRACT_JSON=qwen2.5:7b-instruct-q4_K_M \
  -- ~/repos/mcp-dev-servers/.venv/bin/python ~/repos/mcp-dev-servers/src/ollama_mcp.py
```

### Git Tools (16 tools)

Git operations via MCP: status, diff, log, add, commit, branch, checkout, push, pull, stash.

**Tools:** `git_status`, `git_add`, `git_rm`, `git_commit`, `git_diff`, `git_diff_summary`, `git_log`, `git_branch_list`, `git_checkout`, `git_pull`, `git_push`, `git_stash`, `git_remote_list`, `git_tag_list`, `git_show`, `git_env_info`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio git-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\python.exe" "<your-path>\mcp-dev-servers\src\git_mcp.py"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio git-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/python ~/repos/mcp-dev-servers/src/git_mcp.py
```

### GitHub Tools (2 tools)

Custom GitHub utilities not available in the official GitHub MCP server.

**Tools:** `gh_repo_from_origin` (get OWNER/REPO from local git remote), `gh_workflow_list` (list GitHub Actions workflow runs)

**Requires:** GitHub CLI (`gh`) installed and authenticated

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio github-tools `
  -e GH_PROMPT_DISABLED=1 `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\python.exe" "<your-path>\mcp-dev-servers\src\github_mcp.py"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio github-tools \
  -e GH_PROMPT_DISABLED=1 \
  -- ~/repos/mcp-dev-servers/.venv/bin/python ~/repos/mcp-dev-servers/src/github_mcp.py
```

### Rust Tools (4 tools)

Cargo build, test, and clippy with structured diagnostics. Requires Rust toolchain (rustup).

**Tools:** `cargo_env_info`, `cargo_build`, `cargo_test`, `cargo_clippy`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio rust-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\python.exe" "<your-path>\mcp-dev-servers\src\rust_mcp.py"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio rust-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/python ~/repos/mcp-dev-servers/src/rust_mcp.py
```

### .NET Tools (19 tools)

.NET build, test, NuGet, EF Core, code metrics. Requires .NET SDK.

**Tools:** `build_and_extract_errors`, `run_tests_summary`, `analyze_namespace_conflicts`, `nuget_list_outdated`, `nuget_check_vulnerabilities`, `nuget_dependency_tree`, `parse_csproj`, `analyze_project_references`, `check_framework_compatibility`, `ef_migrations_status`, `ef_pending_migrations`, `ef_dbcontext_info`, `analyze_method_complexity`, `find_large_files`, `find_god_classes`, `parse_stack_trace`, `parse_coverage_report`, `run_coverage`, `map_dotnet_structure`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio dotnet-tools `
  -- "<your-path>\mcp-dev-servers\.venv\Scripts\python.exe" "<your-path>\mcp-dev-servers\src\dotnet_mcp.py"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio dotnet-tools \
  -- ~/repos/mcp-dev-servers/.venv/bin/python ~/repos/mcp-dev-servers/src/dotnet_mcp.py
```

### SQLite MCP Server

Read-only database inspection via Docker. Useful for any project with a SQLite database.

**Tools:** `read_query`, `write_query`, `create_table`, `list_tables`, `describe_table`, `append_insight`

**Requires:** Docker Desktop running

Add to user-level MCP config (`~/.claude/.mcp.json`) with your project's DB path:

**Windows:**

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

**Linux / macOS:**

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

**Note:** The DB path is project-specific. Update the `-v` mount path and `--db-path` filename when switching between projects. All templates include SQLite permissions in `settings.json`, so no per-project permission changes are needed.

### Godot Tools (14 tools)

Godot game engine editor, scenes, nodes. Requires Node.js and Godot 4.x.

**Tools:** `launch_editor`, `run_project`, `get_debug_output`, `stop_project`, `get_godot_version`, `list_projects`, `get_project_info`, `create_scene`, `add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `get_uid`, `update_project_uids`

**Windows (PowerShell):**

```powershell
claude mcp add --scope user --transport stdio godot-tools `
  -- node "<your-path>\mcp-godot\godot-mcp\build\index.js"
```

**Linux / macOS:**

```bash
claude mcp add --scope user --transport stdio godot-tools \
  -- node ~/mcp/mcp-godot/godot-mcp/build/index.js
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

- **Project:** https://github.com/open-brain/open-brain (check for latest installation instructions)
- **Tools:** `capture_thought`, `semantic_search`, `list_topics`, `list_people`, `list_recent`, `weekly_review`, `delete_thought`, `system_status`

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

## Official GitHub MCP Server (40+ tools)

For most GitHub operations (issues, PRs, releases, code search), use the official server:

- **Repository:** https://github.com/github/github-mcp-server
- Follow the installation instructions at that repository
- Provides comprehensive GitHub integration beyond the 2 custom tools above

## Context Mode Plugin

Context Mode is a Claude Code plugin that offloads large tool outputs to a sandbox, keeping the context window clean and reducing token usage. It intercepts tool calls that would produce large outputs and processes them externally, returning only concise summaries to the conversation.

- **Installation:** Installed as a Claude Code plugin, not via `claude mcp add`
- **Install command:** `claude plugins add context-mode` (or install from the Claude Code marketplace)

**Key tools:**
- `ctx_execute(language, code)` -- Run code in sandbox, return summary
- `ctx_execute_file(path, language, code)` -- Run code against a file in sandbox
- `ctx_search(queries)` -- Search indexed content with multiple queries
- `ctx_batch_execute(commands, queries)` -- Run commands + search in one call
- `ctx_fetch_and_index(url)` -- Fetch and index a URL for later searching
- `ctx_index(label, content)` -- Index content for later searching
- `ctx_stats()` -- Show context savings statistics
- `ctx_doctor()` -- Diagnose installation and configuration

**Note:** Context Mode provides both MCP tools and hooks (PreToolUse for routing large outputs). Since it is a plugin, permissions use the `mcp__plugin_context-mode_context-mode__*` pattern in `settings.json`.

## Context7 Plugin

The Context7 plugin provides library documentation lookup. Enable it in Claude Code settings:

- `mcp__plugin_context7_context7__resolve-library-id` - Find library ID
- `mcp__plugin_context7_context7__query-docs` - Query documentation

## Management Commands

These commands work the same on all platforms:

```bash
# List all registered MCP servers
claude mcp list

# Remove a server
claude mcp remove ollama-tools
claude mcp remove git-tools
claude mcp remove github-tools
claude mcp remove rust-tools
claude mcp remove dotnet-tools
claude mcp remove godot-tools
```

## Troubleshooting

### Common Issues

1. **MCP server fails to start:** Verify the Python virtual environment path is correct and the `.venv` has `mcp[cli]` and `httpx` installed.
2. **Ollama tools timeout:** Ensure Ollama is running (`ollama --version`) and accessible at `http://127.0.0.1:11434`.
3. **GitHub tools fail:** Run `gh auth status` to verify GitHub CLI authentication.
4. **dotnet-tools errors:** Confirm `dotnet --version` returns a valid SDK version (8.0+).
5. **Godot tools not found:** Verify Node.js is installed and the Godot MCP build path exists.
