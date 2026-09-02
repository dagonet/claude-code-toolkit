#!/usr/bin/env bash
# probe-a6.sh — what does hooks/gate-before-merge.sh actually do to the
# merge-shaped commands you might type on a protected branch?
#
# Run it from inside the checkout you want to ask about:
#
#   bash scripts/probe-a6.sh
#
# It feeds this repo's own gate a table of realistic payloads and prints the
# verdict for each. Nothing is executed: the payloads never reach git.
#
# Exit codes — and note that NONE of them is a hook verdict:
#   0  the table was printed and every row matched its expectation
#   1  the table was printed and at least one row differed
#   9  REFUSED. A precondition failed, so the answer would have been vacuous.
#
# WHY THE REFUSAL PATH IS THE IMPORTANT HALF OF THIS SCRIPT.
# There are four states in which every row comes back the same value for a
# reason that has nothing to do with the gate's logic:
#
#   every row ALLOWED   the checkout is not on a protected branch
#   every row ALLOWED   the protected set is empty, or lacks this branch
#   every row ALLOWED   PROJECT_CONTEXT.md configures no **Gate** command (or
#                       leaves it a {{...}} placeholder) — the hook exits 0
#                       before it reaches any A6 decision
#   every row BLOCKED   hooks/lib/git-cmd.sh is missing or unreadable — the gate
#                       fails closed at its first line, on everything
#
# The last one hides in the BLOCK direction, which is why it is the dangerous
# one: a probe expecting BLOCKED reads all-2 as the gate working perfectly. So a
# refusal exits 9 (neither verdict — a wrapper testing `-eq 0` or `-eq 2` must
# not read a refusal as an answer), prints the OBSERVED value rather than the
# name of the rule that failed, and NEVER prints the per-row table. The table is
# the reassuring artefact; if it is not printed, it cannot be quoted as evidence.
#
# Deliberately NOT preconditions: artifact freshness and a clean working tree.
# A6 refuses before the artifact is read, and requiring either would make the
# probe unrunnable in the state most people are in — an unrunnable check is a
# skipped check.

set -u

refuse() { # <reason...>
  printf 'REFUSED (exit 9): %s\n' "$1" >&2
  shift
  for r in "$@"; do printf '  %s\n' "$r" >&2; done
  printf 'No table is printed: any table produced in this state would be vacuous.\n' >&2
  exit 9
}

TOP=$(git rev-parse --show-toplevel 2>/dev/null)
[ -n "$TOP" ] || refuse "the current directory is not a git checkout." \
  "observed cwd: $(pwd)"

HOOK="$TOP/hooks/gate-before-merge.sh"
LIB="$TOP/hooks/lib/git-cmd.sh"
JSONLIB="$TOP/hooks/lib/json.sh"

# --- precondition 1: the enforcement layer is present -----------------------
[ -f "$HOOK" ] && [ -s "$HOOK" ] || refuse \
  "the gate itself is absent; there is nothing to probe." "observed: $HOOK"
for f in "$LIB" "$JSONLIB"; do
  [ -f "$f" ] && [ -s "$f" ] || refuse \
    "enforcement layer absent; every row would BLOCK vacuously." \
    "observed: $f is missing or empty" \
    "The gate fails closed on a missing lib, so all-BLOCKED would look like a healthy gate."
done

# --- precondition 2: every hook script parses -------------------------------
for f in "$TOP"/hooks/*.sh "$TOP"/hooks/lib/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || refuse \
    "a hook script does not parse, so its verdicts are not its logic." \
    "observed: $f fails 'bash -n'"
done

# --- precondition 3: the current branch resolves ----------------------------
BRANCH=$(git -C "$TOP" branch --show-current 2>/dev/null)
[ -n "$BRANCH" ] || refuse \
  "no current branch; the hook reads 'git branch --show-current', which is empty on a detached HEAD." \
  "observed HEAD: $(git -C "$TOP" rev-parse --short HEAD 2>/dev/null || echo unresolvable)"

# The protected set is read through the gate's OWN resolution, not re-derived:
# a probe that re-implements the rule can agree with itself while disagreeing
# with the hook. GC_JSON is what json_warn_once reads a session id from.
GC_JSON=""
GC_CWD="$TOP"
# shellcheck disable=SC1090
. "$JSONLIB"
# shellcheck disable=SC1090
. "$LIB"
PROTECTED=$(gc_protected_branches "$TOP" 2>/dev/null)

# --- precondition 4: this branch is in the protected set --------------------
IN=0
for p in $PROTECTED; do [ "$BRANCH" = "$p" ] && IN=1; done
[ "$IN" = 1 ] || refuse \
  "this checkout is not on a protected branch, so every row would be ALLOWED for a reason that is not the gate's logic." \
  "observed: branch=$BRANCH  protected=(${PROTECTED:-<empty>})"

# --- precondition 5: the payload cwd parses as JSON -------------------------
jesc() {
  je=$(printf '%s.' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '%s' "${je%.}"
}
mkpayload() { # <command>
  printf '{"session_id":"probe-a6","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"%s"}' \
    "$(jesc "$1")" "$(jesc "$TOP")"
}
PROBE_PAYLOAD=$(mkpayload 'git status --short')
json_valid "$PROBE_PAYLOAD" || refuse \
  "the payload built for this cwd does not parse as JSON, so every row would be refused by the parser rather than decided by the gate." \
  "observed cwd: $TOP" \
  "A backslash in the path is the usual cause; use forward slashes."
[ "$(json_get "$PROBE_PAYLOAD" cwd)" = "$TOP" ] || refuse \
  "the payload parses but the cwd does not survive the round trip." \
  "observed: $(json_get "$PROBE_PAYLOAD" cwd)"

# --- precondition 6: a **Gate** command is configured -----------------------
# NOT in the specified list, and added because it is a fourth vacuous state in
# the ALLOW direction: the hook exits 0 on an absent or placeholder **Gate**
# field, well before any A6 decision, so an unconfigured repo reports a clean
# all-ALLOWED table for a reason that is not the gate's logic.
GATE_CMD=$(grep -E "${GC_KEY_PRE}\*\*Gate( Command)?\*\*:" "$TOP/PROJECT_CONTEXT.md" 2>/dev/null \
  | sed 's/.*\*\*Gate\( Command\)\?\*\*:[[:space:]]*//;s/[[:space:]]*$//;s/^`//;s/`$//' | head -1)
[ -n "$GATE_CMD" ] || refuse \
  "no **Gate** command is configured, so the gate exits 0 before any A6 decision and every row would be ALLOWED vacuously." \
  "observed: no '**Gate**:' line in $TOP/PROJECT_CONTEXT.md"
case "$GATE_CMD" in
  *\{\{*\}\}*) refuse \
    "the **Gate** command is still an unfilled placeholder, so the gate exits 0 before any A6 decision." \
    "observed: $GATE_CMD" ;;
esac

# --- the table --------------------------------------------------------------
UPSTREAM=$(git -C "$TOP" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)

printf 'A6 probe — hooks/gate-before-merge.sh\n'
printf '  branch=%s  protected=(%s)  upstream=%s\n' \
  "$BRANCH" "$PROTECTED" "${UPSTREAM:-<none configured>}"
printf '  gate=%s\n\n' "$GATE_CMD"
printf '%-8s  %-8s  %s\n' EXPECTED OBSERVED COMMAND

differs=0
row() { # <expected: ALLOWED|BLOCKED|-> <command>
  printf '%s' "$(mkpayload "$2")" | bash "$HOOK" >/dev/null 2>&1
  rrc=$?
  case "$rrc" in
    0) robs=ALLOWED ;;
    2) robs=BLOCKED ;;
    *) robs="exit $rrc" ;;
  esac
  rmark=""
  if [ "$1" != "-" ] && [ "$1" != "$robs" ]; then rmark="   <-- DIFFERS"; differs=1; fi
  printf '%-8s  %-8s  %s%s\n' "$1" "$robs" "$2" "$rmark"
}

# The three merge-state subcommands: a conflicted merge on this branch must
# have an exit that is not the kill switch.
row ALLOWED 'git merge --abort'
row ALLOWED 'git merge --continue'
row ALLOWED 'git merge --quit'
# Provenance: a ref that certainly is not this branch's upstream.
row BLOCKED 'git merge refs/heads/zz-a6-probe-absent'
# The pull path, gated by form.
row ALLOWED 'git pull --ff-only'
row BLOCKED 'git pull'
row BLOCKED 'git pull --ff-only origin main'
row BLOCKED 'gh pr merge 1 --squash'
# State-dependent, so it carries no expectation: this is a catch-up only while
# the upstream is ahead of (or equal to) HEAD.
if [ -n "$UPSTREAM" ]; then
  row - "git merge --ff-only $UPSTREAM"
fi

printf '\n'
if [ "$differs" = 0 ]; then
  printf 'All rows carrying an expectation matched.\n'
  exit 0
fi
printf 'At least one row DIFFERS from its expectation — read that row, not this line.\n'
exit 1
