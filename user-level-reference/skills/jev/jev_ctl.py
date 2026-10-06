#!/usr/bin/env python3
"""jev_ctl.py -- `/jev on | off | status | report` (toolkit v4.4.0, Jev Phase 1a).

The switch is per CLONE: <git common dir>/jev/config.json. The router is
registered per CHECKOUT: ONE PreToolUse(Agent) entry in this checkout's
.claude/settings.local.json. model-floor.sh steps aside only when both are in
place and the router is installed (hooks/lib/agent-model.sh am_jev_routing,
ruling R-2), so a half-on state floors instead of inheriting the orchestrator's
model. `off` writes "route": false FIRST, then restores settings.local.json
byte for byte when nobody edited it since `on`, else removes only the Jev
entry. Never prints the API key.
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
# U-1: SessionStart stdout reaches the new session's context -- the only way a
# new session learns the switch is on. No backticks: they would substitute in bash.
SESSION_COMMAND = 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && echo "Jev routing is ON in this repo (/jev on): omit model on Agent spawns -- Jev picks one per launch (user ruling U-1; an explicit model is never changed). /jev off restores naming it."; exit 0'
MARKER = "skills/jev/jev_route.py"  # in both commands: has/remove find both entries
CONFIG_ON = {"model": "jev-1.13.0", "threshold": 0.8, "route": True, "legs": False}
EXCLUDE_LINE = ".claude/settings.local.json"
LEDGER_RE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}) \| ([^|]+?) \| ")
USAGE = "usage: /jev on | off | status | report   (Phase 1b `on legs` is not in this release)\n"


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
        raise CtlError("not inside a git checkout -- /jev is switched per clone")
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
    for cand in (os.path.join(top, "hooks", "lib", "agent-model.sh"),
                 os.path.join(_home(env), ".claude", "hooks", "lib", "agent-model.sh")):
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
    """The ROUTER is registered (PreToolUse)."""
    return any(isinstance(g, dict) and isinstance(g.get("hooks"), list) and any(_is_jev(h) for h in g["hooks"])
               for g in _groups(obj, "PreToolUse"))


def add_entry(obj):
    """Add the router (PreToolUse, matcher Agent) and the U-1 SessionStart notice."""
    new = json.loads(json.dumps(obj))
    hooks = new.setdefault("hooks", {})
    if not isinstance(hooks, dict):
        raise CtlError('.claude/settings.local.json: "hooks" is not an object -- nothing was changed')
    for event in JEV_EVENTS:
        if not isinstance(hooks.setdefault(event, []), list):
            raise CtlError('.claude/settings.local.json: "hooks.{}" is not a list -- nothing was changed'.format(event))
    hooks["PreToolUse"].append({"matcher": "Agent", "hooks": [{"type": "command", "command": REG_COMMAND, "timeout": 5}]})
    hooks["SessionStart"].append({"hooks": [{"type": "command", "command": SESSION_COMMAND, "timeout": 5}]})
    return new


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


def _ensure_excluded(top, gd, env):
    """Spec step 3: exclude settings.local.json unless git already ignores it."""
    try:
        if subprocess.run(["git", "-C", top, "check-ignore", "-q", EXCLUDE_LINE],
                          capture_output=True, timeout=10, env=env).returncode == 0:
            return False
    except (OSError, subprocess.SubprocessError):
        pass
    path = os.path.join(gd, "info", "exclude")
    data = _read(path) or b""
    if EXCLUDE_LINE in data.decode("utf-8", "replace").splitlines():
        return False
    sep = b"" if not data or data.endswith(b"\n") else b"\n"
    _write(path, data + sep + EXCLUDE_LINE.encode("utf-8") + b"\n")
    return True


def _key_source(env, registry):
    if (env.get("TYPESAFE_API_KEY") or "").strip():
        return "environment"
    if ((registry or jev_route._winreg_key)() or "").strip():
        return "HKCU\\Environment"
    return None


def cmd_on(top, gd, env, out, key_src):
    if not os.path.isfile(os.path.join(_home(env), ".claude", "skills", "jev", "jev_route.py")):
        raise CtlError("~/.claude/skills/jev/jev_route.py is not installed -- copy user-level-reference/skills/jev/ "
                       "to ~/.claude/skills/jev/ first; nothing was changed")
    if not resolver_lib(env, top):
        raise CtlError("no hooks/lib/agent-model.sh in this project or in ~/.claude/hooks/lib/ -- the router reuses "
                       "model-floor's resolution and cannot run without it; nothing was changed")
    mf = _active_model_floor(env, top)
    if mf and b"agent-model.sh" not in (_read(mf) or b""):
        raise CtlError("{} predates v4.4.0 (it steps aside on the switch alone, so a sibling worktree would lose "
                       "the floor) -- update it first (/sync-template, or the v4.4.0 hooks in ~/.claude/hooks/); "
                       "nothing was changed".format(mf))
    path = os.path.join(top, ".claude", "settings.local.json")
    before = _read(path)
    obj = parse_settings(before)
    if has_entry(obj):
        out.write("jev: the router is already registered in .claude/settings.local.json\n")
    else:
        new = add_entry(obj)
        snap = {"existed": before is not None,
                "before_b64": base64.b64encode(before or b"").decode("ascii"), "after": new}
        _write(_snapshot_path(gd, top), _dumps(snap))
        _write(path, _dumps(new))
        out.write("jev: registered the router (PreToolUse, matcher Agent) and a session-start notice in "
                  ".claude/settings.local.json\n")
    _write(_config_path(gd), _dumps(CONFIG_ON))
    if _ensure_excluded(top, gd, env):
        out.write("jev: added .claude/settings.local.json to .git/info/exclude\n")
    out.write("jev: ON for this clone -- spawns that pass no `model` are routed (one step at most from the "
              "agent's default; review/architect types never below sonnet); other checkouts of this clone "
              "need their own /jev on\n")
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
            out.write("jev: .claude/settings.local.json restored to its state before /jev on\n")
        elif remove_entry(obj) != obj:
            _write(path, _dumps(remove_entry(obj)))
            out.write("jev: .claude/settings.local.json changed since /jev on -- removed only the Jev entry "
                      "(the file was re-serialised)\n")
    if os.path.exists(snap_path):
        os.remove(snap_path)
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
    installed = os.path.isfile(os.path.join(_home(env), ".claude", "skills", "jev", "jev_route.py"))
    lib = resolver_lib(env, top)
    src = key_src
    out.write("jev: router registered in this checkout: {}\n".format("yes" if registered else "no"))
    out.write("jev: router installed (~/.claude/skills/jev/jev_route.py): {}\n".format("yes" if installed else "no"))
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
