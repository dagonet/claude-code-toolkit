#!/usr/bin/env bash
# hooks/lib/json.sh
#
# One JSON field reader for every enforcement hook.
#
# Why: until v2.2.0 the hooks parsed their stdin payload with `node -e`. Native
# Claude Code installs (and most WSL/Linux boxes that never installed a JS
# toolchain) have no `node`, so every `node -e` returned empty, every gate saw
# an empty command and exited 0 — the guards were silently inactive. Reported
# 2026-08-29 from a WSL dry run.
#
# Backends, in order: node, python3, jq. All three read the payload from STDIN
# (never argv, which has platform length caps) and print the value with no
# trailing newline.
#
# Source it from a hook:  . "$(dirname "$0")/lib/json.sh"

JSON_PARSER=""

# json_parser -- prints node | python3 | jq | none (memoised).
json_parser() {
  if [ -z "$JSON_PARSER" ]; then
    if   command -v node    >/dev/null 2>&1; then JSON_PARSER=node
    elif command -v python3 >/dev/null 2>&1; then JSON_PARSER=python3
    elif command -v jq      >/dev/null 2>&1; then JSON_PARSER=jq
    else                                          JSON_PARSER=none
    fi
  fi
  printf '%s' "$JSON_PARSER"
}

# json_have -- true when any backend is available.
json_have() { [ "$(json_parser)" != "none" ]; }

# json_get <json> <dotted.path> -- prints the scalar at that path, or "".
#
# Objects, arrays, null and missing keys all print "" — the hooks treat an
# unreadable field as absent, which is the same contract the old `node -e ||
# echo ''` calls had.
json_get() {
  case "$(json_parser)" in
    node)
      printf '%s' "$1" | node -e '
        var v; try { v = JSON.parse(require("fs").readFileSync(0, "utf8")); }
        catch (e) { process.exit(0); }
        var p = process.argv[1].split(".");
        for (var i = 0; i < p.length; i++) {
          if (v === null || typeof v !== "object") { v = undefined; break; }
          v = v[p[i]];
        }
        if (v === undefined || v === null || typeof v === "object") process.exit(0);
        process.stdout.write(String(v));
      ' "$2" 2>/dev/null
      ;;
    python3)
      printf '%s' "$1" | python3 -c '
import json, sys
try:
    v = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for k in sys.argv[1].split("."):
    if not isinstance(v, dict):
        v = None
        break
    v = v.get(k)
if v is None or isinstance(v, (dict, list)):
    sys.exit(0)
sys.stdout.write(v if isinstance(v, str) else json.dumps(v))
' "$2" 2>/dev/null
      ;;
    jq)
      printf '%s' "$1" | jq -j --arg p "$2" '
        getpath($p | split("."))
        | if . == null or type == "object" or type == "array" then ""
          elif type == "string" then .
          else tojson end
      ' 2>/dev/null
      ;;
    *) printf '' ;;
  esac
}

# json_warn_no_parser <hook-name> -- the ONE stderr line a fail-open hook prints
# when it cannot enforce anything. Never changes an exit code.
json_warn_no_parser() {
  echo "WARN: $1: no JSON parser on PATH — enforcement inactive" >&2
}

# json_require_node <hook-name> -- for the fail-open hooks whose engine is an
# embedded node program (a JSONL transcript scan, a JSON rewrite) rather than a
# field read. Returns non-zero — and warns exactly once — when node is missing,
# so the caller can `|| exit 0`.
json_require_node() {
  command -v node >/dev/null 2>&1 && return 0
  if json_have; then
    echo "WARN: $1: node not on PATH (found $(json_parser)) — enforcement inactive" >&2
  else
    json_warn_no_parser "$1"
  fi
  return 1
}
