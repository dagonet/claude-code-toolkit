#!/usr/bin/env bash
# End-to-end smoke test of the cct plugin (v5.0 spec section 5). Run before each release; NOT part of the gate.
# Runs nested `claude -p --plugin-dir <checkout>` in a scratch git repo. Writes nothing under ~/.claude itself (claude's
# own per-cwd projects dirs for the scratch repos are removed at the end):
# every call gets a private TMPDIR (session markers) and CLAUDE_MEMORY_HOME (retro ledger), the session id of
# the outer session is unset, and the model is haiku. Real model calls: it costs a little and takes minutes.
# The scratch workspace is untrusted, so claude ignores its permissions.allow: rows depend on auto mode allowing the
# prompts. Row 5 runs WITHOUT --no-session-persistence: with it no subagent transcript exists and retro-ledger.sh
# (which reads agent_transcript_path) never writes its row.
# Output: one `PASS <label>` or `FAIL <label>` line per check; exit 1 on any FAIL.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v claude >/dev/null 2>&1 || { echo "FAIL claude CLI not on PATH"; exit 1; }
WORK=$(mktemp -d)
# claude keeps a ~/.claude/projects/<slug> dir for every cwd it ran in, whatever the flags. Remove ONLY the
# ones for this script's own scratch repos (slug = path with every : \ / . _ turned into -, as claude names it).
cleanup() {
  local d slug
  for d in "$WORK/scratch" "$WORK/scratch-off"; do
    slug=$(printf '%s' "$d" | sed 's/[:\\/._]/-/g')
    case $slug in -tmp-*) rm -rf "${HOME:?}/.claude/projects/$slug" ;; esac
  done
  rm -rf "$WORK"
}
trap cleanup EXIT
FAILS=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1${2:+ -- $2}"; FAILS=$((FAILS + 1)); }

# --- scratch repo: v5 template settings + manifest + a local bare origin -------------------------------------
# $1 = dir, $2 = true|false (enabledPlugins value for cct@dagonet)
mkscratch() {
  mkdir -p "$1/.claude"
  sed "s/\"cct@dagonet\": true/\"cct@dagonet\": $2/" "$ROOT/templates/general/.claude/settings.json" > "$1/.claude/settings.json"
  echo '{}' > "$1/.claude/template-manifest.json"
  git init -q -b main "$1" && git -C "$1" config user.email smoke@example.invalid && git -C "$1" config user.name smoke
  git init -q --bare "$WORK/origin-$(basename "$1").git"
  git -C "$1" remote add origin "$WORK/origin-$(basename "$1").git"
  printf '%s\n' '.claude/' 'out.*' > "$1/.gitignore"
  echo smoke > "$1/README.md"
  git -C "$1" add -A && git -C "$1" commit -q -m init
}

# $1 = repo dir, $2 = plugin dir ("" = none), $3 = prompt. Streams JSON events (tool results included) to stdout.
# $4.. = extra claude args. stderr is merged so a hook's stderr is visible too.
cl() {
  local repo=$1 plug=$2 prompt=$3; shift 3
  local pa=(); [ -n "$plug" ] && pa=(--plugin-dir "$plug")
  # PERSIST=1 drops --no-session-persistence: without it no subagent transcript exists, so retro-ledger.sh
  # (which reads agent_transcript_path) can never write a row. Only check 5 needs that.
  local np=(--no-session-persistence); [ "${PERSIST:-}" = 1 ] && np=()
  ( cd "$repo" && env -u CLAUDE_CODE_SESSION_ID TMPDIR="$WORK/tmp" CLAUDE_MEMORY_HOME="$WORK/mem" \
      timeout 300 claude -p --model haiku "${np[@]}" --output-format stream-json --verbose \
      "${pa[@]}" "$@" "$prompt" 2>&1 )
}

mkdir -p "$WORK/tmp" "$WORK/mem"
SC="$WORK/scratch"; mkscratch "$SC" true
OFFSC="$WORK/scratch-off"; mkscratch "$OFFSC" false

# 1. A push to main is refused and its side effect never happens.
check_push_refused() {
  local out; out=$(cl "$SC" "$ROOT" "Run exactly this one Bash command and report the result: git push origin main; touch $SC/out.pushed")
  if [ -e "$SC/out.pushed" ]; then fail "1 push to main refused" "side-effect file exists"
  elif ! printf '%s' "$out" | grep -q 'BLOCKED'; then fail "1 push to main refused" "no BLOCKED tool result in the stream"
  elif git -C "$WORK/origin-scratch.git" rev-parse -q --verify main >/dev/null 2>&1; then fail "1 push to main refused" "origin has main"
  else pass "1 push to main refused"; fi
}

# 2. An innocent command runs (and so does the guard's marker path: the plugin wrote the marker).
check_true_runs() {
  local dir=${1:-$SC} plug=${2:-$ROOT} label=${3:-2 true runs} out
  out=$(cl "$dir" "$plug" "Run exactly this one Bash command: touch out.ran" )
  if [ -e "$dir/out.ran" ]; then pass "$label"; else fail "$label" "side-effect file absent: $(printf '%s' "$out" | grep -o 'BLOCKED[^"]*' | head -1)"; fi
  rm -f "$dir/out.ran"
}

# 3. Plugin disabled (enabledPlugins false, no --plugin-dir, private TMPDIR): every tool refused, exact guard message.
check_plugin_off() {
  local out; out=$(cl "$OFFSC" "" "Run exactly this one Bash command: touch out.off")
  if [ -e "$OFFSC/out.off" ]; then fail "3 plugin off refuses" "side-effect file exists"
  elif printf '%s' "$out" | grep -q 'BLOCKED: the cct plugin is not active in this session. Install it with /plugin marketplace add dagonet/claude-code-toolkit and /plugin install cct@dagonet, then restart the session.'; then pass "3 plugin off refuses"
  else fail "3 plugin off refuses" "guard message not in the stream"; fi
}

# 4. cct-gate resolves inside a Bash tool call.
check_gate_on_path() {
  local out; out=$(cl "$SC" "$ROOT" "Run exactly this one Bash command and report its output: command -v cct-gate")
  if printf '%s' "$out" | grep -q 'bin/cct-gate'; then pass "4 cct-gate on PATH"; else fail "4 cct-gate on PATH" "no path printed"; fi
}

# 5. A cct:Explore spawn returns, and its stop is recorded in the retro ledger under cct:Explore. The ledger only
#    records failures, so the subagent runs a command shape that deny-hang-shapes refuses (a leading cd before
#    several commands). A push to main would also do, but the auto-mode classifier denies the spawn itself then.
#    A subagent's tool calls are not refused by the guard: it carries the parent's session_id.
check_explore_spawn() {
  local out led
  rm -rf "$WORK/mem"; mkdir -p "$WORK/mem"
  out=$(PERSIST=1 cl "$SC" "$ROOT" "Use the Agent tool exactly once with subagent_type cct:Explore and this prompt: 'Run this Bash command once: cd /tmp && ls && pwd (it may be refused; that is fine, do not retry). Then reply with the word done.' Then report what the agent returned.")
  led=$(find "$WORK/mem" -name retro.md 2>/dev/null | head -1)
  if [ -z "$led" ]; then fail "5 cct:Explore spawn" "no retro ledger written"
  elif grep -q 'cct:Explore' "$led"; then pass "5 cct:Explore spawn"
  else fail "5 cct:Explore spawn" "ledger has no cct:Explore row: $(head -c 200 "$led")"; fi
}

# 6. Hook cost: median of 15 sequential `true` calls with and without the plugin. Informational.
median_ms() {
  local dir=$1 plug=$2 i s e ts=()
  for i in $(seq 15); do
    s=$(date +%s%N); cl "$dir" "$plug" "Run exactly this one Bash command: true" >/dev/null; e=$(date +%s%N)
    ts+=($(( (e - s) / 1000000 )))
  done
  printf '%s\n' "${ts[@]}" | sort -n | sed -n 8p
}
check_hook_cost() {
  local on off
  on=$(median_ms "$SC" "$ROOT"); off=$(median_ms "$OFFSC" "")
  echo "INFO 6 hook cost medians (15 runs each, whole claude -p call): with plugin ${on}ms, plugin off ${off}ms (the off run is refused at the first tool call, so it is a floor, not a like-for-like)"
  pass "6 hook cost measured"
}

# 7. A checkout path containing a space.
check_space_path() {
  local sp="$WORK/cct smoke"
  mkdir -p "$sp" && git -C "$ROOT" archive HEAD | tar -x -C "$sp" || { fail "7 path with a space" "copy failed"; return; }
  check_true_runs "$SC" "$sp" "7 path with a space"
}

# 8. After the run the scratch repo shows nothing the plugin wrote (the side-effect files are ignored via .gitignore).
check_scratch_clean() {
  local st; st=$(git -C "$SC" status --porcelain)
  if [ -z "$st" ]; then pass "8 scratch repo clean"; else fail "8 scratch repo clean" "$(printf '%s' "$st" | head -3 | tr '\n' ';')"; fi
}

# 9. Two processes sharing a session id: SessionEnd for the sid removes the marker, so a second process is refused.
#    Safe direction, pinned here. Driven directly, no model call.
check_shared_sid() {
  local t="$WORK/sid" sid=smoke-sid-1 guard rc1 rc2
  mkdir -p "$t"
  guard=$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]["command"])' "$ROOT/templates/general/.claude/settings.json" 2>/dev/null)
  [ -n "$guard" ] || { fail "9 shared session id" "guard command not found"; return; }
  printf '{"session_id":"%s"}' "$sid" | TMPDIR="$t" bash "$ROOT/hooks/cct-session.sh"
  printf '{"session_id":"%s"}' "$sid" | TMPDIR="$t" bash -c "$guard" 2>/dev/null; rc1=$?
  printf '{"session_id":"%s"}' "$sid" | TMPDIR="$t" bash "$ROOT/hooks/cct-session.sh" end
  printf '{"session_id":"%s"}' "$sid" | TMPDIR="$t" bash -c "$guard" 2>/dev/null; rc2=$?
  if [ "$rc1" = 0 ] && [ "$rc2" = 2 ]; then pass "9 shared session id"; else fail "9 shared session id" "guard rc before end=$rc1 after end=$rc2 (want 0 then 2)"; fi
}

check_push_refused
check_true_runs "$SC" "$ROOT" "2 true runs"
check_plugin_off
check_gate_on_path
check_explore_spawn
check_hook_cost
check_space_path
check_scratch_clean
check_shared_sid

[ "$FAILS" = 0 ] && echo "SMOKE PASS" || echo "SMOKE FAIL ($FAILS)"
[ "$FAILS" = 0 ]
