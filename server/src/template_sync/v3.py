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

# MIN_SERVER_FOR_V4 names the OLDEST server that can read a v4 manifest
# without applying a region-less CLAUDE.md over a v3 consumer -- the server
# that knows CLAUDE.md is template-owned under v4 (spec §7's v3-manifest
# window) and refuses to apply it while the consumer's manifest is still v3.
# It is NOT the current version and must not track VERSION, for the same
# reason MIN_SERVER_FOR_V3 above does not.
MIN_SERVER_FOR_V4 = "4.1.0"
MANIFEST_VERSION_V4 = 4

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
    "region_bytes_raw",
    "new_template_files_detail",
    "superseded_keys",
    "missing_declared_keys",
    "optional_absent_detail",
    "template_verify",
    "deleted_acknowledged",
    "registered_tools",
    "agent_grants",
)
# CAPABILITIES mixes three kinds of name -- a FIELD a response carries
# (local_diff_kind), a BEHAVIOUR (region_splice), and a TOOL that must be
# dispatchable (template_verify). Only the tool-shaped names are
# dispatch-checkable: test_template_sync_capabilities asserts each is in the
# live registry AND that no other capability name is a registered tool, so a
# new tool-shaped capability left out of this tuple is a red test.
TOOL_CAPABILITIES = ("template_verify",)
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

# `deletedAcknowledged`: repo-relative paths (sorted, deduplicated, `/`-
# separated) the project has decided to KEEP although the template no longer
# ships them (SKILL.md step 6). compute_status_v3 reports such a path
# ACKNOWLEDGED_KEPT instead of TEMPLATE_DELETED, and the entry stays in
# `files` -- if the template ever ships the file again, tracking resumes as
# TEMPLATE_UPDATED/LOCAL_EDITED like any other template-class entry.
# Keys starting "x-" are consumer-owned: never known, never dropped, never
# reported beyond unknown_keys.
KNOWN_TOP_LEVEL_V3 = {
    "manifest_version", "template_version", "template_commit", "lastSynced",
    "variant", "templateRepo", "placeholders", "requires_server", "files",
    "deletedAcknowledged",
    # v2 keys that migration removes; listed so they are never reported as unknown
    "version",
    # v4 declarations (spec §5 header, Decision 2): the paths are fixed today;
    # the keys exist so a v3 server refuses a v4 manifest by shape and a
    # future release can move them without a new top-level key.
    "instructions_file", "agent_grants",
}


def acknowledged_paths(manifest: dict) -> set[str]:
    return {core._normalize_path(p) for p in manifest.get("deletedAcknowledged", [])
            if isinstance(p, str) and p}


def is_v3(manifest: dict) -> bool:
    return manifest.get("manifest_version") == MANIFEST_VERSION_V3


def is_v4_manifest(manifest: dict) -> bool:
    return manifest.get("manifest_version") == MANIFEST_VERSION_V4


def manifest_supported(manifest: dict) -> bool:
    """True for a manifest_version this server can dispatch on -- 3 or 4.

    Acceptance only: sites that mean the v3 SHAPE specifically (the region
    splice, region_bytes) keep calling is_v3 directly."""
    return manifest.get("manifest_version") in (MANIFEST_VERSION_V3, MANIFEST_VERSION_V4)


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


def effective_requires_server_spec(manifest: dict) -> str:
    """The floor actually enforced for `manifest`, fed to requires_server_satisfied.

    A v3 manifest's declared `requires_server` is returned unchanged. A v4
    manifest is raised to at least MIN_SERVER_FOR_V4 regardless of what its
    own field says: migration always writes ">=4.1.0" there (spec §7 step
    1c), so a v4 manifest declaring less is either hand-edited or the
    product of a migration bug, and a server that merely satisfies the
    understated value would run the v4 splice/window logic it may predate.
    Never loosens a v4 manifest's own floor when it already reads at or
    above MIN_SERVER_FOR_V4 (a consumer may have pinned a stricter one).
    """
    declared = (manifest.get("requires_server") or "").strip()
    if not is_v4_manifest(manifest):
        return declared
    floor_spec = f">={MIN_SERVER_FOR_V4}"
    if not declared.startswith(">="):
        return floor_spec
    try:
        have = parse_version(declared[2:])
        floor = parse_version(MIN_SERVER_FOR_V4)
    except ValueError:
        return floor_spec
    return declared if have >= floor else floor_spec


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


# v2's client-derived version labels (v4.0.1, item 8 / R32-R33). Under v3
# these duplicate template_version/template_commit, which are SERVER-written
# at every finalize -- a client-derived copy of the same fact can only drift,
# never correct it, so this is the one exception to the preserve-unknown rule
# (review §12): every other unrecognised top-level key survives untouched.
SUPERSEDED_KEYS = ("lastSynced", "lastSyncedVersion", "lastSyncedVersionOf")


def drop_superseded(manifest: dict) -> list[str]:
    """Remove v2's client-derived version labels in place. Returns the keys
    actually present and dropped, in SUPERSEDED_KEYS order (already
    alphabetical). Callers run this BEFORE unknown_top_level_keys so a
    superseded key can never appear there -- it is gone by construction, not
    by exclusion."""
    dropped = [k for k in SUPERSEDED_KEYS if k in manifest]
    for k in dropped:
        del manifest[k]
    return dropped


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

    # missing_declared_keys (v4.0.1, item 2): every key the consumer's own
    # variant declares that the consumer does NOT hold in a form the hooks
    # read, collapsed from three sources into one list the skill can act on
    # without re-deriving it: a required key truly absent (reason "absent"),
    # a required key held only under a deprecated spelling -- exact_holdings
    # above already lets that satisfy missing_required, so it is reported
    # here under its CANONICAL name, not the spelling on disk (reason
    # "deprecated_spelling"), and any key whose proj value is still an
    # unfilled `{{...}}` token (reason "unfilled").
    # Ownership rule (penumbra): an OPTIONAL key that is simply absent is
    # reported once, in optional_absent(+detail) only -- never duplicated
    # here. The exclusion is not vacuous for "deprecated_spelling": an
    # optional key held only under a deprecated spelling has no exact/loose
    # match under its canonical name either, so it lands in BOTH
    # optional_absent (find_key does not know the old spelling) and this
    # loop unless excluded -- required/absent and unfilled cannot collide
    # with optional_absent by construction (missing_required only holds
    # required keys; placeholder_keys only holds keys the consumer DOES
    # have), but this one can and is exercised by a test.
    missing_declared_keys: list[dict] = []
    for key in missing_required:
        missing_declared_keys.append({"key": key, "reason": "absent", "template_default": tpl.get(key)})
    for old, new in deprecated_map.items():
        if old in proj and new not in optional_absent:
            missing_declared_keys.append(
                {"key": new, "reason": "deprecated_spelling", "template_default": tpl.get(new)})
    for key in placeholder_keys:
        if key not in optional_absent:
            missing_declared_keys.append(
                {"key": key, "reason": "unfilled", "template_default": tpl.get(key)})

    # optional_absent_detail (v4.0.1, item 18): one entry per key in
    # optional_absent, naming what staying absent means for THIS key --
    # `none_meaning` disagrees across keys today (measured from the hook
    # code, hooks/lib/git-cmd.sh and hooks/pre-commit-test.sh; see
    # templates/ownership.json's optional_keys) and must not be made
    # uniform by fiat. A key with no entry in the rule's `optional_keys`
    # falls back to the generic pair below.
    optional_rule_keys = rule.get("optional_keys") or {}
    optional_absent_detail = [
        {
            "key": key,
            "template_default": tpl.get(key),
            "effect_when_absent": (optional_rule_keys.get(key) or {}).get(
                "effect_when_absent", "feature off"),
            "none_meaning": (optional_rule_keys.get(key) or {}).get(
                "none_meaning", "not defined for this key"),
        }
        for key in optional_absent
    ]

    return {
        "missing_required": missing_required,
        "qualified_only": qualified_only,
        "optional_absent": optional_absent,
        "optional_absent_detail": optional_absent_detail,
        "placeholder_keys": placeholder_keys,
        "deprecated_keys": deprecated,
        "missing_declared_keys": missing_declared_keys,
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


# -------------------------
# v4 agent grants splice (spec §4, §5)
# -------------------------

class GrantsError(Exception):
    """.claude/agent-grants.json is malformed, or a token is not a valid
    mcp__<alias>__<tool> name, or a token names an UNGRANTABLE tool.
    Refuse-not-guess (ruling R-C): every agent path -- apply and status
    alike -- errors out rather than silently ignoring the defect."""


class GrantRefused(Exception):
    """A grant names an agent whose frontmatter carries no `tools:` line --
    that agent already inherits every tool including MCP, so a grant for it
    has nothing to extend. Never synthesises an allowlist."""

    def __init__(self, agent_name: str):
        self.agent_name = agent_name
        super().__init__(
            f"{agent_name} ships no `tools:` line and already inherits every tool -- "
            "remove the grant"
        )


AGENT_GRANTS_FILE = ".claude/agent-grants.json"
INSTRUCTIONS_FILE_DEFAULT = ".claude/project-instructions.md"
AGENTS_DIR_PREFIX = ".claude/agents/"

# mcp__<alias>__<tool>. Anything else is a malformed token (GrantsError).
# R-O (fix round 1): the alias segment admits UPPERCASE -- exactly check 50's
# own TOKEN_RE in scripts/verify-template-consistency.sh
# (`^mcp__[A-Za-z0-9_-]+__[a-z0-9_]+$`), so a real alias like MCP_DOCKER is
# expressible as a grant token at all (previously the shape check itself
# refused every MCP_DOCKER-family UNGRANTABLE_TOOLS entry before the
# UNGRANTABLE_TOOLS membership check was ever reached).
_GRANT_TOKEN_RE = re.compile(r"^mcp__[A-Za-z0-9_-]+__[a-z0-9_]+$")

# UNGRANTABLE_TOOLS is a HAND-WRITTEN literal (spec §4 decision), never
# derived from the withheld sets of shipped agents -- deriving it from the
# data it is meant to be a floor under would make the data equal itself and
# defeat the point of the check (reviewer). Three families: Agent itself
# (no coder spawns subagents), every registered template_* sync tool (a
# coder must never sync/verify/migrate the template that governs it), and
# the merge/PR tools the template withholds from coders (only reviewers and
# the PO merge). tests/test_template_sync_v4_grants.py asserts
# union(withheld sets of every shipped agent) subseteq UNGRANTABLE_TOOLS.
UNGRANTABLE_TOOLS = frozenset({
    "Agent",
    "mcp__template-sync-tools__template_load_manifest",
    "mcp__template-sync-tools__template_compute_status",
    "mcp__template-sync-tools__template_get_diff",
    "mcp__template-sync-tools__template_apply_file",
    "mcp__template-sync-tools__template_reverse_placeholders",
    "mcp__template-sync-tools__template_finalize_sync",
    "mcp__template-sync-tools__template_migrate_manifest",
    "mcp__template-sync-tools__template_check_cross_variant",
    "mcp__template-sync-tools__template_propagate_to_variants",
    "mcp__template-sync-tools__template_verify",
    "mcp__MCP_DOCKER__merge_pull_request",
    "mcp__github-tools__github_pr_auto_merge",
    "mcp__MCP_DOCKER__create_pull_request",
    "mcp__MCP_DOCKER__update_pull_request",
})


def load_grants(pp: pathlib.Path) -> dict[str, list[str]]:
    """Read .claude/agent-grants.json: {agent name: [mcp__alias__tool, ...]}.

    Absent file -> {} (no grants -- the splice is a no-op everywhere).
    Malformed (not JSON, wrong schema, `grants` not an object, a value not a
    list of validly-shaped tokens, or a token naming an UNGRANTABLE tool) ->
    GrantsError naming the defect (R-C: refuse, never guess).
    """
    raw = core._read_file(pp / AGENT_GRANTS_FILE)
    if raw is None:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise GrantsError(f"{AGENT_GRANTS_FILE} is not valid JSON: {e}")
    if not isinstance(data, dict):
        raise GrantsError(f"{AGENT_GRANTS_FILE}: top level must be a JSON object")
    if data.get("schema") != 1:
        raise GrantsError(f"{AGENT_GRANTS_FILE}: \"schema\" must be 1, got {data.get('schema')!r}")
    grants = data.get("grants")
    if not isinstance(grants, dict):
        raise GrantsError(f"{AGENT_GRANTS_FILE}: \"grants\" must be a JSON object")
    out: dict[str, list[str]] = {}
    for agent_name, tokens in grants.items():
        if not isinstance(tokens, list) or not all(isinstance(t, str) for t in tokens):
            raise GrantsError(
                f"{AGENT_GRANTS_FILE}: grants[{agent_name!r}] must be a list of strings")
        for tok in tokens:
            if not _GRANT_TOKEN_RE.match(tok):
                raise GrantsError(
                    f"{AGENT_GRANTS_FILE}: grants[{agent_name!r}] has a malformed token "
                    f"{tok!r} -- expected mcp__<alias>__<tool>")
            if tok in UNGRANTABLE_TOOLS:
                raise GrantsError(
                    f"{AGENT_GRANTS_FILE}: grants[{agent_name!r}] grants ungrantable tool {tok!r}")
        out[agent_name] = list(tokens)
    return out


def _frontmatter_body(text: str) -> str | None:
    """The text between an agent file's leading `---` markers, or None when
    the file does not open with a frontmatter block."""
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end == -1:
        return None
    return text[4:end]


_NAME_FIELD_RE = re.compile(r"^name:\s*(.*)$", re.M)
_TOOLS_LINE_RE = re.compile(r"^tools:[ \t]*(.*)$", re.M)


def agent_name_of(text: str) -> str | None:
    """The `name:` frontmatter field of an agent file's rendered content."""
    body = _frontmatter_body(text)
    if body is None:
        return None
    m = _NAME_FIELD_RE.search(body)
    return m.group(1).strip() or None if m else None


def splice_tools(agent_text: str, grants_for_agent: list[str]) -> str:
    """Append `grants_for_agent` to the agent's frontmatter `tools:` line,
    deduplicated, original order then grant order (spec §5).

    The `tools:` line must sit on ONE line inside the leading `---` block; a
    list form (nothing after the colon -- a YAML sequence follows on later
    lines) or a bare `*` wildcard -> GrantsError("unsupported tools: shape").
    An agent with NO `tools:` line already inherits every tool including MCP
    -- a grant for it has nothing to extend -> GrantRefused(agent_name),
    never a synthesised allowlist.
    """
    if not grants_for_agent:
        return agent_text
    body = _frontmatter_body(agent_text)
    agent_name = agent_name_of(agent_text) or "<unnamed agent>"
    if body is None:
        raise GrantRefused(agent_name)
    m = _TOOLS_LINE_RE.search(body)
    if m is None:
        raise GrantRefused(agent_name)
    value = m.group(1).strip()
    if value == "" or value == "*":
        raise GrantsError(f"{agent_name}: unsupported tools: shape ({m.group(0)!r})")
    original = [t.strip() for t in value.split(",") if t.strip()]
    merged = list(original)
    for tok in grants_for_agent:
        if tok not in merged:
            merged.append(tok)
    new_line = "tools: " + ", ".join(merged)
    abs_start = 4 + m.start()
    abs_end = 4 + m.end()
    return agent_text[:abs_start] + new_line + agent_text[abs_end:]


def template_content(pp: pathlib.Path, manifest: dict, rules: OwnershipRules,
                     proj_rel: str, tpl_raw: str | None) -> str | None:
    """Placeholder-rendered content of a template file AS IT APPLIES TO THIS
    PROJECT -- the ONE producer of `tpl_replaced` (spec §5, reviewer D3).
    None when `tpl_raw` is None (the template no longer ships the file).

    `rules` is accepted for signature uniformity with the callers (which
    always have manifest+rules together) and for callers that resolve
    `proj_rel` from a template-relative path via `rules.project_path_for` --
    it is not otherwise consulted here: the agents-directory test below is a
    plain path-prefix check, true regardless of ownership class.

    Splices per-agent tool grants into a `.claude/agents/*` file under a v4
    manifest whose agent-grants.json carries a non-empty entry for that
    agent's `name:` field. NO-OPS (placeholders only) for every other path,
    and for every manifest carrying no grants at all -- v2, v3, and a v4
    manifest whose grants file is empty or absent -- so the existing v2/v3
    regression suites are the witness that nothing else moved.
    """
    del rules  # see docstring
    if tpl_raw is None:
        return None
    placeholders = manifest.get("placeholders", {})
    rendered = core._apply_placeholders(tpl_raw, placeholders)
    if not is_v4_manifest(manifest):
        return rendered
    norm = core._normalize_path(proj_rel)
    if not norm.startswith(AGENTS_DIR_PREFIX):
        return rendered
    grants = load_grants(pp)
    if not grants:
        return rendered
    agent_name = agent_name_of(rendered)
    agent_grants = grants.get(agent_name) if agent_name else None
    if not agent_grants:
        return rendered
    return splice_tools(rendered, agent_grants)


def resolve_base(pp: pathlib.Path, manifest: dict, rules: OwnershipRules,
                 rel_path: str) -> tuple[str | None, str, str | None]:
    """template_content() of `rel_path` at the held revision.

    Chain (review §6.4): template_commit (alias lastSynced) -> the
    template_version tag's commit -> unavailable. Never the current template.
    Returns (content, base_label, warning). `rel_path` is TEMPLATE-relative
    (a tpl_rel); threaded to template_content via
    `rules.project_path_for(rel_path)` deliberately (H1) -- for an agent file
    the two happen to be equal today, but the base provider must not rely on
    that coincidence: a moved template-relative name would otherwise read
    the wrong grants entry, or none, silently.
    """
    repo = core._template_repo_resolved(manifest)
    git_path = core._template_git_path(manifest, rel_path)
    proj_rel = rules.project_path_for(rel_path)
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
            return template_content(pp, manifest, rules, proj_rel, raw), ref, None
    return None, "unavailable", "migration_base_unavailable"


# -------------------------
# The v3-manifest window (spec §7, ruling R-J)
# -------------------------
#
# A v4.1+ server serving a consumer whose manifest is still v3 is the
# mirror of v4.0's "door one": MIN_SERVER_FOR_V4 refuses an OLD server on a
# NEW (v4) manifest, but nothing stops a NEW server applying a region-less
# template CLAUDE.md over a v3 consumer whose project content still lives in
# the region -- unless CLAUDE.md specifically refuses until the consumer
# migrates. Detected against the CURRENT checkout's template, never the
# held commit (a v3 consumer's held commit always carries the region, so
# only the current templates/<variant>/CLAUDE.md can reveal that the
# toolkit itself has moved to v4.1): a v3 consumer synced from a pre-v4.1
# checkout is LEGACY, not in the window, and behaves exactly as today.
MIGRATION_REQUIRED_REMEDY = "migrate first (template_migrate_manifest, dry-run then backup_dir)"


def claude_md_window_active(manifest: dict, tpl_rel: str, tpl_raw: str | None) -> bool:
    """True exactly for CLAUDE.md, under a v3 manifest, when the CURRENT
    checkout's variant template carries no PROJECT-CUSTOM markers."""
    if tpl_rel != "CLAUDE.md" or not is_v3(manifest) or tpl_raw is None:
        return False
    return core.CUSTOM_REGION_BEGIN not in tpl_raw and core.CUSTOM_REGION_END not in tpl_raw


def compute_status_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules) -> dict:
    placeholders = manifest.get("placeholders", {})
    repo_root = core._resolve_path(manifest["templateRepo"])
    template_dir = core._get_template_dir(manifest)
    warnings = list(rules.warnings)
    files_status: dict[str, dict] = {}
    summary = {
        "identical": 0, "template_updated": 0, "local_edited": 0,
        "template_deleted": 0, "present": 0, "missing": 0,
        "acknowledged_kept": 0, "migration_required": 0,
    }
    acknowledged = acknowledged_paths(manifest)

    for proj_rel, entry in manifest.get("files", {}).items():
        proj_rel = core._normalize_path(proj_rel)
        tpl_rel = rules.template_path_for(proj_rel)
        ownership = entry.get("ownership") or rules.class_of(tpl_rel) or "template"
        tpl_raw, tpl_flags = read_with_flags(core._template_file_path(manifest, tpl_rel))

        if claude_md_window_active(manifest, tpl_rel, tpl_raw):
            proj_content, proj_flags = read_with_flags(pp / proj_rel)
            files_status[proj_rel] = {
                "ownership": ownership, "template_path": tpl_rel,
                "project_file_missing": proj_content is None,
                "encoding_drift": [],
                "status": "MIGRATION_REQUIRED",
                "remedy": MIGRATION_REQUIRED_REMEDY,
            }
            summary["migration_required"] += 1
            continue

        try:
            tpl_replaced = template_content(pp, manifest, rules, proj_rel, tpl_raw)
        except (GrantsError, GrantRefused) as e:
            # Refuse-not-guess (R-C): an apply/status ERROR for every agent
            # path -- abort the whole status computation rather than report
            # a partial or silently-degraded result for the other files.
            return {"error": str(e)}
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
                    base, base_label, warn = resolve_base(pp, manifest, rules, tpl_rel)
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
                    lambda: resolve_base(pp, manifest, rules, tpl_rel)[0],
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

        if status == "TEMPLATE_DELETED" and proj_rel in acknowledged:
            status = "ACKNOWLEDGED_KEPT"

        info["status"] = status
        summary[status.lower()] += 1
        files_status[proj_rel] = info

    # New template files: template/once paths absent from the manifest.
    tracked = {core._normalize_path(k) for k in manifest.get("files", {})}
    scanned = core._scan_template_files(template_dir, repo_root)
    gitignore = template_dir / "gitignore"
    if gitignore.is_file():
        scanned.append("gitignore")   # _scan_template_files skips it; the rules decide now
    new_files, new_files_detail, unclassified = [], [], []
    template_files: set[str] = set()
    for tpl_rel in sorted(set(scanned)):
        cls = rules.class_of(tpl_rel)
        proj_rel = rules.project_path_for(tpl_rel)
        template_files.add(proj_rel)
        if proj_rel in tracked:
            continue
        if cls in ("template", "once"):
            new_files.append(proj_rel)
            # new_template_files stays a list of project-path strings (pinned
            # at test_template_sync_v3_status.py:296); this is the additive,
            # parallel surface a caller uses to resolve each path's
            # template-relative name -- .gitignore -> gitignore included
            # (v4.0.1, item 3).
            new_files_detail.append({"path": proj_rel, "template_path": tpl_rel})
        elif cls is None:
            unclassified.append(tpl_rel)

    orphans = find_orphans(pp, rules, tracked, template_files)
    deleted = [p for p, s in files_status.items() if s["status"] == "TEMPLATE_DELETED"]
    gate_hits, gate_declared = collect_gate_refs(pp, rules)

    return {
        "manifest_version": manifest.get("manifest_version", MANIFEST_VERSION_V3),
        "template_commit": core._git_head(core._template_repo_resolved(manifest)) or "unknown",
        "template_version": manifest.get("template_version"),
        "last_synced_commit": manifest_commit(manifest),
        "files": files_status,
        "new_template_files": sorted(new_files),
        "new_template_files_detail": sorted(new_files_detail, key=lambda d: d["path"]),
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

    tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
    if claude_md_window_active(manifest, tpl_rel, tpl_raw):
        # The v3-manifest window (R-J): nothing is written, the region body
        # on disk is byte-identical before and after this call.
        return {"error": f"CLAUDE.md: {MIGRATION_REQUIRED_REMEDY}"}
    try:
        tpl_replaced = template_content(pp, manifest, rules, proj_rel, tpl_raw)
    except (GrantsError, GrantRefused) as e:
        # Refuse-not-guess (R-C): nothing is written; the manifest is untouched.
        return {"error": str(e)}
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
                    lambda: resolve_base(pp, manifest, rules, tpl_rel)[0],
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
                applied: list, new: list, deleted: list, acknowledged: list) -> dict:
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
            files[fp] = {"hash": format_hash(core._sha256(
                             template_content(pp, manifest, rules, fp, tpl_raw))),
                         "ownership": "template"}
        else:
            warnings.append(f"new file {fp}: no template/once rule -- skipped")
            continue
        added += 1

    explicit = {core._normalize_path(p) for p in deleted if isinstance(p, str) and p}

    ack_new = {core._normalize_path(p) for p in acknowledged if isinstance(p, str) and p}
    if ack_new:
        status_now = compute_status_v3(pp, manifest, rules)["files"]
        for p in sorted(ack_new):
            entry_status = status_now.get(p, {}).get("status")
            if p not in status_now or entry_status not in ("TEMPLATE_DELETED", "ACKNOWLEDGED_KEPT"):
                # A once-class PRESENT file was never going to reach
                # ACKNOWLEDGED_KEPT -- that status only ever replaces
                # TEMPLATE_DELETED (line ~1001 above), so a once-class file
                # the project still has is not an acknowledgement candidate
                # at all. Name that answer instead of just the mismatch
                # (Task 1 review F1).
                hint = (" -- a once-class file you still have is already yours; nothing to acknowledge"
                        if entry_status == "PRESENT" else "")
                return {"error": f"acknowledged_deleted: {p} is not a TEMPLATE_DELETED/ACKNOWLEDGED_KEPT "
                                  f"path — manifest NOT written{hint}"}
            if p in explicit:
                return {"error": f"{p} is in both deleted_files and acknowledged_deleted — manifest NOT written"}
    merged = sorted(acknowledged_paths(manifest) | ack_new)

    dropped = []
    for fp in list(files):
        if fp in explicit:
            del files[fp]
            dropped.append(fp)
            continue
        if fp in merged:
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

    out = {k: v for k, v in manifest.items() if k != "version"}
    # finalize_v3 serves both v3 and v4 manifests (v3.manifest_supported
    # dispatch, commit 1) -- it must write back the version it was GIVEN,
    # never force v3, or every v4 finalize would downgrade the consumer's
    # manifest out from under the migration that raised it.
    out["manifest_version"] = manifest.get("manifest_version", MANIFEST_VERSION_V3)
    out["template_version"] = version
    out["template_commit"] = commit
    out["requires_server"], raised, floor_warning = raise_floor(manifest.get("requires_server"))
    if floor_warning:
        warnings.append(floor_warning)
    if merged:
        out["deletedAcknowledged"] = merged
    out["files"] = dict(sorted(files.items()))
    superseded_dropped = drop_superseded(out)
    unknown = unknown_top_level_keys(out)

    manifest_path = pp / ".claude" / "template-manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    core._write_file_atomic(manifest_path, json.dumps(out, indent=2, ensure_ascii=False) + "\n")
    return {
        "manifest_path": ".claude/template-manifest.json",
        "manifest_version": out["manifest_version"],
        "template_commit": commit,
        "template_version": version,
        "files_updated": updated,
        "files_added": added,
        "files_dropped": len(dropped),
        "dropped_entries": sorted(dropped),
        "superseded_keys_dropped": superseded_dropped,
        "unknown_keys": unknown,
        "unknown_file_keys": sorted(unknown_files, key=lambda d: d["path"]),
        "acknowledged_deleted": merged,
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


PROJECT_MD_SEED_BODY = (
    "This file has no `paths:` key, so Claude Code loads it at EVERY session start,\n"
    "at the same priority as CLAUDE.md. Anything you write here is always on.\n"
    "\n"
    "A new or edited rules file is picked up at the NEXT session start, not the current\n"
    "one -- restart the session to test a change.\n"
    "\n"
    "To scope it to files instead, add a frontmatter block at the very top:\n"
    "\n"
    "    ---\n"
    "    paths:\n"
    "      - \"src/**/*.py\"\n"
    "      - \"pyproject.toml\"\n"
    "    ---\n"
    "\n"
    "Always-on project rules belong in `.claude/project-instructions.md` (imported at\n"
    "the end of CLAUDE.md), not here; a rule in both places exists twice and drifts."
)


def build_project_md(hunks: str, base_label: str, template_version: str) -> str:
    """Seed .claude/rules/project.md.

    The PROJECT-CUSTOM region is NOT copied here. Under the toolkit v3.1
    reversal the region stays in CLAUDE.md, so copying it would not relocate
    it, it would duplicate it. Out-of-region edits are no longer embedded
    either (v4.0.1, item 14): `hunks` is accepted for backward compatibility
    but ignored -- the caller (migrate_manifest) writes them to
    `<backup_dir>/CLAUDE.md.out-of-region.diff` instead, because this file
    has NO `paths:` key and is therefore loaded at EVERY session start, same
    as CLAUDE.md -- an unscoped project.md is delivered to EVERY session, not
    to nobody, which is exactly why a migration diff must not live here.
    """
    rendered = "no" if base_label == "unavailable" else "yes"
    out = [
        "# Project instructions",
        f"{MIGRATION_MARKER} {template_version}; migration-base: {base_label}; rendered: {rendered} -->",
        "",
        PROJECT_MD_SEED_BODY,
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


def region_bytes_raw(content: str | None) -> int:
    """Byte length of the PROJECT-CUSTOM region body exactly as it sits in the
    file: every byte from the BEGIN marker LINE's terminating newline
    (inclusive of that newline) up to (not including) the first byte of the
    LINE that carries the END marker. No stripping, no joining on "\n" --
    this is the ONE definition shared with region.sh --bytes (v4.0.1, item
    6), which is necessarily line-based (awk reads line by line and moves to
    the next line the instant it sees the BEGIN marker, without looking at
    what follows "-->" on that same line). Both ends of the span are
    therefore anchored on LINES, not on the marker delimiters themselves:
    starting right after the BEGIN marker's own "-->" (v4.0.1 fix round 1's
    initial implementation) counted any trailing text on the BEGIN line
    itself (e.g. "<!-- PROJECT-CUSTOM:BEGIN --> keep this\\n") as region
    bytes, which region.sh does not -- and ending at the END marker's own
    "<!--" instead of its line start disagrees with region.sh the moment
    that marker is indented. `_region_body` above keeps its line-joined text
    shape for callers that compare CONTENT, not bytes. 0 for no region, an
    unclosed region, or an empty region (BEGIN immediately followed by END
    on the same line).
    """
    if not content:
        return 0
    begin = content.find(core.CUSTOM_REGION_BEGIN)
    if begin < 0:
        return 0
    body_start = content.find("\n", begin)
    if body_start < 0:
        return 0
    end_text = content.find(core.CUSTOM_REGION_END, body_start)
    if end_text < 0:
        return 0
    last_nl = content.rfind("\n", body_start, end_text)
    if last_nl < 0:
        # No newline between the BEGIN marker line's own newline and the END
        # marker's text: BEGIN and END share one physical line -- an empty
        # region.
        return 0
    body_end = last_nl + 1
    return len(content[body_start:body_end].encode("utf-8"))


def migrate_v2_to_v3(pp: pathlib.Path, manifest: dict, rules: OwnershipRules) -> dict:
    warnings = list(rules.warnings)
    repo = core._template_repo_resolved(manifest)

    # Steps 1-2: region + out-of-region hunks against the held, rendered base.
    proj_claude = core._read_file(pp / "CLAUDE.md") or ""
    proj_part, proj_region = core._split_custom_region(proj_claude)
    base, base_label, warn = resolve_base(pp, manifest, rules, "CLAUDE.md")
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
                rendered = template_content(pp, manifest, rules, proj_rel, tpl_raw) or ""
                new_entry = {"hash": format_hash(core._sha256(rendered)),
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
                held, _label, _w = resolve_base(pp, manifest, rules, tpl_rel)
                if held is not None and held == on_disk:
                    redundant.append(proj_rel)

    commit = manifest_commit(manifest)
    version, vwarn = derive_template_version(repo, commit, rules.tracked_paths) if commit else (None, "untagged_template_tree")
    if vwarn:
        warnings.append(vwarn)
    new_manifest = {k: v for k, v in manifest.items() if k not in ("version", "files")}
    new_manifest["manifest_version"] = MANIFEST_VERSION_V3
    new_manifest["template_version"] = version
    new_manifest["template_commit"] = commit
    new_manifest["requires_server"] = f">={MIN_SERVER_FOR_V3}"
    new_manifest["files"] = dict(sorted(files.items()))
    superseded_dropped = drop_superseded(new_manifest)

    # Step 3: project.md, unless the consumer already has one. The
    # out-of-region hunks are NOT embedded here (v4.0.1, item 14) -- this
    # file has no `paths:` key, so it loads at every session start same as
    # CLAUDE.md, and a migration diff belongs in the backup, not in
    # something every session reads. migrate_manifest writes `hunks` to
    # `<backup_dir>/CLAUDE.md.out-of-region.diff` and records the path as
    # `project_md_record`; build_project_md gets hunks="" unconditionally.
    existing = core._read_file(pp / PROJECT_MD)
    project_md = None
    if existing is None:
        project_md = build_project_md("", base_label, "v3.1.0")

    return {
        "manifest": new_manifest,
        "dropped_entries": sorted(dropped),
        "dropped_file_keys": sorted(dropped_file_keys, key=lambda d: d["path"]),
        "dropped_resolutions": sorted(dropped_resolutions, key=lambda d: d["path"]),
        "redundant_project_file": sorted(redundant),
        "project_md": project_md,
        "project_md_existing": existing is not None,
        "hunk_count": hunk_count,
        "out_of_region_diff": hunks,
        "migration_base": base_label,
        "region_was_seed": region_was_seed,
        "region_left_in_place": proj_region is not None,
        "region_bytes": region_bytes_raw(proj_claude),
        "gate_self_reference": gate_hits,
        "gate_unverified": gate_declared,
        "superseded_keys_dropped": superseded_dropped,
        "unknown_keys": unknown_top_level_keys(new_manifest),
        "unknown_file_keys": sorted(unknown_files, key=lambda d: d["path"]),
        "warnings": warnings,
    }


# -------------------------
# v3 -> v4 migration (spec §7 step 1c, §9)
# -------------------------

def _tools_line_diff(tpl_text: str, proj_text: str) -> tuple[list[str], list[str]] | None:
    """(original_tools, added_tools) when `proj_text` differs from
    `tpl_text` ONLY by additional, order-preserving entries appended to the
    `tools:` frontmatter line -- None when the diff touches anything else,
    either side lacks a `tools:` line, or the project's list is not exactly
    the template's list plus a suffix (step 6b: a grants entry replaces the
    rename route for exactly this shape)."""
    tpl_m = _TOOLS_LINE_RE.search(tpl_text)
    proj_m = _TOOLS_LINE_RE.search(proj_text)
    if tpl_m is None or proj_m is None:
        return None
    tpl_rest = tpl_text[:tpl_m.start()] + tpl_text[tpl_m.end():]
    proj_rest = proj_text[:proj_m.start()] + proj_text[proj_m.end():]
    if tpl_rest != proj_rest:
        return None
    tpl_tools = [t.strip() for t in tpl_m.group(1).split(",") if t.strip()]
    proj_tools = [t.strip() for t in proj_m.group(1).split(",") if t.strip()]
    if len(proj_tools) <= len(tpl_tools) or proj_tools[:len(tpl_tools)] != tpl_tools:
        return None
    return tpl_tools, proj_tools[len(tpl_tools):]


def _v4_entry_for(fp: str, entry: dict, *, pp: pathlib.Path, manifest: dict, rules: OwnershipRules,
                  grant_agent_paths: dict[str, str], grants_plan: dict[str, list[str]],
                  new_claude: str) -> tuple[dict | None, list[str], str | None]:
    """The ONE per-entry v4-manifest decision (spec 1.1, review #17 x3):
    used by BOTH the dry-run preview loop and the write-path re-hash, so
    there is exactly one producer of a v4 manifest entry (H2 shape) -- the
    invariant `check_baseline_invariant` checks is then true by
    construction, not by two code paths happening to agree.

    Returns (new_entry, carried_keys, unavailable_agent). `new_entry` is
    None only when `fp` is a grants-plan agent whose HELD base could not be
    rendered -- the caller collects `unavailable_agent` across every entry
    and refuses the WHOLE migration (grants are all-or-nothing: a silently
    un-spliced baseline is worse than a loud refusal, spec 1.1).

    Every entry the migration does not write (everything except CLAUDE.md,
    which is written fresh, and grants-plan agents, whose manifest hash
    must reflect the grant even though their FILE is not written to disk)
    carries `entry["hash"]` forward UNCHANGED -- no render, no
    `template_content()` call at all -- so a stale or deliberately corrupt
    stored hash is PRESERVED, never silently repaired (spec 1.1's
    discriminating fixture), and a template file the template no longer
    ships (deletedAcknowledged) never resolves to `hash: ""` (bug b).
    Unknown per-file keys (consumer annotations, e.g. `reason`) are always
    merged forward via `carry_unknown_file_keys` (spec 1.1's wording covers
    every unwritten entry, not just `once` -- applying it uniformly here is
    a strict superset of the `once`-only reading and costs nothing).
    """
    ownership = entry.get("ownership")
    if ownership == "template":
        if fp == "CLAUDE.md":
            # Written fresh from the CURRENT template -- not carried.
            return {"hash": format_hash(core._sha256(new_claude)), "ownership": "template"}, [], None
        agent_name = grant_agent_paths.get(fp)
        if agent_name is not None:
            tpl_rel_e = rules.template_path_for(fp)
            held_rendered, _base_label, _warn = resolve_base(pp, manifest, rules, tpl_rel_e)
            if held_rendered is None:
                return None, [], agent_name
            spliced = splice_tools(held_rendered, grants_plan[agent_name])
            new_entry, carried = carry_unknown_file_keys(
                entry, {"hash": format_hash(core._sha256(spliced)), "ownership": "template"})
            return new_entry, carried, None
        # Not written by the migration -- carry the stored hash forward
        # unchanged. This IS the fix for #17's three symptoms.
        new_entry, carried = carry_unknown_file_keys(
            entry, {"hash": entry.get("hash", ""), "ownership": "template"})
        return new_entry, carried, None
    if ownership == "once":
        new_entry, carried = carry_unknown_file_keys(entry, {"ownership": "once"})
        return new_entry, carried, None
    # Defensive: neither known ownership -- preserve verbatim rather than guess.
    return dict(entry), [], None


def check_baseline_invariant(old_manifest: dict, new_manifest: dict, will_write) -> dict:
    """Pure invariant (spec 1.1): every v4 entry NOT in `will_write` must
    carry its OLD hash forward unchanged. `will_write` is the set of paths
    whose hash the migration is ALLOWED to change -- CLAUDE.md (written
    fresh), the two new once-class files it creates, and every grants-plan
    agent path (re-hashed via the held base even though the migration never
    writes that agent's bytes to disk).

    A violation means `_v4_entry_for` regressed to reconstructing an entry
    instead of deriving it -- report it, never accept it silently. It
    cannot false-positive: under carry-forward, previewed and stored are
    both literally `entry["hash"]`, even for a deliberately corrupt one, so
    a violation here means the producer changed a baseline it does not own.
    `will_write` may be a set or any other string container; only
    membership (`in`) is used.
    """
    old_files = old_manifest.get("files", {})
    violations = []
    for path, new_entry in new_manifest.get("files", {}).items():
        if path in will_write:
            continue
        old_entry = old_files.get(path)
        if old_entry is None:
            continue
        if new_entry.get("hash") != old_entry.get("hash"):
            violations.append(path)
    return {"ok": not violations, "violations": sorted(violations)}


def migrate_v3_to_v4(pp: pathlib.Path, manifest: dict, rules: OwnershipRules) -> dict:
    """Plan (never writes) a v3 -> v4 migration (spec §7 step 1c, §9).

    Refuse-not-guess: (c) any CLAUDE.md diff outside the PROJECT-CUSTOM
    region, measured against the HELD (last-synced) template, is a REFUSAL
    naming the diff -- resolved by moving the text into the region BEFORE
    migrating (spec §9.2: the region is the one place the migration KNOWS is
    project content, so staging text there is how a consumer tells it what
    to move; it will not guess placement). (d) An EXISTING
    .claude/project-instructions.md is a REFUSAL naming the path (R-K,
    reviewer Q1): the migration writes that file FROM the region body, so a
    silent "keep the existing file" would strand the region body in a
    CLAUDE.md about to lose it -- never a silent once-class skip.

    An agent whose LOCAL_EDITED diff is CONFINED to additions on its
    `tools:` line (R-D: only an agent that SHIPS one) becomes a grants.json
    entry instead (step 6b); an agent that gained a `tools:` line the
    template ships NONE for is an (c)-class refusal, never a synthesised
    grant.
    """
    warnings = list(rules.warnings)

    proj_claude = core._read_file(pp / "CLAUDE.md") or ""
    proj_part, proj_region = core._split_custom_region(proj_claude)
    region_body = _region_body(proj_region)

    tpl_rel = rules.template_path_for("CLAUDE.md")
    tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
    new_claude = template_content(pp, manifest, rules, "CLAUDE.md", tpl_raw)
    if new_claude is None:
        return {"error": "the template no longer ships CLAUDE.md for this variant -- cannot migrate"}

    base, base_label, warn = resolve_base(pp, manifest, rules, tpl_rel)
    if warn:
        warnings.append(warn)
    region_was_seed = None
    out_of_region_diff = ""
    if base is not None:
        base_part, base_region = core._split_custom_region(base)
        out_of_region_diff = _unified(base_part, proj_part, f"CLAUDE.md@{base_label}", "CLAUDE.md@project")
        if region_body is not None and base_region is not None:
            region_was_seed = _norm_ws(region_body) == _norm_ws(_region_body(base_region) or "")
            if region_was_seed:
                region_body = None

    # (b) grant-shaped agent diffs.
    placeholders = manifest.get("placeholders", {})
    grants_plan: dict[str, list[str]] = {}
    grant_agent_paths: dict[str, str] = {}
    no_tools_line_refusals: list[str] = []
    for proj_rel, entry in manifest.get("files", {}).items():
        proj_rel = core._normalize_path(proj_rel)
        if entry.get("ownership") != "template" or not proj_rel.startswith(AGENTS_DIR_PREFIX):
            continue
        tpl_rel_agent = rules.template_path_for(proj_rel)
        agent_tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel_agent))
        agent_proj = core._read_file(pp / proj_rel)
        if agent_tpl_raw is None or agent_proj is None:
            continue
        # `manifest` here is still the OLD v3 manifest (is_v4_manifest is
        # False), so template_content() is a placeholder-only no-op --
        # exactly the plain rendering this detection step needs.
        agent_tpl_rendered = template_content(pp, manifest, rules, proj_rel, agent_tpl_raw)
        if agent_tpl_rendered is None or agent_tpl_rendered == agent_proj:
            continue
        # Route through the region split BEFORE the tools-only diff (spec
        # 1.2, #31): without this, an agent carrying a tools: addition AND
        # region content classifies as `mixed` on the WHOLE text and is
        # skipped here, so grants_plan stays empty for it -- exactly the
        # risk grants exist to close (MM-Agent's 16 + 22 project tools got
        # no durable home). Same split `region_status` (`:932`) already
        # uses -- no second stripper.
        #
        # Residual (stated per the brief): this compares against the
        # CURRENT template (HEAD)'s non-region part, so a template edit to
        # the agent's tools: line between the held commit and HEAD still
        # reads as not-tools-only here -- the held-base comparison is v4.2.
        tpl_nonregion, _tpl_region = core._split_custom_region(agent_tpl_rendered)
        proj_nonregion, _proj_region = core._split_custom_region(agent_proj)
        diff = _tools_line_diff(tpl_nonregion, proj_nonregion)
        if diff is not None:
            agent_name = agent_name_of(agent_tpl_rendered)
            if agent_name:
                grants_plan[agent_name] = diff[1]
                grant_agent_paths[proj_rel] = agent_name
        elif _TOOLS_LINE_RE.search(tpl_nonregion) is None and _TOOLS_LINE_RE.search(proj_nonregion):
            no_tools_line_refusals.append(proj_rel)

    if no_tools_line_refusals:
        return {
            "error": f"agent(s) gained a tools: line the template does not ship: "
                     f"{sorted(no_tools_line_refusals)} -- resolve by hand before migrating",
            "out_of_region_diff": out_of_region_diff,
        }
    if out_of_region_diff.strip():
        return {
            "error": "CLAUDE.md diverges from the held template outside the PROJECT-CUSTOM region -- "
                     "move the text into the region BEFORE migrating (spec §9.2), then migrate again",
            "out_of_region_diff": out_of_region_diff,
        }

    instructions_target = pp / INSTRUCTIONS_FILE_DEFAULT
    if instructions_target.is_file():
        return {
            "error": f"{INSTRUCTIONS_FILE_DEFAULT} already exists -- the migration writes this file "
                     "from the region body; move or remove the existing file first",
        }

    seed_tpl_raw = core._read_file(core._template_file_path(manifest, INSTRUCTIONS_FILE_DEFAULT))
    seed_header = seed_tpl_raw if seed_tpl_raw is not None else (
        "# Project instructions\n\n"
        "Imported at the end of CLAUDE.md; where the two conflict, this file wins.\n\n"
    )
    if region_body:
        instructions_content = seed_header.rstrip("\n") + "\n\n" + region_body.rstrip("\n") + "\n"
    else:
        instructions_content = seed_header
    agent_grants_content = json.dumps(
        {"schema": 1, "grants": dict(sorted(grants_plan.items()))}, indent=2, ensure_ascii=False) + "\n"

    repo = core._template_repo_resolved(manifest)
    commit = core._git_head(repo) or manifest_commit(manifest)
    version, vwarn = derive_template_version(repo, commit, rules.tracked_paths) if commit else (None, "untagged_template_tree")
    if vwarn:
        warnings.append(vwarn)

    new_manifest = {k: v for k, v in manifest.items() if k != "version"}
    new_manifest["manifest_version"] = MANIFEST_VERSION_V4
    new_manifest["template_version"] = version
    new_manifest["template_commit"] = commit
    new_manifest["requires_server"] = f">={MIN_SERVER_FOR_V4}"
    new_manifest["instructions_file"] = INSTRUCTIONS_FILE_DEFAULT
    new_manifest["agent_grants"] = AGENT_GRANTS_FILE

    # Hash PREVIEW: derive, never construct (spec 1.1). Every entry the
    # migration does not write carries its stored hash forward UNCHANGED --
    # no render at all -- through the single producer `_v4_entry_for`, which
    # the write-path re-hash below calls again on the same (fp, entry)
    # pairs, so the two can never disagree (H2 shape).
    files: dict[str, dict] = {}
    carried_file_keys: dict[str, list[str]] = {}
    unavailable_agents: list[str] = []
    for fp, entry in manifest.get("files", {}).items():
        fp = core._normalize_path(fp)
        new_entry, carried, unavailable_agent = _v4_entry_for(
            fp, entry, pp=pp, manifest=manifest, rules=rules,
            grant_agent_paths=grant_agent_paths, grants_plan=grants_plan, new_claude=new_claude)
        if new_entry is None:
            unavailable_agents.append(unavailable_agent)
            continue
        files[fp] = new_entry
        if carried:
            carried_file_keys[fp] = carried
    if unavailable_agents:
        return {
            "error": "migration_base unavailable; grant agents "
                     f"{sorted(set(unavailable_agents))} cannot be re-hashed -- "
                     "fetch the held template commit and retry",
        }
    files[INSTRUCTIONS_FILE_DEFAULT] = {"ownership": "once"}
    files[AGENT_GRANTS_FILE] = {"ownership": "once"}
    new_manifest["files"] = dict(sorted(files.items()))
    superseded_dropped = drop_superseded(new_manifest)

    will_write = sorted({"CLAUDE.md", INSTRUCTIONS_FILE_DEFAULT, AGENT_GRANTS_FILE} | set(grant_agent_paths))
    baseline_invariant = check_baseline_invariant(manifest, new_manifest, set(will_write))

    return {
        "manifest": new_manifest,
        "region_body": region_body,
        "region_was_seed": region_was_seed,
        "region_bytes": region_bytes_raw(proj_claude),
        "out_of_region_diff": out_of_region_diff,
        "migration_base": base_label,
        "grants_plan": grants_plan,
        "grant_agent_paths": grant_agent_paths,
        "will_write": will_write,
        "carried_file_keys": carried_file_keys,
        "baseline_invariant": baseline_invariant,
        "instructions_content": instructions_content,
        "agent_grants_content": agent_grants_content,
        "claude_md_content": new_claude,
        "superseded_keys_dropped": superseded_dropped,
        "unknown_keys": unknown_top_level_keys(new_manifest),
        "warnings": warnings,
    }


def _migrate_v3_manifest(pp: pathlib.Path, manifest: dict, backup_dir: str, dry_run: bool,
                         skill_version: str) -> dict:
    """The v3 -> v4 branch of migrate_manifest (spec §7 step 1c, §9)."""
    rules = load_ownership(manifest["templateRepo"])
    if rules is None:
        return {"error": f"cannot migrate: {OWNERSHIP_FILE} not found in the template repo"}
    ok, refusal, floor_warning, bypassed = skill_floor_satisfied(rules.requires_skill, skill_version)
    if not ok and not dry_run:
        return {"error": refusal, "skill_version": (skill_version or "").strip(),
                **({"skill_version_unknown": True} if not (skill_version or "").strip() else {})}

    plan = migrate_v3_to_v4(pp, manifest, rules)
    if "error" in plan:
        return plan
    plan["dry_run"] = dry_run
    plan["skill_version"] = (skill_version or "").strip()
    if not plan["skill_version"]:
        plan["skill_version_unknown"] = True
    if bypassed:
        plan["skill_version_bypassed"] = True
    if floor_warning:
        plan["warnings"].append(floor_warning)
    if not ok:
        plan["warnings"].append("skill_version would refuse a write: " + refusal)

    if not dry_run and not plan["baseline_invariant"]["ok"]:
        # Defensive tripwire (spec 1.1): with `_v4_entry_for` as the single
        # producer this can only fire if a future change breaks that
        # invariant -- refuse loudly BEFORE any write (backup_dir is not
        # even created yet) rather than let a silently-rewritten baseline
        # land on disk.
        return {
            "error": "baseline invariant violated for "
                     f"{plan['baseline_invariant']['violations']}: the migration would rewrite a "
                     "baseline it does not write -- this is a server defect, report it with these "
                     "paths; nothing was written",
        }

    if dry_run:
        plan["migrated"] = False
        plan["backup"] = None
        plan["written"] = []
        plan["report_path"] = None
        return plan

    if not backup_dir:
        return {"error": "backup_dir is required to migrate (pre-migration CLAUDE.md and manifest are copied "
                         "there); use dry_run=true to preview"}

    bdir = pathlib.Path(backup_dir).resolve()
    bdir.mkdir(parents=True, exist_ok=True)
    claude_bak = bdir / "CLAUDE.md.pre-migration"
    manifest_bak = bdir / "template-manifest.json.pre-migration"
    core._write_file_atomic(claude_bak, core._read_file(pp / "CLAUDE.md") or "")
    core._write_file_atomic(manifest_bak, core._read_file(pp / ".claude" / "template-manifest.json") or "")

    # Write order matters (H2): agent-grants.json FIRST, so every hash below
    # -- computed through template_content(), never _apply_placeholders
    # directly -- reads the SAME grants the next apply/status call will.
    grants_target = pp / AGENT_GRANTS_FILE
    grants_target.parent.mkdir(parents=True, exist_ok=True)
    core._write_file_atomic(grants_target, plan["agent_grants_content"])

    instructions_target = pp / INSTRUCTIONS_FILE_DEFAULT
    instructions_target.parent.mkdir(parents=True, exist_ok=True)
    core._write_file_atomic(instructions_target, plan["instructions_content"])

    claude_target = pp / "CLAUDE.md"
    core._write_file_atomic(claude_target, plan["claude_md_content"])

    # Write-path re-hash (spec 1.1): the SAME per-entry decision as the
    # preview above, via the SAME `_v4_entry_for` helper on the SAME (fp,
    # entry) pairs from the OLD v3 manifest -- so this loop cannot diverge
    # from the preview's `plan["manifest"]["files"]` (H2 shape: exactly one
    # producer). `unavailable_agent` is unreachable here in practice:
    # migrate_v3_to_v4() already refused, before any write, when a
    # grants-plan base was unavailable, and this loop is fed identical
    # inputs -- so a hit here is the same defect the baseline-invariant
    # tripwire above already guards against, not a new failure mode. Unlike
    # that pre-write refusal, grants.json/project-instructions.md/CLAUDE.md
    # are ALREADY on disk by this point -- the message says so rather than
    # repeating "nothing was written", which would be false here.
    final_manifest = dict(plan["manifest"])
    final_files: dict[str, dict] = {}
    carried_file_keys: dict[str, list[str]] = {}
    for fp, entry in manifest.get("files", {}).items():
        fp = core._normalize_path(fp)
        new_entry, carried, unavailable_agent = _v4_entry_for(
            fp, entry, pp=pp, manifest=manifest, rules=rules,
            grant_agent_paths=plan["grant_agent_paths"], grants_plan=plan["grants_plan"],
            new_claude=plan["claude_md_content"])
        if new_entry is None:
            return {
                "error": "migration_base unavailable; grant agents "
                         f"['{unavailable_agent}'] cannot be re-hashed -- this is unreachable given "
                         "migrate_v3_to_v4()'s pre-write refusal with identical inputs; report it as a "
                         "server defect. CLAUDE.md, .claude/project-instructions.md and "
                         ".claude/agent-grants.json were already written; the manifest was not",
            }
        final_files[fp] = new_entry
        if carried:
            carried_file_keys[fp] = carried
    final_files[INSTRUCTIONS_FILE_DEFAULT] = {"ownership": "once"}
    final_files[AGENT_GRANTS_FILE] = {"ownership": "once"}
    final_manifest["files"] = dict(sorted(final_files.items()))
    # Reconcile with the preview: same helper, same inputs, so this is
    # provably identical to plan["carried_file_keys"] today -- overwriting
    # with the write-path's own result means the reported field can never
    # silently drift from the manifest actually written, even if a future
    # change makes the two loops take different branches.
    plan["carried_file_keys"] = carried_file_keys

    manifest_path = pp / ".claude" / "template-manifest.json"
    core._write_file_atomic(manifest_path, json.dumps(final_manifest, indent=2, ensure_ascii=False) + "\n")

    report = {
        "migrated": True, "from": "v3", "to": "v4",
        "region_was_seed": plan["region_was_seed"], "region_bytes": plan["region_bytes"],
        "grants_plan": plan["grants_plan"], "warnings": plan["warnings"],
    }
    report_path = bdir / "migration-report.json"
    core._write_file_atomic(report_path, json.dumps(report, indent=2, ensure_ascii=False) + "\n")

    plan["manifest"] = final_manifest
    plan["migrated"] = True
    plan["backup"] = {"claude_md": str(claude_bak), "manifest": str(manifest_bak)}
    plan["written"] = [AGENT_GRANTS_FILE, INSTRUCTIONS_FILE_DEFAULT, "CLAUDE.md",
                       ".claude/template-manifest.json"]
    plan["report_path"] = str(report_path)
    return plan


def migrate_manifest(pp: pathlib.Path, backup_dir: str, dry_run: bool,
                     skill_version: str = "") -> dict:
    manifest, errors = core._load_manifest(pp)
    if manifest is None:
        return {"error": errors[0]}
    if errors:
        return {"error": "; ".join(errors)}
    if is_v4_manifest(manifest):
        return {"migrated": False, "dry_run": dry_run, "already_v4": True,
                "reason": "manifest is already v4 -- nothing to migrate"}
    if is_v3(manifest):
        return _migrate_v3_manifest(pp, manifest, backup_dir, dry_run, skill_version)
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
        # Nothing is written in dry_run, so there is no record path yet --
        # `out_of_region_diff` (in the plan already) previews what a real
        # write would put in backup_dir.
        plan["project_md_record"] = None
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

    # Item 14: the out-of-region diff is a migration RECORD, not project
    # content -- it goes into the existing, required backup_dir beside the
    # two .pre-migration copies, never into project.md (which has no
    # `paths:` key and is therefore loaded at every session start).
    diff_text = plan.get("out_of_region_diff") or ""
    if diff_text.strip():
        diff_path = bdir / "CLAUDE.md.out-of-region.diff"
        core._write_file_atomic(diff_path, diff_text)
        plan["project_md_record"] = str(diff_path)
    else:
        plan["project_md_record"] = None

    written = []
    if plan["project_md"] is not None:
        target = pp / PROJECT_MD
        target.parent.mkdir(parents=True, exist_ok=True)
        core._write_file_atomic(target, plan["project_md"])
        written.append(PROJECT_MD)
    core._write_file_atomic(pp / ".claude" / "template-manifest.json",
                            json.dumps(plan["manifest"], indent=2, ensure_ascii=False) + "\n")
    written.append(".claude/template-manifest.json")

    plan["migrated"] = True
    plan["backup"] = {"claude_md": str(claude_bak), "manifest": str(manifest_bak)}
    plan["written"] = written
    return plan
