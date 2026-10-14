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
    (repo / "hooks").mkdir(parents=True)
    (repo / "hooks" / "git-pre-push.sh").write_text("pre-push\n", encoding="utf-8")
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
        "hooks/git-pre-push.sh": "template",
        ".claude/agent-grants.json": "once",
    })
    res = json.loads(asyncio.run(ts.template_compute_status(str(proj))))
    files = res["files"]
    assert files[".claude/agents/coder.md"]["status"] == "TEMPLATE_DELETED"
    assert files["hooks/pre-commit-test.sh"]["status"] == "TEMPLATE_DELETED"
    assert files["hooks/git-pre-push.sh"]["status"] != "TEMPLATE_DELETED"
    grants = files[".claude/agent-grants.json"]
    assert grants["status"] != "unknown" and "error" not in res
    assert grants["ownership"] == "once"


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


def test_grants_code_is_gone():
    for name in ("GrantsError", "GrantRefused", "load_grants", "splice_tools",
                 "agent_name_of", "_frontmatter_body"):
        assert not hasattr(v3, name), name
