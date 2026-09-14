#!/usr/bin/env bash
# server/install.sh — create server/.venv and install the package EDITABLE.
# Editable, so a later `git pull` advances the server at the next restart
# without a reinstall; reinstalling into a running venv is the one measured way
# to break it (locked launcher executables, no shim mid-flight).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || { echo "install.sh: no python3/python on PATH" >&2; exit 2; }
# Ruling R28 (third instance of this repo's MSYS-argv-conversion mechanism --
# a bracket defeated it for pip's requirement argument at line 23/below, an
# apostrophe defeats it here): any MSYS path handed to a Windows executable is
# suspect unless the token is bare -- cd and go relative, or cygpath -w it
# first. A checkout path containing `'` (e.g. an O'Brien user directory)
# defeats MSYS's argv auto-conversion for "$HERE/.venv" the same way a `[dev]`
# suffix defeats it for a pip requirement: Windows Python receives the
# unconverted POSIX string, silently creates the venv relative to the current
# drive instead of under $HERE, and returns rc=0 -- the next line's
# Scripts/python.exe check then fails and the script dies on the POSIX
# fallback. `cd "$HERE" && ... .venv` is a bare relative token; no conversion
# is attempted, so there is nothing for the apostrophe to defeat.
[ -d "$HERE/.venv" ] || ( cd "$HERE" && "$PY" -m venv .venv )
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
if command -v cygpath >/dev/null 2>&1; then
    EXE_OUT="$(cygpath -w "$EXE")"   # a failing cygpath aborts here under set -e, never prints an empty line
else
    EXE_OUT="$EXE"
fi
[ -n "$EXE_OUT" ] || { echo "install.sh: could not publish the exe path" >&2; exit 4; }
echo "$EXE_OUT"
