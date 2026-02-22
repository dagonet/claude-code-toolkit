# Setup -- Linux & macOS

[Back to README](../README.md)

## Quick Start with Script

Clone this repo, then run the setup script from your **target project directory** (or use `--target-path`).

Make the script executable first:

```bash
chmod +x ~/repos/claude-code-toolkit/setup-project.sh
```

### Examples

```bash
# General project (any language)
~/repos/claude-code-toolkit/setup-project.sh --variant general \
  --project-name "MyProject" \
  --repo-url "https://github.com/user/myproject"

# .NET project
~/repos/claude-code-toolkit/setup-project.sh --variant dotnet \
  --project-name "MyApi" \
  --solution-file "MyApi.sln" \
  --repo-url "https://github.com/user/myapi"

# .NET MAUI desktop app
~/repos/claude-code-toolkit/setup-project.sh --variant dotnet-maui \
  --project-name "MyApp" \
  --solution-file "MyApp.sln" \
  --repo-url "https://github.com/user/myapp" \
  --db-path "$HOME/.local/share/MyApp" \
  --db-filename "myapp.db"

# Rust/Tauri desktop app
~/repos/claude-code-toolkit/setup-project.sh --variant rust-tauri \
  --project-name "MyApp" \
  --repo-url "https://github.com/user/myapp"

# Java project
~/repos/claude-code-toolkit/setup-project.sh --variant java \
  --project-name "MyService" \
  --repo-url "https://github.com/user/myservice"

# Python project
~/repos/claude-code-toolkit/setup-project.sh --variant python \
  --project-name "MyApp" \
  --repo-url "https://github.com/user/myapp"
```

### Target a specific directory

```bash
~/repos/claude-code-toolkit/setup-project.sh --variant general \
  --project-name "MyProject" \
  --target-path ~/projects/MyProject
```

### Flags

- `--dry-run` -- preview what will be copied and replaced without making changes.
- `--force` -- overwrite existing files (by default, existing files are skipped).

The script copies all template files, replaces `{{PLACEHOLDERS}}` with provided values, creates or appends `.gitignore` entries, generates `.claude/template-manifest.json`, and reports any remaining placeholders to fill manually.

## Manual Setup

If you prefer not to use the script:

1. Copy template files from `templates/<variant>/` to your project root:
   ```bash
   cp -r ~/repos/claude-code-toolkit/templates/general/CLAUDE.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/CLAUDE.local.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/AGENT_TEAM.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/PROJECT_CONTEXT.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/PROJECT_STATE.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/.claude/ .claude/
   ```
2. Copy `gitignore` as `.gitignore` (or append entries to your existing one):
   ```bash
   cp ~/repos/claude-code-toolkit/templates/general/gitignore .gitignore
   ```
3. For dotnet/maui/java/python variants, copy the `.editorconfig`:
   ```bash
   cp ~/repos/claude-code-toolkit/templates/dotnet/.editorconfig .
   ```
   For rust-tauri, copy `rustfmt.toml` and `.prettierrc`:
   ```bash
   cp ~/repos/claude-code-toolkit/templates/rust-tauri/rustfmt.toml .
   cp ~/repos/claude-code-toolkit/templates/rust-tauri/.prettierrc .
   ```
4. Fill in `PROJECT_CONTEXT.md` with your project's tech stack, commands, paths, and task source mode.
5. Replace remaining `{{PLACEHOLDERS}}` with actual values. See the [Placeholder Reference](templates.md#placeholder-reference).
6. (Optional) Configure project-level MCP servers in `.claude/.mcp.json`.

## Platform Notes

### Windows-MCP

Windows-MCP is not available on Linux or macOS. If your template references it (rust-tauri and dotnet-maui do), use the **Playwright MCP plugin** instead for browser-based testing. The `windows-mcp` permissions in `settings.json` are harmless no-ops on any platform where the server is not registered.

### MCP Server Paths

Python MCP servers use venv activation. On Linux and macOS the command is:

```bash
source .venv/bin/activate
```

not `.venv\Scripts\Activate.ps1` (Windows). See [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) for Unix registration commands and full setup instructions.

### Docker Paths

Use Unix-style mount paths in SQLite MCP config. For example:

```json
{
  "args": ["-v", "/home/user/data:/data:ro"]
}
```

### .NET MAUI

MAUI desktop apps target Windows only. The dotnet-maui template can still be used on Linux/macOS for project structure, build configuration, and backend logic, but desktop testing features (FlaUI, Windows-MCP automation) will not work.

### SHA-256 Checksums

The bash setup script auto-detects the available hashing tool:
- **Linux**: `sha256sum`
- **macOS**: `shasum -a 256`

No user action is needed; the script selects the correct one at runtime.

## Post-Setup

After applying the template, verify your setup by following the [verification checklist](verification.md).