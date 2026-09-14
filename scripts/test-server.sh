#!/usr/bin/env bash
# scripts/test-server.sh — third gate command (v4.0): the template-sync server
# suite, run in server/.venv. A MISSING venv is an error, not a skip: the gate
# must not read green because the thing it tests was never installed. Run
# `bash server/install.sh` once per checkout.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if   [ -x "$HERE/server/.venv/Scripts/python.exe" ]; then VPY="$HERE/server/.venv/Scripts/python.exe"
elif [ -x "$HERE/server/.venv/bin/python" ];         then VPY="$HERE/server/.venv/bin/python"
else
  echo "test-server.sh: server/.venv not found -- run 'bash server/install.sh' once per checkout" >&2
  exit 2
fi

# --basetemp outside the checkout: keeps `git status` clean -- gate runs must
# not leave test scratch files as untracked repo content, and a basetemp under
# this checkout would show up there. `mktemp -d` (no TMPDIR override) lands
# outside the repo on this host. A fresh dir per run, removed after.
BASETEMP="$(mktemp -d 2>/dev/null || mktemp -d -t test-server)"
trap 'rm -rf "$BASETEMP"' EXIT
"$VPY" -m pytest "$HERE/server/tests" -q --basetemp="$BASETEMP"
rc=$?
rm -rf "$BASETEMP"
exit "$rc"
