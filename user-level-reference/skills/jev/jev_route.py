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
             if k in choices and isinstance(v, (int, float)) and not isinstance(v, bool)}
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
                      ensure_ascii=False).encode("utf-8")


def emit(tool_input, model):
    """The hook's stdout: the WHOLE original tool_input with only `model` set
    (updatedInput REPLACES it). b"" when it cannot be written as strict JSON."""
    try:
        ti = dict(tool_input)
        ti["model"] = model
        out = json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": ti}},
                         ensure_ascii=False, allow_nan=False)
    except (TypeError, ValueError):
        return b""
    return out.encode("utf-8")
