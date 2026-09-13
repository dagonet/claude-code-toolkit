"""template_finalize_sync under manifest v3 and template_version derivation (review §2.10, §6.3)."""

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


def _tpl_entry(content: str, placeholders: dict | None = None) -> dict:
    replaced = ts._apply_placeholders(content, placeholders or {})
    return {"hash": "sha256:" + ts._sha256(replaced), "ownership": "template"}


def _run(coro):
    return json.loads(asyncio.run(coro))


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _git_out(repo, *args) -> str:
    return subprocess.run(["git", *args], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _init_repo(repo):
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    return _git_out(repo, "rev-parse", "HEAD")


def test_derive_template_version_tree_identical_reachable_tag(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n", "hooks/g.sh": "g\n"}, project={}, entries={})
    c1 = _init_repo(repo)
    _git(repo, "tag", "v3.1.0")
    # A commit that touches only an untracked path keeps the tracked tree identical.
    (repo / "README.md").write_text("docs\n", encoding="utf-8")
    _git(repo, "add", "README.md")
    _git(repo, "commit", "-q", "-m", "docs")
    c2 = _git_out(repo, "rev-parse", "HEAD")
    assert v3.derive_template_version(str(repo), c2, ["templates", "hooks"]) == ("v3.1.0", None)
    # A commit that changes a tracked path is untagged.
    (repo / "hooks" / "g.sh").write_text("g2\n", encoding="utf-8")
    _git(repo, "add", "hooks/g.sh")
    _git(repo, "commit", "-q", "-m", "hook")
    c3 = _git_out(repo, "rev-parse", "HEAD")
    assert v3.derive_template_version(str(repo), c3, ["templates", "hooks"]) == (None, "untagged_template_tree")


def test_derive_template_version_not_git(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={}, entries={})
    assert v3.derive_template_version(str(repo), "abc", ["templates"]) == (None, "template_repo_not_git")


def test_finalize_v3_writes_prefixed_hashes_and_reports_unknown_keys(tmp_path):
    repo, proj = _mk_v3(tmp_path,
                        template={"CLAUDE.md": "v1\n", ".claude/rules/project.md": "p\n", "hooks/new.sh": "n\n"},
                        project={"CLAUDE.md": "v1\n", ".claude/rules/project.md": "mine\n", "hooks/new.sh": "n\n"},
                        entries={"CLAUDE.md": _tpl_entry("v0\n")})
    m = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    m["deletedAcknowledged"] = ["x.md"]
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")
    _init_repo(repo)
    _git(repo, "tag", "v3.1.0")
    head = _git_out(repo, "rev-parse", "HEAD")

    applied = json.dumps([
        {"file_path": "CLAUDE.md", "manifest_entry": {"hash": ts._sha256("v1\n"), "ownership": "template"}},
        {"file_path": ".claude/rules/project.md", "manifest_entry": {"ownership": "once"}},
    ])
    res = _run(ts.template_finalize_sync(str(proj), applied, new_files=json.dumps(["hooks/new.sh"])))
    assert res["manifest_written"] is True
    assert res["template_commit"] == head
    assert res["template_version"] == "v3.1.0"
    assert res["unknown_keys"] == ["deletedAcknowledged"]
    assert res["files_updated"] == 2 and res["files_added"] == 1

    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["manifest_version"] == 3
    assert out["template_commit"] == head
    assert out["template_version"] == "v3.1.0"
    assert out["requires_server"] == ">=0.3.2"   # raised from the fixture's >=0.3.0
    assert out["deletedAcknowledged"] == ["x.md"]
    assert "lastSynced" not in out and "version" not in out
    assert out["files"]["CLAUDE.md"] == {"hash": "sha256:" + ts._sha256("v1\n"), "ownership": "template"}
    assert out["files"][".claude/rules/project.md"] == {"ownership": "once"}
    assert out["files"]["hooks/new.sh"] == {"hash": "sha256:" + ts._sha256("n\n"), "ownership": "template"}


def test_finalize_raises_a_floor_below_the_splice_floor(tmp_path):
    """The earliest adopters migrated before the hazard was understood and
    carry ">=0.3.0" forever: the emitter reaches new projects and the skill
    gate reaches first migrations, but nothing reaches them. Raising on
    finalize is what does."""
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"},
                        entries={}, requires_server=">=0.3.0")
    res = _run(ts.template_finalize_sync(str(proj), "[]"))
    assert res["requires_server_raised"] == {"from": ">=0.3.0", "to": ">=0.3.2"}
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == ">=0.3.2"


def test_finalize_never_lowers_a_stricter_floor(tmp_path):
    """A consumer who pinned higher has made a decision; silently relaxing it
    would be the same class of defect this round has been closing. Monotonic
    tightening is what makes it safe to touch a field the emitter owns."""
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"},
                        entries={}, requires_server=">=0.9.1")
    res = _run(ts.template_finalize_sync(str(proj), "[]"))
    assert "requires_server_raised" not in res
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == ">=0.9.1"


def test_finalize_leaves_an_equal_floor_alone(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"},
                        entries={}, requires_server=">=0.3.2")
    res = _run(ts.template_finalize_sync(str(proj), "[]"))
    assert "requires_server_raised" not in res
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == ">=0.3.2"


def test_finalize_does_not_rewrite_a_floor_it_cannot_parse(tmp_path):
    """An unparseable floor already makes load refuse. Rewriting it would
    silently repair a manifest the server does not understand."""
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"},
                        entries={}, requires_server="^0.3.0")
    res = _run(ts.template_finalize_sync(str(proj), "[]"))
    assert "requires_server_raised" not in res
    assert any("requires_server" in w for w in res["warnings"])
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == "^0.3.0"


def test_finalize_fallback_floor_is_the_splice_floor(tmp_path):
    """A v3 manifest that somehow carries no requires_server gets the splice
    floor written into it, not the older v3 floor."""
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"}, entries={})
    m = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    del m["requires_server"]
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(m), encoding="utf-8")
    _run(ts.template_finalize_sync(str(proj), "[]"))
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["requires_server"] == ">=0.3.2"


def test_finalize_v3_rejects_bad_hash_and_ownership(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"}, entries={})
    applied = json.dumps([
        {"file_path": "CLAUDE.md", "manifest_entry": {"hash": "sha256:nope", "ownership": "template"}},
        {"file_path": "x.md", "manifest_entry": {"hash": "sha256:" + "a" * 64, "ownership": "merge"}},
    ])
    res = _run(ts.template_finalize_sync(str(proj), applied))
    assert "manifest NOT written" in res["error"]
    assert len(res["invalid_entries"]) == 2


def test_finalize_v3_drop_sweep_and_explicit_deletes(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"},
                        project={"CLAUDE.md": "v1\n", ".claude/agents/kept.md": "k\n"},
                        entries={"CLAUDE.md": _tpl_entry("v1\n"),
                                 "hooks/gone.sh": _tpl_entry("g\n"),
                                 ".claude/agents/kept.md": _tpl_entry("k\n")})
    res = _run(ts.template_finalize_sync(str(proj), "[]", deleted_files=json.dumps([".claude/agents/kept.md"])))
    assert sorted(res["dropped_entries"]) == [".claude/agents/kept.md", "hooks/gone.sh"]
    assert "template_repo_not_git" in res["warnings"]
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert list(out["files"]) == ["CLAUDE.md"]
    assert out["template_version"] is None


def test_finalize_reads_applied_files_from_path_and_echoes_consumed(tmp_path):
    # panoscribe (batch 9): tool results reach finalize through a file the skill
    # writes, never through retyping; the response echoes what was consumed.
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n", ".claude/rules/project.md": "p\n"},
                        project={"CLAUDE.md": "v1\n", ".claude/rules/project.md": "p\n"}, entries={})
    applied = [
        {"file_path": "CLAUDE.md", "manifest_entry": {"hash": ts._sha256("v1\n"), "ownership": "template"}},
        {"file_path": ".claude/rules/project.md", "manifest_entry": {"ownership": "once"}},
    ]
    path = tmp_path / "applied.json"
    path.write_text(json.dumps(applied), encoding="utf-8")
    res = _run(ts.template_finalize_sync(str(proj), "[]", applied_files_path=str(path)))
    assert res["manifest_written"] is True
    assert res["consumed_entries"] == 2
    assert res["consumed"] == [
        {"path": ".claude/rules/project.md", "hash": None},
        {"path": "CLAUDE.md", "hash": "sha256:" + ts._sha256("v1\n")},
    ]
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert set(out["files"]) == {"CLAUDE.md", ".claude/rules/project.md"}


def test_finalize_applied_files_path_errors_leave_manifest_untouched(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"}, entries={})
    before = (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8")
    res = _run(ts.template_finalize_sync(str(proj), "[]", applied_files_path=str(tmp_path / "missing.json")))
    assert "applied_files_path" in res["error"]
    bad = tmp_path / "bad.json"
    bad.write_text(json.dumps({"not": "an array"}), encoding="utf-8")
    res2 = _run(ts.template_finalize_sync(str(proj), "[]", applied_files_path=str(bad)))
    assert "applied_files_path" in res2["error"]
    assert (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8") == before


def test_finalize_v2_path_echoes_consumed_template_hash(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "CLAUDE.md").write_text("v1\n", encoding="utf-8", newline="")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text("v1\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {},
    }), encoding="utf-8")
    h = ts._sha256("v1\n")
    applied = json.dumps([{"file_path": "CLAUDE.md", "manifest_entry": {
        "templateHash": h, "templateRawHash": h, "localHash": h, "locallyModified": False}}])
    res = _run(ts.template_finalize_sync(str(proj), applied))
    assert res["consumed_entries"] == 1
    assert res["consumed"] == [{"path": "CLAUDE.md", "hash": h}]


def test_finalize_v3_preserves_per_file_unknown_keys(tmp_path):
    # open-brain (batch 8): a hand-added per-file annotation must survive an
    # applied entry that does not carry it, and be reported (review §12).
    entry = dict(_tpl_entry("v0\n"), reason="Project-specific config", note="x")
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1\n"},
                        entries={"CLAUDE.md": entry})
    applied = json.dumps([
        {"file_path": "CLAUDE.md", "manifest_entry": {"hash": "sha256:" + ts._sha256("v1\n"), "ownership": "template"}},
    ])
    res = _run(ts.template_finalize_sync(str(proj), applied))
    assert res["unknown_file_keys"] == [{"path": "CLAUDE.md", "keys": ["note", "reason"]}]
    out = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert out["files"]["CLAUDE.md"] == {
        "hash": "sha256:" + ts._sha256("v1\n"), "ownership": "template",
        "reason": "Project-specific config", "note": "x",
    }
