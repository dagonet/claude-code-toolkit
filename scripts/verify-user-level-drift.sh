#!/usr/bin/env bash
# verify-user-level-drift.sh [--worktree | <git-ref>]
#
# The delivery probe: does this machine's ~/.claude match a released user level?
#
# SINCE v5.0 the agents, skills, output style and hooks come from the cct plugin, and the
# user level is only CLAUDE.md and settings.json. A machine is 0 drift against a v5.0+ REF when
#   (a) ~/.claude/CLAUDE.md equals the reference CLAUDE.md (on Linux: its Linux rendering);
#   (b) ~/.claude/plugins/installed_plugins.json records cct@dagonet at user scope at the first
#       line of REF's VERSION (a missing or unreadable file, or another version, is drift) AND
#       settings.json has enabledPlugins["cct@dagonet"] == true;
#   (c) no path from REF's scripts/lib/v4-user-leftovers.txt exists under ~/.claude;
#   (d) REF's hooks/verify-hooks.sh --report finds no stale hook registration in the live HOME;
# and permissions.autoMode.environment in settings.json matches the reference (below).
# A REF older than v5.0 (no leftovers list) is compared the pre-v5.0 way: CLAUDE.md plus every
# hooks/, skills/, agents/ and output-styles/ file that REF shipped, byte for byte.
#
# Direction of truth: **the reference leads, the live copy follows.** The repo files are edited
# first; ~/.claude/ is updated per the CHANGELOG's "Downstream migration" section. A DRIFT result
# in the same session that changed the reference means the migration has not run here yet.
#
# THE REFERENCE IS A RELEASED TAG, NOT THE WORKING TREE (v2.2.5 round 4): a live copy matching
# an unmerged branch once read as 0 drift, certifying an unreviewed revision. `--worktree`
# compares against the working tree for pre-release inspection; it prints a banner and is never
# a release check.
#
# settings.json is NOT byte-compared: a user's own permissions, env and MCP entries are theirs.
# It is read for three things only: enabledPlugins["cct@dagonet"] (b), the registered hooks (d,
# through verify-hooks.sh) and the key-scoped autoMode.environment comparison.
#
# Run ad-hoc; not wired into any hook. Works from any cwd (cd's to repo root).
set -u

cd "$(dirname "$0")/.." || { echo "ERROR: cannot resolve repo root"; exit 2; }

MODE="tag"
REF=""
case "${1:-}" in
  --worktree) MODE="worktree" ;;
  "") ;;
  *) REF="$1" ;;
esac

LIVE_ROOT="$HOME/.claude"
if [ ! -d "$LIVE_ROOT" ]; then
  echo "ERROR: $LIVE_ROOT not found — no live user-level tree to compare"
  exit 2
fi

if [ "$MODE" = "tag" ]; then
  if [ -z "$REF" ]; then
    REF=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)
  fi
  # Cannot-determine REFUSES. A silent fallback to the working tree is exactly
  # the failure this mode was added to close.
  if [ -z "$REF" ] || ! git rev-parse --verify "$REF^{commit}" >/dev/null 2>&1; then
    echo "ERROR: cannot resolve a released reference (no v* tag reachable from HEAD)."
    echo "  Pass an explicit <git-ref>, or --worktree to compare against the working tree (NOT a release check)."
    exit 2
  fi
  if git rev-parse -q --verify "refs/tags/$REF" >/dev/null 2>&1; then
    REF_KIND="released tree"
  else
    REF_KIND="tree at $REF, not a release tag"
  fi
  echo "REFERENCE: $REF ($(git rev-parse --short "$REF^{commit}")) — $REF_KIND"
else
  echo "REFERENCE: WORKING TREE — this is NOT a release check. A live copy matching"
  echo "  an unshipped branch will report 0 drift, which certifies nothing."
fi

checked=0
in_sync=0
drift=0
drift_list=""

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

# Materialise the reference copy of <repo-path>; prints the path, or nothing
# when the file does not exist at that reference.
ref_copy() { # <repo-relative path>
  if [ "$MODE" = "worktree" ]; then
    [ -f "$1" ] && printf '%s' "$1"
    return
  fi
  out="$TMPD/$(printf '%s' "$1" | tr '/' '_')"
  if git show "$REF:$1" > "$out" 2>/dev/null; then
    printf '%s' "$out"
  fi
}

# Pre-v5.0 refs: skills/ and output-styles/ lived under user-level-reference/ before v5.0 moved
# them to the plugin root. The listing tries the new location first, then the old one.
sub_roots() { # <sub> -> candidate repo dirs, new location first
  case "$1" in
    skills|output-styles) printf '%s\n' "$1" "user-level-reference/$1" ;;
    *) printf '%s\n' "user-level-reference/$1" ;;
  esac
}
live_rel() { # <repo path of a file under a sub> -> its path relative to ~/.claude
  case "$1" in user-level-reference/*) printf '%s' "${1#user-level-reference/}" ;; *) printf '%s' "$1" ;; esac
}

# The path under which the reference carries <repo path>: itself, else (a tag older than v5.0)
# its user-level-reference/ twin; nothing when neither exists. ONE resolver for every site.
released_path() { # <repo-relative path>
  if [ "$MODE" = "worktree" ]; then
    [ -f "$1" ] && printf '%s' "$1"
    return
  fi
  if git cat-file -e "$REF:$1" 2>/dev/null; then printf '%s' "$1"; return; fi
  if git cat-file -e "$REF:user-level-reference/${1#user-level-reference/}" 2>/dev/null; then
    printf '%s' "user-level-reference/${1#user-level-reference/}"
  fi
}

check_file() { # <repo-relative ref path> <live_path> [expected file, instead of the reference copy]
  rp=$(released_path "$1")
  src=${3:-${rp:+$(ref_copy "$rp")}}
  checked=$((checked + 1))
  if [ -z "$src" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  CANNOT COMPARE: $1 is not in ${REF:-the working tree}"
    return
  fi
  if [ ! -f "$2" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  MISSING live: $2"
    return
  fi
  if diff -q "$src" "$2" >/dev/null 2>&1; then
    in_sync=$((in_sync + 1))
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $2 differs from $1@${REF:-worktree}"
  fi
}

# ON LINUX the installer (scripts/install-user-level-linux.sh) rewrites two things on purpose: the
# CLAUDE.md "Platform" section and the G:/git path in autoMode.environment. A correct Linux install
# therefore never matches the raw reference, and "0 drift" was unreachable there. The rewrites live
# in scripts/linux/linux-render.sh, shared with the installer; this host expects THEIR output. The
# helper and the platform file are read at the SAME reference as everything else. An older ref that
# lacks them falls back to the raw comparison, and says so. Other hosts: unchanged.
LINUX_RENDER=""
claude_expected=""
if [ "$(uname -s)" = "Linux" ]; then
  lr_helper=$(ref_copy "scripts/linux/linux-render.sh")
  lr_plat=$(ref_copy "scripts/linux/CLAUDE-platform-linux.md")
  lr_claude=$(ref_copy "user-level-reference/CLAUDE.md")
  if [ -n "$lr_helper" ] && [ -n "$lr_plat" ] && [ -n "$lr_claude" ]; then
    # The helper comes from the REF, so it is sourced in a SUBSHELL every time: it cannot
    # overwrite this script's variables or functions.
    claude_expected="$TMPD/CLAUDE.linux.md"
    if ! ( . "$lr_helper"; linux_render_claude_md "$lr_claude" "$lr_plat" ) > "$claude_expected"; then
      drift=$((drift + 1))
      drift_list="$drift_list
  LINUX RENDERING FAILED: could not render CLAUDE.md with ${REF:-the working tree}'s linux-render.sh"
    fi
    # Self-check of our own expectation (the installer runs the same function on what it writes).
    # A failing or missing check is drift, never silence.
    lr_chk=$( . "$lr_helper"; linux_check_rendered "$claude_expected" 2>&1 )
    lr_rc=$?
    if [ "$lr_rc" -ne 0 ]; then
      drift=$((drift + 1))
      drift_list="$drift_list
  LINUX RENDERING SELF-CHECK FAILED (rc=$lr_rc) for the expected CLAUDE.md: $(printf '%s' "$lr_chk" | tr '\n' ' ')"
    fi
    LINUX_RENDER=1
    echo "LINUX RENDERING: compared the Linux-rendered CLAUDE.md and autoMode.environment (the installer's rewrites), not the raw reference"
  else
    echo "LINUX RENDERING: not available at ${REF:-the working tree} (linux-render.sh or the platform file is absent there); comparing the raw reference"
  fi
fi

# (a) CLAUDE.md
check_file "user-level-reference/CLAUDE.md" "$LIVE_ROOT/CLAUDE.md" "$claude_expected"

LIVE_SETTINGS="${DRIFT_LIVE_SETTINGS:-$LIVE_ROOT/settings.json}"

LEFT_SRC=$(ref_copy "scripts/lib/v4-user-leftovers.txt")
if [ -n "$LEFT_SRC" ]; then
  # (b) cct@dagonet at REF's VERSION, read from installed_plugins.json. Observed shape (Claude Code
  # 2.1.x): {"version":2,"plugins":{"cct@dagonet":[{"scope":"user","version":"4.6.2",...}]}}.
  # Prints one "<scope> <version>" line per install record; nothing when the file cannot be read.
  plugin_records() { # <installed_plugins.json>
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' 2>/dev/null; then
      python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8-sig"))
    for r in d.get("plugins", {}).get("cct@dagonet", []):
        print("%s %s" % (r.get("scope"), r.get("version")))
except Exception:
    pass' "$1"
    elif command -v node >/dev/null 2>&1; then
      node -e '
try {
  var d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));
  ((d.plugins || {})["cct@dagonet"] || []).forEach(function (r) { console.log(r.scope + " " + r.version); });
} catch (e) {}' "$1"
    elif command -v jq >/dev/null 2>&1; then
      jq -r '(.plugins["cct@dagonet"] // [])[] | "\(.scope) \(.version)"' "$1" 2>/dev/null
    else
      echo "NO-PARSER"
    fi
  }
  # Prints "true" when settings.json has enabledPlugins["cct@dagonet"] == true; nothing otherwise
  # (a missing or unreadable file, false, absent). Same parser chain as plugin_records.
  plugin_enabled() { # <settings.json>
    [ -f "$1" ] || return 0
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import json' 2>/dev/null; then
      python3 -c '
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8-sig"))
    if d.get("enabledPlugins", {}).get("cct@dagonet") is True:
        print("true")
except Exception:
    pass' "$1"
    elif command -v node >/dev/null 2>&1; then
      node -e '
try {
  var d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8").replace(/^\uFEFF/, ""));
  if ((d.enabledPlugins || {})["cct@dagonet"] === true) console.log("true");
} catch (e) {}' "$1"
    elif command -v jq >/dev/null 2>&1; then
      jq -r 'select(.enabledPlugins["cct@dagonet"] == true) | "true"' "$1" 2>/dev/null
    fi
  }
  ver_src=$(ref_copy "VERSION")
  want_ver=$([ -n "$ver_src" ] && head -1 "$ver_src" | tr -d '\r')
  ip="$LIVE_ROOT/plugins/installed_plugins.json"
  if [ -z "$want_ver" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  CANNOT COMPARE the cct plugin: VERSION is not in ${REF:-the working tree}"
  elif [ ! -f "$ip" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  PLUGIN MISSING: $ip not found (cct@dagonet is not installed; want $want_ver)"
  else
    recs=$(plugin_records "$ip")
    if [ "$recs" = "NO-PARSER" ]; then
      drift=$((drift + 1))
      drift_list="$drift_list
  CANNOT READ $ip: no python3, node or jq"
    elif printf '%s\n' "$recs" | grep -qxF "user $want_ver"; then
      if [ "$(plugin_enabled "$LIVE_SETTINGS")" = true ]; then
        echo "PLUGIN: cct@dagonet $want_ver (user scope, enabled)"
      else
        drift=$((drift + 1))
        drift_list="$drift_list
  PLUGIN DISABLED: cct@dagonet is installed but enabledPlugins[\"cct@dagonet\"] is not true in $LIVE_SETTINGS (no toolkit agent, skill or hook loads)"
      fi
    else
      drift=$((drift + 1))
      drift_list="$drift_list
  PLUGIN DRIFT: cct@dagonet at user scope is not $want_ver in $ip (found: $(printf '%s' "${recs:-none}" | tr '\n' ',' ))"
    fi
  fi

  # (c) no v4.x user-level leftover
  n_left=0
  # A dollar-quoted CR here is refused by the gates when this script is typed
  # (v5.1.1 #14), so the CR comes from printf.
  cr=$(printf '\r')
  while IFS= read -r rel; do
    rel=${rel%"$cr"}
    [ -n "$rel" ] || continue
    n_left=$((n_left + 1))
    if [ -e "$LIVE_ROOT/$rel" ]; then
      drift=$((drift + 1))
      drift_list="$drift_list
  LEFTOVER: $LIVE_ROOT/$rel (a v4.x user-level copy; the plugin ships it now: remove it)"
    fi
  done < "$LEFT_SRC"
  if [ "$n_left" -eq 0 ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  LEFTOVER LIST IS EMPTY at ${REF:-the working tree}: cannot check for v4.x copies"
  fi

  # (d) no stale hook registration in the live HOME: REF's own hooks/verify-hooks.sh --report reads
  # ~/.claude/settings.json (a v4 registration whose script the installer moved away is MISSING there
  # and silently offline, e.g. the model-floor entry). Run it from the same reference as everything else;
  # it sources its lib/json.sh relative to itself, so the two files go to a scratch dir together.
  if [ "$MODE" = "worktree" ]; then
    vh_dir="$PWD/hooks"
  else
    vh_dir="$TMPD/vh/hooks"; mkdir -p "$TMPD/vh"
    git archive "$REF" hooks/verify-hooks.sh hooks/lib/json.sh 2>/dev/null | tar -x -C "$TMPD/vh" 2>/dev/null
  fi
  if [ ! -f "$vh_dir/verify-hooks.sh" ]; then
    drift=$((drift + 1))
    drift_list="$drift_list
  CANNOT RUN hooks/verify-hooks.sh --report: it is not in ${REF:-the working tree}"
  else
    vh_out=$(env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT HOME="$HOME" bash "$vh_dir/verify-hooks.sh" --report 2>&1)
    vh_rc=$?
    if [ "$vh_rc" -ne 0 ]; then
      drift=$((drift + 1))
      drift_list="$drift_list
  STALE HOOK REGISTRATION (verify-hooks.sh --report exit $vh_rc): $(printf '%s' "$vh_out" | tr '\n' ';')"
    fi
  fi
else
  # Pre-v5.0 ref: the file SET comes from the reference, not from the working tree.
  for sub in hooks skills agents output-styles; do
    files=""
    for d in $(sub_roots "$sub"); do
      if [ "$MODE" = "worktree" ]; then
        [ -d "$d" ] || continue
        files=$(find "$d" -type f)
      else
        files=$(git ls-tree -r --name-only "$REF" -- "$d" 2>/dev/null)
      fi
      [ -n "$files" ] && break
    done
    [ -n "$files" ] || continue
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      check_file "$f" "$LIVE_ROOT/$(live_rel "$f")"
    done <<EOF
$files
EOF
  done
fi

# ---------------------------------------------------------------------------
# autoMode.environment — THE ONE THING COMPARED INSIDE settings.json (v3.0.3,
# item 24).
#
# This is NOT the byte comparison the scope note above forbids, and settings.json
# is still NOT in the `for sub in` loop. A user's own permissions, env and MCP
# entries are theirs; `permissions.autoMode.environment` is not — it is the trust
# boundary the toolkit's own reference defines, it is USER scope (it applies to
# every repo on the machine), and drift in it is silent and expensive.
#
# Measured: a live file with 25 environment entries against the reference's 4, in
# a repo that reported "0 drift" for two releases — because nothing here looked
# at settings.json at all. The damage was a per-repo `**Trusted repo**: <path>`
# line, which made every OTHER repository read as outside the trust boundary: 58
# classifier denials across 11 sessions, 50 of them in one repo.
#
# TWO ARMS, deliberately, because either can be true without the other: the
# arrays must MATCH, and no live entry may carry the singular, path-naming
# `**Trusted repo**:` form. An array that differs for some benign reason would
# otherwise hide the specific defect, and the specific defect could arrive inside
# an otherwise-matching array.
#
# DRIFT_LIVE_SETTINGS overrides the live path. It exists so the control can be
# run against a DOCTORED COPY — never doctor the live file to test this.
# ---------------------------------------------------------------------------
automode_entries() { # <settings.json> -> permissions.autoMode.environment, one entry per line
  [ -f "$1" ] || return 0
  awk '/"environment"[[:space:]]*:[[:space:]]*\[/ { inarr = 1; next }
       inarr && /^[[:space:]]*\]/ { exit }
       inarr { sub(/^[[:space:]]+/, ""); sub(/,[[:space:]]*$/, ""); print }' "$1"
}

am_ref_src=$(ref_copy "user-level-reference/settings.json")
if [ -z "$am_ref_src" ]; then
  # Cannot determine refuses: no reference, no comparison, and silence would read
  # as agreement.
  drift=$((drift + 1))
  drift_list="$drift_list
  CANNOT COMPARE autoMode.environment: user-level-reference/settings.json is not in ${REF:-the working tree}"
elif [ ! -f "$LIVE_SETTINGS" ]; then
  drift=$((drift + 1))
  drift_list="$drift_list
  MISSING live: $LIVE_SETTINGS (autoMode.environment not comparable)"
else
  am_ref=$(automode_entries "$am_ref_src")
  [ -z "$LINUX_RENDER" ] || am_ref=$(printf '%s\n' "$am_ref" | ( . "$lr_helper"; linux_rewrite_paths ))
  am_live=$(automode_entries "$LIVE_SETTINGS")
  if [ -z "$am_ref" ]; then
    # In-band control for the extractor itself: the reference always carries
    # entries, so an empty read is a broken parser, not an empty array.
    drift=$((drift + 1))
    drift_list="$drift_list
  autoMode.environment EXTRACTOR IS INERT: read 0 entries from the reference copy of user-level-reference/settings.json"
  elif [ "$am_ref" = "$am_live" ]; then
    : # arm 1 clean
  else
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: permissions.autoMode.environment in $LIVE_SETTINGS differs from user-level-reference/settings.json@${REF:-worktree}
    reference has $(printf '%s\n' "$am_ref" | grep -c .) entry(ies), live has $(printf '%s\n' "$am_live" | grep -c .)"
  fi
  if printf '%s\n' "$am_live" | grep -q '\*\*Trusted repo\*\*:'; then
    drift=$((drift + 1))
    drift_list="$drift_list
  DRIFT: $LIVE_SETTINGS names a SINGLE repo as THE trusted repo (**Trusted repo**: ...). autoMode.environment is USER scope: that line puts every other repository on this machine outside the trust boundary. Use the reference's generic **Trusted repos** entry."
  fi
fi


if [ "$drift" -gt 0 ]; then
  echo "DRIFT DETECTED. The reference leads. Apply CHANGELOG.md -> latest 'Downstream migration' to resync."
  printf '%s\n' "$drift_list"
fi

file_drift=$((checked - in_sync))
other_drift=$((drift - file_drift))
if [ "$other_drift" -gt 0 ]; then
  echo "$checked files checked against ${REF:-working tree}, $in_sync in sync, $file_drift file drift; $other_drift other drift (plugin, leftovers, settings.json)"
else
  echo "$checked files checked against ${REF:-working tree}, $in_sync in sync, $drift drift"
fi

[ "$drift" -eq 0 ] && exit 0
exit 1
