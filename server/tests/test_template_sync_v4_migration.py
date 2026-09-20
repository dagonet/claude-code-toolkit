"""v3 -> v4 migration (v4.1 plan Task 1 commit 6 -- spec §7 step 1c, §9).

Refuse-not-guess: an out-of-region CLAUDE.md diff, or a pre-existing
.claude/project-instructions.md, REFUSES with nothing written -- never a
silent guess.
"""

import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3

OWNERSHIP = {
    "tracked_paths": ["templates"],
    "rules": [
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/agents/*.md", "ownership": "template"},
    ],
}

FOO_TPL = "---\nname: foo\ntools: Read, Write\n---\nbody\n"


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _git_out(repo, *args) -> str:
    return subprocess.run(["git", *args], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _with_region(body: str, region: str | None) -> str:
    """`region=None` -> no region at all; `region=""` -> an EMPTY region;
    otherwise a region carrying that text."""
    if region is None:
        return body + "\n"
    inner = f"\n{region}\n" if region else "\n"
    return f"{body}\n<!-- PROJECT-CUSTOM:BEGIN -->{inner}<!-- PROJECT-CUSTOM:END -->\n"


def _mk_v3(tmp_path, claude_body: str = "# T\nrule one", tpl_region: str | None = "",
          proj_region: str | None = "MY RULE", agents: dict[str, str] | None = None,
          project_extra: dict[str, str] | None = None):
    """A git-backed v3 fixture. `tpl_region` is what the TOOLKIT'S OWN
    template carries (a v3-era seed -- EMPTY by default, matching a
    just-bootstrapped consumer's template); `proj_region` is what the
    CONSUMER customized it to -- kept DIFFERENT from `tpl_region` by default
    so `region_was_seed` correctly reads False and `region_body` survives
    (a fixture where both sides carry the SAME text would look, correctly,
    like the consumer never touched their untouched seed)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    tpl_claude = _with_region(claude_body, tpl_region)
    (repo / "templates" / "general" / "CLAUDE.md").write_text(tpl_claude, encoding="utf-8", newline="")
    if agents:
        (repo / "templates" / "general" / ".claude" / "agents").mkdir(parents=True)
        for name, content in agents.items():
            (repo / "templates" / "general" / ".claude" / "agents" / name).write_text(
                content, encoding="utf-8", newline="")
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    commit = _git_out(repo, "rev-parse", "HEAD")

    proj_claude = _with_region(claude_body, proj_region)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(proj_claude, encoding="utf-8", newline="")
    # The manifest's stored hash is the template's OWN (region-tolerant, as
    # under v3) -- the project's committed copy legitimately differs only in
    # its own region, exactly the region_status splice v3 already handles.
    entries = {"CLAUDE.md": {"hash": "sha256:" + ts._sha256(tpl_claude), "ownership": "template"}}
    if agents:
        (proj / ".claude" / "agents").mkdir(parents=True)
        for name, content in agents.items():
            (proj / ".claude" / "agents" / name).write_text(content, encoding="utf-8", newline="")
            entries[f".claude/agents/{name}"] = {"hash": "sha256:" + ts._sha256(content), "ownership": "template"}
    for rel, content in (project_extra or {}).items():
        p = proj / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")

    manifest = {
        "manifest_version": 3, "template_version": "v3.1.0", "template_commit": commit,
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.2", "files": entries,
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")
    return repo, proj, commit


def _migrate(proj, **kw):
    return v3.migrate_manifest(proj, backup_dir=kw.pop("backup_dir", ""),
                               dry_run=kw.pop("dry_run", False), **kw)


def _all_bytes(proj) -> dict:
    return {str(p.relative_to(proj)): p.read_bytes() for p in proj.rglob("*") if p.is_file()}


# --- (a) dry-run lists the region body ---------------------------------


def test_dry_run_lists_region_body_with_content(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE\nsecond line")
    res = _migrate(proj, dry_run=True)
    assert "error" not in res, res
    assert res["migrated"] is False and res["dry_run"] is True
    assert res["region_body"] == "MY RULE\nsecond line"
    assert res["region_was_seed"] is None or res["region_was_seed"] is False
    assert not (proj / ".claude" / "project-instructions.md").exists()
    assert not (proj / ".claude" / "agent-grants.json").exists()


def test_dry_run_empty_region_previews_header_only_seed(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="")
    res = _migrate(proj, dry_run=True)
    assert "error" not in res, res
    assert res["region_body"] in (None, "")
    assert res["instructions_content"].strip() != ""
    assert "MY RULE" not in res["instructions_content"]


# --- real run: project-instructions.md, CLAUDE.md, manifest v4 -----------


def test_real_run_writes_region_verbatim_claude_md_matches_template_manifest_v4(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE\nsecond line")
    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert "error" not in res, res
    assert res["migrated"] is True

    instructions = (proj / ".claude" / "project-instructions.md").read_text(encoding="utf-8")
    assert instructions.endswith("MY RULE\nsecond line\n")

    tpl_claude = (repo / "templates" / "general" / "CLAUDE.md").read_text(encoding="utf-8")
    proj_claude = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    assert proj_claude == tpl_claude

    written_manifest = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    assert written_manifest["manifest_version"] == 4
    assert written_manifest["instructions_file"] == ".claude/project-instructions.md"
    assert written_manifest["agent_grants"] == ".claude/agent-grants.json"
    assert written_manifest["requires_server"] == ">=4.1.0"
    assert (proj / ".claude" / "agent-grants.json").is_file()

    assert res["report_path"] is not None
    report = json.loads((tmp_path / "backup" / "migration-report.json").read_text(encoding="utf-8"))
    assert report["migrated"] is True and report["to"] == "v4"

    # claude_md_identical PASS afterwards.
    rules = v3.load_ownership(str(repo))
    status = v3.compute_status_v3(proj, written_manifest, rules)
    assert status["files"]["CLAUDE.md"]["status"] == "IDENTICAL", status["files"]["CLAUDE.md"]


# --- (c) out-of-region diff refuses, nothing written -----------------------


def test_out_of_region_diff_refuses_nothing_written(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE")
    # Edit the TEMPLATE part directly on the project's CLAUDE.md (outside
    # the region) -- a real consumer edit the migration cannot safely apply.
    content = (proj / "CLAUDE.md").read_text(encoding="utf-8")
    (proj / "CLAUDE.md").write_text(content.replace("rule one", "rule one EDITED", 1),
                                    encoding="utf-8", newline="")
    before = _all_bytes(proj)
    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert "error" in res, res
    assert "out_of_region_diff" in res
    assert "EDITED" in res["out_of_region_diff"]
    after = _all_bytes(proj)
    assert after == before, "every file's bytes must be unchanged"
    assert not (tmp_path / "backup").exists() or not any((tmp_path / "backup").iterdir())


# --- (d) pre-existing project-instructions.md refuses -----------------------


def test_pre_existing_instructions_file_refuses_by_path_nothing_written(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE",
                                project_extra={".claude/project-instructions.md": "already here\n"})
    before = _all_bytes(proj)
    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert "error" in res, res
    assert ".claude/project-instructions.md" in res["error"]
    after = _all_bytes(proj)
    assert after == before, "every file's bytes must be unchanged"


# --- (b) grant-shaped agent diff -------------------------------------------


def test_grant_shaped_agent_diff_becomes_a_grants_entry_agent_reads_identical_after_apply(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE", agents={"foo.md": FOO_TPL})
    # The consumer manually appended a tool to foo's tools: line (the
    # pre-v4.1 workaround this migration step replaces).
    edited = FOO_TPL.replace("tools: Read, Write\n", "tools: Read, Write, mcp__glider__symbol_lookup\n")
    assert edited != FOO_TPL
    (proj / ".claude" / "agents" / "foo.md").write_text(edited, encoding="utf-8", newline="")

    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert "error" not in res, res
    grants = json.loads((proj / ".claude" / "agent-grants.json").read_text(encoding="utf-8"))
    assert grants["grants"] == {"foo": ["mcp__glider__symbol_lookup"]}

    written_manifest = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    rules = v3.load_ownership(str(repo))
    status = v3.compute_status_v3(proj, written_manifest, rules)
    info = status["files"][".claude/agents/foo.md"]
    assert info["status"] == "IDENTICAL", info


def test_agent_gaining_tools_line_the_template_ships_none_for_is_refused(tmp_path):
    bare_tpl = "---\nname: bare-agent\ndescription: x\n---\nbody\n"
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE", agents={"bare-agent.md": bare_tpl})
    edited = bare_tpl.replace("description: x\n", "description: x\ntools: Read\n")
    (proj / ".claude" / "agents" / "bare-agent.md").write_text(edited, encoding="utf-8", newline="")
    before = _all_bytes(proj)
    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert "error" in res, res
    assert "bare-agent.md" in res["error"]
    assert _all_bytes(proj) == before


# --- idempotent: v4 manifest is a no-op -------------------------------------


def test_v4_manifest_is_idempotent_no_op(tmp_path):
    repo, proj, commit = _mk_v3(tmp_path, proj_region="MY RULE")
    res = _migrate(proj, backup_dir=str(tmp_path / "backup"))
    assert res["migrated"] is True
    again = _migrate(proj, backup_dir=str(tmp_path / "backup2"))
    assert "error" not in again
    assert again["migrated"] is False and again.get("already_v4") is True
