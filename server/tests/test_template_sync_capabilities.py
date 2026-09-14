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


WITNESSES = {
    "region_splice": _witness_region_splice,
    "region_orphaned": _witness_region_orphaned,
    "region_markers_malformed": _witness_region_markers_malformed,
    "local_diff_kind": _witness_local_diff_kind,
    "server_source": _witness_server_source,
    "skill_version_floor": _witness_skill_version_floor,
}


@pytest.mark.parametrize("name", sorted(EXPECTED))
def test_every_advertised_capability_has_a_working_witness(name, tmp_path):
    """Present implies true. A name advertised by a build that cannot perform
    it fails here."""
    assert name in v3.CAPABILITIES
    assert WITNESSES[name](tmp_path) is True, f"{name} is advertised but its witness failed"


def test_every_name_has_a_witness():
    assert set(WITNESSES) == set(v3.CAPABILITIES)
