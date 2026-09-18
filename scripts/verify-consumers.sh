#!/usr/bin/env bash
# verify-consumers.sh <dir>...
#
# Runs `template_verify` (mode=post_commit) against each given consumer
# checkout, using the toolkit's OWN installed template-sync-tools exe
# (server/.venv), and prints one summary line per consumer. Exits non-zero
# if any consumer's `ok` is false.
#
# The `unknown_keys_empty` line FAILS, BY DESIGN, on every consumer that has
# not yet synced on toolkit >= 4.0.1 -- its remedy text says so. A fleet run
# right after this release ships is expected to print FAILs for every
# not-yet-synced consumer; that is the release's own "who still needs to
# sync" report, not a defect in this script. Re-run after each consumer's
# `/sync-template` to watch the fleet turn green one row at a time.
#
# R28: paths handed to a Windows executable are bare/relative or converted
# with `cygpath -w` -- never handed an MSYS path directly. This script `cd`s
# into each consumer directory and passes `.` (bare, relative), and converts
# $TOOLKIT to its Win32 form before passing it as --template-repo.
#
# Branch hygiene, if ever added: key on the REMOTE (`git ls-remote --heads`)
# or squash-tolerant semantics (`git cherry`, tree equality) -- after a
# squash merge `git branch -d` refuses the local sync branch while the
# remote delete succeeds (Yutraffic, open-brain 2026-09-17).

set -u

HERE="$(cd "$(dirname "$0")/.." && pwd)"
TOOLKIT="$HERE"

if [ "$#" -eq 0 ]; then
    echo "usage: bash scripts/verify-consumers.sh <dir>..." >&2
    exit 2
fi

TS_EXE=""
for cand in "$TOOLKIT/server/.venv/Scripts/mcp-template-sync-tools.exe" "$TOOLKIT/server/.venv/bin/mcp-template-sync-tools"; do
    if [ -x "$cand" ]; then
        TS_EXE="$cand"
        break
    fi
done
if [ -z "$TS_EXE" ]; then
    echo "template-sync-tools not installed under $TOOLKIT/server/.venv -- run 'bash server/install.sh' first" >&2
    exit 2
fi

case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        if command -v cygpath >/dev/null 2>&1; then
            TEMPLATE_REPO_ARG="$(cygpath -w "$TOOLKIT" 2>/dev/null || echo "$TOOLKIT")"
        else
            echo "cygpath not found -- cannot convert $TOOLKIT to a Win32 path for the exe" >&2
            exit 2
        fi
        ;;
    *)
        TEMPLATE_REPO_ARG="$TOOLKIT"
        ;;
esac

rc=0
for dir in "$@"; do
    if [ ! -d "$dir" ]; then
        printf '%-30s SKIP (no such directory: %s)\n' "$(basename "$dir")" "$dir"
        rc=1
        continue
    fi
    out="$(cd "$dir" && "$TS_EXE" --verify . --template-repo "$TEMPLATE_REPO_ARG" --mode post_commit 2>&1)"
    line_rc=$?
    summary="$(printf '%s\n' "$out" | tail -1)"
    printf '%-30s %s\n' "$(basename "$dir")" "$summary"
    if [ "$line_rc" -ne 0 ]; then
        rc=1
    fi
done

exit "$rc"
