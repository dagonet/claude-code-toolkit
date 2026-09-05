#!/usr/bin/env bash
# scripts/check-b3-placement.sh
#
# Heading-anchored placement check (v3.0.4, item B3 / SKILL.md step 4):
# a merge can be clean (has_conflicts:false, dropped_lines:[]) and still
# splice the template's new content into the wrong section of the file.
# Line-distance / exact-line anchoring fails here because the anchor line
# itself differs between template ({{GATE_COMMAND}}) and project (a real
# value) — so this check anchors on the enclosing HEADING instead, which
# is byte-identical across base, template and project.
#
# Algorithm:
#   1. Find the line(s) the template ADDS over base (diff base -> template).
#   2. For each added line, find the heading it sits under IN THE TEMPLATE.
#   3. Find that same added line in the target file (merged / spliced), and
#      the heading it sits under THERE.
#   4. RED if the headings differ, GREEN if they match.
#
# Usage: check-b3-placement.sh <base.md> <template.md> <target.md>
# Exit 0 = GREEN (placement correct), 1 = RED (placement violation).

set -euo pipefail

base="$1"
template="$2"
target="$3"

heading_before_line() {
  # $1 = file, $2 = 1-based line number in that file
  local file="$1" lineno="$2"
  awk -v ln="$lineno" '
    /^#+ / { heading = $0 }
    NR == ln { print heading; exit }
  ' "$file"
}

find_line_containing() {
  # $1 = file, $2 = needle (fixed string) -> first matching line number, or empty
  local file="$1" needle="$2"
  grep -nF -- "$needle" "$file" | head -n1 | cut -d: -f1
}

# Lines added by the template over base (diff '>' lines, content only).
mapfile -t added_lines < <(diff "$base" "$template" | grep '^> ' | sed 's/^> //')

if [ "${#added_lines[@]}" -eq 0 ]; then
  echo "check-b3-placement: no added lines found between $base and $template" >&2
  exit 2
fi

overall_red=0
for added in "${added_lines[@]}"; do
  tmpl_lineno="$(find_line_containing "$template" "$added")"
  if [ -z "$tmpl_lineno" ]; then
    echo "check-b3-placement: added line not found verbatim in $template — cannot anchor" >&2
    overall_red=1
    continue
  fi
  tmpl_heading="$(heading_before_line "$template" "$tmpl_lineno")"

  target_lineno="$(find_line_containing "$target" "$added")"
  if [ -z "$target_lineno" ]; then
    echo "check-b3-placement: RED — added block missing entirely from $target" >&2
    overall_red=1
    continue
  fi
  target_heading="$(heading_before_line "$target" "$target_lineno")"

  if [ "$tmpl_heading" = "$target_heading" ]; then
    echo "check-b3-placement: GREEN — '$added' sits under '$target_heading' in $target (matches template's '$tmpl_heading')"
  else
    echo "check-b3-placement: RED — '$added' sits under '$target_heading' in $target, template placed it under '$tmpl_heading'"
    overall_red=1
  fi
done

exit "$overall_red"
