"""PROJECT-CUSTOM region under manifest v3 (toolkit v3.1 reversal).

The toolkit ships CLAUDE.md as `template` class AND keeps the PROJECT-CUSTOM
region in it, with marker text that promises "sync-template preserves
everything between these markers". v3 must therefore be region-aware the way
v2 already is: a region-only difference is not drift, and applying the
template splices the consumer's region back in instead of wiping it.
"""

import asyncio
import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3

BEGIN = "<!-- PROJECT-CUSTOM:BEGIN - sync-template preserves everything between these markers -->"
END = "<!-- PROJECT-CUSTOM:END -->"

OWNERSHIP = {"tracked_paths": ["templates"], "rules": [
    {"pattern": "CLAUDE.md", "ownership": "template"},
    {"pattern": "AGENT_TEAM.md", "ownership": "template"},
]}


def tpl(body: str, region: str = "") -> str:
    inner = f"\n{region}\n" if region else "\n"
    return f"# Toolkit\n\n{body}\n\n{BEGIN}{inner}{END}\n"


MINE = "MY HARD RULE: never force-push main.\nMY ROUTING BLOCK: use ctx tools."


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _head(repo) -> str:
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _run(coro):
    return json.loads(asyncio.run(coro))


def mk(tmp_path, template_now: str, project: str, template_at_sync: str | None = None,
       with_git: bool = True, entry_hash_of: str | None = None):
    """Toolkit repo whose HEAD ships `template_now`; when `template_at_sync`
    differs, that older content is what the manifest's template_commit points at."""
    repo, proj = tmp_path / "tk", tmp_path / "proj"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    at_sync = template_at_sync if template_at_sync is not None else template_now
    (repo / "templates" / "general" / "CLAUDE.md").write_text(at_sync, encoding="utf-8", newline="")
    commit = "unknown"
    if with_git:
        _git(repo, "init", "-q")
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", "at sync")
        commit = _head(repo)
    if template_at_sync is not None:
        (repo / "templates" / "general" / "CLAUDE.md").write_text(template_now, encoding="utf-8", newline="")
        if with_git:
            _git(repo, "add", "-A")
            _git(repo, "commit", "-q", "-m", "template moved on")

    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(project, encoding="utf-8", newline="")
    baseline = entry_hash_of if entry_hash_of is not None else at_sync
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "manifest_version": 3, "template_version": "v3.1.0", "template_commit": commit,
        "requires_server": ">=0.3.0", "variant": "general", "templateRepo": str(repo),
        "placeholders": {},
        "files": {"CLAUDE.md": {"hash": "sha256:" + ts._sha256(baseline), "ownership": "template"}},
    }), encoding="utf-8", newline="")
    return repo, proj


def status_of(proj, rel="CLAUDE.md"):
    return _run(ts.template_compute_status(str(proj)))["files"][rel]


# --- classification -----------------------------------------------------------


def test_region_only_difference_is_not_drift(tmp_path):
    base = tpl("rule one\nrule two")
    _, proj = mk(tmp_path, template_now=base, project=tpl("rule one\nrule two", MINE))
    info = status_of(proj)
    assert info["status"] == "IDENTICAL"
    assert "local_diff" not in info


def test_region_only_difference_with_moved_template_is_template_updated(tmp_path):
    _, proj = mk(
        tmp_path,
        template_at_sync=tpl("rule one\nrule two"),
        template_now=tpl("rule one\nrule two CHANGED\nrule three"),
        project=tpl("rule one\nrule two", MINE),
    )
    info = status_of(proj)
    assert info["status"] == "TEMPLATE_UPDATED"
    assert "local_diff" not in info


def test_edit_outside_the_region_is_still_local_edited(tmp_path):
    base = tpl("rule one\nrule two")
    _, proj = mk(tmp_path, template_now=base,
                 project=tpl("rule one\nrule two\nMY EXTRA LINE", MINE))
    info = status_of(proj)
    assert info["status"] == "LOCAL_EDITED"
    assert "MY EXTRA LINE" in info["local_diff"]
    assert info["local_diff_kind"] == "insertion"


def test_single_sided_markers_keep_whole_file_semantics(tmp_path):
    # Template has no region; the project invented one. Not project-owned.
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project=f"# Toolkit\n\nrule one\n{BEGIN}\n{MINE}\n{END}\n")
    assert status_of(proj)["status"] == "LOCAL_EDITED"


# --- apply --------------------------------------------------------------------


def test_apply_preserves_the_region_and_updates_the_body(tmp_path):
    _, proj = mk(
        tmp_path,
        template_at_sync=tpl("rule one\nrule two"),
        template_now=tpl("rule one\nrule two CHANGED\nrule three"),
        project=tpl("rule one\nrule two", MINE),
    )
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir=str(tmp_path / "bak")))
    after = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert res["region_preserved"] is True
    assert "MY HARD RULE: never force-push main." in after
    assert "rule two CHANGED" in after and "rule three" in after


def test_apply_then_status_is_clean(tmp_path):
    """The property that ends the every-sync fight: after applying, the next
    status is clean rather than reporting the same region again."""
    _, proj = mk(
        tmp_path,
        template_at_sync=tpl("rule one"),
        template_now=tpl("rule one\nrule two"),
        project=tpl("rule one", MINE),
    )
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir=str(tmp_path / "bak")))
    entry = res["manifest_entry"]
    mf = proj / ".claude" / "template-manifest.json"
    m = json.loads(mf.read_text(encoding="utf-8"))
    m["files"]["CLAUDE.md"] = entry
    mf.write_text(json.dumps(m), encoding="utf-8", newline="")
    info = status_of(proj)
    assert info["status"] == "IDENTICAL"
    assert "MY HARD RULE: never force-push main." in (proj / "CLAUDE.md").read_text(encoding="utf-8")


def test_region_only_difference_does_not_demand_backup_dir(tmp_path):
    """status and apply must agree: if a region-only difference is not drift,
    applying it must not be refused for want of a backup of that non-drift."""
    base = tpl("rule one\nrule two")
    _, proj = mk(tmp_path, template_now=base, project=tpl("rule one\nrule two", MINE))
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md"))
    assert "error" not in res, res
    assert res["local_edit_overwritten"] is False
    assert "MY HARD RULE: never force-push main." in (proj / "CLAUDE.md").read_text(encoding="utf-8")


def test_apply_without_markers_on_either_side_is_unchanged(tmp_path):
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n", project="# Toolkit\n\nrule one\n")
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md"))
    assert res["region_preserved"] is False
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == "# Toolkit\n\nrule one\n"


# --- orphaned region: template has no markers ---------------------------------
#
# The consumer keeps a region but the template it syncs against has no markers,
# so an apply has nowhere to splice it and the region leaves the working file.
# The toolkit's own template is guarded by a consistency check, but that check
# says nothing about a forked, locally edited, older or never-shipped template,
# where the server is the only thing in the loop. Reported BEFORE the apply, and
# keyed on PRESENCE: the field appears only in the hazardous case, so a caller
# writes `if "region_orphaned" in info` instead of reasoning about what False
# means on a build that predates the field.


def test_region_orphaned_is_reported_when_the_template_has_no_markers(tmp_path):
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project=f"# Toolkit\n\nrule one\n{BEGIN}\n{MINE}\n{END}\n")
    info = status_of(proj)
    assert info["region_orphaned"] is True
    assert info["status"] == "LOCAL_EDITED"


def test_region_orphaned_absent_when_both_sides_carry_markers(tmp_path):
    base = tpl("rule one")
    _, proj = mk(tmp_path, template_now=base, project=tpl("rule one", MINE))
    assert "region_orphaned" not in status_of(proj)


def test_region_orphaned_absent_when_neither_side_has_a_region(tmp_path):
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project="# Toolkit\n\nrule one\n")
    assert "region_orphaned" not in status_of(proj)


def test_region_orphaned_absent_when_only_the_template_has_markers(tmp_path):
    # Nothing of the consumer's is at risk here.
    _, proj = mk(tmp_path, template_now=tpl("rule one"), project="# Toolkit\n\nrule one\n")
    assert "region_orphaned" not in status_of(proj)


def test_malformed_begin_without_end_is_not_a_region(tmp_path):
    # penumbra's second residual: BEGIN with no END is not a detected region,
    # so it must not be reported as an orphaned one either -- it is reported
    # as malformed instead, so the promise "you are told before a region is
    # dropped" has no hole in it.
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project=f"# Toolkit\n\nrule one\n{BEGIN}\n{MINE}\n")
    info = status_of(proj)
    assert "region_orphaned" not in info
    assert info["region_markers_malformed"] == "project"


# --- malformed markers: case H, and the template side ------------------------


def test_markers_malformed_detects_each_broken_shape():
    assert v3.markers_malformed(f"a\n{BEGIN}\nb\n") is True          # BEGIN, no END
    assert v3.markers_malformed(f"a\n{END}\nb\n") is True            # END, no BEGIN
    assert v3.markers_malformed(f"a\n{END}\nb\n{BEGIN}\n") is True   # out of order
    assert v3.markers_malformed(f"a\n{BEGIN}\nb\n{END}\n") is False  # well formed
    assert v3.markers_malformed("a\nb\n") is False                   # no markers
    assert v3.markers_malformed(None) is False


def test_region_markers_malformed_names_the_template_side(tmp_path):
    """A broken pair in the template is the toolkit's bug, but the consumer is
    the one who loses the region and the only party positioned to notice."""
    _, proj = mk(tmp_path, template_now=f"# Toolkit\n\nrule one\n{BEGIN}\n",
                 project=tpl("rule one", MINE))
    assert status_of(proj)["region_markers_malformed"] == "template"


def test_region_markers_malformed_names_both_sides(tmp_path):
    _, proj = mk(tmp_path, template_now=f"# Toolkit\n\nrule one\n{BEGIN}\n",
                 project=f"# Toolkit\n\nrule one\n{END}\n")
    assert status_of(proj)["region_markers_malformed"] == "both"


def test_region_markers_malformed_absent_when_both_sides_are_well_formed(tmp_path):
    base = tpl("rule one")
    _, proj = mk(tmp_path, template_now=base, project=tpl("rule one", MINE))
    assert "region_markers_malformed" not in status_of(proj)


def test_region_markers_malformed_absent_when_there_are_no_markers(tmp_path):
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project="# Toolkit\n\nrule one\n")
    assert "region_markers_malformed" not in status_of(proj)


def test_apply_also_reports_region_markers_malformed(tmp_path):
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project=f"# Toolkit\n\nrule one\n{BEGIN}\n{MINE}\n")
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir=str(tmp_path / "bak")))
    assert res["region_markers_malformed"] == "project"
    safe = mk(tmp_path / "safe", template_now=tpl("rule one"), project=tpl("rule one", MINE))[1]
    assert "region_markers_malformed" not in _run(
        ts.template_apply_file(str(safe), "CLAUDE.md", backup_dir=str(tmp_path / "bak2")))


def test_apply_also_reports_region_orphaned(tmp_path):
    """A caller that goes straight to apply still gets told, on the same key."""
    _, proj = mk(tmp_path, template_now="# Toolkit\n\nrule one\n",
                 project=f"# Toolkit\n\nrule one\n{BEGIN}\n{MINE}\n{END}\n")
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir=str(tmp_path / "bak")))
    assert res["region_orphaned"] is True
    safe = mk(tmp_path / "safe", template_now=tpl("rule one"), project=tpl("rule one", MINE))[1]
    assert "region_orphaned" not in _run(
        ts.template_apply_file(str(safe), "CLAUDE.md", backup_dir=str(tmp_path / "bak2")))


# --- cross-path invariant (penumbra) -----------------------------------------


@pytest.mark.parametrize("manifest_version", [2, 3])
def test_region_round_trips_on_every_manifest_version(tmp_path, manifest_version):
    """The defect's shape was a promise inherited by a path that never
    implemented it, so the assertion is written across paths rather than per
    version: for EVERY manifest version the server accepts, a template whose
    text carries the markers must round-trip the consumer's region.

    Discriminating on purpose: the region's bytes must survive in the WORKING
    FILE, not merely in backup_dir. A fix that writes a correct backup while
    clobbering the working file fails the user exactly as today's defect does.
    """
    at_sync = tpl("rule one")
    now = tpl("rule one\nrule two CHANGED")
    project = tpl("rule one", MINE)
    repo, proj = tmp_path / "tk", tmp_path / "proj"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    (repo / "templates" / "general" / "CLAUDE.md").write_text(now, encoding="utf-8", newline="")
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(project, encoding="utf-8", newline="")

    if manifest_version == 3:
        manifest = {"manifest_version": 3, "template_version": "v3.1.0",
                    "template_commit": "unknown", "requires_server": ">=0.3.0",
                    "variant": "general", "templateRepo": str(repo), "placeholders": {},
                    "files": {"CLAUDE.md": {"hash": "sha256:" + ts._sha256(at_sync),
                                            "ownership": "template"}}}
    else:
        local_part, tpl_part = ts._part_hashes(project, at_sync)
        manifest = {"version": 2, "variant": "general", "templateRepo": str(repo),
                    "placeholders": {}, "lastSynced": "",
                    "files": {"CLAUDE.md": {"templateHash": ts._sha256(at_sync),
                                            "templateRawHash": ts._sha256(at_sync),
                                            "localHash": ts._sha256(project),
                                            "locallyModified": True,
                                            "localPartHash": local_part,
                                            "templatePartHashAtSync": tpl_part}}}
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")

    backup = tmp_path / "bak"
    res = _run(ts.template_apply_file(str(proj), "CLAUDE.md", backup_dir=str(backup)))
    assert "error" not in res, res
    working = (proj / "CLAUDE.md").read_text(encoding="utf-8")

    assert res["region_preserved"] is True
    assert "MY HARD RULE: never force-push main." in working, "region lost from the WORKING file"
    assert "MY ROUTING BLOCK: use ctx tools." in working
    assert "rule two CHANGED" in working, "template body must still update"
    assert BEGIN in working and END in working


# --- migration ----------------------------------------------------------------


def test_migration_leaves_the_region_in_claude_md_and_reports_it(tmp_path):
    """Under the reversal the region is no longer homeless, so copying it into
    project.md would duplicate it into a file that reaches no agent."""
    repo, proj = tmp_path / "tk", tmp_path / "proj"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(
        {"tracked_paths": ["templates"], "rules": [
            {"pattern": "CLAUDE.md", "ownership": "template"},
            {"pattern": ".claude/rules/project.md", "ownership": "once"}]}), encoding="utf-8")
    at_sync = tpl("rule one")
    (repo / "templates" / "general" / "CLAUDE.md").write_text(at_sync, encoding="utf-8", newline="")
    _git(repo, "init", "-q"); _git(repo, "add", "-A"); _git(repo, "commit", "-q", "-m", "v2")
    commit = _head(repo)

    (proj / ".claude").mkdir(parents=True)
    project_claude = tpl("rule one\nMY OUT OF REGION EDIT", MINE)
    (proj / "CLAUDE.md").write_text(project_claude, encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "lastSynced": commit,
        "files": {"CLAUDE.md": {"templateHash": ts._sha256(at_sync)}},
    }), encoding="utf-8", newline="")

    res = _run(ts.template_migrate_manifest(str(proj), dry_run=True))
    pmd = res["project_md"]
    assert "MY HARD RULE: never force-push main." not in pmd, "region must not be duplicated"
    assert res["region_left_in_place"] is True
    assert res["region_bytes"] > 0
    # Out-of-region edits are still what an apply would discard, so they stay reported.
    assert "MY OUT OF REGION EDIT" in pmd
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == project_claude
