#!/usr/bin/env bash
set -euo pipefail

# Sets up a new project with Claude Code configuration from a template variant.
#
# Usage:
#   ./setup-project.sh --variant general --project-name "MyProject" --repo-url "https://github.com/user/myproject"
#   ./setup-project.sh --variant dotnet --project-name "MyApi" --solution-file "MyApi.sln"
#   ./setup-project.sh --variant java --project-name "MyService" --build-tool gradle --java-version 21
#   ./setup-project.sh --variant python --project-name "MyApp" --package-manager poetry --python-version 3.12
#   ./setup-project.sh --variant dotnet-maui --project-name "MyApp" --solution-file "MyApp.sln" --dry-run
#
# Command flags (all variants; an explicit flag always wins over a derived default):
#   --build-cmd --test-cmd --format-cmd --lint-cmd --gate-cmd
#   --worktree-base --log-path --default-branch
#
#   --wrap-existing-claude-md   keep an existing CLAUDE.md by moving its full
#                               content into .claude/project-instructions.md
#                               (v4.1: CLAUDE.md carries no PROJECT-CUSTOM
#                               region any more -- see docs/plans/2026-09-18-
#                               v4.1-design.md sect 1-2)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CALLER_CWD="$(pwd)"

# --- Defaults ---
VARIANT=""
PROJECT_NAME=""
TARGET_PATH="."
REPO_URL=""
SOLUTION_FILE=""
DB_PATH=""
DB_FILENAME=""
TECH_STACK=""
# Default, not a constant: --worktree-base still wins. Agent worktrees have to
# land SOMEWHERE, and an empty value left `{{WORKTREE_BASE}}` in the rendered
# PROJECT_CONTEXT.md. The value is asserted against templates/*/gitignore by
# verify-template-consistency.sh — a default the ignore rules do not cover puts
# a full repo checkout in `git status`.
WORKTREE_BASE=".claude/worktrees"
LOG_PATH=""
MAUI_PROJECT=""
TEST_PROJECT=""
BUILD_TOOL=""
JAVA_VERSION=""
PACKAGE_MANAGER=""
PYTHON_VERSION=""
MCP_DEV_SERVERS_PATH=""
SQLITE_DB_PATH=""
BUILD_CMD=""
TEST_CMD=""
FORMAT_CMD=""
LINT_CMD=""
GATE_CMD=""
DEFAULT_BRANCH=""
WRAP_EXISTING_CLAUDE_MD=false
FORCE=false
DRY_RUN=false

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --variant)         VARIANT="$2"; shift 2 ;;
        --project-name)    PROJECT_NAME="$2"; shift 2 ;;
        --target-path)     TARGET_PATH="$2"; shift 2 ;;
        --repo-url)        REPO_URL="$2"; shift 2 ;;
        --solution-file)   SOLUTION_FILE="$2"; shift 2 ;;
        --db-path)         DB_PATH="$2"; shift 2 ;;
        --db-filename)     DB_FILENAME="$2"; shift 2 ;;
        --tech-stack)      TECH_STACK="$2"; shift 2 ;;
        --worktree-base)   WORKTREE_BASE="$2"; shift 2 ;;
        --log-path)        LOG_PATH="$2"; shift 2 ;;
        --maui-project)    MAUI_PROJECT="$2"; shift 2 ;;
        --test-project)    TEST_PROJECT="$2"; shift 2 ;;
        --build-tool)      BUILD_TOOL="$2"; shift 2 ;;
        --java-version)    JAVA_VERSION="$2"; shift 2 ;;
        --package-manager) PACKAGE_MANAGER="$2"; shift 2 ;;
        --python-version)  PYTHON_VERSION="$2"; shift 2 ;;
        --mcp-dev-servers-path) MCP_DEV_SERVERS_PATH="$2"; shift 2 ;;
        --sqlite-db-path)  SQLITE_DB_PATH="$2"; shift 2 ;;
        --build-cmd)       BUILD_CMD="$2"; shift 2 ;;
        --test-cmd)        TEST_CMD="$2"; shift 2 ;;
        --format-cmd)      FORMAT_CMD="$2"; shift 2 ;;
        --lint-cmd)        LINT_CMD="$2"; shift 2 ;;
        --gate-cmd)        GATE_CMD="$2"; shift 2 ;;
        --default-branch)  DEFAULT_BRANCH="$2"; shift 2 ;;
        --wrap-existing-claude-md) WRAP_EXISTING_CLAUDE_MD=true; shift ;;
        --force)           FORCE=true; shift ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)
            sed -n '3,18p' "$0"
            exit 0
            ;;
        *) echo "Error: Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Validate required params ---
if [[ -z "$VARIANT" ]]; then
    echo "Error: --variant is required (general, dotnet, dotnet-maui, rust-tauri, java, python)" >&2
    exit 1
fi
if [[ -z "$PROJECT_NAME" ]]; then
    echo "Error: --project-name is required" >&2
    exit 1
fi
case "$VARIANT" in
    general|dotnet|dotnet-maui|rust-tauri|java|python) ;;
    *) echo "Error: --variant must be one of: general, dotnet, dotnet-maui, rust-tauri, java, python" >&2; exit 1 ;;
esac

# --- Resolve paths ---
TEMPLATE_DIR="$SCRIPT_DIR/templates/$VARIANT"
if [[ -d "$TARGET_PATH" ]]; then
    TARGET_DIR="$(cd "$TARGET_PATH" && pwd)"
else
    mkdir -p "$TARGET_PATH"
    TARGET_DIR="$(cd "$TARGET_PATH" && pwd)"
fi

if [[ ! -d "$TEMPLATE_DIR" ]]; then
    echo "Error: Template variant '$VARIANT' not found at: $TEMPLATE_DIR" >&2
    exit 1
fi

# --- Validate variant-specific parameters ---
warnings=()

if [[ "$VARIANT" == "dotnet" || "$VARIANT" == "dotnet-maui" ]] && [[ -z "$SOLUTION_FILE" ]]; then
    warnings+=("SolutionFile not provided - {{SOLUTION_FILE}}, {{BUILD_COMMAND}} placeholders will remain")
fi
if [[ "$VARIANT" == "dotnet-maui" ]]; then
    [[ -z "$DB_PATH" ]] && warnings+=("DbPath not provided - {{DB_DIRECTORY}}, {{DB_PATH}} placeholders will remain")
    [[ -z "$DB_FILENAME" ]] && warnings+=("DbFilename not provided - {{DB_FILENAME}} placeholders will remain")
fi
if [[ -n "$BUILD_TOOL" ]] && [[ "$BUILD_TOOL" != "maven" && "$BUILD_TOOL" != "gradle" ]]; then
    echo "Error: --build-tool must be 'maven' or 'gradle', got: $BUILD_TOOL" >&2; exit 1
fi
if [[ -n "$PACKAGE_MANAGER" ]] && [[ "$PACKAGE_MANAGER" != "pip" && "$PACKAGE_MANAGER" != "poetry" && "$PACKAGE_MANAGER" != "uv" ]]; then
    echo "Error: --package-manager must be 'pip', 'poetry', or 'uv', got: $PACKAGE_MANAGER" >&2; exit 1
fi

if [[ "$FORCE" == true && "$WRAP_EXISTING_CLAUDE_MD" == true ]]; then
    echo "Error: --force and --wrap-existing-claude-md conflict — --force overwrites an existing CLAUDE.md, --wrap-existing-claude-md preserves its content by moving it into .claude/project-instructions.md. Pass one or the other." >&2
    exit 1
fi

# --- Default branch: explicit flag, else detected from the target repo, else main ---
if [[ -n "$DEFAULT_BRANCH" ]]; then
    # A plain ref name only — this value ends up in PROJECT_CONTEXT.md and is read
    # back by the branch-protection hooks, so refuse anything shell- or ref-unsafe.
    if [[ ! "$DEFAULT_BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || [[ "$DEFAULT_BRANCH" == -* ]] || [[ "$DEFAULT_BRANCH" == *..* ]]; then
        echo "Error: --default-branch must be a plain ref name (letters, digits, . _ / -), got: $DEFAULT_BRANCH" >&2; exit 1
    fi
else
    # Detect only when the TARGET ITSELF is a repo root: git walks up, so a target
    # inside someone else's checkout would otherwise inherit that repo's branch.
    detected=""
    toplevel="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$toplevel" ]] && [[ "$(cd "$toplevel" 2>/dev/null && pwd)" == "$TARGET_DIR" ]]; then
        # Prefer the remote's default branch: the branch that happens to be checked
        # out during bootstrap is often a feature branch, and this value is what
        # PROJECT_CONTEXT.md declares PROTECTED.
        remote_head="$(git -C "$TARGET_DIR" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true)"
        if [[ "$remote_head" == refs/remotes/origin/* ]]; then
            detected="${remote_head#refs/remotes/origin/}"
        else
            detected="$(git -C "$TARGET_DIR" symbolic-ref --short HEAD 2>/dev/null || true)"
        fi
    fi
    if [[ -n "$detected" ]]; then
        DEFAULT_BRANCH="$detected"
        echo "Detected default branch: $DEFAULT_BRANCH (override with --default-branch)"
    else
        DEFAULT_BRANCH="main"
    fi
fi

# --- Resolve relative MCP path flags against caller CWD ---
resolve_caller_path() {
    local p="$1"
    case "$p" in
        /*|[a-zA-Z]:[/\\]*) printf '%s' "$p" ;;
        *) printf '%s/%s' "$CALLER_CWD" "$p" ;;
    esac
}
[[ -n "$MCP_DEV_SERVERS_PATH" ]] && MCP_DEV_SERVERS_PATH="$(resolve_caller_path "$MCP_DEV_SERVERS_PATH")"
[[ -n "$SQLITE_DB_PATH" ]]       && SQLITE_DB_PATH="$(resolve_caller_path "$SQLITE_DB_PATH")"

# Warn if a variant needs --mcp-dev-servers-path but it's missing
case "$VARIANT" in
    dotnet|dotnet-maui)
        [[ -z "$MCP_DEV_SERVERS_PATH" ]] && warnings+=("--mcp-dev-servers-path not set - project-level dotnet-tools MCP entry will be skipped")
        ;;
    rust-tauri)
        [[ -z "$MCP_DEV_SERVERS_PATH" ]] && warnings+=("--mcp-dev-servers-path not set - project-level rust-tools MCP entry will be skipped")
        ;;
esac

# --- v4.0: resolve the toolkit's OWN template-sync exe (ruling R2) ----------
# The template-sync server ships from THIS checkout, so unlike dotnet-tools /
# rust-tools above it needs no --mcp-dev-servers-path flag -- the path is
# $SCRIPT_DIR/server/.venv/.... Register it only if its exe exists, installing
# it first when server/install.sh is present and the exe is not. A tree
# without server/ (the bootstrap fixture's no-.git copy, or a partial
# checkout) gets a WARNING and no registration: a registration that points at
# nothing is the failure the release sequencing exists to prevent.
#
# `[[ -x "$cand" ]]` below is a check in BASH's own namespace -- $cand is
# whatever path shape bash/MSYS produced for $SCRIPT_DIR. The consumer of the
# registration this script publishes is a Win32 process (claude.exe reading
# ~/.claude.json), so the candidate is re-verified after converting it to the
# Win32 form that actually gets written out: round-tripped back to a POSIX
# path via `cygpath -u` and stat'd again, rather than trusting that bash's own
# resolution of the candidate implies the Win32 process's resolution agrees.
TS_EXE=""
for cand in "$SCRIPT_DIR/server/.venv/Scripts/mcp-template-sync-tools.exe" "$SCRIPT_DIR/server/.venv/bin/mcp-template-sync-tools"; do
    [[ -x "$cand" ]] && { TS_EXE="$cand"; break; }
done
TS_INSTALL_RC=0
if [[ -z "$TS_EXE" && -x "$SCRIPT_DIR/server/install.sh" ]]; then
    if TS_EXE="$("$SCRIPT_DIR/server/install.sh")"; then
        :
    else
        TS_INSTALL_RC=$?
        TS_EXE=""
    fi
fi
TS_REGISTER=0
TS_WIN_EXE=""
TS_WARN_REASON=""
if [[ -n "$TS_EXE" ]]; then
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            # On a Windows shell the consumer is a Win32 process (claude.exe
            # reading ~/.claude.json), and cygpath is the ONLY thing that can
            # turn bash's own MSYS path shape into the Win32 namespace that
            # consumer needs -- so it is REQUIRED here, never best-effort. A
            # silent fallback to the raw (MSYS) path when cygpath is missing
            # would write exactly the kind of unresolvable path this task
            # exists to stop, with no warning at all.
            if command -v cygpath >/dev/null 2>&1; then
                TS_WIN_EXE="$(cygpath -w "$TS_EXE" 2>/dev/null || true)"
                if ! command -v powershell >/dev/null 2>&1; then
                    # Cannot ask the actual consumer whether the published
                    # string resolves -- same posture as cygpath missing:
                    # cannot verify, so do not register.
                    TS_WARN_REASON="cannot verify the exe in the Win32 namespace: powershell not found; not registering template-sync-tools - install PowerShell or register the exe by hand"
                else
                    # The consumer is a Win32 process (claude.exe reading
                    # ~/.claude.json). Ask THAT consumer's own resolution
                    # mechanism whether the published string resolves -- the
                    # same check install.ps1 makes with Test-Path -- rather
                    # than round-tripping back through cygpath: `cygpath -w`
                    # then `cygpath -u` then `-f` never leaves MSYS's own
                    # path-mapping, so it only proves cygpath inverts itself
                    # and the file exists in the namespace bash already
                    # trusted, never that a Win32 process can open it.
                    ts_probe_out=""
                    if [[ -n "$TS_WIN_EXE" ]]; then
                        # PowerShell's single-quoted string escape is a doubled
                        # quote, not a backslash -- a checkout path containing
                        # an apostrophe (e.g. an O'Brien user directory) would
                        # otherwise terminate the string early and hand
                        # Test-Path a ParserError instead of True/False.
                        ts_win_esc="${TS_WIN_EXE//\'/\'\'}"
                        ts_probe_out="$(powershell -NoProfile -Command "Test-Path -LiteralPath '$ts_win_esc'" 2>/dev/null | tr -d '\r')"
                    fi
                    if [[ "$ts_probe_out" == "True" ]]; then
                        TS_REGISTER=1
                    else
                        TS_WARN_REASON="could not verify the exe in the Win32 namespace (cygpath conversion of $TS_EXE failed or the converted path does not resolve); not registering template-sync-tools - register the exe by hand"
                    fi
                fi
            else
                TS_WARN_REASON="cannot convert the exe path to the Win32 namespace: cygpath not found; not registering template-sync-tools - install Git for Windows' cygpath or register the exe by hand"
            fi
            ;;
        *)
            # A real POSIX host (Linux/macOS): the raw path already IS the
            # consumer's own (POSIX) namespace, so no conversion is needed.
            TS_WIN_EXE="$TS_EXE"
            [[ -f "$TS_EXE" ]] && TS_REGISTER=1
            ;;
    esac
fi
if [[ "$TS_REGISTER" -ne 1 ]]; then
    if [[ -n "$TS_WARN_REASON" ]]; then
        warnings+=("$TS_WARN_REASON")
    elif [[ "$TS_INSTALL_RC" -ne 0 ]]; then
        # install.sh failed -- name the exit code and point at the direct
        # invocation rather than swallowing it into a bare "not found" warning
        # (its cygpath-fails path exits under `set -e` with nothing on stderr).
        warnings+=("template-sync-tools not registered: server/install.sh exited $TS_INSTALL_RC - run 'bash server/install.sh' in the toolkit checkout by hand to see the error, then re-run setup or add the entry to ~/.claude.json manually")
    else
        warnings+=("template-sync-tools not registered: no exe under server/.venv and no server/install.sh to create one - run 'bash server/install.sh' in the toolkit checkout, then re-run setup or add the entry by hand")
    fi
fi

# --- Build placeholder replacement map ---
# Parallel arrays for bash 3 compatibility (macOS ships bash 3)
declare -a PH_KEYS=()
declare -a PH_VALS=()

add_replacement() { PH_KEYS+=("$1"); PH_VALS+=("$2"); }

# Variant-derived default: never overwrites a value an explicit flag already set.
# (apply_replacements substitutes in insertion order, so a duplicate key would be
# a silent no-op — this makes the precedence explicit instead of positional.)
add_derived() {
    local k
    for k in "${PH_KEYS[@]}"; do
        [[ "$k" == "$1" ]] && return 0
    done
    add_replacement "$1" "$2"
}

# --- Protected branches: bootstrap is the only layer that KNOWS the trunk ---
#
# The template ships the safe literal `- **Protected branches**: main master`.
# Until v2.2.1 it shipped `{{DEFAULT_BRANCH}}`, which NOTHING substitutes on a
# /sync-template apply — so a `develop` repo received a line that read as
# configured, silently resolved to `main master`, and had its trunk unprotected.
# No placeholder is reintroduced here: the static default is correct for the
# common case, and setup — which resolved the branch above — rewrites the line
# when that default would not cover it. An unreplaced placeholder must never
# widen access; a static default that is simply wrong is at least readable.
PROTECTED_DEFAULT="main master"
PROTECTED_BRANCHES="$PROTECTED_DEFAULT"
case " $PROTECTED_DEFAULT " in
    *" $DEFAULT_BRANCH "*) ;;
    *) PROTECTED_BRANCHES="$DEFAULT_BRANCH" ;;
esac

# set_protected_branches <rendered PROJECT_CONTEXT.md text>
set_protected_branches() {
    if [[ "$PROTECTED_BRANCHES" == "$PROTECTED_DEFAULT" ]]; then
        printf '%s' "$1"
        return 0
    fi
    printf '%s' "$1" | sed "s|^- \*\*Protected branches\*\*:.*|- **Protected branches**: $PROTECTED_BRANCHES|"
}

# derived_value <placeholder key, e.g. '{{POST_EDIT_BUILD}}'> -- looks up the
# value add_derived (or an explicit flag via add_replacement) settled on for
# that key. Parallel-array lookup mirrors add_derived's own loop.
derived_value() {
    local i
    for i in "${!PH_KEYS[@]}"; do
        [[ "${PH_KEYS[$i]}" == "$1" ]] && { printf '%s' "${PH_VALS[$i]}"; return 0; }
    done
    return 1
}

# set_derived_defaults <rendered PROJECT_CONTEXT.md text> (v4.0.1, item 5)
#
# The template now ships `- **Gate-checked branches**: none` and
# `- **Post-edit build**: none` as LITERAL text (no `{{...}}` token), so
# apply_replacements' token substitution has nothing left to match once the
# template default is the string a manual bootstrap would also write --
# add_derived's value never reaches the file for these two keys unless the
# whole VALUE LINE is rewritten, the same shape set_protected_branches
# already uses above. Mirrors it further: a derive that agrees with the
# template's own shipped default (`none`) is a no-op, so the line's inline
# HTML comment survives on the common path; only a REAL override (the
# dotnet post-edit-build command) rewrites the line and drops the comment.
set_derived_defaults() {
    local text="$1" gcb pob
    gcb="$(derived_value '{{GATE_CHECKED_BRANCHES}}')"
    pob="$(derived_value '{{POST_EDIT_BUILD}}')"
    if [[ -n "$gcb" && "$gcb" != "none" ]]; then
        text="$(printf '%s' "$text" | sed "s|^- \*\*Gate-checked [Bb]ranches\*\*:.*|- **Gate-checked branches**: $gcb|")"
    fi
    if [[ -n "$pob" && "$pob" != "none" ]]; then
        text="$(printf '%s' "$text" | sed "s|^- \*\*Post-edit build\*\*:.*|- **Post-edit build**: $pob|")"
    fi
    printf '%s' "$text"
}

PROJECT_NAME_LOWER="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')"
add_replacement '{{PROJECT_NAME}}' "$PROJECT_NAME"
add_replacement '{{PROJECT_NAME_LOWER}}' "$PROJECT_NAME_LOWER"
add_replacement '{{DEFAULT_BRANCH}}' "$DEFAULT_BRANCH"

# Explicit command flags — added before any variant-derived default so they win.
[[ -n "$BUILD_CMD" ]]      && add_replacement '{{BUILD_COMMAND}}' "$BUILD_CMD"
[[ -n "$TEST_CMD" ]]       && add_replacement '{{TEST_COMMAND}}' "$TEST_CMD"
[[ -n "$FORMAT_CMD" ]]     && add_replacement '{{FORMAT_COMMAND}}' "$FORMAT_CMD"
[[ -n "$LINT_CMD" ]]       && add_replacement '{{LINT_COMMAND}}' "$LINT_CMD"
[[ -n "$GATE_CMD" ]]       && add_replacement '{{GATE_COMMAND}}' "$GATE_CMD"

[[ -n "$REPO_URL" ]]      && add_replacement '{{REPO_URL}}' "$REPO_URL"
[[ -n "$SOLUTION_FILE" ]]  && add_replacement '{{SOLUTION_FILE}}' "$SOLUTION_FILE"
[[ -n "$TECH_STACK" ]]     && add_replacement '{{TECH_STACK}}' "$TECH_STACK"
# The -n guard is now always true for a default bootstrap, and is KEPT for
# parity with setup-project.ps1's `if ($WorktreeBase)`: on an explicit
# `--worktree-base ""` both scripts must behave the same way (leave the
# placeholder), or the two implementations diverge exactly as the dry-run and
# real-run paths did in v2.2.0/v2.2.1.
[[ -n "$WORKTREE_BASE" ]]  && add_replacement '{{WORKTREE_BASE}}' "$WORKTREE_BASE"
# v4.0.2 item 4: defaults to `none`, not left as the literal `{{LOG_PATH}}`
# token -- the -n guard is dropped for this key only (the derived-placeholder
# convention already used by Gate-checked branches / Post-edit build).
add_replacement '{{LOG_PATH}}' "${LOG_PATH:-none}"
[[ -n "$MAUI_PROJECT" ]]   && add_replacement '{{MAUI_PROJECT}}' "$MAUI_PROJECT"
[[ -n "$TEST_PROJECT" ]]   && add_replacement '{{TEST_PROJECT}}' "$TEST_PROJECT"
[[ -n "$DB_PATH" ]]        && add_replacement '{{DB_DIRECTORY}}' "$DB_PATH"
[[ -n "$DB_FILENAME" ]]    && add_replacement '{{DB_FILENAME}}' "$DB_FILENAME"
[[ -n "$DB_PATH" && -n "$DB_FILENAME" ]] && add_replacement '{{DB_PATH}}' "$DB_PATH/$DB_FILENAME"

# Auto-derived: dotnet build commands
if [[ "$VARIANT" == "dotnet" || "$VARIANT" == "dotnet-maui" ]] && [[ -n "$SOLUTION_FILE" ]]; then
    add_derived '{{BUILD_COMMAND}}' "dotnet build $SOLUTION_FILE"
    add_derived '{{TEST_COMMAND}}' "dotnet test"
fi

# Auto-derived: rust-tauri defaults
if [[ "$VARIANT" == "rust-tauri" && -z "$TECH_STACK" ]]; then
    add_replacement '{{TECH_STACK}}' "Tauri v2, Rust, TypeScript, SolidJS, SQLite"
fi
# rust-tauri had NO {{TEST_COMMAND}} derivation and its PROJECT_CONTEXT.md
# shipped only `**Test (backend)**` / `**Test (frontend)**`. The declared-key
# reader in pre-commit-test.sh matches `\*\*Test( Command)?\*\*:` -- neither
# parenthesised spelling matches, so a rust-tauri project resolved NO Test key
# and the pre-commit gate had nothing to run. Backend-only is the deliberate
# default: it is the fast half, `--test-cmd` overrides it, and the two
# parenthesised lines stay for a human reading the file.
if [[ "$VARIANT" == "rust-tauri" ]]; then
    add_derived '{{TEST_COMMAND}}' "cargo test --manifest-path src-tauri/Cargo.toml"
fi

# Auto-derived: Python variant
if [[ "$VARIANT" == "python" ]]; then
    py_pkg="${PACKAGE_MANAGER:-pip}"
    py_ver="${PYTHON_VERSION:-3.12}"
    add_replacement '{{PYTHON_VERSION}}' "$py_ver"
    case "$py_pkg" in
        poetry)
            add_derived '{{BUILD_COMMAND}}' "poetry run pytest"
            add_derived '{{TEST_COMMAND}}' "poetry run pytest"
            add_derived '{{FORMAT_COMMAND}}' "poetry run ruff format ."
            add_derived '{{LINT_COMMAND}}' "poetry run ruff check ."
            add_derived '{{GATE_COMMAND}}' "poetry run ruff format --check . && poetry run ruff check . && poetry run pytest"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Python $py_ver, Poetry"
            ;;
        uv)
            add_derived '{{BUILD_COMMAND}}' "uv run pytest"
            add_derived '{{TEST_COMMAND}}' "uv run pytest"
            add_derived '{{FORMAT_COMMAND}}' "uv run ruff format ."
            add_derived '{{LINT_COMMAND}}' "uv run ruff check ."
            add_derived '{{GATE_COMMAND}}' "uv run ruff format --check . && uv run ruff check . && uv run pytest"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Python $py_ver, uv"
            ;;
        *)
            add_derived '{{BUILD_COMMAND}}' "python -m pytest"
            add_derived '{{TEST_COMMAND}}' "python -m pytest"
            add_derived '{{FORMAT_COMMAND}}' "ruff format ."
            add_derived '{{LINT_COMMAND}}' "ruff check ."
            add_derived '{{GATE_COMMAND}}' "ruff format --check . && ruff check . && python -m pytest"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Python $py_ver, pip"
            ;;
    esac
fi

# Auto-derived: Java variant
if [[ "$VARIANT" == "java" ]]; then
    java_bt="${BUILD_TOOL:-maven}"
    java_ver="${JAVA_VERSION:-21}"
    add_replacement '{{JAVA_VERSION}}' "$java_ver"
    case "$java_bt" in
        gradle)
            add_derived '{{BUILD_COMMAND}}' "./gradlew build"
            add_derived '{{TEST_COMMAND}}' "./gradlew test"
            add_derived '{{FORMAT_COMMAND}}' "./gradlew spotlessApply"
            add_derived '{{LINT_COMMAND}}' "./gradlew spotlessCheck"
            add_derived '{{GATE_COMMAND}}' "./gradlew spotlessCheck build"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Java $java_ver, Spring Boot, Gradle"
            ;;
        *)
            add_derived '{{BUILD_COMMAND}}' "mvn clean verify"
            add_derived '{{TEST_COMMAND}}' "mvn test"
            add_derived '{{FORMAT_COMMAND}}' "mvn spotless:apply"
            add_derived '{{LINT_COMMAND}}' "mvn spotless:check"
            add_derived '{{GATE_COMMAND}}' "mvn spotless:check clean verify"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Java $java_ver, Spring Boot, Maven"
            ;;
    esac
fi

# Auto-derived: post-edit build (hooks/post-edit-build.sh, PostToolUse Edit|Write).
# Only the dotnet variants build after every edit; the rest declare `none`.
if [[ "$VARIANT" == "dotnet" || "$VARIANT" == "dotnet-maui" ]]; then
    add_derived '{{POST_EDIT_BUILD}}' "dotnet build --no-restore -v q"
else
    add_derived '{{POST_EDIT_BUILD}}' "none"
fi

# Auto-derived: gate-checked branches (hooks/gate-before-merge.sh companion
# spec). No variant declares one at bootstrap time -- a consumer opts in later
# by naming a glob on the PROJECT_CONTEXT.md line themselves.
add_derived '{{GATE_CHECKED_BRANCHES}}' "none"

# Count of trailing LF bytes at the end of $1 (0 if none), capped at 4 -- no
# shipped source needs more. Every `$(...)` capture of a file's content
# (however many bash function calls it passes through) strips ALL trailing
# newlines, which PowerShell's `Get-Content -Raw` does not -- that divergence
# used to be invisible (nothing compared the two writers' byte output); the
# ownership-cutover manifest's per-file hash now makes it a cross-writer hash
# mismatch on every template file ending in a newline. An earlier version of
# this restored only a single newline (cheaper than fighting command
# substitution's stripping at every intermediate step) because no shipped
# file ended in more than one; `.claude/project-instructions.md` (v4.1, spec
# sect 3: "+ one blank line") is the first that ends in two, and restoring
# only one would silently drop that seed's trailing blank line on every
# bootstrap. The count itself is safe to capture via `$(...)` (it is plain
# digits, nothing for command substitution to strip); the newlines it
# describes are appended by the CALLER with a bash loop, never round-tripped
# through another `$(...)`, which would strip them right back off.
trailing_newline_count() {
    local f="$1" n=0 i
    for ((i = 1; i <= 4; i++)); do
        if [[ "$(tail -c "$i" "$f" | tr -d '\n')" == "" ]]; then
            n=$i
        else
            break
        fi
    done
    printf '%s' "$n"
}

# --- SHA-256 helper ---
content_hash() {
    if command -v sha256sum &>/dev/null; then
        printf '%s' "$1" | sha256sum | cut -d' ' -f1
    elif command -v shasum &>/dev/null; then
        printf '%s' "$1" | shasum -a 256 | cut -d' ' -f1
    else
        echo "error-no-sha256-tool"
    fi
}

# --- Apply placeholder replacements to a string ---
apply_replacements() {
    local text="$1"
    for i in "${!PH_KEYS[@]}"; do
        text="${text//"${PH_KEYS[$i]}"/"${PH_VALS[$i]}"}"
    done
    printf '%s' "$text"
}

# --- Move an existing CLAUDE.md's content into the instructions seed ---
#
# v4.1: CLAUDE.md is a template-class file with NO PROJECT-CUSTOM region to
# splice into any more (docs/plans/2026-09-18-v4.1-design.md sect 1-2) --
# `claude_md_identical` requires the consumer's CLAUDE.md to be byte-identical
# to the rendered template, so nothing can be wrapped inside it. Without
# --wrap-existing-claude-md an existing CLAUDE.md is skipped outright, so a
# consumer whose file is all hard rules gets none of the template. Wrapping
# now keeps every one of their rules by moving the file's full prior content
# into `.claude/project-instructions.md` (the once-class file CLAUDE.md's own
# `@` line imports) instead of splicing it back into CLAUDE.md itself.
append_existing_claude_md() {
    # $1 = rendered instructions-seed text, $2 = existing CLAUDE.md text
    printf '%s\n<!-- Moved here from the previous CLAUDE.md by --wrap-existing-claude-md -->\n\n%s\n' "$1" "$2"
}

# True when this file is an existing CLAUDE.md that --wrap-existing-claude-md
# applies to -- it is overwritten with the plain template instead of being
# skipped, on the strength of should_migrate_claude_md_into_instructions below
# actually moving its content somewhere first.
should_wrap_claude_md() {
    [[ "$1" == "CLAUDE.md" ]] || return 1
    [[ "$WRAP_EXISTING_CLAUDE_MD" == true ]] || return 1
    [[ "$FORCE" != true ]] || return 1
    [[ -f "$TARGET_DIR/CLAUDE.md" ]] || return 1
}

# True when this file is the instructions seed AND there is a pre-existing
# CLAUDE.md whose content --wrap-existing-claude-md is moving into it. Once
# the seed exists on disk this is false on every later run -- the seed is
# once-class (never overwritten), so a second wrap must not re-merge into it;
# the file's OWN generic "exists, skip unless --force" handling already
# protects it, this guard only decides whether THIS run's write is a plain
# seed or a seed-plus-migrated-content write.
should_migrate_claude_md_into_instructions() {
    [[ "$1" == ".claude/project-instructions.md" ]] || return 1
    [[ "$WRAP_EXISTING_CLAUDE_MD" == true ]] || return 1
    [[ "$FORCE" != true ]] || return 1
    [[ -f "$TARGET_DIR/CLAUDE.md" ]] || return 1
    [[ ! -f "$TARGET_DIR/.claude/project-instructions.md" ]] || return 1
}

# --- .gitignore merge block ---
#
# The rendered lines the merge would append to an EXISTING .gitignore. Shared by
# both modes so the dry-run list is the real run's list. The presence test is a
# WHOLE-LINE match: `/.mcp.json` is a substring of `.claude/.mcp.json`, so a
# substring test skipped the root rule on every upgrade path.
# Prints nothing when there is nothing to add. No trailing newline (the caller
# adds it) -- command substitution would strip it anyway.
gitignore_append_block() {
    local content="$1" target_file="$2"
    local lines_to_add="" line trimmed
    while IFS= read -r line; do
        trimmed="${line#"${line%%[![:space:]]*}"}"
        trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
        [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
        if ! grep -qxF "$trimmed" "$target_file" 2>/dev/null; then
            lines_to_add+="$trimmed"$'\n'
        fi
    done <<< "$content"
    [[ -z "$lines_to_add" ]] && return 0
    apply_replacements $'\n'"# Claude Code - machine-specific files"$'\n'"$lines_to_add"
}

# One-line hint appended to an existing-CLAUDE.md skip, naming the way out.
claude_md_skip_hint() {
    [[ "$1" == "CLAUDE.md" ]] || return 0
    printf '%s' " — pass --wrap-existing-claude-md to move its content into .claude/project-instructions.md"
}

# Exact text that would be written for FILE_SOURCES[$1] — used by both modes.
render_file() {
    local idx="$1"
    local rendered
    # An existing .gitignore is merged, not rewritten -- only the append block is written.
    if [[ "${FILE_IS_GITIGNORE[$idx]}" == true ]] && [[ -f "$TARGET_DIR/${FILE_RELS[$idx]}" ]]; then
        gitignore_append_block "$(<"${FILE_SOURCES[$idx]}")" "$TARGET_DIR/${FILE_RELS[$idx]}"
        return 0
    fi
    rendered="$(apply_replacements "$(<"${FILE_SOURCES[$idx]}")")"
    if [[ "${FILE_RELS[$idx]}" == "PROJECT_CONTEXT.md" ]]; then
        rendered="$(set_protected_branches "$rendered")"
        rendered="$(set_derived_defaults "$rendered")"
    fi
    if should_migrate_claude_md_into_instructions "${FILE_RELS[$idx]}"; then
        rendered="$(append_existing_claude_md "$rendered" "$(<"$TARGET_DIR/CLAUDE.md")")"
    fi
    printf '%s' "$rendered"
}

# --- Remaining-placeholder report ---
#
# Computed over the RENDERED content in memory, so the dry run and the real run
# report the same thing. The old real-run-only version grepped the written files
# and therefore could not run in dry-run mode at all (that branch exits first)
# and saw nothing for files that do not exist yet.
declare -a REPORT_RELS=()
declare -a REPORT_TEXTS=()

record_rendered() { REPORT_RELS+=("$1"); REPORT_TEXTS+=("$2"); }

print_remaining_placeholders() {
    local has_remaining=false
    local i line
    for i in "${!REPORT_RELS[@]}"; do
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            if [[ "$has_remaining" == false ]]; then
                echo "Remaining placeholders to fill manually:"
                has_remaining=true
            fi
            echo "  ${REPORT_RELS[$i]}:$line"
        done < <(printf '%s' "${REPORT_TEXTS[$i]}" | grep -n '{{[A-Z_]*}}' || true)
    done
    if [[ "$has_remaining" == false ]]; then
        echo "All placeholders replaced."
    fi
}

# --- Branch protection, stated in the report ---
#
# A bootstrap that cannot protect the trunk it just configured must SAY so here.
# The hook does warn, but hook stderr never reaches the session transcript, so
# this output is the only channel that actually reaches the person running it.
print_branch_protection() {
    local rendered=false r
    for r in "${REPORT_RELS[@]}"; do
        [[ "$r" == "PROJECT_CONTEXT.md" ]] && rendered=true && break
    done
    if [[ "$rendered" != true ]]; then
        echo "Branch protection: PROJECT_CONTEXT.md was NOT written (kept the existing file)."
        echo "  Resolved trunk is '$DEFAULT_BRANCH' — check its '- **Protected branches**:' line"
        echo "  yourself; a trunk that is not named there is not protected."
        return 0
    fi
    if [[ "$PROTECTED_BRANCHES" == "$PROTECTED_DEFAULT" ]]; then
        echo "Branch protection: $PROTECTED_BRANCHES (trunk '$DEFAULT_BRANCH' is covered)."
    else
        echo "Branch protection: $PROTECTED_BRANCHES — set from the resolved trunk."
        echo "  main/master are NOT protected in this project; add them to"
        echo "  PROJECT_CONTEXT.md's '- **Protected branches**:' line if you want them."
    fi
}

# --- JSON escape (used by both .mcp.json and manifest generation) ---
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# --- Build project-level .mcp.json content based on variant and flags ---
# Prints the JSON to stdout. Empty output means "do not write the file".
build_project_mcp_json() {
    declare -a entries=()

    case "$VARIANT" in
        dotnet|dotnet-maui)
            [[ -n "$MCP_DEV_SERVERS_PATH" ]] && entries+=("dotnet-tools")
            ;;
        rust-tauri)
            [[ -n "$MCP_DEV_SERVERS_PATH" ]] && entries+=("rust-tools")
            ;;
    esac
    case "$VARIANT" in
        dotnet-maui|rust-tauri) entries+=("windows-mcp") ;;
    esac
    [[ -n "$SQLITE_DB_PATH" ]] && entries+=("sqlite")

    if [[ ${#entries[@]} -eq 0 ]]; then
        return 0
    fi

    local out='{'$'\n'
    out+='  "mcpServers": {'$'\n'
    local last=$((${#entries[@]} - 1))
    local idx=0
    for entry in "${entries[@]}"; do
        local comma=","
        [[ $idx -eq $last ]] && comma=""
        case "$entry" in
            dotnet-tools)
                out+='    "dotnet-tools": {'$'\n'
                out+='      "command": "'"$(json_escape "$MCP_DEV_SERVERS_PATH/.venv/bin/mcp-dotnet-tools")"'"'$'\n'
                out+='    }'"$comma"$'\n'
                ;;
            rust-tools)
                out+='    "rust-tools": {'$'\n'
                out+='      "command": "'"$(json_escape "$MCP_DEV_SERVERS_PATH/.venv/bin/mcp-rust-tools")"'"'$'\n'
                out+='    }'"$comma"$'\n'
                ;;
            windows-mcp)
                out+='    "windows-mcp": {'$'\n'
                out+='      "command": "uvx",'$'\n'
                out+='      "args": ["windows-mcp"]'$'\n'
                out+='    }'"$comma"$'\n'
                ;;
            sqlite)
                out+='    "sqlite": {'$'\n'
                out+='      "command": "uvx",'$'\n'
                out+='      "args": ["mcp-server-sqlite", "--db-path", "'"$(json_escape "$SQLITE_DB_PATH")"'"]'$'\n'
                out+='    }'"$comma"$'\n'
                ;;
        esac
        idx=$((idx + 1))
    done
    out+='  }'$'\n'
    out+='}'$'\n'

    printf '%s' "$out"
}

# --- Collect template files ---
declare -a FILE_SOURCES=()
declare -a FILE_RELS=()
declare -a FILE_IS_GITIGNORE=()
# TEMPLATE-relative name to feed the ownership classifier. Equal to FILE_RELS
# except for .gitignore, which FILE_RELS already carries under its renamed
# project-path key ("gitignore" -> ".gitignore") -- the classifier's own rule
# is `^gitignore$` and will not match the renamed form.
declare -a FILE_CLASSIFY_NAMES=()

for name in CLAUDE.md AGENT_TEAM.md PROJECT_CONTEXT.md PROJECT_STATE.md VERIFICATION_PLAYBOOK.md; do
    if [[ -f "$TEMPLATE_DIR/$name" ]]; then
        FILE_SOURCES+=("$TEMPLATE_DIR/$name")
        FILE_RELS+=("$name")
        FILE_IS_GITIGNORE+=(false)
        FILE_CLASSIFY_NAMES+=("$name")
    fi
done

for name in .editorconfig rustfmt.toml .prettierrc .gitattributes; do
    if [[ -f "$TEMPLATE_DIR/$name" ]]; then
        FILE_SOURCES+=("$TEMPLATE_DIR/$name")
        FILE_RELS+=("$name")
        FILE_IS_GITIGNORE+=(false)
        FILE_CLASSIFY_NAMES+=("$name")
    fi
done

if [[ -f "$TEMPLATE_DIR/gitignore" ]]; then
    FILE_SOURCES+=("$TEMPLATE_DIR/gitignore")
    FILE_RELS+=(".gitignore")
    FILE_IS_GITIGNORE+=(true)
    FILE_CLASSIFY_NAMES+=("gitignore")
fi

if [[ -d "$TEMPLATE_DIR/.claude" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$TEMPLATE_DIR/"}"
        FILE_SOURCES+=("$file")
        FILE_RELS+=("$rel")
        FILE_IS_GITIGNORE+=(false)
        FILE_CLASSIFY_NAMES+=("$rel")
    done < <(find "$TEMPLATE_DIR/.claude" -type f -print0 | sort -z)
fi

# Shared hook scripts (from repo root, not template-specific).
# EVERY file, recursively: the gates source hooks/lib/*.sh via $(dirname "$0")/lib/…
# and fail CLOSED (exit 2) when the lib is missing, so a filtered copy would leave a
# bootstrapped project unable to commit, push, or merge.
if [[ -d "$SCRIPT_DIR/hooks" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$SCRIPT_DIR/"}"
        FILE_SOURCES+=("$file")
        FILE_RELS+=("$rel")
        FILE_IS_GITIGNORE+=(false)
        FILE_CLASSIFY_NAMES+=("$rel")
    done < <(find "$SCRIPT_DIR/hooks" -type f -print0 | sort -z)
fi

# --- Classify every collected file against templates/ownership.json --------
# One batched node invocation (node is already required by the hooks) rather
# than one process per file. Output columns: rel, ownership, target, rule-idx.
declare -A CLASS_OWNERSHIP=()
declare -A CLASS_TARGET=()
if [[ ${#FILE_CLASSIFY_NAMES[@]} -gt 0 ]]; then
    while IFS=$'\t' read -r c_rel c_own c_target _c_idx; do
        CLASS_OWNERSHIP["$c_rel"]="$c_own"
        CLASS_TARGET["$c_rel"]="$c_target"
    done < <(node "$SCRIPT_DIR/scripts/lib/ownership-classify.mjs" "$SCRIPT_DIR/templates/ownership.json" "${FILE_CLASSIFY_NAMES[@]}")
fi

# Manifest key + ownership class for FILE index $1, from the classifier
# results above. Prints "<key>\t<ownership>" ("-" ownership means the
# classifier did not match -- e.g. a project-added file with no ownership
# rule -- and the file is left out of the manifest entirely, per the
# ownership-cutover contract.
manifest_entry_for() {
    local idx="$1" cname own target
    cname="${FILE_CLASSIFY_NAMES[$idx]}"
    own="${CLASS_OWNERSHIP[$cname]:-UNCLASSIFIED}"
    if [[ "$own" != "template" && "$own" != "once" ]]; then
        # A leading tab is IFS whitespace to `read` and gets collapsed away
        # (the empty key field would otherwise vanish), so both columns carry
        # the sentinel here rather than leaving the first one empty.
        printf -- '-\t-\n'
        return 0
    fi
    target="${CLASS_TARGET[$cname]:-}"
    if [[ -n "$target" && "$target" != "-" ]]; then
        printf '%s\t%s\n' "$target" "$own"
    else
        printf '%s\t%s\n' "${FILE_RELS[$idx]//\\//}" "$own"
    fi
}

# Record a manifest row for FILE index $1 using the content actually written
# ($2). Unclassified files (no ownership rule match; surfaced server-side as
# unclassified_template_files) are silently left out, per contract. `once`
# entries get no hash at all; $2 is ignored for them.
add_manifest_entry() {
    local idx="$1" written="$2" key own
    IFS=$'\t' read -r key own < <(manifest_entry_for "$idx")
    [[ "$own" == "-" ]] && return 0
    MF_KEYS+=("$key")
    MF_OWNERSHIP+=("$own")
    if [[ "$own" == "template" ]]; then
        MF_HASHES+=("sha256:$(content_hash "$written")")
    else
        MF_HASHES+=("")
    fi
}

# --- autoMode.environment snippet -------------------------------------------
#
# `permissions.autoMode` is User/managed scope only: a project cannot ship one,
# which is the right polarity (a hostile repo must not widen its own trust). So
# the script cannot write this anywhere useful — it prints a line for the user
# to paste into ~/.claude/settings.json, exactly like the legacy .mcp.json
# warning above tells the user what to move by hand.
# v3.0.3 (item 23): this used to print a PER-REPO line naming $TARGET_DIR as THE
# trusted repo, and told the user to append it. `autoMode.environment` is USER
# scope: a line naming one repository makes the classifier read every OTHER
# repository as outside the trust boundary. Measured: 58 classifier denials
# across 11 sessions, 50 of them in the one consumer whose commands began with a
# `Set-Location` into a path a per-repo line had declared untrusted. The entries
# are read from user-level-reference/settings.json at run time so the snippet
# cannot drift from the reference it points at.
print_automode_snippet() {
    local ref="$SCRIPT_DIR/user-level-reference/settings.json"

    echo "autoMode.environment (User/managed scope -- it applies to EVERY project on this"
    echo "machine, so it cannot live in this project and must not name this project):"
    echo ""
    if [[ -f "$ref" ]]; then
        awk '/"environment"[[:space:]]*:[[:space:]]*\[/ { inarr = 1; next }
             inarr && /^[[:space:]]*\]/ { exit }
             inarr { print "  " $0 }' "$ref"
    else
        echo "  (user-level-reference/settings.json not found next to this script --"
        echo "   read the entries from the toolkit repo before editing anything.)"
    fi
    echo ""
    echo "  Verify these entries are present in permissions.autoMode.environment in"
    echo "  ~/.claude/settings.json. Do NOT append per-project variants: a line naming"
    echo "  one repository as THE trusted repo makes every other repository on this"
    echo "  machine read as outside the trust boundary, and the classifier will then"
    echo "  ask for confirmation on ordinary commands there."
}

# --- template-sync-tools ~/.claude.json snippet -----------------------------
#
# Same reasoning as autoMode above: ~/.claude.json is user/global scope, this
# script only knows about the one project it just bootstrapped, so it prints
# the entry rather than writing it. TS_REGISTER/TS_WIN_EXE are resolved once,
# above, before the dry-run/real-run fork, so both paths print the same thing.
print_template_sync_snippet() {
    [[ "$TS_REGISTER" -eq 1 ]] || return 0
    echo "template-sync-tools (register in ~/.claude.json's mcpServers if not already"
    echo "present -- this is the toolkit's OWN server, resolved from this checkout):"
    echo ""
    echo "  \"template-sync-tools\": {"
    echo "    \"type\": \"stdio\","
    echo "    \"command\": \"$(json_escape "$TS_WIN_EXE")\","
    echo "    \"args\": []"
    echo "  }"
}

# --- Dry run ---
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "=== DRY RUN ==="
    echo "Variant:    $VARIANT"
    echo "Project:    $PROJECT_NAME"
    echo "Source:     $TEMPLATE_DIR"
    echo "Target:     $TARGET_DIR"
    echo ""
    echo "Files to copy:"
    for i in "${!FILE_SOURCES[@]}"; do
        target_file="$TARGET_DIR/${FILE_RELS[$i]}"
        if [[ "${FILE_IS_GITIGNORE[$i]}" == true ]] && [[ -f "$target_file" ]]; then
            action="APPEND"
        elif should_migrate_claude_md_into_instructions "${FILE_RELS[$i]}"; then
            action="CREATE (existing CLAUDE.md content moved in)"
        elif should_wrap_claude_md "${FILE_RELS[$i]}"; then
            action="OVERWRITE (existing content moves to .claude/project-instructions.md)"
        elif [[ -f "$target_file" ]] && [[ "$FORCE" != true ]]; then
            action="SKIP (exists)$(claude_md_skip_hint "${FILE_RELS[$i]}")"
        elif [[ -f "$target_file" ]] && [[ "$FORCE" == true ]]; then
            action="OVERWRITE"
        else
            action="CREATE"
        fi
        echo "  ${FILE_RELS[$i]} -> $action"
        # Only files the real run would write contribute to the placeholder report.
        if [[ "$action" != SKIP* ]]; then
            record_rendered "${FILE_RELS[$i]}" "$(render_file "$i")"
        fi
    done
    echo ""
    echo "Replacements:"
    for i in "${!PH_KEYS[@]}"; do
        echo "  ${PH_KEYS[$i]} -> ${PH_VALS[$i]}"
    done
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo ""
        echo "Warnings:"
        for w in "${warnings[@]}"; do echo "  [!] $w"; done
    fi
    echo ""
    echo "Manifest:"
    echo "  .claude/template-manifest.json will be generated with:"
    echo "    variant: $VARIANT"
    echo "    templateRepo: $SCRIPT_DIR"
    echo "    placeholders: ${#PH_KEYS[@]} values"
    non_gi=0
    for ig in "${FILE_IS_GITIGNORE[@]}"; do [[ "$ig" == false ]] && ((non_gi++)) || true; done
    echo "    files: $non_gi tracked"
    echo ""
    mcp_preview="$(build_project_mcp_json)"
    if [[ -n "$mcp_preview" ]]; then
        echo "Project-level .mcp.json (would be generated at repo root):"
        printf '%s\n' "$mcp_preview" | sed 's/^/    /'
    else
        echo "Project-level .mcp.json: (not generated - no entries for this variant/flags)"
    fi
    echo ""
    print_remaining_placeholders
    print_branch_protection
    echo ""
    print_automode_snippet
    echo ""
    print_template_sync_snippet
    echo ""
    echo "=== END DRY RUN ==="
    exit 0
fi

# --- Create target directory ---
mkdir -p "$TARGET_DIR"

# --- Copy and process files ---
copied=()
skipped=()

# Manifest tracking. MF_HASHES holds a "sha256:<hex>" value for `template`
# entries and is unset (never assigned) for `once` entries so the manifest
# writer can tell "no hash key at all" apart from an empty one.
declare -a MF_KEYS=()
declare -a MF_OWNERSHIP=()
declare -a MF_HASHES=()

for i in "${!FILE_SOURCES[@]}"; do
    src="${FILE_SOURCES[$i]}"
    rel="${FILE_RELS[$i]}"
    is_gi="${FILE_IS_GITIGNORE[$i]}"
    target_file="$TARGET_DIR/$rel"
    content="$(<"$src")"

    # .gitignore: append or create
    if [[ "$is_gi" == true ]]; then
        if [[ -f "$target_file" ]]; then
            append_block="$(gitignore_append_block "$content" "$target_file")"
            if [[ -n "$append_block" ]]; then
                printf '%s\n' "$append_block" >> "$target_file"
                copied+=("$rel (appended)")
                record_rendered "$rel" "$append_block"
            else
                skipped+=("$rel (entries already present)")
            fi
        else
            mkdir -p "$(dirname "$target_file")"
            content="$(apply_replacements "$content")"
            printf '%s' "$content" > "$target_file"
            copied+=("$rel")
            record_rendered "$rel" "$content"
        fi
        # gitignore is `once` ownership -- no hash regardless of branch above.
        add_manifest_entry "$i" ""
        continue
    fi

    # Overwrite an existing CLAUDE.md instead of skipping it -- its content is
    # moved into the instructions seed by the branch below, not kept here.
    if should_wrap_claude_md "$rel"; then
        wrapped="$(render_file "$i")"
        # Every `$(...)` above stripped the source's trailing newline(s), if
        # any -- restore them so the byte written matches the plain "CREATE"
        # path exactly.
        wrapped_nl=$(trailing_newline_count "$src")
        for ((wni = 0; wni < wrapped_nl; wni++)); do wrapped+=$'\n'; done
        printf '%s' "$wrapped" > "$target_file"
        if should_migrate_claude_md_into_instructions ".claude/project-instructions.md"; then
            copied+=("$rel (existing content will be moved to .claude/project-instructions.md)")
        else
            copied+=("$rel (overwritten; .claude/project-instructions.md is already seeded, nothing to move)")
        fi
        record_rendered "$rel" "$wrapped"
        # Hash covers the content AS WRITTEN, i.e. the plain template.
        add_manifest_entry "$i" "$wrapped"
        continue
    fi

    # Move a pre-existing CLAUDE.md's content into the freshly seeded
    # instructions file instead of writing it as an ordinary once-class seed --
    # see should_migrate_claude_md_into_instructions above.
    if should_migrate_claude_md_into_instructions "$rel"; then
        rendered_seed="$(render_file "$i")"
        # append_existing_claude_md already ends its output in a newline, but
        # the `$(...)` above stripped it along with everything else -- restore
        # exactly one, matching the plain once-class seed write below.
        rendered_seed+=$'\n'
        mkdir -p "$(dirname "$target_file")"
        printf '%s' "$rendered_seed" > "$target_file"
        copied+=("$rel (existing CLAUDE.md content moved in)")
        record_rendered "$rel" "$rendered_seed"
        add_manifest_entry "$i" "$rendered_seed"
        continue
    fi

    # Skip existing unless --force
    if [[ -f "$target_file" ]] && [[ "$FORCE" != true ]]; then
        skipped+=("$rel (exists, use --force to overwrite)$(claude_md_skip_hint "$rel")")
        continue
    fi

    mkdir -p "$(dirname "$target_file")"
    content="$(apply_replacements "$content")"
    # Same rewrite the dry run reports — this write path does NOT go through
    # render_file, so the transform has to be applied here too or the two modes
    # disagree about the one line that decides whether the trunk is protected.
    if [[ "$rel" == "PROJECT_CONTEXT.md" ]]; then
        content="$(set_protected_branches "$content")"
        content="$(set_derived_defaults "$content")"
    fi
    # Every `$(...)` above stripped the source's trailing newline(s), if any --
    # restore them so the bytes written, and hashed, match what ps1 (which
    # never strips them) writes for the same source.
    content_nl=$(trailing_newline_count "$src")
    for ((cni = 0; cni < content_nl; cni++)); do content+=$'\n'; done
    printf '%s' "$content" > "$target_file"
    copied+=("$rel")
    record_rendered "$rel" "$content"
    add_manifest_entry "$i" "$content"
done

# --- Set execute permissions on hook scripts (Linux/macOS) ---
if [[ -d "$TARGET_DIR/hooks" ]]; then
    chmod +x "$TARGET_DIR/hooks/"*.sh 2>/dev/null
fi

# --- Summary ---
echo ""
echo "=== Setup Complete ==="
echo "Variant:    $VARIANT"
echo "Project:    $PROJECT_NAME"
echo "Target:     $TARGET_DIR"
echo ""

if [[ ${#copied[@]} -gt 0 ]]; then
    echo "Copied/Updated:"
    for f in "${copied[@]}"; do echo "  [+] $f"; done
fi

if [[ ${#skipped[@]} -gt 0 ]]; then
    echo ""
    echo "Skipped:"
    for f in "${skipped[@]}"; do echo "  [-] $f"; done
fi

if [[ ${#warnings[@]} -gt 0 ]]; then
    echo ""
    echo "Warnings:"
    for w in "${warnings[@]}"; do echo "  [!] $w"; done
fi

# --- Generate template manifest (v3, per the ownership-cutover contract) ---
template_commit="$(git -C "$SCRIPT_DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
# DERIVED, never a literal. A hardcoded "v3.1.0" here survived the v3.1.1 bump
# and stamped projects with a tag that did not match template_commit -- the
# manifest named one release and pinned a commit belonging to another, and the
# bootstrap could not notice because the fixture asserted the same literal.
# VERSION line 1 is the single source; the tag is always "v" + that. Read from
# the file rather than `git describe`, so an export or a shallow clone with no
# tags still stamps the truth.
# Guarded with -f rather than swallowing the error inside the substitution:
# this script runs under `set -o pipefail`, so a missing VERSION makes the
# PIPELINE fail, and a failing command substitution fails the ASSIGNMENT, which
# `set -e` turns into an aborted bootstrap. The fixture's no-.git control is
# what caught it -- the toolkit copy there has no VERSION file either.
# JSON null, not the string "unknown", when it cannot be determined. The v3
# contract already names null for this field ("the nearest reachable tag whose
# tracked tree is identical, null when none") and the sync server emits null
# from the same condition. A sentinel string is TRUTHY, so a consumer written
# against the contract -- `if manifest.template_version is None` -- sails past
# the check and then fails resolving "unknown" as a ref. Same class as the
# missing `v` prefix, one layer down, in the branch nobody exercises.
# `template_commit` keeps "unknown" deliberately: that IS its contract, and the
# fixture asserts it.
template_version_json="null"
if [ -f "$SCRIPT_DIR/VERSION" ]; then
    template_version="v$(head -1 "$SCRIPT_DIR/VERSION" | tr -d '\r\n')"
    if [ "$template_version" != "v" ]; then
        template_version_json="\"$(json_escape "$template_version")\""
    fi
fi
manifest_path="$TARGET_DIR/.claude/template-manifest.json"
mkdir -p "$(dirname "$manifest_path")"

# Rerun preservation: under manifest v3 a file absent from `files` is
# project-owned BY DEFINITION, so rebuilding the manifest from only this
# run's writes would silently unshare every template file the run did not
# touch. Merge instead -- entries this run wrote replace the old ones,
# every other old entry (even one whose file has since vanished from the
# target; the sync server is the right place to report that) is carried
# forward verbatim.
new_entries_tsv=""
for j in "${!MF_KEYS[@]}"; do
    new_entries_tsv+="${MF_KEYS[$j]}"$'\t'"${MF_OWNERSHIP[$j]}"$'\t'"${MF_HASHES[$j]}"$'\n'
done
merged_tsv="$(printf '%s' "$new_entries_tsv" | node "$SCRIPT_DIR/scripts/lib/manifest-merge.mjs" "$manifest_path")"
MF_KEYS=()
MF_OWNERSHIP=()
MF_HASHES=()
if [[ -n "$merged_tsv" ]]; then
    while IFS=$'\t' read -r m_key m_own m_hash; do
        MF_KEYS+=("$m_key")
        MF_OWNERSHIP+=("$m_own")
        MF_HASHES+=("$m_hash")
    done <<< "$merged_tsv"
fi

# Collect all placeholder key/value pairs for the manifest
declare -a MPH_KEYS=()
declare -a MPH_VALS=()
for i in "${!PH_KEYS[@]}"; do
    bare="${PH_KEYS[$i]#\{\{}"
    bare="${bare%\}\}}"
    MPH_KEYS+=("$bare")
    MPH_VALS+=("${PH_VALS[$i]}")
done

{
    echo "{"
    echo "  \"manifest_version\": 3,"
    echo "  \"variant\": \"$VARIANT\","
    echo "  \"templateRepo\": \"$(json_escape "$SCRIPT_DIR")\","
    echo "  \"template_version\": $template_version_json,"
    echo "  \"template_commit\": \"$template_commit\","
    # >=0.3.2, not >=0.3.0: 0.3.0 and 0.3.1 read a v3 manifest happily but lack
    # the region splice, so applying CLAUDE.md under them overwrites a populated
    # PROJECT-CUSTOM region with the template's empty seed. The floor is enforced
    # at template_load_manifest, so this refuses on every sync after the first --
    # including a consumer who downgrades, or the same repo opened on a machine
    # whose server process is older. It cannot protect the FIRST migration (a v2
    # manifest carries no floor); the sync skill's server_version check does that.
    echo "  \"requires_server\": \">=0.3.2\","
    echo "  \"placeholders\": {"
    last=$((${#MPH_KEYS[@]} - 1))
    for j in $(seq 0 "$last"); do
        comma=","; [[ $j -eq $last ]] && comma=""
        echo "    \"${MPH_KEYS[$j]}\": \"$(json_escape "${MPH_VALS[$j]}")\"$comma"
    done
    echo "  },"
    echo "  \"files\": {"
    last=$((${#MF_KEYS[@]} - 1))
    for j in $(seq 0 "$last"); do
        comma=","; [[ $j -eq $last ]] && comma=""
        echo "    \"${MF_KEYS[$j]}\": {"
        if [[ "${MF_OWNERSHIP[$j]}" == "template" ]]; then
            echo "      \"ownership\": \"template\","
            echo "      \"hash\": \"${MF_HASHES[$j]}\""
        else
            echo "      \"ownership\": \"once\""
        fi
        echo "    }$comma"
    done
    echo "  }"
    echo "}"
} > "$manifest_path"

echo "  [+] .claude/template-manifest.json (generated)"

# --- Generate project-level .mcp.json if any entries apply ---
#
# MUST be the REPO ROOT. Claude Code reads project-scope MCP servers only from
# <project-root>/.mcp.json; <project>/.claude/.mcp.json is an open upstream
# feature request, not current behaviour. Earlier versions of this script wrote
# the .claude/ path, so those servers never loaded.
mcp_json_content="$(build_project_mcp_json)"
if [[ -n "$mcp_json_content" ]]; then
    mcp_json_path="$TARGET_DIR/.mcp.json"
    legacy_mcp_path="$TARGET_DIR/.claude/.mcp.json"

    if [[ -f "$legacy_mcp_path" ]]; then
        echo "  [!] .claude/.mcp.json found — that path is NOT read by Claude Code."
        echo "      Its servers have never loaded. Merge anything you need into .mcp.json, then delete it."
    fi

    if [[ -f "$mcp_json_path" ]] && [[ "$FORCE" != true ]]; then
        # Never clobber a hand-maintained root file — several repos already have one.
        echo "  [-] .mcp.json (exists — left untouched; use --force to overwrite)"
        echo "      Servers this variant would add: $(printf '%s' "$mcp_json_content" | grep -o '"[a-zA-Z_-]*": *{' | sed 's/": *{//; s/"//' | tr '\n' ' ')"
    else
        printf '%s' "$mcp_json_content" > "$mcp_json_path"
        echo "  [+] .mcp.json (generated at repo root)"
    fi
fi

# --- Check for remaining placeholders ---
echo ""
print_remaining_placeholders
print_branch_protection

echo ""
print_automode_snippet

echo ""
print_template_sync_snippet

# --- v4.0.1 item 22: verify the freshly-bootstrapped project (last step) ---
#
# TS_WIN_EXE is resolved above, once, before the dry-run/real-run fork; it is
# set only when the exe was verified to resolve in the Win32 namespace the
# consumer (claude.exe) actually reads from (or, on a POSIX host, is just the
# raw path). A FAIL line is reported, not fatal -- setup's job is done by
# this point; the user reads the lines and the remedy text names the fix.
if [[ -n "${TS_WIN_EXE:-}" ]]; then
    echo ""
    echo "Verifying the bootstrap:"
    verify_repo_arg="$SCRIPT_DIR"
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v cygpath >/dev/null 2>&1; then
                verify_repo_arg="$(cygpath -w "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")"
            fi
            ;;
    esac
    # `|| verify_rc=$?` (not a bare statement) is required under `set -e`: a
    # FAIL line makes the exe exit 1, and a bare statement's unguarded
    # nonzero exit would abort the whole bootstrap under `set -euo pipefail`.
    # This step's contract is that a verify FAIL is reported, never fatal to
    # setup -- `|| verify_rc=$?` is what `set -e` cannot see as an error, so
    # it is what keeps that contract instead of silently breaking it.
    verify_rc=0
    ( cd "$TARGET_DIR" && "$TS_EXE" --verify . --template-repo "$verify_repo_arg" ) || verify_rc=$?
    if [[ "$verify_rc" -ne 0 ]]; then
        echo "  (verify reported FAIL line(s) above -- not fatal to setup; each remedy names the fix)"
    fi
fi

echo ""
