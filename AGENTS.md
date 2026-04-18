# AGENTS.md — Agent-Guided Project Setup

This file guides an AI coding agent (Claude Code, Cursor, Copilot CLI, OpenAI Codex, etc.) through bootstrapping a new project from this toolkit's templates.

**Scope:** the agent conducts interactive Q&A with the user, then invokes `setup-project.sh` or `setup-project.ps1` — the scripts remain the source of truth for deterministic operations (placeholder substitution, `.gitignore` merge, directory layout). The agent never derives build/test commands itself; it passes user answers to the script.

---

## 1. Prerequisites

Before starting, confirm the following are on PATH:

- `git` (any recent version)
- **One** shell:
  - Linux / macOS / Git Bash on Windows → `bash`
  - Native Windows → `pwsh` (PowerShell 7+) **or** Windows PowerShell 5.1
- The target directory for the new project exists (or can be created) and is writable.

If any prerequisite is missing, stop and tell the user what to install — do not attempt to install tools on the user's behalf.

---

## 2. OS / shell detection

Pick the correct script based on the active shell:

| Shell probe | Script to invoke |
|---|---|
| `bash --version` succeeds | `./setup-project.sh` |
| `pwsh -Version` or PowerShell host variable `$PSVersionTable` is set | `.\setup-project.ps1` |

On Windows the user may have both — prefer `bash` if the user is already in Git Bash; prefer `pwsh` otherwise.

Run the script from the **repo root** (this file's directory), not from the target project directory.

---

## 3. Variant selection

Ask the user which variant to use. If they don't know, summarize the choices with the table below — do not guess.

| Variant | Use when |
|---|---|
| `general` | Any language/stack not covered by a specialized variant |
| `dotnet` | .NET 8+ backend, console, or ASP.NET Core |
| `dotnet-maui` | .NET MAUI cross-platform app |
| `rust-tauri` | Rust backend + Tauri desktop shell |
| `java` | Java (Maven or Gradle, Spring Boot assumed as default) |
| `python` | Python 3.11+ (pip, Poetry, or uv) |

---

## 4. Interactive Q&A

Collect answers before running the script. Ask only questions relevant to the chosen variant. **Do not compute `BUILD_COMMAND` / `TEST_COMMAND` / `FORMAT_COMMAND` yourself — the script derives those from the user's answers.**

### Always ask

- **Project name** (e.g. `MyApp`) → `--project-name`
- **Target path** (where the project will live; default is current dir) → `--target-path`
- **Repo URL** (optional; can be added later) → `--repo-url`

### Variant-specific

**`dotnet` / `dotnet-maui`:**

- **Solution file** (e.g. `MyApp.sln`) → `--solution-file`
- *(dotnet-maui only)* **MAUI project name** → `--maui-project`
- *(dotnet-maui only)* **Test project name** → `--test-project`
- *(optional)* **SQLite DB directory + filename** → `--db-path` / `--db-filename`

**`java`:**

- **Build tool**: `maven` or `gradle` (default: maven) → `--build-tool`
- **Java version** (default: 21) → `--java-version`

**`python`:**

- **Package manager**: `pip`, `poetry`, or `uv` (default: pip) → `--package-manager`
- **Python version** (default: 3.12) → `--python-version`

**`rust-tauri` / `general`:** no additional questions.

### Optional (all variants)

- **Worktree base path** → `--worktree-base`
- **Log path** → `--log-path`
- **Tech stack blurb** → `--tech-stack`

---

## 5. Script invocation

1. **Construct the command** using the answers collected above. One flag per answer. Do not invent flags.

2. **Dry-run first.** Append `--dry-run` to the command and run it. Show the user the output (files that would be touched, placeholders that would be substituted).

3. **Confirm.** Ask the user to approve the dry-run output before running for real. If they say no, adjust answers and repeat step 2.

4. **Run for real.** Drop `--dry-run` and re-execute. Surface the script's exit code — non-zero means abort and report the error verbatim.

### Examples

```bash
# general variant, bash
./setup-project.sh --variant general --project-name MyApp --target-path ../my-app --repo-url https://github.com/me/my-app

# java + gradle, bash
./setup-project.sh --variant java --project-name MyService --build-tool gradle --java-version 21

# python + poetry, PowerShell
.\setup-project.ps1 -Variant python -ProjectName MyApp -PackageManager poetry -PythonVersion 3.12
```

---

## 6. Post-setup verification

After the script exits 0:

1. **Manifest written.** Confirm `.claude-setup-manifest.json` exists in the target directory.
2. **No unfilled placeholders.** Run `grep -r '{{' <target-dir>` — expect no matches in `.claude/`, `CLAUDE.md`, `CLAUDE.local.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`, `PROJECT_STATE.md`. Stray `{{` inside code or 3rd-party docs is fine.
3. **Discoverability sanity.** `ls -la <target-dir>/.claude/` shows `settings.json` and `agents/`.
4. **Suggest next step.** Recommend the user runs the project's build command once to confirm the toolchain works — but do not run it yourself unless asked.

If any check fails, report the specific failure verbatim — do not attempt to patch the target directory by hand. Re-running the setup script with `--force` is the correct remediation; surface that option to the user.

---

## Out of scope

- **Do not** derive or substitute `BUILD_COMMAND` / `TEST_COMMAND` / `FORMAT_COMMAND` / `LINT_COMMAND` manually. The script handles that based on `--build-tool` / `--package-manager` / variant defaults.
- **Do not** edit `.gitignore` by hand. The script merges a variant-appropriate `.gitignore` with any existing one.
- **Do not** generate `.mcp.json` for the target project. MCP servers are user-level (`~/.claude/.mcp.json`); no per-project `.mcp.json` ships with any variant.
- **Do not** install language toolchains (dotnet, poetry, cargo, mvn, etc.). Prerequisites are the user's responsibility — refer them to their OS package manager.
