"""template_apply_file under manifest v3: backup_dir, once, skip refused, gate refusal (review §2.7, §2.8, §9a)."""

import asyncio
import json

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


def _apply(proj, **kw):
    return _run(ts.template_apply_file(str(proj), **kw))


def test_template_identical_or_updated_writes_without_backup(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v2 {{NAME}}\n"},
                        project={"CLAUDE.md": "v1 Demo\n"},
                        entries={"CLAUDE.md": _tpl_entry("v1 {{NAME}}\n", {"NAME": "Demo"})},
                        placeholders={"NAME": "Demo"})
    res = _apply(proj, file_path="CLAUDE.md")
    assert res["action"] == "written_from_template"
    assert res["backup"] is None
    assert res["local_edit_overwritten"] is False
    assert res["manifest_entry"] == {"hash": "sha256:" + ts._sha256("v2 Demo\n"), "ownership": "template"}
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == "v2 Demo\n"


def test_local_edit_refused_without_backup_dir(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1 mine\n"},
                        entries={"CLAUDE.md": _tpl_entry("v1\n")})
    res = _apply(proj, file_path="CLAUDE.md")
    assert "backup_dir" in res["error"]
    assert (proj / "CLAUDE.md").read_text(encoding="utf-8") == "v1 mine\n"


def test_local_edit_backed_up_then_overwritten(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"hooks/gate.sh": "v1\n"}, project={"hooks/gate.sh": "v1 mine\n"},
                        entries={"hooks/gate.sh": _tpl_entry("v1\n")})
    backup = tmp_path / "backup"
    res = _apply(proj, file_path="hooks/gate.sh", backup_dir=str(backup))
    assert res["local_edit_overwritten"] is True
    assert (backup / "hooks" / "gate.sh.pre-sync").read_text(encoding="utf-8") == "v1 mine\n"
    diff = (backup / "hooks" / "gate.sh.diff").read_text(encoding="utf-8")
    assert "+v1 mine" in diff
    assert res["backup"]["pre_sync"].endswith("gate.sh.pre-sync")
    assert (proj / "hooks" / "gate.sh").read_text(encoding="utf-8") == "v1\n"


def test_skip_refused_on_template_class(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={"CLAUDE.md": "v1 mine\n"},
                        entries={"CLAUDE.md": _tpl_entry("v1\n")})
    res = _apply(proj, file_path="CLAUDE.md", source="skip")
    assert "skip" in res["error"] and "template" in res["error"]


def test_provided_on_template_class(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"CLAUDE.md": "v1\n"}, project={}, entries={})
    res = _apply(proj, file_path="CLAUDE.md", source="provided", content="custom\n")
    assert res["action"] == "created_from_provided"
    assert res["manifest_entry"]["ownership"] == "template"
    assert res["manifest_entry"]["hash"] == "sha256:" + ts._sha256("v1\n")


def test_once_created_when_missing_and_kept_when_present(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={".claude/rules/project.md": "# P\n", "gitignore": "*.log\n"},
                        project={}, entries={})
    res = _apply(proj, file_path=".claude/rules/project.md")
    assert res["action"] == "created_from_template"
    assert res["manifest_entry"] == {"ownership": "once"}
    assert (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8") == "# P\n"

    (proj / ".claude" / "rules" / "project.md").write_text("mine\n", encoding="utf-8")
    res2 = _apply(proj, file_path=".claude/rules/project.md")
    assert res2["action"] == "kept"
    assert res2["bytes_written"] == 0
    assert (proj / ".claude" / "rules" / "project.md").read_text(encoding="utf-8") == "mine\n"

    res3 = _apply(proj, file_path=".gitignore")
    assert res3["action"] == "created_from_template"
    assert (proj / ".gitignore").read_text(encoding="utf-8") == "*.log\n"


def test_unclassified_path_refused(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={"weird.toml": "w"}, project={}, entries={})
    res = _apply(proj, file_path="weird.toml")
    assert "no ownership rule" in res["error"]


def test_gate_self_reference_refused_before_any_write(tmp_path):
    repo, proj = _mk_v3(
        tmp_path, template={"hooks/run-gate.sh": "tpl\n"},
        project={"hooks/run-gate.sh": "tpl\n",
                 "PROJECT_CONTEXT.md": "**Protected branches**: main\n**Gate**: bash hooks/run-gate.sh\n"},
        entries={"hooks/run-gate.sh": _tpl_entry("tpl\n"), "PROJECT_CONTEXT.md": {"ownership": "once"}},
    )
    res = _apply(proj, file_path="hooks/run-gate.sh", backup_dir=str(tmp_path / "b"))
    assert res["error"].startswith("gate_self_reference")
    assert "Gate" in res["error"]
    assert (proj / "hooks" / "run-gate.sh").read_text(encoding="utf-8") == "tpl\n"
    assert not (tmp_path / "b").exists()


def test_v2_manifest_path_unchanged(tmp_path):
    # A v2 manifest keeps the 0.2.x behaviour: source="skip" is still allowed.
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "CLAUDE.md").write_text("v1\n", encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text("mine\n", encoding="utf-8")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {"CLAUDE.md": {"templateHash": ts._sha256("v1\n")}},
    }), encoding="utf-8")
    res = _apply(proj, file_path="CLAUDE.md", source="skip")
    assert res["action"] == "skipped"
    assert res["manifest_entry"]["resolution"] == "keep-mine"
