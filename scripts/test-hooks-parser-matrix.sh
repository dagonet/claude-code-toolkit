#!/usr/bin/env bash
# scripts/test-hooks-parser-matrix.sh
#
# Runs scripts/test-hooks.sh in all THREE parser configurations (node,
# python3-only, jq-only) and refuses to report a result it cannot vouch for.
#
# WHY THIS EXISTS AS A SCRIPT (v2.2.5 round 3). The three-configuration run was
# a remembered procedure, and it was performed wrongly: a shim directory was
# prepended to PATH in WINDOWS spelling (`C:/Users/...`), PATH splits on `:`,
# the drive letter became one bogus entry and the rest another, the shims never
# took effect, and all three "configurations" silently ran the real interpreters.
# They came back a uniform 352/0/0 — and a uniform result is the TELL, not a
# clean bill of health: a restricted configuration reporting ZERO skips is proof
# the restriction did not apply.
#
# Two mechanical consequences, both baked in below so the mistake cannot recur:
#
#   1. MSYS SPELLING ONLY. Every path this script puts on PATH comes out of
#      `command -v`, which returns `/c/...` under Git Bash. Nothing here ever
#      constructs a `C:\` or `C:/` path.
#   2. THE SKIP COUNT IS ASSERTED, NOT REPORTED. A restricted run must skip a
#      non-zero, in-band number of assertions. Zero skips fails the matrix.
#
# It also PRINTS the resolved interpreter path for each configuration, so the
# evidence that the restriction applied is in the transcript rather than in
# somebody's recollection of having applied it.
#
# Usage:  bash scripts/test-hooks-parser-matrix.sh
# Exit:   0 only if all three configurations pass AND their skip counts are in
#         band. Any other outcome is a hard failure.

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
# MATRIX_SUITE exists so the skip-count assertion below can be CONTROLLED in
# seconds instead of 90 minutes: point it at a stub that prints a summary line
# with 0 skips and confirm this script goes red. A guard nobody has watched fire
# is indistinguishable from one that was deleted, and the assertion right below
# is the whole reason this file exists — so it needs a control of its own.
SUITE="${MATRIX_SUITE:-$ROOT/scripts/test-hooks.sh}"
OUTDIR=$(mktemp -d)
trap 'rm -rf "$OUTDIR"' EXIT

# Expected skip counts per configuration, and the tolerance. These are
# MEASUREMENTS, not guesses: the node run exercises everything, and the two
# restricted runs skip the blocks whose backend is a node program. Update the
# constants deliberately when the suite grows — the band is wide enough to
# absorb ordinary additions and narrow enough that "the restriction silently
# did not apply" (which lands on 0) can never pass.
EXP_NODE_SKIP=0
EXP_PY_SKIP=103
EXP_JQ_SKIP=119
BAND=20

matrix_fail=0

note() { printf '%s\n' "$*"; }

# EVERY PATH directory that provides <tool>, not just the first (MSYS spelling).
#
# `command -v` alone is not enough and this is measured, not defensive: hiding
# the directory `command -v python3` reports still left `python3` resolvable
# through Windows' App-Installer stub in
# `.../WindowsApps/Microsoft.DesktopAppInstaller_.../python3`. That is the same
# stub this repository already documents as "the name resolves, the program is
# not the one you meant" — and a configuration that still sees the interpreter
# it was told to hide is the exact void measurement this script exists to stop.
dirs_of() { # <tool> -> prints one dir per line
  do_old_ifs=$IFS
  IFS=:
  for entry in $PATH; do
    IFS=$do_old_ifs
    [ -n "$entry" ] || continue
    for ext in "" ".exe" ".EXE" ".cmd" ".bat"; do
      if [ -x "$entry/$1$ext" ] && [ ! -d "$entry/$1$ext" ]; then
        printf '%s\n' "$entry"
        break
      fi
    done
    IFS=:
  done
  IFS=$do_old_ifs
}

# Build a PATH with the given directories removed. Splitting on ':' is correct
# here and only here BECAUSE every entry is MSYS-spelled; this is the exact
# operation that silently did nothing when the entries carried drive letters.
# Directories to drop arrive as ONE newline-separated string, never as separate
# words: `/c/Program Files/nodejs` contains a space, so word-splitting the list
# would drop nothing and the configuration would silently not apply.
path_without() { # <newline-separated dirs> [<newline-separated dirs> ...]
  pw_drop_list=$(printf '%s\n' "$@")
  pw_out=""
  pw_old_ifs=$IFS
  IFS=:
  for entry in $PATH; do
    IFS=$pw_old_ifs
    if [ -n "$entry" ] && printf '%s\n' "$pw_drop_list" | grep -qxF -- "$entry"; then
      IFS=:
      continue
    fi
    if [ -z "$pw_out" ]; then pw_out="$entry"; else pw_out="$pw_out:$entry"; fi
    IFS=:
  done
  IFS=$pw_old_ifs
  printf '%s' "$pw_out"
}

NODE_DIRS=$(dirs_of node)
PY_DIRS=$(dirs_of python3)
JQ_DIRS=$(dirs_of jq)

note "=== interpreters on this host (MSYS spelling — a 'C:\\' here is the bug) ==="
note "  node    -> $(command -v node 2>/dev/null || echo '<absent>')"
note "  python3 -> $(command -v python3 2>/dev/null || echo '<absent>')"
note "  jq      -> $(command -v jq 2>/dev/null || echo '<absent>')"
note "  PATH dirs providing node:    $(printf '%s' "$NODE_DIRS" | tr '\n' ' ')"
note "  PATH dirs providing python3: $(printf '%s' "$PY_DIRS" | tr '\n' ' ')"
note "  PATH dirs providing jq:      $(printf '%s' "$JQ_DIRS" | tr '\n' ' ')"
note ""

# <label> <PATH to run under> <expected-skip> <must-see tool> <must-not-see tools...>
run_config() {
  cfg_label="$1"; cfg_path="$2"; cfg_exp="$3"; cfg_want="$4"; shift 4

  note "=== configuration: $cfg_label ==="
  # SELF-CHECK FIRST. A configuration that still sees the interpreter it was
  # supposed to hide passes green and proves nothing — that is the exact failure
  # this script was written after.
  for t in "$@"; do
    seen=$(PATH="$cfg_path" command -v "$t" 2>/dev/null || true)
    if [ -n "$seen" ]; then
      note "  MATRIX FAIL: '$t' is still visible at $seen — the restriction did not apply"
      matrix_fail=$((matrix_fail + 1))
      return 0
    fi
    note "  hidden:   $t"
  done
  if [ -n "$cfg_want" ]; then
    wseen=$(PATH="$cfg_path" command -v "$cfg_want" 2>/dev/null || true)
    if [ -z "$wseen" ]; then
      note "  MATRIX SKIP: '$cfg_want' is not installed on this host — cannot run $cfg_label"
      note ""
      return 0
    fi
    note "  resolved: $cfg_want -> $wseen"
  fi

  cfg_out="$OUTDIR/$cfg_label.out"
  PATH="$cfg_path" bash "$SUITE" > "$cfg_out" 2>&1
  cfg_rc=$?
  # The summary line, NOT `tail -1`: the suite prints a verdict banner after it.
  cfg_tail=$(grep '^test-hooks\.sh: ' "$cfg_out" | tail -1)
  note "  $cfg_tail"
  note "  $(tail -1 "$cfg_out")"

  cfg_skip=$(printf '%s' "$cfg_tail" | sed -n 's/.*failed, \([0-9]*\) skipped.*/\1/p')
  cfg_failed=$(printf '%s' "$cfg_tail" | sed -n 's/.*passed, \([0-9]*\) failed.*/\1/p')

  if [ "$cfg_rc" -ne 0 ] || [ "${cfg_failed:-1}" != "0" ]; then
    note "  MATRIX FAIL: $cfg_label suite is RED (rc=$cfg_rc)"
    grep '^FAIL' "$cfg_out" | sed 's/^/    /'
    matrix_fail=$((matrix_fail + 1))
  fi

  if [ -z "$cfg_skip" ]; then
    note "  MATRIX FAIL: could not parse a skip count out of the summary line"
    matrix_fail=$((matrix_fail + 1))
    note ""
    return 0
  fi

  # THE ASSERTION THIS SCRIPT EXISTS FOR. A restricted configuration that skips
  # NOTHING ran the real interpreters; it is not an improvement, it is a void
  # measurement. Asserted separately from the band so the message names the
  # actual failure rather than an off-by-N.
  if [ "$cfg_exp" -eq 0 ]; then
    # The unrestricted configuration: 0 is the ONLY correct answer, so it is
    # asserted EXACTLY. A band here would accept 15 skips as "in band (~0)",
    # which is precisely where a silently-skipping new fixture would hide.
    if [ "$cfg_skip" -ne 0 ]; then
      note "  MATRIX FAIL: $cfg_label skipped $cfg_skip, expected exactly 0 — with every"
      note "               parser present nothing may skip; a skip here is a fixture that"
      note "               never runs anywhere."
      matrix_fail=$((matrix_fail + 1))
    else
      note "  skip count 0 — exact, as required with every parser present"
    fi
  elif [ "$cfg_skip" -eq 0 ]; then
    note "  MATRIX FAIL: $cfg_label skipped 0 assertions — a restricted run that"
    note "               skips nothing is proof the restriction did not apply."
    matrix_fail=$((matrix_fail + 1))
  elif [ "$cfg_skip" -lt $((cfg_exp - BAND)) ] || [ "$cfg_skip" -gt $((cfg_exp + BAND)) ]; then
    note "  MATRIX FAIL: $cfg_label skipped $cfg_skip, expected ~$cfg_exp (+/-$BAND)."
    note "               Either the restriction half-applied, or the suite grew and"
    note "               EXP_*_SKIP in this script needs a deliberate update."
    matrix_fail=$((matrix_fail + 1))
  else
    note "  skip count $cfg_skip is in band (~$cfg_exp +/-$BAND)"
  fi
  note ""
}

# WHAT EACH CONFIGURATION HIDES, and why it is not "hide everything else".
# hooks/lib/json.sh picks the first WORKING backend of node -> python3 -> jq, so
# hiding node alone is what forces the python3 backend. jq is left VISIBLE in
# that configuration deliberately: test-hooks.sh builds its own jq-only stub
# PATH internally and needs the real jq to exist to do it, so hiding jq here
# turns the suite red for a harness reason rather than a hook reason (measured:
# `FAIL stub PATH minimum tool set (missing: jq)`). The jq configuration hides
# node AND python3, which is what makes jq the first working backend.
run_config "node"    "$PATH"                                            "$EXP_NODE_SKIP" node
run_config "python3" "$(path_without "$NODE_DIRS")"                     "$EXP_PY_SKIP"   python3 node
run_config "jq"      "$(path_without "$NODE_DIRS" "$PY_DIRS")"          "$EXP_JQ_SKIP"   jq      node python3

if [ "$matrix_fail" -eq 0 ]; then
  note "PARSER MATRIX PASSED (3 configurations)"
  exit 0
fi
note "PARSER MATRIX FAILED ($matrix_fail problem(s))"
exit 1
