"""PROJECT-CUSTOM region, finalize validation, and LF-write tests.

Coverage for the 2026-07-19 downstream sync findings:
- #2: region-aware sync (reclassification, apply-splice, three-way reattach)
- #5: LF-safe atomic writes on Windows
- #6: finalize rejects malformed hashes and path traversal
"""

import asyncio
import json

from template_sync import mcp as ts

REGION_TPL = (
    "<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n"
    "<!-- Project-specific rules, routing blocks, and extensions go here. -->\n"
    "<!-- PROJECT-CUSTOM:END -->"
)
REGION_PROJ = (
    "<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n"
    "# My project rules\n"
    "- rule one\n"
    "<!-- PROJECT-CUSTOM:END -->"
)

TPL_BODY_V1 = "# Template v1\n\nShared body.\n\n"
TPL_BODY_V2 = "# Template v2\n\nShared body, updated.\n\n"


def _mk_project(tmp_path, tpl_body, proj_body, *, tpl_hash_of=None, local_hash_of=None):
    """Build a toolkit repo + consumer project pair with a v2 manifest for CLAUDE.md."""
    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text(tpl_body, encoding="utf-8", newline="")

    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(proj_body, encoding="utf-8", newline="")

    manifest = {
        "version": 2,
        "templateRepo": str(repo),
        "variant": "general",
        "lastSynced": "",
        "placeholders": {},
        "files": {
            "CLAUDE.md": {
                "templateHash": ts._sha256(tpl_hash_of if tpl_hash_of is not None else tpl_body),
                "templateRawHash": ts._sha256(tpl_hash_of if tpl_hash_of is not None else tpl_body),
                "localHash": ts._sha256(local_hash_of if local_hash_of is not None else proj_body),
                "locallyModified": False,
            }
        },
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline=""
    )
    return repo, proj


# --- _split_custom_region unit behavior -------------------------------------

def test_split_no_markers():
    part, region = ts._split_custom_region("plain content\n")
    assert part == "plain content\n" and region is None


def test_split_with_region():
    content = TPL_BODY_V1 + REGION_PROJ + "\n"
    part, region = ts._split_custom_region(content)
    assert region == REGION_PROJ
    assert part == TPL_BODY_V1 + "\n"


def test_split_malformed_begin_only():
    content = "body\n<!-- PROJECT-CUSTOM:BEGIN -->\nno end marker\n"
    part, region = ts._split_custom_region(content)
    assert region is None and part == content


# --- compute_status reclassification ----------------------------------------

def _status(proj):
    return json.loads(asyncio.run(ts.template_compute_status(str(proj))))


def test_region_only_edit_reclassifies_up_to_date(tmp_path):
    tpl = TPL_BODY_V1 + REGION_TPL + "\n"
    proj_content = TPL_BODY_V1 + REGION_PROJ + "\n"
    # localHash recorded at sync time = template content (region then empty)
    _, proj = _mk_project(tmp_path, tpl, proj_content, local_hash_of=tpl)
    res = _status(proj)
    assert res["files"]["CLAUDE.md"]["status"] == "UP_TO_DATE"
    assert res["files"]["CLAUDE.md"]["region_reclassified"] is True


def test_conflict_collapses_to_auto_update_when_parts_equal(tmp_path):
    # Template moved to v2; project already carries v2 body + own region,
    # but manifest hashes still point at v1 (stale) => raw classification CONFLICT.
    tpl = TPL_BODY_V2 + REGION_TPL + "\n"
    proj_content = TPL_BODY_V2 + REGION_PROJ + "\n"
    old = TPL_BODY_V1 + REGION_TPL + "\n"
    _, proj = _mk_project(tmp_path, tpl, proj_content, tpl_hash_of=old, local_hash_of=old)
    res = _status(proj)
    assert res["files"]["CLAUDE.md"]["status"] == "AUTO_UPDATE"
    assert res["files"]["CLAUDE.md"]["region_reclassified"] is True


def test_real_body_drift_still_conflicts(tmp_path):
    tpl = TPL_BODY_V2 + REGION_TPL + "\n"
    proj_content = TPL_BODY_V1 + "project body edit\n" + REGION_PROJ + "\n"
    old = TPL_BODY_V1 + REGION_TPL + "\n"
    _, proj = _mk_project(tmp_path, tpl, proj_content, tpl_hash_of=old, local_hash_of=old)
    res = _status(proj)
    assert res["files"]["CLAUDE.md"]["status"] == "CONFLICT"
    assert res["files"]["CLAUDE.md"]["region_reclassified"] is False


def test_project_only_markers_stay_legacy(tmp_path):
    # Template has NO markers; project added them => legacy comparison.
    tpl = TPL_BODY_V1
    proj_content = TPL_BODY_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(tmp_path, tpl, proj_content, local_hash_of=tpl)
    res = _status(proj)
    assert res["files"]["CLAUDE.md"]["status"] == "PROJECT_CUSTOM"
    assert res["files"]["CLAUDE.md"]["region_reclassified"] is False


# --- apply_file region splice -------------------------------------------------

def test_apply_template_preserves_project_region(tmp_path):
    tpl = TPL_BODY_V2 + REGION_TPL + "\n"
    proj_content = TPL_BODY_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(tmp_path, tpl, proj_content)
    res = json.loads(asyncio.run(ts.template_apply_file(str(proj), "CLAUDE.md", source="template")))
    assert res["action"] == "written_from_template"
    assert res["region_preserved"] is True
    written = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert written.startswith(TPL_BODY_V2)          # template body adopted
    assert "# My project rules" in written           # project region preserved
    assert res["manifest_entry"]["localHash"] == ts._sha256(written)
    assert res["manifest_entry"]["locallyModified"] is True


def test_apply_template_no_project_file_writes_sentinel(tmp_path):
    tpl = TPL_BODY_V1 + REGION_TPL + "\n"
    _, proj = _mk_project(tmp_path, tpl, "irrelevant")
    (proj / "CLAUDE.md").unlink()
    res = json.loads(asyncio.run(ts.template_apply_file(str(proj), "CLAUDE.md", source="template")))
    assert res["region_preserved"] is False
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == tpl


# --- three-way merge region reattach -----------------------------------------

def test_three_way_reattaches_region(tmp_path):
    tpl = TPL_BODY_V2 + REGION_TPL + "\n"
    proj_content = TPL_BODY_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(tmp_path, tpl, proj_content)
    res = json.loads(asyncio.run(ts.template_get_diff(str(proj), "CLAUDE.md", diff_type="three_way")))
    merge = res["merge_result"]
    assert merge.get("region_reattached") is True
    assert "# My project rules" in merge["auto_merged"]
    # Region must not appear duplicated
    assert merge["auto_merged"].count("PROJECT-CUSTOM:BEGIN") == 1


# --- finalize validation ------------------------------------------------------

def _finalize(proj, applied):
    return json.loads(asyncio.run(ts.template_finalize_sync(str(proj), json.dumps(applied))))


def test_finalize_rejects_malformed_hash(tmp_path):
    tpl = TPL_BODY_V1
    _, proj = _mk_project(tmp_path, tpl, tpl)
    bad = [{"file_path": "CLAUDE.md", "manifest_entry": {
        "templateHash": "abc 123",  # stray space — the exact downstream corruption
        "templateRawHash": ts._sha256("x"),
        "localHash": ts._sha256("y"),
        "locallyModified": False,
    }}]
    res = _finalize(proj, bad)
    assert "error" in res and "validation failed" in res["error"]
    assert any("templateHash" in e for e in res["invalid_entries"])
    # Manifest untouched
    manifest = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert manifest["files"]["CLAUDE.md"]["templateHash"] == ts._sha256(tpl)


def test_finalize_rejects_path_traversal(tmp_path):
    tpl = TPL_BODY_V1
    _, proj = _mk_project(tmp_path, tpl, tpl)
    bad = [{"file_path": "../outside.md", "manifest_entry": {
        "templateHash": ts._sha256("a"), "templateRawHash": ts._sha256("b"),
        "localHash": ts._sha256("c"), "locallyModified": False,
    }}]
    res = _finalize(proj, bad)
    assert "error" in res
    assert any("file_path" in e for e in res["invalid_entries"])


def test_finalize_accepts_valid_entries(tmp_path):
    tpl = TPL_BODY_V1
    _, proj = _mk_project(tmp_path, tpl, tpl)
    good = [{"file_path": "CLAUDE.md", "manifest_entry": {
        "templateHash": ts._sha256(tpl), "templateRawHash": ts._sha256(tpl),
        "localHash": ts._sha256(tpl), "locallyModified": False,
    }}]
    res = _finalize(proj, good)
    assert res.get("error") is None
    assert res["files_updated"] == 1


# --- LF-safe writes -----------------------------------------------------------

def test_atomic_write_preserves_lf(tmp_path):
    target = tmp_path / "out.md"
    ts._write_file_atomic(target, "line1\nline2\n")
    raw = target.read_bytes()
    assert b"\r\n" not in raw
    assert raw == b"line1\nline2\n"
