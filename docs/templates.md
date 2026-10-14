# Template Variants

[Back to README](../README.md)

## Comparison Table

| Feature | General | .NET | .NET MAUI | Rust/Tauri | Java | Python |
|---------|---------|------|-----------|------------|------|--------|
| Language/Framework | Any | C#/.NET | .NET MAUI Desktop | Rust + TypeScript (Tauri v2) | Java (Spring Boot) | Python |
| Default Task Source | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` | `plan-files` |
| User-level MCP (universal) | git, github, ollama, template-sync, searxng, open-brain (+ plugins) | same | same | same | same | same |
| Project-level MCP (auto-generated) | none (unless `--sqlite-db-path`) | `dotnet-tools` | `dotnet-tools`, `windows-mcp` | `rust-tools`, `windows-mcp` | none (unless `--sqlite-db-path`) | none (unless `--sqlite-db-path`) |
| Agents (from the cct plugin, all 10 in every variant; the variant's `CLAUDE.md` names its coder) | `cct:coder` | `cct:dotnet-coder` | `cct:dotnet-coder` | `cct:rust-coder` | `cct:java-coder` | `cct:python-coder` |
| Code Style | No | .editorconfig | .editorconfig | rustfmt.toml + .prettierrc | .editorconfig | .editorconfig |
| Build/Test Integration | Generic | dotnet build/test | dotnet build/test | cargo + npm | Maven or Gradle | pytest + ruff |
| Post-Edit Build (`**Post-edit build**`, set by setup) | `none` | `dotnet build --no-restore -v q` on Edit/Write | `dotnet build --no-restore -v q` on Edit/Write | `none` | `none` | `none` |
| Format check in the derived `**Gate**` | — (`--gate-cmd`) | `dotnet format --verify-no-changes` | `dotnet format --verify-no-changes` | — (`--gate-cmd`) | `spotless:check` / `spotlessCheck` | `ruff format --check` + `ruff check` |
| Git enforcement | git/`gh` CLI allowed and **gated** — the hooks parse the command | same | same | same | same | same |
| Workflow Enforcement | No push to main + gated merge | No push to main + gated merge | No push to main + gated merge | No push to main + gated merge | No push to main + gated merge | No push to main + gated merge |
| Pipeline Hook | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge | SubagentStop nudge |
| Delegation Enforcement | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds | PO cannot edit code or run builds |
| Agent Liveness | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget | Escalating tool-call budget |
| CLAUDE.md Behavior | Session Bootstrap, Debugging, Task Brief — identical across variants; language conventions live in `.claude/rules/` | same | same | same | same | same |
| Path-scoped rules (`.claude/rules/`) | none | `csharp.md` | `csharp.md`, `xaml.md` | `rust.md`, `frontend.md` | `java.md` | `python.md` |
| Database Tools | No | No | SQLite MCP (optional) | No | No | SQLite MCP (optional) |
| Desktop Automation | No | No | Windows-MCP | Windows-MCP | No | No |

## What Is in a Template

Each template variant provides the following files:

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Session bootstrap, workflow TL;DR, verification/debugging/commit rules. **Facts only** — anything that applies to a subset of files belongs in `.claude/rules/` |
| `.claude/rules/` | Path-scoped language conventions (v2.0 PR4). Each `*.md` carries a `paths:` frontmatter glob list and loads **only** when Claude reads or edits a matching file. **Corrected in v3.1, on measurement, then corrected again in v4.0.1 (item 14):** a **scoped** rule (`paths:` present) is absent from context at spawn, subagents included, and arrives only attached to a matching tool call. An **unscoped** rule (no `paths:` key) is the opposite, not a third state: it loads at **every session start**, at `CLAUDE.md` priority — v3.1's "delivered to nobody" was itself wrong, not just the earlier "loaded at launch at CLAUDE.md cost" it replaced. `project.md`, seeded by v3.1 as a project-owned `once` file, ships unscoped ON PURPOSE for exactly that reason: it is where a consumer's own always-on conventions belong, and its own header says so; add a `paths:` key only to scope it down. `general` ships none (no language of its own); `dotnet` → `csharp.md`, `dotnet-maui` → `csharp.md` + `xaml.md`, `rust-tauri` → `rust.md` + `frontend.md`, `java` → `java.md`, `python` → `python.md` |
| `CLAUDE.local.md` | **Retired in v4.0.1**: the template no longer ships this file. It held MCP usage rules (gitignored, machine-specific paths); a project that already has one keeps it, and it is never touched by a sync |
| `.claude/rules/project.md` | **New in v3.1**, class `once`: seeded by `setup-project` and never overwritten by a sync. It ships unscoped, so it loads at every session start; its header says how to scope it with `paths:` and that always-on project rules belong in `.claude/project-instructions.md` instead |
| `.claude/project-instructions.md` | **New in v4.1.0**, class `once`: imported by `CLAUDE.md`'s last line; where the project's own rules live |
| `AGENT_TEAM.md` | v2.0 dual-mode workflow (identical across all variants) |
| `PROJECT_CONTEXT.md` | Per-project config: tech stack, build/test commands, task source mode |
| `PROJECT_STATE.md` | Sprint state tracking |
| `.claude/settings.json` | MCP permissions, plugin enablement and the plugin-off guard; the workflow hooks come from the cct plugin (`hooks/hooks.json`) |
| `.claude/agents/` | Not shipped since v5.0: the 10 agents (incl. the custom `Explore` and the domain coders) come from the cct plugin as `cct:<name>`. A project may add its own agent there; it sits beside `cct:<name>` (namespaced) and never replaces it |
| `hooks/` | Not a variant directory. Since v5.0 a project receives only `hooks/git-pre-push.sh` (a NATIVE git hook, installed per clone by `bash hooks/git-pre-push.sh --install`, registered in no `settings.json`) and the two libraries it sources, `hooks/lib/git-cmd.sh` and `hooks/lib/json.sh`, all three tracked once at the toolkit ROOT. Every other enforcement hook (`no-push-main`, `pre-commit-test`, `gate-before-merge`, `read-size-gate`, `enforce-agent-contract`, `enforce-delegation`, `agent-budget-warn`, `retro-ledger` + `retro-brief`, `bash-output-guard`, `deny-secret-reads`, `post-edit-build`, `deny-claude-md-writes`, `deny-hang-shapes`, `model-floor`, `verify-hooks`, `now-brief`, and the Jev pair) runs from the cct plugin, registered by its `hooks/hooks.json` through `hooks/run-hook.sh`; the gate runner `hooks/run-gate.sh` is called as `cct-gate` |
| `gitignore` | Template for .gitignore (copied or merged by the setup script) |
| `.editorconfig` | Code style for dotnet, dotnet-maui, java, and python variants |
| `rustfmt.toml` + `.prettierrc` | Code style for rust-tauri variant only |

### Branch protection: three layers

1. `hooks/no-push-main.sh` (Claude Code, PreToolUse, registered by the cct plugin): refuses a push Claude types, with advice. Script scanning is best-effort.
2. `hooks/git-pre-push.sh` (git, per clone): refuses every create, update or delete of a protected branch, however the push started, on every remote. Installed by setup and by `bash hooks/git-pre-push.sh --install`; with `core.hooksPath` or an existing `pre-push`, add the chain line the installer prints. `git push --no-verify` is the one deliberate escape.
3. Server-side (recommended): a GitHub ruleset on the default branch with **Require a pull request before merging** and **Block force pushes**. It is the only layer a client cannot skip.

## Variant Details

### General

The simplest starting point, suitable for any language or framework. Its `CLAUDE.md` routes all development work to `cct:coder` (the plugin's six generic agents: Explore, architect, code-reviewer, coder, ops, tester). No post-edit build or code style files; the cct plugin supplies the three git gates on `Bash|PowerShell` (tests before a commit, no push to main, no ungated merge), the `Read` cap, SubagentStop pipeline hooks, delegation enforcement, the agent tool-call budget, and a post-compaction `## Now` brief. No language-specific conventions in CLAUDE.md. Use this when your project does not match one of the specialized variants.

### Dotnet

Extends the general template for C#/.NET projects. Its `CLAUDE.md` routes .NET work to `cct:dotnet-coder`; it adds an `.editorconfig` for code style, and .NET conventions in `.claude/rules/csharp.md` (implicit usings, DI patterns, null-coalescing, `dotnet format` compliance) scoped to `**/*.cs`, `**/*.csproj`, `**/*.props`, `**/*.targets`, and `.editorconfig`. Setup declares `**Post-edit build**: dotnet build --no-restore -v q`, which the plugin's PostToolUse hook runs after every Edit or Write, catching compilation errors immediately. The derived `**Gate**` starts with `dotnet format --verify-no-changes`, so the merge gate fails on format violations.

### Dotnet-MAUI

Extends the dotnet template for .NET MAUI desktop applications. Adds MAUI-specific conventions in `.claude/rules/xaml.md` (CommunityToolkit.Maui references, XAML namespace checks), scoped to `**/*.xaml` and `**/*.xaml.cs`, alongside the shared `csharp.md`. Setup generates a project-level `windows-mcp` entry. (Through v4.x the template tester agent was specialised for FlaUI and a settings hook blocked Windows-MCP `Click`/`Type`; neither ships since v5.0 — the plugin has one `cct:tester` and the template registers only the plugin-off guard.) SQLite MCP support is optional and configured through `PROJECT_CONTEXT.md` placeholders. Database-related fields (`{{DB_DIRECTORY}}`, `{{DB_FILENAME}}`, `{{DB_PATH}}`) can be left empty if the project does not use SQLite.

### Java

Its `CLAUDE.md` routes Java work to `cct:java-coder` (Maven/Gradle build discipline). Ships a Java-focused `.editorconfig` for whitespace and indent rules (the project formatter — Spotless, Checkstyle, or google-java-format — is authoritative for Java style). `.claude/rules/java.md` carries the "Code Style (MANDATORY)" block plus Java/Spring conventions (constructor injection, `Optional` for nullable returns, `@ComponentScan` verification), scoped to `**/*.java`, `pom.xml`, `**/build.gradle*`, and `src/main/resources/application.*`. The `cct:java-coder` agent uses Bash `mvn`/`gradle` commands directly — no Java-specific MCP tools exist yet. The derived `**Gate**` (`mvn spotless:check clean verify` or `./gradlew spotlessCheck build`) fails the merge gate on a Spotless violation. The setup script accepts `--build-tool` (maven or gradle, default: maven) and `--java-version` (default: 21) to auto-derive build, test, format, and lint commands.

### Python

Its `CLAUDE.md` routes Python work to `cct:python-coder` (pytest/ruff discipline). Ships a Python-focused `.editorconfig` for whitespace and indent rules. `.claude/rules/python.md` carries the "Code Style (MANDATORY)" block plus Python conventions (type hints, `pathlib`, `logging` over `print`), scoped to `**/*.py`, `pyproject.toml`, `requirements*.txt`, and `ruff.toml`. The `cct:python-coder` agent uses Bash `pytest` / `ruff` commands directly -- no Python-specific MCP tools exist yet. Setup writes `**Post-edit build**: none`; the derived `**Gate**` runs `ruff format --check`, `ruff check` and pytest, so the merge gate fails unless all pass. The setup script accepts `--package-manager` (pip, poetry, or uv, default: pip) and `--python-version` (default: 3.12) to auto-derive build, test, format, and lint commands. SQLite MCP support is optional.

### Rust-Tauri

Its `CLAUDE.md` routes Rust/Tauri work to `cct:rust-coder` (cargo/clippy/fmt discipline). Ships `rustfmt.toml` and `.prettierrc` for Rust and TypeScript formatting. `.claude/rules/rust.md` (scoped to `**/*.rs`, `rustfmt.toml`, `Cargo.toml`) and `.claude/rules/frontend.md` (scoped to `src/**/*.ts`, `src/**/*.tsx`, `**/*.css`, `.prettierrc`) carry the "Code Style (MANDATORY)" blocks plus the backend/frontend conventions. Setup generates a project-level `windows-mcp` entry for desktop UI testing. (Rule 12 -- prefer `cargo_build`/`cargo_test`/`cargo_clippy` MCP tools over Bash -- lived in `CLAUDE.local.md`, retired in v4.0.1; the template no longer ships it.) Setup derives `**Test**` (`cargo test --manifest-path src-tauri/Cargo.toml`) and writes `**Post-edit build**: none`; the `**Gate**` is yours to set with `--gate-cmd` (e.g. `cargo fmt --check` + `npm run format --check` + the tests).

## Project-Level MCP Matrix

The setup script generates `<project-root>/.mcp.json` per variant at setup time, based on the variant and optional CLI flags. Language/framework MCP servers are **not** registered at user level — they only load in repos that explicitly need them.

| Variant | Always generated | Optional (via flag) | Required flag |
|---|---|---|---|
| general | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |
| dotnet | `dotnet-tools` | `sqlite` | `--mcp-dev-servers-path` |
| dotnet-maui | `dotnet-tools`, `windows-mcp` | `sqlite` | `--mcp-dev-servers-path` |
| rust-tauri | `rust-tools`, `windows-mcp` | `sqlite` | `--mcp-dev-servers-path` |
| java | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |
| python | *(none — file omitted unless flags set)* | `sqlite` | `--sqlite-db-path` |

**Flag notes:**

- `--mcp-dev-servers-path <path>` — points at a local clone of [`mcp-dev-servers`](https://github.com/dagonet/mcp-dev-servers). Required for variants that register `dotnet-tools` or `rust-tools`. If omitted, the setup script prints a warning and skips the affected entries (no default).
- `--sqlite-db-path <path>` — optional for any variant. Accepts absolute or relative (resolved against caller CWD).
- `windows-mcp` is hard-coded to `uvx windows-mcp` — assumes `uvx` is on PATH.
- If no entries would be written for a variant, `.mcp.json` is not created.

See `docs/architecture.md` → *MCP Layering* and `mcp-servers/HOWTO.md` → *Project-Level Servers* for rationale and per-server details.

## Placeholder Reference

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `{{PROJECT_NAME}}` | Project name | MyProject |
| `{{PROJECT_NAME_LOWER}}` | Lowercase project name | myproject |
| `{{REPO_URL}}` | GitHub repository URL | https://github.com/user/myproject |
| `{{SOLUTION_FILE}}` | Main build file path (.NET) | MyProject.sln |
| `{{BUILD_COMMAND}}` | Build command | dotnet build MyProject.sln |
| `{{RUN_COMMAND}}` | Run command — **not used by any current template** (0 occurrences under `templates/`; kept for a reintroduced placeholder) | dotnet run --project src/MyProject |
| `{{TEST_COMMAND}}` | Test command | dotnet test |
| `{{FORMAT_COMMAND}}` | Format command | dotnet format |
| `{{LINT_COMMAND}}` | Lint command | dotnet format --verify-no-changes |
| `{{GATE_COMMAND}}` | Gate command (`cct-gate`, the plugin's `hooks/run-gate.sh`, runs it). Chaining is supported — `bash preflight.sh && <real gate>` — and a chained preflight can declare a **terminal** failure (one re-running cannot fix) by printing its remedy to stderr, touching `$RUN_GATE_TERMINAL` and exiting 78. Worked example: [`verification.md`](verification.md#terminal-conditions-in-a-gate-command) | dotnet format --verify-no-changes && dotnet test |
| `{{DEFAULT_BRANCH}}` | **No template file uses it** since v2.2.3 — nothing fills it on a sync, so a permanent unresolved-placeholder warning was the only thing it earned. Both setup scripts still substitute it and record it in the manifest, so a reintroduced placeholder resolves for a bootstrapped repo. `--default-branch` itself is live: it rewrites `**Protected branches**:`. | main |
| `{{DB_DIRECTORY}}` | Database directory (MAUI) | c:\Users\...\Data |
| `{{DB_FILENAME}}` | Database filename (MAUI) — **not used by any current template** since `CLAUDE.local.md` was retired (v4.0.1); `setup-project.ps1` still accepts `-DbFilename` and warns when it is absent, which is a bootstrap defect logged for v4.0.4 | myproject.db |
| `{{DB_PATH}}` | Full database path (MAUI) | c:\Users\...\Data\myproject.db |
| `{{JAVA_VERSION}}` | Java version (Java) | 21 |
| `{{PYTHON_VERSION}}` | Python version (Python) | 3.12 |
| `{{LOG_PATH}}` | Log file location | c:\Users\...\Logs\ |
| `{{WORKTREE_BASE}}` | Git worktree base (defaults to `../.worktrees/<project name>`, resolved against the repo root; convention only — EnterWorktree ignores it; every variant gitignore still covers `.claude/worktrees/`, EnterWorktree's fixed location). Note: `.claude/worktrees/` in `.gitignore` does not stop a flat-config `eslint .` from linting the worktree copies — flat config does not read `.gitignore`; add the path to the config's `ignores` as well (yutraffic). | g:/git/.worktrees |
| `{{TECH_STACK}}` | Technology stack description | .NET 10, MAUI, SQLite |
| `{{MAUI_PROJECT}}` | MAUI project path (MAUI) | src/MyApp.MAUI |
| `{{TEST_PROJECT}}` | Test project path | tests/MyApp.Tests |
| `{{GATE_CHECKED_BRANCHES}}` | Fills `**Gate-checked branches**:` in `PROJECT_CONTEXT.md` — glob list of branches whose merges the gate checks in addition to the protected set. Setup writes `none` (= no branch is gate-checked); edit the key afterwards to opt in | none |
| `{{POST_EDIT_BUILD}}` | Fills `**Post-edit build**:` in `PROJECT_CONTEXT.md`, the command `hooks/post-edit-build.sh` runs after every edit. Derived: `dotnet build --no-restore -v q` for the dotnet variants, `none` (= no post-edit build) for the others | dotnet build --no-restore -v q |

## Template Manifest (v4)

The setup script generates `.claude/template-manifest.json` in each target project (`manifest_version: 4` since v4.1.0; older v2 and v3 manifests are migrated by `template_migrate_manifest`). It records:

- **`manifest_version`**: schema version (`4`)
- **`variant`**: which template was applied (general, dotnet, dotnet-maui, rust-tauri, java, python)
- **`templateRepo`**: absolute path to the claude-code-toolkit repo on disk
- **`template_version`** / **`template_commit`**: the toolkit tag and commit the tracked tree matches at setup/sync
- **`requires_server`**: the template-sync server floor (`>=4.1.0`), enforced on every later sync
- **`instructions_file`**: the fixed path `.claude/project-instructions.md` (v4 declaration key). **`agent_grants`** (`.claude/agent-grants.json`) is still written by the v3→v4 migration for older servers, but since v5.0 it is accepted, never required and read by nothing
- **`placeholders`**: the concrete values used during setup (for reverse-mapping by `/cct:contribute-upstream`)
- **`files`**: one entry per tracked path — `{"ownership": "template", "hash": "sha256:<hex>"}` for files the template owns (the hash is of the rendered content the server wrote, so a later diff is measurable), `{"ownership": "once"}` for files seeded once and then yours; files the ownership table does not name are yours and have no entry

The full field reference, key order and the historical v2 shape are in [`template-sync.md`](template-sync.md#manifest-v3--v4-claudetemplate-manifestjson).

The manifest is consumed by the **template-sync-tools** MCP server, which powers the `/cct:sync-template` and `/cct:contribute-upstream` skills. See [`template-sync.md`](template-sync.md) for the full workflow.

## Next Steps

- [Setup walkthrough (Windows + Linux/macOS)](setup.md)