"""v4.3.1 S-8 (issue #173, ruling S-8): a file that exists on disk but is untracked by the manifest is
never overwritten by a sync unless the caller says so.

`new_template_files` means "absent from the manifest", not "absent from the project"; the server used
to overwrite such a file (with a backup, but without asking)."""

import asyncio
import json
import subprocess

from template_sync import mcp as ts

OWNERSHIP = {"tracked_paths": ["hooks", "templates"],
             "rules": [{"pattern": "hooks/**", "ownership": "template"}]}

MINE = "echo my project-specific gate\n"
TEMPLATE = "echo template version\n"


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _fixture(tmp_path, on_disk=MINE):
    """Template ships hooks/g.sh and hooks/h.sh; the manifest tracks neither.
    The project has hooks/g.sh (project content) and no hooks/h.sh."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    for name in ("g.sh", "h.sh"):
        tpl = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, f"hooks/{name}")
        tpl.parent.mkdir(parents=True, exist_ok=True)
        tpl.write_text(TEMPLATE, encoding="utf-8", newline="")
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "v1")
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "hooks").mkdir()
    (proj / "hooks" / "g.sh").write_text(on_disk, encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3, "template_version": None, "template_commit": head,
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.2", "files": {},
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return proj


def _run(coro):
    return json.loads(asyncio.run(coro))


def _apply(proj, rel, tmp_path, **kw):
    return _run(ts.template_apply_file(str(proj), rel, backup_dir=str(tmp_path / "bak"), **kw))


def test_status_marks_new_template_files_present_on_disk(tmp_path):
    proj = _fixture(tmp_path)
    detail = {d["path"]: d for d in _run(ts.template_compute_status(str(proj)))["new_template_files_detail"]}
    assert detail["hooks/g.sh"]["present_on_disk"] is True
    assert detail["hooks/h.sh"]["present_on_disk"] is False


def test_apply_refuses_to_overwrite_an_untracked_file_on_disk(tmp_path):
    proj = _fixture(tmp_path)
    res = _apply(proj, "hooks/g.sh", tmp_path, source="template")
    assert "overwrite_existing" in res.get("error", ""), res
    assert (proj / "hooks" / "g.sh").read_text(encoding="utf-8") == MINE


def test_apply_provided_content_is_refused_too(tmp_path):
    proj = _fixture(tmp_path)
    res = _apply(proj, "hooks/g.sh", tmp_path, source="provided", content="echo other\n")
    assert "overwrite_existing" in res.get("error", ""), res
    assert (proj / "hooks" / "g.sh").read_text(encoding="utf-8") == MINE


def test_apply_overwrites_when_asked(tmp_path):
    proj = _fixture(tmp_path)
    res = _apply(proj, "hooks/g.sh", tmp_path, source="template", overwrite_existing=True)
    assert "error" not in res, res
    assert (proj / "hooks" / "g.sh").read_text(encoding="utf-8") == TEMPLATE
    assert res["backup"], "the pre-image is still backed up"


def test_apply_creates_an_absent_new_file_without_the_flag(tmp_path):
    proj = _fixture(tmp_path)
    res = _apply(proj, "hooks/h.sh", tmp_path, source="template")
    assert res["action"] == "created_from_template"


def test_overwrite_existing_is_a_declared_parameter(tmp_path):
    proj = _fixture(tmp_path)
    out = asyncio.run(ts.mcp.call_tool("template_apply_file", {
        "project_path": str(proj), "file_path": "hooks/g.sh", "source": "template",
        "backup_dir": str(tmp_path / "bak"), "overwrite_existing": True}))
    assert "unknown parameter" not in str(out)
    assert (proj / "hooks" / "g.sh").read_text(encoding="utf-8") == TEMPLATE
