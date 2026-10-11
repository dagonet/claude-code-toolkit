"""Running server older/newer than the template checkout's VERSION (stale-session skew)."""

import asyncio
import json
import pathlib

import pytest

from template_sync import mcp as ts

V3 = {
    "manifest_version": 3, "template_version": "3.1.0", "template_commit": "abc1234",
    "variant": "general", "placeholders": {}, "requires_server": ">=0.3.0", "files": {},
}


def _project(tmp_path, manifest=V3, checkout_version=None):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps({"rules": []}), encoding="utf-8")
    if checkout_version is not None:
        (repo / "VERSION").write_text(checkout_version, encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(dict(manifest, templateRepo=str(repo))), encoding="utf-8")
    return proj, repo


def _load(proj):
    return json.loads(asyncio.run(ts.template_load_manifest(str(proj))))


def _status(proj):
    return json.loads(asyncio.run(ts.template_compute_status(str(proj))))


def _bump(version: str, delta: int) -> str:
    major, minor, patch = (int(x) for x in version.split("."))
    return f"{major}.{minor}.{patch + delta}" if patch + delta >= 0 else f"{major}.{minor}.0"


def test_equal_versions_load_ok_without_note(tmp_path):
    proj, _ = _project(tmp_path, checkout_version=ts.__version__ + "\n")
    res = _load(proj)
    assert res["valid"] is True
    assert "version_skew_note" not in res


def test_server_older_than_checkout_refuses_load(tmp_path):
    newer = _bump(ts.__version__, 1)
    proj, repo = _project(tmp_path, checkout_version=newer + "\n")
    res = _load(proj)
    assert res["valid"] is False
    msg = " ".join(res["errors"])
    assert ts.__version__ in msg and newer in msg and str(repo) in msg
    assert "Restart the session" in msg and "bash server/install.sh" in msg


def test_server_newer_than_checkout_loads_with_note(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "__version__", "9.9.9")
    proj, _ = _project(tmp_path, checkout_version="9.9.8\n")
    res = _load(proj)
    assert res["valid"] is True
    assert "9.9.9" in res["version_skew_note"] and "9.9.8" in res["version_skew_note"]


@pytest.mark.parametrize("content", [None, "", "not-a-version\n", "1.2\n"])
def test_missing_or_unparseable_checkout_version_is_no_finding(tmp_path, content):
    proj, _ = _project(tmp_path, checkout_version=content)
    res = _load(proj)
    assert res["valid"] is True
    assert "version_skew_note" not in res


def test_compute_status_carries_note_but_does_not_refuse(tmp_path):
    newer = _bump(ts.__version__, 1)
    proj, _ = _project(tmp_path, checkout_version=newer + "\n")
    res = _status(proj)
    assert "error" not in res
    assert newer in res["version_skew_note"] and ts.__version__ in res["version_skew_note"]


def test_requires_server_refusal_still_applies(tmp_path):
    proj, _ = _project(tmp_path, dict(V3, requires_server=">=99.0.0"),
                       checkout_version=ts.__version__ + "\n")
    res = _load(proj)
    assert res["valid"] is False
    assert any("requires server >=99.0.0" in e for e in res["errors"])
    assert not any("Restart the session" in e for e in res["errors"])
