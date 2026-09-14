"""
template-sync manifest v3: three-class file ownership.

Pure functions used by the tools in template_sync_mcp.py when a project's
manifest carries `manifest_version: 3`. A v2 manifest never reaches this
module. Contract: docs/plans/2026-09-05-v3.1-ownership-server-review.md.

Imports the shared helpers from template_sync_mcp as `core`; that module
imports this one lazily inside tool bodies, so there is no import cycle.
"""

from __future__ import annotations

import json
import pathlib
import re

from . import mcp as core

# MIN_SERVER_FOR_V3 names the OLDEST server whose region splice is safe. It is
# NOT the current version and must not track VERSION. In a 4.x codebase this
# line looks exactly like the stale literals corrected in v3.1.2 and v3.1.4;
# "bumping it to match" is a contract change with a monotonic, per-project,
# automatic consequence: raise_floor stamps every existing manifest with the
# new floor on its first finalize, after which that project cannot load on any
# older server. Check 45 in the toolkit gate keeps this a 0.3.x string.
MIN_SERVER_FOR_V3 = "0.3.2"
MANIFEST_VERSION_V3 = 3

# Capabilities a caller may gate on, reported by template_load_manifest.
#
# A version is a proxy for a capability, and every proxy eventually disagrees
# with the thing it stands for: 0.3.1 was newer than 0.3.0 and equally unable
# to splice a region, so a skill keying on the version number learned nothing
# about the hazard. Gate on `"region_splice" in capabilities` instead.
#
# PRESENCE is the contract -- a name is here or it is not, never a boolean
# whose default someone misreads. Names are PERMANENT: appended to, never
# renamed or removed, even if the implementation behind one changes, or the
# map becomes another drifting proxy. Every name is paired with a witness in
# tests/test_template_sync_capabilities.py that exercises the behaviour it
# claims, and the set is asserted exactly, so the list cannot grow into
# claims nobody checked. Deliberately short: names a caller would branch on,
# not an inventory of every field emitted.
CAPABILITIES = (
    "region_splice",
    "region_orphaned",
    "region_markers_malformed",
    "local_diff_kind",
    "server_source",
    "skill_version_floor",
)
OWNERSHIP_FILE = "templates/ownership.json"
PROJECT_MD = ".claude/rules/project.md"
CLASSES = ("template", "once", "project")


# -------------------------
# Ownership rules
# -------------------------

def glob_to_regex(pattern: str) -> re.Pattern:
    """Translate a PurePosixPath-style glob into an anchored regex.

    `**` matches across `/`, `*` and `?` stay within one segment. The
    pattern is matched against a template-relative path with forward
    slashes (the key space of _scan_template_files).
    """
    out = []
    i = 0
    while i < len(pattern):
        ch = pattern[i]
        if ch == "*":
            if pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif ch == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(ch))
        i += 1
    return re.compile("^" + "".join(out) + "$")


class OwnershipRules:
    def __init__(self, rules: list[dict], tracked_paths: list[str], warnings: list[str],
                 requires_skill: str = ""):
        self.rules = rules
        self.tracked_paths = tracked_paths
        self.warnings = warnings
        # The toolkit's floor on the CALLER's sync-template skill. Declared in
        # its own file so it can be raised without a release here -- a floor
        # living in this code would ship later than the thing it must gate,
        # which is the 0.3.1 problem in mirror image.
        self.requires_skill = requires_skill
        self._compiled = [(glob_to_regex(r["pattern"]), r) for r in rules]

    def rule_for(self, template_rel: str) -> dict | None:
        norm = core._normalize_path(template_rel)
        for rx, rule in self._compiled:
            if rx.match(norm):
                return rule
        return None

    def class_of(self, template_rel: str) -> str | None:
        rule = self.rule_for(template_rel)
        return rule["ownership"] if rule else None

    def project_path_for(self, template_rel: str) -> str:
        rule = self.rule_for(template_rel)
        if rule and rule.get("target"):
            return core._normalize_path(rule["target"])
        return core._normalize_path(template_rel)

    def template_path_for(self, project_rel: str) -> str:
        norm = core._normalize_path(project_rel)
        for rule in self.rules:
            if rule.get("target") and core._normalize_path(rule["target"]) == norm:
                return rule["pattern"]
        return norm

    def template_class_rules(self) -> list[dict]:
        return [r for r in self.rules if r["ownership"] == "template"]


def load_ownership(template_repo: str) -> OwnershipRules | None:
    """Read <repo>/templates/ownership.json. None when absent (no v3 template)."""
    path = core._resolve_path(template_repo) / OWNERSHIP_FILE
    raw = core._read_file(path)
    if raw is None:
        return None
    warnings: list[str] = []
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        return OwnershipRules([], ["templates"], [f"ownership.json is not valid JSON: {e}"])

    rules: list[dict] = []
    for idx, rule in enumerate(data.get("rules", [])):
        pattern = rule.get("pattern") if isinstance(rule, dict) else None
        ownership = rule.get("ownership") if isinstance(rule, dict) else None
        if not pattern or not isinstance(pattern, str):
            warnings.append(f"ownership.json rules[{idx}]: missing pattern -- skipped")
            continue
        if ownership not in CLASSES:
            warnings.append(
                f"ownership.json rules[{idx}] ({pattern}): ownership must be one of {CLASSES} -- skipped"
            )
            continue
        rules.append(rule)

    tracked = data.get("tracked_paths")
    if not isinstance(tracked, list) or not all(isinstance(t, str) for t in tracked):
        tracked = ["templates"] + [p.rstrip("/") for p in core._ROOT_TRACKED_PREFIXES]
        warnings.append(
            "ownership.json has no tracked_paths -- template_version derivation "
            f"falls back to {tracked}"
        )
    floor = data.get("requires_skill")
    return OwnershipRules(rules, list(tracked), warnings,
                          floor if isinstance(floor, str) else "")


# -------------------------
# Manifest v3 helpers
# -------------------------

HASH_RE = re.compile(r"^(?:sha256:)?([0-9a-f]{64})$")

KNOWN_TOP_LEVEL_V3 = {
    "manifest_version", "template_version", "template_commit", "lastSynced",
    "variant", "templateRepo", "placeholders", "requires_server", "files",
    # v2 keys that migration removes; listed so they are never reported as unknown
    "version",
}


def is_v3(manifest: dict) -> bool:
    return manifest.get("manifest_version") == MANIFEST_VERSION_V3


def manifest_commit(manifest: dict) -> str:
    """template_commit, with lastSynced accepted as a read alias (review §2.1)."""
    return manifest.get("template_commit") or manifest.get("lastSynced") or ""


def parse_hash(value: str) -> str:
    m = HASH_RE.match(value or "")
    return m.group(1) if m else ""


def format_hash(hex_digest: str) -> str:
    return "sha256:" + hex_digest


def parse_version(s: str) -> tuple[int, int, int]:
    parts = s.strip().split(".")
    if len(parts) != 3 or not all(p.isdigit() for p in parts):
        raise ValueError(f"not a X.Y.Z version: {s!r}")
    return int(parts[0]), int(parts[1]), int(parts[2])


# The one string a non-skill caller passes to say so: a harness, a rehearsal
# rig, a human driving the tool directly. Without it the guard's first casualty
# would be the tooling that caught the region data-loss regression, none of
# which is the sync skill and none of which can honestly claim a skill version.
#
# EXACT, case-sensitive, surrounding whitespace only. Every near miss must land
# in the mismatch arm and REFUSE: a mistyped sentinel that refuses is a
# nuisance, a mistyped sentinel that bypasses is the guard quietly not existing.
SKILL_BYPASS_SENTINEL = "not-a-skill"

# Tag-shaped on BOTH sides. The floor reads ">=v3.1.3" and the skill's marker
# reads "v3.1.3", so a bare "3.1.3" is a different namespace, not a synonym --
# `VERSION` holds a version number, this holds a tag name, and the `v` is the
# whole difference. Normalising it away here invites a second, disagreeing
# normalisation somewhere else, which is exactly how the toolkit's emitter broke
# as a git ref before. Named as a mismatch instead.
SKILL_TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")

# The below-floor arm needs no population split: a caller that passed a
# tag-shaped value IS the skill, or is impersonating one on purpose.
_SKILL_REMEDY = (
    "copy user-level-reference/skills/sync-template/SKILL.md from toolkit tag {tag} or "
    "later into ~/.claude/skills/sync-template/SKILL.md, then START A FRESH SESSION and run "
    "the sync again. Re-copying without restarting changes nothing for this session. "
    "Pass dry_run=True to inspect without migrating."
)


def skill_floor_satisfied(spec: str, claimed: str) -> tuple[bool, str, str, bool]:
    """Compare a caller's claimed sync-template skill version to the floor.

    Returns (ok, refusal, warning, bypassed). `ok` False carries a refusal for
    WRITE mode only -- dry_run is never refused for this, because the preview is
    what surfaces a gate_self_reference before a consumer is mid-sync.

    The value is self-asserted by the caller even though the caller is the thing
    being checked. That is deliberate and it is the only thing that works: the
    installed ~/.claude/skills/sync-template/SKILL.md reports the DISK, while the
    failure being gated is a session executing a body it read at startup, so a
    disk read returns a confident green in precisely the stale case. It holds
    because the threat is staleness, not deceit -- a body too old to carry the
    instruction cannot produce the value by accident, and absence is therefore
    the load-bearing signal rather than a low number.
    """
    spec = (spec or "").strip()
    claimed = (claimed or "").strip()
    if not spec:
        return True, "", "", False               # nothing declared, nothing to enforce
    if not spec.startswith(">=") or not SKILL_TAG_RE.match(spec[2:].strip()):
        # Same rule as requires_server: a floor this server cannot read is left
        # exactly as found. Refusing on a value my parser failed to understand
        # would turn my bug into the consumer's outage, and guessing is worse.
        return True, "", (f"requires_skill_unparseable: {spec!r} is not the '>=vX.Y.Z' form "
                          "this server understands -- not enforced"), False
    floor = spec[2:].strip()
    if claimed == SKILL_BYPASS_SENTINEL:
        return True, "", "", True
    if not claimed:
        # TWO populations arrive here and their remedies differ, so the text runs
        # both arms in parallel rather than diagnosing one and mentioning the
        # other last. A stale skill body passes nothing because it has no
        # instruction to; a caller that is not the skill at all -- a harness, a
        # direct tool call, a human -- passes nothing regardless of which body
        # the session loaded, because the thing that passes skill_version is the
        # skill's migration step and that step only runs when the skill runs.
        # Addressing only the first sends the second to restart, call again, and
        # read the same message. Measured on a consumer who was BOTH at once, so
        # the diagnosis was true of them by coincidence while only the second
        # fact explained their empty field.
        return False, (
            f"template_migrate_manifest refused: this caller did not identify its "
            f"sync-template skill version, and templates/ownership.json declares "
            f"requires_skill \"{spec}\". Two callers arrive here, and the remedy differs: "
            f"-- IF YOU ARE THE sync-template SKILL: the body this session loaded predates "
            f"{floor} and has no instruction to identify itself. A running session keeps the "
            f"body it read at startup, so the file on disk may already be current while this "
            f"session is not. Copy user-level-reference/skills/sync-template/SKILL.md from "
            f"toolkit tag {floor} or later into ~/.claude/skills/sync-template/SKILL.md if it "
            f"is not already there, then START A FRESH SESSION. Re-copying without restarting "
            f"changes nothing for this session. "
            f"-- IF YOU ARE NOT THE SKILL (a harness, a direct tool call, a human): pass "
            f"skill_version=\"{SKILL_BYPASS_SENTINEL}\" exactly. Case-sensitive; near-misses "
            f"refuse by design. "
            f"dry_run=True previews without migrating and is never refused."
        ), "", False
    m = SKILL_TAG_RE.match(claimed)
    if not m:
        return False, (
            f"template_migrate_manifest refused: skill_version {claimed!r} is not tag-shaped. "
            f"templates/ownership.json declares requires_skill \"{spec}\", so the value must "
            f"read like \"v3.1.3\" -- with the leading 'v', which is what makes it a tag name "
            f"rather than a bare version number. This server does not normalise the two "
            f"together. Pass the marker from the top of the skill body you are executing, or "
            f"skill_version=\"{SKILL_BYPASS_SENTINEL}\" if you are not that skill."
        ), "", False
    if tuple(int(g) for g in m.groups()) < tuple(int(g) for g in SKILL_TAG_RE.match(floor).groups()):
        return False, (
            f"template_migrate_manifest refused: caller reported sync-template skill "
            f"{claimed}, and templates/ownership.json declares requires_skill {spec}. That "
            f"skill body predates the migration step that reports which keep-mine deviations "
            f"this migration drops, so migrating under it would lose them silently. Fix: "
            + _SKILL_REMEDY.format(tag=floor)
        ), "", False
    return True, "", "", False


def requires_server_satisfied(spec: str, server_version: str) -> tuple[bool, str]:
    """Only the `>=X.Y.Z` form the toolkit writes is supported (review §2.5)."""
    spec = (spec or "").strip()
    if not spec:
        return True, ""
    if not spec.startswith(">="):
        return False, f"requires_server {spec!r}: only the '>=X.Y.Z' form is supported"
    try:
        floor = parse_version(spec[2:])
        have = parse_version(server_version)
    except ValueError as e:
        return False, f"requires_server {spec!r}: {e}"
    if have < floor:
        return False, (
            f"manifest requires server {spec}, this server is {server_version} -- "
            "upgrade mcp-dev-servers and restart the MCP server"
        )
    return True, ""


def unknown_top_level_keys(manifest: dict) -> list[str]:
    return sorted(k for k in manifest if k not in KNOWN_TOP_LEVEL_V3)


def raise_floor(existing: str | None) -> tuple[str, dict | None, str | None]:
    """Tighten a `requires_server` floor to the splice floor. Never loosen it.

    Returns (floor_to_write, raised_report_or_None, warning_or_None).

    Monotonic by construction, and that is what makes it safe to touch a
    field the toolkit's emitter owns: it can only move in the direction that
    protects. A consumer who pinned a STRICTER floor has made a decision and
    it is kept -- silently relaxing it would be the same class of defect as
    the one this floor exists to close. A consumer sitting on ">=0.3.0" is
    permitting a server that eats their region, which is not a configuration
    worth preserving; those are the earliest adopters, who migrated before
    the hazard was understood and whom no emitter change reaches.

    A floor this server cannot parse is left exactly as found and warned
    about: it already makes load refuse, and rewriting it would silently
    repair a manifest the server does not understand.
    """
    target = f">={MIN_SERVER_FOR_V3}"
    spec = (existing or "").strip()
    if not spec:
        return target, None, None
    if not spec.startswith(">="):
        return spec, None, (
            f"requires_server {spec!r} is not the '>=X.Y.Z' form -- left unchanged; "
            "it will refuse at load until the emitter writes a floor this server can read"
        )
    try:
        have = parse_version(spec[2:])
        floor = parse_version(MIN_SERVER_FOR_V3)
    except ValueError:
        return spec, None, (
            f"requires_server {spec!r} does not parse as '>=X.Y.Z' -- left unchanged"
        )
    if have >= floor:
        return spec, None, None
    return target, {"from": spec, "to": target}, None


KNOWN_FILE_KEYS_V3 = {"hash", "ownership"}
# The named v2 per-file fields migration drops (review §2.10). Anything else
# on an entry is a consumer annotation: preserved and reported (review §12).
SUPERSEDED_V2_FILE_KEYS = {
    "templateHash", "templateRawHash", "localHash", "locallyModified",
    "localPartHash", "templatePartHashAtSync", "resolution",
}


def carry_unknown_file_keys(old_entry: dict, new_entry: dict) -> tuple[dict, list[str]]:
    """Merge the unknown keys of `old_entry` into `new_entry`; return the
    merged entry and the sorted key names carried over."""
    carried = sorted(
        k for k in (old_entry or {})
        if k not in KNOWN_FILE_KEYS_V3 and k not in SUPERSEDED_V2_FILE_KEYS
    )
    merged = dict(new_entry)
    for k in carried:
        merged[k] = old_entry[k]
    return merged, carried


# -------------------------
# Key audit (once files with "audit": "keys")
# -------------------------

KEY_LINE_RE = re.compile(r"^(?:[-*+][ \t]+)?\*\*(?P<key>[^*\n]+?)\*\*:[ \t]*(?P<val>.*)$", re.M)
PLACEHOLDER_RE = re.compile(r"\{\{.*?\}\}")


def parse_keys(text: str) -> dict[str, str]:
    keys: dict[str, str] = {}
    for m in KEY_LINE_RE.finditer(text or ""):
        key = m.group("key").strip()
        if key not in keys:
            keys[key] = m.group("val").strip()
    return keys


def find_key(consumer_keys: dict[str, str], key: str, rule: dict) -> list[str]:
    """Names in the consumer that satisfy `key`: exact, qualified `key (...)`,
    or a declared alias (review §7b). Exact first, then in document order.
    Used for OPTIONAL keys; required keys use exact_holdings."""
    matches = []
    if key in consumer_keys:
        matches.append(key)
    qualified = re.compile(r"^" + re.escape(key) + r" \(.+\)$")
    aliases = set((rule.get("aliases") or {}).get(key, []))
    for name in consumer_keys:
        if name == key:
            continue
        if qualified.match(name) or name in aliases:
            matches.append(name)
    return matches


def _norm_ws(s: str) -> str:
    return " ".join((s or "").split())


def exact_holdings(consumer_keys: dict[str, str], key: str, rule: dict) -> list[str]:
    """The hook's own match for a REQUIRED key: exact `**Key**:` or one of its
    deprecated spellings (review §11b). Qualified/alias forms do not count."""
    deprecated_map = dict(rule.get("deprecated_keys") or {})
    out = [key] if key in consumer_keys else []
    out += [old for old, new in deprecated_map.items() if new == key and old in consumer_keys]
    return out


def _hook_note(key: str, rule: dict) -> str:
    deprecated_map = dict(rule.get("deprecated_keys") or {})
    spellings = [f"**{key}**:"] + [f"**{old}**:" for old, new in deprecated_map.items() if new == key]
    return f"the hook matches {'/'.join(spellings)} exactly and will not read it"


def audit_keys(proj_text: str, tpl_text: str, tpl_at_sync_text: str | None, rule: dict,
               placeholders: dict | None = None) -> dict:
    proj = parse_keys(proj_text)
    tpl = parse_keys(tpl_text)
    tpl_sync = parse_keys(tpl_at_sync_text) if tpl_at_sync_text is not None else None
    required = list(rule.get("required_keys") or [])
    deprecated_map = dict(rule.get("deprecated_keys") or {})
    warnings: list[str] = []
    if tpl_sync is None:
        warnings.append("audit_base_unavailable")

    missing_required: list[str] = []
    qualified_only: list[dict] = []
    optional_absent: list[str] = []
    detail: dict[str, dict] = {}

    def _required(key: str) -> None:
        held = exact_holdings(proj, key, rule)
        if not held:
            loose = find_key(proj, key, rule)
            if loose:
                qualified_only.append({"key": key, "held_as": loose, "note": _hook_note(key, rule)})
            else:
                missing_required.append(key)
            return
        info = {
            "value": proj[held[0]],
            "matched_as": held,
            "template_value": tpl.get(key),
        }
        if tpl_sync is not None:
            at_sync = tpl_sync.get(key)
            info["template_value_at_sync"] = at_sync
            info["template_default_changed"] = _norm_ws(tpl.get(key) or "") != _norm_ws(at_sync or "")
            info["consumer_holds_old_default"] = (
                at_sync is not None and _norm_ws(proj[held[0]]) == _norm_ws(at_sync)
            )
        detail[key] = info

    for key in tpl:
        if key in required:
            _required(key)
        elif not find_key(proj, key, rule):
            optional_absent.append(key)

    # Required keys the template itself lacks are still required.
    for key in required:
        if key not in tpl:
            _required(key)

    placeholder_keys = sorted(k for k, val in proj.items() if PLACEHOLDER_RE.search(val))
    deprecated = [
        {"key": k, "replacement": deprecated_map[k]}
        for k in proj if k in deprecated_map
    ]
    # Placeholder VALUE correctness (review §10b): the key's value in the
    # once file versus the manifest placeholder that renders into CLAUDE.md.
    divergence = []
    ph = placeholders or {}
    for key, ph_name in (rule.get("placeholder_map") or {}).items():
        for name in find_key(proj, key, rule):
            ph_value = ph.get(ph_name)
            if ph_value is None or _norm_ws(proj[name]) != _norm_ws(ph_value):
                divergence.append({"key": name, "key_value": proj[name],
                                   "placeholder": ph_name, "placeholder_value": ph_value})
    return {
        "missing_required": missing_required,
        "qualified_only": qualified_only,
        "optional_absent": optional_absent,
        "placeholder_keys": placeholder_keys,
        "deprecated_keys": deprecated,
        "required": detail,
        "placeholder_key_divergence": divergence,
        "warnings": warnings,
    }


def gate_tokens(value: str) -> list[str]:
    """Tokenise a **Gate**:/**Test**: value the way run-gate.sh normalises it
    (review §11a): surrounding backticks off the whole value and each token,
    leading ./ dropped, a leading bash/sh token ignored."""
    value = (value or "").strip().strip("`").strip()
    toks = [core._normalize_path(t.strip("\"'`")) for t in value.split()]
    if toks and toks[0] in ("bash", "sh"):
        toks = toks[1:]
    out = []
    for t in toks:
        while t.startswith("./"):
            t = t[2:]
        if t:
            out.append(t)
    return out


def gate_refs(consumer_keys: dict[str, str], rule: dict, rules: OwnershipRules) -> list[dict]:
    """Direct gate self-reference (review §9a, §11a): a token in a required
    key's value that is a template-class path by the rules. Static and
    direct-only -- a wrapper that calls the hook from elsewhere passes."""
    out = []
    for key in rule.get("required_keys") or []:
        for name in exact_holdings(consumer_keys, key, rule):
            for tok in gate_tokens(consumer_keys[name]):
                if rules.class_of(rules.template_path_for(tok)) == "template":
                    out.append({"key": name, "path": tok})
    return out


def collect_gate_refs(pp: pathlib.Path, rules: OwnershipRules) -> tuple[list[dict], bool]:
    """(gate_self_reference hits, gate declared) over every audited once file
    whose pattern is a literal path."""
    hits: list[dict] = []
    declared = False
    for rule in rules.rules:
        if rule.get("audit") != "keys" or any(c in rule["pattern"] for c in "*?["):
            continue
        text = core._read_file(pp / rules.project_path_for(rule["pattern"]))
        if text is None:
            continue
        keys = parse_keys(text)
        if exact_holdings(keys, "Gate", rule):
            declared = True
        hits.extend(gate_refs(keys, rule, rules))
    return hits, declared


# -------------------------
# Orphans, template notes, encoding flags
# -------------------------

def static_prefix(pattern: str) -> str:
    segs = []
    for seg in core._normalize_path(pattern).split("/"):
        if any(c in seg for c in "*?["):
            break
        segs.append(seg)
    return "/".join(segs)


def find_orphans(project_root: pathlib.Path, rules: OwnershipRules,
                 manifest_keys: set[str], template_files: set[str]) -> list[str]:
    """Consumer files that match a template-class rule, sit in no manifest entry
    and are not shipped by the template (review §5b). Informational only."""
    found: set[str] = set()
    for rule in rules.template_class_rules():
        rx = glob_to_regex(rule["pattern"])
        root = project_root / static_prefix(rule["pattern"])
        if root.is_file():
            candidates = [root]
        elif root.is_dir():
            candidates = [p for p in root.rglob("*") if p.is_file()]
        else:
            continue
        for p in candidates:
            rel = core._normalize_path(str(p.relative_to(project_root)))
            if not rx.match(rel):
                continue
            # First match over ALL rules decides; a preceding `project` rule silences.
            if rules.class_of(rel) != "template":
                continue
            if rel in manifest_keys or rel in template_files:
                continue
            found.add(rel)
    return sorted(found)


def notes_hunks(tpl_at_sync: str, tpl_now: str) -> list[str]:
    """Hunks of the template-side diff that touch no **Key**: line (review §7c)."""
    from difflib import unified_diff
    lines = list(unified_diff(
        tpl_at_sync.splitlines(keepends=True), tpl_now.splitlines(keepends=True),
        fromfile="template@sync", tofile="template@now", n=1,
    ))
    hunks: list[list[str]] = []
    for line in lines:
        if line.startswith("@@"):
            hunks.append([line])
        elif hunks and not line.startswith(("---", "+++")):
            hunks[-1].append(line)
    out = []
    for h in hunks:
        # Key-line changes are the audit's business; drop them from the hunk
        # and keep it only if a non-key change remains (a MIXED hunk keeps
        # its note part -- panoscribe's shape).
        kept = [h[0]] + [
            l for l in h[1:]
            if not (l[:1] in "+-" and KEY_LINE_RE.match(l[1:].rstrip("\n")))
        ]
        if not any(l[:1] in "+-" for l in kept[1:]):
            continue
        out.append("".join(kept))
    return out


NO_FLAGS = {"bom": False, "crlf": False}


def read_with_flags(path: pathlib.Path) -> tuple[str | None, dict]:
    """Read once as bytes; return the text the way _read_file would see it
    (BOM stripped, CRLF/CR folded to LF) plus the encoding flags (review §8)."""
    try:
        data = path.read_bytes()
    except (FileNotFoundError, OSError):
        return None, dict(NO_FLAGS)
    flags = {"bom": data.startswith(b"\xef\xbb\xbf"), "crlf": b"\r\n" in data}
    text = data.decode("utf-8", errors="replace")
    if text.startswith("\ufeff"):
        text = text[1:]
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    return text, flags


def encoding_drift(proj_flags: dict, tpl_flags: dict) -> list[str]:
    return sorted(k for k in ("bom", "crlf") if bool(proj_flags.get(k)) != bool(tpl_flags.get(k)))


# -------------------------
# v3 status
# -------------------------

def _unified(a: str, b: str, fromfile: str, tofile: str) -> str:
    from difflib import unified_diff
    return "".join(unified_diff(
        a.splitlines(keepends=True), b.splitlines(keepends=True),
        fromfile=fromfile, tofile=tofile,
    ))


def diff_kind(diff: str) -> str:
    """"insertion" when the unified diff body carries only added lines,
    else "mixed" (review batch 10: a pure insertion outside the region is
    the case the skill can send to .claude/rules/project.md)."""
    added = removed = 0
    for line in (diff or "").splitlines():
        if line.startswith(("+++", "---", "@@")):
            continue
        if line.startswith("+"):
            added += 1
        elif line.startswith("-"):
            removed += 1
    return "insertion" if added and not removed else "mixed"


def template_status(entry_hash_hex: str, tpl_replaced: str | None,
                    proj_content: str | None) -> tuple[str, str | None]:
    """§7 statuses for a `template` entry. LOCAL_EDITED wins over
    TEMPLATE_UPDATED; local_diff is what the overwrite would discard
    (project -> current template)."""
    if tpl_replaced is None:
        return "TEMPLATE_DELETED", None
    if proj_content is None:
        return "TEMPLATE_UPDATED", None
    if core._sha256(proj_content) != entry_hash_hex:
        return "LOCAL_EDITED", _unified(tpl_replaced, proj_content, "template", "project")
    if core._sha256(tpl_replaced) != entry_hash_hex:
        return "TEMPLATE_UPDATED", None
    return "IDENTICAL", None


def splice_region(tpl_content: str, proj_content: str | None) -> tuple[str, bool]:
    """Put the project's PROJECT-CUSTOM region into the template content.

    Only when BOTH sides carry the markers -- a single-sided region is not
    project-owned, the same rule the v2 path applies. The toolkit ships
    CLAUDE.md as `template` class with the markers still in it and marker text
    promising that sync preserves what is between them, so the v3 apply path
    has to keep that promise too (toolkit v3.1 reversal).
    """
    if proj_content is None:
        return tpl_content, False
    _tpl_part, tpl_region = core._split_custom_region(tpl_content)
    _proj_part, proj_region = core._split_custom_region(proj_content)
    if tpl_region is None or proj_region is None or proj_region == tpl_region:
        return tpl_content, False
    return tpl_content.replace(tpl_region, proj_region, 1), True


def region_orphaned(tpl_replaced: str | None, proj_content: str | None) -> bool:
    """True when the project keeps a region the template has nowhere to hold.

    An apply then writes the template wholesale and the region leaves the
    working file (it survives in backup_dir, so this is recoverable rather
    than lost). The toolkit guards its own template with a consistency check,
    but that check cannot see a forked, locally edited, older or never-shipped
    template -- in those the server is the only thing in the loop, and the
    failure mode is data loss, so it is worth a field.
    """
    if proj_content is None or tpl_replaced is None:
        return False
    _proj_part, proj_region = core._split_custom_region(proj_content)
    _tpl_part, tpl_region = core._split_custom_region(tpl_replaced)
    return proj_region is not None and tpl_region is None


def markers_malformed(content: str | None) -> bool:
    """True when PROJECT-CUSTOM markers are present but do not form a region.

    BEGIN with no END, END with no BEGIN, or END before BEGIN. Such a file has
    no region to splice, so an apply replaces it whole and whatever the
    consumer put between the broken markers leaves the working file -- the
    same loss `region_orphaned` reports, arriving through a shape that is
    unparseable rather than absent.
    """
    if content is None:
        return False
    _part, region = core._split_custom_region(content)
    if region is not None:
        return False
    return core.CUSTOM_REGION_BEGIN in content or core.CUSTOM_REGION_END in content


def malformed_side(tpl_replaced: str | None, proj_content: str | None) -> str | None:
    """Which side carries broken markers: "project", "template", "both", None.

    The template side is reported too. A broken pair there is the toolkit's
    bug, but the consumer is the one who loses the region and the only party
    positioned to notice before the write.
    """
    in_tpl = markers_malformed(tpl_replaced)
    in_proj = markers_malformed(proj_content)
    if in_tpl and in_proj:
        return "both"
    if in_proj:
        return "project"
    if in_tpl:
        return "template"
    return None


def region_status(entry_hash_hex: str, tpl_replaced: str | None, proj_content: str | None,
                  base_provider) -> str | None:
    """Second opinion on a LOCAL_EDITED verdict when both sides carry the
    markers: a difference confined to the region is not drift.

    Returns the corrected status, or None to leave the verdict alone. The
    project part may match either the current template or the one held at
    sync -- the latter is what keeps a consumer whose template moved on from
    reading as drift. `base_provider` is called only when the cheap comparison
    is inconclusive, so the git lookup stays rare.
    """
    if proj_content is None or tpl_replaced is None:
        return None
    tpl_part, tpl_region = core._split_custom_region(tpl_replaced)
    proj_part, proj_region = core._split_custom_region(proj_content)
    if tpl_region is None or proj_region is None:
        return None
    if proj_part != tpl_part:
        base = base_provider()
        if base is None:
            return None
        base_part, base_region = core._split_custom_region(base)
        if base_region is None or proj_part != base_part:
            return None
    return "TEMPLATE_UPDATED" if core._sha256(tpl_replaced) != entry_hash_hex else "IDENTICAL"


def _git_commit_exists(repo: str, ref: str) -> bool:
    return core._run_git(["cat-file", "-e", f"{ref}^{{commit}}"], cwd=repo)["exit_code"] == 0


def resolve_base(manifest: dict, rel_path: str) -> tuple[str | None, str, str | None]:
    """Placeholder-replaced template content of `rel_path` at the held revision.

    Chain (review §6.4): template_commit (alias lastSynced) -> the
    template_version tag's commit -> unavailable. Never the current template.
    Returns (content, base_label, warning).
    """
    repo = core._template_repo_resolved(manifest)
    git_path = core._template_git_path(manifest, rel_path)
    placeholders = manifest.get("placeholders", {})
    candidates = []
    commit = manifest_commit(manifest)
    if commit and commit != "unknown":
        candidates.append(commit)
    tag = manifest.get("template_version")
    if tag:
        candidates.append(str(tag))
    for ref in candidates:
        if not _git_commit_exists(repo, ref):
            continue
        raw = core._git_show_file(repo, ref, git_path)
        if raw is not None:
            return core._apply_placeholders(raw, placeholders), ref, None
    return None, "unavailable", "migration_base_unavailable"


def compute_status_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules) -> dict:
    placeholders = manifest.get("placeholders", {})
    repo_root = core._resolve_path(manifest["templateRepo"])
    template_dir = core._get_template_dir(manifest)
    warnings = list(rules.warnings)
    files_status: dict[str, dict] = {}
    summary = {
        "identical": 0, "template_updated": 0, "local_edited": 0,
        "template_deleted": 0, "present": 0, "missing": 0,
    }

    for proj_rel, entry in manifest.get("files", {}).items():
        proj_rel = core._normalize_path(proj_rel)
        tpl_rel = rules.template_path_for(proj_rel)
        ownership = entry.get("ownership") or rules.class_of(tpl_rel) or "template"
        tpl_raw, tpl_flags = read_with_flags(core._template_file_path(manifest, tpl_rel))
        tpl_replaced = core._apply_placeholders(tpl_raw, placeholders) if tpl_raw is not None else None
        proj_content, proj_flags = read_with_flags(pp / proj_rel)
        info: dict = {"ownership": ownership, "template_path": tpl_rel,
                      "project_file_missing": proj_content is None,
                      "encoding_drift": (encoding_drift(proj_flags, tpl_flags)
                                         if proj_content is not None and tpl_raw is not None else [])}

        if ownership == "once":
            if proj_content is not None:
                status = "PRESENT"
                rule = rules.rule_for(tpl_rel) or {}
                if rule.get("audit") == "keys" and tpl_replaced is not None:
                    base, base_label, warn = resolve_base(manifest, tpl_rel)
                    audit = audit_keys(proj_content, tpl_replaced, base, rule, placeholders)
                    audit["base"] = base_label
                    if base is not None:
                        audit["template_notes_changed"] = notes_hunks(base, tpl_replaced)
                    info["key_audit"] = audit
            elif tpl_replaced is None:
                status = "TEMPLATE_DELETED"
            else:
                status = "MISSING"
        else:
            entry_hash = parse_hash(entry.get("hash", ""))
            status, local_diff = template_status(entry_hash, tpl_replaced, proj_content)
            if status == "LOCAL_EDITED":
                corrected = region_status(
                    entry_hash, tpl_replaced, proj_content,
                    lambda: resolve_base(manifest, tpl_rel)[0],
                )
                if corrected is not None:
                    status, local_diff = corrected, None
                    info["region_only"] = True
            if local_diff is not None:
                info["local_diff"] = local_diff
                info["local_diff_kind"] = diff_kind(local_diff)
            # Present only in the hazardous case, so callers key on presence.
            if region_orphaned(tpl_replaced, proj_content):
                info["region_orphaned"] = True
            broken = malformed_side(tpl_replaced, proj_content)
            if broken is not None:
                info["region_markers_malformed"] = broken
            info["template_changed"] = (
                tpl_replaced is not None and core._sha256(tpl_replaced) != parse_hash(entry.get("hash", ""))
            )

        info["status"] = status
        summary[status.lower()] += 1
        files_status[proj_rel] = info

    # New template files: template/once paths absent from the manifest.
    tracked = {core._normalize_path(k) for k in manifest.get("files", {})}
    scanned = core._scan_template_files(template_dir, repo_root)
    gitignore = template_dir / "gitignore"
    if gitignore.is_file():
        scanned.append("gitignore")   # _scan_template_files skips it; the rules decide now
    new_files, unclassified = [], []
    template_files: set[str] = set()
    for tpl_rel in sorted(set(scanned)):
        cls = rules.class_of(tpl_rel)
        proj_rel = rules.project_path_for(tpl_rel)
        template_files.add(proj_rel)
        if proj_rel in tracked:
            continue
        if cls in ("template", "once"):
            new_files.append(proj_rel)
        elif cls is None:
            unclassified.append(tpl_rel)

    orphans = find_orphans(pp, rules, tracked, template_files)
    deleted = [p for p, s in files_status.items() if s["status"] == "TEMPLATE_DELETED"]
    gate_hits, gate_declared = collect_gate_refs(pp, rules)

    return {
        "manifest_version": 3,
        "template_commit": core._git_head(core._template_repo_resolved(manifest)) or "unknown",
        "template_version": manifest.get("template_version"),
        "last_synced_commit": manifest_commit(manifest),
        "files": files_status,
        "new_template_files": sorted(new_files),
        "unclassified_template_files": sorted(unclassified),
        "orphans": orphans,
        "deleted_template_files": deleted,
        "gate_self_reference": gate_hits,
        "gate_unverified": gate_declared,
        "summary": summary,
        "warnings": warnings,
    }


# -------------------------
# v3 apply
# -------------------------

def write_backup(backup_dir: pathlib.Path, proj_rel: str, pre_image: str, diff: str) -> dict:
    target = backup_dir / core._normalize_path(proj_rel)
    target.parent.mkdir(parents=True, exist_ok=True)
    pre = target.with_name(target.name + ".pre-sync")
    dif = target.with_name(target.name + ".diff")
    core._write_file_atomic(pre, pre_image)
    core._write_file_atomic(dif, diff)
    return {"pre_sync": str(pre), "diff": str(dif)}


def apply_file_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules, file_path: str,
                  source: str, content: str, backup_dir: str) -> dict:
    proj_rel = core._normalize_path(file_path)
    tpl_rel = rules.template_path_for(proj_rel)
    entry = manifest.get("files", {}).get(proj_rel) or manifest.get("files", {}).get(file_path) or {}
    ownership = entry.get("ownership") or rules.class_of(tpl_rel)
    if ownership is None:
        return {"error": f"{proj_rel}: no ownership rule matches {tpl_rel!r} in {OWNERSHIP_FILE} -- not applied"}
    if ownership == "project":
        return {"error": f"{proj_rel}: ownership is 'project'; the server never writes it"}
    if source not in ("template", "provided"):
        if source == "skip":
            return {"error": f"source='skip' is refused under manifest v3 for {ownership}-class files: "
                             "there is no keep-mine class -- fix the template or declare a key"}
        return {"error": f"Unknown source: {source}"}
    if source == "provided" and not content:
        return {"error": "source='provided' requires content parameter"}
    for hit in collect_gate_refs(pp, rules)[0]:
        if hit["path"] == proj_rel:
            return {"error": f"gate_self_reference: **{hit['key']}**: points at template-class {proj_rel}; "
                             "move the logic to a non-template path (e.g. scripts/gate.sh) and point the key there"}

    placeholders = manifest.get("placeholders", {})
    tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
    tpl_replaced = core._apply_placeholders(tpl_raw, placeholders) if tpl_raw is not None else None
    if source == "template" and tpl_replaced is None:
        return {"error": f"Template file not found: {tpl_rel}"}
    target = pp / proj_rel
    proj_existing = core._read_file(target)
    write_content = tpl_replaced if source == "template" else content

    if ownership == "once":
        if proj_existing is not None:
            return {
                "file_path": proj_rel, "action": "kept", "ownership": "once",
                "manifest_entry": {"ownership": "once"}, "bytes_written": 0,
                "backup": None, "local_edit_overwritten": False,
            }
        target.parent.mkdir(parents=True, exist_ok=True)
        core._write_file_atomic(target, write_content)
        return {
            "file_path": proj_rel, "action": f"created_from_{source}", "ownership": "once",
            "manifest_entry": {"ownership": "once"},
            "bytes_written": len(write_content.encode("utf-8")),
            "backup": None, "local_edit_overwritten": False,
        }

    # template class
    backup = None
    local_edit = False
    region_preserved = False
    if source == "template" and tpl_replaced is not None:
        write_content, region_preserved = splice_region(tpl_replaced, proj_existing)
    if proj_existing is not None:
        baseline = parse_hash(entry.get("hash", ""))
        if baseline:
            status, local_diff = template_status(baseline, tpl_replaced, proj_existing)
            if status == "LOCAL_EDITED":
                corrected = region_status(
                    baseline, tpl_replaced, proj_existing,
                    lambda: resolve_base(manifest, tpl_rel)[0],
                )
                if corrected is not None:
                    status, local_diff = corrected, None
            local_edit = status == "LOCAL_EDITED"
        else:
            # No baseline (new file the project already has): any difference
            # from what will be written is a local edit.
            local_edit = proj_existing != write_content
            local_diff = _unified(write_content, proj_existing, "template", "project") if local_edit else None
        if local_edit and proj_existing != write_content:
            if not backup_dir:
                return {"error": f"{proj_rel} is LOCAL_EDITED; refusing to overwrite without backup_dir "
                                 "(the pre-image and diff must be saved first)"}
            backup = write_backup(pathlib.Path(backup_dir).resolve(), proj_rel, proj_existing, local_diff or "")
        elif local_edit:
            local_edit = False   # content already equals the target; nothing is lost

    orphaned = region_orphaned(tpl_replaced, proj_existing)
    target.parent.mkdir(parents=True, exist_ok=True)
    core._write_file_atomic(target, write_content)
    hash_hex = core._sha256(tpl_replaced) if tpl_replaced is not None else core._sha256(write_content)
    result = {
        "file_path": proj_rel,
        "action": ("created" if proj_existing is None else "written") + f"_from_{source}",
        "ownership": "template",
        "manifest_entry": {"hash": format_hash(hash_hex), "ownership": "template"},
        "bytes_written": len(write_content.encode("utf-8")),
        "backup": backup,
        "local_edit_overwritten": local_edit,
        "region_preserved": region_preserved,
    }
    if orphaned:
        # Present only in the hazardous case, so callers key on presence.
        result["region_orphaned"] = True
    broken = malformed_side(tpl_replaced, proj_existing)
    if broken is not None:
        result["region_markers_malformed"] = broken
    return result


# -------------------------
# v3 finalize
# -------------------------

def _tree_id(repo: str, ref: str, path: str) -> str | None:
    r = core._run_git(["rev-parse", f"{ref}:{path}"], cwd=repo)
    return r["stdout"].strip() if r["exit_code"] == 0 else None


def derive_template_version(repo: str, commit: str, tracked_paths: list[str]) -> tuple[str | None, str | None]:
    """Nearest reachable tag whose tree over the tracked paths equals the
    tree at `commit` (review §6.3). Never `git describe`."""
    if core._run_git(["rev-parse", "--is-inside-work-tree"], cwd=repo)["exit_code"] != 0:
        return None, "template_repo_not_git"
    r = core._run_git(["tag", "--merged", commit, "--sort=-v:refname"], cwd=repo)
    if r["exit_code"] != 0:
        return None, "untagged_template_tree"
    want = {p: _tree_id(repo, commit, p) for p in tracked_paths}
    for tag in [t.strip() for t in r["stdout"].splitlines() if t.strip()]:
        if all(_tree_id(repo, f"{tag}^{{commit}}", p) == want[p] for p in tracked_paths):
            return tag, None
    return None, "untagged_template_tree"


def finalize_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules,
                applied: list, new: list, deleted: list) -> dict:
    invalid: list[str] = []
    for item in applied:
        fp = item.get("file_path", "")
        entry = item.get("manifest_entry", {})
        norm = core._normalize_path(fp)
        if not fp or not norm.strip("/") or ".." in norm.split("/"):
            invalid.append(f"invalid file_path: {fp!r}")
            continue
        if entry.get("ownership") not in ("template", "once"):
            invalid.append(f"{fp}: ownership must be 'template' or 'once'")
        if entry.get("ownership") == "template" and not HASH_RE.match(entry.get("hash", "") or ""):
            invalid.append(f"{fp}: hash is not sha256:<64 lowercase hex>")
    if invalid:
        return {"error": "applied_files validation failed — manifest NOT written", "invalid_entries": invalid}

    files = {core._normalize_path(k): v for k, v in manifest.get("files", {}).items()}
    placeholders = manifest.get("placeholders", {})
    warnings = list(rules.warnings)

    updated = 0
    unknown_files: list[dict] = []
    for item in applied:
        fp = core._normalize_path(item["file_path"])
        entry = item["manifest_entry"]
        if entry["ownership"] == "template":
            new_entry = {"hash": format_hash(parse_hash(entry["hash"])), "ownership": "template"}
        else:
            new_entry = {"ownership": "once"}
        # Per-file annotations survive by server policy, from the on-disk
        # entry -- the applied entry never carries them (review §12).
        files[fp], carried = carry_unknown_file_keys(files.get(fp, {}), new_entry)
        if carried:
            unknown_files.append({"path": fp, "keys": carried})
        updated += 1
    consumed = sorted(
        ({"path": core._normalize_path(i["file_path"]),
          "hash": files[core._normalize_path(i["file_path"])].get("hash")} for i in applied),
        key=lambda d: d["path"],
    )

    added = 0
    for fp in new:
        fp = core._normalize_path(fp)
        if fp in files:
            continue
        tpl_rel = rules.template_path_for(fp)
        cls = rules.class_of(tpl_rel)
        if cls == "once":
            files[fp] = {"ownership": "once"}
        elif cls == "template":
            tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
            if tpl_raw is None:
                warnings.append(f"new file {fp}: template file {tpl_rel} not found -- skipped")
                continue
            files[fp] = {"hash": format_hash(core._sha256(core._apply_placeholders(tpl_raw, placeholders))),
                         "ownership": "template"}
        else:
            warnings.append(f"new file {fp}: no template/once rule -- skipped")
            continue
        added += 1

    explicit = {core._normalize_path(p) for p in deleted if isinstance(p, str) and p}
    dropped = []
    for fp in list(files):
        if fp in explicit:
            del files[fp]
            dropped.append(fp)
            continue
        if core._template_file_path(manifest, rules.template_path_for(fp)).is_file():
            continue
        if (pp / fp).exists():
            continue
        del files[fp]
        dropped.append(fp)

    repo = core._template_repo_resolved(manifest)
    head = core._run_git(["rev-parse", "HEAD"], cwd=repo)
    commit = head["stdout"].strip() if head["exit_code"] == 0 else manifest_commit(manifest)
    version, warn = derive_template_version(repo, commit, rules.tracked_paths)
    if warn:
        warnings.append(warn)

    out = {k: v for k, v in manifest.items() if k not in ("version", "lastSynced")}
    out["manifest_version"] = MANIFEST_VERSION_V3
    out["template_version"] = version
    out["template_commit"] = commit
    out["requires_server"], raised, floor_warning = raise_floor(manifest.get("requires_server"))
    if floor_warning:
        warnings.append(floor_warning)
    out["files"] = dict(sorted(files.items()))
    unknown = unknown_top_level_keys(out)

    manifest_path = pp / ".claude" / "template-manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    core._write_file_atomic(manifest_path, json.dumps(out, indent=2, ensure_ascii=False))
    return {
        "manifest_path": ".claude/template-manifest.json",
        "manifest_version": 3,
        "template_commit": commit,
        "template_version": version,
        "files_updated": updated,
        "files_added": added,
        "files_dropped": len(dropped),
        "dropped_entries": sorted(dropped),
        "unknown_keys": unknown,
        "unknown_file_keys": sorted(unknown_files, key=lambda d: d["path"]),
        **({"requires_server_raised": raised} if raised else {}),
        "consumed_entries": len(consumed),
        "consumed": consumed,
        "warnings": warnings,
        "manifest_written": True,
    }


# -------------------------
# v2 -> v3 migration
# -------------------------

MIGRATION_MARKER = "<!-- template-sync: project-owned; migrated from CLAUDE.md at"


def build_project_md(hunks: str, base_label: str, template_version: str) -> str:
    """Seed .claude/rules/project.md.

    The PROJECT-CUSTOM region is NOT copied here. Under the toolkit v3.1
    reversal the region stays in CLAUDE.md, so copying it would not relocate
    it, it would duplicate it -- and the duplicate is the dangerous half,
    because an unscoped project.md is delivered to no agent. Out-of-region
    edits are still reported, since an apply does discard those.
    """
    rendered = "no" if base_label == "unavailable" else "yes"
    out = [
        "# Project instructions",
        f"{MIGRATION_MARKER} {template_version}; migration-base: {base_label}; rendered: {rendered} -->",
        "",
    ]
    if hunks.strip():
        out += [
            "## Migrated from CLAUDE.md — review, then keep or delete",
            "```diff",
            hunks.rstrip("\n"),
            "```",
            "",
        ]
    return "\n".join(out)


def _region_body(region_block: str | None) -> str | None:
    """Inner text of a PROJECT-CUSTOM block (markers stripped)."""
    if region_block is None:
        return None
    lines = region_block.splitlines()
    inner = [l for l in lines if core.CUSTOM_REGION_BEGIN not in l and core.CUSTOM_REGION_END not in l]
    return "\n".join(inner)


def migrate_v2_to_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules) -> dict:
    warnings = list(rules.warnings)
    placeholders = manifest.get("placeholders", {})
    repo = core._template_repo_resolved(manifest)

    # Steps 1-2: region + out-of-region hunks against the held, rendered base.
    proj_claude = core._read_file(pp / "CLAUDE.md") or ""
    proj_part, proj_region = core._split_custom_region(proj_claude)
    base, base_label, warn = resolve_base(manifest, "CLAUDE.md")
    if warn:
        warnings.append(warn)
    hunks = ""
    hunk_count = 0
    region_body = _region_body(proj_region)
    region_was_seed = None
    if base is not None:
        base_part, base_region = core._split_custom_region(base)
        hunks = _unified(base_part, proj_part, f"CLAUDE.md@{base_label}", "CLAUDE.md@project")
        hunk_count = sum(1 for l in hunks.splitlines() if l.startswith("@@"))
        # The toolkit's own seed is not the consumer's content (review §9b).
        if region_body is not None and base_region is not None:
            region_was_seed = _norm_ws(region_body) == _norm_ws(_region_body(base_region) or "")
            if region_was_seed:
                region_body = None
    gate_hits, gate_declared = collect_gate_refs(pp, rules)

    # Step 4: the v3 manifest.
    files: dict[str, dict] = {}
    dropped: list[str] = []
    redundant: list[str] = []
    unknown_files: list[dict] = []
    # v3 has no keep-mine class, so `resolution` is dropped by design (review
    # §2.8). Dropping it SILENTLY is the defect: the rewritten entry records
    # the template's hash for a file that still holds the consumer's
    # deviation, so the next status reports drift and the next apply
    # overwrites it, while the consumer reads a successful migration and
    # learns nothing. Migration is careful with keys it does not understand;
    # it must be at least as loud about the one it does.
    dropped_resolutions: list[dict] = []
    dropped_file_keys: list[dict] = []
    for proj_rel, entry in manifest.get("files", {}).items():
        proj_rel = core._normalize_path(proj_rel)
        tpl_rel = rules.template_path_for(proj_rel)
        cls = rules.class_of(tpl_rel)
        if entry.get("resolution"):
            # The class the file lands in is what decides whether the dropped
            # record matters: `template` means the next apply overwrites the
            # deviation, `once` means apply KEEPS the consumer's file (0 bytes
            # written), and `project`/null means the server never writes it at
            # all. Reporting the row without the class leaves the caller to join
            # against the returned manifest, and a caller who skips the join
            # warns about files v3 already protects -- measured on a live
            # consumer whose four deviation-bearing entries were all safe. False
            # alarms are not a lesser failure here: they teach a consumer to
            # skim the one warning that is real.
            dropped_resolutions.append({"path": proj_rel, "resolution": entry["resolution"],
                                        "ownership": cls})
        new_entry = None
        if cls == "template":
            hex_digest = parse_hash(entry.get("templateHash", ""))
            if hex_digest:
                new_entry = {"hash": format_hash(hex_digest), "ownership": "template"}
            else:
                tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
                new_entry = {"hash": format_hash(core._sha256(core._apply_placeholders(tpl_raw or "", placeholders))),
                             "ownership": "template"}
                warnings.append(f"{proj_rel}: no templateHash in v2 entry -- baseline set to the current template")
        elif cls == "once":
            new_entry = {"ownership": "once"}
        if new_entry is not None:
            files[proj_rel], carried = carry_unknown_file_keys(entry, new_entry)
            if carried:
                unknown_files.append({"path": proj_rel, "keys": carried})
        else:
            dropped.append(proj_rel)
            # carry_unknown_file_keys runs only when a new entry is built, so an
            # annotation on a DROPPED entry was neither carried nor reported:
            # dropped_entries gave a bare path and the key left no trace in any
            # response. Same silent-loss shape as the keep-mine record, in the
            # branch nobody looked at -- and unobservable without this field,
            # which is why "no consumer has hit it" and "no consumer could tell
            # us" were the same sentence. The VALUES are not lost: the
            # pre-migration manifest is copied to backup_dir before any write.
            annotations = sorted(
                k for k in entry
                if k not in KNOWN_FILE_KEYS_V3 and k not in SUPERSEDED_V2_FILE_KEYS
            )
            if annotations:
                dropped_file_keys.append({"path": proj_rel, "keys": annotations})
            on_disk = core._read_file(pp / proj_rel)
            if on_disk is not None:
                held, _label, _w = resolve_base(manifest, tpl_rel)
                if held is not None and held == on_disk:
                    redundant.append(proj_rel)

    commit = manifest_commit(manifest)
    version, vwarn = derive_template_version(repo, commit, rules.tracked_paths) if commit else (None, "untagged_template_tree")
    if vwarn:
        warnings.append(vwarn)
    new_manifest = {k: v for k, v in manifest.items() if k not in ("version", "lastSynced", "files")}
    new_manifest["manifest_version"] = MANIFEST_VERSION_V3
    new_manifest["template_version"] = version
    new_manifest["template_commit"] = commit
    new_manifest["requires_server"] = f">={MIN_SERVER_FOR_V3}"
    new_manifest["files"] = dict(sorted(files.items()))

    # Step 3: project.md, unless the consumer already has one.
    existing = core._read_file(pp / PROJECT_MD)
    project_md = None
    if existing is None:
        project_md = build_project_md(hunks, base_label, "v3.1.0")

    return {
        "manifest": new_manifest,
        "dropped_entries": sorted(dropped),
        "dropped_file_keys": sorted(dropped_file_keys, key=lambda d: d["path"]),
        "dropped_resolutions": sorted(dropped_resolutions, key=lambda d: d["path"]),
        "redundant_project_file": sorted(redundant),
        "project_md": project_md,
        "project_md_existing": existing is not None,
        "hunk_count": hunk_count,
        "migration_base": base_label,
        "region_was_seed": region_was_seed,
        "region_left_in_place": proj_region is not None,
        "region_bytes": len((_region_body(proj_region) or "").encode("utf-8")),
        "gate_self_reference": gate_hits,
        "gate_unverified": gate_declared,
        "unknown_keys": unknown_top_level_keys(new_manifest),
        "unknown_file_keys": sorted(unknown_files, key=lambda d: d["path"]),
        "warnings": warnings,
    }


def migrate_manifest(pp: pathlib.Path, backup_dir: str, dry_run: bool,
                     skill_version: str = "") -> dict:
    manifest, errors = core._load_manifest(pp)
    if manifest is None:
        return {"error": errors[0]}
    if errors:
        return {"error": "; ".join(errors)}
    if is_v3(manifest):
        return {"migrated": False, "dry_run": dry_run, "reason": "manifest is already v3 -- nothing to migrate"}
    # Only v2 has the fields this migration reads. A v1 entry carries no
    # localHash and may carry no templateHash, so migrating one sets the
    # baseline to the CURRENT template -- recording "identical" for a file the
    # consumer may have deviated in, which is the silent loss the whole v3 round
    # exists to stop. The version test matches template_load_manifest's, missing
    # key included: two readers disagreeing about what a manifest IS would be
    # worse than either answer. Checked after the v3 test, because a v3 manifest
    # has no `version` key at all.
    if manifest.get("version", 1) < 2:
        return {"error": "manifest is v1 (a missing `version` key reads as 1, as in "
                         "template_load_manifest); template_migrate_manifest migrates v2 -> v3 only. "
                         "A v1 entry has no localHash, so migrating it would set the baseline to the "
                         "current template and report a deviating file as identical. Run "
                         "template_load_manifest (which upgrades v1 to v2 in memory) and then "
                         "template_finalize_sync to persist the v2 manifest, then migrate."}
    rules = load_ownership(manifest["templateRepo"])
    if rules is None:
        return {"error": f"cannot migrate: {OWNERSHIP_FILE} not found in the template repo -- "
                         "the toolkit checkout predates v3.1"}
    # The skill floor. Refusals apply to WRITE mode only: dry_run is what the
    # toolkit's own step does first, precisely so a gate_self_reference surfaces
    # before a consumer is mid-sync, and blocking inspection behind a current
    # skill would break the step that makes the migration safe.
    ok, refusal, floor_warning, bypassed = skill_floor_satisfied(rules.requires_skill,
                                                                 skill_version)
    if not ok and not dry_run:
        return {"error": refusal, "skill_version": (skill_version or "").strip(),
                **({"skill_version_unknown": True} if not (skill_version or "").strip() else {})}

    plan = migrate_v2_to_v3(pp, manifest, rules)
    plan["dry_run"] = dry_run
    # Echoed as CLAIMED, never as verified -- no field here implies this server
    # checked something it cannot check.
    plan["skill_version"] = (skill_version or "").strip()
    if not plan["skill_version"]:
        plan["skill_version_unknown"] = True
    if bypassed:
        plan["skill_version_bypassed"] = True
    if floor_warning:
        plan["warnings"].append(floor_warning)
    if not ok:
        # dry_run proceeds, but says what a write would do.
        plan["warnings"].append("skill_version would refuse a write: " + refusal)
    plan["project_md_bytes"] = len((plan["project_md"] or "").encode("utf-8"))
    if dry_run:
        plan["migrated"] = False
        plan["backup"] = None
        plan["written"] = []
        return plan
    if plan["gate_self_reference"]:
        hit = plan["gate_self_reference"][0]
        return {"error": f"gate_self_reference: **{hit['key']}**: points at template-class {hit['path']}; "
                         "move the logic to a non-template path (e.g. scripts/gate.sh) and point the key "
                         "there, then migrate", "gate_self_reference": plan["gate_self_reference"]}
    if not backup_dir:
        return {"error": "backup_dir is required to migrate (pre-migration CLAUDE.md and manifest are copied there); "
                         "use dry_run=true to preview"}

    bdir = pathlib.Path(backup_dir).resolve()
    bdir.mkdir(parents=True, exist_ok=True)
    claude_bak = bdir / "CLAUDE.md.pre-migration"
    manifest_bak = bdir / "template-manifest.json.pre-migration"
    core._write_file_atomic(claude_bak, core._read_file(pp / "CLAUDE.md") or "")
    core._write_file_atomic(manifest_bak, core._read_file(pp / ".claude" / "template-manifest.json") or "")

    written = []
    if plan["project_md"] is not None:
        target = pp / PROJECT_MD
        target.parent.mkdir(parents=True, exist_ok=True)
        core._write_file_atomic(target, plan["project_md"])
        written.append(PROJECT_MD)
    core._write_file_atomic(pp / ".claude" / "template-manifest.json",
                            json.dumps(plan["manifest"], indent=2, ensure_ascii=False))
    written.append(".claude/template-manifest.json")

    plan["migrated"] = True
    plan["backup"] = {"claude_md": str(claude_bak), "manifest": str(manifest_bak)}
    plan["written"] = written
    return plan
