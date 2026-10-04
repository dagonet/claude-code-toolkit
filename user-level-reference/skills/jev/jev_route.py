#!/usr/bin/env python3
"""jev_route.py -- PreToolUse(Agent) router for the optional Jev layer (toolkit v4.4.0).

Spec: docs/plans/2026-09-28-jev-phase1-design.md (Phase 1a); plan:
docs/plans/2026-10-02-jev-phase1-implementation.md (rulings R-1..R-9).
Registered only by `/jev on`, as ONE entry in one checkout's
.claude/settings.local.json:
    f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0

Contract:
- STDOUT is exactly one {"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "updatedInput": {...}}} object, or nothing. Never a permissionDecision: a
  router must never auto-approve a spawn (ruling S-19).
- An explicit `model` in the call is never changed. A typed agent moves at most
  one step from its own model; review/architect types never below sonnet.
- A floor-class spawn (built-in, `model: inherit`, no model) ALWAYS leaves with
  a model -- Jev's choice when every check passes, else the project floor --
  because model-floor.sh has stepped aside for this checkout (R-1).
- Exit 0 always. The state text and the key are never logged.
"""
import sys

sys.dont_write_bytecode = True  # no __pycache__ beside the installed skill (drift)

import datetime  # noqa: E402
import json  # noqa: E402
import os  # noqa: E402
import re  # noqa: E402
import shutil  # noqa: E402
import socket  # noqa: E402
import subprocess  # noqa: E402
import threading  # noqa: E402
import time  # noqa: E402
import urllib.error  # noqa: E402
import urllib.parse  # noqa: E402
import urllib.request  # noqa: E402
from typing import NamedTuple  # noqa: E402

from redact import redact, residual_findings, trim  # noqa: E402

JEV_MODEL_DEFAULT = "jev-1.13.0"
THRESHOLD_DEFAULT = 0.8
ENDPOINT = "https://api.typesafe.ai/v1/systemone"
STATE_CAP = 4000
HTTP_TIMEOUT = 2.0
DEADLINE = 3.5  # seconds after start; the registration's hook timeout is 5
RESOLVER_TIMEOUT = 2.0
MAX_RESPONSE = 65536
ORDER = ("haiku", "sonnet", "opus", "fable")
EFFORTS = ("low", "medium", "high", "xhigh")
ROLE_FLOOR_RE = re.compile(r"review|architect", re.I)
FAMILY_RE = re.compile(r"^claude-(haiku|sonnet|opus|fable)-")

# The Phase 0 questions, verbatim (spikes/jev-phase0/extract_payloads.py): the
# measured agreement (model 98.5 %, effort 97.1 % within one step) holds for
# THIS wording against jev-1.13.0 only.
SPAWN_QUESTIONS = {
    "model": {
        "type": "choice",
        "instructions": "Which Claude model is the least costly one that can complete this delegated task correctly on the first attempt?",
        "criteria": {
            "haiku": "Read-only search, lookups, listing or simple extraction; no judgement and no edits.",
            "sonnet": "Well-specified implementation, tests, fixes or mechanical multi-file edits that follow a clear brief.",
            "opus": "Code review, debugging with an unclear root cause, design judgement, security-sensitive or cross-cutting changes.",
            "fable": "Architecture across subsystems, ambiguous high-stakes decisions, or very long multi-step reasoning.",
        },
    },
    "effort": {
        "type": "choice",
        "instructions": "How much reasoning effort does this delegated task need to avoid skipped files or steps?",
        "criteria": {
            "low": "A single lookup or a mechanical change with nothing to weigh.",
            "medium": "A clear brief with a few steps and ordinary verification.",
            "high": "Many steps or files, edge cases to track, verification that is easy to skip.",
            "xhigh": "Adversarial review, subtle correctness or security reasoning, or a large surface to check exhaustively.",
        },
    },
}


def family(model):
    """The alias family of a model: an alias itself, claude-<fam>-... -> <fam>, else None."""
    if model in ORDER:
        return model
    m = FAMILY_RE.match(model or "")
    return m.group(1) if m else None


def decide(kind, default, subagent_type, answer, threshold):
    """Bound Jev's answer (spec step 6). -> (model to emit or None, applied, reason).

    A floor spawn always gets a model (R-1): the floor itself when Jev's choice
    is not applied. A typed spawn gets one only for an applied move.
    """
    fallback = default if kind == "floor" else None
    fam = family(default)
    if fam is None:
        return fallback, False, "pinned"
    if not answer:
        return fallback, False, "bad-response"
    choice, conf = answer["choice"], answer["confidence"]
    if conf < threshold:
        return fallback, False, "low-confidence"
    if abs(ORDER.index(choice) - ORDER.index(fam)) > 1:
        return fallback, False, "out-of-bounds"
    if choice == fam:
        return fallback, False, "kept"
    if ROLE_FLOOR_RE.search(subagent_type or "") and ORDER.index(choice) < ORDER.index("sonnet"):
        return fallback, False, "role-floor"
    return choice, True, "applied"


def _answer(answers, key, choices):
    a = answers.get(key) if isinstance(answers, dict) else None
    if not isinstance(a, dict):
        return None
    choice, conf = a.get("choice"), a.get("confidence")
    if choice not in choices or isinstance(conf, bool) or not isinstance(conf, (int, float)):
        return None
    if not 0.0 <= conf <= 1.0:  # also false for NaN
        return None
    probs = a.get("probabilities") if isinstance(a.get("probabilities"), dict) else {}
    probs = {k: v for k, v in probs.items()
             if k in choices and isinstance(v, (int, float)) and not isinstance(v, bool)
             and 0.0 <= v <= 1.0}  # finite 0..1 only (the range test is false for NaN)
    return {"choice": choice, "confidence": float(conf), "probabilities": probs}


def parse_answers(raw):
    """-> (model answer or None, effort answer or None) from a /v1/systemone body."""
    try:
        obj = json.loads(raw.decode("utf-8"))
    except (AttributeError, UnicodeDecodeError, ValueError):
        return None, None
    answers = obj.get("answers") if isinstance(obj, dict) else None
    return _answer(answers, "model", ORDER), _answer(answers, "effort", EFFORTS)


def build_state(tool_input):
    """Spec step 3: type + description + prompt, redacted, then trimmed. -> (state, residual findings)."""
    text = "agent_type: {}\ndescription: {}\n\n{}".format(
        tool_input.get("subagent_type") or "general-purpose",
        tool_input.get("description") or "",
        tool_input.get("prompt") or "")
    redacted, _counts = redact(text)
    state = trim(redacted, STATE_CAP)
    return state, residual_findings(state)


def build_request(state, jev_model):
    return json.dumps({"state": state, "model": jev_model, "questions": SPAWN_QUESTIONS},
                      ensure_ascii=True).encode("utf-8")


def emit(tool_input, model):
    """The hook's stdout: the WHOLE original tool_input with only `model` set
    (updatedInput REPLACES it). b"" when it cannot be written as strict JSON."""
    try:
        ti = dict(tool_input)
        ti["model"] = model
        out = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}},
                         ensure_ascii=True, allow_nan=False)  # ASCII escapes: a lone surrogate must not break encode()
    except (TypeError, ValueError):
        return b""
    return out.encode("utf-8")


REASONS = frozenset({
    "explicit", "none", "pinned", "egress-refused", "no-key", "no-endpoint",
    "deadline", "timeout", "http-error", "bad-response", "low-confidence",
    "out-of-bounds", "role-floor", "kept", "applied", "error",
})
EVENT_FIELDS = ("ts", "subagent_type", "kind", "default", "agent_effort", "choice", "confidence",
                "probabilities", "effort_choice", "effort_confidence", "applied", "reason",
                "emitted", "latency_s")


class Resolution(NamedTuple):
    """One line of `bash hooks/lib/agent-model.sh <type> <cwd>`."""
    kind: str    # own | floor | env | none
    model: str   # "" for none; for env the CLAUDE_CODE_SUBAGENT_MODEL value (U-1)
    jev: bool    # Jev routing is live in this checkout (model-floor stepped aside)
    effort: str  # the agent file's `effort:`, "" when unset
    gd: str      # absolute git common dir, "" when unknown


class JevTimeout(Exception):
    """No answer within the deadline."""


class HttpError(Exception):
    """A non-200 status or a transport failure."""


def _winreg_key():
    if sys.platform != "win32":
        return ""
    try:
        import winreg
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as k:
            val, _ = winreg.QueryValueEx(k, "TYPESAFE_API_KEY")
            return str(val)
    except OSError:
        return ""


def load_key(env, registry=None):
    """TYPESAFE_API_KEY from env, else HKCU\\Environment. Test mode never reads the registry."""
    key = (env.get("TYPESAFE_API_KEY") or "").strip()
    if key or env.get("JEV_TEST_MODE") == "1":
        return key
    return ((registry or _winreg_key)() or "").strip()


def pick_endpoint(env):
    """The real endpoint, always -- except in test mode, which may only reach http://127.0.0.1."""
    if env.get("JEV_TEST_MODE") != "1":
        return ENDPOINT
    url = env.get("JEV_ENDPOINT") or ""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme == "http" and parts.hostname == "127.0.0.1":
        return url
    return None


def read_config(gd):
    """-> (jev model, threshold) from <gd>/jev/config.json; defaults for anything unreadable."""
    model, threshold = JEV_MODEL_DEFAULT, THRESHOLD_DEFAULT
    try:
        with open(os.path.join(gd, "jev", "config.json"), "rb") as fh:
            cfg = json.loads(fh.read().decode("utf-8-sig"))
    except (OSError, UnicodeDecodeError, ValueError):
        return model, threshold
    if isinstance(cfg, dict):
        if isinstance(cfg.get("model"), str) and re.fullmatch(r"jev-[0-9]+(\.[0-9]+)*", cfg["model"]):
            model = cfg["model"]
        t = cfg.get("threshold")
        if isinstance(t, (int, float)) and not isinstance(t, bool) and 0.5 <= t <= 1.0:
            threshold = float(t)
    return model, threshold


def _now_utc():
    return datetime.datetime.now(datetime.timezone.utc)


def write_event(gd, ev, now=None):
    """<gd>/jev/events/<YYYYmmddTHHMMSSffffffZ>-<pid>.json -- no colon (NTFS)."""
    now = now or _now_utc()
    d = os.path.join(gd, "jev", "events")
    os.makedirs(d, exist_ok=True)
    name = "{}-{}.json".format(now.strftime("%Y%m%dT%H%M%S%fZ"), os.getpid())
    with open(os.path.join(d, name), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(ev, fh, sort_keys=True, ensure_ascii=False)
        fh.write("\n")


def _new_event(stype, res):
    return {"ts": _now_utc().isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "subagent_type": stype or "general-purpose", "kind": res.kind, "default": res.model,
            "agent_effort": res.effort, "choice": None, "confidence": None, "probabilities": {},
            "effort_choice": None, "effort_confidence": None, "applied": False, "reason": "error",
            "emitted": None, "latency_s": None}


def _ask(ti, stype, res, env, post, registry, clock, t0, ev):
    """Ask Jev and bound the answer. -> (model to emit or None, reason, applied)."""
    fallback = res.model if res.kind == "floor" else None
    if family(res.model) is None:
        return fallback, "pinned", False
    state, findings = build_state(ti)
    if findings:
        return fallback, "egress-refused", False
    key = load_key(env, registry)
    if not key:
        return fallback, "no-key", False
    url = pick_endpoint(env)
    if not url:
        return fallback, "no-endpoint", False
    jev_model, threshold = read_config(res.gd)
    budget = min(HTTP_TIMEOUT, DEADLINE - (clock() - t0))
    if budget <= 0.05:
        return fallback, "deadline", False
    try:
        raw = post(url, build_request(state, jev_model), key, budget, env)
    except JevTimeout:
        return fallback, "timeout", False
    except (HttpError, OSError):
        return fallback, "http-error", False
    model_ans, effort_ans = parse_answers(raw)
    if effort_ans:
        ev["effort_choice"], ev["effort_confidence"] = effort_ans["choice"], effort_ans["confidence"]
    if model_ans:
        ev["choice"], ev["confidence"] = model_ans["choice"], model_ans["confidence"]
        ev["probabilities"] = model_ans["probabilities"]
    model, applied, reason = decide(res.kind, res.model, stype, model_ans, threshold)
    return model, reason, applied


def run(stdin_bytes, env, resolver=None, post=None, registry=None, clock=time.monotonic):
    """The whole hook minus process I/O. -> (stdout bytes, event or None, git common dir).

    An event of None means Jev is off for this checkout (the resolver says
    model-floor did not step aside, or there is no resolver): no output, no
    file, no network -- the zero-footprint path.
    """
    t0 = clock()
    try:
        payload = json.loads(stdin_bytes.decode("utf-8-sig"))
    except (UnicodeDecodeError, ValueError):
        return b"", None, ""
    if not isinstance(payload, dict) or payload.get("tool_name") != "Agent":
        return b"", None, ""
    ti = payload.get("tool_input")
    if not isinstance(ti, dict):
        return b"", None, ""
    stype = ti.get("subagent_type") if isinstance(ti.get("subagent_type"), str) else ""
    cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) and payload.get("cwd") else "."
    res = (resolver or run_resolver)(stype, cwd, env)
    if res is None or not res.jev or not res.gd:
        return b"", None, ""
    ev = _new_event(stype, res)
    fallback = res.model if res.kind == "floor" else None
    try:
        if ti.get("model"):
            model, ev["reason"] = None, "explicit"
        elif res.kind not in ("own", "floor", "env"):  # U-1: env routes like own
            model, ev["reason"] = None, "none"
        else:
            model, ev["reason"], ev["applied"] = _ask(
                ti, stype, res, env, post or post_with_deadline, registry, clock, t0, ev)
    except Exception:  # noqa: BLE001 -- the router must never fail a spawn
        model, ev["reason"], ev["applied"] = fallback, "error", False
    out = emit(ti, model) if model else b""
    ev["emitted"] = model if out else None
    ev["latency_s"] = round(clock() - t0, 3)
    return out, ev, res.gd


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Never follow a 3xx: urllib would resend the Bearer header to the Location host.
    Returning None makes the 3xx raise HTTPError, which is an http-error -> floor."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


RESOLUTION_RE = re.compile(r"^(own|floor|env|none) (\S+) ([01]) (\S+) (.+)$")


def post_with_deadline(url, body, key, timeout, env):
    """POST in a worker thread joined with `timeout`. urllib's own timeout is per
    socket operation (a slow drip never trips it) and name resolution has none,
    so only the join bounds the wall clock. Raises JevTimeout or HttpError."""
    box = {}
    handlers = [_NoRedirect()]
    if env.get("JEV_TEST_MODE") == "1":
        handlers.append(urllib.request.ProxyHandler({}))
    opener = urllib.request.build_opener(*handlers)

    def work():
        req = urllib.request.Request(url, data=body, method="POST", headers={
            "Authorization": "Bearer " + key, "Content-Type": "application/json"})
        try:
            with opener.open(req, timeout=timeout) as resp:
                box["status"], box["raw"] = resp.status, resp.read(MAX_RESPONSE)
        except urllib.error.HTTPError as exc:
            box["status"] = exc.code
        except Exception as exc:  # noqa: BLE001 -- any failure is "no answer"
            box["exc"] = exc

    worker = threading.Thread(target=work, daemon=True)
    worker.start()
    worker.join(timeout)
    if worker.is_alive():
        raise JevTimeout()
    exc = box.get("exc")
    if exc is not None:
        if isinstance(exc, (TimeoutError, socket.timeout)) or isinstance(getattr(exc, "reason", None), (TimeoutError, socket.timeout)):
            raise JevTimeout()
        raise HttpError(type(exc).__name__)
    if box.get("status") != 200:
        raise HttpError(str(box.get("status")))
    return box["raw"]


def run_resolver(subagent_type, cwd, env):
    """Run model-floor's own resolution (hooks/lib/agent-model.sh) -- the project's
    copy when CLAUDE_PROJECT_DIR has one (the S-24 precedence), else the user-level
    one. Arguments go in argv, never into program text. None when unavailable."""
    cands = []
    if env.get("CLAUDE_PROJECT_DIR"):
        cands.append(os.path.join(env["CLAUDE_PROJECT_DIR"], "hooks", "lib", "agent-model.sh"))
    home = env.get("HOME") or os.path.expanduser("~")
    cands.append(os.path.join(home, ".claude", "hooks", "lib", "agent-model.sh"))
    lib = next((c for c in cands if os.path.isfile(c)), None)
    bash = shutil.which("bash", path=env.get("PATH"))
    if not lib or not bash:
        return None
    try:
        cp = subprocess.run([bash, lib, subagent_type, cwd], capture_output=True,
                            timeout=RESOLVER_TIMEOUT,
                            env={k: v for k, v in env.items() if k != "TYPESAFE_API_KEY"})
    except (OSError, subprocess.SubprocessError):
        return None
    m = RESOLUTION_RE.match(cp.stdout.decode("utf-8", "replace").strip())
    if not m:
        return None
    kind, model, jev, effort, gd = m.groups()
    return Resolution(kind, "" if model == "-" else model, jev == "1",
                      "" if effort == "-" else effort, "" if gd == "-" else gd)


def main():
    try:
        out, ev, gd = run(sys.stdin.buffer.read(), dict(os.environ))
    except Exception:  # noqa: BLE001 -- never fail a spawn
        return 0
    if out:
        sys.stdout.buffer.write(out)
        sys.stdout.buffer.flush()
    if ev is not None and gd:
        try:
            write_event(gd, ev)
        except OSError:
            pass
    if out and ev is not None:
        sys.stderr.write("jev: {} {} -> {} ({})\n".format(
            ev["subagent_type"], ev["default"] or "-", ev["emitted"], ev["reason"]))
    return 0


if __name__ == "__main__":
    _rc = main()
    sys.stdout.flush()
    sys.stderr.flush()
    os._exit(_rc)  # never wait for a request thread still blocked in the network
