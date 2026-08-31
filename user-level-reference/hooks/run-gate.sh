#!/usr/bin/env bash
# Gate runner (invoked by developers/PO, not registered as a hook):
#   bash hooks/run-gate.sh
#
# Reads the Gate command from PROJECT_CONTEXT.md ("**Gate**: <command>",
# with or without a leading list marker) and runs it. On success, writes
# the gate artifact that hooks/gate-before-merge.sh checks before allowing
# a PR merge:
#
#   .gate/last-pass.json  (at the repo toplevel of the current checkout/worktree)
#   {"sha":"<HEAD sha>","tree":"<working-tree hash>","branch":"<branch>",
#    "ts":"<UTC ISO-8601>","status":"pass"}
#
# On failure, any existing artifact is deleted and the script exits nonzero:
# 1 for an ordinary red gate (retry after fixing), GC_TERMINAL_RC (78) when the
# failure is terminal — a configuration the gate command cannot succeed under,
# where "re-run it" is the wrong advice. See the exit-code conventions block in
# hooks/lib/git-cmd.sh.
# No-op (exit 0) when the Gate field is missing or still a {{...}} placeholder,
# so templates degrade gracefully before a project configures its gate.
#
# v2.1.3 fix round 1 (review): a project whose **Gate** command itself invokes
# this script (e.g. "bash hooks/run-gate.sh" -- a copy/paste mistake, or a
# gate that shells out to a wrapper that shells out here) would otherwise
# recurse until the process/fd limit kills it. RUN_GATE_ACTIVE guards against
# that: it is exported before the gate command runs and checked on entry.

#
# v2.2.5 (consumer report): the guard was safe but its follow-on advice was
# circular — the outer layers appended "fix the failures and re-run" to a
# condition that no amount of re-running can change. GC_TERMINAL_RC, defined
# locally for the same standalone reason as GC_KEY_PRE below, is how a caller
# tells the two apart. See the exit-code conventions block in
# hooks/lib/git-cmd.sh; scripts/verify-template-consistency.sh asserts the two
# definitions stay in step.
GC_TERMINAL_RC=78

if [ "${RUN_GATE_ACTIVE:-}" = "1" ]; then
  echo "BLOCKED: **Gate** must not invoke run-gate.sh itself" >&2
  echo "Edit '**Gate**:' in PROJECT_CONTEXT.md to your real build/test commands — run-gate.sh RUNS that value, so it cannot BE that value." >&2
  exit "$GC_TERMINAL_RC"
fi

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: bash hooks/run-gate.sh"
  echo ""
  echo "Runs the Gate command from PROJECT_CONTEXT.md (**Gate**: <command>)."
  echo "Green: writes .gate/last-pass.json (checked by gate-before-merge.sh) and prints GATE PASS <sha>."
  echo "Red:   deletes the artifact and exits 1 (78 when the failure is terminal — see hooks/lib/git-cmd.sh)."
  echo "No Gate configured: prints GATE SKIP and exits 0."
  exit 0
fi

CWD=$(pwd)
REPO_TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_TOP" ]; then
  echo "GATE ERROR: not inside a git repository" >&2
  exit 1
fi

# GC_KEY_PRE, defined locally: this script is deliberately standalone (it must
# run with no JSON parser on PATH, which sourcing hooks/lib/git-cmd.sh would
# forbid), so it repeats the constant rather than importing it. The definition
# and the reason live in the header note on GC_KEY_PRE in hooks/lib/git-cmd.sh;
# scripts/verify-template-consistency.sh asserts the two stay in step.
GC_BOM=$(printf '\357\273\277')
GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"

# Read Gate command from PROJECT_CONTEXT.md. Tolerates: an optional leading
# UTF-8 BOM, leading "- " / "* " list
# markers, the "**Gate Command**:" label style (java/python variants), and
# surrounding backticks — several variants write commands as `cmd`.
GATE_CMD=$(grep -E "${GC_KEY_PRE}\*\*Gate( Command)?\*\*:" "$REPO_TOP/PROJECT_CONTEXT.md" 2>/dev/null | sed 's/.*\*\*Gate\( Command\)\?\*\*:[[:space:]]*//;s/[[:space:]]*$//;s/^`//;s/`$//' | head -1)

# No-op: no PROJECT_CONTEXT.md or no Gate command configured
if [ -z "$GATE_CMD" ]; then
  echo "GATE SKIP (no Gate command configured in PROJECT_CONTEXT.md)"
  exit 0
fi

# No-op: placeholder not yet filled in
case "$GATE_CMD" in
  *\{\{*\}\}*)
    echo "GATE SKIP (Gate command is still a template placeholder)"
    exit 0
    ;;
esac

HEAD_SHA=$(git -C "$CWD" rev-parse HEAD 2>/dev/null)
BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
ARTIFACT_DIR="$REPO_TOP/.gate"
ARTIFACT="$ARTIFACT_DIR/last-pass.json"

echo "GATE: running: $GATE_CMD"
cd "$REPO_TOP" || exit 1

# v2.1.3 fix round 1 (Critical 2 / penumbra #2c): key the artifact on the
# INDEX tree, not just HEAD's sha. At PreToolUse commit time (pre-commit-test.sh
# invoking this script before the `git commit` runs) the index tree is the tree
# the commit is about to get -- so gate-before-merge.sh can accept an artifact
# whose tree matches HEAD^{tree} even though its sha is the PARENT commit's,
# not the new one. Accepted miss: `git commit -a` or a commit with extra
# `git add` after this ran stages more than the index snapshot we hashed here
# -- that produces a tree mismatch too, and the merge gate falls back to
# requiring a fresh run, exactly as before this fix.
#
# v2.1.5 (consumer feedback: Yutraffic PR #223 e59e6fd vs 567f0d1, panoscribe
# PR #123): key the artifact on the WORKING TREE, not the index. The PreToolUse
# hook fires before a chained `git add ... && git commit` stages anything, so
# the v2.1.3 index tree was the PARENT tree and the v2.1.3-round-2 `git diff
# --quiet` guard recorded no tree at all -- the artifact matched nothing and the
# single-run merge path never fired for agents, who chain add+commit habitually.
#
# A temp index (a copy of the real one, so unchanged paths need no re-stat) is
# `add -A`'d and hashed. The REAL index is never touched, and .gitignore is
# respected, so .gate/ and build output stay out of the hash.
#
# Consequently `git add -A && git commit`, `git commit -a`, and separate
# add/commit calls all yield `HEAD^{tree} == tree`. A PARTIAL-add commit
# mismatches by design: the committed tree is not what was gated, so
# gate-before-merge.sh correctly demands a fresh run.
#
# CAVEAT -- the hash is taken BEFORE the gate command runs (deliberately: a
# gate that fails must not have its own mutations blessed). So a gate that
# MUTATES the tree makes the following commit mismatch anyway:
#   * a formatter in the gate rewriting tracked files;
#   * gate-generated output that is untracked and NOT gitignored (coverage
#     reports, `pytest-of-*`, build logs) -- `add -A` on the temp index writes
#     blobs for every unignored untracked file on every run, so such output
#     lands in the NEXT run's hash and never in this one's.
# The fix is on the project side: gitignore everything the gate produces (and
# run the formatter before the gate, not inside it).
#
# `rev-parse --git-path index` (not a hardcoded .git/index) is what makes this
# work in a LINKED WORKTREE, where the index lives at
# .git/worktrees/<name>/index -- coder/tester run under `isolation: worktree`.
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
TMPIDX="$TMPD/index"   # must not pre-exist: git rejects a 0-byte index
cp "$(git -C "$REPO_TOP" rev-parse --git-path index)" "$TMPIDX" 2>/dev/null || true
GIT_INDEX_FILE="$TMPIDX" git -C "$REPO_TOP" add -A >/dev/null 2>&1
TREE_HASH=$(GIT_INDEX_FILE="$TMPIDX" git -C "$REPO_TOP" write-tree 2>/dev/null)

RUN_GATE_ACTIVE=1
export RUN_GATE_ACTIVE
bash -c "$GATE_CMD"
GATE_RC=$?

if [ "$GATE_RC" -eq 0 ]; then
  mkdir -p "$ARTIFACT_DIR"
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  printf '{"sha":"%s","tree":"%s","branch":"%s","ts":"%s","status":"pass"}\n' \
    "$HEAD_SHA" "$TREE_HASH" "${BRANCH:-unknown}" "$TS" > "$ARTIFACT"
  echo "GATE PASS $HEAD_SHA"
  exit 0
elif [ "$GATE_RC" -eq "$GC_TERMINAL_RC" ]; then
  # TERMINAL: the gate command reported a condition retrying cannot change (a
  # self-invoking **Gate**, or any future guard that exits GC_TERMINAL_RC).
  # DELIBERATELY SILENT. The generic "fix the failures and re-run" of the else
  # arm is wrong here, and so is any replacement of it: only the guard knows the
  # specific remedy, it has already printed it on this same stderr, and it must
  # stay the LAST thing on screen. Printing a trailing summary would bury it
  # again — which is the exact defect this branch exists to fix. The code is
  # propagated so the caller (pre-commit-test.sh) can suppress ITS retry advice
  # by the same structural test, without knowing which guard fired.
  rm -f "$ARTIFACT"
  exit "$GC_TERMINAL_RC"
else
  rm -f "$ARTIFACT"
  echo "GATE FAILED: '$GATE_CMD' exited nonzero. Fix the failures and re-run 'bash hooks/run-gate.sh'." >&2
  exit 1
fi
