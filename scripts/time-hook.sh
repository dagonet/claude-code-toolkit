#!/usr/bin/env bash
# time-hook.sh — per-payload latency for the PreToolUse gates, WITH A CONTROL ARM.
#
# Why this exists, and why it has three arms rather than one. v3.0.3 item 25
# proposed an early exit for payloads that cannot be gated, on the reasoning
# that the ~1.5 s a gate spends is WORK (lib sourcing, git subprocesses, the
# parser) and not parse: measured, comments intact 49 KB -> 1512 ms/call, the
# same logic with comments stripped 17 KB -> 1559 ms, a no-op script 38 ms.
# Stripping 32 KB changed nothing. A number from a single arm on one machine
# cannot tell a real improvement from the machine being busier five minutes
# ago, so an UNCHANGED hook (retro-brief.sh, or whatever --control names) is
# timed in the same run. If the control arm moves as much as the treatment,
# the treatment number is NOISE and the change stands on its fixtures alone.
#
# The output is a plain table on purpose: a consumer re-runs this on their own
# machine, against their own baseline, and diffs the two tables.
#
# Usage:
#   bash scripts/time-hook.sh                 # 3 warm-ups + 20 runs per arm
#   RUNS=40 WARMUP=5 bash scripts/time-hook.sh
#
# Every arm ASSERTS ITS EXIT CODES ARE ALL EQUAL before reporting a median. An
# arm whose runs disagree is timing two different code paths, and its median is
# the average of two answers rather than one answer measured twenty times.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNS=${RUNS:-20}
WARMUP=${WARMUP:-3}
TMP=$(mktemp -d 2>/dev/null || mktemp -d -t timehook)
trap 'rm -rf "$TMP"' EXIT

jesc() {
  je=$(printf '%s.' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  printf '%s' "${je%.}"
}
mkjson() { # <tool> <command> <cwd>
  printf '{"session_id":"time-hook","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":{"command":"%s"},"cwd":"%s"}' \
    "$(jesc "$1")" "$(jesc "$2")" "$(jesc "$3")"
}

# --- a protected fixture repo with a **Gate** field, so nothing is vacuous ---
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q >/dev/null 2>&1
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t
git -C "$REPO" config commit.gpgsign false
echo seed > "$REPO/seed.txt"
printf '.gate/\n' > "$REPO/.gitignore"
printf '# ctx\n\n- **Gate**: `bash hooks/run-gate.sh`\n' > "$REPO/PROJECT_CONTEXT.md"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -q -m seed >/dev/null 2>&1
git -C "$REPO" branch -M main >/dev/null 2>&1
git -C "$REPO" branch feature/x >/dev/null 2>&1

# millisecond clock, portable across the three shells this repo runs under
now_ms() {
  if date +%s%3N 2>/dev/null | grep -qv N; then date +%s%3N; else
    python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || echo 0
  fi
}

# --- one arm: <label> <hook-path> <payload> ---------------------------------
# Prints "<label>|<median>|<q1>|<q3>|<iqr>|<exit>" or "<label>|MIXED-EXITS|…".
time_arm() {
  ta_label="$1"; ta_hook="$2"; ta_payload="$3"
  ta_i=0
  while [ "$ta_i" -lt "$WARMUP" ]; do
    printf '%s' "$ta_payload" | bash "$ta_hook" >/dev/null 2>&1
    ta_i=$((ta_i + 1))
  done
  : > "$TMP/samples"; : > "$TMP/exits"
  ta_i=0
  while [ "$ta_i" -lt "$RUNS" ]; do
    ta_t0=$(now_ms)
    printf '%s' "$ta_payload" | bash "$ta_hook" >/dev/null 2>&1
    ta_rc=$?
    ta_t1=$(now_ms)
    echo "$((ta_t1 - ta_t0))" >> "$TMP/samples"
    echo "$ta_rc" >> "$TMP/exits"
    ta_i=$((ta_i + 1))
  done
  ta_uniq=$(sort -u "$TMP/exits" | tr '\n' ',' | sed 's/,$//')
  case "$ta_uniq" in
    *,*) printf '%s|MIXED-EXITS(%s)|-|-|-|-\n' "$ta_label" "$ta_uniq"; return ;;
  esac
  sort -n "$TMP/samples" > "$TMP/sorted"
  ta_med=$(awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2)}' "$TMP/sorted")
  ta_q1=$(awk -v n="$RUNS" '{a[NR]=$1} END{i=int(NR/4); if(i<1)i=1; print a[i]}' "$TMP/sorted")
  ta_q3=$(awk '{a[NR]=$1} END{i=int(3*NR/4); if(i<1)i=1; print a[i]}' "$TMP/sorted")
  printf '%s|%s|%s|%s|%s|%s\n' "$ta_label" "$ta_med" "$ta_q1" "$ta_q3" "$((ta_q3 - ta_q1))" "$ta_uniq"
}

# GATE is overridable so a BASELINE copy of the hook — `git show
# main:hooks/gate-before-merge.sh` beside `main:hooks/lib/` in a temp dir — can
# be timed with the same fixture, warm-ups, run count and control arm. Without
# that, "the merge payload regressed 46%" is a number with nothing to subtract.
GATE="${GATE:-$ROOT/hooks/gate-before-merge.sh}"
CONTROL="${CONTROL:-$ROOT/hooks/retro-brief.sh}"
if [ ! -f "$CONTROL" ]; then
  # The control must be a hook this change does not touch. Fall back to another
  # untouched one rather than dropping the arm: a run with no control arm is a
  # run whose treatment number cannot be believed.
  for c in "$ROOT/hooks/read-size-gate.sh" "$ROOT/hooks/retro-ledger.sh" "$ROOT/hooks/bash-output-guard.sh"; do
    [ -f "$c" ] && { CONTROL="$c"; break; }
  done
fi

printf 'time-hook.sh — %s runs after %s warm-ups, medians in ms\n' "$RUNS" "$WARMUP"
printf '  gate:    %s\n' "$GATE"
printf '  control: %s (unchanged by this change)\n\n' "$CONTROL"
printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' ARM MEDIAN Q1 Q3 IQR EXIT
printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' '----------------------------------' -------- -------- -------- -------- ------

{
  time_arm 'gate / non-git payload (ls -la)'  "$GATE"    "$(mkjson Bash 'ls -la' "$REPO")"
  time_arm 'gate / merge payload'             "$GATE"    "$(mkjson Bash 'git merge feature/x' "$REPO")"
  time_arm 'control / unchanged hook'         "$CONTROL" "$(mkjson Bash 'ls -la' "$REPO")"
} | while IFS='|' read -r l m q1 q3 iqr ex; do
  printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' "$l" "$m" "$q1" "$q3" "$iqr" "$ex"
done

printf '\nRead the CONTROL row first. If it moved between two runs by as much as\n'
printf 'the treatment row did, the treatment number is noise and the change\n'
printf 'stands on its fixtures alone.\n'
