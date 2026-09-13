"""Keep-mine ("skip") classification tests.

Consumer finding 2026-08-29 (data-loss class): a file registered via
`template_apply_file(source="skip")` deviates from the template it was synced
against, but `template_compute_status` reported it as AUTO_UPDATE with
`locally_modified: false` as long as the project file had not changed *since*
the last sync -- so the next sync overwrote the project's content.
"""

import asyncio
import json

from template_sync import mcp as ts

REGION_TPL = (
    "<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n"
    "<!-- Project-specific rules go here. -->\n"
    "<!-- PROJECT-CUSTOM:END -->"
)
REGION_PROJ = (
    "<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n"
    "# My project rules\n"
    "<!-- PROJECT-CUSTOM:END -->"
)

TPL_V1 = "# Template v1\n\nShared body.\n"
TPL_V2 = "# Template v2\n\nShared body, updated.\n"


def _mk_project(tmp_path, tpl_body, proj_body, *, entry_overrides=None):
    """Toolkit repo + consumer project with a v2 manifest entry for CLAUDE.md.

    Manifest hashes default to "synced against `tpl_body`, project file
    unchanged since that sync" -- callers override what the scenario needs.
    """
    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text(tpl_body, encoding="utf-8", newline="")

    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(proj_body, encoding="utf-8", newline="")

    entry = {
        "templateHash": ts._sha256(tpl_body),
        "templateRawHash": ts._sha256(tpl_body),
        "localHash": ts._sha256(proj_body),
        "locallyModified": False,
    }
    entry.update(entry_overrides or {})

    manifest = {
        "version": 2,
        "templateRepo": str(repo),
        "variant": "general",
        "lastSynced": "",
        "placeholders": {},
        "files": {"CLAUDE.md": entry},
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline=""
    )
    return repo, proj


def _status(proj):
    return json.loads(asyncio.run(ts.template_compute_status(str(proj))))


def _part_hashes(proj_body, tpl_body):
    """(project part, template part) hashes with the single-sided fallback."""
    proj_part, proj_region = ts._split_custom_region(proj_body)
    tpl_part, tpl_region = ts._split_custom_region(tpl_body)
    if proj_region is None or tpl_region is None:
        proj_part, tpl_part = proj_body, tpl_body
    return ts._sha256(proj_part), ts._sha256(tpl_part)


def _keep_mine_entry(tpl_at_sync, proj_body):
    """Manifest entry as `template_apply_file(source='skip')` records it."""
    local_part, tpl_part = _part_hashes(proj_body, tpl_at_sync)
    return {
        "templateHash": ts._sha256(tpl_at_sync),
        "templateRawHash": ts._sha256(tpl_at_sync),
        "localHash": ts._sha256(proj_body),
        "locallyModified": True,
        "localPartHash": local_part,
        "templatePartHashAtSync": tpl_part,
        "resolution": "keep-mine",
    }


def _legacy_keep_mine_entry(tpl_at_sync, proj_body):
    """Pre-round-1 entry shape: no part hashes at all."""
    return {
        "templateHash": ts._sha256(tpl_at_sync),
        "templateRawHash": ts._sha256(tpl_at_sync),
        "localHash": ts._sha256(proj_body),
        "locallyModified": True,
        "resolution": "keep-mine",
    }


# --- (a) skip-registered + template changed => CONFLICT ----------------------

def test_keep_mine_with_changed_template_is_conflict(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V2, proj_body,
        entry_overrides=_keep_mine_entry(TPL_V1, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "CONFLICT"
    assert f["deviates_from_template"] is True
    assert f["locally_modified"] is True
    assert f["changed_since_sync"] is False
    assert f["resolution_at_sync"] == "keep-mine"


# --- (b) skip-registered + template unchanged => PROJECT_CUSTOM -------------

def test_keep_mine_with_unchanged_template_is_project_custom(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V1, proj_body,
        entry_overrides=_keep_mine_entry(TPL_V1, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "PROJECT_CUSTOM"
    assert f["deviates_from_template"] is True
    assert f["locally_modified"] is True


# --- (c) clean file + template changed => AUTO_UPDATE ------------------------

def test_clean_file_with_changed_template_is_auto_update(tmp_path):
    _, proj = _mk_project(
        tmp_path, TPL_V2, TPL_V1,
        entry_overrides={
            "templateHash": ts._sha256(TPL_V1),
            "templateRawHash": ts._sha256(TPL_V1),
            "localHash": ts._sha256(TPL_V1),
            "localPartHash": ts._sha256(TPL_V1),
            "templatePartHashAtSync": ts._sha256(TPL_V1),
        },
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "AUTO_UPDATE"
    assert f["deviates_from_template"] is False
    assert f["locally_modified"] is False
    assert f["resolution_at_sync"] == ""
    assert f["hint"] == ""


# --- (d) region-only deviation keeps the existing reclassification ----------

def test_legacy_region_only_deviation_still_reclassifies(tmp_path):
    old_tpl = TPL_V1 + REGION_TPL + "\n"
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V2 + REGION_PROJ + "\n"
    _, proj = _mk_project(
        tmp_path, new_tpl, proj_body,
        entry_overrides={
            "templateHash": ts._sha256(old_tpl),
            "templateRawHash": ts._sha256(old_tpl),
            "localHash": ts._sha256(old_tpl),
        },
    )
    res = _status(proj)
    f = res["files"]["CLAUDE.md"]
    assert f["status"] == "AUTO_UPDATE"
    assert f["region_reclassified"] is True
    # Raw fields stay honest: the collapse to AUTO_UPDATE is explained by
    # region_reclassified, not by pretending the file matches the template.
    assert f["deviates_from_template"] is True
    assert f["locally_modified"] is True
    # ...but a reclassified file is not a genuine deviation for the summary.
    assert res["summary"] == {**res["summary"], "auto_update": 1, "deviating": 0}


def _region_spliced_entry(old_tpl, proj_body):
    """Entry as a region-preserving `source="template"` apply records it."""
    local_part, tpl_part = _part_hashes(proj_body, old_tpl)
    return {
        "templateHash": ts._sha256(old_tpl),
        "templateRawHash": ts._sha256(old_tpl),
        "localHash": ts._sha256(proj_body),
        "locallyModified": True,
        "localPartHash": local_part,
        "templatePartHashAtSync": tpl_part,
    }


# --- (g) region-spliced file, template moves OUTSIDE the region -> AUTO_UPDATE

def test_region_spliced_file_with_template_move_outside_region_is_auto_update(tmp_path):
    old_tpl = TPL_V1 + REGION_TPL + "\n"
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V1 + REGION_PROJ + "\n"  # written by a region-preserving apply
    _, proj = _mk_project(
        tmp_path, new_tpl, proj_body,
        entry_overrides=_region_spliced_entry(old_tpl, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "AUTO_UPDATE"
    assert f["locally_modified"] is False
    assert f["deviates_from_template"] is False
    assert f["region_only"] is True

    # ...and applying the template keeps the project's region.
    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    assert res["region_preserved"] is True
    written = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert REGION_PROJ in written and TPL_V2 in written


# --- (h) template moves INSIDE its own region placeholder -------------------

def test_template_move_inside_region_placeholder_keeps_project_region(tmp_path):
    old_tpl = TPL_V1 + REGION_TPL + "\n"
    new_region_tpl = (
        "<!-- PROJECT-CUSTOM:BEGIN — sync-template preserves everything between these markers -->\n"
        "<!-- New placeholder wording. -->\n"
        "<!-- PROJECT-CUSTOM:END -->"
    )
    new_tpl = TPL_V1 + new_region_tpl + "\n"
    proj_body = TPL_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(
        tmp_path, new_tpl, proj_body,
        entry_overrides=_region_spliced_entry(old_tpl, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["template_changed"] is True
    assert f["status"] == "AUTO_UPDATE"
    assert f["region_only"] is True

    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    assert res["region_preserved"] is True
    assert REGION_PROJ in (proj / "CLAUDE.md").read_text(encoding="utf-8")


# --- (i) genuine deviation outside the region -> CONFLICT -------------------

def test_genuine_deviation_outside_region_is_conflict(tmp_path):
    old_tpl = TPL_V1 + REGION_TPL + "\n"
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V1 + "Project edit outside the region.\n" + REGION_PROJ + "\n"
    _, proj = _mk_project(
        tmp_path, new_tpl, proj_body,
        entry_overrides=_region_spliced_entry(old_tpl, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "CONFLICT"
    assert f["deviates_from_template"] is True
    assert f["region_only"] is False


# --- (j) legacy entry without templatePartHash -> conservative CONFLICT -----

def test_legacy_region_entry_without_template_part_hash_conflicts_with_hint(tmp_path):
    old_tpl = TPL_V1 + REGION_TPL + "\n"
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V1 + "Project edit outside the region.\n" + REGION_PROJ + "\n"
    _, proj = _mk_project(
        tmp_path, new_tpl, proj_body,
        entry_overrides=_legacy_keep_mine_entry(old_tpl, proj_body),
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "CONFLICT"
    assert "localPartHash" in f["hint"]


# --- apply records the region-aware fields ---------------------------------

def test_apply_template_records_part_hashes(tmp_path):
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(tmp_path, new_tpl, proj_body)
    entry = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))["manifest_entry"]
    written = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    local_part, tpl_part = _part_hashes(written, new_tpl)
    assert entry["localPartHash"] == local_part
    assert entry["templatePartHashAtSync"] == tpl_part
    assert local_part == tpl_part  # region-preserving apply: parts match
    assert "regionOnlyDeviation" not in entry


def test_apply_skip_records_deviating_part_hashes(tmp_path):
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    proj_body = TPL_V1 + REGION_PROJ + "\n"
    _, proj = _mk_project(tmp_path, new_tpl, proj_body)
    entry = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="skip")
    ))["manifest_entry"]
    local_part, tpl_part = _part_hashes(proj_body, new_tpl)
    assert entry["localPartHash"] == local_part
    assert entry["templatePartHashAtSync"] == tpl_part
    assert local_part != tpl_part  # body is still V1, template is V2


def test_region_apply_round_trip_survives_next_template_move(tmp_path):
    """End-to-end: apply + finalize, template moves, status must NOT conflict."""
    repo, proj = _mk_project(tmp_path, TPL_V1 + REGION_TPL + "\n", TPL_V1 + REGION_PROJ + "\n")
    applied = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    asyncio.run(ts.template_finalize_sync(str(proj), json.dumps([applied])))

    (repo / "templates" / "general" / "CLAUDE.md").write_text(
        TPL_V2 + REGION_TPL + "\n", encoding="utf-8", newline=""
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "AUTO_UPDATE"
    assert f["region_only"] is True
    assert _status(proj)["summary"]["deviating"] == 0


def test_project_only_markers_are_not_auto_updated(tmp_path):
    """Single-sided markers must fall back to full-file behavior.

    apply(source="template") only splices when BOTH sides carry markers, so a
    part-hash comparison that ignores that would call the file safe and let
    the apply wipe the project's region.
    """
    proj_body = TPL_V1 + REGION_PROJ  # template has no markers at all
    repo, proj = _mk_project(tmp_path, TPL_V1, proj_body)
    applied = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="skip")
    ))
    asyncio.run(ts.template_finalize_sync(str(proj), json.dumps([applied])))

    (repo / "templates" / "general" / "CLAUDE.md").write_text(
        TPL_V2, encoding="utf-8", newline=""
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "CONFLICT"
    assert f["region_only"] is False


def test_apply_records_full_content_part_when_template_has_no_region(tmp_path):
    proj_body = TPL_V1 + REGION_PROJ
    _, proj = _mk_project(tmp_path, TPL_V2, proj_body)
    entry = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="skip")
    ))["manifest_entry"]
    # Not the region-stripped part -- the template carries no markers, so the
    # region is NOT project-owned as far as apply is concerned.
    assert entry["localPartHash"] == ts._sha256(proj_body)
    assert entry["templatePartHashAtSync"] == ts._sha256(TPL_V2)


# --- (5) mirror: template HAS markers, project does NOT ---------------------

def test_template_only_markers_auto_update_writes_verbatim(tmp_path):
    """The next sync every consumer runs: the template gains the region."""
    new_tpl = TPL_V2 + REGION_TPL + "\n"
    repo, proj = _mk_project(tmp_path, TPL_V1, TPL_V1)  # project has no markers
    applied = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    asyncio.run(ts.template_finalize_sync(str(proj), json.dumps([applied])))

    (repo / "templates" / "general" / "CLAUDE.md").write_text(
        new_tpl, encoding="utf-8", newline=""
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "AUTO_UPDATE"
    assert f["region_only"] is False

    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    assert res["region_preserved"] is False
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == new_tpl


# --- (1) finalize records real hashes for new files -------------------------

def test_finalize_new_files_entry_is_not_blindly_auto_updated(tmp_path):
    repo, proj = _mk_project(tmp_path, TPL_V1, TPL_V1)
    # A second template file the project already has, with its own content.
    (repo / "templates" / "general" / "AGENT_TEAM.md").write_text(
        TPL_V1, encoding="utf-8", newline=""
    )
    (proj / "AGENT_TEAM.md").write_text(
        TPL_V1 + "Project-owned paragraph.\n", encoding="utf-8", newline=""
    )
    asyncio.run(ts.template_finalize_sync(str(proj), "[]", new_files='["AGENT_TEAM.md"]'))

    (repo / "templates" / "general" / "AGENT_TEAM.md").write_text(
        TPL_V2, encoding="utf-8", newline=""
    )
    f = _status(proj)["files"]["AGENT_TEAM.md"]
    assert f["status"] != "AUTO_UPDATE"
    assert f["deviates_from_template"] is True


def test_legacy_entry_without_template_hash_is_not_auto_updated(tmp_path):
    proj_body = TPL_V1 + "Project-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V2, proj_body,
        entry_overrides={
            "templateHash": "",
            "templateRawHash": "",
            "localHash": "",
            "locallyModified": False,
        },
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] != "AUTO_UPDATE"
    assert f["deviates_from_template"] is True


def test_entry_without_template_hash_matching_template_is_auto_update(tmp_path):
    """The same unknown-baseline rule must not block a genuinely clean file."""
    _, proj = _mk_project(
        tmp_path, TPL_V2, TPL_V2,
        entry_overrides={
            "templateHash": "",
            "templateRawHash": "",
            "localHash": "",
            "locallyModified": False,
        },
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["deviates_from_template"] is False
    assert f["status"] == "AUTO_UPDATE"


# --- (6) missing project file, CRLF ----------------------------------------

def test_missing_project_file_is_flagged(tmp_path):
    _, proj = _mk_project(tmp_path, TPL_V2, TPL_V1)
    (proj / "CLAUDE.md").unlink()
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["project_file_missing"] is True
    # Classification is unchanged by the flag: the manifest still points at the
    # current template, so a missing file reads as a deviation, not AUTO_UPDATE.
    assert f["deviates_from_template"] is True
    assert f["status"] == "PROJECT_CUSTOM"


def test_present_project_file_is_not_flagged_missing(tmp_path):
    _, proj = _mk_project(tmp_path, TPL_V1, TPL_V1)
    assert _status(proj)["files"]["CLAUDE.md"]["project_file_missing"] is False


def test_crlf_project_file_matches_lf_template(tmp_path):
    _, proj = _mk_project(tmp_path, TPL_V1, TPL_V1)
    (proj / "CLAUDE.md").write_bytes(TPL_V1.replace("\n", "\r\n").encode("utf-8"))
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "UP_TO_DATE"
    assert f["deviates_from_template"] is False


# --- (e) old manifest without `resolution` classifies by hash inequality ----

def test_legacy_entry_without_resolution_still_conflicts(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V2, proj_body,
        entry_overrides={
            "templateHash": ts._sha256(TPL_V1),
            "templateRawHash": ts._sha256(TPL_V1),
            "localHash": ts._sha256(proj_body),
            "locallyModified": False,  # flag never set -- only the hashes tell
        },
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["status"] == "CONFLICT"
    assert f["deviates_from_template"] is True
    assert f["resolution_at_sync"] == ""


# --- (f) changed_since_sync keeps the old "changed since last sync" meaning --

def test_changed_since_sync_tracks_edits_after_the_sync(tmp_path):
    proj_body = TPL_V1 + "\nEdited after the sync.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V1, proj_body,
        entry_overrides={"localHash": ts._sha256(TPL_V1)},  # sync recorded clean content
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["changed_since_sync"] is True
    assert f["deviates_from_template"] is True
    assert f["status"] == "PROJECT_CUSTOM"


def test_unchanged_since_sync_but_deviating_is_not_auto_update(tmp_path):
    """The reported bug in one assertion: unchanged-since-sync != matches-template."""
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V2, proj_body,
        entry_overrides={
            "templateHash": ts._sha256(TPL_V1),
            "templateRawHash": ts._sha256(TPL_V1),
            "localHash": ts._sha256(proj_body),
        },
    )
    f = _status(proj)["files"]["CLAUDE.md"]
    assert f["changed_since_sync"] is False
    assert f["status"] != "AUTO_UPDATE"


# --- summary counts ---------------------------------------------------------

def test_summary_counts_deviating_files(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(
        tmp_path, TPL_V2, proj_body,
        entry_overrides=_keep_mine_entry(TPL_V1, proj_body),
    )
    summary = _status(proj)["summary"]
    assert summary["conflict"] == 1
    assert summary["auto_update"] == 0
    assert summary["deviating"] == 1


# --- template_apply_file records / clears the resolution --------------------

def test_apply_skip_records_keep_mine(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(tmp_path, TPL_V2, proj_body)
    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="skip")
    ))
    assert res["manifest_entry"]["resolution"] == "keep-mine"
    assert res["manifest_entry"]["locallyModified"] is True


def test_apply_template_clears_keep_mine(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(tmp_path, TPL_V2, proj_body)
    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="template")
    ))
    assert "resolution" not in res["manifest_entry"]


def test_apply_provided_clears_keep_mine(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(tmp_path, TPL_V2, proj_body)
    res = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="provided", content="new\n")
    ))
    assert "resolution" not in res["manifest_entry"]


def test_finalize_persists_keep_mine_resolution(tmp_path):
    proj_body = TPL_V1 + "\nProject-owned paragraph.\n"
    _, proj = _mk_project(tmp_path, TPL_V2, proj_body)
    applied = json.loads(asyncio.run(
        ts.template_apply_file(str(proj), "CLAUDE.md", source="skip")
    ))
    asyncio.run(ts.template_finalize_sync(str(proj), json.dumps([applied])))
    manifest = json.loads(
        (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8")
    )
    assert manifest["files"]["CLAUDE.md"]["resolution"] == "keep-mine"
    # And the very next status call must not offer to overwrite it.
    assert _status(proj)["files"]["CLAUDE.md"]["status"] == "PROJECT_CUSTOM"
