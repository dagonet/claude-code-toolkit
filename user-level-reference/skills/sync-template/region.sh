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
#   NOMARKERS <path>    no region in this file
#   UNCLOSED  <path>    a BEGIN with no END — malformed, treat as CONTENT
#
# EXIT: 0 when every named path was readable, 1 on a read/usage error.  The
# CLASSIFICATION IS DATA, NOT A VERDICT — it is on stdout for the caller to
# read; do not encode "found content" in the exit code, because a caller that
# tests `$?` alone then cannot tell "no content" from "could not look".

set -u

BEGIN_MARK='PROJECT-CUSTOM:BEGIN'
END_MARK='PROJECT-CUSTOM:END'

usage() {
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
  awk -v bm="$BEGIN_MARK" -v em="$END_MARK" '
    state == 0 {
      i = index($0, bm)
      if (i > 0) {
        rest = substr($0, i + length(bm))
        j = index(rest, "-->")
        if (j > 0) {
          state = 1
          tail = substr(rest, j + 3)
          # A one-line region: BEGIN, body and END all on the same line.
          k = index(tail, "<!--")
          if (k > 0 && index(substr(tail, k), em) > 0) {
            printf "%s", substr(tail, 1, k - 1)
            exit
          }
          if (tail != "") printf "%s\n", tail
        }
      }
      next
    }
    state == 1 {
      k = index($0, "<!--")
      if (k > 0 && index(substr($0, k), em) > 0) {
        if (k > 1) printf "%s", substr($0, 1, k - 1)
        exit
      }
      printf "%s\n", $0
    }
  ' "$1"
}

# has_begin / has_end -- marker presence, for the NOMARKERS/UNCLOSED verdicts.
has_begin() { grep -q "$BEGIN_MARK" "$1"; }
has_end()   { grep -q "$END_MARK" "$1"; }

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
scan() {
  d="$1"
  [ -d "$d" ] || { echo "ERROR: not a directory: $d" >&2; return 1; }
  find "$d" -name .git -prune -o -type f -print 2>/dev/null | sort | while IFS= read -r f; do
    has_begin "$f" 2>/dev/null || continue
    classify "$f"
  done
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
