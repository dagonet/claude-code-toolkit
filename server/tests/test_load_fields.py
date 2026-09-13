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


def test_git_head_of_is_none_outside_a_git_checkout(tmp_path):
    """`git rev-parse HEAD` searches upward for an enclosing .git, so this
    holds only while tmp_path is outside any git work tree. This project's
    pytest --basetemp convention (see the brief/CLAUDE.md for how the moved
    suite is invoked) keeps basetemp outside any checkout; an implementer who
    points --basetemp inside a checkout would find `tmp_path` picking up that
    checkout's HEAD instead of None.

    GIT_CEILING_DIRECTORIES was measured and rejected as a fix inside
    _git_head_of itself: setting the ceiling to a probed path's immediate
    parent stops `git rev-parse` from finding a `.git` several levels further
    up -- exactly the topology of the real SERVER_SOURCE_DIR call
    (server/src/template_sync, with .git at the repo root), so it would turn
    the real SERVER_COMMIT into None. See task-4 report for the two probe
    outputs.
    """
    assert ts._git_head_of(str(tmp_path)) is None
