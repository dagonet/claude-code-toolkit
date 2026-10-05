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

# --- per-call arms: the user-level checks through THEIR registrations ---------
# old = the registration of the base commit (shell form, `sh -c`), new = the working tree's
# (exec form rendered by scripts/render-user-hooks.sh). Same fixture repo, same payloads.
BASE=""
[ -r "$ROOT/.superpowers/sdd/2026-10-04-hook-slimming/base.txt" ] &&
  BASE=$(sed -n 's/^PHASEC_BASE=\([0-9a-f]\{7,40\}\).*/\1/p' "$ROOT/.superpowers/sdd/2026-10-04-hook-slimming/base.txt" | head -n 1)
[ -n "$BASE" ] || BASE=$(grep -E '^[0-9a-f]{7,40}$' "$ROOT/scripts/fixtures/hook-equivalence/base.sha" 2>/dev/null | head -n 1)
REGS_OK=0
if [ -n "$BASE" ] && command -v python3 >/dev/null 2>&1; then
  mkdir -p "$TMP/oldroot" "$TMP/home-old/.claude" "$TMP/home-new/.claude"
  if git -C "$ROOT" archive "$BASE" 2>/dev/null | tar -x -C "$TMP/oldroot" 2>/dev/null; then
    cp -R "$ROOT/user-level-reference/hooks" "$TMP/home-new/.claude/hooks"
    cp -R "$TMP/oldroot/user-level-reference/hooks" "$TMP/home-old/.claude/hooks"
    BASHBIN=$(command -v bash)
    # argv files (NUL-separated) per set/hook/event, written by the registration reader
    if python3 - "$ROOT" "$TMP" "$BASHBIN" <<'PYEOF'
import sys, os, re, json, subprocess
root, tmp, bashbin = sys.argv[1:4]
for st, r in (("old", tmp + "/oldroot"), ("new", root)):
    home = "%s/home-%s" % (tmp, st)
    text = open(r + "/user-level-reference/settings.json", encoding="utf-8").read()
    ruh = r + "/scripts/render-user-hooks.sh"
    if os.path.isfile(ruh):
        out = subprocess.run(["bash", ruh, "--print"], stdout=subprocess.PIPE, check=True,
                             env=dict(os.environ, HOME=home, RUH_TEST_BASH=bashbin)).stdout.decode()
        hooks = json.loads(out)
    else:
        hooks = json.loads(text.replace("@BASH@", bashbin).replace("@HOOKS@", home + "/.claude/hooks"))["hooks"]
    for event, groups in hooks.items():
        for g in groups:
            for h in g.get("hooks", []):
                a = h.get("args")
                m = re.search(r"([A-Za-z0-9_-]+)\.sh$", a[-1]) if a else re.search(r"hooks/([A-Za-z0-9_-]+)\.sh", h.get("command", ""))
                if not m or not re.fullmatch(g.get("matcher") or ".*", "Bash"): continue
                argv = [h["command"]] + a if a else ["/bin/sh", "-c", h["command"]]
                open("%s/reg.%s.%s.%s" % (tmp, st, event, m.group(1)), "wb").write(b"\0".join(x.encode() for x in argv))
PYEOF
    then REGS_OK=1; fi
  fi
fi

# <label> <set old|new> <event> <hook> <payload>: time one registration (argv from the reg file)
time_reg() {
  tr_label="$1"; tr_f="$TMP/reg.$2.$3.$4"; tr_payload="$5"
  if [ ! -f "$tr_f" ]; then printf '%s|NO-REGISTRATION|-|-|-|-\n' "$tr_label"; return; fi
  tr_args=()
  while IFS= read -r -d '' tr_a || [ -n "$tr_a" ]; do tr_args+=("$tr_a"); done < "$tr_f"
  ta_label="$tr_label"; ta_payload="$tr_payload"
  time_cmd "$2" "${tr_args[@]}"
}

# like time_arm, but runs an argv with the home of set $1 and CLAUDE_PROJECT_DIR=$REPO
time_cmd() {
  tc_set="$1"; shift
  tc_run() { printf '%s' "$ta_payload" | HOME="$TMP/home-$tc_set" CLAUDE_PROJECT_DIR="$REPO" "$@" >/dev/null 2>&1; }
  ta_i=0
  while [ "$ta_i" -lt "$WARMUP" ]; do tc_run "$@"; ta_i=$((ta_i + 1)); done
  : > "$TMP/samples"; : > "$TMP/exits"
  ta_i=0
  while [ "$ta_i" -lt "$RUNS" ]; do
    ta_t0=$(now_ms); tc_run "$@"; ta_rc=$?; ta_t1=$(now_ms)
    echo "$((ta_t1 - ta_t0))" >> "$TMP/samples"; echo "$ta_rc" >> "$TMP/exits"
    ta_i=$((ta_i + 1))
  done
  ta_uniq=$(sort -u "$TMP/exits" | tr '\n' ',' | sed 's/,$//')
  case "$ta_uniq" in *,*) printf '%s|MIXED-EXITS(%s)|-|-|-|-\n' "$ta_label" "$ta_uniq"; return ;; esac
  sort -n "$TMP/samples" > "$TMP/sorted"
  ta_med=$(awk '{a[NR]=$1} END{print (NR%2)?a[(NR+1)/2]:int((a[NR/2]+a[NR/2+1])/2)}' "$TMP/sorted")
  ta_q1=$(awk '{a[NR]=$1} END{i=int(NR/4); if(i<1)i=1; print a[i]}' "$TMP/sorted")
  ta_q3=$(awk '{a[NR]=$1} END{i=int(3*NR/4); if(i<1)i=1; print a[i]}' "$TMP/sorted")
  printf '%s|%s|%s|%s|%s|%s\n' "$ta_label" "$ta_med" "$ta_q1" "$ta_q3" "$((ta_q3 - ta_q1))" "$ta_uniq"
}

printf 'time-hook.sh — %s runs after %s warm-ups, medians in ms\n' "$RUNS" "$WARMUP"
printf '  gate:    %s\n' "$GATE"
printf '  control: %s (unchanged by this change)\n\n' "$CONTROL"
printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' ARM MEDIAN Q1 Q3 IQR EXIT
printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' '----------------------------------' -------- -------- -------- -------- ------

{
  time_arm 'gate / non-git payload (ls -la)'  "$GATE"    "$(mkjson Bash 'ls -la' "$REPO")"
  time_arm 'gate / merge payload'             "$GATE"    "$(mkjson Bash 'git merge feature/x' "$REPO")"
  time_arm 'control / unchanged hook'         "$CONTROL" "$(mkjson Bash 'ls -la' "$REPO")"
  if [ "$REGS_OK" = 1 ]; then
    for cmd in 'git status' 'ls -la'; do
      for hk in no-push-main:PreToolUse deny-secret-reads:PreToolUse deny-hang-shapes:PreToolUse bash-output-guard:PostToolUse; do
        h=${hk%%:*}; ev=${hk##*:}
        pl=$(mkjson Bash "$cmd" "$REPO" | sed "s/\"PreToolUse\"/\"$ev\"/")
        [ "$ev" = PostToolUse ] && pl=${pl%\}},\"tool_response\":{\"stdout\":\"ok\",\"stderr\":\"\",\"interrupted\":false}}
        time_reg "$h old / $cmd" old "$ev" "$h" "$pl"
        time_reg "$h new / $cmd" new "$ev" "$h" "$pl"
      done
    done
  else
    printf 'per-call arms|SKIPPED (no base sha, python3 or archive)|-|-|-|-\n'
  fi
} | while IFS='|' read -r l m q1 q3 iqr ex; do
  printf '%-34s  %8s  %8s  %8s  %8s  %6s\n' "$l" "$m" "$q1" "$q3" "$iqr" "$ex"
done

printf '\nRead the CONTROL row first. If it moved between two runs by as much as\n'
printf 'the treatment row did, the treatment number is noise and the change\n'
printf 'stands on its fixtures alone.\n'
