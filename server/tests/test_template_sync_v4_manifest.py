"""manifest v4: constants, acceptance predicate, and the requires_server floor
(v4.1 plan Task 1 commit 1 -- spec §5 header, Decision 2).

A v4 manifest gains two new REQUIRED top-level keys (instructions_file,
agent_grants -- declarations only, the server reads the files at these fixed
paths) on top of everything v3 requires. Acceptance sites (mcp.py's
_load_manifest / template_load_manifest / template_compute_status /
template_apply_file / template_finalize_sync) accept manifest_version 3 OR 4;
sites that mean the v3 SHAPE (the region splice) are untouched by this commit.
"""

import asyncio
import json

import pytest

from template_sync import mcp as ts
from template_sync import v3


def _v4_manifest(repo: str, **overrides) -> dict:
    m = {
        "manifest_version": 4,
        "template_version": "v4.1.0",
        "template_commit": "abc1234",
        "variant": "general",
        "templateRepo": repo,
        "placeholders": {},
        "requires_server": ">=4.1.0",
        "instructions_file": ".claude/project-instructions.md",
        "agent_grants": ".claude/agent-grants.json",
        "files": {},
    }
    m.update(overrides)
    return m


def _toolkit(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps({"rules": []}), encoding="utf-8")
    return repo


# --- constants / predicates --------------------------------------------------


def test_manifest_version_v4_is_four():
    assert v3.MANIFEST_VERSION_V4 == 4


def test_min_server_for_v4_is_4_1_0():
    assert v3.MIN_SERVER_FOR_V4 == "4.1.0"


@pytest.mark.parametrize("mv,expected", [(2, False), (3, False), (4, True), (None, False)])
def test_is_v4_manifest(mv, expected):
    assert v3.is_v4_manifest({"manifest_version": mv}) is expected


@pytest.mark.parametrize("mv,expected", [(1, False), (2, False), (3, True), (4, True), (5, False)])
def test_manifest_supported(mv, expected):
    assert v3.manifest_supported({"manifest_version": mv}) is expected


# --- effective_requires_server_spec ------------------------------------------


def test_effective_spec_v3_manifest_unchanged():
    m = {"manifest_version": 3, "requires_server": ">=0.3.2"}
    assert v3.effective_requires_server_spec(m) == ">=0.3.2"


def test_effective_spec_v4_manifest_no_declared_floor_raised_to_min():
    m = {"manifest_version": 4}
    assert v3.effective_requires_server_spec(m) == ">=4.1.0"


def test_effective_spec_v4_manifest_understated_floor_raised():
    """A hand-edited or migration-bug v4 manifest declaring a floor below
    MIN_SERVER_FOR_V4 must not silently pass on a server that merely
    satisfies the understated value."""
    m = {"manifest_version": 4, "requires_server": ">=0.3.2"}
    assert v3.effective_requires_server_spec(m) == ">=4.1.0"


def test_effective_spec_v4_manifest_pinned_stricter_floor_preserved():
    m = {"manifest_version": 4, "requires_server": ">=4.2.0"}
    assert v3.effective_requires_server_spec(m) == ">=4.2.0"


def test_effective_spec_v4_manifest_unparseable_floor_raised_to_min():
    m = {"manifest_version": 4, "requires_server": "not-a-spec"}
    assert v3.effective_requires_server_spec(m) == ">=4.1.0"


# --- template_load_manifest: v4 acceptance -----------------------------------


def test_v4_manifest_loads(tmp_path, monkeypatch):
    # The checkout's own VERSION is bumped to 4.1.0 only at release (Task 5);
    # this commit's code is exercised as-if-released.
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo = _toolkit(tmp_path)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(_v4_manifest(str(repo))), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is True, r
    assert r["manifest_version"] == 4


def test_v2_manifest_still_reports_migration_required(tmp_path):
    """RED-CANDIDATE regression guard: v4 acceptance must not disturb the v2
    path's migration_required contract."""
    repo = _toolkit(tmp_path)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {
        "version": 2, "variant": "general", "templateRepo": str(repo),
        "placeholders": {}, "files": {}, "lastSynced": "abc1234",
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is True, r
    assert r["migration_required"] is True


def test_v4_manifest_on_old_server_refused_by_name(tmp_path, monkeypatch):
    """The MIN_SERVER_FOR_V4 witness: a server claiming 4.0.3 refuses a v4
    manifest by name -- requires_server_satisfied fed the effective (>=4.1.0)
    spec against a server that predates it."""
    monkeypatch.setattr(ts, "__version__", "4.0.3")
    repo = _toolkit(tmp_path)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(_v4_manifest(str(repo))), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is False, r
    assert any("requires server >=4.1.0" in e and "4.0.3" in e for e in r["errors"]), r["errors"]


def test_v4_manifest_missing_declaration_keys_is_invalid(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo = _toolkit(tmp_path)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    m = _v4_manifest(str(repo))
    del m["instructions_file"]
    del m["agent_grants"]
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is False, r
    assert "errors" in r
    joined = " ".join(r["errors"])
    assert "instructions_file" in joined and "agent_grants" in joined


def test_known_top_level_keys_include_v4_declarations():
    unknown = v3.unknown_top_level_keys(
        {"manifest_version": 4, "instructions_file": "x", "agent_grants": "y"})
    assert unknown == []


# --- template_compute_status / template_apply_file / template_finalize_sync -
# dispatch a v4 manifest the same way a v3 one is dispatched (v3.manifest_
# supported), rather than falling through to the v2 legacy code path.


def test_compute_status_dispatches_v4_manifest_to_v3_path(tmp_path):
    repo = _toolkit(tmp_path)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    m = _v4_manifest(str(repo))
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")
    out = json.loads(asyncio.run(ts.template_compute_status(project_path=str(proj))))
    # The v2 legacy shape keys "up_to_date"/"conflict" in its summary; the
    # v3/v4 shape's summary keys "identical"/"template_updated" instead.
    assert "identical" in out["summary"], out
    assert out["manifest_version"] == 4
