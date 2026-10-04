"""v4.3.1 S7 (ruling P-1): template_get_diff's base under a v3/v4 manifest.

open-brain (2026-09-30) and MM-Agent (2026-10-02): diff_type="template_changes"
returned has_changes: false and fallback_to_two_way: true on files compute_status
had just classified TEMPLATE_UPDATED; diff_type="full" showed the real diff."""

import asyncio
import json
import subprocess

from template_sync import mcp as ts
from template_sync import v3

OWNERSHIP = {"tracked_paths": ["hooks", "templates"],
             "rules": [{"pattern": "hooks/**", "ownership": "template"}]}


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _head(repo) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _fixture(tmp_path, held_commit=None, project_text="echo v1\n"):
    """Template hooks/g.sh: v1 at commit c1, v2 at HEAD. The consumer holds c1
    (manifest v3, no lastSynced -- what finalize writes since v4.0.1)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    tpl = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, "hooks/g.sh")
    tpl.parent.mkdir(parents=True, exist_ok=True)
    tpl.write_text("echo v1\n", encoding="utf-8", newline="")
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "v1")
    c1 = _head(repo)
    tpl.write_text("echo v2\n", encoding="utf-8", newline="")
    _git(repo, "commit", "-q", "-am", "v2")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "hooks").mkdir()
    (proj / "hooks" / "g.sh").write_text(project_text, encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3, "template_version": None, "template_commit": held_commit or c1,
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.2",
        "files": {"hooks/g.sh": {"hash": "sha256:" + ts._sha256("echo v1\n"), "ownership": "template"}},
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return repo, proj, c1


def _diff(proj, diff_type):
    return json.loads(asyncio.run(ts.template_get_diff(str(proj), "hooks/g.sh", diff_type)))


def test_template_changes_reads_the_base_at_template_commit(tmp_path):
    repo, proj, c1 = _fixture(tmp_path)
    manifest = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    status = v3.compute_status_v3(proj, manifest, v3.load_ownership(str(repo)))
    assert status["files"]["hooks/g.sh"]["status"] == "TEMPLATE_UPDATED"   # the field report's premise
    res = _diff(proj, "template_changes")
    assert res["fallback_to_two_way"] is False
    assert res["has_changes"] is True
    assert "-echo v1" in res["unified_diff"] and "+echo v2" in res["unified_diff"]
    assert res["base"] == c1


def test_local_changes_reads_the_base_at_template_commit(tmp_path):
    repo, proj, c1 = _fixture(tmp_path, project_text="echo mine\n")
    res = _diff(proj, "local_changes")
    assert res["has_changes"] is True
    assert "-echo v1" in res["unified_diff"] and "+echo mine" in res["unified_diff"]


def test_unrecoverable_base_is_reported_never_no_changes(tmp_path):
    repo, proj, c1 = _fixture(tmp_path, held_commit="f" * 40)
    for diff_type in ("template_changes", "local_changes"):
        res = _diff(proj, diff_type)
        assert res["has_changes"] is None, diff_type
        assert res["unified_diff"] == ""
        assert "base unavailable" in res["base_unavailable_reason"]
        assert "f" * 40 in res["base_unavailable_reason"]


def test_full_diff_is_unchanged(tmp_path):
    repo, proj, c1 = _fixture(tmp_path)
    res = _diff(proj, "full")
    assert res["has_changes"] is True and "+echo v1" in res["unified_diff"]
