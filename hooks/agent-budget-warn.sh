#!/usr/bin/env bash
# PreToolUse tool-call budget for agents. Counters the runaway single spawn.
#
# Measured motivation: median 38 tool calls per agent, but the worst spawn ran
# 565 calls over 4.2 hours and another burned 9.06 hours before ending
# mid-sentence. Nothing in the toolkit bounded a single spawn.
#
# Contract (measured from live hook stdin):
#   Named teammates DO fire the project's PreToolUse and DO carry agent_id
#   (e.g. "aprobe-teammate-2-e14467006a486b91") plus agent_type. Main-thread
#   calls carry neither. So agent_id is a sound discriminator here, and the
#   agents that actually run away are reachable.
#
# Cost discipline: this fires on EVERY agent tool call, so the hot path is pure
# shell — one grep, no node, and an immediate exit on the main thread.
#
# Posture: WARN first, then block ONCE, then warn again. A hard wall would break
# legitimate large tasks; the goal is to force one deliberate reconsideration.
# Wrap with the WARN-on-127 form in settings.json (exit 0) — a missing budget
# hook must never brick every tool call.

set -u

WARN_AT=60
BLOCK_AT=120
WARN_EVERY=60

INPUT=$(cat 2>/dev/null || true)
[ -z "$INPUT" ] && exit 0

# Fast path: main thread has no agent_id -> not our business.
AGENT_ID=$(printf '%s' "$INPUT" | grep -o '"agent_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$AGENT_ID" ] && exit 0

SESSION=$(printf '%s' "$INPUT" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -z "$SESSION" ] && exit 0

# Kill switch, mirroring the other guards.
HOOK_CWD=$(printf '%s' "$INPUT" | grep -o '"cwd":"[^"]*"' | head -1 | cut -d'"' -f4)
if [ -n "${HOOK_CWD:-}" ]; then
  ROOT=$(printf '%s' "$HOOK_CWD" | tr '\\' '/')
  [ -f "$ROOT/.claude/liveness-off" ] && exit 0
fi

# Sanitize: agent_id is used as a filename.
SAFE=$(printf '%s' "$AGENT_ID" | tr -c 'A-Za-z0-9._-' '_')
DIR="${TMPDIR:-/tmp}/claude-agent-budget/$SESSION"
mkdir -p "$DIR" 2>/dev/null || exit 0
COUNTER="$DIR/$SAFE"

N=0
[ -f "$COUNTER" ] && N=$(cat "$COUNTER" 2>/dev/null || echo 0)
case "$N" in ''|*[!0-9]*) N=0 ;; esac
N=$((N + 1))
printf '%s' "$N" > "$COUNTER" 2>/dev/null || exit 0

# Block exactly once, at BLOCK_AT.
if [ "$N" -eq "$BLOCK_AT" ]; then
  cat >&2 <<EOF
BUDGET: this spawn has made $N tool calls (typical is under 40).

Stop expanding and land what you have. Report your partial result plus the
blocker and let the PO re-tier the remainder — do not keep growing scope inside
one spawn. A long run is not evidence of progress.

This blocks once. Continuing past it is allowed, but be deliberate about it.
EOF
  exit 2
fi

# Advisory warnings: at WARN_AT, and every WARN_EVERY calls past BLOCK_AT.
if [ "$N" -eq "$WARN_AT" ]; then
  printf 'BUDGET: %s tool calls so far. Check that you are still inside your stated scope.\n' "$N" >&2
elif [ "$N" -gt "$BLOCK_AT" ] && [ $(( (N - BLOCK_AT) % WARN_EVERY )) -eq 0 ]; then
  printf 'BUDGET: %s tool calls. Still expanding — report partial progress and the blocker instead.\n' "$N" >&2
fi

exit 0
