# shellcheck shell=bash
# agent-model.sh -- the model an Agent spawn WITHOUT an explicit `model` runs on
# (v4.4.0; the logic is v4.3.0's model-floor.sh, moved here unchanged).
#
# Two callers, one answer (Jev Phase 1 spec, step 2: the router "reuses
# model-floor's resolution code rather than re-deriving it"):
#   - hooks/model-floor.sh SOURCES it: am_resolve, then am_jev_routing;
#   - the Jev router (plugins/cct-jev/skills/jev/jev_route.py) RUNS it:
#       bash agent-model.sh <subagent_type> <cwd>
#     and reads ONE line: "<kind> <model|-> <jev 0|1> <effort|-> <git common dir|->".
#     Arguments are data: a type outside [A-Za-z0-9_.-] (bar one `cct:` prefix) resolves to `none`,
#     unless it is exactly a row of the agent type table (am_table).
# kind: own   -- the agent file sets a model (an alias or a full id): its choice
#       floor -- no model of its own (`inherit`, none, or a known inheriting
#                built-in with no file): **Subagent default model**, else sonnet
#       env   -- CLAUDE_CODE_SUBAGENT_MODEL holds a real model and covers this
#                spawn (S-23/S-30); AM_MODEL is its value. model-floor steps
#                aside (the native default wins); the Jev router routes from
#                that value (user ruling U-1)
#       none  -- a self-modelled built-in, a type no visible file defines (cct:<n> is
#                looked up in the plugin's agents/ only), another plugin's x:y that is not
#                a row of the agent type table (am_table, v7.0.0), or an unsafe name:
#                change nothing
# Agent identity (S-22): the frontmatter `name:`, .claude/agents/ scanned
# recursively, project before user level, filename as the fallback.
# No JSON parser needed: it reads frontmatter and PROJECT_CONTEXT.md only.
# Shipped by the cct plugin (hooks/lib/), pinned byte for byte into plugins/cct-jev/hooks/lib/ (check 88), and by sync-template into projects; no user-level copy since v5.0.

# S-23/S-30: CLAUDE_CODE_SUBAGENT_MODEL is a native default only when it holds a
# REAL model (an alias or a full claude-* id); `inherit` or empty means unset.
AM_ENV_REAL=""
case "${CLAUDE_CODE_SUBAGENT_MODEL:-}" in haiku|sonnet|opus|fable|claude-*) AM_ENV_REAL=1 ;; esac
# am_env_forced -- with CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 the variable covers
# every spawn. Without FORCE it covers only general-purpose and an untyped spawn.
am_env_forced() { [ -n "$AM_ENV_REAL" ] && [ "${CLAUDE_CODE_SUBAGENT_MODEL_FORCE:-}" = 1 ]; }

# GC_BOM / GC_KEY_PRE: the same text as hooks/lib/git-cmd.sh and run-gate.sh,
# pinned together by the definition census (check 21c-2). Sourcing git-cmd.sh
# here would cost ~57 ms per Agent spawn. A BOM on line 1 must not hide the key.
GC_BOM=$(printf '\357\273\277')
GC_KEY_PRE="^(${GC_BOM})?[-*[:space:]]*"

# am_fm <file> <key> -- a frontmatter value, unquoted, no whitespace, CR and a
# leading BOM tolerated. Empty when the key (or the frontmatter) is absent.
am_fm() { awk -v k="$2" -v bom="$GC_BOM" 'NR==1&&index($0,bom)==1{$0=substr($0,length(bom)+1)} NR==1&&/^---/{f=1;next} f&&/^---/{exit} f&&index($0,k":")==1{sub(/^[^:]*:[[:space:]]*/,"");print;exit}' "$1" 2>/dev/null | tr -d '\r"'"'"'[:space:]'; }
# am_find <agents dir> <type> -- the first *.md under it (recursively) whose
# frontmatter name equals <type>. grep narrows the candidates; am_fm confirms the
# name is really in the frontmatter (a `name:` line in a body does not count).
am_find() {
  [ -d "$1" ] || return 0
  grep -rlE "^name:[[:space:]]*[\"']?${2}[\"']?[[:space:]]*\$" --include='*.md' "$1" 2>/dev/null | while IFS= read -r am_c; do
    if [ "$(am_fm "$am_c" name)" = "$2" ]; then printf '%s\n' "$am_c"; break; fi
  done | head -1
}

# am_plugin_root -- CLAUDE_PLUGIN_ROOT, else two levels above this file. The fallback is
# right only when this library sits inside the plugin; the user-level copy points it at
# ~/.claude, which Tasks 7/13 retire.
am_plugin_root() { printf '%s' "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"; }

# am_table <type> -- the fixed agent type table (v7.0.0, spec section 10 item 1). One row per toolkit agent type:
# the six core types and the four language plugins' coders. A row sets AM_T_MODEL, AM_T_EFFORT and AM_T_PIPE (the
# `pipeline:` flag, empty for none); a type that is not a row returns 1 and sets nothing. No sibling-plugin file is
# read: a plugin's agents are not on a path this library can know. Check 87 pins every row, two-sided, against
# the agent file's frontmatter, so the table cannot drift from the file it describes.
am_table() {
  AM_T_MODEL=""; AM_T_EFFORT=""; AM_T_PIPE=""
  case "$1" in
    cct:coder)                  AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=true ;;
    cct:code-reviewer)          AM_T_MODEL=opus   AM_T_EFFORT=xhigh  AM_T_PIPE=true ;;
    cct:tester)                 AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=notify ;;
    cct:architect)              AM_T_MODEL=opus   AM_T_EFFORT=xhigh  AM_T_PIPE=notify ;;
    cct:Explore)                AM_T_MODEL=haiku  AM_T_EFFORT=low ;;
    cct:ops)                    AM_T_MODEL=sonnet AM_T_EFFORT=medium ;;
    dotnet-tools:dotnet-coder)  AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=true ;;
    python-tools:python-coder)  AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=true ;;
    rust-tools:rust-coder)      AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=true ;;
    java-tools:java-coder)      AM_T_MODEL=sonnet AM_T_EFFORT=medium AM_T_PIPE=true ;;
    *) return 1 ;;
  esac
}

# am_resolve <type> <cwd> -- sets AM_KIND, AM_MODEL, AM_EFFORT, AM_PIPELINE, AM_ROOT.
# AM_ROOT stays empty on the early `env`/`none`/table answers (no git call needed). AM_PIPELINE is set only
# by a table row (the other types' `pipeline:` flag is read from their file by whoever needs it).
am_resolve() {
  AM_KIND=none; AM_MODEL=""; AM_EFFORT=""; AM_PIPELINE=""; AM_ROOT=""
  am_t=${1:-general-purpose}
  am_env_forced && { AM_KIND=env; AM_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL; return 0; }
  [ -n "$AM_ENV_REAL" ] && [ "$am_t" = general-purpose ] && { AM_KIND=env; AM_MODEL=$CLAUDE_CODE_SUBAGENT_MODEL; return 0; }
  # v7.0.0: a table row answers before any file is read (the plugin's agents/ included).
  if am_table "$am_t"; then
    AM_KIND=own; AM_MODEL=$AM_T_MODEL; AM_EFFORT=$AM_T_EFFORT; AM_PIPELINE=$AM_T_PIPE
    return 0
  fi
  # v5.0: plugin agents are named cct:<name> and live in the plugin's agents/ (spec §2).
  # Another plugin's agent (x:y) is not a toolkit agent: not ours, change nothing.
  am_plug=""
  case "$am_t" in
    cct:*) am_t=${am_t#cct:}; am_plug=1
           case "$am_t" in *..*) return 0 ;; esac ;;
    *:*)   return 0 ;;
  esac
  case "$am_t" in *[!A-Za-z0-9_.-]*|.*) return 0 ;; esac
  # Types that carry a model of their own (statusline-setup: sonnet,
  # claude-code-guide: haiku) or ignore a model override (fork).
  case "$am_t" in statusline-setup|claude-code-guide|fork) return 0 ;; esac
  AM_ROOT=$(git -C "${2:-.}" rev-parse --show-toplevel 2>/dev/null) || AM_ROOT=${2:-.}
  am_file=""
  if [ -n "$am_plug" ]; then
    # exactly the plugin's file: no project/user lookup, and no built-in fallback below
    am_file="$(am_plugin_root)/agents/$am_t.md"
    [ -f "$am_file" ] || return 0
  else
    for am_d in "$AM_ROOT/.claude/agents" "$HOME/.claude/agents"; do
      am_file=$(am_find "$am_d" "$am_t")
      [ -n "$am_file" ] && break
    done
  fi
  if [ -z "$am_file" ] && [ -z "$am_plug" ]; then
    for am_f in "$AM_ROOT/.claude/agents/$am_t.md" "$HOME/.claude/agents/$am_t.md"; do
      [ -f "$am_f" ] && { am_file=$am_f; break; }
    done
  fi
  if [ -n "$am_file" ]; then
    AM_EFFORT=$(am_fm "$am_file" effort)
    AM_MODEL=$(am_fm "$am_file" model)
    # Any model of its own -- an alias or a full id -- is the agent's choice;
    # only `inherit` (or none) falls through to the floor.
    case "$AM_MODEL" in ""|inherit) AM_MODEL="" ;; *) AM_KIND=own; return 0 ;; esac
  else
    # No file: only the known inheriting built-ins. Anything else may be defined
    # where this cannot look (--agents, managed settings, another plugin): do nothing.
    case "$am_t" in general-purpose|Plan|Explore|claude) ;; *) return 0 ;; esac
  fi
  AM_MODEL=$(grep -E "${GC_KEY_PRE}\*\*Subagent default model\*\*:" "$AM_ROOT/PROJECT_CONTEXT.md" 2>/dev/null | head -1 | sed -E 's/.*\*\*Subagent default model\*\*:[[:space:]]*//; s/[`[:space:]]//g')
  case "$AM_MODEL" in haiku|sonnet|opus|fable) ;; *) AM_MODEL=sonnet ;; esac
  AM_KIND=floor
}

# AM_JEV_MARKER -- the path every v4 /jev registration names. Check 65 asserts the
# v4 registration literal (REG_COMMAND in jev_ctl.py, now only what legacy removal matches) contains it.
AM_JEV_MARKER='skills/jev/jev_route.py'
# am_jev_loaded <session_id> -- exit 0 iff the cct-jev plugin's SessionStart hook (plugins/cct-jev/hooks/cct-jev-session.sh)
# marked this session. The marker lives in ${TMPDIR:-/tmp}/cct-jev-<uid>/, NOT in cct-<uid>/ (the folder the project template's
# guard reads), so it can never satisfy that guard and the cct-session marker can never satisfy this. The id is sanitized as the
# writer does: only [A-Za-z0-9-], else "not loaded". A marker dir this user does not own is no marker dir, except on Git Bash/Cygwin.
am_jev_loaded() {
  case ${1:-} in ''|*[!A-Za-z0-9-]*) return 1 ;; esac
  local am_d="${TMPDIR:-/tmp}/cct-jev-$(id -u)"
  case $(uname -s) in MINGW*|MSYS*|CYGWIN*) ;; *) [ -O "$am_d" ] || return 1 ;; esac
  [ -f "$am_d/$1" ]
}
# am_jev_routing <root> [<session_id>] -- exit 0 iff the Jev router WILL run for a spawn in this
# checkout, so model-floor may step aside (v4.4.0 R-2). All of these must hold:
#   1. <git common dir>/jev/config.json says "route": true      (/cct-jev:jev on, per clone)
#   2. python3 runs                                              (the registration runs it)
#   3. a router exists to run it                                 (a deleted skill is silent):
#      - WITH a session id (model-floor always passes one, possibly empty; v7.0.0): the cct-jev plugin is LOADED in this
#        session (am_jev_loaded, its own marker). cct holds no router file, so the files are not asked: the marker is the
#        only evidence that the plugin's hooks.json is registered. Uninstalled plugin = no marker = the floor applies.
#      - WITHOUT one (jev-route.sh, jev-notice.sh and the executed mode run only inside the loaded plugin): the plugin's own
#        .claude-plugin/plugin.json and skills/jev/jev_route.py exist (this file is pinned, byte for byte, into cct-jev).
#   4. a v4 registration in <root>/.claude/settings.local.json runs ~/.claude/skills/jev/jev_route.py takes the place of 3
#      (per CHECKOUT: a sibling worktree of the same clone has its own settings.local.json); jev-route.sh steps aside for it
# Any one missing -> model-floor floors, so a spawn never has neither emitter.
# Sets AM_GD (the absolute git common dir) whenever git answers.
am_jev_routing() {
  AM_GD=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$AM_GD" ] || return 1
  grep -Eq '"route"[[:space:]]*:[[:space:]]*true' "$AM_GD/jev/config.json" 2>/dev/null || return 1
  python3 -c '' >/dev/null 2>&1 || return 1
  if grep -qF "$AM_JEV_MARKER" "$1/.claude/settings.local.json" 2>/dev/null; then
    [ -f "$HOME/.claude/skills/jev/jev_route.py" ]   # v4 entry: it routes (jev-route.sh steps aside), if its file is there
  elif [ $# -ge 2 ]; then
    am_jev_loaded "$2"
  else
    local am_pr; am_pr=$(am_plugin_root)
    [ -f "$am_pr/.claude-plugin/plugin.json" ] && [ -f "$am_pr/skills/jev/jev_route.py" ]
  fi
}

# Executed (the Jev router), not sourced: print the one-line answer.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  am_resolve "${1:-}" "${2:-.}"
  [ -n "$AM_ROOT" ] || AM_ROOT=$(git -C "${2:-.}" rev-parse --show-toplevel 2>/dev/null) || AM_ROOT=${2:-.}
  if am_jev_routing "$AM_ROOT"; then am_j=1; else am_j=0; fi
  printf '%s %s %s %s %s\n' "$AM_KIND" "${AM_MODEL:--}" "$am_j" "${AM_EFFORT:--}" "${AM_GD:--}"
fi
