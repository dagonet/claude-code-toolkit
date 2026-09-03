#!/usr/bin/env bash
# region.sh — THE PROJECT-CUSTOM REGION EXTRACTOR.  (v2.4.0, item A1)
#
# WHY THIS IS A SCRIPT AND NOT A PARAGRAPH.  Step 4's accept-template
# disqualifier and step 6's deletion precondition both turn on one question —
# "is this file's PROJECT-CUSTOM region empty?" — and BOTH consumers who
# implemented that question from prose got the REASSURING answer wrongly:
#
#   * `PROJECT-CUSTOM:BEGIN\s*-->` matches NOTHING.  The shipped marker carries
#     trailing prose:
#       <!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->
#   * `glob('**/*.md', recursive=True)` does NOT descend into dot-directories,
#     so it skips all of `.claude/` — every agent file.
#
# One consumer measured "zero regions" across a repo with ELEVEN.  A consumer
# who follows the prose literally concludes "empty", clears the disqualifier,
# and accept-template (or `git rm`) destroys the region.  The defect lives in
# the unspecified implementation — same class as `--include` after paths, the
# `which`-resolved `bash -n`, and the `command:`-anchored collector.  The
# population bitten is the consumers who follow us most literally.
#
# THE SPECIFICATION THIS FILE IMPLEMENTS, verbatim:
#
#   regex : PROJECT-CUSTOM:BEGIN.*?-->(.*?)<!--\s*PROJECT-CUSTOM:END   (DOTALL)
#   scope : enumeration MUST include dot-directories (.claude/ especially)
#   empty : body is whitespace or the shipped placeholder comment only
#
# AND THE COROLLARY REACHES BACKWARDS: every consumer who has ever reported
# "no PROJECT-CUSTOM content here" may have been reporting their EXTRACTOR,
# not their repo.  Re-check with this one.
#
# ONE ENUMERATION PATH, DELIBERATELY.  `--scan` is the only enumeration this
# skill documents.  Two documented ways to enumerate is how the naive `glob()`
# came back; if you need the file list for something else, take it from
# `--scan`'s output rather than writing a second walker.
#
# USAGE
#   bash region.sh <path>...      classify each named file
#   bash region.sh --scan <dir>   walk <dir> INCLUDING dot-directories and
#                                 classify every file that carries the markers
#   bash region.sh --body <path>  print the region body VERBATIM (byte-exact,
#                                 no trailing newline added) — this is what
#                                 step 6 prints before refusing a deletion, and
#                                 what the post-relocate byte-compare compares
#
# CLASSIFY OUTPUT, one line per file, tab-separated:
#   CONTENT   <path>    the region holds project work.  DESTRUCTION IS REFUSED.
#   EMPTY     <path>    whitespace or the shipped placeholder only
#   NOMARKERS <path>    no region in this file — INCLUDING a file that merely
#                       writes ABOUT the markers in prose (v3.0.0; see the
#                       matcher note below, it used to say EMPTY or UNCLOSED)
#   UNCLOSED  <path>    a BEGIN with no END — malformed, treat as CONTENT
#
# EXIT: 0 when every named path was readable, 1 on a read/usage error.  The
# CLASSIFICATION IS DATA, NOT A VERDICT — it is on stdout for the caller to
# read; do not encode "found content" in the exit code, because a caller that
# tests `$?` alone then cannot tell "no content" from "could not look".

set -u

# ⚠ MATCH THE MARKER'S SHAPE, NOT ITS NAME (v3.0.0).  ONE MATCHER, SHARED BY
# THE CLASSIFIER AND THE BODY EXTRACTOR — two matchers is how they drifted apart.
#
# v2.4.0 shipped these as BARE SUBSTRINGS while the documented specification at
# the top of this file anchors on the comment opener.  The implementation did
# not, so any file that merely WRITES ABOUT the markers matched, and it produced
# TWO false classifications with opposite consequences.  Both measured on live
# consumer repos during a v2.4.0 sync:
#
#   prose naming BEGIN only   -> UNCLOSED   (want NOMARKERS)
#   prose naming BOTH markers -> EMPTY      (want NOMARKERS)   <- THE DANGEROUS ONE
#
# The `EMPTY` one is the reason this is a v3.0.0 stop-ship rather than a
# tidy-up.  Step 6a reaches the ORDINARY deletion flow for `EMPTY` and
# `NOMARKERS`, so a documentation file that names both markers in one sentence
# sails through the precondition and lands in the delete prompt — and A2's whole
# premise is that the consent prompt never showed the thing being destroyed.
# Here the guard goes further and AFFIRMATIVELY CERTIFIES the file as empty.
# `--body` shares the asymmetry, returning empty on both false shapes, so step
# 6a's post-relocate byte-compare inherits it: `cmp` compares two empty bodies,
# they match, and the mechanical proof-of-relocation passes for a relocation
# that never happened.
#
# The `UNCLOSED` one DEADLOCKS instead: 6a offers only "relocate the region" or
# "defer" for CONTENT/UNCLOSED, and a false positive has NO region to relocate,
# so the prescribed remedy is unreachable — and A2 is deliberately built so no
# acknowledgement can override it.
#
# THIS IS A4's OWN REASONING APPLIED TO A1: key on the reference FORM, not on
# any occurrence of the name.  Same failure, same population — the consumers who
# document our mechanism most carefully are the ones who trip its detector.
#
# ⚠ The regexes are POSIX EREs used by BOTH `grep -E` AND awk's `match()`.  Do
# not reintroduce awk `index()` here: `index()` is a literal search and would
# silently ignore the `[[:space:]]*`, which is exactly how the two paths came to
# disagree with the spec in different ways.
BEGIN_RE='<!--[[:space:]]*PROJECT-CUSTOM:BEGIN'
END_RE='<!--[[:space:]]*PROJECT-CUSTOM:END'

# REGION_SH_VERSION -- bump on every behavioural change to this script.
#
# `SKILL.md` carries `SYNC-TEMPLATE-SKILL-VERSION` and a step that asserts it.
# This script had no version string at all, and it grew 6,924 -> 11,384 bytes
# between v2.4.0 and v3.0.0 — a consumer had to `sha256sum` it to work out which
# one they were running. It matters MORE here than for `SKILL.md`: the skill
# asserts its own marker, while `region.sh` is invoked by a step that simply
# assumes the copy on disk is current. Printing it in `--help` means the answer
# is one command away rather than a hash lookup.
REGION_SH_VERSION="3.0.1"

usage() {
  echo "region.sh $REGION_SH_VERSION" >&2
  echo "usage: region.sh <path>...            classify" >&2
  echo "       region.sh --scan <dir>         enumerate (dot-dirs included) + classify" >&2
  echo "       region.sh --body <path>        print the region body verbatim" >&2
  exit 1
}

# body <file> -- print the region body verbatim, or nothing.
#
# awk, not grep: the span is DOTALL (it crosses lines) and grep is line-based.
# The BEGIN marker's body starts after the FIRST `-->` at or after the marker
# on that line — which is precisely what the `\s*-->` implementations got
# wrong, since the shipped marker has prose between the two.
body() {
  awk -v bre="$BEGIN_RE" -v ere="$END_RE" '
    state == 0 {
      if (match($0, bre)) {
        rest = substr($0, RSTART + RLENGTH)
        j = index(rest, "-->")
        if (j > 0) {
          state = 1
          tail = substr(rest, j + 3)
          # A one-line region: BEGIN, body and END all on the same line.
          if (match(tail, ere)) {
            printf "%s", substr(tail, 1, RSTART - 1)
            exit
          }
          if (tail != "") printf "%s\n", tail
        }
      }
      next
    }
    state == 1 {
      if (match($0, ere)) {
        if (RSTART > 1) printf "%s", substr($0, 1, RSTART - 1)
        exit
      }
      printf "%s\n", $0
    }
  ' "$1"
}

# has_begin / has_end -- marker presence, for the NOMARKERS/UNCLOSED verdicts.
# `grep -E` with the SAME regexes awk uses; see the note at their definition.
has_begin() { grep -qE "$BEGIN_RE" "$1"; }
has_end()   { grep -qE "$END_RE" "$1"; }

# is_empty <body> -- "whitespace or the shipped placeholder comment only".
#
# The placeholder alone does NOT make a region non-empty (this is the rule the
# skill's step-4 note already states in prose).  Any OTHER comment does: a
# consumer who wrote their notes in a comment wrote content, and this guard
# must not decide otherwise on their behalf.
is_empty() {
  printf '%s' "$1" \
    | sed -E 's@^[[:space:]]*<!--[^>]*(Project-specific rules|extensions go here)[^>]*-->[[:space:]]*$@@' \
    | tr -d '[:space:]' \
    | grep -q . && return 1
  return 0
}

classify() { # <path>
  f="$1"
  if [ ! -f "$f" ]; then
    echo "ERROR: not a readable file: $f" >&2
    return 1
  fi
  if ! has_begin "$f"; then
    printf 'NOMARKERS\t%s\n' "$f"
    return 0
  fi
  if ! has_end "$f"; then
    # Fail toward preservation: a malformed region is content until a human
    # says otherwise.  The alternative — reporting EMPTY — is the destructive
    # reading, and this whole file exists because the destructive reading is
    # the one that looks reassuring.
    printf 'UNCLOSED\t%s\n' "$f"
    return 0
  fi
  b=$(body "$f")
  if is_empty "$b"; then
    printf 'EMPTY\t%s\n' "$f"
  else
    printf 'CONTENT\t%s\n' "$f"
  fi
  return 0
}

# scan <dir> -- THE enumeration.  `find` descends into dot-directories; the
# language-level glob that produced the "zero regions across eleven" reading
# does not.  `.git` is pruned (its objects are not project files); NOTHING ELSE
# IS — in particular `.claude/` must be walked, which is the entire point.
#
# ⚠ PRUNE VENDOR AND BUILD DIRECTORIES, OR THE ONLY SANCTIONED ENUMERATION IS
# UNUSABLE ON A REAL TREE (v3.0.0).  v2.4.0 pruned `.git` and nothing else.
# Measured on three consumer repos:
#
#   node repo   : 40,445 files (`src-tauri/target` 31,413, `node_modules` 4,781)
#                 -- killed after two minutes with no output
#   python repo : 10,524 files, of which `.venv` is 10,246 -- 97% -- and is
#                 gitignored by the rule the python variant itself ships.
#                 `--scan .` took ~15 minutes; scoped to `.claude`, 2.3 seconds.
#
# THE SILENCE IS AS BAD AS THE DURATION.  A 15-minute scan with no output reads
# as HUNG, and the consumer's next move is to kill it — which matters because
# SKILL.md documents `--scan` as THE enumeration and explicitly warns against
# hand-rolling a walker.  A consumer whose scan appears to hang has no
# sanctioned alternative, and the hand-rolled walker is the exact failure mode
# this file exists to prevent.  So it reports progress on stderr, leaving stdout
# clean for the caller.
#
# ⚠ NEVER BARE `git ls-files`.  Bare `ls-files` enumerates TRACKED files only
# and would go blind to the untracked, hand-authored project-owned agent this
# scan exists to find — the one nobody can regenerate (A3, set (c)).  The form
# used below is `ls-files --cached --others --exclude-standard`: tracked files
# PLUS untracked-but-not-ignored, in ONE process.  That is not the form this
# warning is about; it is strictly a superset of the tracked list, and a
# consumer measured it covering exactly the case the warning protects (two
# untracked project-owned agents included; a gitignored decompile tree of
# 16,000+ files excluded).
#
# ⚠ WHY THE NAME LIST WAS NOT ENOUGH (v3.0.3, item 17).  v3.0.1 fixed a
# 40,445-file timeout by pruning on a DIRECTORY-NAME list.  The next consumer's
# build output was a decompile tree whose directory is not on that list, and the
# scan took 120 s and was killed.  An enumeration keyed on a name list does not
# close: the list is a guess about names, and the property that actually matters
# is gitignore STATUS.  Inside a git repo, ask git.  The residual — a
# project-owned file that is ALSO gitignored — is set (a)'s job, not this scan's.
#
# The name-list `find` walk survives for the NON-git case only (no repo, so no
# ignore status to ask about).  It is conservative on purpose: only unambiguous
# vendor/build output, and no template-synced file has ever lived in any of
# them.  `bin`/`obj` are deliberately ABSENT — Rust's `src/bin/` is real source.

# scan_stream <label> <prefix> -- consumes NUL-delimited paths on stdin.
# NUL-delimited because a path may contain a newline; both producers emit -z/-print0.
scan_stream() {
  _lbl="$1"; _pfx="$2"; n=0
  while IFS= read -r -d '' f; do
    f="$_pfx$f"
    n=$((n + 1))
    [ $((n % 2000)) -eq 0 ] && printf 'region.sh: scanned %s files...\n' "$n" >&2
    has_begin "$f" 2>/dev/null || continue
    classify "$f"
  done
  printf 'region.sh: scanned %s files under %s\n' "$n" "$_lbl" >&2
  # A dead enumerator and an empty tree print the same "scanned 0 files", and a
  # 0 reads as CLEAN. Say so instead of letting silence be the verdict.
  [ "$n" -eq 0 ] && printf 'region.sh: WARNING: enumerated 0 files under %s — verify this is an empty tree and not an enumeration failure\n' "$_lbl" >&2
  return 0
}

scan() {
  d="$1"
  [ -d "$d" ] || { echo "ERROR: not a directory: $d" >&2; return 1; }
  if ( cd "$d" && git rev-parse --show-toplevel ) >/dev/null 2>&1; then
    # Paths come back relative to <dir>; prefix them so classify gets a usable path.
    ( cd "$d" && git ls-files --cached --others --exclude-standard -z -- . ) \
      | sort -z | scan_stream "$d" "$d/"
  else
    find "$d" \( -name .git -o -name node_modules -o -name .venv -o -name venv \
                 -o -name __pycache__ -o -name .mypy_cache -o -name .pytest_cache \
                 -o -name .tox -o -name .next -o -name .nuxt -o -name target \
                 -o -name dist -o -name build -o -name vendor -o -name .gradle \
                 -o -name .terraform \) -prune -o -type f -print0 2>/dev/null \
      | sort -z | scan_stream "$d" ""
  fi
}

[ $# -ge 1 ] || usage

case "$1" in
  --scan) [ $# -eq 2 ] || usage; scan "$2" ;;
  --body) [ $# -eq 2 ] || usage
          [ -f "$2" ] || { echo "ERROR: not a readable file: $2" >&2; exit 1; }
          body "$2" ;;
  -h|--help) usage ;;
  -*) usage ;;
  *)  rc=0
      for f in "$@"; do classify "$f" || rc=1; done
      exit "$rc" ;;
esac
