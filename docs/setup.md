[Back to README](../README.md)

# Setup Walkthrough

Detailed instructions for running `setup-project.{sh,ps1}` against a target project, plus a manual fallback. For prerequisites and adoption tiers see [`getting-started.md`](getting-started.md). For per-variant flag details see [`templates.md`](templates.md). For MCP server installation see [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md).

## Quick Start

Clone this repo, then run the setup script from your **target project directory** (or pass `--target-path` / `-TargetPath`).

The script copies all template files, replaces `{{PLACEHOLDERS}}` with your values, creates or merges `.gitignore`, generates `.claude/template-manifest.json`, and reports any remaining placeholders to fill manually.

### Per-variant examples

The Linux/macOS and Windows commands are equivalent — pick the one for your shell.

#### `general` — any language

**Bash (Linux / macOS / Git Bash):**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant general \
  --project-name "MyProject" \
  --repo-url "https://github.com/user/myproject"
```

**PowerShell (Windows):**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant general `
  -ProjectName "MyProject" `
  -RepoUrl "https://github.com/user/myproject"
```

#### `dotnet` — C#/.NET

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant dotnet \
  --project-name "MyApi" \
  --solution-file "MyApi.sln" \
  --repo-url "https://github.com/user/myapi"
```

**PowerShell:**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant dotnet `
  -ProjectName "MyApi" `
  -SolutionFile "MyApi.sln" `
  -RepoUrl "https://github.com/user/myapi"
```

#### `dotnet-maui` — .NET MAUI desktop

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant dotnet-maui \
  --project-name "MyApp" \
  --solution-file "MyApp.sln" \
  --repo-url "https://github.com/user/myapp" \
  --db-path "$HOME/.local/share/MyApp" \
  --db-filename "myapp.db"
```

**PowerShell:**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant dotnet-maui `
  -ProjectName "MyApp" `
  -SolutionFile "MyApp.sln" `
  -RepoUrl "https://github.com/user/myapp" `
  -DbPath "C:\Users\Me\AppData\Local\MyApp\Data" `
  -DbFilename "myapp.db"
```

#### `rust-tauri` — Rust + Tauri v2 desktop

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant rust-tauri \
  --project-name "MyApp" \
  --repo-url "https://github.com/user/myapp"
```

**PowerShell:**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant rust-tauri `
  -ProjectName "MyApp" `
  -RepoUrl "https://github.com/user/myapp"
```

#### `java` — Java (Maven or Gradle)

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant java \
  --project-name "MyService" \
  --build-tool gradle \
  --java-version 21 \
  --repo-url "https://github.com/user/myservice"
```

**PowerShell:**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant java `
  -ProjectName "MyService" `
  -BuildTool gradle `
  -JavaVersion 21 `
  -RepoUrl "https://github.com/user/myservice"
```

#### `python` — Python 3.11+

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant python \
  --project-name "MyApp" \
  --package-manager poetry \
  --python-version 3.12 \
  --repo-url "https://github.com/user/myapp"
```

**PowerShell:**
```powershell
C:\repos\claude-code-toolkit\setup-project.ps1 -Variant python `
  -ProjectName "MyApp" `
  -PackageManager poetry `
  -PythonVersion 3.12 `
  -RepoUrl "https://github.com/user/myapp"
```

### Targeting a different directory

If you are not already inside the target project directory, pass `--target-path` (Bash) or `-TargetPath` (PowerShell):

**Bash:**
```bash
~/repos/claude-code-toolkit/setup-project.sh --variant general \
  --project-name "MyProject" \
  --target-path ~/projects/MyProject
```

**PowerShell:**
```powershell
.\setup-project.ps1 -Variant general -ProjectName "MyProject" -TargetPath "C:\repos\MyProject"
```

### Useful flags

Bash flags use `--kebab-case`; PowerShell uses `-PascalCase`. Both scripts accept the same set:

| Bash flag | PowerShell flag | Purpose |
|---|---|---|
| `--dry-run` | `-DryRun` | Preview which files would be copied and which placeholders would be replaced, without writing anything. |
| `--force` | `-Force` | Overwrite existing files in the target directory (default: skip existing). |
| `--mcp-dev-servers-path <path>` | `-McpDevServersPath <path>` | Path to a local clone of [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers). Required for `dotnet`, `dotnet-maui`, `rust-tauri` variants to generate project-level `dotnet-tools` / `rust-tools`. |
| `--sqlite-db-path <path>` | `-SqliteDbPath <path>` | Optional; generates a project-level `sqlite` MCP entry for any variant. |

See [`templates.md`](templates.md#project-level-mcp-matrix) for the per-variant project-level MCP matrix.

### Make the bash script executable (first time only)

```bash
chmod +x ~/repos/claude-code-toolkit/setup-project.sh
```

## Manual Setup

If you prefer to set things up by hand:

1. **Copy template files** from `templates/<variant>/` to your project root. This includes `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`, `PROJECT_STATE.md`, and the `.claude/` directory (agents + `settings.json`).

   ```bash
   # Bash
   cp -r ~/repos/claude-code-toolkit/templates/general/CLAUDE.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/CLAUDE.local.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/AGENT_TEAM.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/PROJECT_CONTEXT.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/PROJECT_STATE.md .
   cp -r ~/repos/claude-code-toolkit/templates/general/.claude/ .claude/
   ```

2. **Copy `gitignore` as `.gitignore`** in your project root. If you already have a `.gitignore`, append the entries from the template file instead of overwriting.

3. **Copy style files** if present in the template (`.editorconfig` for `dotnet` / `dotnet-maui` / `java` / `python`, `rustfmt.toml` + `.prettierrc` for `rust-tauri`).

4. **Fill in `PROJECT_CONTEXT.md`** with your project's tech stack, build/test commands, paths, and task source mode.

5. **Replace remaining `{{PLACEHOLDERS}}`** with actual values throughout the copied files. See [`templates.md`](templates.md#placeholder-reference) for the full reference.

6. *(Optional)* Configure project-level MCP servers in `.claude/.mcp.json` if needed.

## Platform Notes

### Windows

- **PowerShell 5.1+** is pre-installed on Windows 10 and 11. The setup script is compatible with both Windows PowerShell 5.1 and PowerShell 7+.
- **Path separators**: MCP server configurations (`~\.claude\.mcp.json`) typically use backslashes for Windows paths. Most other contexts (Git, Claude Code, Bash) accept forward slashes on Windows without issues.
- **Windows-MCP** is auto-configured for `dotnet-maui` and `rust-tauri` variants via `uvx windows-mcp` (project-level). Used by the `tester` agent for desktop UI smoke tests.

### Linux / macOS

- **Windows-MCP** is not available — the generated `.claude/.mcp.json` entry will fail to load but will not break anything else. For browser-based testing, use the **Playwright MCP plugin** instead.
- **Docker paths** in SQLite MCP config use Unix-style mount paths:
  ```json
  { "args": ["-v", "/home/user/data:/data:ro"] }
  ```
- **.NET MAUI** desktop apps target Windows only. The `dotnet-maui` template can still be used on Linux/macOS for project structure, build configuration, and backend logic, but desktop testing features (FlaUI, Windows-MCP automation) will not work.
- **SHA-256 checksums**: the bash setup script auto-detects `sha256sum` (Linux) or `shasum -a 256` (macOS).

### MCP server paths

Python MCP servers run from a venv at `<mcp-dev-servers>/.venv/`. Activation differs per OS:

```powershell
# Windows
.\.venv\Scripts\Activate.ps1
```

```bash
# Linux / macOS
source .venv/bin/activate
```

See [`../mcp-servers/HOWTO.md`](../mcp-servers/HOWTO.md) for full registration commands.

## Post-setup

After running the script or completing manual setup, verify everything works. See [`verification.md`](verification.md) for the full checklist.
