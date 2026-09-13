#!/usr/bin/env bash
# server/install.sh — create server/.venv and install the package EDITABLE.
# Editable, so a later `git pull` advances the server at the next restart
# without a reinstall; reinstalling into a running venv is the one measured way
# to break it (locked launcher executables, no shim mid-flight).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "install.sh: no python3/python on PATH" >&2; exit 2; }
[ -d "$HERE/.venv" ] || "$PY" -m venv "$HERE/.venv"
if [ -x "$HERE/.venv/Scripts/python.exe" ]; then VPY="$HERE/.venv/Scripts/python.exe"; EXE="$HERE/.venv/Scripts/mcp-template-sync-tools.exe"
else VPY="$HERE/.venv/bin/python"; EXE="$HERE/.venv/bin/mcp-template-sync-tools"; fi
# stdout is the CONTRACT: the exe path and nothing else. setup-project captures
# it with $(...), and pip writes progress to stdout even under --quiet on some
# versions -- so pip's stdout goes to stderr, unconditionally.
"$VPY" -m pip install --quiet --upgrade pip 1>&2
# cd + relative ".[dev]" -- not "$HERE[dev]" -- deliberately: on Git Bash for
# Windows, HERE is an MSYS POSIX-style path (e.g. /g/...), and MSYS's argv
# auto-conversion to a Windows path fires only for a bare path token. Appending
# "[dev]" breaks that heuristic, so pip's own native python.exe receives the
# unconverted /g/... string and rejects it as "not a valid editable requirement".
# A relative path has no leading slash, so no conversion is attempted.
( cd "$HERE" && "$VPY" -m pip install --quiet -e ".[dev]" 1>&2 )
[ -x "$EXE" ] || { echo "install.sh: expected console script not found at $EXE" >&2; exit 3; }
# The path is published into ~/.claude.json and spawned by a Win32 process:
# publish it in THAT namespace. Internal checks above stay on the MSYS path.
if command -v cygpath >/dev/null 2>&1; then echo "$(cygpath -w "$EXE")"; else echo "$EXE"; fi
