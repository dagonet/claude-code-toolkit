# Setup — Windows

[Back to README](../README.md)

## Quick Start with Script

Clone this repo, then run `setup-project.ps1` from your **target project directory** (or use `-TargetPath`). The script copies all template files, replaces `{{PLACEHOLDERS}}` with your values, merges `.gitignore`, and generates a template manifest for future syncing.

### Variant Examples

```powershell
# General project (any language)
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant general -ProjectName "MyProject" -RepoUrl "https://github.com/user/myproject"

# .NET project
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant dotnet -ProjectName "MyApi" -SolutionFile "MyApi.sln" -RepoUrl "https://github.com/user/myapi"

# .NET MAUI desktop app
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant dotnet-maui -ProjectName "MyApp" -SolutionFile "MyApp.sln" -RepoUrl "https://github.com/user/myapp" -DbPath "C:\Users\Me\AppData\Local\MyApp\Data" -DbFilename "myapp.db"

# Rust/Tauri desktop app
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant rust-tauri -ProjectName "MyApp" -RepoUrl "https://github.com/user/myapp"

# Java project
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant java -ProjectName "MyService" -RepoUrl "https://github.com/user/myservice"

# Python project
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant python -ProjectName "MyApp" -RepoUrl "https://github.com/user/myapp"
```

### Targeting a Different Directory

If you are not already inside the target project directory, pass `-TargetPath`:

```powershell
.\setup-project.ps1 -Variant general -ProjectName "MyProject" -TargetPath "C:\repos\MyProject"
```

### Useful Flags

| Flag | Purpose |
|------|---------|
| `-DryRun` | Preview which files would be copied and which placeholders would be replaced, without writing anything. |
| `-Force` | Overwrite existing files in the target directory. Without this flag the script skips files that already exist. |

## Manual Setup

If you prefer to set things up by hand:

1. **Copy template files** from `templates\{variant}\` to your project root. This includes `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`, `PROJECT_STATE.md`, and the `.claude\` directory (agents + `settings.json`).

2. **Copy `gitignore` as `.gitignore`** in your project root. If you already have a `.gitignore`, append the entries from the template file instead of overwriting.

3. **Copy style files** if present in the template (`.editorconfig` for dotnet/maui/java/python, `rustfmt.toml` + `.prettierrc` for rust-tauri).

4. **Fill in `PROJECT_CONTEXT.md`** with your project's tech stack, build/test commands, paths, and task source mode.

5. **Replace remaining `{{PLACEHOLDERS}}`** with actual values throughout the copied files. See [templates.md](templates.md) for the full placeholder reference.

6. *(Optional)* Configure project-level MCP servers in `.claude\.mcp.json` if needed.

## Platform Notes

- **Windows-MCP** is available as an optional MCP server for desktop automation testing (used by the `tester` agent in MAUI and Rust/Tauri templates). Register it at user-level in `~\.claude\.mcp.json`.

- **Path separators**: MCP server configurations (`~\.claude\.mcp.json`) typically use backslashes for Windows paths (e.g., `C:\repos\mcp-dev-servers\src\rust_mcp.py`). Most other contexts -- Git, Claude Code, Bash -- accept forward slashes on Windows without issues.

- **PowerShell 5.1+** is pre-installed on Windows 10 and Windows 11. The setup script is compatible with both Windows PowerShell 5.1 and PowerShell 7+.

## Post-Setup

After running the script or completing manual setup, verify everything works. See [verification.md](verification.md) for the full checklist.