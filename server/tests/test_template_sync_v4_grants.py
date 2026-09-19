"""agent-grants: loader, UNGRANTABLE_TOOLS, splice_tools, refusal, status
integration (v4.1 plan Task 1 commit 3 -- spec §4, §5).
"""

import asyncio
import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3

AGENT_OWNERSHIP = {
    "tracked_paths": ["templates"],
    "rules": [
        {"pattern": ".claude/agents/*.md", "ownership": "template"},
    ],
}

FOO_TPL = "---\nname: foo\ntools: Read, Write\n---\nbody\n"
FOO_TPL_REGION = (
    "---\nname: foo\ntools: Read, Write\n---\n"
    "body\n"
    "<!-- PROJECT-CUSTOM:BEGIN -->\n"
    "<!-- PROJECT-CUSTOM:END -->\n"
)
BARE_TPL = "---\nname: bare-agent\ndescription: no tools line\n---\nbody\n"


def _mk_v4(tmp_path, template: dict[str, str], project: dict[str, str],
          entries: dict[str, dict], grants: dict | None = None,
          ownership: dict | None = None):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(
        json.dumps(ownership if ownership is not None else AGENT_OWNERSHIP), encoding="utf-8")
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
    if grants is not None:
        (proj / ".claude" / "agent-grants.json").write_text(
            json.dumps(grants), encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 4,
        "template_version": "v4.1.0",
        "template_commit": "0000000",
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": {},
        "requires_server": ">=4.1.0",
        "instructions_file": ".claude/project-instructions.md",
        "agent_grants": ".claude/agent-grants.json",
        "files": entries,
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")
    return repo, proj, manifest


def _rules(repo):
    return v3.load_ownership(str(repo))


def _run(coro):
    return json.loads(asyncio.run(coro))


# --- load_grants --------------------------------------------------------


def test_load_grants_absent_file_returns_empty(tmp_path):
    (tmp_path / ".claude").mkdir()
    assert v3.load_grants(tmp_path) == {}


def test_load_grants_not_json_raises(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text("not json", encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="not valid JSON"):
        v3.load_grants(tmp_path)


def test_load_grants_wrong_schema_raises(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 2, "grants": {}}), encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="schema"):
        v3.load_grants(tmp_path)


def test_load_grants_grants_not_object_raises(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": []}), encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="grants"):
        v3.load_grants(tmp_path)


def test_load_grants_value_not_list_of_strings_raises_naming_agent(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": "not-a-list"}}), encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="foo"):
        v3.load_grants(tmp_path)


def test_load_grants_malformed_token_raises_naming_token(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["not-an-mcp-token"]}}), encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="not-an-mcp-token"):
        v3.load_grants(tmp_path)


def test_load_grants_ungrantable_token_raises_naming_token(tmp_path):
    """A lowercase-alias ungrantable token (the shape check must pass first
    for the UNGRANTABLE_TOOLS check to be reached at all -- see the
    MCP_DOCKER-family concern in the report)."""
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__template-sync-tools__template_verify"]}}),
        encoding="utf-8")
    with pytest.raises(v3.GrantsError, match="template_verify"):
        v3.load_grants(tmp_path)


def test_load_grants_valid_returns_dict(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}),
        encoding="utf-8")
    assert v3.load_grants(tmp_path) == {"foo": ["mcp__glider__symbol_lookup"]}


# --- UNGRANTABLE_TOOLS ----------------------------------------------------
#
# Scoping note (advisor review point 5): a LITERAL "union of every shipped
# agent's withheld set, where withheld = the tools a sibling agent has that
# it lacks" is unsatisfiable -- pairwise agent tools: diffs cover roughly
# every tool that is not in every agent's list (hundreds of tokens), never
# subseteq a small hand-written frozenset (measured: templates/general's own
# coder.md already carries mcp__MCP_DOCKER__merge_pull_request /
# create_pull_request in ITS OWN tools: line, which a literal sibling-diff
# would then have to explain away rather than assert against). Scoped
# instead, per that guidance, to the three families spec §4 actually names:
# every registered template_* sync tool (measured against the LIVE
# _registered_tool_names() registry, not a hardcoded list), the four
# merge/PR tokens, and Agent.


def test_ungrantable_tools_covers_every_registered_template_tool():
    registered = {n for n in ts._registered_tool_names() if n.startswith("template_")}
    assert registered, "sanity: the live registry must expose template_* tools"
    tokens = {f"mcp__template-sync-tools__{n}" for n in registered}
    assert tokens <= v3.UNGRANTABLE_TOOLS, tokens - v3.UNGRANTABLE_TOOLS


def test_ungrantable_tools_covers_the_merge_pr_family_and_agent():
    merge_pr_family = {
        "mcp__MCP_DOCKER__merge_pull_request",
        "mcp__github-tools__github_pr_auto_merge",
        "mcp__MCP_DOCKER__create_pull_request",
        "mcp__MCP_DOCKER__update_pull_request",
    }
    assert merge_pr_family <= v3.UNGRANTABLE_TOOLS
    assert "Agent" in v3.UNGRANTABLE_TOOLS


# --- splice_tools ----------------------------------------------------------


def test_splice_tools_appends_dedup_original_then_grant_order():
    out = v3.splice_tools(FOO_TPL, ["mcp__glider__symbol_lookup", "Read"])
    assert "tools: Read, Write, mcp__glider__symbol_lookup" in out
    assert out.count("tools:") == 1


def test_splice_tools_no_grants_is_noop():
    assert v3.splice_tools(FOO_TPL, []) == FOO_TPL


def test_splice_tools_no_tools_line_refused_by_name():
    with pytest.raises(v3.GrantRefused) as exc:
        v3.splice_tools(BARE_TPL, ["mcp__glider__symbol_lookup"])
    assert exc.value.agent_name == "bare-agent"
    assert "bare-agent" in str(exc.value)
    assert "already inherits every tool" in str(exc.value)


def test_splice_tools_list_form_refused():
    text = "---\nname: foo\ntools:\n  - Read\n  - Write\n---\nbody\n"
    with pytest.raises(v3.GrantsError, match="unsupported tools:"):
        v3.splice_tools(text, ["mcp__glider__symbol_lookup"])


def test_splice_tools_wildcard_refused():
    text = "---\nname: foo\ntools: *\n---\nbody\n"
    with pytest.raises(v3.GrantsError, match="unsupported tools:"):
        v3.splice_tools(text, ["mcp__glider__symbol_lookup"])


# --- apply + status integration witnesses (spec §5, the four + writer) -----


def test_apply_then_status_identical_and_stable_on_second_call(tmp_path):
    """Witnesses 1-2: apply -> IDENTICAL; a second status call with nothing
    changed -> still IDENTICAL."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    rules = _rules(repo)
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    assert "error" not in res, res
    assert "mcp__glider__symbol_lookup" in (proj / ".claude" / "agents" / "foo.md").read_text(encoding="utf-8")
    manifest["files"][".claude/agents/foo.md"] = res["manifest_entry"]

    status1 = v3.compute_status_v3(proj, manifest, rules)
    assert status1["files"][".claude/agents/foo.md"]["status"] == "IDENTICAL"
    status2 = v3.compute_status_v3(proj, manifest, rules)
    assert status2["files"][".claude/agents/foo.md"]["status"] == "IDENTICAL"


def test_template_updated_appears_only_after_a_grants_edit(tmp_path):
    """Witness 3: TEMPLATE_UPDATED must NOT be present before the grants
    edit (asserted explicitly, not just "appears after")."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {}})
    rules = _rules(repo)
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    manifest["files"][".claude/agents/foo.md"] = res["manifest_entry"]

    before = v3.compute_status_v3(proj, manifest, rules)
    assert before["files"][".claude/agents/foo.md"]["status"] != "TEMPLATE_UPDATED"
    assert before["files"][".claude/agents/foo.md"]["status"] == "IDENTICAL"

    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}),
        encoding="utf-8", newline="")
    after = v3.compute_status_v3(proj, manifest, rules)
    assert after["files"][".claude/agents/foo.md"]["status"] == "TEMPLATE_UPDATED"


def test_grants_and_region_prose_together_are_identical(tmp_path):
    """Witness 4 (first half): grants AND consumer prose inside the agent's
    PROJECT-CUSTOM region -> IDENTICAL (the region-aware status, H1 --
    the agent's own region prose is tolerated exactly as it is under v3)."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL_REGION}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    rules = _rules(repo)
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    manifest["files"][".claude/agents/foo.md"] = res["manifest_entry"]

    agent_path = proj / ".claude" / "agents" / "foo.md"
    content = agent_path.read_text(encoding="utf-8").replace(
        "<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n",
        "<!-- PROJECT-CUSTOM:BEGIN -->\nMY RULE\n<!-- PROJECT-CUSTOM:END -->\n")
    agent_path.write_text(content, encoding="utf-8", newline="")

    status = v3.compute_status_v3(proj, manifest, rules)
    info = status["files"][".claude/agents/foo.md"]
    assert info["status"] == "IDENTICAL", info
    assert info.get("region_only") is True


def test_grants_agent_with_template_part_edit_is_local_edited_diff_isolated(tmp_path):
    """Witness 4 (second half, adjusted -- see report): the SAME shape (grants
    present) with a one-line edit CONFINED to the template part (no region
    markers in play here, so nothing else can leak into the diff) ->
    LOCAL_EDITED whose local_diff contains only that line. (Measured: when a
    region ALSO carries consumer prose at the same time as a template-part
    edit, the existing region-aware code -- unchanged per H1, "no new
    comparison code" -- falls through to the FULL-file diff, which then also
    shows the region insertion; that combined scenario does not isolate to
    one line with today's code, so this witness exercises the two
    conditions -- region-tolerant IDENTICAL, and diff-isolated LOCAL_EDITED
    -- as the two independent cases the design actually produces, rather
    than asserting they compose losslessly, which the RED run below shows
    they do not.)"""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    rules = _rules(repo)
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    manifest["files"][".claude/agents/foo.md"] = res["manifest_entry"]

    agent_path = proj / ".claude" / "agents" / "foo.md"
    agent_path.write_text(
        agent_path.read_text(encoding="utf-8").replace("body\n", "body edited\n", 1),
        encoding="utf-8", newline="")

    status = v3.compute_status_v3(proj, manifest, rules)
    info = status["files"][".claude/agents/foo.md"]
    assert info["status"] == "LOCAL_EDITED", info
    diff_lines = [l for l in info["local_diff"].splitlines()
                  if l.startswith(("+", "-")) and not l.startswith(("+++", "---"))]
    assert diff_lines == ["-body", "+body edited"], diff_lines
    # The spliced grant appears only as unchanged CONTEXT in the diff (it is
    # not itself a +/- line -- diff_lines above already proves isolation).
    assert "mcp__glider__symbol_lookup" in info["local_diff"]


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _git_out(repo, *args) -> str:
    return subprocess.run(["git", *args], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def test_resolve_base_is_spliced_so_a_moved_on_template_still_reads_updated(tmp_path):
    """H1's called-out failure mode: an UN-spliced base_provider would make
    the held (synced) revision's part disagree with the spliced project part
    on the tools: line alone, so a consumer who has done nothing wrong would
    read LOCAL_EDITED forever instead of TEMPLATE_UPDATED. This is the
    variant the plan's commit-3 witness asks for: "add a variant where the
    template moved on so the base path runs" (resolve_base's base_provider,
    inside region_status)."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL_REGION}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "v1")
    v1_commit = _git_out(repo, "rev-parse", "HEAD")
    _git(repo, "tag", "v4.1.0")

    rules = _rules(repo)
    manifest["template_commit"] = v1_commit
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    manifest["files"][".claude/agents/foo.md"] = res["manifest_entry"]

    # Consumer adds region prose (kept, project-owned).
    agent_path = proj / ".claude" / "agents" / "foo.md"
    agent_path.write_text(
        agent_path.read_text(encoding="utf-8").replace(
            "<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n",
            "<!-- PROJECT-CUSTOM:BEGIN -->\nMY RULE\n<!-- PROJECT-CUSTOM:END -->\n"),
        encoding="utf-8", newline="")

    # The template moves on: the TEMPLATE part changes (not the consumer's
    # doing) -- consumer has not re-synced.
    tpl_path = ts._template_file_path({"templateRepo": str(repo), "variant": "general"},
                                      ".claude/agents/foo.md")
    tpl_path.write_text(FOO_TPL_REGION.replace("body\n", "body v2\n", 1), encoding="utf-8", newline="")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "template moves on")

    status = v3.compute_status_v3(proj, manifest, rules)
    info = status["files"][".claude/agents/foo.md"]
    assert info["status"] == "TEMPLATE_UPDATED", info
    assert "local_diff" not in info or not info["local_diff"]


def test_writer_witness_finalize_hash_matches_on_disk_spliced_bytes(tmp_path):
    """Witness 5 (H2, the writer): after apply + finalize_v3, the manifest
    entry's hash equals sha256 of the ON-DISK file's spliced content --
    asserted against the file BYTES, never against template_content()'s
    return value (the case witnesses 1-4 cannot see: a baseline computed
    un-spliced while apply writes spliced would still pass those)."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    rules = _rules(repo)
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    assert "error" not in res, res

    fin = _run(ts.template_finalize_sync(
        str(proj), applied_files=json.dumps([res]), new_files="[]",
        deleted_files="[]", acknowledged_deleted="[]"))
    assert "error" not in fin, fin

    written = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    entry_hash = v3.parse_hash(written["files"][".claude/agents/foo.md"]["hash"])

    on_disk_bytes = (proj / ".claude" / "agents" / "foo.md").read_bytes()
    assert entry_hash == ts._sha256(on_disk_bytes.decode("utf-8"))
    assert entry_hash != ts._sha256(FOO_TPL), "must not be the un-spliced template's hash"

    # Fix round 1, F2-c3: witness 5 only exercised the APPLIED path, where
    # finalize_v3 ECHOES the hash apply already computed -- the NEW-FILE
    # branch (`for fp in new:`, v3.py ~1540-1559) computes its OWN baseline
    # via a separate template_content() call and was unreached by any
    # witness. Extend with a second agent, applied to disk (spliced) but
    # registered through `new_files` instead of `applied_files`, so THIS
    # call goes through the new-file branch specifically.
    bar_tpl = "---\nname: bar\ntools: Read\n---\nbody\n"
    (ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, ".claude/agents/bar.md")
     ).write_text(bar_tpl, encoding="utf-8", newline="")
    grants_path = proj / ".claude" / "agent-grants.json"
    grants_path.write_text(
        json.dumps({"schema": 1, "grants": {
            "foo": ["mcp__glider__symbol_lookup"], "bar": ["mcp__glider__decompile"]}}),
        encoding="utf-8", newline="")
    bar_res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/bar.md", source="template"))
    assert "error" not in bar_res, bar_res

    fin2 = _run(ts.template_finalize_sync(
        str(proj), applied_files="[]", new_files=json.dumps([".claude/agents/bar.md"]),
        deleted_files="[]", acknowledged_deleted="[]"))
    assert "error" not in fin2, fin2

    written2 = json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))
    bar_entry_hash = v3.parse_hash(written2["files"][".claude/agents/bar.md"]["hash"])
    bar_on_disk = (proj / ".claude" / "agents" / "bar.md").read_bytes()
    assert bar_entry_hash == ts._sha256(bar_on_disk.decode("utf-8"))
    assert "mcp__glider__decompile" in bar_on_disk.decode("utf-8")
    assert bar_entry_hash != ts._sha256(bar_tpl), "must not be the un-spliced template's hash"


# --- refusals ----------------------------------------------------------


def test_apply_refuses_grant_for_agent_with_no_tools_line_by_name(tmp_path):
    """R-E: no shipped agent lacks a tools: line, so the fixture ships one
    that does -- file untouched, status unchanged (nothing written)."""
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/bare-agent.md": BARE_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {"bare-agent": ["mcp__glider__symbol_lookup"]}})
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/bare-agent.md", source="template"))
    assert "error" in res, res
    assert "bare-agent" in res["error"]
    assert "already inherits every tool" in res["error"]
    assert not (proj / ".claude" / "agents" / "bare-agent.md").exists()


def test_apply_refuses_list_form_tools(tmp_path):
    list_form_tpl = "---\nname: foo\ntools:\n  - Read\n  - Write\n---\nbody\n"
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": list_form_tpl}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}})
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    assert "error" in res, res
    assert "unsupported tools:" in res["error"]
    assert not (proj / ".claude" / "agents" / "foo.md").exists()


def test_apply_refuses_ungrantable_token_by_name(tmp_path):
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL}, project={}, entries={},
        grants={"schema": 1, "grants": {"foo": ["mcp__template-sync-tools__template_verify"]}})
    res = _run(ts.template_apply_file(str(proj), file_path=".claude/agents/foo.md", source="template"))
    assert "error" in res, res
    assert "template_verify" in res["error"]
    assert not (proj / ".claude" / "agents" / "foo.md").exists()


def test_compute_status_returns_error_on_malformed_grants_rather_than_crash(tmp_path):
    repo, proj, manifest = _mk_v4(
        tmp_path, template={".claude/agents/foo.md": FOO_TPL},
        project={".claude/agents/foo.md": FOO_TPL}, entries={
            ".claude/agents/foo.md": {"hash": "sha256:" + ts._sha256(FOO_TPL), "ownership": "template"}},
        grants={"schema": 1, "grants": {"foo": ["not-an-mcp-token"]}})
    rules = _rules(repo)
    status = v3.compute_status_v3(proj, manifest, rules)
    assert "error" in status, status
    assert "not-an-mcp-token" in status["error"]
