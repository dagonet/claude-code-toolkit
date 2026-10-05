#!/usr/bin/env bash
# scripts/render-user-hooks.sh -- v4.4.0 C1: render the user-level `hooks` block.
#
# user-level-reference/settings.json registers the user-level hooks in EXEC form
# (`command` + `args`, no shell between Claude Code and bash) and spells the two
# machine-specific parts as placeholders: `@BASH@` (the bash program) and
# `@HOOKS@` (the hooks directory). Exec form does not expand `~` or `$HOME` and
# resolves a bare `bash` through PATH, which on Windows can reach the WSL
# launcher (System32\bash.exe) and fail OPEN for every protection. So the
# program and the paths are written ABSOLUTE, once per machine, by this script.
# DO NOT copy the reference's `hooks` block by hand: `@BASH@` would be spawned
# as a program and every user protection would fail open.
#
#   bash scripts/render-user-hooks.sh [--print | --write | --list] [--settings <path>]
#
#   --print   (default) the rendered `hooks` object on stdout.
#   --write   replace ONLY the top-level `hooks` key of the settings file (default
#             $HOME/.claude/settings.json). Backs the live file up first to
#             settings.json.bak-<UTC yyyymmddThhmmssZ> (restore it to back out),
#             keeps hooks this toolkit does not own (merged by event + matcher,
#             appended after the toolkit's, each printed as `kept foreign hook:
#             <command>`), refuses a live file that does not parse, and re-reads
#             the result to check that every rendered script path exists.
#             Idempotent: a second run changes nothing and makes no backup. Keeps the
#             file mode, writes through a symlinked settings.json to its target, and
#             (like --print) refuses, exit 1, if the output still holds an @NAME@
#             placeholder. A reference copied verbatim is recognised and replaced.
#   --list    one line per rendered entry: event, matcher ('-' = none), command,
#             args... (TAB separated). Used by the fixtures.
#
# BASH_EXE: on Windows (Git Bash / MSYS / Cygwin) `cygpath -m /usr/bin/bash`, and
# NEVER Git's bin\bash.exe (a launcher that starts usr\bin\bash.exe as a second
# process). Elsewhere `command -v bash`, made absolute. Refuses (exit 1) a path
# that does not exist or ends in System32/bash.exe (the WSL stub).
# Test hooks: RUH_TEST_BASH=<path> stands in for the detected path, RUH_TEST_OSTYPE
# for $OSTYPE, RUH_BACKEND="node python3 jq" restricts the parser chain.
# JSON handling: node -> python3 -> jq, the order hooks/lib/json.sh uses; with none
# working the script refuses.

die() { echo "render-user-hooks: $*" >&2; exit 1; }

MODE=print; SETTINGS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --print) MODE=print ;;
    --write) MODE=write ;;
    --list)  MODE=list ;;
    --settings) [ $# -ge 2 ] || die "--settings needs a path"; SETTINGS=$2; shift ;;
    -h|--help) sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

[ -n "${HOME:-}" ] || die "HOME is not set"
[ -n "$SETTINGS" ] || SETTINGS="$HOME/.claude/settings.json"
TOOLKIT=$(cd "$(dirname "$0")/.." && pwd) || die "cannot resolve the toolkit root"
REF="$TOOLKIT/user-level-reference/settings.json"
[ -r "$REF" ] || die "cannot read $REF"

# ---- BASH_EXE and HOOKS_DIR ----------------------------------------------
OS_T=${RUH_TEST_OSTYPE:-${OSTYPE:-}}
IS_WIN=""
case "$OS_T" in msys*|cygwin*|mingw*|MINGW*|MSYS*|CYGWIN*|win32*) IS_WIN=1 ;; esac
if [ -n "${RUH_TEST_BASH:-}" ]; then
  BASH_EXE=$RUH_TEST_BASH
elif [ -n "$IS_WIN" ]; then
  command -v cygpath >/dev/null 2>&1 || die "cygpath not found: cannot resolve Git's usr/bin/bash"
  BASH_EXE=$(cygpath -m /usr/bin/bash) || die "cygpath failed"
else
  BASH_EXE=$(command -v bash) || die "bash not found on PATH"
  case "$BASH_EXE" in
    /*) ;;
    */*) BASH_EXE=$PWD/$BASH_EXE ;;
    *) die "bash resolves to '$BASH_EXE', not a file path (alias or function?)" ;;
  esac
fi
# cygpath -m /usr/bin/bash has no .exe: spell it (Windows hosts only)
if [ -n "$IS_WIN" ]; then case "$BASH_EXE" in *.exe|*.EXE) ;; *) BASH_EXE=$BASH_EXE.exe ;; esac; fi
RUH_LC=$(printf '%s' "$BASH_EXE" | tr 'A-Z\\' 'a-z/')
case "$RUH_LC" in
  */system32/bash.exe) die "refusing $BASH_EXE: System32/bash.exe is the WSL launcher; a WSL bash fails open for every protection" ;;
  */usr/bin/bash.exe) ;;
  */git/bin/bash.exe) die "refusing $BASH_EXE: Git's bin/bash.exe is a launcher that starts usr/bin/bash.exe as a second process; use usr/bin/bash.exe" ;;
esac
[ -f "$BASH_EXE" ] || die "bash program does not exist: $BASH_EXE"
HOOKS_DIR=$HOME/.claude/hooks
[ -n "$IS_WIN" ] && [ -z "${RUH_TEST_BASH:-}" ] && HOOKS_DIR=$(cygpath -m "$HOOKS_DIR")

# ---- the parser chain (json.sh's order, probed the same way) ---------------
# shellcheck source=../hooks/lib/json.sh
. "$TOOLKIT/hooks/lib/json.sh"
BACKEND=""
for _b in ${RUH_BACKEND:-node python3 jq}; do
  command -v "$_b" >/dev/null 2>&1 || continue
  json_probe_ok "$_b" || continue
  BACKEND=$_b; break
done
[ -n "$BACKEND" ] || die "no working JSON parser (node, python3 or jq) found: refusing"

WORK=$(mktemp -d 2>/dev/null || mktemp -d -t ruh) || die "mktemp failed"
TMPF=""
trap 'rm -rf "$WORK"; [ -z "$TMPF" ] || rm -f "$TMPF"' EXIT

# natpath <path>: the spelling a native Windows interpreter can open
natpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }

# ---- the three programs: same contract, one per backend --------------------
# prog <mode> <ref file> <live file>; modes: print | merge | foreign | list-ref | list-live
# Substitutes @BASH@/@HOOKS@ (JSON-aware: values are escaped by the serializer).
# A hook entry is the toolkit's when its text names /.claude/hooks/<name>.sh OR the
# unrendered @HOOKS@/<name>.sh (a hand-copied reference) for a <name> the reference
# registers, or equals a reference entry on that event (the inline date hook);
# everything else is foreign and kept.
PROG_NODE='
var fs = require("fs");
var mode = process.argv[1], refp = process.argv[2], livep = process.argv[3];
var B = process.env.RUH_B, H = process.env.RUH_H;
function fail(e) { process.stderr.write("render-user-hooks: " + (e && e.message ? e.message : e) + "\n"); process.exit(1); }
function rd(p) { var t = fs.readFileSync(p, "utf8"); if (t.charCodeAt(0) === 0xFEFF) t = t.slice(1); return JSON.parse(t); }
function sub(v) {
  if (typeof v === "string") return v.split("@BASH@").join(B).split("@HOOKS@").join(H);
  if (Array.isArray(v)) return v.map(sub);
  if (v && typeof v === "object") { var o = {}; Object.keys(v).forEach(function (k) { o[k] = sub(v[k]); }); return o; }
  return v;
}
function argv(h) { return Array.isArray(h.args) ? h.args.map(String) : []; }
function disp(h) { return [h.command === undefined || h.command === null ? "" : String(h.command)].concat(argv(h)).join(" "); }
function arr(x, what) { if (x === undefined || x === null) return []; if (!Array.isArray(x)) throw new Error(what + " is not an array"); return x; }
function lst(hs) {
  var out = [];
  Object.keys(hs).forEach(function (ev) {
    arr(hs[ev], "hooks." + ev).forEach(function (g) {
      arr(g.hooks, "hooks." + ev + " group").forEach(function (h) {
        out.push([ev, (g.matcher === undefined || g.matcher === null || g.matcher === "") ? "-" : g.matcher, h.command === undefined || h.command === null ? "" : String(h.command)].concat(argv(h)).join("\t"));
      });
    });
  });
  return out.length ? out.join("\n") + "\n" : "";
}
(function () { try {
  var ref = sub(rd(refp).hooks);
  if (mode === "print") { process.stdout.write(JSON.stringify(ref, null, 2) + "\n"); return; }
  if (mode === "list-ref") { process.stdout.write(lst(ref)); return; }
  var live = rd(livep);
  if (live === null || typeof live !== "object" || Array.isArray(live)) throw new Error("the live settings file is not a JSON object");
  if (mode === "list-live") { process.stdout.write(lst(live.hooks || {})); return; }
  var names = [], refd = {};
  Object.keys(ref).forEach(function (ev) {
    refd[ev] = [];
    ref[ev].forEach(function (g) { g.hooks.forEach(function (h) {
      refd[ev].push(disp(h));
      var a = argv(h), m = /\/([A-Za-z0-9_-]+)\.sh$/.exec(a.length ? a[a.length - 1] : "");
      if (m && names.indexOf(m[1]) < 0) names.push(m[1]);
    }); });
  });
  var own = new RegExp("(/\\.claude/hooks|@HOOKS@)/(" + names.join("|") + ")\\.sh([^A-Za-z0-9_.-]|$)");
  function isown(ev, h) { var d = disp(h); return (refd[ev] || []).indexOf(d) >= 0 || own.test(d); }
  var lh = live.hooks === undefined || live.hooks === null ? {} : live.hooks;
  if (typeof lh !== "object" || Array.isArray(lh)) throw new Error("hooks is not an object");
  var out = {}, foreign = [];
  Object.keys(ref).forEach(function (ev) {
    var groups = JSON.parse(JSON.stringify(ref[ev]));
    arr(lh[ev], "hooks." + ev).forEach(function (g) {
      var keep = arr(g.hooks, "hooks." + ev + " group").filter(function (h) { return !isown(ev, h); });
      if (!keep.length) return;
      keep.forEach(function (h) { foreign.push(disp(h)); });
      var t = null;
      groups.forEach(function (x) { if (t === null && x.matcher === g.matcher) t = x; });
      if (t) t.hooks = t.hooks.concat(keep);
      else { var c = {}; Object.keys(g).forEach(function (k) { c[k] = g[k]; }); c.hooks = keep; groups.push(c); }
    });
    out[ev] = groups;
  });
  Object.keys(lh).forEach(function (ev) {
    if (Object.prototype.hasOwnProperty.call(ref, ev)) return;
    out[ev] = lh[ev];
    arr(lh[ev], "hooks." + ev).forEach(function (g) { arr(g.hooks, "hooks." + ev + " group").forEach(function (h) { foreign.push(disp(h)); }); });
  });
  if (mode === "foreign") { process.stdout.write(foreign.length ? foreign.join("\n") + "\n" : ""); return; }
  live.hooks = out;
  process.stdout.write(JSON.stringify(live, null, 2) + "\n");
} catch (e) { fail(e); } })();
'

PROG_PY='
import json, os, re, sys
mode, refp, livep = sys.argv[1], sys.argv[2], sys.argv[3]
B, H = os.environ["RUH_B"], os.environ["RUH_H"]
def fail(e):
    sys.stderr.write("render-user-hooks: %s\n" % e); sys.exit(1)
def rd(p):
    with open(p, "rb") as f: return json.loads(f.read().decode("utf-8-sig"))
def sub(v):
    if isinstance(v, str): return v.replace("@BASH@", B).replace("@HOOKS@", H)
    if isinstance(v, list): return [sub(x) for x in v]
    if isinstance(v, dict): return dict((k, sub(x)) for k, x in v.items())
    return v
def argv(h): return [str(a) for a in h["args"]] if isinstance(h.get("args"), list) else []
def disp(h):
    c = h.get("command")
    return " ".join([("" if c is None else str(c))] + argv(h))
def arr(x, what):
    if x is None: return []
    if not isinstance(x, list): raise Exception("%s is not an array" % what)
    return x
def lst(hs):
    out = []
    for ev, gs in hs.items():
        for g in arr(gs, "hooks." + ev):
            for h in arr(g.get("hooks"), "hooks." + ev + " group"):
                c = h.get("command")
                m = g.get("matcher")
                out.append("\t".join([ev, "-" if m in (None, "") else m, "" if c is None else str(c)] + argv(h)))
    return "".join(l + "\n" for l in out)
def emit(t): sys.stdout.buffer.write(t.encode("utf-8"))
def dump(v): return json.dumps(v, indent=2, ensure_ascii=False) + "\n"
try:
    ref = sub(rd(refp)["hooks"])
    if mode == "print": emit(dump(ref)); sys.exit(0)
    if mode == "list-ref": emit(lst(ref)); sys.exit(0)
    live = rd(livep)
    if not isinstance(live, dict): raise Exception("the live settings file is not a JSON object")
    if mode == "list-live": emit(lst(live.get("hooks") or {})); sys.exit(0)
    names = []; refd = {}
    for ev, gs in ref.items():
        refd[ev] = []
        for g in gs:
            for h in g["hooks"]:
                refd[ev].append(disp(h))
                a = argv(h)
                m = re.search(r"/([A-Za-z0-9_-]+)\.sh$", a[-1] if a else "")
                if m and m.group(1) not in names: names.append(m.group(1))
    own = re.compile(r"(/\.claude/hooks|@HOOKS@)/(" + "|".join(re.escape(n) for n in names) + r")\.sh([^A-Za-z0-9_.-]|$)")
    def isown(ev, h):
        d = disp(h)
        return d in refd.get(ev, []) or own.search(d) is not None
    lh = live.get("hooks")
    if lh is None: lh = {}
    if not isinstance(lh, dict): raise Exception("hooks is not an object")
    out = {}; foreign = []
    for ev in ref:
        groups = json.loads(json.dumps(ref[ev]))
        for g in arr(lh.get(ev), "hooks." + ev):
            keep = [h for h in arr(g.get("hooks"), "hooks." + ev + " group") if not isown(ev, h)]
            if not keep: continue
            foreign += [disp(h) for h in keep]
            t = None
            for x in groups:
                if t is None and x.get("matcher") == g.get("matcher"): t = x
            if t is not None: t["hooks"] = t["hooks"] + keep
            else:
                c = dict(g); c["hooks"] = keep; groups.append(c)
        out[ev] = groups
    for ev in lh:
        if ev in ref: continue
        out[ev] = lh[ev]
        for g in arr(lh[ev], "hooks." + ev):
            for h in arr(g.get("hooks"), "hooks." + ev + " group"): foreign.append(disp(h))
    if mode == "foreign": emit("".join(l + "\n" for l in foreign)); sys.exit(0)
    live["hooks"] = out
    emit(dump(live))
except SystemExit: raise
except Exception as e: fail(e)
'

PROG_JQ='
def subst: walk(if type == "string" then (split("@BASH@") | join($B) | split("@HOOKS@") | join($H)) else . end);
def disp: ([(.command // "") | tostring] + ((.args // []) | map(tostring)) | join(" "));
def arr($what): if . == null then [] elif type == "array" then . else error($what + " is not an array") end;
def lst: to_entries[] | .key as $ev | (.value | arr("hooks." + $ev))[] | . as $g
  | ($g.hooks | arr("hooks." + $ev + " group"))[]
  | ([$ev, (if ($g.matcher // "") == "" then "-" else $g.matcher end), ((.command // "") | tostring)] + ((.args // []) | map(tostring))) | join("\t");
($r[0].hooks | subst) as $ref
| if $mode == "print" then $ref
  elif $mode == "list-ref" then ($ref | lst)
  else
    (if ($l | length) != 1 then error("the live settings file must hold exactly one JSON document") else $l[0] end) as $live
    | (if ($live | type) != "object" then error("the live settings file is not a JSON object") else . end)
    | if $mode == "list-live" then ($live.hooks // {} | lst)
      else
        ($ref | map_values([.[].hooks[] | disp])) as $refd
        | ([$ref[][].hooks[] | (.args // []) | select(length > 0) | .[-1] | tostring | capture("/(?<n>[A-Za-z0-9_-]+)\\.sh$")? | .n] | unique) as $names
        | ("(/\\.claude/hooks|@HOOKS@)/(" + ($names | join("|")) + ")\\.sh([^A-Za-z0-9_.-]|$)") as $own
        | ($live.hooks // {}) as $lh
        | (if ($lh | type) != "object" then error("hooks is not an object") else . end)
        | def isown($ev): disp as $d | ((($refd[$ev] // []) | index($d)) != null) or ($d | test($own));
          def mergeev($ev):
            reduce (($lh[$ev]) | arr("hooks." + $ev))[] as $g ($ref[$ev];
              ($g.hooks | arr("hooks." + $ev + " group") | map(select(isown($ev) | not))) as $keep
              | if ($keep | length) == 0 then .
                else ((to_entries | map(select(.value.matcher == $g.matcher)) | .[0].key) as $i
                      | if $i != null then .[$i].hooks += $keep else . + [$g | .hooks = $keep] end) end);
          if $mode == "foreign" then
            ($lh | to_entries[]) as $e
            | ($e.value | arr("hooks." + $e.key))[] | (.hooks | arr("group"))[]
            | select((($ref | has($e.key)) | not) or (isown($e.key) | not)) | disp
          else
            $live | .hooks = ((reduce ($ref | keys_unsorted[]) as $ev ({}; .[$ev] = mergeev($ev)))
                              + ($lh | with_entries(select(.key as $k | ($ref | has($k)) | not))))
          end
      end
  end
'

# prog <mode> <ref file> <live file> -> stdout
prog() {
  case "$BACKEND" in
    node) RUH_B=$BASH_EXE RUH_H=$HOOKS_DIR node -e "$PROG_NODE" "$1" "$(natpath "$2")" "$(natpath "$3")" ;;
    python3) RUH_B=$BASH_EXE RUH_H=$HOOKS_DIR python3 -c "$PROG_PY" "$1" "$(natpath "$2")" "$(natpath "$3")" ;;
    jq)
      _jo=-r; [ "$1" = print ] || [ "$1" = merge ] && _jo=
      jq -n $_jo --arg mode "$1" --arg B "$BASH_EXE" --arg H "$HOOKS_DIR" \
        --slurpfile r "$2" --slurpfile l "$3" "$PROG_JQ" ;;
  esac
}

# noph <file>: fails when the file still carries an @NAME@ placeholder (a copied, unrendered entry)
noph() { ! grep -Eq '@[A-Z]+@' "$1"; }

EMPTY=$WORK/empty.json
printf '{}\n' > "$EMPTY"

case "$MODE" in
  print)
    prog print "$REF" "$EMPTY" > "$WORK/print.json" || exit 1
    noph "$WORK/print.json" || die "refusing to print: the output still contains an unsubstituted @NAME@ placeholder"
    cat "$WORK/print.json" ;;
  list)  prog list-ref "$REF" "$EMPTY" || exit 1 ;;
  write)
    # a symlinked settings.json: write its resolved target, never replace the link
    if [ -L "$SETTINGS" ]; then
      _t=$(readlink -f "$SETTINGS" 2>/dev/null) && [ -n "$_t" ] && [ -f "$_t" ] || die "$SETTINGS is a symlink that cannot be resolved to a regular file: nothing was changed"
      SETTINGS=$_t
    fi
    LIVE=$EMPTY
    [ -f "$SETTINGS" ] && LIVE=$SETTINGS
    prog merge "$REF" "$LIVE" > "$WORK/new.json" || die "refusing to write: $SETTINGS could not be merged (does it parse as JSON?). Nothing was changed."
    prog foreign "$REF" "$LIVE" > "$WORK/foreign.txt" || die "refusing to write: $SETTINGS could not be merged. Nothing was changed."
    noph "$WORK/new.json" || die "refusing to write: the result still contains an unsubstituted @NAME@ placeholder (a foreign entry carries one?). Nothing was changed."
    while IFS= read -r _l; do echo "kept foreign hook: $_l"; done < "$WORK/foreign.txt"
    if [ -f "$SETTINGS" ] && cmp -s "$WORK/new.json" "$SETTINGS"; then
      echo "render-user-hooks: $SETTINGS already carries the rendered hooks (no change, no backup)"
    else
      mkdir -p "$(dirname "$SETTINGS")" || die "cannot create $(dirname "$SETTINGS")"
      if [ -f "$SETTINGS" ]; then
        BAK="$SETTINGS.bak-$(date -u +%Y%m%dT%H%M%SZ)"
        [ -e "$BAK" ] && BAK=$BAK.$$
        [ -e "$BAK" ] && die "backup $BAK already exists: nothing was changed"
        cp -p "$SETTINGS" "$BAK" || die "cannot back up $SETTINGS: nothing was changed"
        echo "render-user-hooks: backup $BAK"
      fi
      TMPF="$SETTINGS.tmp.$$"
      if [ -f "$SETTINGS" ]; then cp -p "$SETTINGS" "$TMPF" || die "cannot write $SETTINGS"; fi   # keeps the file mode
      cat "$WORK/new.json" > "$TMPF" && mv -f "$TMPF" "$SETTINGS" || die "cannot write $SETTINGS"
      echo "render-user-hooks: wrote the hooks block of $SETTINGS"
    fi
    # re-read: every rendered script path must exist
    BAD=0
    prog list-live "$REF" "$SETTINGS" > "$WORK/live.tsv" || die "the written $SETTINGS does not re-read: restore the .bak"
    while IFS=$'\t' read -r _ev _m _cmd _a1 _a2 _a3 _rest; do
      case "$_a3" in
        "$HOOKS_DIR"/*) [ -f "$_a3" ] || { echo "render-user-hooks: MISSING script $_a3 (registered for $_ev); copy user-level-reference/hooks to $HOOKS_DIR" >&2; BAD=1; } ;;
      esac
    done < "$WORK/live.tsv"
    [ "$BAD" = 0 ] || exit 1
    ;;
esac
exit 0
