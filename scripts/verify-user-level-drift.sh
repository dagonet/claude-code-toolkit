#!/usr/bin/env bash
# verify-user-level-drift.sh [--worktree | <git-ref>]
#
# Diff user-level-reference/{CLAUDE.md,hooks/**,skills/**,agents/**} against
# the live ~/.claude/ tree.
#
# Direction of truth: **the reference leads, the live copy follows.** The repo
# files are edited first; ~/.claude/ is updated by the reader per the
# CHANGELOG's "Downstream migration" section. So a DRIFT result in the same
# session that changed the reference is expected, not a regression — it means
# the migration step has not been run on this machine yet.
#
# THE REFERENCE IS A RELEASED TAG, NOT THE WORKING TREE (v2.2.5 round 4).
# Measured: a live ~/.claude/ copy byte-identical to an UNMERGED branch made this
# script report 0 drift — so the delivery probe certified that an unreviewed,
# ship-blocked revision had reached a user's machine. Green meant the opposite of
# what the check exists to establish. Comparing against the last released tag
# makes "0 drift" mean "the live tree matches something that shipped", which is
# the only claim worth making. In-flight reference edits on a branch then read as
# UNRELEASED and are listed, not silently blessed.
#
# `--worktree` restores the old behaviour for pre-release inspection. It prints a
# banner and is never a release check.
#
# WHY BLOB-VERSUS-TAG IS A LEGITIMATE BASELINE AT ALL (v2.2.5 round 5).
# For a PROCESSED tree it would not be: the released reference of a
# placeholder-bearing file is the manifest's PROCESSED hash, not the tag's raw
# blob, and a consumer hit exactly that — their pre-commit-test.sh read as drift
# against the tag's blob (templateRawHash 07de572b…) while matching the processed
# template exactly (templateHash cd29e1b1…). Wrong baseline, not drift. A check
# that noisy is disabled within a week, which is how a real check dies.
#
# This script is safe from that NOT because the tree is placeholder-free — it is
# not; three in-scope files carry placeholders (hooks/lib/git-cmd.sh 2,
# hooks/pre-commit-test.sh 1, skills/sync-template/SKILL.md 3) — but because
# **the user-level install is VERBATIM**: there is no substitution step at user
# level, unlike the project bootstrap. The files match precisely BECAUSE nobody
# processes them. That is the narrow property, and the VERBATIM INSTALL section
# below STATES it — derived from the drift result for released files (v2.2.6),
# and genuinely measured for unreleased ones, which no other line here can see.
#
# EXTENDING THIS SCRIPT TO ANY PROCESSED TREE (the project bootstrap path)
# REQUIRES THE MANIFEST'S PROCESSED HASH INSTEAD — a blob comparison there
# reports every placeholder-bearing file as drift, forever.
#
# Verbatim-install is only half of what matters, and it is NOT the half that
# catches breakage: a placeholder added in a shell VALUE position keeps verbatim
# install true, keeps this comparison green, and makes the shipped hook execute a
# literal `{{...}}`. That second property — no placeholder in an EXECUTABLE
# position — is asserted in scripts/verify-template-consistency.sh (search:
# executable-position sweep), because it needs no live tree and belongs in the
# gate. Do not read a green run here as evidence about it.
#
# SCOPE, AND WHAT IS DELIBERATELY NOT COMPARED.
# The loop below covers CLAUDE.md + hooks/ + skills/ + agents/.
# `user-level-reference/settings.json` is EXCLUDED ON PURPOSE: it is reference
# material a reader merges by hand, not a file this project installs. A user's
# own ~/.claude/settings.json legitimately carries their personal permissions,
# env and MCP entries, so force-matching it would report every user as drifting
# from a file they were never meant to copy verbatim. Same class as
# `.mcp.json.template`, `README.md` and `settings-reference.md` — reference
# files, never installed. DO NOT ADD ANY OF THEM TO THE `for sub in` LOOP.
#
# ONE NARROW EXCEPTION, ADDED v3.0.3 AND NOT A WEAKENING OF THE ABOVE:
# `permissions.autoMode.environment` inside settings.json IS compared, as a
# KEY-SCOPED comparison, not a byte one, and settings.json stays out of the loop.
# The reasoning that excludes the file is about the user's OWN entries; that key
# is not one of them — it is the trust boundary this repo's reference defines,
# at USER scope, and drift in it was invisible for two releases. See the
# autoMode.environment section below for the measurement.
#
# Run ad-hoc; not wired into any hook. Works from any cwd (cd's to repo root).
set -u

cd "$(dirname "$0")/.." || { echo "ERROR: cannot resolve repo root"; exit 2; }

MODE="tag"
REF=""
case "${1:-}" in
  --worktree) MODE="worktree" ;;
  "") ;;
  *) REF="$1" ;;
esac

LIVE_ROOT="$HOME/.claude"
if [ ! -d "$LIVE_ROOT" ]; then
  echo "ERROR: $LIVE_ROOT not found — no live user-level tree to compare"
  exit 2
fi

if [ "$MODE" = "tag" ]; then
  if [ -z "$REF" ]; then
    REF=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)
  fi
  # Cannot-determine REFUSES. A silent fallback to the working tree is exactly
  # the failure this mode was added to close.
  if [ -z "$REF" ] || ! git rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
    echo "ERROR: cannot resolve a released reference (no v* tag reachable from HEAD)."
    echo "  Pass an explicit <git-ref>, or --worktree to compare against the working tree (NOT a release check)."
    exit 2
  fi
  echo "REFERENCE: $REF ($(git rev-parse --short "$REF^{commit}")) — released tree"
else
  echo "REFERENCE: WORKING TREE — this is NOT a release check. A live copy matching"
  echo "  an unshipped branch will report 0 drift, which certifies nothing."
fi

checked=0
in_sync=0
drift=0
unreleased=0
drift_list=""
unreleased_list=""

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Materialise the reference copy of <repo-path>; prints the path, or nothing
# when the file does not exist at that reference.
ref_copy() { # <repo-relative path>
  if [ "$MODE" = "worktree" ]; then
    [ -f "$1" ] && printf '%s' "$1"
    return
  fi
  out="$TMPD/$(printf '%s' "$1" | tr '/' '_')"
  if git show "$REF:$1" > "$out" 2>/dev/null; then
    printf '%s' "$out"
  fi
}

check_file() { # <repo-relative ref path> <live_path>
  src=$(ref_copy "$1")
  if [ -z "$src" ]; then
    # Present on this branch, absent from the released reference.
    unreleased=$((unreleased + 1))
    unreleased_list="$unreleased_list
  UNRELEASED (not in $REF, not compared): $1"
    return
  fi
  checked=$((checked + 1))
  if [ ! -f "$2" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  MISSING live: $2"
    return
  fi
  if diff -q "$src" "$2" >/dev/null 2>&1; then
    in_sync=$((in_sync + 1))
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $2 differs from $1@${REF:-worktree}"
  fi
}

check_file "user-level-reference/CLAUDE.md" "$LIVE_ROOT/CLAUDE.md"

# The file SET comes from the reference too, not from the working tree: a file
# added on a branch must not enlarge a released-tree comparison.
for sub in hooks skills agents; do
  if [ "$MODE" = "worktree" ]; then
    [ -d "user-level-reference/$sub" ] || continue
    files=$(find "user-level-reference/$sub" -type f)
  else
    files=$(git ls-tree -r --name-only "$REF" -- "user-level-reference/$sub" 2>/dev/null)
  fi
  [ -n "$files" ] || continue
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    rel="${f#user-level-reference/}"
    check_file "$f" "$LIVE_ROOT/$rel"
  done <<EOF
$files
EOF
done

# Files on this branch that the released reference does not carry. Reported so
# an in-flight addition is visible rather than invisible; never a failure.
if [ "$MODE" = "tag" ]; then
  for sub in hooks skills agents; do
    [ -d "user-level-reference/$sub" ] || continue
    while IFS= read -r f; do
      git cat-file -e "$REF:$f" 2>/dev/null && continue
      unreleased=$((unreleased + 1))
      unreleased_list="$unreleased_list
  UNRELEASED (not in $REF, not compared): $f"
    done < <(find "user-level-reference/$sub" -type f)
  done
fi

# ---------------------------------------------------------------------------
# autoMode.environment — THE ONE THING COMPARED INSIDE settings.json (v3.0.3,
# item 24).
#
# This is NOT the byte comparison the scope note above forbids, and settings.json
# is still NOT in the `for sub in` loop. A user's own permissions, env and MCP
# entries are theirs; `permissions.autoMode.environment` is not — it is the trust
# boundary the toolkit's own reference defines, it is USER scope (it applies to
# every repo on the machine), and drift in it is silent and expensive.
#
# Measured: a live file with 25 environment entries against the reference's 4, in
# a repo that reported "0 drift" for two releases — because nothing here looked
# at settings.json at all. The damage was a per-repo `**Trusted repo**: <path>`
# line, which made every OTHER repository read as outside the trust boundary: 58
# classifier denials across 11 sessions, 50 of them in one repo.
#
# TWO ARMS, deliberately, because either can be true without the other: the
# arrays must MATCH, and no live entry may carry the singular, path-naming
# `**Trusted repo**:` form. An array that differs for some benign reason would
# otherwise hide the specific defect, and the specific defect could arrive inside
# an otherwise-matching array.
#
# DRIFT_LIVE_SETTINGS overrides the live path. It exists so the control can be
# run against a DOCTORED COPY — never doctor the live file to test this.
# ---------------------------------------------------------------------------
LIVE_SETTINGS="${DRIFT_LIVE_SETTINGS:-$LIVE_ROOT/settings.json}"

automode_entries() { # <settings.json> -> permissions.autoMode.environment, one entry per line
  [ -f "$1" ] || return 0
  awk '/"environment"[[:space:]]*:[[:space:]]*\[/ { inarr = 1; next }
       inarr && /^[[:space:]]*\]/ { exit }
       inarr { sub(/^[[:space:]]+/, ""); sub(/,[[:space:]]*$/, ""); print }' "$1"
}

am_ref_src=$(ref_copy "user-level-reference/settings.json")
if [ -z "$am_ref_src" ]; then
  # Cannot determine refuses: no reference, no comparison, and silence would read
  # as agreement.
  drift=$((drift + 1))
  drift_list="$drift_list
  CANNOT COMPARE autoMode.environment: user-level-reference/settings.json is not in ${REF:-the working tree}"
elif [ ! -f "$LIVE_SETTINGS" ]; then
  drift=$((drift + 1))
  drift_list="$drift_list
  MISSING live: $LIVE_SETTINGS (autoMode.environment not comparable)"
else
  am_ref=$(automode_entries "$am_ref_src")
  am_live=$(automode_entries "$LIVE_SETTINGS")
  if [ -z "$am_ref" ]; then
    # In-band control for the extractor itself: the reference always carries
    # entries, so an empty read is a broken parser, not an empty array.
    drift=$((drift + 1))
    drift_list="$drift_list
  autoMode.environment EXTRACTOR IS INERT: read 0 entries from the reference copy of user-level-reference/settings.json"
  elif [ "$am_ref" = "$am_live" ]; then
    : # arm 1 clean
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: permissions.autoMode.environment in $LIVE_SETTINGS differs from user-level-reference/settings.json@${REF:-worktree}
    reference has $(printf '%s\n' "$am_ref" | grep -c .) entry(ies), live has $(printf '%s\n' "$am_live" | grep -c .)"
  fi
  if printf '%s\n' "$am_live" | grep -q '\*\*Trusted repo\*\*:'; then
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $LIVE_SETTINGS names a SINGLE repo as THE trusted repo (**Trusted repo**: ...). autoMode.environment is USER scope: that line puts every other repository on this machine outside the trust boundary. Use the reference's generic **Trusted repos** entry."
  fi
fi

# ---------------------------------------------------------------------------
# VERBATIM INSTALL — the property that makes the comparison above VALID.
#
# Observable form of "nobody processes these files": the placeholder COUNT in
# each reference file equals the count in its live copy. A substitution step
# appearing at user level drops the live count and this reports PROCESSED,
# naming the manifest's processed hash as the required baseline.
#
# SCOPE NARROWED IN v2.2.6 — IT NOW SCANS ONLY THE UNRELEASED FILES, AND THE
# RELEASED LINE IS DERIVED FROM THE DRIFT RESULT. The argument is the reporter's
# own delete-the-guard on their own proposal: over the RELEASED set the arm never
# contributes information alone, because there are only two states and it is
# redundant in one and unevaluable in the other.
#
#   drift == 0  -> the live copy is BYTE-IDENTICAL to the reference, which is
#                  STRICTLY STRONGER than same-placeholder-count. The arm can
#                  only restate what the drift line already said.
#   drift != 0  -> staleness and substitution are both live hypotheses and a
#                  placeholder count CANNOT distinguish them. Observed live
#                  during the v2.2.5 release, pre-propagation: "VERBATIM INSTALL
#                  VIOLATED ... live has 4, reference@v2.2.5 has 12" — caused by
#                  STALENESS, not substitution, printed beside a correct "4
#                  drift". A wrong causal claim stacked on top of correct
#                  information, aimed at someone mid-migration. It would print
#                  that on EVERY release before propagation: the
#                  disabled-within-a-week shape, in a check we had just added.
#
# Softening the wording was rejected — that preserves the false alarm and makes
# it vaguer. Coupling it to the adjacent drift line was rejected too: adjacent
# output is not a condition the check evaluated, and relying on a human to read
# two lines together defends against an attentive reader and nothing else.
#
# WHAT SURVIVES, AND WHY IT IS NOT DELETED: the UNRELEASED file. check_file skips
# those entirely, so a processed live copy of a reference file not yet in the tag
# is invisible to every other line in this script. That arm still measures, still
# folds into the exit code, and is still scanned from the WORKING TREE — because
# no released baseline exists for it, which is exactly the case that makes it
# informative. The released line is now documentation with a computed value in
# it: it STATES THE PREMISE the drift result establishes, so nobody re-derives
# why blob-versus-tag is legitimate. Worth having; it is not a check.
#
# SOMETHING ELSE DEPENDS ON THIS PROPERTY — DO NOT DROP THE LINE AS OVERLAPPING
# (round 7, still true after the v2.2.6 narrowing). verify-template-consistency
# .sh's 21c-3c censuses shipped *.json for executable-position placeholders
# REPO-SIDE ONLY, and never touches the live ~/.claude tree. That census is
# SUFFICIENT for user level solely because of the property named here: reference
# clean + verbatim install => live copy clean. The two look like independent
# checks and are one argument with two halves. What changed in v2.2.6 is only
# WHERE the premise comes from — `drift == 0` now establishes it for released
# files, more strongly than a placeholder count ever did. So the line must keep
# STATING it; it just stops pretending to test it.
#
# ITS CONTROL RUNS IN BAND, on a planted pair, because a counter that always
# returns 0 would also report "verbatim" forever. Nothing is written under
# $HOME.
ph_count() { # <file> -> number of {{PLACEHOLDER}} occurrences
  [ -f "$1" ] || { printf '0'; return; }
  grep -o '{{[A-Z_]\{2,\}}}' "$1" 2>/dev/null | grep -c . | tr -d ' '
}

VFIX=$(mktemp -d)
VPH=$(printf '{{%s}}' TEST_COMMAND)
printf 'TEST_CMD="%s"\n' "$VPH" > "$VFIX/ref.sh"
cp "$VFIX/ref.sh" "$VFIX/verbatim.sh"
printf 'TEST_CMD="npm test"\n'  > "$VFIX/processed.sh"
vc_ref=$(ph_count "$VFIX/ref.sh")
vc_verb=$(ph_count "$VFIX/verbatim.sh")
vc_proc=$(ph_count "$VFIX/processed.sh")
rm -rf "$VFIX"

verbatim_ok=1
if [ "$vc_ref" -ne 1 ] || [ "$vc_verb" -ne "$vc_ref" ] || [ "$vc_proc" -eq "$vc_ref" ]; then
  verbatim_ok=0
  echo "VERBATIM-INSTALL CHECK IS INERT — its own control failed (ref=$vc_ref want 1, verbatim copy=$vc_verb want 1, processed copy=$vc_proc want 0)."
  echo "  Treat the verbatim result below as UNKNOWN, not as a pass."
fi

processed=0
processed_list=""
scanned=0
scanned_rel=0
for f in user-level-reference/CLAUDE.md $(find user-level-reference/hooks user-level-reference/skills user-level-reference/agents -type f 2>/dev/null); do
  [ -f "$f" ] || continue
  rel="${f#user-level-reference/}"
  live="$LIVE_ROOT/$rel"
  [ -f "$live" ] || continue
  # THE BASELINE MUST BE THE SAME REFERENCE check_file USES. Counting against the
  # WORKING TREE was tried first and immediately reproduced the exact false
  # positive this round exists to prevent: on this branch sync-template/SKILL.md
  # had 11 placeholders in prose against the live copy's 4, so a live tree that
  # was byte-identical to the released tag was reported as PROCESSED. Wrong
  # baseline, not processing — the consumer's own lesson, arriving from inside.
  # The working tree is used only when the file is absent from the reference,
  # which is the UNRELEASED case this check exists to reach.
  srcf=$(ref_copy "$f")
  if [ -n "$srcf" ]; then
    # RELEASED file: check_file already compared it BYTE-WISE against the same
    # reference. Counting placeholders here adds nothing and can only be wrong
    # (v2.2.6) — see the header note. Count it for the derived line and move on.
    n_ref=$(ph_count "$srcf")
    [ "$n_ref" -gt 0 ] && scanned_rel=$((scanned_rel + 1))
    continue
  fi
  # UNRELEASED file: check_file SKIPPED it, so nothing else in this script can
  # see a processed live copy of it. This is the arm that carries information.
  n_ref=$(ph_count "$f")
  [ "$n_ref" -gt 0 ] || continue
  scanned=$((scanned + 1))
  n_live=$(ph_count "$live")
  if [ "$n_ref" -ne "$n_live" ]; then
    processed=$((processed + 1))
    processed_list="$processed_list
  PROCESSED: $live has $n_live placeholder(s), $f@worktree has $n_ref"
  fi
done

if [ "$verbatim_ok" -eq 1 ]; then
  if [ "$drift" -eq 0 ]; then
    echo "VERBATIM INSTALL: implied by $in_sync/$checked in sync — byte-identical is strictly stronger than same-placeholder-count ($scanned_rel released placeholder-bearing file(s))."
  else
    echo "VERBATIM INSTALL: not evaluated — $drift file(s) drifted. Staleness and substitution are both live hypotheses and a placeholder count cannot distinguish them; re-check after propagation."
  fi
  if [ "$scanned" -gt 0 ]; then
    if [ "$processed" -eq 0 ]; then
      echo "  UNRELEASED arm: $scanned placeholder-bearing file(s) compared directly (no released baseline exists for them) — clean."
    else
      echo "  UNRELEASED arm: something SUBSTITUTES placeholders at user level."
      echo "  Blob-versus-tag will not be a legitimate baseline for these files once released:"
      echo "  compare the manifest's PROCESSED hash instead, or they report drift forever."
      printf '%s\n' "$processed_list"
    fi
  fi
fi

if [ "$drift" -gt 0 ]; then
  echo "DRIFT DETECTED. The reference leads. Apply CHANGELOG.md -> latest 'Downstream migration' to resync."
  printf '%s\n' "$drift_list"
fi
if [ "$unreleased" -gt 0 ]; then
  echo "UNRELEASED reference files (expected on a feature branch; they ship with the release):"
  printf '%s\n' "$unreleased_list"
fi

echo "$checked files checked against ${REF:-working tree}, $in_sync in sync, $drift drift, $unreleased unreleased"

# A violated verbatim install fails the run on its own: for an UNRELEASED file no
# DRIFT line exists to carry it, so folding it into $drift is what makes the
# assertion load-bearing rather than advisory. An INERT control fails too —
# cannot-determine refuses.
[ "$drift" -eq 0 ] && [ "$processed" -eq 0 ] && [ "$verbatim_ok" -eq 1 ] && exit 0
exit 1
