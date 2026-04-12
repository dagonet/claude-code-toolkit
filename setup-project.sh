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
WORKTREE_BASE=""
LOG_PATH=""
MAUI_PROJECT=""
TEST_PROJECT=""
BUILD_TOOL=""
JAVA_VERSION=""
PACKAGE_MANAGER=""
PYTHON_VERSION=""
MCP_DEV_SERVERS_PATH=""
SQLITE_DB_PATH=""
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
        --force)           FORCE=true; shift ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)
            sed -n '3,11p' "$0"
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

# --- Build placeholder replacement map ---
# Parallel arrays for bash 3 compatibility (macOS ships bash 3)
declare -a PH_KEYS=()
declare -a PH_VALS=()

add_replacement() { PH_KEYS+=("$1"); PH_VALS+=("$2"); }

PROJECT_NAME_LOWER="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')"
add_replacement '{{PROJECT_NAME}}' "$PROJECT_NAME"
add_replacement '{{PROJECT_NAME_LOWER}}' "$PROJECT_NAME_LOWER"

[[ -n "$REPO_URL" ]]      && add_replacement '{{REPO_URL}}' "$REPO_URL"
[[ -n "$SOLUTION_FILE" ]]  && add_replacement '{{SOLUTION_FILE}}' "$SOLUTION_FILE"
[[ -n "$TECH_STACK" ]]     && add_replacement '{{TECH_STACK}}' "$TECH_STACK"
[[ -n "$WORKTREE_BASE" ]]  && add_replacement '{{WORKTREE_BASE}}' "$WORKTREE_BASE"
[[ -n "$LOG_PATH" ]]       && add_replacement '{{LOG_PATH}}' "$LOG_PATH"
[[ -n "$MAUI_PROJECT" ]]   && add_replacement '{{MAUI_PROJECT}}' "$MAUI_PROJECT"
[[ -n "$TEST_PROJECT" ]]   && add_replacement '{{TEST_PROJECT}}' "$TEST_PROJECT"
[[ -n "$DB_PATH" ]]        && add_replacement '{{DB_DIRECTORY}}' "$DB_PATH"
[[ -n "$DB_FILENAME" ]]    && add_replacement '{{DB_FILENAME}}' "$DB_FILENAME"
[[ -n "$DB_PATH" && -n "$DB_FILENAME" ]] && add_replacement '{{DB_PATH}}' "$DB_PATH/$DB_FILENAME"

# Auto-derived: dotnet build commands
if [[ "$VARIANT" == "dotnet" || "$VARIANT" == "dotnet-maui" ]] && [[ -n "$SOLUTION_FILE" ]]; then
    add_replacement '{{BUILD_COMMAND}}' "dotnet build $SOLUTION_FILE"
    add_replacement '{{TEST_COMMAND}}' "dotnet test"
fi

# Auto-derived: rust-tauri defaults
if [[ "$VARIANT" == "rust-tauri" && -z "$TECH_STACK" ]]; then
    add_replacement '{{TECH_STACK}}' "Tauri v2, Rust, TypeScript, SolidJS, SQLite"
fi

# Auto-derived: Python variant
if [[ "$VARIANT" == "python" ]]; then
    py_pkg="${PACKAGE_MANAGER:-pip}"
    py_ver="${PYTHON_VERSION:-3.12}"
    add_replacement '{{PYTHON_VERSION}}' "$py_ver"
    case "$py_pkg" in
        poetry)
            add_replacement '{{BUILD_COMMAND}}' "poetry run pytest"
            add_replacement '{{TEST_COMMAND}}' "poetry run pytest"
            add_replacement '{{FORMAT_COMMAND}}' "poetry run ruff format ."
            add_replacement '{{LINT_COMMAND}}' "poetry run ruff check ."
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Python $py_ver, Poetry"
            ;;
        uv)
            add_replacement '{{BUILD_COMMAND}}' "uv run pytest"
            add_replacement '{{TEST_COMMAND}}' "uv run pytest"
            add_replacement '{{FORMAT_COMMAND}}' "uv run ruff format ."
            add_replacement '{{LINT_COMMAND}}' "uv run ruff check ."
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Python $py_ver, uv"
            ;;
        *)
            add_replacement '{{BUILD_COMMAND}}' "python -m pytest"
            add_replacement '{{TEST_COMMAND}}' "python -m pytest"
            add_replacement '{{FORMAT_COMMAND}}' "ruff format ."
            add_replacement '{{LINT_COMMAND}}' "ruff check ."
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
            add_replacement '{{BUILD_COMMAND}}' "./gradlew build"
            add_replacement '{{TEST_COMMAND}}' "./gradlew test"
            add_replacement '{{FORMAT_COMMAND}}' "./gradlew spotlessApply"
            add_replacement '{{LINT_COMMAND}}' "./gradlew spotlessCheck"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Java $java_ver, Spring Boot, Gradle"
            ;;
        *)
            add_replacement '{{BUILD_COMMAND}}' "mvn clean verify"
            add_replacement '{{TEST_COMMAND}}' "mvn test"
            add_replacement '{{FORMAT_COMMAND}}' "mvn spotless:apply"
            add_replacement '{{LINT_COMMAND}}' "mvn spotless:check"
            [[ -z "$TECH_STACK" ]] && add_replacement '{{TECH_STACK}}' "Java $java_ver, Spring Boot, Maven"
            ;;
    esac
fi

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
                out+='      "command": "python",'$'\n'
                out+='      "args": ["'"$(json_escape "$MCP_DEV_SERVERS_PATH/src/dotnet_mcp.py")"'"]'$'\n'
                out+='    }'"$comma"$'\n'
                ;;
            rust-tools)
                out+='    "rust-tools": {'$'\n'
                out+='      "command": "python",'$'\n'
                out+='      "args": ["'"$(json_escape "$MCP_DEV_SERVERS_PATH/src/rust_mcp.py")"'"]'$'\n'
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

for name in CLAUDE.md CLAUDE.local.md AGENT_TEAM.md PROJECT_CONTEXT.md PROJECT_STATE.md; do
    if [[ -f "$TEMPLATE_DIR/$name" ]]; then
        FILE_SOURCES+=("$TEMPLATE_DIR/$name")
        FILE_RELS+=("$name")
        FILE_IS_GITIGNORE+=(false)
    fi
done

for name in .editorconfig rustfmt.toml .prettierrc; do
    if [[ -f "$TEMPLATE_DIR/$name" ]]; then
        FILE_SOURCES+=("$TEMPLATE_DIR/$name")
        FILE_RELS+=("$name")
        FILE_IS_GITIGNORE+=(false)
    fi
done

if [[ -f "$TEMPLATE_DIR/gitignore" ]]; then
    FILE_SOURCES+=("$TEMPLATE_DIR/gitignore")
    FILE_RELS+=(".gitignore")
    FILE_IS_GITIGNORE+=(true)
fi

if [[ -d "$TEMPLATE_DIR/.claude" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$TEMPLATE_DIR/"}"
        FILE_SOURCES+=("$file")
        FILE_RELS+=("$rel")
        FILE_IS_GITIGNORE+=(false)
    done < <(find "$TEMPLATE_DIR/.claude" -type f -print0 | sort -z)
fi

# Shared hook scripts (from repo root, not template-specific)
if [[ -d "$SCRIPT_DIR/hooks" ]]; then
    while IFS= read -r -d '' file; do
        rel="${file#"$SCRIPT_DIR/"}"
        FILE_SOURCES+=("$file")
        FILE_RELS+=("$rel")
        FILE_IS_GITIGNORE+=(false)
    done < <(find "$SCRIPT_DIR/hooks" -type f -name '*.sh' -print0 | sort -z)
fi

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
        elif [[ -f "$target_file" ]] && [[ "$FORCE" != true ]]; then
            action="SKIP (exists)"
        elif [[ -f "$target_file" ]] && [[ "$FORCE" == true ]]; then
            action="OVERWRITE"
        else
            action="CREATE"
        fi
        echo "  ${FILE_RELS[$i]} -> $action"
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
        echo "Project-level .claude/.mcp.json (would be generated):"
        printf '%s' "$mcp_preview" | sed 's/^/    /'
    else
        echo "Project-level .claude/.mcp.json: (not generated - no entries for this variant/flags)"
    fi
    echo ""
    echo "=== END DRY RUN ==="
    exit 0
fi

# --- Create target directory ---
mkdir -p "$TARGET_DIR"

# --- Copy and process files ---
copied=()
skipped=()

# Manifest tracking
declare -a MF_KEYS=()
declare -a MF_HASHES=()
declare -a MF_RAW_HASHES=()
declare -a MF_MODIFIED=()
declare -a MF_REASONS=()

always_modified="PROJECT_CONTEXT.md"
case "$VARIANT" in
    dotnet|dotnet-maui) variant_coder=".claude/agents/dotnet-coder.md" ;;
    rust-tauri)         variant_coder=".claude/agents/rust-coder.md" ;;
    java)               variant_coder=".claude/agents/java-coder.md" ;;
    python)             variant_coder=".claude/agents/python-coder.md" ;;
    *)                  variant_coder="" ;;
esac

for i in "${!FILE_SOURCES[@]}"; do
    src="${FILE_SOURCES[$i]}"
    rel="${FILE_RELS[$i]}"
    is_gi="${FILE_IS_GITIGNORE[$i]}"
    target_file="$TARGET_DIR/$rel"
    content="$(<"$src")"

    # .gitignore: append or create
    if [[ "$is_gi" == true ]]; then
        if [[ -f "$target_file" ]]; then
            lines_to_add=""
            while IFS= read -r line; do
                trimmed="${line#"${line%%[![:space:]]*}"}"
                trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
                [[ -z "$trimmed" || "$trimmed" == \#* ]] && continue
                if ! grep -qF "$trimmed" "$target_file" 2>/dev/null; then
                    lines_to_add+="$trimmed"$'\n'
                fi
            done <<< "$content"
            if [[ -n "$lines_to_add" ]]; then
                append_block=$'\n'"# Claude Code - machine-specific files"$'\n'"$lines_to_add"
                append_block="$(apply_replacements "$append_block")"
                printf '%s' "$append_block" >> "$target_file"
                copied+=("$rel (appended)")
            else
                skipped+=("$rel (entries already present)")
            fi
        else
            mkdir -p "$(dirname "$target_file")"
            content="$(apply_replacements "$content")"
            printf '%s' "$content" > "$target_file"
            copied+=("$rel")
        fi
        continue
    fi

    # Skip existing unless --force
    if [[ -f "$target_file" ]] && [[ "$FORCE" != true ]]; then
        skipped+=("$rel (exists, use --force to overwrite)")
        continue
    fi

    mkdir -p "$(dirname "$target_file")"
    raw_content="$content"
    content="$(apply_replacements "$content")"
    printf '%s' "$content" > "$target_file"
    copied+=("$rel")

    # Track for manifest
    rel_key="${rel//\\//}"
    is_mod=false
    reason=""
    if [[ "$rel_key" == "$always_modified" ]]; then
        is_mod=true; reason="Project-specific config"
    elif [[ "$rel_key" == "$variant_coder" ]]; then
        is_mod=true; reason="Project-specific agent"
    fi
    MF_KEYS+=("$rel_key")
    MF_HASHES+=("$(content_hash "$content")")
    MF_RAW_HASHES+=("$(content_hash "$raw_content")")
    MF_MODIFIED+=("$is_mod")
    MF_REASONS+=("$reason")
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

# --- Generate template manifest ---
template_head="$(git -C "$SCRIPT_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")"
manifest_path="$TARGET_DIR/.claude/template-manifest.json"
mkdir -p "$(dirname "$manifest_path")"

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
    echo "  \"version\": 2,"
    echo "  \"variant\": \"$VARIANT\","
    echo "  \"templateRepo\": \"$(json_escape "$SCRIPT_DIR")\","
    echo "  \"lastSynced\": \"$template_head\","
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
        echo "      \"templateHash\": \"${MF_HASHES[$j]}\","
        echo "      \"templateRawHash\": \"${MF_RAW_HASHES[$j]}\","
        echo "      \"localHash\": \"${MF_HASHES[$j]}\","
        if [[ -n "${MF_REASONS[$j]}" ]]; then
            echo "      \"locallyModified\": ${MF_MODIFIED[$j]},"
            echo "      \"reason\": \"${MF_REASONS[$j]}\""
        else
            echo "      \"locallyModified\": ${MF_MODIFIED[$j]}"
        fi
        echo "    }$comma"
    done
    echo "  }"
    echo "}"
} > "$manifest_path"

echo "  [+] .claude/template-manifest.json (generated)"

# --- Generate project-level .claude/.mcp.json if any entries apply ---
mcp_json_content="$(build_project_mcp_json)"
if [[ -n "$mcp_json_content" ]]; then
    mcp_json_path="$TARGET_DIR/.claude/.mcp.json"
    if [[ -f "$mcp_json_path" ]] && [[ "$FORCE" != true ]]; then
        echo "  [-] .claude/.mcp.json (exists, use --force to overwrite)"
    else
        mkdir -p "$(dirname "$mcp_json_path")"
        printf '%s' "$mcp_json_content" > "$mcp_json_path"
        echo "  [+] .claude/.mcp.json (generated)"
    fi
fi

# --- Check for remaining placeholders ---
echo ""
has_remaining=false
for f in "${copied[@]}"; do
    clean="${f%% (*}"
    filepath="$TARGET_DIR/$clean"
    [[ ! -f "$filepath" ]] && continue
    while IFS= read -r line; do
        if [[ "$has_remaining" == false ]]; then
            echo "Remaining placeholders to fill manually:"
            has_remaining=true
        fi
        echo "  $clean:$line"
    done < <(grep -n '{{[A-Z_]*}}' "$filepath" 2>/dev/null || true)
done

if [[ "$has_remaining" == false ]]; then
    echo "All placeholders replaced."
fi

echo ""
