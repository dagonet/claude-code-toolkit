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
import subprocess

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
