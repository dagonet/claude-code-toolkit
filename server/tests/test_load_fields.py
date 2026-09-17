"""server_commit in the load response (Task 4).

`server_commit` reports the toolkit commit this SERVER PROCESS imported at
spawn (`SERVER_COMMIT`, computed once at import via `_git_head_of` on
`SERVER_SOURCE_DIR`), beside `template_commit`/`lastSynced`, which each call
re-reads from the project's manifest on disk. The two drift apart the moment
the toolkit is pulled mid-session; this key makes that skew visible instead of
letting a reader assume both track the same commit.
"""

import asyncio
import json
import pathlib
import subprocess

import pytest

from template_sync import mcp as ts


def test_server_commit_is_the_checkout_head_at_import():
    expected = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True,
        cwd=ts.SERVER_SOURCE_DIR, check=True,
    ).stdout.strip()
    assert ts.SERVER_COMMIT == expected


def _write_v2_project(tmp_path):
    """A minimal v2 manifest project, modeled on `_write_project`/`V2` in
    test_template_sync_v3_gate.py (there is no `v2_project` fixture and no
    conftest.py in this suite -- test modules do not import each other, so
    this is a local copy rather than a cross-module import)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {
        "version": 2, "variant": "general", "lastSynced": "abc1234",
        "placeholders": {}, "files": {}, "templateRepo": str(repo),
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8"
    )
    return proj


def _write_manifest_missing_a_required_field(tmp_path):
    """A valid-JSON manifest with a non-None `manifest` but a non-empty
    `errors` list -- the "errors shape" (mcp.py's second `template_load_manifest`
    return, distinct from both the no-manifest-at-all shape and the legacy v2
    shape above): `_load_manifest` appends "Missing required field: files"
    (mcp.py:352) while still returning the parsed dict, since `placeholders`
    is present but `files` is not.
    """
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {"version": 2, "variant": "general", "templateRepo": str(repo), "placeholders": {}}
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8"
    )
    return proj


def test_load_response_carries_server_commit_unconditionally(tmp_path):
    v2_project = _write_v2_project(tmp_path)
    # template_load_manifest is async; the moved suite's own helper awaits it
    # via asyncio.run rather than calling it bare (test_template_sync_v3_gate.py).
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(v2_project))))
    assert "server_commit" in r
    assert r["server_commit"] == ts.SERVER_COMMIT


def test_load_response_carries_server_commit_with_no_manifest_at_all(tmp_path):
    # Mirrors test_server_source_reports_the_imported_package_directory in
    # test_template_sync_v3_gate.py: server_source is present on this
    # "valid": False / no-manifest path so a caller diagnosing which build is
    # live never needs a valid project to ask. server_commit is the same
    # diagnostic and must be unconditional in the same sense.
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(tmp_path / "nonexistent"))))
    assert r["valid"] is False
    assert r["server_commit"] == ts.SERVER_COMMIT


def test_load_response_carries_server_commit_on_the_v3_path(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps({"rules": []}), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {
        "manifest_version": 3, "template_version": "3.1.0", "template_commit": "abc1234",
        "variant": "general", "placeholders": {}, "requires_server": ">=0.3.0", "files": {},
        "templateRepo": str(repo),
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is True
    assert r["manifest_version"] == 3
    assert r["server_commit"] == ts.SERVER_COMMIT


# --- registered_tools: identity/registry/capabilities pinned at one moment
# (Task 2, v4.0.2 spec item 5). Every template_load_manifest response shape
# carries it beside "capabilities" -- the brief names three ("manifest-less",
# "errors", "v3"), but mcp.py has FOUR return dicts with "capabilities": the
# no-manifest-at-all shape and the errors-present shape are textually
# identical in KEYS (both "valid": False / same field set) yet are two
# distinct return statements, and the legacy v2 shape (this file's
# `_write_v2_project` fixture) is a fourth. All four are asserted here so a
# v2-manifest consumer is never silently missing the capability the registry
# equally advertises to it.


def test_load_response_carries_registered_tools_with_no_manifest_at_all(tmp_path):
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(tmp_path / "nonexistent"))))
    assert r["valid"] is False
    assert r["registered_tools"] == ts._registered_tool_names()
    assert r["registered_tools"] == sorted(r["registered_tools"])
    assert "template_verify" in r["registered_tools"]


def test_load_response_carries_registered_tools_on_the_errors_shape(tmp_path):
    proj = _write_manifest_missing_a_required_field(tmp_path)
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is False
    assert r["errors"] == ["Missing required field: files"]
    assert r["registered_tools"] == ts._registered_tool_names()
    assert "template_verify" in r["registered_tools"]


def test_load_response_carries_registered_tools_on_the_v3_path(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps({"rules": []}), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    manifest = {
        "manifest_version": 3, "template_version": "3.1.0", "template_commit": "abc1234",
        "variant": "general", "placeholders": {}, "requires_server": ">=0.3.0", "files": {},
        "templateRepo": str(repo),
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(proj))))
    assert r["valid"] is True
    assert r["registered_tools"] == ts._registered_tool_names()
    assert "template_verify" in r["registered_tools"]


def test_load_response_carries_registered_tools_on_the_legacy_v2_path(tmp_path):
    v2_project = _write_v2_project(tmp_path)
    r = json.loads(asyncio.run(ts.template_load_manifest(project_path=str(v2_project))))
    assert r["registered_tools"] == ts._registered_tool_names()
    assert "template_verify" in r["registered_tools"]


@pytest.mark.parametrize("template_repo_form", [
    "G:/git/claude-code-toolkit",          # forward slashes, Windows drive
    "G:\\git\\claude-code-toolkit",         # backslashes
    "/g/git/claude-code-toolkit",           # MSYS form written by setup-project.sh:20 (cd && pwd under Git Bash)
])
def test_server_in_template_repo_true_across_path_namespaces(template_repo_form, monkeypatch):
    # The server's source dir, in Windows form, is inside the repo in all three spellings.
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", "G:\\git\\claude-code-toolkit\\server\\src\\template_sync")
    assert ts._server_in_template_repo(template_repo_form) is True


def test_server_in_template_repo_false_for_the_old_server(monkeypatch):
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", "G:\\git\\mcp-dev-servers\\src\\mcp_dev_servers")
    assert ts._server_in_template_repo("/g/git/claude-code-toolkit") is False


def test_server_in_template_repo_false_when_unresolvable(monkeypatch):
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", "G:\\git\\claude-code-toolkit\\server\\src\\template_sync")
    assert ts._server_in_template_repo("") is False
    assert ts._server_in_template_repo("not-a-path-that-exists-anywhere") is False


def test_git_head_of_is_none_outside_a_git_checkout(tmp_path, monkeypatch):
    """`git rev-parse HEAD` searches upward for an enclosing .git. A
    test-scoped GIT_CEILING_DIRECTORIES (tmp_path's parent) confines that
    search to tmp_path itself, so this test is independent of where
    --basetemp lives -- it does not rely on the project's --basetemp
    convention keeping basetemp outside any checkout.

    GIT_CEILING_DIRECTORIES was measured and rejected as a fix inside
    _git_head_of itself: setting the ceiling to a probed path's immediate
    parent stops `git rev-parse` from finding a `.git` several levels further
    up -- exactly the topology of the real SERVER_SOURCE_DIR call
    (server/src/template_sync, with .git at the repo root), so it would turn
    the real SERVER_COMMIT into None. See task-4 report for the two probe
    outputs. The helper stays as-is; only this test sets the ceiling, and
    only in its own subprocess environment.
    """
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path.parent))
    assert ts._git_head_of(str(tmp_path)) is None
