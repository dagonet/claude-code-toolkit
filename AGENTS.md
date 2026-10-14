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
- The **cct plugin** is installed on the machine that will open the project (`/plugin marketplace add dagonet/claude-code-toolkit`, then `/plugin install cct@dagonet`). Without it the bootstrapped project refuses every tool call (the plugin-off guard). Setup itself does not need it.

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

### What lands in the target project (v5.0)

- **No agents.** All 10 agents — `cct:Explore` (haiku), `cct:architect`, `cct:code-reviewer`, `cct:coder`, `cct:ops`, `cct:tester` and the language coders `cct:dotnet-coder` / `cct:rust-coder` / `cct:java-coder` / `cct:python-coder` — come from the cct plugin; the variant's `CLAUDE.md` names which coder to spawn. Each agent declares its own `model:` and `effort:`; do not pass `model:` in an Agent call, it silently overrides the file.
- **`.claude/settings.json`** — permissions, `enabledPlugins` (`cct@dagonet`) and the inline plugin-off guard; no other hook registration.
- **`.claude/rules/*.md`** — `project.md` (unscoped, once-class, yours) in every variant, plus path-scoped language conventions with a `paths:` frontmatter glob list, loaded only when Claude touches a matching file. Every variant except `general` ships at least one of those; `general` has no language of its own. `{{FORMAT_COMMAND}}` / `{{LINT_COMMAND}}` inside them are substituted by the script like any other template file.
- **`hooks/`** — only `hooks/git-pre-push.sh` and the two libraries it sources, `hooks/lib/git-cmd.sh` and `hooks/lib/json.sh`, copied from the toolkit root; setup installs the native pre-push hook from them. Every other enforcement hook runs from the cct plugin.
- **No `commands/` directory.** Slash commands are skills now; the 9 skills ship in the cct plugin (`/cct:<skill>`), not in the project — see [`user-level-reference/README.md`](user-level-reference/README.md).

---

## 4. Interactive Q&A

Collect answers before running the script. Ask only questions relevant to the chosen variant. **Do not compute `BUILD_COMMAND` / `TEST_COMMAND` / `FORMAT_COMMAND` yourself — the script derives those from the user's answers, or takes them verbatim from the command flags below.**

**Precedence:** an explicit command flag always wins over the value a variant would derive. Passing `--build-cmd "make build"` to the `java` variant yields `make build`, not `mvn clean verify`; the flags the user does not pass keep deriving as before.

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

**`general`:** the variant derives nothing, so ask for the five commands — anything left unanswered stays a `{{...}}` placeholder in `PROJECT_CONTEXT.md` and `CLAUDE.md`:

- **Build command** → `--build-cmd`
- **Test command** → `--test-cmd`
- **Format command** → `--format-cmd`
- **Lint command** → `--lint-cmd`
- **Gate command** (build + test + format-check + lint in one line; `cct-gate` runs it) → `--gate-cmd`

**`rust-tauri`:** no additional questions.

### Optional (all variants)

- **Worktree base path** → `--worktree-base`
- **Log path** → `--log-path`
- **Tech stack blurb** → `--tech-stack`
- **Default / protected branch** (defaults to the target repo's current branch, else `main`) → `--default-branch`
- **Any of the five command flags above** — they apply to every variant and override the derived value.
- **Existing `CLAUDE.md`?** If the target already has one, ask whether to keep it: `--wrap-existing-claude-md` writes the template and moves their full existing file into `.claude/project-instructions.md`. Without the flag the file is skipped untouched.

---

## 5. Script invocation

1. **Construct the command** using the answers collected above. One flag per answer. Do not invent flags.

2. **Dry-run first.** Append `--dry-run` to the command and run it. Show the user the output: files that would be touched (`CREATE` / `OVERWRITE` / `APPEND` / `WRAP` / `SKIP`), placeholders that would be substituted, and the **"Remaining placeholders to fill manually"** report — the dry run computes it over the rendered content, so it is the same list the real run prints. Anything listed there is a value the user still owes you; offer the matching flag before running for real.

3. **Confirm.** Ask the user to approve the dry-run output before running for real. If they say no, adjust answers and repeat step 2.

4. **Run for real.** Drop `--dry-run` and re-execute. Surface the script's exit code — non-zero means abort and report the error verbatim.

### Examples

```bash
# general variant, bash
./setup-project.sh --variant general --project-name MyApp --target-path ../my-app --repo-url https://github.com/me/my-app

# general with explicit commands, bash
./setup-project.sh --variant general --project-name MyApp --build-cmd "make build" --test-cmd "make test" \
  --format-cmd "make fmt" --lint-cmd "make lint" --gate-cmd "make gate" --default-branch main

# java + gradle, bash
./setup-project.sh --variant java --project-name MyService --build-tool gradle --java-version 21

# keep an existing CLAUDE.md by moving its content into .claude/project-instructions.md
./setup-project.sh --variant general --project-name MyApp --wrap-existing-claude-md

# python + poetry, PowerShell
.\setup-project.ps1 -Variant python -ProjectName MyApp -PackageManager poetry -PythonVersion 3.12
```

---

## 6. Post-setup verification

After the script exits 0:

1. **Manifest written.** Confirm `.claude/template-manifest.json` exists in the target directory.
2. **No unfilled placeholders.** Run `grep -r '{{' <target-dir>` — expect no matches in `.claude/`, `CLAUDE.md`, `AGENT_TEAM.md`, `PROJECT_CONTEXT.md`, `PROJECT_STATE.md`. Stray `{{` inside code or 3rd-party docs is fine.
3. **Discoverability sanity.** `ls -la <target-dir>/.claude/` shows `settings.json`, `project-instructions.md`, `template-manifest.json` and `rules/` (no `agents/` since v5.0), and `<target-dir>/hooks/` holds `git-pre-push.sh` plus `lib/git-cmd.sh` and `lib/json.sh`.
4. **Surface the `autoMode.environment` snippet.** The script prints one at the end of both the dry run and the real run. `permissions.autoMode` is **User/managed scope only** — a project cannot ship one, which is deliberate: a repo must not be able to widen its own trust. Show the user the line and tell them to paste it into `permissions.autoMode.environment` in `~/.claude/settings.json`. Do not write it into the project.
5. **Suggest next step.** Recommend the user runs the project's build command once to confirm the toolchain works — but do not run it yourself unless asked.

If any check fails, report the specific failure verbatim — do not attempt to patch the target directory by hand. Re-running the setup script with `--force` is the correct remediation; surface that option to the user.

---

## Out of scope

- **Do not** derive or substitute `BUILD_COMMAND` / `TEST_COMMAND` / `FORMAT_COMMAND` / `LINT_COMMAND` manually. The script handles that based on `--build-tool` / `--package-manager` / variant defaults.
- **Do not** edit `.gitignore` by hand. The script merges a variant-appropriate `.gitignore` with any existing one.
- **Do not** hand-write `.mcp.json` for the target project. The script generates `<target>/.mcp.json` itself when the variant has project-scope servers (`dotnet-tools`, `rust-tools`, `windows-mcp`, `sqlite`), and never clobbers an existing root file without `--force`. Everything else is user-level (`~/.claude.json`).
- **Do not** install language toolchains (dotnet, poetry, cargo, mvn, etc.). Prerequisites are the user's responsibility — refer them to their OS package manager.
