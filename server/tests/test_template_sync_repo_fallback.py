"""templateRepo fallback (v4.5.1, item 3).

A project's committed .claude/template-manifest.json stores templateRepo as
the absolute path of the machine that wrote it ("G:/git/claude-code-toolkit").
On any other host that path does not exist and every manifest-based call used
to fail. When the declared repo is not an existing directory here, the server
falls back to the toolkit checkout it itself runs from, says so in the tool
output, and never writes the fallback back into the manifest.
"""

import asyncio
import json
import pathlib

from template_sync import mcp as ts
from template_sync import v3

MISSING = "G:/git/claude-code-toolkit-does-not-exist"


def _toolkit(root: pathlib.Path) -> pathlib.Path:
    (root / "templates" / "general").mkdir(parents=True)
    (root / "user-level-reference").mkdir(parents=True)
    return root


def _project(tmp_path: pathlib.Path, template_repo: str) -> tuple[pathlib.Path, pathlib.Path, bytes]:
    pp = tmp_path / "proj"
    (pp / ".claude").mkdir(parents=True)
    mf = pp / ".claude" / "template-manifest.json"
    mf.write_text(json.dumps({
        "version": 2, "variant": "general", "templateRepo": template_repo,
        "placeholders": {}, "files": {}, "lastSynced": "",
    }), encoding="utf-8")
    return pp, mf, mf.read_bytes()


def _load(pp: pathlib.Path) -> dict:
    return json.loads(asyncio.run(ts.template_load_manifest(str(pp))))


def test_existing_template_repo_is_used_unchanged(tmp_path, monkeypatch):
    repo = _toolkit(tmp_path / "declared")
    other = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: other)
    pp, _, _ = _project(tmp_path, str(repo))
    res = _load(pp)
    assert "template_repo_note" not in res
    assert not any("Template directory not found" in e for e in res["errors"])
    assert ts._get_template_dir({"templateRepo": str(repo), "variant": "general"}) == repo.resolve() / "templates" / "general"


def test_missing_repo_falls_back_to_server_checkout_with_note(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    pp, _, _ = _project(tmp_path, MISSING)
    res = _load(pp)
    assert not any("Template directory not found" in e for e in res["errors"])
    assert res["template_repo_note"] == (
        f"templateRepo {MISSING} not found on this machine; using the server's own checkout {checkout}")
    assert ts._template_repo_resolved({"templateRepo": MISSING}) == str(checkout)
    assert ts._get_template_dir({"templateRepo": MISSING, "variant": "general"}) == checkout / "templates" / "general"


def test_every_resolution_site_uses_the_fallback(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    # load_ownership reads <repo>/templates/ownership.json: the path it asks for proves what it resolved
    seen = {}
    real = v3.core._read_file
    monkeypatch.setattr(v3.core, "_read_file", lambda p: seen.setdefault("p", pathlib.Path(p)) and real(p))
    v3.load_ownership(MISSING)
    assert seen["p"] == checkout / "templates" / "ownership.json"
    assert ts._template_file_path({"templateRepo": MISSING, "variant": "general"}, "hooks/x.sh") == checkout / "hooks" / "x.sh"


def test_missing_repo_and_server_outside_a_checkout_keeps_todays_error(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    pp, _, _ = _project(tmp_path, MISSING)
    res = _load(pp)
    assert "template_repo_note" not in res
    assert any("Template directory not found" in e for e in res["errors"])


def test_manifest_file_is_never_modified(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    pp, mf, before = _project(tmp_path, MISSING)
    mtime = mf.stat().st_mtime_ns
    _load(pp)
    json.loads(asyncio.run(ts.template_compute_status(str(pp))))
    assert mf.read_bytes() == before
    assert mf.stat().st_mtime_ns == mtime


def test_server_toolkit_root_is_derived_from_the_package_location(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "tk")
    src = checkout / "server" / "src" / "template_sync"
    src.mkdir(parents=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(src))
    assert ts._server_toolkit_root() == checkout
    bare = tmp_path / "site-packages" / "template_sync"
    bare.mkdir(parents=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(bare))
    assert ts._server_toolkit_root() is None
