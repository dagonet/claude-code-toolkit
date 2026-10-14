#!/usr/bin/env python3
"""jev_ctl.py -- `/cct:jev on | off | status | report` (toolkit v4.4.0, Jev Phase 1a; v5.0 plugin form).

The switch is per CLONE: <git common dir>/jev/config.json. Since v5.0 the cct
plugin registers the router itself (hooks/jev-route.sh, jev-notice.sh), active
only while that file says "route": true, so `on` writes the file and nothing
else. model-floor.sh steps aside only when the router will run
(hooks/lib/agent-model.sh am_jev_routing, ruling R-2). A v4 `/jev on` left ONE
PreToolUse(Agent) entry and a SessionStart notice in the checkout's
.claude/settings.local.json: `on` and `off` remove it. `off` writes
"route": false FIRST, then restores that file byte for byte when nobody edited
it since the v4 `on`, else removes only the Jev entries. Never prints the API key.
"""
import sys

sys.dont_write_bytecode = True

import base64  # noqa: E402
import datetime  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
from collections import Counter  # noqa: E402

import jev_route  # noqa: E402

REG_COMMAND = 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0'
MARKER = "skills/jev/jev_route.py"  # in both v4 commands: has/remove find both entries
HERE = os.path.dirname(os.path.abspath(__file__))  # the router and (in the plugin) the resolver live next to / above this file
CONFIG_ON = {"model": "jev-1.13.0", "threshold": 0.65, "route": True, "legs": False}
LEDGER_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \| ([^|]+?) \| ")
USAGE = "usage: /cct:jev on | off | status | report   (Phase 1b `on legs` is not in this release)\n"


class CtlError(Exception):
    pass


def _git(cwd, env, *args):
    """Every git call gets the caller's env (J-6), so the HOME it was given is the one git reads."""
    try:
        cp = subprocess.run(["git", "-C", cwd] + list(args), capture_output=True, timeout=10, env=env)
    except (OSError, subprocess.SubprocessError):
        return None
    return cp.stdout.decode("utf-8", "replace").strip() if cp.returncode == 0 else None


def locate(cwd, env=None):
    """-> (checkout top level, absolute git common dir)."""
    top = _git(cwd, env, "rev-parse", "--show-toplevel")
    gd = _git(cwd, env, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if not top or not gd:
        raise CtlError("not inside a git checkout -- /cct:jev is switched per clone")
    return top, gd


def _home(env):
    return env.get("HOME") or os.path.expanduser("~")


def _read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read()
    except FileNotFoundError:
        return None


def _write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _dumps(obj):
    return (json.dumps(obj, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def resolver_lib(env, top):
    """The resolver the router would run: jev_route's own candidate list, so status and routing agree."""
    for cand in jev_route.resolver_candidates(top, _home(env)):
        if os.path.isfile(cand):
            return cand
    return None


def _active_model_floor(env, top):
    """The model-floor.sh a spawn here runs: the project's copy wins (S-24)."""
    for cand in (os.path.join(top, "hooks", "model-floor.sh"),
                 os.path.join(_home(env), ".claude", "hooks", "model-floor.sh")):
        if os.path.isfile(cand):
            return cand
    return None


def parse_settings(data):
    if data is None or not data.strip():
        return {}
    try:
        obj = json.loads(data.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        raise CtlError(".claude/settings.local.json is not valid JSON -- fix it by hand first")
    if not isinstance(obj, dict):
        raise CtlError(".claude/settings.local.json is not a JSON object -- fix it by hand first")
    return obj


def _is_jev(hook):
    return isinstance(hook, dict) and MARKER in str(hook.get("command", ""))


JEV_EVENTS = ("PreToolUse", "SessionStart")  # the router and the U-1 notice


def _groups(obj, event):
    hooks = obj.get("hooks")
    groups = hooks.get(event) if isinstance(hooks, dict) else None
    return groups if isinstance(groups, list) else []


def has_entry(obj):
    """The v4 ROUTER registration is present (PreToolUse)."""
    return any(isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(_is_jev(h) for h in g["hooks"])
               for g in _groups(obj, "PreToolUse"))


def remove_entry(obj):
    """Remove every Jev hook from both events, and any group or event left empty by that."""
    new = json.loads(json.dumps(obj))
    hooks = new.get("hooks")
    if not isinstance(hooks, dict):
        return new
    for event in JEV_EVENTS:
        if not isinstance(hooks.get(event), list):
            continue
        kept = []
        for g in hooks[event]:
            if isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(_is_jev(h) for h in g["hooks"]):
                rest = [h for h in g["hooks"] if not _is_jev(h)]
                if not rest:
                    continue
                g = dict(g, hooks=rest)
            kept.append(g)
        if kept:
            hooks[event] = kept
        else:
            del hooks[event]
    if not hooks:
        del new["hooks"]
    return new


def _snapshot_path(gd, top):
    return os.path.join(gd, "jev", "snapshots", hashlib.sha256(top.encode("utf-8")).hexdigest()[:16] + ".json")


def _config_path(gd):
    return os.path.join(gd, "jev", "config.json")


def _read_config(gd):
    try:
        cfg = json.loads((_read(_config_path(gd)) or b"").decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        return None
    return cfg if isinstance(cfg, dict) else None


def _key_source(env, registry):
    if (env.get("TYPESAFE_API_KEY") or "").strip():
        return "environment"
    if ((registry or jev_route._winreg_key)() or "").strip():
        return "HKCU\\Environment"
    return None


def _drop_v4_registration(top, gd, out):
    """Remove what a v4 `/jev on` left in this checkout's settings.local.json: restore the bytes from before it
    when nobody edited the file since, else remove only the Jev entries. Nothing there -> nothing happens."""
    path = os.path.join(top, ".claude", "settings.local.json")
    snap_path = _snapshot_path(gd, top)
    snap = None
    raw = _read(snap_path)
    if raw:
        try:
            snap = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            snap = None
    cur = _read(path)
    if cur is not None:
        obj = parse_settings(cur)
        if isinstance(snap, dict) and obj == snap.get("after"):
            if snap.get("existed"):
                _write(path, base64.b64decode(snap.get("before_b64", "")))
            else:
                os.remove(path)
            out.write("jev: .claude/settings.local.json restored to its state before the v4 /jev on\n")
        elif remove_entry(obj) != obj:
            _write(path, _dumps(remove_entry(obj)))
            out.write("jev: .claude/settings.local.json held a v4 Jev registration -- removed only the Jev entry "
                      "(the file was re-serialised)\n")
    if os.path.exists(snap_path):
        os.remove(snap_path)


def cmd_on(top, gd, env, out, key_src):
    if not os.path.isfile(os.path.join(HERE, "jev_route.py")):
        raise CtlError("jev_route.py is not installed next to jev_ctl.py ({}) -- reinstall the cct plugin "
                       "(claude plugin uninstall cct@dagonet, then claude plugin install cct@dagonet); "
                       "nothing was changed".format(HERE))
    if not resolver_lib(env, top):
        raise CtlError("no hooks/lib/agent-model.sh in the cct plugin, this project or a v4 leftover ~/.claude/hooks/lib/ -- the "
                       "router reuses model-floor's resolution and cannot run without it; nothing was changed")
    mf = _active_model_floor(env, top)
    if mf and b"agent-model.sh" not in (_read(mf) or b""):
        raise CtlError("{} predates v4.4.0 (it steps aside on the switch alone, so a sibling worktree would lose "
                       "the floor) -- update it first (/cct:sync-template for a project copy; for a v4 leftover in ~/.claude/hooks/ "
                       "run bash scripts/install-user-level-linux.sh on Linux, or see docs/plugin-migration-windows.md on the PC); "
                       "nothing was changed".format(mf))
    parse_settings(_read(os.path.join(top, ".claude", "settings.local.json")))  # unreadable -> refuse before any write
    _write(_config_path(gd), _dumps(CONFIG_ON))
    _drop_v4_registration(top, gd, out)
    out.write("jev: ON for this clone -- spawns that pass no `model` are routed (any model, at confidence >= the "
              "threshold; review/architect types never below sonnet, effort never lowered; effort too); the cct plugin registers the router, "
              "other checkouts of this clone need no /cct:jev on; /cct:jev off switches it off\n")
    # U-1: the orchestrator must stop naming a model, or Jev routes nothing.
    out.write("jev: ORCHESTRATOR -- from now on in this repo, omit `model` on Agent spawns: Jev picks one per "
              "launch (user ruling U-1; an explicit model is never changed). New sessions are told by the "
              "session-start notice.\n")
    if not key_src:
        out.write("jev: note -- no TYPESAFE_API_KEY: spawns get the project floor until one is set\n")
    return 0


def cmd_off(top, gd, env, out, key_src):
    cfg = _read_config(gd) or dict(CONFIG_ON)
    cfg["route"] = False
    _write(_config_path(gd), _dumps(cfg))  # FIRST: model-floor floors again whatever happens below
    _drop_v4_registration(top, gd, out)
    out.write("jev: OFF for this clone -- model-floor applies the project default again; events stay in "
              "<git common dir>/jev/events/\n")
    out.write("jev: ORCHESTRATOR -- name `model` on every Agent spawn again (the user-level rule; U-1 "
              "applied only while Jev was on)\n")
    return 0


def _events(gd):
    d = os.path.join(gd, "jev", "events")
    evs = []
    for name in sorted(os.listdir(d)) if os.path.isdir(d) else []:
        try:
            ev = json.loads(_read(os.path.join(d, name)).decode("utf-8"))
        except (AttributeError, OSError, UnicodeDecodeError, ValueError):
            continue
        if isinstance(ev, dict):
            evs.append(ev)
    return evs


def cmd_status(top, gd, env, out, key_src):
    cfg = _read_config(gd)
    route = bool(cfg and cfg.get("route") is True)
    out.write("jev: switch (this clone): {}\n".format("on" if route else "off"))
    if cfg:
        out.write("jev: config: model {} threshold {} legs {}\n".format(cfg.get("model"), cfg.get("threshold"), cfg.get("legs")))
    try:
        registered = has_entry(parse_settings(_read(os.path.join(top, ".claude", "settings.local.json"))))
    except CtlError:
        registered = False
    installed = os.path.isfile(os.path.join(HERE, "jev_route.py"))
    lib = resolver_lib(env, top)
    src = key_src
    out.write("jev: v4 registration left in this checkout (run /cct:jev off): {}\n".format("yes" if registered else "no"))
    out.write("jev: router installed (next to jev_ctl.py): {}\n".format("yes" if installed else "no"))
    out.write("jev: resolver: {}\n".format(lib or "MISSING"))
    out.write("jev: TYPESAFE_API_KEY: {}\n".format("set ({})".format(src) if src else "not set"))
    evs = _events(gd)
    if evs:
        e = evs[-1]
        out.write("jev: last event: {} {} {} applied={}\n".format(e.get("ts"), e.get("subagent_type"), e.get("reason"), e.get("applied")))
    else:
        out.write("jev: last event: none\n")
    out.write("jev: routing spawns in this checkout: {}\n".format("yes" if _routing_live(env, top, lib) else "no"))
    return 0


def _routing_live(env, top, lib):
    """J-9: field 3 of the resolver's CLI line (kind model jev effort gd), never a re-derivation."""
    if not lib:
        return False
    try:
        # a bare "bash" resolves to System32's WSL launcher on Windows; use the PATH's (Git) bash like jev_route does
        bash = shutil.which("bash", path=env.get("PATH")) or "bash"
        cp = subprocess.run([bash, lib, "general-purpose", top], capture_output=True, timeout=20, env=env)
    except (OSError, subprocess.SubprocessError):
        return False
    fields = cp.stdout.decode("utf-8", "replace").split()
    return len(fields) >= 3 and fields[2] == "1"


def ledger_slug(top):
    """Claude Code's auto-memory directory name (hooks/retro-ledger.sh): each of : \\ / . _ -> '-'."""
    return re.sub(r"[:\\/._]", "-", top)


def _local(ts):
    return datetime.datetime.fromisoformat(ts.replace("Z", "+00:00")).astimezone().replace(tzinfo=None)


def _ledger_rows(env, top):
    path = os.path.join(_home(env), ".claude", "projects", ledger_slug(top), "memory", "retro.md")
    rows = []
    for line in (_read(path) or b"").decode("utf-8", "replace").splitlines():
        m = LEDGER_RE.match(line)
        if m:
            rows.append((datetime.datetime.strptime(m.group(1), "%Y-%m-%d %H:%M"), m.group(2).strip(), line))
    return rows


def _idx(model):
    return jev_route.ORDER.index(model) if model in jev_route.ORDER else -1


def cmd_report(top, gd, env, out, key_src):
    evs = _events(gd)
    out.write("jev report: {} spawns seen\n".format(len(evs)))
    if not evs:
        return 0
    applied = [e for e in evs if e.get("applied") is True]
    up = sum(1 for e in applied if _idx(e.get("emitted")) > _idx(jev_route.family(e.get("default") or "")))
    out.write("  applied: {} (up {}, down {})\n".format(len(applied), up, len(applied) - up))
    reasons = Counter(str(e.get("reason")) for e in evs if e.get("applied") is not True)
    out.write("  not applied: {}\n".format(", ".join("{} {}".format(r, n) for r, n in sorted(reasons.items())) or "none"))
    confs = [e["confidence"] for e in evs
             if isinstance(e.get("confidence"), (int, float)) and not isinstance(e.get("confidence"), bool)]
    out.write("  model confidence: <0.5: {}, 0.5-0.8: {}, >=0.8: {}\n".format(
        sum(c < 0.5 for c in confs), sum(0.5 <= c < 0.8 for c in confs), sum(c >= 0.8 for c in confs)))
    out.write("  effort applied: {} of {}\n".format(sum(1 for e in evs if e.get("effort_emitted")), len(evs)))
    eff = [e for e in evs if e.get("agent_effort") and e.get("effort_choice")]
    out.write("  effort recommendation differs from the agent file's effort: {} of {}\n".format(
        sum(e["agent_effort"] != e["effort_choice"] for e in eff), len(eff)))
    rows, hits = _ledger_rows(env, top), []
    for e in applied:
        try:
            t = _local(e["ts"]).replace(second=0, microsecond=0)
        except (KeyError, TypeError, ValueError):
            continue
        for when, atype, line in rows:
            if atype == e.get("subagent_type") and datetime.timedelta(0) <= when - t <= datetime.timedelta(minutes=60):
                hits.append((e, line))
    out.write("  retro-ledger failure rows within 60 min after a routed spawn of the same type: {} "
              "(hook blocks and dead tools -- not the agent's report status)\n".format(len(hits)))
    for e, line in hits:
        out.write("    {} {} -> {}: {}\n".format(e.get("ts"), e.get("subagent_type"), e.get("emitted"), line))
    return 0


def main(argv=None, cwd=None, env=None, out=None, registry=None):
    argv = sys.argv[1:] if argv is None else argv
    env = dict(os.environ) if env is None else env
    out = out or sys.stdout
    cmd = (argv[0] if argv else "status").strip().lower()
    handlers = {"on": cmd_on, "off": cmd_off, "status": cmd_status, "report": cmd_report}
    if cmd not in handlers or len(argv) > 1:
        out.write(USAGE)
        return 2
    key_src = _key_source(env, registry)
    env = {k: v for k, v in env.items() if k != "TYPESAFE_API_KEY"}  # MH-1: no subprocess needs the key
    try:
        top, gd = locate(cwd or os.getcwd(), env)
        return handlers[cmd](top, gd, env, out, key_src)
    except (CtlError, OSError) as exc:
        out.write("jev: error: {}\n".format(exc))
        return 1


if __name__ == "__main__":
    sys.exit(main())
