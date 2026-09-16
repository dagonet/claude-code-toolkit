"""Capability reporting on template_load_manifest.

A version is a proxy for a capability, and every proxy eventually disagrees
with the thing it stands for -- which is what this round demonstrated, when
0.3.1 was newer than 0.3.0 and equally unable to splice a region. A skill
should gate on `"region_splice" in capabilities`, never on version arithmetic.

**What these tests prove, and what they cannot.** Each name is paired with a
witness that exercises the behaviour the name claims, so a name that is
present but false fails here -- the risk the controller named. The converse,
"absent when unsupported", is not provable inside a build that supports
everything: nothing in this repository can produce a server lacking a
capability it ships. What stands in for it is `test_capability_set_is_exact`,
which fails the moment a name is added without a witness, so the list cannot
grow by accident into claims nobody checked.

The list is deliberately short. It carries the names a skill would branch on,
not an inventory of every field the server emits: better four names that can
be trusted than eleven that cannot. Names are permanent once published --
appended to, never renamed or removed, or the map becomes another drifting
proxy.
"""

import asyncio
import json

import pytest

from template_sync import mcp as ts
from template_sync import v3

BEGIN = "<!-- PROJECT-CUSTOM:BEGIN -->"
END = "<!-- PROJECT-CUSTOM:END -->"
TPL = f"# T\nrule one\n{BEGIN}\n{END}\n"
PROJ = f"# T\nrule one\n{BEGIN}\nMY RULE\n{END}\n"

EXPECTED = {
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
}


def _load(project_path):
    return json.loads(asyncio.run(ts.template_load_manifest(str(project_path))))


def test_capability_set_is_exact():
    """Adding a name without a witness below must fail here rather than ship
    an unverified claim."""
    assert set(v3.CAPABILITIES) == EXPECTED
    assert len(v3.CAPABILITIES) == len(set(v3.CAPABILITIES)), "names must be unique"
    assert all(n == n.lower() and " " not in n for n in v3.CAPABILITIES)


def test_capabilities_present_even_when_validation_fails(tmp_path):
    """The gate must be readable exactly when the manifest is wrong: a skill
    still has to act in that state, and a gate that disappears then is
    unavailable when it matters most."""
    res = _load(tmp_path / "no-such-project")
    assert res["valid"] is False
    assert set(res["capabilities"]) == EXPECTED


def test_capabilities_present_on_a_valid_load(tmp_path):
    repo, proj = tmp_path / "tk", tmp_path / "proj"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(
        json.dumps({"rules": [{"pattern": "CLAUDE.md", "ownership": "template"}]}), encoding="utf-8")
    (proj / ".claude").mkdir(parents=True)
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "manifest_version": 3, "template_version": "v3.1.0", "template_commit": "unknown",
        "requires_server": ">=0.3.2", "variant": "general", "templateRepo": str(repo),
        "placeholders": {}, "files": {},
    }), encoding="utf-8")
    res = _load(proj)
    assert res["valid"] is True
    assert set(res["capabilities"]) == EXPECTED


# --- one witness per name: the capability must actually do what it claims ----


def _witness_region_splice(tmp_path) -> bool:
    spliced, preserved = v3.splice_region(TPL, PROJ)
    return preserved is True and "MY RULE" in spliced


def _witness_region_orphaned(tmp_path) -> bool:
    return (v3.region_orphaned("# T\nrule one\n", PROJ) is True
            and v3.region_orphaned(TPL, PROJ) is False)


def _witness_region_markers_malformed(tmp_path) -> bool:
    return (v3.malformed_side(None, f"# T\n{BEGIN}\nx\n") == "project"
            and v3.malformed_side(TPL, PROJ) is None)


def _witness_local_diff_kind(tmp_path) -> bool:
    added = v3._unified("a\n", "a\nb\n", "t", "p")
    replaced = v3._unified("a\n", "c\n", "t", "p")
    return v3.diff_kind(added) == "insertion" and v3.diff_kind(replaced) == "mixed"


def _witness_server_source(tmp_path) -> bool:
    import pathlib

    src = ts._server_source()
    return (pathlib.Path(src) / "__init__.py").is_file()


def _witness_skill_version_floor(tmp_path) -> bool:
    """Advertising the floor means enforcing it. Three arms, because a name that
    is present but false is the risk this file exists for: a declared floor
    refuses an unidentified caller, the exact sentinel bypasses, and a near miss
    of that sentinel does NOT.
    """
    refused, _, _, _ = v3.skill_floor_satisfied(">=v3.1.3", "")
    ok, _, _, bypassed = v3.skill_floor_satisfied(">=v3.1.3", v3.SKILL_BYPASS_SENTINEL)
    near_miss_ok, _, _, near_miss_bypassed = v3.skill_floor_satisfied(">=v3.1.3", "not_a_skill")
    undeclared, _, _, _ = v3.skill_floor_satisfied("", "")
    return (refused is False and ok is True and bypassed is True
            and near_miss_ok is False and near_miss_bypassed is False
            and undeclared is True)


def _witness_region_bytes_raw(tmp_path) -> bool:
    """The `"\\n\\nX\\n\\n"` fixture (v4.0.1 item 6): a body without a
    trailing blank line cannot distinguish the raw span from the two
    stripped definitions it replaced, so this is the one shape that proves
    which definition `region_bytes_raw` -- and the `region_bytes` field it
    now backs -- actually ships.
    """
    body = "\n\nX\n\n"
    content = "# T\n<!-- PROJECT-CUSTOM:BEGIN -->" + body + "<!-- PROJECT-CUSTOM:END -->\n"
    return (v3.region_bytes_raw(content) == len(body.encode())
            and v3.region_bytes_raw("# T\n<!-- PROJECT-CUSTOM:BEGIN --><!-- PROJECT-CUSTOM:END -->\n") == 0)


def _witness_new_template_files_detail(tmp_path) -> bool:
    """Exercised through the actual v3 status payload (compute_status_v3 --
    the dispatch target for every real, v3-manifest consumer), not
    `hasattr`, and with a NON-identity row: `.gitignore` -> `gitignore` is
    the shape that proves the detail list carries real information rather
    than echoing the path back at itself.
    """
    if ts.template_path_for(".gitignore") != "gitignore":
        return False
    repo = tmp_path / "tk"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "gitignore").write_text("*.log\n", encoding="utf-8", newline="")
    (repo / "templates" / "ownership.json").write_text(json.dumps({
        "tracked_paths": ["templates"],
        "rules": [{"pattern": "gitignore", "ownership": "once", "target": ".gitignore"}],
    }), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "manifest_version": 3, "template_version": "3.1.0", "template_commit": "0000000",
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.0", "files": {},
    }), encoding="utf-8")
    res = json.loads(asyncio.run(ts.template_compute_status(str(proj))))
    return (res["new_template_files"] == [".gitignore"]
            and res["new_template_files_detail"] == [{"path": ".gitignore", "template_path": "gitignore"}])


def _witness_superseded_keys(tmp_path) -> bool:
    """finalize_v3 drops the v2-era lastSynced*/lastSyncedVersion*/
    lastSyncedVersionOf trio unconditionally (v4.0.1, item 8). The witness
    is a real finalize on a manifest carrying the agreeing-values form the
    consumers carry today, not `hasattr`.
    """
    repo = tmp_path / "tk"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps({
        "tracked_paths": ["templates"],
        "rules": [{"pattern": "CLAUDE.md", "ownership": "template"}],
    }), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {
        "manifest_version": 3, "template_version": "v3.1.0", "template_commit": "0000000",
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.2", "files": {},
        "lastSyncedVersion": "v4.0.0", "lastSyncedVersionOf": "0000000",
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    res = json.loads(asyncio.run(ts.template_finalize_sync(str(proj))))
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    return (res.get("superseded_keys_dropped") == ["lastSyncedVersion", "lastSyncedVersionOf"]
            and "lastSyncedVersion" not in out and "lastSyncedVersionOf" not in out)


def _witness_missing_declared_keys(tmp_path) -> bool:
    """A required key held only under its deprecated spelling is reported
    under its CANONICAL name with reason "deprecated_spelling" (v4.0.1, item
    2) -- exercised through a real audit_keys() call, not `hasattr`.
    """
    rule = {
        "pattern": "PROJECT_CONTEXT.md", "ownership": "once", "audit": "keys",
        "required_keys": ["Protected branches", "Gate"],
        "deprecated_keys": {"Gate Command": "Gate"},
    }
    proj = "- **Protected branches**: main\n- **Gate Command**: old-gate.sh\n"
    tpl = "- **Protected branches**: main\n- **Gate**: g\n"
    res = v3.audit_keys(proj, tpl, None, rule)
    return (res["missing_required"] == []
            and {"key": "Gate", "reason": "deprecated_spelling", "template_default": "g"}
            in res["missing_declared_keys"])


def _witness_optional_absent_detail(tmp_path) -> bool:
    """optional_absent_detail carries the rule's per-key none_meaning /
    effect_when_absent for a key that is actually absent -- and the same
    key never appears in missing_declared_keys (the ownership rule).
    """
    rule = {
        "pattern": "PROJECT_CONTEXT.md", "ownership": "once", "audit": "keys",
        "required_keys": ["Gate"],
        "optional_keys": {"Test": {"effect_when_absent": "Gate fallback",
                                   "none_meaning": "not declared"}},
    }
    proj = "- **Gate**: g\n"
    tpl = "- **Gate**: g\n- **Test**: t\n"
    res = v3.audit_keys(proj, tpl, None, rule)
    return (res["optional_absent"] == ["Test"]
            and res["optional_absent_detail"] == [{"key": "Test", "template_default": "t",
                                                     "effect_when_absent": "Gate fallback",
                                                     "none_meaning": "not declared"}]
            and "Test" not in [e["key"] for e in res["missing_declared_keys"]])


WITNESSES = {
    "region_splice": _witness_region_splice,
    "region_orphaned": _witness_region_orphaned,
    "region_markers_malformed": _witness_region_markers_malformed,
    "local_diff_kind": _witness_local_diff_kind,
    "server_source": _witness_server_source,
    "skill_version_floor": _witness_skill_version_floor,
    "region_bytes_raw": _witness_region_bytes_raw,
    "new_template_files_detail": _witness_new_template_files_detail,
    "superseded_keys": _witness_superseded_keys,
    "missing_declared_keys": _witness_missing_declared_keys,
    "optional_absent_detail": _witness_optional_absent_detail,
}


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_every_advertised_capability_has_a_working_witness(name, tmp_path):
    """Present implies true. A name advertised by a build that cannot perform
    it fails here."""
    assert name in v3.CAPABILITIES
    assert WITNESSES[name](tmp_path) is True, f"{name} is advertised but its witness failed"


def test_every_name_has_a_witness():
    assert set(WITNESSES) == set(v3.CAPABILITIES)
