"""v5.0 (Task 10): the sync ships only the pre-push hook set; agent grants are gone.

Spec §3.4 / §4. Projects receive hooks/git-pre-push.sh and the two libraries it
sources; every other hook ships in the cct plugin. A v4.6.x consumer's existing
agent/hook files still classify (rules are kept) and resolve TEMPLATE_DELETED.
"""

import asyncio
import json
import pathlib

from template_sync import mcp as ts
from template_sync import v3

PRE_PUSH_SET = {"hooks/git-pre-push.sh", "hooks/lib/git-cmd.sh", "hooks/lib/json.sh"}
REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
MARKER = "v5.1.0"   # the fixture checkout's own sync-template skill tag (above the real floor)


def test_scan_ships_only_the_pre_push_hook_set(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "hooks" / "lib").mkdir(parents=True)
    for p in sorted(PRE_PUSH_SET) + ["hooks/pre-commit-test.sh", "hooks/run-hook.sh",
                                     "hooks/hooks.json", "hooks/lib/agent-model.sh"]:
        (repo / p).write_text("x\n")
    tpl = repo / "templates" / "general"
    (tpl / ".claude").mkdir(parents=True)
    (tpl / "CLAUDE.md").write_text("x\n")
    scanned = ts._scan_template_files(tpl, repo)
    assert {p for p in scanned if p.startswith("hooks/")} == PRE_PUSH_SET
    assert "CLAUDE.md" in scanned


def test_root_tracked_is_the_explicit_tuple():
    assert set(ts.ROOT_TRACKED_FILES) == PRE_PUSH_SET
    assert ts._is_root_tracked("hooks/git-pre-push.sh")
    assert not ts._is_root_tracked("hooks/pre-commit-test.sh")


def _consumer(tmp_path, files):
    """A v4.6.1-shaped consumer: manifest lists `files`, all present on disk,
    none shipped by the (v5.0) template except the pre-push hook."""
    repo = tmp_path / "toolkit"
    (repo / "hooks" / "lib").mkdir(parents=True)
    for rel in ("hooks/git-pre-push.sh", "hooks/pre-commit-test.sh", "hooks/lib/agent-model.sh"):
        (repo / rel).write_text("hook\n", encoding="utf-8")   # as in the real toolkit tree
    (repo / "skills" / "sync-template").mkdir(parents=True)
    (repo / "skills" / "sync-template" / "SKILL.md").write_text(
        f"<!-- SYNC-TEMPLATE-SKILL-VERSION: {MARKER} -->\n", encoding="utf-8")
    (repo / "templates" / "general").mkdir(parents=True)
    shutil_own = json.loads((REPO_ROOT / "templates" / "ownership.json").read_text(encoding="utf-8"))
    (repo / "templates" / "ownership.json").write_text(json.dumps(shutil_own), encoding="utf-8")
    proj = tmp_path / "proj"
    entries = {}
    for rel, ownership in files.items():
        p = proj / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("old\n", encoding="utf-8", newline="")
        entry = {"ownership": ownership}
        if ownership == "template":
            entry["hash"] = "sha256:" + ts._sha256("old\n")
        entries[rel] = entry
    manifest = {
        "manifest_version": 4, "template_version": "v4.6.1", "template_commit": "0000000",
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=4.1.0",
        "instructions_file": ".claude/project-instructions.md",
        "agent_grants": ".claude/agent-grants.json",
        "files": entries,
    }
    (proj / ".claude").mkdir(parents=True, exist_ok=True)
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    return proj


def test_v461_consumer_files_resolve_template_deleted(tmp_path):
    proj = _consumer(tmp_path, {
        ".claude/agents/coder.md": "template",
        "hooks/pre-commit-test.sh": "template",
        "hooks/lib/agent-model.sh": "template",
        "hooks/git-pre-push.sh": "template",
        ".claude/agent-grants.json": "once",
    })
    res = json.loads(asyncio.run(ts.template_compute_status(str(proj))))
    files = res["files"]
    assert "error" not in res
    assert {p: files[p]["status"] for p in files} == {
        ".claude/agents/coder.md": "TEMPLATE_DELETED",
        "hooks/pre-commit-test.sh": "TEMPLATE_DELETED",
        "hooks/lib/agent-model.sh": "TEMPLATE_DELETED",
        "hooks/git-pre-push.sh": "TEMPLATE_UPDATED",
        ".claude/agent-grants.json": "PRESENT",
    }
    assert files[".claude/agent-grants.json"]["ownership"] == "once"


def test_agent_grants_key_is_accepted_but_not_required():
    base = {"manifest_version": 4, "instructions_file": ".claude/project-instructions.md"}
    assert v3.unknown_top_level_keys({**base, "agent_grants": ".claude/agent-grants.json"}) == []
    assert v3.unknown_top_level_keys(base) == []


def test_v5_manifest_without_agent_grants_loads_clean(tmp_path):
    proj = _consumer(tmp_path, {})
    mp = proj / ".claude" / "template-manifest.json"
    m = json.loads(mp.read_text(encoding="utf-8"))
    del m["agent_grants"]
    mp.write_text(json.dumps(m), encoding="utf-8")
    manifest, errors = ts._load_manifest(proj)
    assert errors == []
    mp.write_text(json.dumps({**m, "agent_grants": ".claude/agent-grants.json"}), encoding="utf-8")
    assert ts._load_manifest(proj)[1] == []


def _load(proj, **kw):
    return json.loads(asyncio.run(ts.template_load_manifest(str(proj), **kw)))


def test_load_manifest_reports_floor_and_marker(tmp_path):
    r = _load(_consumer(tmp_path, {}), skill_version=MARKER)
    assert r["requires_skill"] == json.loads(
        (REPO_ROOT / "templates" / "ownership.json").read_text(encoding="utf-8"))["requires_skill"]
    assert r["skill_marker"] == MARKER


def test_load_manifest_refuses_missing_skill_version(tmp_path):
    r = _load(_consumer(tmp_path, {}))
    assert r["valid"] is False
    assert any("/cct:sync-template" in e for e in r["errors"])


def test_load_manifest_refuses_skill_below_floor(tmp_path):
    r = _load(_consumer(tmp_path, {}), skill_version="v4.0.0")
    assert r["valid"] is False
    assert any("requires_skill" in e and "/cct:sync-template" in e for e in r["errors"])


def test_release_floor_is_v5_and_refuses_every_v4_skill(tmp_path):
    """Spec §4 step 1: the v5.0 release raises the floor so a v4.x sync skill
    cannot add the plugin-off guard to a machine without the plugin."""
    own = json.loads((REPO_ROOT / "templates" / "ownership.json").read_text(encoding="utf-8"))
    assert own["requires_skill"] == ">=v5.0.0"
    proj = _consumer(tmp_path, {})
    for below in ("v4.6.2", "v4.99.99"):
        r = _load(proj, skill_version=below)
        assert r["valid"] is False, below
        assert any("requires_skill '>=v5.0.0'" in e for e in r["errors"]), below
    assert _load(proj, skill_version=MARKER)["valid"] is True


def _as_v2(proj):
    mp = proj / ".claude" / "template-manifest.json"
    m = json.loads(mp.read_text(encoding="utf-8"))
    mp.write_text(json.dumps({"version": 2, "variant": m["variant"], "templateRepo": m["templateRepo"],
                              "placeholders": {}, "files": {}}), encoding="utf-8")
    return proj


def test_load_manifest_v2_path_refuses_missing_skill_version(tmp_path):
    proj = _as_v2(_consumer(tmp_path, {}))
    r = _load(proj)
    assert r["manifest_version"] == 2 and r["valid"] is False
    assert any("/cct:sync-template" in e for e in r["errors"])
    assert _load(proj, skill_version=MARKER)["valid"] is True


def test_load_manifest_sentinel_bypasses_and_near_miss_is_refused(tmp_path):
    proj = _consumer(tmp_path, {})
    ok = _load(proj, skill_version="not-a-skill")
    assert ok["valid"] is True and ok["skill_version_bypassed"] is True
    bad = _load(proj, skill_version="Not-A-Skill")
    assert bad["valid"] is False and "tag-shaped" in " ".join(bad["errors"])
    assert "skill_version_bypassed" not in bad


def test_load_manifest_unparseable_checkout_marker_warns(tmp_path):
    proj = _consumer(tmp_path, {})
    (tmp_path / "toolkit" / "skills" / "sync-template" / "SKILL.md").write_text(
        "<!-- SYNC-TEMPLATE-SKILL-VERSION: banana -->\n", encoding="utf-8")
    r = _load(proj, skill_version="v5.0.0")
    assert r["skill_marker"] == "" and r["valid"] is True
    assert any("skill_marker_unparseable" in w for w in r["warnings"])


def test_load_manifest_accepts_skill_equal_to_marker(tmp_path):
    r = _load(_consumer(tmp_path, {}), skill_version=MARKER)
    assert r["valid"] is True and r["errors"] == []


def test_load_manifest_refuses_skill_below_marker_but_above_floor(tmp_path):
    r = _load(_consumer(tmp_path, {}), skill_version="v5.0.0")
    assert r["valid"] is False
    assert any("claude plugin update cct@dagonet" in e for e in r["errors"])


def test_grants_code_is_gone():
    for name in ("GrantsError", "GrantRefused", "load_grants", "splice_tools",
                 "agent_name_of", "_frontmatter_body"):
        assert not hasattr(v3, name), name
