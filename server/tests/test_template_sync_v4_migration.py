"""v3 -> v4 migration (v4.1 plan Task 1 commit 6 -- spec §7 step 1c, §9).

Refuse-not-guess: an out-of-region CLAUDE.md diff, or a pre-existing
.claude/project-instructions.md, REFUSES with nothing written -- never a
silent guess.
"""

import asyncio
import json
import re
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3
from template_sync import verify

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


# =============================================================================
# v4.1.1 spec 1.1/1.2 (Task 1): migrate_v3_to_v4 derives, does not construct;
# the grants detector routes through the region split.
#
# NOTE ON FIXTURES: the brief for this task claimed a `v3_consumer` fixture
# object and wrapper functions (migrate_v3_to_v4_write/_dry_run,
# compute_status, template_verify_lines, apply_file) already existed in this
# module. They did not -- only the plain `_mk_v3`/`_migrate`/`_all_bytes`
# helpers above existed. Everything below is new fixture code, built to the
# ASSERTION shapes the brief's test bodies specify, not to literal helper
# names it assumed.
# =============================================================================

CODER_TPL = (
    "---\nname: coder\ntools: Read, Write\n---\n"
    "body\n"
    "<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n"
)
AGENT_TEAM_BODY = "# Agent Team\n\nShared workflow doc.\n"
V3C_CLAUDE_BODY = "# T\nrule one"


class V3Consumer:
    """A v3 consumer whose template repo ships CLAUDE.md (region-bearing),
    AGENT_TEAM.md (plain template-class), .claude/agents/coder.md
    (template-class, region-bearing, carries a tools: line) and whose
    project also carries PROJECT_CONTEXT.md (once-class, template does not
    ship it -- matches the real toolkit's once-seed shape)."""

    def __init__(self, repo, proj, commit, old_manifest):
        self.repo = repo
        self.proj = proj
        self.commit = commit
        self.old_manifest = old_manifest

    def write_manifest(self):
        (self.proj / ".claude" / "template-manifest.json").write_text(
            json.dumps(self.old_manifest), encoding="utf-8", newline="")

    def edit_template(self, repo_rel_path: str, append: str = ""):
        """Append `append` to a file under the TEMPLATE repo and commit --
        simulates "the template moved on after this consumer synced"."""
        p = self.repo / repo_rel_path
        p.write_text(p.read_text(encoding="utf-8") + append, encoding="utf-8", newline="")
        _git(self.repo, "add", "-A")
        _git(self.repo, "commit", "-q", "-m", "template moves on")

    def acknowledge_deleted(self, proj_rel: str):
        """The template no longer ships `proj_rel`; the consumer keeps it
        (SKILL.md step 6)."""
        tpl_path = self.repo / "templates" / "general" / proj_rel
        if tpl_path.exists():
            tpl_path.unlink()
            _git(self.repo, "add", "-A")
            _git(self.repo, "commit", "-q", "-m", f"drop {proj_rel}")
        acked = sorted(set(self.old_manifest.get("deletedAcknowledged", [])) | {proj_rel})
        self.old_manifest["deletedAcknowledged"] = acked
        self.write_manifest()

    def add_tools_to_agent(self, proj_rel: str, tools: list[str]):
        """Simulates the pre-v4.1 workaround: hand-appending tool names to
        an agent's on-disk `tools:` frontmatter line."""
        p = self.proj / proj_rel
        text = p.read_text(encoding="utf-8")

        def _append(m: re.Match) -> str:
            existing = m.group(1).rstrip()
            return "tools: " + existing + "".join(f", {t}" for t in tools)

        new_text, n = re.subn(r"^tools:[ \t]*(.*)$", _append, text, count=1, flags=re.M)
        assert n == 1, f"no tools: line found in {proj_rel}"
        p.write_text(new_text, encoding="utf-8", newline="")

    def add_region_content(self, proj_rel: str, text: str):
        """Fill the (empty, template-shipped) PROJECT-CUSTOM region of an
        on-disk project file with `text`."""
        p = self.proj / proj_rel
        content = p.read_text(encoding="utf-8")
        _part, region = ts._split_custom_region(content)
        assert region is not None, f"{proj_rel} has no PROJECT-CUSTOM markers to fill"
        new_region = "<!-- PROJECT-CUSTOM:BEGIN -->\n" + text.rstrip("\n") + "\n<!-- PROJECT-CUSTOM:END -->"
        p.write_text(content.replace(region, new_region, 1), encoding="utf-8", newline="")

    def snapshot_tree(self) -> dict:
        return _all_bytes(self.proj)


@pytest.fixture
def v3_consumer(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general" / ".claude" / "agents").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    tpl_claude = _with_region(V3C_CLAUDE_BODY, "")
    (repo / "templates" / "general" / "CLAUDE.md").write_text(tpl_claude, encoding="utf-8", newline="")
    (repo / "templates" / "general" / "AGENT_TEAM.md").write_text(AGENT_TEAM_BODY, encoding="utf-8", newline="")
    (repo / "templates" / "general" / ".claude" / "agents" / "coder.md").write_text(
        CODER_TPL, encoding="utf-8", newline="")
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    commit = _git_out(repo, "rev-parse", "HEAD")

    proj = tmp_path / "proj"
    (proj / ".claude" / "agents").mkdir(parents=True)
    proj_claude = _with_region(V3C_CLAUDE_BODY, "MY RULE")
    (proj / "CLAUDE.md").write_text(proj_claude, encoding="utf-8", newline="")
    (proj / "AGENT_TEAM.md").write_text(AGENT_TEAM_BODY, encoding="utf-8", newline="")
    (proj / "PROJECT_CONTEXT.md").write_text("# Project Context\n\nplaceholder\n", encoding="utf-8", newline="")
    (proj / ".claude" / "agents" / "coder.md").write_text(CODER_TPL, encoding="utf-8", newline="")

    entries = {
        "CLAUDE.md": {"hash": "sha256:" + ts._sha256(tpl_claude), "ownership": "template"},
        "AGENT_TEAM.md": {"hash": "sha256:" + ts._sha256(AGENT_TEAM_BODY), "ownership": "template"},
        ".claude/agents/coder.md": {"hash": "sha256:" + ts._sha256(CODER_TPL), "ownership": "template"},
        "PROJECT_CONTEXT.md": {"ownership": "once"},
    }
    manifest = {
        "manifest_version": 3, "template_version": "v3.1.0", "template_commit": commit,
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.2", "files": entries,
    }
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps(manifest), encoding="utf-8", newline="")
    return V3Consumer(repo=repo, proj=proj, commit=commit, old_manifest=manifest)


def migrate_v3_to_v4_write(c: V3Consumer) -> dict:
    return v3.migrate_manifest(c.proj, backup_dir=str(c.proj.parent / "backup"), dry_run=False)


def migrate_v3_to_v4_dry_run(c: V3Consumer) -> dict:
    return v3.migrate_manifest(c.proj, backup_dir="", dry_run=True)


def compute_status(c: V3Consumer) -> dict:
    manifest, errors = ts._load_manifest(c.proj)
    assert manifest is not None, errors
    rules = v3.load_ownership(str(c.repo))
    return v3.compute_status_v3(c.proj, manifest, rules)


def template_verify_lines(c: V3Consumer, mode: str = "post_commit") -> dict:
    result = verify.run(str(c.proj), template_repo=str(c.repo), mode=mode)
    return {line["id"]: line for line in result["lines"]}


def _run_async(coro):
    return json.loads(asyncio.run(coro))


def apply_file(c: V3Consumer, proj_rel: str, source: str = "template") -> dict:
    return _run_async(ts.template_apply_file(str(c.proj), file_path=proj_rel, source=source))


def test_unwritten_entry_keeps_stored_hash_when_template_moved(v3_consumer):
    v3_consumer.edit_template("templates/general/AGENT_TEAM.md", append="\nnew line\n")
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    stored = report["manifest"]["files"]["AGENT_TEAM.md"]["hash"]
    assert stored == v3_consumer.old_manifest["files"]["AGENT_TEAM.md"]["hash"]
    assert compute_status(v3_consumer)["files"]["AGENT_TEAM.md"]["status"] == "TEMPLATE_UPDATED"


def test_unwritten_entry_identical_when_template_unchanged(v3_consumer):
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert compute_status(v3_consumer)["files"]["AGENT_TEAM.md"]["status"] == "IDENTICAL"


def test_corrupt_stored_hash_is_preserved_not_repaired(v3_consumer):
    # THE discriminating fixture: carry-forward preserves; re-render would repair.
    v3_consumer.old_manifest["files"]["AGENT_TEAM.md"]["hash"] = "sha256:" + "0" * 64
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"]["AGENT_TEAM.md"]["hash"] == "sha256:" + "0" * 64
    assert compute_status(v3_consumer)["files"]["AGENT_TEAM.md"]["status"] == "LOCAL_EDITED"


def test_deleted_acknowledged_entry_keeps_hash_and_classes_stay_green(v3_consumer):
    v3_consumer.acknowledge_deleted("AGENT_TEAM.md")   # template no longer ships it
    old = v3_consumer.old_manifest["files"]["AGENT_TEAM.md"]["hash"]
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"]["AGENT_TEAM.md"]["hash"] == old
    lines = template_verify_lines(v3_consumer, mode="post_commit")
    assert lines["classes_and_hashes"]["status"] == "PASS", lines["classes_and_hashes"]


def test_once_entry_reason_is_carried_and_reported(v3_consumer):
    v3_consumer.old_manifest["files"]["PROJECT_CONTEXT.md"]["reason"] = "Project-specific config"
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"]["PROJECT_CONTEXT.md"]["reason"] == "Project-specific config"
    assert report["carried_file_keys"]["PROJECT_CONTEXT.md"] == ["reason"]


def test_dry_run_baseline_invariant_holds_and_is_reported(v3_consumer):
    v3_consumer.edit_template("templates/general/AGENT_TEAM.md", append="\nnew line\n")
    preview = migrate_v3_to_v4_dry_run(v3_consumer)
    assert "error" not in preview, preview
    assert preview["baseline_invariant"] == {"ok": True, "violations": []}
    for path, entry in preview["manifest"]["files"].items():
        if path not in preview["will_write"]:
            assert entry.get("hash") == v3_consumer.old_manifest["files"][path].get("hash")


def test_baseline_invariant_red_against_a_rewritten_preview(v3_consumer):
    # The tripwire must be able to fire: feed it a preview that rebuilt one baseline.
    preview = migrate_v3_to_v4_dry_run(v3_consumer)
    assert "error" not in preview, preview
    preview["manifest"]["files"]["AGENT_TEAM.md"]["hash"] = "sha256:" + "f" * 64
    result = v3.check_baseline_invariant(v3_consumer.old_manifest, preview["manifest"], preview["will_write"])
    assert result == {"ok": False, "violations": ["AGENT_TEAM.md"]}


def test_grant_agent_rehashed_on_held_base_reads_identical(v3_consumer):
    v3_consumer.add_tools_to_agent(".claude/agents/coder.md", ["mcp__glider__find_references"])
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["grants_plan"] == {"coder": ["mcp__glider__find_references"]}
    assert compute_status(v3_consumer)["files"][".claude/agents/coder.md"]["status"] == "IDENTICAL"


def test_grant_agent_with_unavailable_base_refuses_and_writes_nothing(v3_consumer):
    v3_consumer.add_tools_to_agent(".claude/agents/coder.md", ["mcp__glider__find_references"])
    v3_consumer.old_manifest["template_commit"] = "0" * 40   # unresolvable
    v3_consumer.old_manifest["template_version"] = None
    v3_consumer.write_manifest()
    before = v3_consumer.snapshot_tree()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" in report and "migration_base unavailable" in report["error"], report
    assert v3_consumer.snapshot_tree() == before


def test_mixed_agent_tools_plus_region_yields_a_grant(v3_consumer):
    # MM-Agent's case: tools addition AND region content in the same agent.
    # NOTE (brief inconsistency, reported in task-1-report.md): the brief's
    # own pseudocode called add_tools_to_agent with
    # ["find_references", "decompile"] but asserted
    # {"coder": ["decompile", "find_references"]} -- the reverse of what
    # `_tools_line_diff`'s documented, order-preserving contract produces
    # (and what `splice_tools` promises: "original order then grant
    # order"). The assertion below matches the call order, not the brief's
    # (self-contradictory) literal text.
    v3_consumer.add_tools_to_agent(
        ".claude/agents/coder.md", ["mcp__glider__find_references", "mcp__glider__decompile"])
    v3_consumer.add_region_content(".claude/agents/coder.md", "Project rule: never filter find_references by kind.\n")
    preview = migrate_v3_to_v4_dry_run(v3_consumer)
    assert "error" not in preview, preview
    assert preview["grants_plan"] == {"coder": ["mcp__glider__find_references", "mcp__glider__decompile"]}


def test_mixed_agent_reapplied_from_template_reads_identical(v3_consumer):
    v3_consumer.add_tools_to_agent(".claude/agents/coder.md", ["mcp__glider__find_references"])
    v3_consumer.add_region_content(".claude/agents/coder.md", "Project rule.\n")
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    res = apply_file(v3_consumer, ".claude/agents/coder.md", source="template")
    assert "error" not in res, res
    assert compute_status(v3_consumer)["files"][".claude/agents/coder.md"]["status"] == "IDENTICAL"


# =============================================================================
# v4.1.1 Task 1, fix round 1: every v4 entry carries its annotations,
# CLAUDE.md included; the two seed entries (project-instructions.md,
# agent-grants.json) never ship a clobberable stale ownership/hash.
# =============================================================================


def test_claude_md_reason_is_carried_and_reported(v3_consumer):
    v3_consumer.old_manifest["files"]["CLAUDE.md"]["reason"] = "kept"
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"]["CLAUDE.md"]["reason"] == "kept"
    assert report["carried_file_keys"]["CLAUDE.md"] == ["reason"]


def test_plain_template_entry_reason_is_carried(v3_consumer):
    v3_consumer.old_manifest["files"]["AGENT_TEAM.md"]["reason"] = "kept"
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"]["AGENT_TEAM.md"]["reason"] == "kept"
    assert report["carried_file_keys"]["AGENT_TEAM.md"] == ["reason"]


def test_grant_agent_reason_is_carried(v3_consumer):
    v3_consumer.add_tools_to_agent(".claude/agents/coder.md", ["mcp__glider__find_references"])
    v3_consumer.old_manifest["files"][".claude/agents/coder.md"]["reason"] = "kept"
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    assert report["manifest"]["files"][".claude/agents/coder.md"]["reason"] == "kept"
    assert report["carried_file_keys"][".claude/agents/coder.md"] == ["reason"]


def test_instructions_seed_entry_ownership_forced_to_once_reason_carried(v3_consumer):
    # A v3 manifest that already (mis-)lists the seed path as template-class
    # with a hash: migration must not let a v4 manifest ship it that way --
    # the next sync would then treat it as template-owned and overwrite the
    # consumer's own project-instructions.md.
    v3_consumer.old_manifest["files"][".claude/project-instructions.md"] = {
        "ownership": "template", "hash": "sha256:" + "a" * 64, "reason": "kept"}
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    entry = report["manifest"]["files"][".claude/project-instructions.md"]
    assert entry["ownership"] == "once"
    assert entry["reason"] == "kept"
    assert "hash" not in entry


def test_agent_grants_seed_entry_ownership_forced_to_once_reason_carried(v3_consumer):
    v3_consumer.old_manifest["files"][".claude/agent-grants.json"] = {
        "ownership": "template", "hash": "sha256:" + "a" * 64, "reason": "kept"}
    v3_consumer.write_manifest()
    report = migrate_v3_to_v4_write(v3_consumer)
    assert "error" not in report, report
    entry = report["manifest"]["files"][".claude/agent-grants.json"]
    assert entry["ownership"] == "once"
    assert entry["reason"] == "kept"
    assert "hash" not in entry
