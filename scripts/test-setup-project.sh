#!/usr/bin/env bash
# test-setup-project.sh
#
# Bootstrap fixtures for setup-project.sh / setup-project.ps1.
#
# WHY THIS FILE EXISTS, specifically:
#
# Both scripts render a file TWICE through two different code paths — one for
# `--dry-run` (report only) and one for the real write — and those two paths
# have now diverged twice, one release apart:
#
#   v2.2.0 PR16  `--dry-run` exited before the "Remaining placeholders" report
#                and the real-run version grepped files on disk. Fixed by
#                computing the report over the RENDERED content in memory.
#   v2.2.1 r5    the protected-branches rewrite was added to render_file (the
#                dry-run path) only. The dry run reported `develop`; the real
#                run wrote `main master`. Caught by running both by hand.
#
# The second one is the point: an adjacent comment saying "do not let these
# diverge" did not prevent the recurrence, because nothing executed both paths
# and compared them. That is what this file does. Anything a consumer's
# bootstrap depends on which is computed on BOTH paths belongs here.
#
# Run from repo root: bash scripts/test-setup-project.sh
# Exit 0 = all cases pass. Exit 1 = at least one FAIL.

set -u
pass=0
fail=0
skipped=0

ROOT=$(pwd)
TMPROOT=$(mktemp -d 2>/dev/null || mktemp -d -t setuptest)
trap 'rm -rf "$TMPROOT"' EXIT

expect() { # <label> <want> <got>
  if [ "$2" = "$3" ]; then
    printf 'PASS  %-52s (%s)\n' "$1" "$3"
    pass=$((pass + 1))
  else
    printf 'FAIL  %-52s (want %s, got %s)\n' "$1" "$2" "$3"
    fail=$((fail + 1))
  fi
}

skip() { # <label> <reason> [count]
  skipped=$((skipped + ${3:-1}))
  printf 'SKIP  %-52s (%s, %s assertion(s))\n' "$1" "$2" "${3:-1}"
}

# --- helpers ---------------------------------------------------------------

# The one line the branch-protection hooks read, from a generated project.
protected_line() { # <project dir>
  grep -E '^- \*\*Protected branches\*\*:' "$1/PROJECT_CONTEXT.md" 2>/dev/null | head -1
}

# The line setup-project PRINTS about branch protection, from either mode.
protected_report() { # <output file>
  grep -E '^Branch protection:' "$1" 2>/dev/null | head -1
}

run_sh() { # <target> <branch> <outfile> [--dry-run]
  mkdir -p "$1"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$1" --default-branch "$2" ${4:+"$4"} > "$3" 2>&1
}

echo "=== setup-project.sh: dry run and real run must agree ==="

# The divergence is only VISIBLE when the resolved trunk is not in the static
# default, so `develop` is the load-bearing case; `main` is the control that
# proves the comparison is not vacuous.
for branch in develop main; do
  DRY="$TMPROOT/$branch-dry"
  REAL="$TMPROOT/$branch-real"
  DRYOUT="$TMPROOT/$branch-dry.out"
  REALOUT="$TMPROOT/$branch-real.out"

  run_sh "$DRY"  "$branch" "$DRYOUT" --dry-run
  run_sh "$REAL" "$branch" "$REALOUT"

  dry_report=$(protected_report "$DRYOUT")
  real_report=$(protected_report "$REALOUT")
  real_line=$(protected_line "$REAL")

  # 1. The report a user reads before committing to the run must be the report
  #    they get from the run. This is the assertion that failed in r5.
  expect "[$branch] dry-run report == real-run report" "$dry_report" "$real_report"

  # 2. ... and the report must describe the file that was actually written.
  #    Report equality alone would still pass if BOTH paths were wrong.
  case "$branch" in
    develop) want_line="- **Protected branches**: develop" ;;
    *)       want_line="- **Protected branches**: main master" ;;
  esac
  expect "[$branch] written line matches the report" "$want_line" "$real_line"

  # 3. No placeholder survives on that line — the v2.2.0 fail-open shape.
  case "$real_line" in
    *'{{'*) got_ph=1 ;;
    *)      got_ph=0 ;;
  esac
  expect "[$branch] no placeholder on the protected line" 0 "$got_ph"
done

# A rerun over an existing PROJECT_CONTEXT.md must SAY the file was kept, not
# claim a protection it did not write.
RERUN_OUT="$TMPROOT/develop-rerun.out"
run_sh "$TMPROOT/develop-real" develop "$RERUN_OUT"
expect "rerun reports that the file was not written" 1 \
  "$(grep -c 'was NOT written' "$RERUN_OUT")"

# --- WORKTREE_BASE: a DEFAULT, not a constant (v2.2.6) ---------------------
#
# The field used to default to empty, which left `{{WORKTREE_BASE}}` in the
# rendered PROJECT_CONTEXT.md of every bootstrap that did not pass the flag.
# Two things have to hold and neither is implied by the other: a plain run
# fills the field, and an explicit flag still overrides it.
#
# The expected value is read from setup-project.sh rather than restated here —
# verify-template-consistency.sh check 26b is what pins that value across the
# .ps1 and the six gitignores. This fixture asserts it REACHES the file.
WTB_DEFAULT=$(grep -E '^WORKTREE_BASE="' "$ROOT/setup-project.sh" | head -1 | sed 's/^WORKTREE_BASE="//; s/".*$//')

worktree_line() { # <project dir>
  grep -E '^- \*\*Worktree base\*\*:' "$1/PROJECT_CONTEXT.md" 2>/dev/null | head -1
}

if [ -z "$WTB_DEFAULT" ]; then
  # Refuse rather than compare against an empty string, which every line matches.
  expect "WORKTREE_BASE default is readable from setup-project.sh" "non-empty" ""
else
  # Fresh dirs: a rerun over an existing PROJECT_CONTEXT.md is not written at
  # all, and the assertion would read a stale file.
  WTBDIR="$TMPROOT/wtb-default"
  mkdir -p "$WTBDIR"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$WTBDIR" > "$TMPROOT/wtb-default.out" 2>&1
  expect "default bootstrap fills the worktree base" \
    "- **Worktree base**: $WTB_DEFAULT" "$(worktree_line "$WTBDIR")"

  WTBOVR="$TMPROOT/wtb-override"
  mkdir -p "$WTBOVR"
  bash "$ROOT/setup-project.sh" --variant general --project-name SetupFixture \
    --target-path "$WTBOVR" --worktree-base "custom/wt" > "$TMPROOT/wtb-override.out" 2>&1
  expect "--worktree-base still overrides the default" \
    "- **Worktree base**: custom/wt" "$(worktree_line "$WTBOVR")"
fi

# --- the PowerShell half, where it can run ---------------------------------
#
# The two scripts are independent implementations of the same contract, and the
# same two-path shape exists in both — so parity is asserted, not assumed.
PSBIN=""
for c in pwsh powershell; do
  command -v "$c" >/dev/null 2>&1 && { PSBIN=$c; break; }
done
if [ -n "$PSBIN" ] && [ -f "$ROOT/setup-project.ps1" ]; then
  PSDIR="$TMPROOT/ps-develop"
  mkdir -p "$PSDIR"
  "$PSBIN" -NoProfile -ExecutionPolicy Bypass -File "$ROOT/setup-project.ps1" \
    -Variant general -ProjectName SetupFixture -TargetPath "$PSDIR" \
    -DefaultBranch develop > "$TMPROOT/ps-develop.out" 2>&1
  expect "ps1 writes the same protected line as sh" \
    "- **Protected branches**: develop" "$(protected_line "$PSDIR")"
  # No -WorktreeBase passed: the .ps1 parameter default must reach the file
  # through BOTH `if ($WorktreeBase)` sites, exactly as the .sh default does.
  expect "ps1 writes the same worktree base as sh" \
    "- **Worktree base**: $WTB_DEFAULT" "$(worktree_line "$PSDIR")"
else
  skip "setup-project.ps1 parity" "no PowerShell on this host" 2
fi

echo "----------------------------------------------------------------"
echo "test-setup-project.sh: $pass passed, $fail failed, $skipped skipped ($((pass + fail + skipped)) assertions)"
[ "$fail" -eq 0 ] || exit 1
echo "ALL SETUP FIXTURES PASSED"
exit 0
