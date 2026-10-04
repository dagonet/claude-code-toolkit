"""Redaction, trimming and a fail-closed residual check for what the Jev router sends.

From the Jev Phase 0 spike (spikes/jev-phase0/redact.py), unchanged except trim(),
which now keeps the WHOLE result -- marker included -- within the cap (spec step 3:
"trim to 4,000 chars"; the spike's version overshot by the marker's length).

Order matters: redact the FULL text first (trimming could cut a secret in half so
no pattern matches), then trim, then run residual_findings() on what would be sent.
Any residual finding means nothing is sent -- egress is fail-closed.
"""
import sys

sys.dont_write_bytecode = True

import getpass  # noqa: E402
import re  # noqa: E402

try:
    _USER = getpass.getuser()
except Exception:  # no passwd entry, no env: nothing to mask by name
    _USER = ""

# (kind, regex, replacement). Order matters: specific shapes first, key=value after
# them (its value lookahead skips what an earlier pattern already masked).
_PATTERNS = [
    ("private_key", r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
     "[REDACTED:private_key]"),
    ("url_credentials", r"(\b[A-Za-z][A-Za-z0-9+.-]*://[^\s:/@]+:)[^\s@/]+(@)",
     r"\1[REDACTED:url_credentials]\2"),
    ("jwt", r"\beyJ[\w-]+\.[\w-]+\.[\w-]+", "[REDACTED:jwt]"),
    ("api_key", r"\bsk-[A-Za-z0-9_-]{16,}", "[REDACTED:api_key]"),
    ("github_token", r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
     "[REDACTED:github_token]"),
    ("aws_key", r"\bAKIA[0-9A-Z]{16}\b", "[REDACTED:aws_key]"),
    ("slack_token", r"\bxox[abprs]-[A-Za-z0-9-]{10,}", "[REDACTED:slack_token]"),
    ("bearer", r"(\bBearer\s+)[A-Za-z0-9._~+/=-]{8,}", r"\1[REDACTED:bearer]"),
    ("key_value",
     r"(?i)(\b[\w.-]*(?:password|passwd|secret|token|api[_-]?key)[\w.-]*\s*[=:]\s*)([\"']?)(?!\[REDACTED)[^\s\"']+\2",
     r"\1\2[REDACTED:key_value]\2"),
    ("email", r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", "[REDACTED:email]"),
]
if _USER:
    _u = re.escape(_USER)
    _PATTERNS += [
        ("user_path", r"(?i)(?:\b[A-Za-z]:[\\/]|/[a-z]/)Users[\\/]" + _u + r"(?![\w-])|/home/" + _u + r"(?![\w-])", "~"),
        ("username", r"(?<![\w-])" + _u + r"(?![\w-])", "[REDACTED:user]"),
    ]
_COMPILED = [(kind, re.compile(rx), repl) for kind, rx, repl in _PATTERNS]

_HEXISH = re.compile(r"[0-9a-fA-F]{24,}")
_TOKEN = re.compile(r"(?<![\w./\\-])[A-Za-z0-9_-]{24,}(?![\w./\\-])")


def redact(text):
    """Mask secrets and the local username. Returns (text, {kind: hits})."""
    counts = {}
    for kind, rx, repl in _COMPILED:
        text, n = rx.subn(repl, text)
        counts[kind] = n
    return text, counts


def residual_findings(text):
    """Anything that still looks like a secret after redact(); empty means clear to send."""
    found = []
    if "PRIVATE KEY-----" in text:
        found.append("private key marker")
    for m in _TOKEN.finditer(text):
        tok = m.group(0)
        if _HEXISH.fullmatch(tok):
            continue
        if re.search(r"[a-z]", tok) and re.search(r"[A-Z]", tok) and re.search(r"\d", tok):
            found.append("high-entropy token of {} chars".format(len(tok)))
    return found


def trim(text, cap):
    """Keep the head and tail of text longer than cap; the result, marker included, is at most cap chars."""
    if len(text) <= cap:
        return text
    # The marker sized for the LARGEST count it can show, so the real one is never longer.
    keep = max(cap - len("\n...[trimmed {} chars]...\n".format(len(text))), 0)
    head, tail = keep - keep // 2, keep // 2
    removed = len(text) - head - tail
    return text[:head] + "\n...[trimmed {} chars]...\n".format(removed) + (text[len(text) - tail:] if tail else "")
