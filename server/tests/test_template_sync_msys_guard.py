"""MSYS write-path guard on the three server tools that write to disk
(v4.0.1, item 9 -- SKILL.md item 9 names the client-side half).

`_resolve_path` already converts an MSYS-shaped read path (`/g/git/...` ->
`G:/git/...`) for lookups like `applied_files_path`. `template_apply_file`,
`template_finalize_sync` and `template_migrate_manifest` do not go through
it for `project_path`/`backup_dir` -- they call `pathlib.Path(...).resolve()`
directly, which on Windows resolves a leading `/` against the CURRENT drive,
not MSYS's drive-letter segment. Handed `/g/git/proj` from a `G:` process,
that silently creates a literal `G:\\g\\git\\proj` tree instead of refusing;
measured on a real sync as a stray `<drive>:\\<letter>\\...` tree. Each tool
must now refuse the shape outright and write nothing.
"""

import asyncio
import json

from template_sync import mcp as ts

MSYS_PATH = "/g/git/msys-guard-fixture"


def _snapshot(root) -> set[str]:
    return {str(p.relative_to(root)) for p in root.rglob("*")}


def test_apply_file_rejects_msys_project_path(tmp_path):
    before = _snapshot(tmp_path)
    res = json.loads(asyncio.run(ts.template_apply_file(MSYS_PATH, "CLAUDE.md")))
    assert "error" in res
    assert "MSYS path" in res["error"]
    assert MSYS_PATH in res["error"]
    assert _snapshot(tmp_path) == before


def test_apply_file_rejects_msys_backup_dir(tmp_path):
    proj = tmp_path / "proj"
    proj.mkdir()
    before = _snapshot(tmp_path)
    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir="/g/backup")))
    assert "error" in res
    assert "MSYS path" in res["error"]
    assert "/g/backup" in res["error"]
    assert _snapshot(tmp_path) == before


def test_finalize_sync_rejects_msys_project_path(tmp_path):
    before = _snapshot(tmp_path)
    res = json.loads(asyncio.run(ts.template_finalize_sync(MSYS_PATH)))
    assert "error" in res
    assert "MSYS path" in res["error"]
    assert _snapshot(tmp_path) == before


def test_migrate_manifest_rejects_msys_project_path(tmp_path):
    before = _snapshot(tmp_path)
    res = json.loads(asyncio.run(ts.template_migrate_manifest(MSYS_PATH, dry_run=True)))
    assert "error" in res
    assert "MSYS path" in res["error"]
    assert _snapshot(tmp_path) == before


def test_migrate_manifest_rejects_msys_backup_dir(tmp_path):
    proj = tmp_path / "proj"
    proj.mkdir()
    before = _snapshot(tmp_path)
    res = json.loads(asyncio.run(
        ts.template_migrate_manifest(str(proj), backup_dir="/g/backup")))
    assert "error" in res
    assert "MSYS path" in res["error"]
    assert _snapshot(tmp_path) == before


def test_reject_msys_path_leaves_ordinary_paths_alone():
    """Two-sided: a Windows path and a repo-relative path must NOT be
    flagged, or every real call to these tools would refuse."""
    assert ts._reject_msys_path(r"G:\git\proj") is None
    assert ts._reject_msys_path("relative/proj") is None
    assert ts._reject_msys_path("") is None
