#!/usr/bin/env bash
# scripts/test-server.sh — third gate command (v4.0): the template-sync server
# suite, run in server/.venv. A MISSING venv is an error, not a skip: the gate
# must not read green because the thing it tests was never installed. Run
# `bash server/install.sh` once per checkout.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TS_VENV_DIR: where the server venv lives. Default server/.venv. Check 46 in
# verify-template-consistency.sh points this at an EMPTY directory to prove the
# no-venv arm below without touching the real venv (v4.0.1, item 11).
VENV="${TS_VENV_DIR:-$HERE/server/.venv}"
if   [ -x "$VENV/Scripts/python.exe" ]; then VPY="$VENV/Scripts/python.exe"
elif [ -x "$VENV/bin/python" ];         then VPY="$VENV/bin/python"
else
  echo "test-server.sh: no python found under $VENV (probed Scripts/python.exe and bin/python) -- run 'bash server/install.sh' once per checkout" >&2
  exit 2
fi
# v4.0.1 (fix round 1, constraint 9): name what was tested on the path that
# actually runs the suite too, not only on the no-venv error path -- a green
# gate run used to say nothing about which venv it used. STDERR only, and
# safe there: check 46 captures this script's combined output (`2>&1`) but
# only to probe the NO-VENV arm, which `exit 2`s above before this line is
# ever reached; on the has-venv arm this line runs but goes to stderr, so
# stdout -- what the gate and any pytest-output scraping actually read --
# stays machine-clean either way.
echo "test-server.sh: using venv $VENV" >&2

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
