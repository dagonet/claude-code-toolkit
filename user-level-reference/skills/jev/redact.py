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
    # Terminated block first. The body may not run into another BEGIN marker, so a pile of
    # unterminated markers costs one short scan each (linear overall), not 10000 chars each.
    ("private_key",
     r"-----BEGIN [A-Z ]{0,40}PRIVATE KEY-----(?:(?!-----BEGIN )[\s\S]){0,10000}?-----END [A-Z ]{0,40}PRIVATE KEY-----",
     "[REDACTED:private_key]"),
    # A BEGIN with no (reachable) END: mask to the end of the text. The greedy tail consumes
    # everything, so re.sub resumes at the end -- one match, no retries.
    ("private_key", r"-----BEGIN [A-Z ]{0,40}PRIVATE KEY-----[\s\S]*", "[REDACTED:private_key]"),
    ("url_credentials", r"((?<![\w+.-])[A-Za-z][A-Za-z0-9+.-]{0,20}://[^\s:/@]{1,64}:)[^\s@/]{1,256}(@)",
     r"\1[REDACTED:url_credentials]\2"),
    ("jwt", r"\beyJ[\w-]+\.[\w-]+\.[\w-]+", "[REDACTED:jwt]"),
    ("api_key", r"\bsk-[A-Za-z0-9_-]{16,}", "[REDACTED:api_key]"),
    ("github_token", r"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
     "[REDACTED:github_token]"),
    ("aws_key", r"(?<![A-Z0-9])(?:AKIA|ASIA)[0-9A-Z]{16}(?![A-Z0-9])", "[REDACTED:aws_key]"),
    ("slack_token", r"\bxox[abprs]-[A-Za-z0-9-]{10,}", "[REDACTED:slack_token]"),
    ("slack_webhook", r"hooks\.slack\.com/services/[\w/]+", "[REDACTED:slack_webhook]"),
    ("google_key", r"(?<![\w-])AIza[0-9A-Za-z_-]{35}", "[REDACTED:google_key]"),
    ("google_oauth", r"(?<![\w-])ya29\.[\w.-]{20,}", "[REDACTED:google_oauth]"),
    ("gitlab_token", r"(?<![\w-])glpat-[\w-]{20,}", "[REDACTED:gitlab_token]"),
    ("stripe_key", r"(?<![A-Za-z0-9])(?:sk|rk|pk)_(?:live|test)_[0-9A-Za-z]{10,}", "[REDACTED:stripe_key]"),
    ("hf_token", r"(?<![A-Za-z0-9])hf_[A-Za-z0-9]{20,}", "[REDACTED:hf_token]"),
    ("npm_token", r"(?<![A-Za-z0-9])npm_[A-Za-z0-9]{20,}", "[REDACTED:npm_token]"),
    ("sendgrid_key", r"(?<![\w-])SG\.[\w-]{16,}\.[\w-]{16,}", "[REDACTED:sendgrid_key]"),
    ("bearer", r"(?i)(\bBearer\s+)[A-Za-z0-9._~+/=-]{8,}", r"\1[REDACTED:bearer]"),
    ("basic", r"(?i)(\bBasic\s+)[A-Za-z0-9+/=]{8,}", r"\1[REDACTED:basic]"),
    # Azure storage connection string: the value runs to the ';' and keeps its '=' padding.
    ("azure_key", r"(?i)((?<![\w.-])AccountKey=)[^;\s\"']+", r"\1[REDACTED:azure_key]"),
    # `auth` only as a whole name (auth, basic_auth, http.auth), so author/authority/OAuth stay.
    ("key_value",
     r"(?i)((?<![\w.-])(?:[\w.-]{0,64}?(?:password|passwd|secret|token|api[_-]?key|private[_-]?key"
     r"|credentials?|access[_-]?key|accountkey)[\w.-]{0,64}|(?:[\w.-]{0,64}?[_.-])?auth)[\"']?\s*[=:]\s*)"
     r"(?:\"[^\"\n]*\"|'[^'\n]*'|(?!\[REDACTED)[^\s\"']+)",
     r"\1[REDACTED:key_value]"),
    ("email", r"(?<![\w.+-])[\w.+-]{1,64}@[\w-]{1,63}(?:\.[\w-]{1,63}){1,8}", "[REDACTED:email]"),
]
if _USER:
    _u = re.escape(_USER)
    _PATTERNS += [
        ("user_path", r"(?i)(?:\b[A-Za-z]:[\\/]|/[a-z]/)Users[\\/]" + _u + r"(?![\w-])|/home/" + _u + r"(?![\w-])", "~"),
        ("username", r"(?<![\w-])" + _u + r"(?![\w-])", "[REDACTED:user]"),
    ]
_COMPILED = [(kind, re.compile(rx), repl) for kind, rx, repl in _PATTERNS]

_HEXISH = re.compile(r"[0-9a-fA-F]{24,}")
_TOKEN = re.compile(r"(?<![\w.\\-])[A-Za-z0-9_-]{24,}(?![\w/\\-])(?!\.\w)")
# Base64-ish run that may hold / + . (and = padding): AWS secret keys, ya29.*, SG.*.*. The run is
# found in one linear pass; _b64_secret() then tells it from a path / package name / URL.
_B64RUN = re.compile(r"(?<![A-Za-z0-9+/._-])[A-Za-z0-9+/._-]{32,}={0,2}")
_SEGMENT_SPLIT = re.compile(r"[/.+]")
_WORDISH = re.compile(r"([A-Za-z_-]+)[0-9]{0,3}")


def redact(text):
    """Mask secrets and the local username. Returns (text, {kind: hits})."""
    counts = {}
    for kind, rx, repl in _COMPILED:
        text, n = rx.subn(repl, text)
        counts[kind] = counts.get(kind, 0) + n
    return text, counts


_LETTER_PAIR = re.compile(r"(?=[A-Za-z]{2})")
_CASE_FLIP = re.compile(r"(?=[a-z][A-Z]|[A-Z][a-z])")
_LOWER, _UPPER, _DIGIT = re.compile(r"[a-z]"), re.compile(r"[A-Z]"), re.compile(r"\d")
# 7M in K7MDENG / 3oVM in EZ513oVM: a digit inside a word that has an upper-case letter and is NOT followed by
# a plain word piece. Random text has these; trailing version digits (Service2), Int64RangeMatch, 7z-compressed,
# 4t64 and all-lowercase names do not.
_DIGIT_IN_WORD = re.compile(r"[A-Z][A-Za-z0-9]*\d(?![A-Z]?[a-z]{2})[A-Za-z][A-Za-z0-9]|\d(?![A-Z]?[a-z]{2})[A-Z][A-Za-z0-9]")
_WINDOW_SEGS = 6  # longest stretch of segments judged on its own (a secret hiding behind a path prefix)
_WINDOW_RUN = 400  # only runs up to this long are windowed; keeps the scan linear and cheap


def _case_stats(text):
    """(letter pairs, case changes) over adjacent letters; random base64 changes case about half the time."""
    return (sum(1 for _ in _LETTER_PAIR.finditer(text)), sum(1 for _ in _CASE_FLIP.finditer(text)))


def _wordish(seg):
    """A path/identifier segment: letters (up to 3 trailing digits) that change case rarely (<= 1 in 4)."""
    m = _WORDISH.fullmatch(seg)
    if not m or len(m.group(1)) < 3:
        return False
    return _case_stats(m.group(1))[1] * 4 <= len(m.group(1))


def _secret_segment(seg):
    """One segment that is random on its own: long enough, mixed case, and flipping case like random text."""
    if len(seg) < 12 or "_" in seg or "-" in seg:
        return False  # snake/kebab names (HiPKI_Root_CA_-_G1) are identifiers, not random
    pairs, changes = _case_stats(seg)
    if pairs < 10 or changes * 20 <= pairs * 7:  # fewer than 35% flips: ordinary CamelCase
        return False
    return bool(_DIGIT_IN_WORD.search(seg)) or changes * 20 > pairs * 9  # a digit inside a word, or coin-toss flips


def _random_looking(core, windowed=False):
    """core is an unpadded base64-ish string with separators: random secret (True) or path / package name."""
    if len(core) < 32:
        return False
    if not (_LOWER.search(core) and _UPPER.search(core) and _DIGIT.search(core)):
        return False
    segs = _SEGMENT_SPLIT.split(core)
    if (len(segs) - 1) * 8 > len(core):
        return False  # many separators for its length: a path or URL
    if any(_secret_segment(seg) for seg in segs):
        return True  # one random-looking segment is decisive, whatever words surround it
    pairs, changes = _case_stats(core)
    if pairs >= 12 and changes * 100 >= pairs * 30 and _DIGIT_IN_WORD.search(core):
        return True  # case flips like random text, with digits inside words, across the whole token
    if windowed:
        return False  # a window needs positive evidence; "not enough words" is only enough for the whole token
    if _DIGIT_IN_WORD.search(core):
        return True  # digits inside words are not how paths and package names are spelled
    return sum(1 for seg in segs if _wordish(seg)) < 2  # two word-like segments: a path or package name


def _b64_secret(run):
    """True if a base64-ish run (with / + . or = padding) looks like a secret, not a path or package name."""
    stripped = run.rstrip(".")  # a sentence-ending dot is not part of the token
    padded = stripped.endswith("=")
    core = stripped.rstrip("=")
    if len(core) < 32 or not (padded or re.search(r"[/.+]", core)):
        return False  # no separators: _TOKEN's job
    if _random_looking(core):
        return True
    if len(core) > _WINDOW_RUN:
        return False
    # A secret behind/before path words (aws/<key>, <key>/config): judge each short stretch of segments too.
    cuts = [-1] + [m.start() for m in _SEGMENT_SPLIT.finditer(core)] + [len(core)]
    count = len(cuts) - 1
    for i in range(count - 1):
        for j in range(i + 2, min(i + _WINDOW_SEGS, count) + 1):
            if (i, j) != (0, count) and _random_looking(core[cuts[i] + 1:cuts[j]], True):
                return True
    return False


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
    for m in _B64RUN.finditer(text):
        if _b64_secret(m.group(0)):
            found.append("base64-like token of {} chars".format(len(m.group(0))))
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
