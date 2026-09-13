"""Manifest v3 detection, hash forms, and the requires_server gate (review §2.1, §2.2, §2.5, §2.6)."""

import asyncio
import json

import pytest

from template_sync import mcp as ts
from template_sync import v3


def test_is_v3_and_commit_alias():
    assert v3.is_v3({"manifest_version": 3}) is True
    assert v3.is_v3({"version": 2}) is False
    assert v3.is_v3({}) is False
    assert v3.manifest_commit({"template_commit": "abc"}) == "abc"
    assert v3.manifest_commit({"lastSynced": "def"}) == "def"
    assert v3.manifest_commit({"template_commit": "", "lastSynced": "def"}) == "def"
    assert v3.manifest_commit({}) == ""


def test_hash_forms():
    hx = "a" * 64
    assert v3.parse_hash("sha256:" + hx) == hx
    assert v3.parse_hash(hx) == hx
    assert v3.parse_hash("") == ""
    assert v3.parse_hash("sha256:zz") == ""
    assert v3.format_hash(hx) == "sha256:" + hx


@pytest.mark.parametrize("spec,server,ok", [
    (">=0.3.0", "0.3.0", True),
    (">=0.3.0", "0.3.1", True),
    (">=0.3.0", "1.0.0", True),
    (">=0.3.0", "0.2.1", False),
    (">=0.10.0", "0.9.9", False),
    ("", "0.3.0", True),
    ("^0.3.0", "0.3.0", False),
    (">=x.y", "0.3.0", False),
])
def test_requires_server_satisfied(spec, server, ok):
    result, reason = v3.requires_server_satisfied(spec, server)
    assert result is ok
    if not ok:
        assert reason


def test_server_source_reports_the_imported_package_directory(tmp_path):
    """An editable install's dist-info is stamped at install time and never
    re-stamped, so `pip show` can say 0.3.0 while the process runs 0.3.2 --
    measured on this machine during the v3.1 round. server_version already
    reads from the imported source; server_source says WHICH checkout that is,
    so the ambiguity is closed rather than inferred."""
    import pathlib

    import template_sync

    expected = str(pathlib.Path(template_sync.__file__).parent)
    # Present even when there is no manifest at all: a caller diagnosing which
    # build is live must not need a valid project to ask.
    res = _load(tmp_path / "nonexistent")
    assert res["valid"] is False
    assert res["server_source"] == expected
    assert (pathlib.Path(res["server_source"]) / "__init__.py").is_file()


def test_server_source_present_on_a_valid_v3_load(tmp_path):
    import pathlib

    import template_sync

    proj = _write_project(tmp_path, V3, {"rules": []})
    res = _load(proj)
    assert res["valid"] is True
    assert res["server_source"] == str(pathlib.Path(template_sync.__file__).parent)


def test_unknown_top_level_keys():
    m = {"manifest_version": 3, "files": {}, "deletedAcknowledged": [], "variant": "general"}
    assert v3.unknown_top_level_keys(m) == ["deletedAcknowledged"]


# --- template_load_manifest as the v3 gate (Task 3) ---------------------------


def _write_project(tmp_path, manifest: dict, ownership: dict | None):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    if ownership is not None:
        (repo / "templates" / "ownership.json").write_text(json.dumps(ownership), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = dict(manifest, templateRepo=str(repo))
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return proj


def _load(proj):
    return json.loads(asyncio.run(ts.template_load_manifest(str(proj))))


V3 = {
    "manifest_version": 3, "template_version": "3.1.0", "template_commit": "abc1234",
    "variant": "general", "placeholders": {}, "requires_server": ">=0.3.0", "files": {},
}
V2 = {"version": 2, "variant": "general", "lastSynced": "abc1234", "placeholders": {}, "files": {}}


def test_load_v3_reports_server_version_and_no_migration(tmp_path):
    proj = _write_project(tmp_path, dict(V3, stray="x"), {"rules": []})
    res = _load(proj)
    assert res["valid"] is True
    assert res["manifest_version"] == 3
    assert res["migration_required"] is False
    assert res["server_version"] == ts.__version__
    assert res["template_commit"] == "abc1234"
    assert res["unknown_keys"] == ["stray"]


def test_load_v3_refuses_when_requires_server_unsatisfied(tmp_path):
    proj = _write_project(tmp_path, dict(V3, requires_server=">=99.0.0"), {"rules": []})
    res = _load(proj)
    assert res["valid"] is False
    assert res["server_version"] == ts.__version__
    assert any("requires server >=99.0.0" in e for e in res["errors"])


def test_load_v3_missing_required_fields(tmp_path):
    m = {k: v for k, v in V3.items() if k not in ("template_commit", "requires_server")}
    proj = _write_project(tmp_path, m, {"rules": []})
    res = _load(proj)
    assert res["valid"] is False
    assert "Missing required field: template_commit" in res["errors"]
    assert "Missing required field: requires_server" in res["errors"]


def test_load_v2_migration_required_only_with_ownership_file(tmp_path):
    proj = _write_project(tmp_path, V2, None)
    res = _load(proj)
    assert res["valid"] is True
    assert res["version"] == 2
    assert res["manifest_version"] == 2
    assert res["migration_required"] is False
    assert res["server_version"] == ts.__version__

    proj2 = _write_project(tmp_path / "b", V2, {"rules": []})
    res2 = _load(proj2)
    assert res2["migration_required"] is True
