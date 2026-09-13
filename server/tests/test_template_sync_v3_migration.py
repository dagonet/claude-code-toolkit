"""v2 -> v3 migration (spec §7 steps 1-5, §8; review §2.4, §2.5, §5c, §6.4, §6.5, §7d, §9a, §9b, §9d, §10a)."""

import asyncio
import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3

OWNERSHIP = {
    "tracked_paths": ["hooks", "templates"],
    "rules": [
        {"pattern": ".claude/agents/local-*.md", "ownership": "project"},
        {"pattern": "hooks/**", "ownership": "template"},
        {"pattern": ".claude/agents/*.md", "ownership": "template"},
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/settings.json", "ownership": "template"},
        {"pattern": ".claude/rules/project.md", "ownership": "once"},
        {"pattern": "gitignore", "ownership": "once", "target": ".gitignore"},
        {
            "pattern": "PROJECT_CONTEXT.md", "ownership": "once", "audit": "keys",
            "required_keys": ["Protected branches", "Gate"],
            "deprecated_keys": {"Gate Command": "Gate", "Test Command": "Test"},
            "aliases": {"Build": ["Build (desktop)"]},
            "placeholder_map": {"Build": "BUILD_COMMAND", "Test": "TEST_COMMAND"},
        },
    ],
}


def _mk_v3(tmp_path, template: dict[str, str], project: dict[str, str],
           entries: dict[str, dict], placeholders: dict | None = None,
           ownership: dict | None = None, requires_server: str = ">=0.3.0"):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(
        json.dumps(ownership if ownership is not None else OWNERSHIP), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    m = {"templateRepo": str(repo), "variant": "general"}
    for rel, content in template.items():
        p = ts._template_file_path(m, rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    for rel, content in project.items():
        p = proj / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3,
        "template_version": "3.1.0",
        "template_commit": "0000000",
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": placeholders or {},
        "requires_server": requires_server,
        "files": entries,
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")
    return repo, proj


def _run(coro):
    return json.loads(asyncio.run(coro))


SEED = "<!-- Project-specific rules go here -->"
# The held template CONTAINS a placeholder (review §10a): the vacuity control
# only proves the base is rendered when there is something to render.
TPL_V2 = (
    "# Project\n\nRules line for {{NAME}}.\n\n"
    f"<!-- PROJECT-CUSTOM:BEGIN -->\n{SEED}\n<!-- PROJECT-CUSTOM:END -->\n"
)
TPL_V2_RENDERED = TPL_V2.replace("{{NAME}}", "Demo")
TPL_V3 = "# Project\n\nProject-specific instructions: .claude/rules/project.md\n\nRules line v3.\n"


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _head(repo):
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _mk_v2(tmp_path, project_claude: str, extra_project: dict | None = None,
           extra_entries: dict | None = None, with_git: bool = True, ownership=True):
    """Toolkit repo whose history holds the v2 CLAUDE.md (tagged v2.3.0) and
    now ships the v3 one, plus a project holding a v2 manifest."""
    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text(TPL_V2, encoding="utf-8", newline="")
    (vdir / "CLAUDE.local.md").write_text("local {{NAME}}\n", encoding="utf-8", newline="")
    (vdir / ".claude").mkdir()
    (vdir / ".claude" / "settings.json").write_text("{}", encoding="utf-8")
    commit = ""
    if with_git:
        _git(repo, "init", "-q")
        _git(repo, "add", "-A")
        _git(repo, "commit", "-q", "-m", "v2")
        commit = _head(repo)
        _git(repo, "tag", "v2.3.0")
    (vdir / "CLAUDE.md").write_text(TPL_V3, encoding="utf-8", newline="")
    (vdir / "CLAUDE.local.md").unlink()
    (vdir / ".claude" / "rules").mkdir()
    (vdir / ".claude" / "rules" / "project.md").write_text("# Project instructions\n", encoding="utf-8")
    if ownership:
        (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")

    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(project_claude, encoding="utf-8", newline="")
    (proj / "CLAUDE.local.md").write_text("local Demo\n", encoding="utf-8", newline="")
    (proj / ".claude" / "settings.json").write_text("{}", encoding="utf-8")
    for rel, content in (extra_project or {}).items():
        p = proj / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    files = {
        "CLAUDE.md": {"templateHash": ts._sha256(TPL_V2_RENDERED), "templateRawHash": ts._sha256(TPL_V2),
                      "localHash": ts._sha256(project_claude), "locallyModified": True},
        "CLAUDE.local.md": {"templateHash": ts._sha256("local Demo\n"), "localHash": ts._sha256("local Demo\n"),
                            "locallyModified": False},
        ".claude/settings.json": {"templateHash": ts._sha256("{}"), "localHash": ts._sha256("{}"),
                                  "locallyModified": False},
    }
    files.update(extra_entries or {})
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general",
        "lastSynced": commit, "placeholders": {"NAME": "Demo"}, "files": files,
        "deletedAcknowledged": ["old.md"],
    }), encoding="utf-8", newline="")
    return repo, proj, commit


PROJ_CLAUDE = (
    "# Project\n\nRules line for Demo.\nMy extra rule.\n\n"
    "<!-- PROJECT-CUSTOM:BEGIN -->\nKeep this region.\n<!-- PROJECT-CUSTOM:END -->\n"
)


def _migrate(proj, **kw):
    return _run(ts.template_migrate_manifest(str(proj), **kw))


def test_migration_region_and_hunks(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    backup = tmp_path / "backup"
    res = _migrate(proj, backup_dir=str(backup))
    assert res["migrated"] is True and res["dry_run"] is False
    assert res["migration_base"] == commit
    assert res["hunk_count"] == 1
    assert res["project_md_bytes"] > 0
    md = (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8")
    assert md.startswith("# Project instructions\n<!-- template-sync: project-owned; migrated from CLAUDE.md at ")
    assert f"migration-base: {commit}; rendered: yes -->" in md
    assert "{{NAME}}" not in md and "-Rules line for {{NAME}}" not in md   # base was rendered before diffing
    # v3.1 reversal: the region stays in CLAUDE.md and is reported, not copied.
    assert "Keep this region." not in md
    assert res["region_left_in_place"] is True and res["region_bytes"] > 0
    assert res["region_was_seed"] is False
    assert res["gate_self_reference"] == [] and res["gate_unverified"] is False
    assert "```diff\n" in md and "+My extra rule." in md
    assert "Project-specific instructions" not in md      # never diffed against the current template
    # backup
    assert (backup / "CLAUDE.md.pre-migration").read_text(encoding="utf-8") == PROJ_CLAUDE
    assert (backup / "template-manifest.json.pre-migration").exists()
    assert res["backup"]["claude_md"].endswith("CLAUDE.md.pre-migration")
    # manifest
    m = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert m["manifest_version"] == 3
    assert m["template_commit"] == commit
    assert m["template_version"] == "v2.3.0"
    assert m["requires_server"] == ">=0.3.2"   # the splice floor, not the v3 floor
    assert m["deletedAcknowledged"] == ["old.md"]
    assert res["unknown_keys"] == ["deletedAcknowledged"]
    assert "version" not in m and "lastSynced" not in m
    assert m["files"]["CLAUDE.md"] == {"hash": "sha256:" + ts._sha256(TPL_V2_RENDERED), "ownership": "template"}
    assert m["files"][".claude/settings.json"]["ownership"] == "template"
    assert "CLAUDE.local.md" not in m["files"]
    assert res["dropped_entries"] == ["CLAUDE.local.md"]
    assert res["redundant_project_file"] == ["CLAUDE.local.md"]
    assert (proj / "CLAUDE.local.md").exists()                # never deleted
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == PROJ_CLAUDE   # apply step does that, not migrate


def test_migration_reports_the_keep_mine_entries_it_drops(tmp_path):
    """v3 has no keep-mine class, so `resolution` is dropped by design -- but
    dropping it silently is the defect. The manifest afterwards records the
    TEMPLATE's hash for a file that still holds the consumer's deviation, so
    the next status reports drift and the next apply overwrites it, while the
    consumer reads a successful migration and learns nothing.

    Measured by penumbra on a real tree: migration is careful with keys it
    does NOT understand (`reason` survives under unknown_file_keys,
    `lastSyncedVersion` under unknown_keys) and discarded the one it does.
    """
    entries = {
        "hooks/enforce-delegation.sh": {
            "templateHash": ts._sha256("tpl\n"), "localHash": ts._sha256("mine\n"),
            "locallyModified": True, "resolution": "keep-mine",
        },
        "hooks/plain.sh": {"templateHash": ts._sha256("p\n"), "localHash": ts._sha256("p\n"),
                           "locallyModified": False},
    }
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_entries=entries,
                                extra_project={"hooks/enforce-delegation.sh": "mine\n",
                                               "hooks/plain.sh": "p\n"})
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))

    assert res["dropped_resolutions"] == [
        {"path": "hooks/enforce-delegation.sh", "resolution": "keep-mine",
         "ownership": "template"}
    ]
    # The behaviour itself is the agreed one and is unchanged: the entry
    # becomes template class, so the deviation is no longer protected.
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["files"]["hooks/enforce-delegation.sh"]["ownership"] == "template"
    assert "resolution" not in out["files"]["hooks/enforce-delegation.sh"]
    # The file on disk is untouched by migration -- only the record changed.
    assert (proj / "hooks" / "enforce-delegation.sh").read_text(encoding="utf-8") == "mine\n"


def test_migration_reports_no_dropped_resolutions_when_there_are_none(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj, dry_run=True)
    assert res["dropped_resolutions"] == []


def test_migration_stamps_the_splice_floor_not_the_v3_floor(tmp_path):
    """0.3.0 and 0.3.1 accept a v3 manifest but lack the region splice, so a
    manifest written by this server must refuse to load on them. This is the
    one place requires_server can protect that hazard: not the first
    migration, which no server-side code can reach, but every sync afterwards
    — a downgrade, or the same repo opened where an older process is running.
    """
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["manifest"]["requires_server"] == ">=0.3.2"
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == ">=0.3.2"
    # And that floor is enforced: a 0.3.1-era server would be refused by name.
    ok, reason = v3.requires_server_satisfied(out["requires_server"], "0.3.1")
    assert ok is False and "0.3.1" in reason


def test_migration_vacuity_control(tmp_path):
    # Consumer holds the RENDERED template: region is the untouched seed, no edits.
    repo, proj, commit = _mk_v2(tmp_path, TPL_V2_RENDERED)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["hunk_count"] == 0
    assert res["region_was_seed"] is True
    md = (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8")
    assert "```diff" not in md
    assert SEED not in md                       # the toolkit's seed is not the consumer's content
    assert md.count("\n") <= 3                  # header only


def test_migration_region_only_no_migrated_heading(tmp_path):
    # penumbra's shape (spec §8): consumer region, zero out-of-region edits.
    region_only = TPL_V2_RENDERED.replace(SEED, "Line one.\nLine two.")
    repo, proj, commit = _mk_v2(tmp_path, region_only)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["hunk_count"] == 0 and res["region_was_seed"] is False
    assert res["region_left_in_place"] is True and res["region_bytes"] > 0
    md = (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8")
    # The region stays in CLAUDE.md; a region-only consumer gets a header-only seed.
    assert "Line one.\nLine two." not in md
    assert "Line one.\nLine two." in (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert "Migrated from CLAUDE.md" not in md and "```diff" not in md


def test_migration_idempotent_and_keeps_existing_project_md(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_project={".claude/rules/project.md": "mine\n"})
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["project_md_existing"] is True
    assert (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8") == "mine\n"
    res2 = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res2["migrated"] is False
    assert "already" in res2["reason"]


def test_migration_dry_run_writes_nothing(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj, dry_run=True)
    assert res["dry_run"] is True and res["migrated"] is False
    assert res["hunk_count"] == 1 and "+My extra rule." in res["project_md"]
    assert res["manifest"]["manifest_version"] == 3
    assert not (proj / ".claude" / "rules" / "project.md").exists()
    assert json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))["version"] == 2


def test_migration_refuses_write_without_backup_dir(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj)
    assert "backup_dir" in res["error"]
    assert not (proj / ".claude" / "rules" / "project.md").exists()


def test_migration_base_unavailable_emits_no_hunks(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, with_git=False)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["migration_base"] == "unavailable"
    assert "migration_base_unavailable" in res["warnings"]
    assert res["hunk_count"] == 0
    md = (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8")
    assert "migration-base: unavailable; rendered: no -->" in md
    assert "Keep this region." not in md
    assert "Keep this region." in (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert res["region_left_in_place"] is True
    assert res["region_was_seed"] is None
    assert res["redundant_project_file"] == []


def test_migration_falls_back_to_tag_commit(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    m = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    m["lastSynced"] = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    m["template_version"] = "v2.3.0"
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["migration_base"] == "v2.3.0"
    assert res["hunk_count"] == 1


def test_migration_requires_ownership_file_and_skips_v3(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, ownership=False)
    res = _migrate(proj, dry_run=True)
    assert "ownership.json" in res["error"]

    repo2, proj2 = _mk_v3(tmp_path / "v3", template={"CLAUDE.md": "x"}, project={}, entries={})
    res2 = _migrate(proj2, dry_run=True)
    assert res2["migrated"] is False and "already" in res2["reason"]


def test_migration_refuses_gate_self_reference(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_project={
        "PROJECT_CONTEXT.md": "**Protected branches**: main\n**Gate**: bash hooks/run-gate.sh\n",
        "hooks/run-gate.sh": "x\n",
    })
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["error"].startswith("gate_self_reference")
    assert not (proj / ".claude" / "rules" / "project.md").exists()
    assert not (tmp_path / "b").exists()
    assert json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))["version"] == 2
    dry = _migrate(proj, dry_run=True)
    assert dry["gate_self_reference"] == [{"key": "Gate", "path": "hooks/run-gate.sh"}]
    assert dry["gate_unverified"] is True


def test_migration_open_brain_manifest_shape(tmp_path):
    # v2, two hand-written unknown keys, 26 clean entries, 3 keep-mine resolutions (review §9d).
    entries = {
        f".claude/agents/a{i:02d}.md": {"templateHash": ts._sha256(f"a{i}\n"), "localHash": ts._sha256(f"a{i}\n"),
                                       "locallyModified": False}
        for i in range(26)
    }
    for i in range(3):
        entries[f"hooks/h{i}.sh"] = {"templateHash": ts._sha256(f"h{i}\n"), "localHash": ts._sha256("mine\n"),
                                     "locallyModified": True, "resolution": "keep-mine"}
    entries["hooks/h0.sh"]["reason"] = "Project-specific config"     # batch 8: survives, reported
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_entries=entries)
    m = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    m["lastSyncedVersion"] = "v2.3.0"
    m["lastSyncedVersionOf"] = "claude-code-toolkit"
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")

    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert res["migrated"] is True
    assert sorted(res["unknown_keys"]) == ["deletedAcknowledged", "lastSyncedVersion", "lastSyncedVersionOf"]
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["template_version"] == "v2.3.0"                 # server-written
    assert out["lastSyncedVersion"] == "v2.3.0" and out["lastSyncedVersionOf"] == "claude-code-toolkit"
    assert out["files"]["hooks/h0.sh"] == {"hash": "sha256:" + ts._sha256("h0\n"), "ownership": "template",
                                           "reason": "Project-specific config"}
    assert out["files"]["hooks/h1.sh"] == {"hash": "sha256:" + ts._sha256("h1\n"), "ownership": "template"}
    assert res["unknown_file_keys"] == [{"path": "hooks/h0.sh", "keys": ["reason"]}]
    assert "resolution" not in json.dumps(out["files"])
    assert len(out["files"]) == 26 + 3 + 2                       # agents, hooks, CLAUDE.md, settings.json


# ---------------------------------------------------------------------------
# v1 is refused rather than silently migrated (0.3.5 item 3).
# ---------------------------------------------------------------------------

def _downgrade_to_v1(proj, drop_version_key: bool = False):
    """A v1 manifest as one actually looked: no version 2 fields on the entries."""
    p = proj / ".claude" / "template-manifest.json"
    m = json.loads(p.read_text(encoding="utf-8"))
    if drop_version_key:
        m.pop("version", None)
    else:
        m["version"] = 1
    for entry in m["files"].values():
        entry.pop("templateRawHash", None)
        entry.pop("localHash", None)
    p.write_text(json.dumps(m), encoding="utf-8", newline="")
    return p.read_text(encoding="utf-8")


def test_v1_manifest_is_refused_not_migrated(tmp_path):
    """migrate_manifest guarded only against v3, so a v1 manifest fell straight
    into the v2 path. A v1 entry has no localHash and may have no templateHash,
    so the baseline would be silently set to the CURRENT template -- recording
    "you are up to date" for a file the consumer may have deviated in, which is
    the same silent-loss shape 0.3.4 was released to end. Refuse instead.
    """
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    before = _downgrade_to_v1(proj)

    res = _migrate(proj, backup_dir=str(tmp_path / "b"))

    assert "error" in res
    assert "v1" in res["error"]
    assert "template_load_manifest" in res["error"]      # the remedy, named
    assert res.get("migrated") is not True
    # Nothing written: not the manifest, not project.md.
    assert (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8") == before
    assert not (proj / ".claude" / "rules" / "project.md").exists()


def test_v1_manifest_is_refused_in_dry_run_too(tmp_path):
    """dry_run computes the same plan, so it reaches the same bad baseline --
    the refusal belongs before the plan, not before the write."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _downgrade_to_v1(proj)
    res = _migrate(proj, dry_run=True)
    assert "error" in res and "v1" in res["error"]


def test_missing_version_key_reads_as_v1_and_is_refused(tmp_path):
    """template_load_manifest reads a missing `version` as 1, so this tool must
    agree with it -- two readers disagreeing about what a manifest IS is worse
    than either answer."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _downgrade_to_v1(proj, drop_version_key=True)
    res = _migrate(proj, dry_run=True)
    assert "error" in res and "v1" in res["error"]


def test_v2_manifest_still_migrates_after_the_v1_guard(tmp_path):
    """The other arm: the guard must not catch the version it exists to let
    through. Without this a refuse-everything guard passes the tests above."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert "error" not in res
    assert res["migrated"] is True


# ---------------------------------------------------------------------------
# dropped_resolutions rows carry the resulting ownership (0.3.5 item 4).
# ---------------------------------------------------------------------------

def test_dropped_resolution_rows_carry_the_resulting_ownership(tmp_path):
    """A dropped keep-mine record is only a hazard when the file lands in the
    TEMPLATE class -- `once` keeps the consumer's file (apply returns "kept",
    0 bytes) and a classless path is never written at all. Without the class on
    the row a caller has to join against the returned manifest to know which,
    and one that skips the join warns about files v3 already protects. Measured
    on a live consumer: all four of their deviation-bearing entries were safe.
    """
    entries = {
        "hooks/at-risk.sh": {"templateHash": ts._sha256("t\n"), "localHash": ts._sha256("mine\n"),
                             "locallyModified": True, "resolution": "keep-mine"},
        ".gitignore": {"templateHash": ts._sha256("ig\n"), "localHash": ts._sha256("mine\n"),
                       "locallyModified": True, "resolution": "keep-mine"},
        ".claude/agents/local-x.md": {"templateHash": ts._sha256("l\n"), "localHash": ts._sha256("l\n"),
                                     "locallyModified": False, "resolution": "keep-mine"},
        # No rule matches this path at all -- the template stopped shipping it.
        "CLAUDE.local.md": {"templateHash": ts._sha256("local Demo\n"),
                            "localHash": ts._sha256("local Demo\n"),
                            "locallyModified": False, "resolution": "keep-mine"},
    }
    repo, proj, commit = _mk_v2(
        tmp_path, PROJ_CLAUDE, extra_entries=entries,
        extra_project={"hooks/at-risk.sh": "mine\n", ".gitignore": "mine\n",
                       ".claude/agents/local-x.md": "l\n"})
    (repo / "templates" / "general" / "gitignore").write_text("ig\n", encoding="utf-8", newline="")

    res = _migrate(proj, backup_dir=str(tmp_path / "b"))

    rows = {r["path"]: r for r in res["dropped_resolutions"]}
    assert rows["hooks/at-risk.sh"]["ownership"] == "template"      # the real hazard
    assert rows[".gitignore"]["ownership"] == "once"                # apply keeps it
    assert rows[".claude/agents/local-x.md"]["ownership"] == "project"
    assert rows["CLAUDE.local.md"]["ownership"] is None             # no rule matches
    # The pre-0.3.5 keys are unchanged -- this is additive, nothing renamed.
    assert rows["hooks/at-risk.sh"]["resolution"] == "keep-mine"
    assert set(rows["hooks/at-risk.sh"]) == {"path", "resolution", "ownership"}
    # The class on the row agrees with the class in the manifest it returns.
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["files"]["hooks/at-risk.sh"]["ownership"] == "template"
    assert out["files"][".gitignore"]["ownership"] == "once"
    assert ".claude/agents/local-x.md" not in out["files"]


# ---------------------------------------------------------------------------
# Unknown keys on DROPPED entries are reported (0.3.5 item 5).
# ---------------------------------------------------------------------------

def test_unknown_keys_on_dropped_entries_are_reported(tmp_path):
    """carry_unknown_file_keys runs only when a new entry is built, so an
    annotation on an entry that gets DROPPED was neither carried nor reported:
    `dropped_entries` gave a bare path and the key vanished from every response.
    Same silent-loss shape as the keep-mine record 0.3.4 reported, in the branch
    nobody looked at -- and unobservable without this field, which is why "no
    consumer has hit it" and "no consumer could tell us" were the same sentence.
    """
    entries = {
        # project class: dropped, and carrying a consumer annotation.
        ".claude/agents/local-x.md": {"templateHash": ts._sha256("l\n"), "localHash": ts._sha256("l\n"),
                                     "locallyModified": False, "reason": "Project-specific agent"},
        # no rule matches: dropped too, with two annotations.
        "CLAUDE.local.md": {"templateHash": ts._sha256("local Demo\n"),
                            "localHash": ts._sha256("local Demo\n"), "locallyModified": False,
                            "reason": "Local only", "owner": "platform-team"},
        # template class: survives, so it belongs to unknown_file_keys instead.
        "hooks/kept.sh": {"templateHash": ts._sha256("k\n"), "localHash": ts._sha256("k\n"),
                          "locallyModified": False, "reason": "Kept annotation"},
    }
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_entries=entries,
                                extra_project={".claude/agents/local-x.md": "l\n",
                                               "hooks/kept.sh": "k\n"})

    res = _migrate(proj, backup_dir=str(tmp_path / "b"))

    assert res["dropped_file_keys"] == [
        {"path": ".claude/agents/local-x.md", "keys": ["reason"]},
        {"path": "CLAUDE.local.md", "keys": ["owner", "reason"]},
    ]
    # The two lists partition: a surviving entry is never in both.
    assert res["unknown_file_keys"] == [{"path": "hooks/kept.sh", "keys": ["reason"]}]
    dropped_paths = {r["path"] for r in res["dropped_file_keys"]}
    assert dropped_paths.isdisjoint({r["path"] for r in res["unknown_file_keys"]})
    assert dropped_paths <= set(res["dropped_entries"])
    # The values are not lost: the pre-migration manifest is in the backup.
    bak = json.loads((tmp_path / "b" / "template-manifest.json.pre-migration").read_text(encoding="utf-8"))
    assert bak["files"]["CLAUDE.local.md"]["owner"] == "platform-team"


def test_dropped_file_keys_is_empty_when_no_dropped_entry_is_annotated(tmp_path):
    """Asserted so an empty list means "nothing annotated" rather than "this
    build cannot tell you" -- the discipline 0.3.4 established."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    res = _migrate(proj, dry_run=True)
    assert res["dropped_entries"] == ["CLAUDE.local.md"]     # dropped, but unannotated
    assert res["dropped_file_keys"] == []


def test_superseded_v2_keys_are_not_reported_as_dropped_annotations(tmp_path):
    """templateHash and friends are dropped by design and reported nowhere; a
    field that listed them would bury the one key a consumer put there. And
    `resolution` has its own list, so it must not appear twice."""
    entries = {
        "CLAUDE.local.md": {"templateHash": ts._sha256("local Demo\n"),
                            "localHash": ts._sha256("local Demo\n"),
                            "locallyModified": True, "resolution": "keep-mine"},
    }
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE, extra_entries=entries)
    res = _migrate(proj, dry_run=True)
    assert res["dropped_file_keys"] == []
    assert [r["path"] for r in res["dropped_resolutions"]] == ["CLAUDE.local.md"]
