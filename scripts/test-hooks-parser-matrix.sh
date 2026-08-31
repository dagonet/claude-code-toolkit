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
SUITE="$ROOT/scripts/test-hooks.sh"
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

# Resolve an interpreter to its containing directory, MSYS spelling.
dir_of() { # <tool> -> prints dir, or empty
  p=$(command -v "$1" 2>/dev/null) || p=""
  [ -n "$p" ] || return 0
  dirname "$p"
}

# Build a PATH with the given directories removed. Splitting on ':' is correct
# here and only here BECAUSE every entry is MSYS-spelled; this is the exact
# operation that silently did nothing when the entries carried drive letters.
path_without() { # <dir> [<dir> ...]
  pw_out=""
  pw_old_ifs=$IFS
  IFS=:
  for entry in $PATH; do
    pw_drop=0
    for d in "$@"; do
      [ -n "$d" ] && [ "$entry" = "$d" ] && pw_drop=1
    done
    [ "$pw_drop" = "1" ] && continue
    if [ -z "$pw_out" ]; then pw_out="$entry"; else pw_out="$pw_out:$entry"; fi
  done
  IFS=$pw_old_ifs
  printf '%s' "$pw_out"
}

NODE_DIR=$(dir_of node)
PY_DIR=$(dir_of python3)
JQ_DIR=$(dir_of jq)

note "=== interpreters on this host (MSYS spelling — a 'C:\\' here is the bug) ==="
note "  node    -> ${NODE_DIR:-<absent>}/node"
note "  python3 -> ${PY_DIR:-<absent>}/python3"
note "  jq      -> ${JQ_DIR:-<absent>}/jq"
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
  cfg_tail=$(tail -1 "$cfg_out")
  note "  $cfg_tail"

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
  if [ "$cfg_exp" -gt 0 ] && [ "$cfg_skip" -eq 0 ]; then
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

run_config "node"    "$PATH"                                  "$EXP_NODE_SKIP" node    ""
run_config "python3" "$(path_without "$NODE_DIR" "$JQ_DIR")"  "$EXP_PY_SKIP"   python3 node jq
run_config "jq"      "$(path_without "$NODE_DIR" "$PY_DIR")"  "$EXP_JQ_SKIP"   jq      node python3

if [ "$matrix_fail" -eq 0 ]; then
  note "PARSER MATRIX PASSED (3 configurations)"
  exit 0
fi
note "PARSER MATRIX FAILED ($matrix_fail problem(s))"
exit 1
