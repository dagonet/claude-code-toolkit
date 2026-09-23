"""template_verify: consumer consistency check (v4.0.1, item 22).

Each FAIL-capable line (`verify.LINES`, kind FAIL_LINE) gets one fixture that
breaks EXACTLY that condition, built by mutating one thing on top of a shared
"good" (fully-synced, committed) fixture -- chosen so the mutation cannot
cascade into a second line: a template-class file's CONTENT is never touched
by a mutation aimed at a different line (that would also flip status_clean
and classes_and_hashes together, since both read the same IDENTICAL/entry-
hash state), and every proj-side mutation is followed by a commit so the
mutation itself does not also trip tree_clean.
"""

import asyncio
import json
import pathlib
import shutil
import subprocess
import time

import pytest

from template_sync import mcp as ts
from template_sync import v3
from template_sync import verify

# server/tests/test_x.py -> parents[0]=tests, [1]=server, [2]=toolkit root
# (same convention as test_template_sync_docstring_contract.py's ROOT).
TOOLKIT_ROOT = pathlib.Path(__file__).resolve().parents[2]

OWNERSHIP = {
    "tracked_paths": ["hooks", "templates"],
    "rules": [
        {"pattern": "hooks/**", "ownership": "template"},
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/rules/project.md", "ownership": "once"},
        {
            "pattern": "PROJECT_CONTEXT.md", "ownership": "once", "audit": "keys",
            "required_keys": ["Protected branches", "Gate"],
        },
    ],
}

# v4.1, ruling R-J: this fixture models a v4.0.x TOOLKIT CHECKOUT -- its
# template CLAUDE.md carries the PROJECT-CUSTOM markers, matching every
# pre-v4.1 template. WITHOUT them, this fixture's v3 manifest would silently
# fall into the v3-manifest window the moment the window predicate lands
# (commit 4): CLAUDE.md would read MIGRATION_REQUIRED and status_clean would
# FAIL -- the "fix" an implementer would reach for there is weakening this
# suite's assertions, which is exactly the failure mode the markers below
# are here to prevent from looking like success.
CLAUDE_CONTENT = "# T\nrule one\n<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n"
HOOK_CONTENT = "echo g\n"

# V401_SEED: the pre-v4.0.2 `PROJECT_MD_SEED_BODY` text, captured verbatim
# HERE (not read off the constant) so the "predates v4.0.2" arm of
# test_project_md_lines actually exercises the old shape rather than
# silently tracking whatever the constant says today.
V401_SEED = (
    "This file has no `paths:` key, so Claude Code loads it at EVERY session start,\n"
    "at the same priority as CLAUDE.md. Anything you write here is always on.\n"
    "\n"
    "To scope it to files instead, add a frontmatter block at the very top:\n"
    "\n"
    "    ---\n"
    "    paths:\n"
    "      - \"src/**/*.py\"\n"
    "      - \"pyproject.toml\"\n"
    "    ---\n"
    "\n"
    "Always-on project rules belong in CLAUDE.md's PROJECT-CUSTOM region, not here;\n"
    "a rule in both places exists twice and drifts."
)
# V401_SEED_NO_MARKER: V401_SEED's shape (predates v4.0.2 -- no next-session
# sentence) WITHOUT a PROJECT-CUSTOM reference, so it exercises the
# "predates v4.0.2" arm in isolation. v4.1.1 (spec §2.1) inserts a NEW
# harm-keyed arm BEFORE the "predates"/"delivered to nobody" arms, and
# V401_SEED itself names PROJECT-CUSTOM -- it now correctly routes to that
# new arm first (see test_seed_current_flags_project_custom_reference and
# the "project_custom" case of test_project_md_lines below), so a body that
# still wants to exercise "predates" alone must not carry the marker.
V401_SEED_NO_MARKER = V401_SEED.replace(
    "Always-on project rules belong in CLAUDE.md's PROJECT-CUSTOM region, not here;",
    "Always-on project rules belong in the project instructions file, not here;")
# V402_SEED: read from the constant (v4.0.2, item 12) so it can never drift
# from what verify.py's project_md_seed_current actually checks against.
V402_SEED = v3.PROJECT_MD_SEED_BODY

# The v4.0.2 seed (so the good fixture stays INFO-clean: the "current" arm,
# never "predates").
PROJECT_MD_CONTENT = "# Project instructions\n\n" + V402_SEED + "\n"
CONTEXT_CONTENT = "- **Protected branches**: main\n- **Gate**: bash scripts/gate.sh\n"


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


def _recommit(d, msg="update"):
    _git(d, "add", "-A")
    _git(d, "commit", "-q", "-m", msg)


def _write_manifest(proj, manifest: dict):
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="")


def _read_manifest(proj) -> dict:
    return json.loads((proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8"))


def _good_fixture(tmp_path, ownership: dict | None = None):
    """A fully-synced, git-committed v3 project against a git-committed
    toolkit repo. Every FAIL-capable line is expected PASS (server_skew
    SKIPs: this repo is not the running server's own source tree)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(
        json.dumps(ownership if ownership is not None else OWNERSHIP), encoding="utf-8")
    m = {"templateRepo": str(repo), "variant": "general"}
    for rel, content in {"CLAUDE.md": CLAUDE_CONTENT, "hooks/g.sh": HOOK_CONTENT,
                         "PROJECT_CONTEXT.md": CONTEXT_CONTENT,
                         ".claude/rules/project.md": PROJECT_MD_CONTENT}.items():
        p = ts._template_file_path(m, rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    commit = _init_repo(repo)
    _git(repo, "tag", "v3.1.0")

    proj = tmp_path / "proj"
    (proj / ".claude" / "rules").mkdir(parents=True)
    (proj / "hooks").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(CLAUDE_CONTENT, encoding="utf-8", newline="")
    (proj / "hooks" / "g.sh").write_text(HOOK_CONTENT, encoding="utf-8", newline="")
    (proj / ".claude" / "rules" / "project.md").write_text(PROJECT_MD_CONTENT, encoding="utf-8", newline="")
    (proj / "PROJECT_CONTEXT.md").write_text(CONTEXT_CONTENT, encoding="utf-8", newline="")

    entries = {
        "CLAUDE.md": {"hash": "sha256:" + ts._sha256(CLAUDE_CONTENT), "ownership": "template"},
        "hooks/g.sh": {"hash": "sha256:" + ts._sha256(HOOK_CONTENT), "ownership": "template"},
        ".claude/rules/project.md": {"ownership": "once"},
        "PROJECT_CONTEXT.md": {"ownership": "once"},
    }
    manifest = {
        "manifest_version": 3,
        "template_version": "v3.1.0",
        "template_commit": commit,
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": {},
        "requires_server": ">=0.3.2",
        "files": entries,
    }
    _write_manifest(proj, manifest)
    _init_repo(proj)
    return repo, proj, commit


# --- v4.1: a green v4 fixture, and a v3-window fixture (spec §6, §7; R-J/R-K)

CLAUDE_CONTENT_V4 = "# T\nrule one\n@.claude/project-instructions.md\n"
# R-H: the agent KEEPS its PROJECT-CUSTOM region under v4 -- only CLAUDE.md's
# is removed.
AGENT_CONTENT_V4 = ("---\nname: foo\ntools: Read, Write\n---\n"
                    "body\n<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n")
INSTRUCTIONS_CONTENT_V4 = "# Project instructions\n\nSeed body\n"
GRANTS_CONTENT_V4 = json.dumps({"schema": 1, "grants": {}}) + "\n"

OWNERSHIP_V4 = {
    "tracked_paths": ["hooks", "templates"],
    "rules": [
        {"pattern": "hooks/**", "ownership": "template"},
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/agents/*.md", "ownership": "template"},
        {"pattern": ".claude/rules/project.md", "ownership": "once"},
        {"pattern": ".claude/project-instructions.md", "ownership": "once"},
        {"pattern": ".claude/agent-grants.json", "ownership": "once"},
        {
            "pattern": "PROJECT_CONTEXT.md", "ownership": "once", "audit": "keys",
            "required_keys": ["Protected branches", "Gate"],
        },
    ],
}


def _good_fixture_v4(tmp_path):
    """A fully-synced, git-committed v4 project against a git-committed
    toolkit repo. Every FAIL-capable line is expected PASS except
    server_skew (R-H: region_markers PASSes here too -- it keeps measuring
    the agent's region; import_line_present PASSes, not SKIPs, since this is
    v4)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general" / ".claude" / "agents").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP_V4), encoding="utf-8")
    m = {"templateRepo": str(repo), "variant": "general"}
    template_files = {
        "CLAUDE.md": CLAUDE_CONTENT_V4, "hooks/g.sh": HOOK_CONTENT,
        "PROJECT_CONTEXT.md": CONTEXT_CONTENT, ".claude/rules/project.md": PROJECT_MD_CONTENT,
        ".claude/agents/foo.md": AGENT_CONTENT_V4,
        ".claude/project-instructions.md": INSTRUCTIONS_CONTENT_V4,
        ".claude/agent-grants.json": GRANTS_CONTENT_V4,
    }
    for rel, content in template_files.items():
        p = ts._template_file_path(m, rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    commit = _init_repo(repo)
    _git(repo, "tag", "v4.1.0")

    proj = tmp_path / "proj"
    (proj / ".claude" / "rules").mkdir(parents=True)
    (proj / ".claude" / "agents").mkdir(parents=True)
    (proj / "hooks").mkdir(parents=True)
    for rel, content in template_files.items():
        (proj / rel).write_text(content, encoding="utf-8", newline="")

    entries = {
        "CLAUDE.md": {"hash": "sha256:" + ts._sha256(CLAUDE_CONTENT_V4), "ownership": "template"},
        "hooks/g.sh": {"hash": "sha256:" + ts._sha256(HOOK_CONTENT), "ownership": "template"},
        ".claude/agents/foo.md": {"hash": "sha256:" + ts._sha256(AGENT_CONTENT_V4), "ownership": "template"},
        ".claude/rules/project.md": {"ownership": "once"},
        "PROJECT_CONTEXT.md": {"ownership": "once"},
        ".claude/project-instructions.md": {"ownership": "once"},
        ".claude/agent-grants.json": {"ownership": "once"},
    }
    manifest = {
        "manifest_version": 4,
        "template_version": "v4.1.0",
        "template_commit": commit,
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": {},
        "requires_server": ">=4.1.0",
        "instructions_file": ".claude/project-instructions.md",
        "agent_grants": ".claude/agent-grants.json",
        "files": entries,
    }
    _write_manifest(proj, manifest)
    _init_repo(proj)
    return repo, proj, commit


def _window_fixture(tmp_path):
    """A v3 manifest whose CURRENT checkout's template has ALREADY dropped
    the region (the v3-manifest window, R-J): CLAUDE.md reads
    MIGRATION_REQUIRED and status_clean is the ONE FAIL (R-K)."""
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    window_claude = "# T\nrule one\n@.claude/project-instructions.md\n"  # no markers -- v4.1+ shape
    m = {"templateRepo": str(repo), "variant": "general"}
    for rel, content in {"CLAUDE.md": window_claude, "hooks/g.sh": HOOK_CONTENT,
                         "PROJECT_CONTEXT.md": CONTEXT_CONTENT,
                         ".claude/rules/project.md": PROJECT_MD_CONTENT}.items():
        p = ts._template_file_path(m, rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
    commit = _init_repo(repo)

    proj = tmp_path / "proj"
    (proj / ".claude" / "rules").mkdir(parents=True)
    (proj / "hooks").mkdir(parents=True)
    # The project's HELD CLAUDE.md always carries the region (R-J: a v3
    # consumer's own committed copy always has it).
    (proj / "CLAUDE.md").write_text(CLAUDE_CONTENT, encoding="utf-8", newline="")
    (proj / "hooks" / "g.sh").write_text(HOOK_CONTENT, encoding="utf-8", newline="")
    (proj / ".claude" / "rules" / "project.md").write_text(PROJECT_MD_CONTENT, encoding="utf-8", newline="")
    (proj / "PROJECT_CONTEXT.md").write_text(CONTEXT_CONTENT, encoding="utf-8", newline="")

    entries = {
        "CLAUDE.md": {"hash": "sha256:" + ts._sha256(CLAUDE_CONTENT), "ownership": "template"},
        "hooks/g.sh": {"hash": "sha256:" + ts._sha256(HOOK_CONTENT), "ownership": "template"},
        ".claude/rules/project.md": {"ownership": "once"},
        "PROJECT_CONTEXT.md": {"ownership": "once"},
    }
    manifest = {
        "manifest_version": 3,
        "template_version": "v3.1.0",
        "template_commit": commit,
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": {},
        "requires_server": ">=0.3.2",
        "files": entries,
    }
    _write_manifest(proj, manifest)
    _init_repo(proj)
    return repo, proj, commit


def _only_fail(res: dict) -> list[str]:
    return [l["id"] for l in res["lines"] if l["status"] == "FAIL"]


def _by_id(res: dict) -> dict:
    return {l["id"]: l for l in res["lines"]}


def _acknowledged_fixture(tmp_path):
    """MM-Agent's shape: a template-class file the template no longer ships,
    kept by the project and acknowledged by hand (SKILL.md step 6)."""
    repo, proj, commit = _good_fixture(tmp_path)
    tpl_hook = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, "hooks/g.sh")
    tpl_hook.unlink()
    _recommit(repo, "template drops hooks/g.sh")
    m = _read_manifest(proj)
    m["deletedAcknowledged"] = ["hooks/g.sh"]
    _write_manifest(proj, m)
    _recommit(proj, "acknowledge kept hook")
    return repo, proj


def test_acknowledged_kept_file_is_not_a_fail(tmp_path):
    repo, proj = _acknowledged_fixture(tmp_path)
    res = verify.run(str(proj), str(repo), "post_commit")
    by = _by_id(res)
    assert by["unknown_keys_empty"]["status"] == "PASS", by["unknown_keys_empty"]
    assert by["classes_and_hashes"]["status"] == "PASS", by["classes_and_hashes"]
    assert "acknowledged_kept=1" in by["classes_and_hashes"]["measured"]


# --- PASS fixture + mode switch ---------------------------------------------


def test_pass_fixture_is_all_green(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    res = verify.run(str(proj), str(repo), "post_commit")
    lines = res["lines"]
    assert len(lines) == len(verify.LINES)
    ids_in_order = [l["id"] for l in lines]
    assert ids_in_order == [i for i, _k in verify.LINES]

    skip_ids = {l["id"] for l in lines if l["status"] == "SKIP"}
    info_ids = {l["id"] for l in lines if l["status"] == "INFO"}
    fail_ids = {l["id"] for l in lines if l["status"] == "FAIL"}
    assert fail_ids == set()
    # server_skew SKIPs: this fixture's "toolkit" repo is not the tree the
    # running server process was imported from. v4.1 (R-K): this fixture is
    # the v3 LEGACY situation (a v3 manifest, template still carrying the
    # region) -- the three CLAUDE.md-related lines SKIP "no import yet".
    assert skip_ids == {"server_skew", "claude_md_identical", "import_line_present",
                        "instructions_file_present"}
    # v4.0.2 extends this to six: the three new INFO lines (legacy_gate_dir,
    # once_notes_changed, project_md_scoped_consistent) all emit their null
    # case on this healthy fixture -- none may SKIP here (a SKIP would be a
    # defect in the line, not grounds to widen this set).
    # v4.1.1 (spec §2.1) adds a seventh: project_md_seed_differs, a fact-only
    # INFO line that reads "matches" on this fixture (the project and
    # template copies of project.md are byte-identical, PROJECT_MD_CONTENT).
    assert info_ids == {"template_behind_head", "encoding_drift", "project_md_seed_current",
                        "project_md_seed_differs",
                        "legacy_gate_dir", "once_notes_changed", "project_md_scoped_consistent"}

    n_pass = len(verify.LINES) - len(skip_ids) - len(info_ids) - len(fail_ids)
    assert res["summary"] == f"{n_pass} PASS, 0 FAIL, {len(skip_ids)} SKIP, {len(info_ids)} INFO"
    assert res["ok"] is True
    assert res["mode"] == "post_commit"


def test_lines_count_is_31():
    """Constraint 5: stated by hand, moves in the SAME commit as the ids it
    counts -- never derived from anything, so it is a red flag by itself if a
    later edit changes LINES without touching this number. 30 -> 31 in
    v4.1.1 (spec §2.1): project_md_seed_differs."""
    assert len(verify.LINES) == 31


def test_v4_fixture_is_all_green(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo, proj, commit = _good_fixture_v4(tmp_path)
    res = verify.run(str(proj), str(repo), "post_commit")
    lines = res["lines"]
    assert len(lines) == len(verify.LINES)

    skip_ids = {l["id"] for l in lines if l["status"] == "SKIP"}
    info_ids = {l["id"] for l in lines if l["status"] == "INFO"}
    fail_ids = {l["id"] for l in lines if l["status"] == "FAIL"}
    assert fail_ids == set(), _by_id(res)
    # R-H: region_markers PASSes here (it keeps measuring the agent's own
    # region); import_line_present PASSes, not SKIPs, since this IS v4.
    assert skip_ids == {"server_skew"}
    # All six v4.1 new ids are FAIL_LINE kind (never INFO_LINE), so info_ids
    # is unchanged from the v3 fixture's set, plus v4.1.1's
    # project_md_seed_differs (also fact-only INFO here: this fixture's
    # project and template copies of project.md are byte-identical).
    assert info_ids == {"template_behind_head", "encoding_drift", "project_md_seed_current",
                        "project_md_seed_differs",
                        "legacy_gate_dir", "once_notes_changed", "project_md_scoped_consistent"}
    by_id = _by_id(res)
    assert by_id["claude_md_identical"]["status"] == "PASS"
    assert by_id["import_line_present"]["status"] == "PASS"
    assert by_id["instructions_file_present"]["status"] == "PASS"
    assert by_id["agent_grants_resolvable"]["status"] == "PASS"
    assert "no grants file" not in by_id["agent_grants_resolvable"]["measured"]  # the file IS present
    assert "grants=0" in by_id["agent_grants_resolvable"]["measured"]
    assert by_id["agent_grants_names_known"]["status"] == "PASS"
    assert by_id["agent_grants_extendable"]["status"] == "PASS"
    assert res["ok"] is True


def test_agent_grants_resolvable_fails_on_nonexistent_template_sync_tool(tmp_path, monkeypatch):
    """The one alias `agent_grants_resolvable` can resolve FOR REAL: a
    `template-sync-tools` token naming a tool that is not in the live
    registry FAILs. (Every REAL template_* tool is itself in
    UNGRANTABLE_TOOLS, so a fake name is the only way to exercise this
    alias's resolution path at all without tripping the earlier
    ungrantable-token refusal in load_grants -- noted in the report.)"""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo, proj, commit = _good_fixture_v4(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__template-sync-tools__template_nonexistent"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    assert line["status"] == "FAIL", line
    assert "template_nonexistent" in line["measured"]


def test_agent_grants_resolvable_skips_without_registration_for_third_party_alias(tmp_path, monkeypatch):
    """R-N (fix round 1): "glider" is neither `template-sync-tools` nor a
    mcp-dev-servers-family alias -- there is no census route for it at all,
    so this SKIPs naming the alias, regardless of ~/.claude.json."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    monkeypatch.setattr(pathlib.Path, "home", lambda: tmp_path / "no-such-home")
    repo, proj, commit = _good_fixture_v4(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    assert line["status"] == "SKIP", line
    assert "alias glider: no census route" in line["measured"]


def test_agent_grants_resolvable_never_passes_an_unresolved_alias_even_with_registration(tmp_path, monkeypatch):
    """R-N, INVERTING the c5b witness this replaces
    (`test_agent_grants_resolvable_counts_unresolved_by_name_when_registration_readable`,
    fix round 1 task-1-fix1-brief.md): that test asserted PASS-by-name for a
    third-party alias merely because ~/.claude.json was READABLE -- R-N
    rules that a FALSE GREEN (the alias still has no real census route: it
    is not registered in THIS fake ~/.claude.json, and "glider" is not in
    the mcp-dev-servers family regardless). The corrected behaviour is
    SKIP, naming the alias, whether or not the registration file exists."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    fake_home = tmp_path / "fake-home"
    fake_home.mkdir()
    (fake_home / ".claude.json").write_text(json.dumps({"mcpServers": {}}), encoding="utf-8")
    monkeypatch.setattr(pathlib.Path, "home", lambda: fake_home)
    repo, proj, commit = _good_fixture_v4(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    assert line["status"] == "SKIP", line
    assert "alias glider: no census route" in line["measured"]


def _mk_mcp_dev_servers_family_registration(tmp_path, alias: str, tool_names: list[str]):
    """A REAL census route for `alias` (R-N): a fake ~/.claude.json
    registering it with a `.venv/Scripts/...` command path (check 50's own
    derivation marker), a fake mcp-dev-servers source tree at the derived
    directory shipping a module with `FastMCP("<alias>")` and one
    `@mcp.tool()`-decorated function per name in `tool_names` (the STATIC
    census route -- no real venv/import needed, matching how check 50
    itself falls back when a registered alias has no live venv). Returns
    (fake_home, mcp_dev_servers_dir)."""
    fake_home = tmp_path / "fake-home"
    fake_home.mkdir()
    mcp_dev_servers_dir = tmp_path / "mcp-dev-servers"
    pkg_dir = mcp_dev_servers_dir / "src" / "mcp_dev_servers"
    pkg_dir.mkdir(parents=True)
    body = "\n".join(f"@mcp.tool()\ndef {name}(x):\n    return x\n" for name in tool_names)
    (pkg_dir / f"{alias.replace('-', '_')}.py").write_text(
        f'FastMCP("{alias}")\n\n{body}', encoding="utf-8", newline="")
    fake_venv_command = str(mcp_dev_servers_dir / ".venv" / "Scripts" / f"mcp-{alias}.exe")
    (fake_home / ".claude.json").write_text(
        json.dumps({"mcpServers": {alias: {"command": fake_venv_command}}}), encoding="utf-8")
    return fake_home, mcp_dev_servers_dir


def _mk_v4_toolkit_repo_with_list_mcp_tools(tmp_path):
    """A _good_fixture_v4 toolkit repo that also ships a REAL copy of
    scripts/lib/list-mcp-tools.py at the SAME repo-relative path -- R-N's
    census subprocess resolves the script from the manifest's own
    templateRepo, so the fixture toolkit repo needs it too."""
    repo, proj, commit = _good_fixture_v4(tmp_path)
    lib_dir = repo / "scripts" / "lib"
    lib_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy(TOOLKIT_ROOT / "scripts" / "lib" / "list-mcp-tools.py", lib_dir / "list-mcp-tools.py")
    return repo, proj, commit


def test_agent_grants_resolvable_real_census_fails_on_a_nonexistent_family_tool(tmp_path, monkeypatch):
    """R-N: a REAL census route (the mcp-dev-servers family) resolves for
    real -- a token naming a tool absent from the (statically-censused)
    module FAILs by name, proving actual resolution happened rather than a
    generic SKIP."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    fake_home, _mds_dir = _mk_mcp_dev_servers_family_registration(tmp_path, "git-tools", ["git_status"])
    monkeypatch.setattr(pathlib.Path, "home", lambda: fake_home)
    repo, proj, commit = _mk_v4_toolkit_repo_with_list_mcp_tools(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {
            "foo": ["mcp__git-tools__git_status", "mcp__git-tools__git_nonexistent"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    assert line["status"] == "FAIL", line
    assert "mcp__git-tools__git_nonexistent" in line["measured"]
    assert "mcp__git-tools__git_status" not in line["measured"], \
        "the real token must not be named alongside the missing one"


def test_agent_grants_resolvable_real_census_passes_when_every_token_resolves(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    fake_home, _mds_dir = _mk_mcp_dev_servers_family_registration(
        tmp_path, "git-tools", ["git_status", "git_commit"])
    monkeypatch.setattr(pathlib.Path, "home", lambda: fake_home)
    repo, proj, commit = _mk_v4_toolkit_repo_with_list_mcp_tools(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": ["mcp__git-tools__git_status"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    assert line["status"] == "PASS", line
    assert "resolved=1" in line["measured"]


def test_census_budget_two_sided_within_budget_resolves_exhausted_skips(tmp_path, monkeypatch):
    """J2 (fix round 2): a TOTAL census budget across the whole
    agent_grants_resolvable computation, not just a per-alias ceiling.
    Two-sided with a FAKE census that sleeps: "git-tools" fits inside the
    (tiny, monkeypatched) budget and resolves for real; "github-tools" --
    alphabetically AFTER "git-tools", so the sorted-iteration ruling
    (controller addendum (a)) puts it on the exhausted side deterministically
    -- is never even attempted (the fake census's own call count proves the
    cutoff, not just the message) and SKIPs naming itself and the budget
    reason."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    monkeypatch.setattr(verify, "AGENT_GRANTS_CENSUS_BUDGET_S", 0.03)
    calls: list[str] = []

    def fake_derive(registration_path, alias):
        return str(tmp_path)  # any real directory -- only is_dir() is checked

    def fake_census(template_repo, source_dir, registration_path, alias):
        calls.append(alias)
        time.sleep(0.05)  # exceeds the 0.03s budget after this ONE call
        return (["real_tool"], None)

    monkeypatch.setattr(verify, "_derive_mcp_dev_servers_source_dir", fake_derive)
    monkeypatch.setattr(verify, "_census_mcp_dev_servers_alias", fake_census)

    repo, proj, commit = _good_fixture_v4(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {
            "foo": ["mcp__git-tools__real_tool", "mcp__github-tools__real_tool"]}}),
        encoding="utf-8", newline="")
    _recommit(proj)

    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["agent_grants_resolvable"]
    # Side A (within budget): exactly one census call was attempted, and it
    # was for "git-tools" (sorted-first) -- the fake census really ran.
    assert calls == ["git-tools"], calls
    # Side B (budget exhausted): "github-tools" SKIPs, naming itself and the
    # budget cause, WITHOUT a census call ever being attempted for it.
    assert line["status"] == "SKIP", line
    assert line["measured"] == "alias github-tools: census budget exhausted before it was reached"


def _mk_registered_family_alias(fake_home: pathlib.Path, alias: str, mds_dir: pathlib.Path) -> None:
    """Register `alias` in a fake ~/.claude.json pointing its command at a
    `.venv/Scripts/...` path under `mds_dir` -- `mds_dir` itself is not
    required to exist unless the test wants "source dir not found" to be
    FALSE."""
    fake_home.mkdir(parents=True, exist_ok=True)
    (fake_home / ".claude.json").write_text(
        json.dumps({"mcpServers": {alias: {"command": str(mds_dir / ".venv" / "Scripts" / f"mcp-{alias}.exe")}}}),
        encoding="utf-8")


@pytest.mark.parametrize("cause", [
    "source_dir_missing", "template_repo_unknown", "list_mcp_tools_fails", "budget_exhausted",
])
def test_agent_grants_resolvable_degraded_arms_name_alias_and_cause(cause, tmp_path, monkeypatch):
    """J1 (fix round 2): R-N's requirement is SKIP naming the alias AND the
    cause -- a degraded arm that SKIPs with a generic or empty `measured` is
    a silent hole the consumer cannot act on. One parametrized test over
    every degrade cause, unit-level (`_check_agent_grants_resolvable`
    called directly -- "templateRepo unknown" cannot be reached through a
    full `verify.run()`, since a manifest with no templateRepo fails much
    earlier in the cascade for unrelated reasons)."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    alias = "git-tools"
    pp = tmp_path / "proj"
    (pp / ".claude").mkdir(parents=True)
    (pp / ".claude" / "agent-grants.json").write_text(
        json.dumps({"schema": 1, "grants": {"foo": [f"mcp__{alias}__some_tool"]}}),
        encoding="utf-8", newline="")
    manifest = {"templateRepo": str(tmp_path / "toolkit")}

    if cause == "source_dir_missing":
        _mk_registered_family_alias(tmp_path / "home1", alias, tmp_path / "nonexistent-mds")
        monkeypatch.setattr(pathlib.Path, "home", lambda: tmp_path / "home1")
        expected_cause = "source dir not found"

    elif cause == "template_repo_unknown":
        manifest["templateRepo"] = ""
        mds_dir = tmp_path / "mds-tru"
        (mds_dir / "src" / "mcp_dev_servers").mkdir(parents=True)
        _mk_registered_family_alias(tmp_path / "home2", alias, mds_dir)
        monkeypatch.setattr(pathlib.Path, "home", lambda: tmp_path / "home2")
        expected_cause = "templateRepo unknown"

    elif cause == "list_mcp_tools_fails":
        mds_dir = tmp_path / "mds-fail"
        (mds_dir / "src" / "mcp_dev_servers").mkdir(parents=True)
        _mk_registered_family_alias(tmp_path / "home3", alias, mds_dir)
        monkeypatch.setattr(pathlib.Path, "home", lambda: tmp_path / "home3")
        lib_dir = pathlib.Path(manifest["templateRepo"]) / "scripts" / "lib"
        lib_dir.mkdir(parents=True)
        (lib_dir / "list-mcp-tools.py").write_text("import sys\nsys.exit(1)\n", encoding="utf-8", newline="")
        expected_cause = "list-mcp-tools.py exit 1"

    elif cause == "budget_exhausted":
        monkeypatch.setattr(verify, "AGENT_GRANTS_CENSUS_BUDGET_S", 0.0)
        mds_dir = tmp_path / "mds-budget"
        (mds_dir / "src" / "mcp_dev_servers").mkdir(parents=True)
        _mk_registered_family_alias(tmp_path / "home4", alias, mds_dir)
        monkeypatch.setattr(pathlib.Path, "home", lambda: tmp_path / "home4")
        expected_cause = "census budget exhausted before it was reached"

    else:
        pytest.fail(f"unhandled cause {cause!r}")

    line = verify._check_agent_grants_resolvable(pp, manifest)
    assert line["status"] == "SKIP", line
    assert alias in line["measured"], line
    assert expected_cause in line["measured"], line


def test_malformed_grants_file_fails_gracefully_never_crashes(tmp_path, monkeypatch):
    """R-P (fix round 1): compute_status_v3 returns {"error": ...} on a
    malformed .claude/agent-grants.json (R-C) rather than raising --
    verify.run must not KeyError in status_clean/classes_and_hashes (or any
    other status-dependent line); every one of them reports FAIL with the
    error message instead, and no_errors (the ORIGINAL R-C route) FAILs
    with it too. len(lines) == len(verify.LINES) still holds -- no line is
    silently dropped by the error path."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo, proj, commit = _good_fixture_v4(tmp_path)
    (proj / ".claude" / "agent-grants.json").write_text("not json", encoding="utf-8", newline="")
    _recommit(proj)

    res = verify.run(str(proj), str(repo), "post_commit")
    assert len(res["lines"]) == len(verify.LINES) == 31
    by_id = _by_id(res)
    for id_ in ("no_errors", "status_clean", "classes_and_hashes"):
        line = by_id[id_]
        assert line["status"] == "FAIL", (id_, line)
        assert "not valid JSON" in line["measured"], (id_, line)
    assert res["ok"] is False


def test_window_fixture_status_clean_is_the_one_fail(tmp_path):
    repo, proj, commit = _window_fixture(tmp_path)
    res = verify.run(str(proj), str(repo), "post_commit")
    fail_ids = {l["id"] for l in res["lines"] if l["status"] == "FAIL"}
    skip_ids = {l["id"] for l in res["lines"] if l["status"] == "SKIP"}
    info_ids = {l["id"] for l in res["lines"] if l["status"] == "INFO"}
    assert fail_ids == {"status_clean"}, _by_id(res)
    assert skip_ids == {"server_skew", "claude_md_identical", "import_line_present",
                        "instructions_file_present"}
    # v4.1.1 (spec §2.1): symmetric with test_pass_fixture_is_all_green /
    # test_v4_fixture_is_all_green -- project_md_seed_differs is not
    # manifest-version-gated, so the window situation's INFO set is the
    # SAME seven ids as the v3-legacy situation (this fixture's project.md
    # and the template's copy are byte-identical, PROJECT_MD_CONTENT).
    assert info_ids == {"template_behind_head", "encoding_drift", "project_md_seed_current",
                        "project_md_seed_differs",
                        "legacy_gate_dir", "once_notes_changed", "project_md_scoped_consistent"}
    line = _by_id(res)["status_clean"]
    assert "CLAUDE.md" in line["measured"]
    assert line["remedy"] == v3.MIGRATION_REQUIRED_REMEDY
    assert res["ok"] is False


def test_import_line_present_two_sided_template_regression(tmp_path, monkeypatch):
    """The stated case (R-K amended): the TEMPLATE loses the @ line, the
    consumer syncs from that broken checkout and matches it exactly --
    claude_md_identical PASSes (they match) while import_line_present is the
    ONLY line that can report the import silently gone."""
    monkeypatch.setattr(ts, "__version__", "4.1.0")
    repo, proj, commit = _good_fixture_v4(tmp_path)

    tpl_claude = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, "CLAUDE.md")
    broken = CLAUDE_CONTENT_V4.replace("@.claude/project-instructions.md\n", "")
    assert broken != CLAUDE_CONTENT_V4 and not broken.endswith("@.claude/project-instructions.md\n")
    tpl_claude.write_text(broken, encoding="utf-8", newline="")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "template regresses: loses the @ line")
    new_commit = _git_out(repo, "rev-parse", "HEAD")

    # The consumer re-applies (matches the broken template exactly) and
    # finalizes against the new commit.
    (proj / "CLAUDE.md").write_text(broken, encoding="utf-8", newline="")
    m = _read_manifest(proj)
    m["files"]["CLAUDE.md"] = {"hash": "sha256:" + ts._sha256(broken), "ownership": "template"}
    m["template_commit"] = new_commit
    _write_manifest(proj, m)
    _recommit(proj)

    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = _by_id(res)
    assert by_id["claude_md_identical"]["status"] == "PASS", by_id["claude_md_identical"]
    assert by_id["import_line_present"]["status"] == "FAIL", by_id["import_line_present"]


def test_tree_clean_mode_switch_both_ways(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    post = _by_id(verify.run(str(proj), str(repo), "post_commit"))["tree_clean"]
    pre = _by_id(verify.run(str(proj), str(repo), "pre_commit"))["tree_clean"]
    assert post["status"] == "PASS"
    assert pre["status"] == "SKIP"
    assert "pre_commit" in pre["measured"]


# --- one broken fixture per FAIL line ---------------------------------------


def test_manifest_valid_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    del m["variant"]
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["manifest_valid"]


def test_manifest_version_supported_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["manifest_version"] = 2
    m["version"] = 2
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["manifest_version_supported"]


def test_template_commit_known_fails_alone_on_unknown_sha(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["template_commit"] = "deadbeef" * 5
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["template_commit_known"]
    by_id = _by_id(res)
    assert by_id["template_behind_head"]["status"] == "INFO"
    assert "unknown" in by_id["template_behind_head"]["measured"]


def test_requires_server_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["requires_server"] = ">=99.0.0"
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["requires_server"]


def test_no_errors_fails_alone(tmp_path):
    """Isolated fixture: only once-class files, so a missing template variant
    directory cannot cascade into status_clean/classes_and_hashes, which
    read only template-class entries."""
    repo = tmp_path / "toolkit"
    repo.mkdir(parents=True)
    (repo / "templates").mkdir()
    (repo / "templates" / "ownership.json").write_text(json.dumps({
        "tracked_paths": ["templates"],
        "rules": [{"pattern": ".claude/rules/project.md", "ownership": "once"}],
    }), encoding="utf-8")
    commit = _init_repo(repo)

    proj = tmp_path / "proj"
    (proj / ".claude" / "rules").mkdir(parents=True)
    (proj / ".claude" / "rules" / "project.md").write_text(PROJECT_MD_CONTENT, encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3, "template_version": "v0.0.0", "template_commit": commit,
        "variant": "general",  # templates/general/ deliberately never created
        "templateRepo": str(repo), "placeholders": {}, "requires_server": ">=0.3.2",
        "files": {".claude/rules/project.md": {"ownership": "once"}},
    }
    _write_manifest(proj, manifest)
    _init_repo(proj)

    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["no_errors"]


def test_no_warnings_fails_alone(tmp_path):
    """A skipped ownership.json rule (bad `ownership` value) warns without
    changing classification of anything the good fixture already covers."""
    broken = json.loads(json.dumps(OWNERSHIP))
    broken["rules"].append({"pattern": "unrelated/**", "ownership": "bogus"})
    repo, proj, commit = _good_fixture(tmp_path, ownership=broken)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["no_warnings"]


def test_unknown_keys_empty_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["extra_field"] = "x"
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["unknown_keys_empty"]


def test_superseded_absent_fails_alone(tmp_path):
    """`lastSynced` alone: a SUPERSEDED key that is ALSO a known top-level key
    (accepted as a template_commit alias), so this cannot also trip
    unknown_keys_empty."""
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    assert "lastSynced" not in v3.KNOWN_TOP_LEVEL_V3 or "lastSynced" in v3.KNOWN_TOP_LEVEL_V3
    m["lastSynced"] = commit
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["superseded_absent"]


def test_server_skew_fails_alone_dirty_working_tree(tmp_path, monkeypatch):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "server").mkdir()
    (repo / "server" / "x.py").write_text("x = 1\n", encoding="utf-8", newline="")
    _recommit(repo, "add server/")
    server_commit = _git_out(repo, "rev-parse", "HEAD")
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(repo / "server"))
    monkeypatch.setattr(ts, "SERVER_COMMIT", server_commit)
    # Dirty the working tree under server/ WITHOUT committing.
    (repo / "server" / "x.py").write_text("x = 2\n", encoding="utf-8", newline="")

    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["server_skew"]
    by_id = _by_id(res)
    assert "working tree dirty=True" in by_id["server_skew"]["measured"]


def test_server_skew_both_arms(tmp_path, monkeypatch):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "server").mkdir()
    (repo / "server" / "x.py").write_text("x = 1\n", encoding="utf-8", newline="")
    _recommit(repo, "add server/")
    server_commit = _git_out(repo, "rev-parse", "HEAD")
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(repo / "server"))
    monkeypatch.setattr(ts, "SERVER_COMMIT", server_commit)

    # Arm A: committed diff under server/ (working tree clean).
    (repo / "server" / "x.py").write_text("x = 2\n", encoding="utf-8", newline="")
    _recommit(repo, "change server/")
    res_a = _by_id(verify.run(str(proj), str(repo), "post_commit"))["server_skew"]
    assert res_a["status"] == "FAIL"
    assert "committed diff dirty=True" in res_a["measured"]

    # Arm B: a docs-only commit after server_commit, server/ itself untouched
    # since -- INFO, not FAIL.
    (repo / "README.md").write_text("docs\n", encoding="utf-8", newline="")
    _recommit(repo, "docs")
    monkeypatch.setattr(ts, "SERVER_COMMIT", _git_out(repo, "rev-parse", "HEAD~1"))
    res_b = _by_id(verify.run(str(proj), str(repo), "post_commit"))["server_skew"]
    assert res_b["status"] == "INFO"


def test_status_clean_fails_alone(tmp_path):
    """A missing ONCE-class file (status MISSING) trips status_clean without
    touching any template-class entry's identical/hash state, so
    classes_and_hashes is unaffected."""
    repo, proj, commit = _good_fixture(tmp_path)
    _git(proj, "rm", "-q", ".claude/rules/project.md")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["status_clean"]


def test_gate_self_reference_empty_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / "PROJECT_CONTEXT.md").write_text(
        "- **Protected branches**: main\n- **Gate**: bash hooks/run-gate.sh\n",
        encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["gate_self_reference_empty"]


def test_unclassified_empty_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "templates" / "general" / "stray.md").write_text("x\n", encoding="utf-8", newline="")
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["unclassified_empty"]


def test_new_template_files_empty_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "hooks" / "extra.sh").write_text("echo extra\n", encoding="utf-8", newline="")
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["new_template_files_empty"]


def test_classes_and_hashes_fails_alone_on_invalid_shape(tmp_path):
    """A `once` entry carrying a hash key is malformed manifest shape --
    caught without touching any status classification."""
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["files"][".claude/rules/project.md"]["hash"] = "sha256:" + "0" * 64
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["classes_and_hashes"]


def test_local_edited_pair_shape_pass_status_fail(tmp_path):
    """MM-Agent's shape (item 10): two template-class files edited locally
    used to fire classes_and_hashes too, because its old check duplicated
    status_clean's drift assertion (IDENTICAL count == template-class
    count). classes_and_hashes now asserts SHAPE plus a closed status
    PARTITION -- LOCAL_EDITED is one of the enumerated buckets, so the
    partition is complete and this line PASSes; the drift itself stays
    with status_clean alone."""
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / "CLAUDE.md").write_text("# T\nrule one, edited\n", encoding="utf-8", newline="")
    (proj / "hooks" / "g.sh").write_text("echo g, edited\n", encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    by = _by_id(res)
    assert by["classes_and_hashes"]["status"] == "PASS", by["classes_and_hashes"]
    assert "local_edited=2" in by["classes_and_hashes"]["measured"]
    assert by["status_clean"]["status"] == "FAIL", by["status_clean"]
    assert "local_edited=2" in by["status_clean"]["measured"]


def test_classes_and_hashes_fails_on_unenumerated_status(tmp_path, monkeypatch):
    """The partition witness (reviewer's acceptance rule): a one-line
    production change that makes compute_status_v3 emit a status not in
    TEMPLATE_CLASS_STATUSES, without extending the tuple, must make this
    line FAIL -- otherwise the enumeration is not actually closed."""
    repo, proj, commit = _good_fixture(tmp_path)
    real_compute = v3.compute_status_v3

    def _patched(pp, manifest, rules):
        result = real_compute(pp, manifest, rules)
        for info in result["files"].values():
            if info.get("ownership") == "template":
                info["status"] = "NEW_STATUS"
                break
        return result

    monkeypatch.setattr(v3, "compute_status_v3", _patched)
    res = verify.run(str(proj), str(repo), "post_commit")
    line = _by_id(res)["classes_and_hashes"]
    assert line["status"] == "FAIL", line
    assert "unenumerated=NEW_STATUS" in line["measured"], line


def test_classes_and_hashes_unenumerated_none_no_crash(tmp_path, monkeypatch):
    """Review round 2: two-sided -- one template-class path compute_status_v3
    omits entirely (entry_status resolves to None via .get(..., {}).get(
    "status")) AND a second template-class path relabelled to an actual
    unenumerated status string, so `unenumerated` holds two DISTINCT values
    (None and a str). A plain sorted(set(...)) raises TypeError comparing
    str and NoneType on exactly this shape; sorting by str() must not."""
    repo, proj, commit = _good_fixture(tmp_path)
    real_compute = v3.compute_status_v3

    def _patched(pp, manifest, rules):
        result = real_compute(pp, manifest, rules)
        template_paths = [p for p, info in result["files"].items()
                          if info.get("ownership") == "template"]
        assert len(template_paths) >= 2, template_paths  # fixture must supply both sides
        del result["files"][template_paths[0]]
        result["files"][template_paths[1]]["status"] = "NEW_STATUS"
        return result

    monkeypatch.setattr(v3, "compute_status_v3", _patched)
    res = verify.run(str(proj), str(repo), "post_commit")  # must not raise
    line = _by_id(res)["classes_and_hashes"]
    assert line["status"] == "FAIL", line
    assert "unenumerated=None" in line["measured"], line
    assert "unenumerated=NEW_STATUS" in line["measured"], line


def test_region_markers_fails_alone(tmp_path):
    """Broken markers on a ONCE-class file: content changes there never
    affect status (once-class status is presence-only)."""
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / ".claude" / "rules" / "project.md").write_text(
        "<!-- PROJECT-CUSTOM:BEGIN -->\nno end marker\n", encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["region_markers"]


def test_manifest_bytes_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    manifest_path = proj / ".claude" / "template-manifest.json"
    data = manifest_path.read_bytes()
    assert data.endswith(b"\n")
    manifest_path.write_bytes(data[:-1])  # drop the trailing LF; JSON content unchanged
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["manifest_bytes"]


def test_declared_keys_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / "PROJECT_CONTEXT.md").write_text("- **Protected branches**: main\n", encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["declared_keys"]
    by_id = _by_id(res)
    assert any(d["key"] == "Gate" for d in by_id["declared_keys"]["measured"] if isinstance(d, dict)) or \
        "Gate" in str(by_id["declared_keys"]["measured"])


def test_tree_clean_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / "scratch.txt").write_text("x\n", encoding="utf-8", newline="")  # left uncommitted, deliberately
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["tree_clean"]


# --- INFO lines --------------------------------------------------------------


def test_info_lines_nonempty_on_crlf_bom_and_stale_seed(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    # CRLF drift on a template-class file the project copy does NOT carry:
    # the template's own on-disk copy gets CRLF, the project's does not.
    tpl_claude = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, "CLAUDE.md")
    tpl_claude.write_bytes(CLAUDE_CONTENT.encode("utf-8").replace(b"\n", b"\r\n"))
    # BOM on the project's own copy.
    (proj / "PROJECT_CONTEXT.md").write_bytes(b"\xef\xbb\xbf" + CONTEXT_CONTENT.encode("utf-8"))
    (proj / ".claude" / "rules" / "project.md").write_text(
        "This file has been delivered to nobody.\n", encoding="utf-8", newline="")
    _recommit(proj)

    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = _by_id(res)
    assert by_id["encoding_drift"]["status"] == "INFO"
    assert by_id["encoding_drift"]["measured"] != "no encoding drift (bom/crlf) on any tracked file"
    assert by_id["project_md_seed_current"]["status"] == "INFO"
    assert "delivered to nobody" in by_id["project_md_seed_current"]["measured"]


# --- v4.0.2 new INFO lines and remedies --------------------------------------


def test_legacy_gate_dir_names_artifacts_and_counts_the_rest(tmp_path):
    repo, proj, _ = _good_fixture(tmp_path)
    g = proj / ".gate"; g.mkdir()
    (g / "last-pass.json").write_text("{}")
    (g / "run-2026-09-01.log").write_text("x"); (g / "run-2026-09-02.log").write_text("y")
    _recommit(proj)
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["legacy_gate_dir"]
    assert line["status"] == "INFO"
    assert "last-pass.json" in line["measured"] and "2 other entr" in line["measured"]
    assert "by name" in line["remedy"] and "leave them" in line["remedy"]


def test_legacy_gate_dir_null_case(tmp_path):
    repo, proj, _ = _good_fixture(tmp_path)
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["legacy_gate_dir"]
    assert line["status"] == "INFO" and "no legacy" in line["measured"]


def test_legacy_gate_dir_runs_on_the_manifest_less_path(tmp_path):
    """Task 3 addendum item C / ruling R8: legacy_gate_dir reads only
    pp/".gate" -- no manifest, no rules, no status needed -- so it belongs
    in _SHAPE_INDEPENDENT alongside manifest_bytes/tree_clean and must
    actually run (not cascade-SKIP) on a directory with no manifest at all,
    the same place manifest_bytes/tree_clean already run."""
    proj = tmp_path / "proj"
    gate = proj / ".gate"
    gate.mkdir(parents=True)
    (gate / "last-pass.json").write_text("{}")

    res = verify.run(str(proj), "", "post_commit")
    assert len(res["lines"]) == len(verify.LINES)
    # A missing manifest still FAILs exactly manifest_valid; ok stays False --
    # legacy_gate_dir running here must not introduce any new FAIL.
    assert _only_fail(res) == ["manifest_valid"]
    assert res["ok"] is False
    line = _by_id(res)["legacy_gate_dir"]
    assert line["status"] == "INFO"
    assert "last-pass.json" in line["measured"]


def test_once_notes_changed_reports_hunk_count(tmp_path):
    # PROJECT_CONTEXT.md is once-class with audit=keys in OWNERSHIP; change a
    # template COMMENT line only (never a **Key**: line), so
    # key_audit.template_notes_changed is non-empty without touching
    # status_clean or classes_and_hashes (once-class status is presence-only,
    # and only the TEMPLATE's own copy changes -- the project's is untouched).
    repo, proj, commit = _good_fixture(tmp_path)
    tpl_context = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, "PROJECT_CONTEXT.md")
    tpl_context.write_text(CONTEXT_CONTENT + "<!-- a new guidance comment -->\n",
                           encoding="utf-8", newline="")
    _recommit(repo, "template gains a guidance comment")
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["once_notes_changed"]
    assert line["status"] == "INFO" and "PROJECT_CONTEXT.md" in line["measured"] and "hunks: 1" in line["measured"]


def test_once_notes_changed_null_case(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["once_notes_changed"]
    assert line["status"] == "INFO" and "no once-class file has changed template notes" in line["measured"]


def test_status_clean_names_stale_hash_remedy(tmp_path):
    repo, proj, _ = _good_fixture(tmp_path)
    m = _read_manifest(proj); m["files"]["hooks/g.sh"]["hash"] = "sha256:" + "0" * 64
    _write_manifest(proj, m); _recommit(proj)
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["status_clean"]
    assert line["status"] == "FAIL" and "stale stored hash" in line["measured"]
    assert "applied_files" in line["remedy"]


def test_tree_clean_remedy_mentions_unrelated_work(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / "scratch.txt").write_text("x", encoding="utf-8", newline="")
    line = _by_id(verify.run(str(proj), str(repo), "post_commit"))["tree_clean"]
    assert "unrelated" in line["remedy"] and "separately" in line["remedy"]


@pytest.mark.parametrize("body,seed,scoped", [
    ("This file has been delivered to nobody.\n", "stale", "n/a"),
    (V401_SEED_NO_MARKER, "predates", "n/a"),
    # v4.1.1 (spec §2.1): the harm-keyed arm fires BEFORE "predates"/"stale"
    # -- V401_SEED itself names PROJECT-CUSTOM, so it now reads as this new
    # case rather than "predates" (V401_SEED_NO_MARKER above is the fixture
    # that isolates "predates" from this drift).
    (V401_SEED, "project_custom", "n/a"),
    (V402_SEED, "current", "n/a"),
    # v4.1.2 spec §2 (panoscribe, two-sided): a historical NOTE naming the
    # retired region, with the guidance line already repointed -> current.
    (PROJECT_MD_CONTENT + "\nMigration note: this used to live in CLAUDE.md's PROJECT-CUSTOM region.\n",
     "current", "n/a"),
    # Same file, note reworded -> also current (the guidance line decides).
    (PROJECT_MD_CONTENT + "\nMigration note: this used to live in the old region.\n",
     "current", "n/a"),
    # The retired v4.0.1 guidance sentence itself, with a realistic header
    # -> the harm arm.
    ("# Project instructions\n\n" + V401_SEED + "\n", "project_custom", "n/a"),
    # Guidance AND note both name it -> ONE line, the harm arm (not two);
    # the exactly-one-line assertion lives in
    # test_seed_current_guidance_and_note_yields_one_line below.
    ("# Project instructions\n\n" + V401_SEED + "\nNote: PROJECT-CUSTOM again.\n",
     "project_custom", "n/a"),
    # Review Focus 4: guidance line wrapped by an editor -> first line names
    # nothing -> older arms -> current. Deliberate, pinned.
    (PROJECT_MD_CONTENT.replace(
        "Always-on project rules belong in `.claude/project-instructions.md`",
        "Always-on project rules belong in\n`.claude/project-instructions.md`"),
     "current", "n/a"),
    ("---\npaths:\n  - \"src/**\"\n---\n# mine\n", "scoped", "clean"),
    ("---\npaths:\n  - \"src/**\"\n---\n" + V402_SEED, "scoped", "contradiction"),
])
def test_project_md_lines(tmp_path, body, seed, scoped):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / ".claude" / "rules" / "project.md").write_text(body, encoding="utf-8", newline="")
    _recommit(proj)
    by_id = _by_id(verify.run(str(proj), str(repo), "post_commit"))

    seed_map = {"stale": "pre-v4.0.1", "predates": "predates v4.0.2",
               "current": "seed is current", "scoped": "scoped",
               # v4.1.2 spec §2: the message names the GUIDANCE LINE, not a
               # "header" (the arm no longer fires on the token anywhere in
               # the file, so its wording says exactly what it now checks).
               "project_custom": "guidance line points at PROJECT-CUSTOM"}
    scoped_map = {"n/a": "n/a", "clean": "no unscoped sentence", "contradiction": "still carries"}
    assert seed_map[seed] in by_id["project_md_seed_current"]["measured"], by_id["project_md_seed_current"]
    assert scoped_map[scoped] in by_id["project_md_scoped_consistent"]["measured"], \
        by_id["project_md_scoped_consistent"]


def test_seed_current_guidance_and_note_yields_one_line(tmp_path):
    """v4.1.2 spec §2 (panoscribe, two-sided): when BOTH the guidance line
    and a separate note name PROJECT-CUSTOM, the harm arm fires once --
    project_md_seed_current is a single-emit id (one `elif` chain), never
    two lines for one file."""
    repo, proj, commit = _good_fixture(tmp_path)
    body = "# Project instructions\n\n" + V401_SEED + "\nNote: PROJECT-CUSTOM again.\n"
    (proj / ".claude" / "rules" / "project.md").write_text(body, encoding="utf-8", newline="")
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    seed_current_lines = [l for l in res["lines"] if l["id"] == "project_md_seed_current"]
    assert len(seed_current_lines) == 1, seed_current_lines
    assert "PROJECT-CUSTOM" in seed_current_lines[0]["measured"]


def test_project_md_remedies_hand_edit_and_move_hunks(tmp_path):
    """Both project_md_seed_current remedy arms (items 9, 11) say the
    consumer HAND-EDITS the once-class file the sync never writes, name the
    sentence that must be added, and tell a consumer migrated before
    v4.0.1 to move any migration hunks out of the header FIRST."""
    repo, proj, commit = _good_fixture(tmp_path)

    (proj / ".claude" / "rules" / "project.md").write_text(V401_SEED_NO_MARKER, encoding="utf-8", newline="")
    _recommit(proj)
    predates = _by_id(verify.run(str(proj), str(repo), "post_commit"))["project_md_seed_current"]
    assert predates["status"] == "INFO"
    assert "hand-edit" in predates["remedy"]
    assert "picked up at the NEXT session start" in predates["remedy"]
    assert "move them" in predates["remedy"]

    (proj / ".claude" / "rules" / "project.md").write_text(
        "This file has been delivered to nobody.\n", encoding="utf-8", newline="")
    _recommit(proj)
    stale = _by_id(verify.run(str(proj), str(repo), "post_commit"))["project_md_seed_current"]
    assert stale["status"] == "INFO"
    assert "hand-edit" in stale["remedy"]
    assert "picked up at the NEXT session start" in stale["remedy"]
    assert "move them" in stale["remedy"]


# --- template_behind_head sub-arms -------------------------------------------


def test_template_behind_head_unchanged_on_untracked_commit(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "README.md").write_text("docs\n", encoding="utf-8", newline="")
    _recommit(repo, "docs")
    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = _by_id(res)
    assert by_id["template_commit_known"]["status"] == "PASS"
    assert "unchanged" in by_id["template_behind_head"]["measured"]


def test_template_behind_head_differs_on_tracked_commit(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    (repo / "hooks" / "g.sh").write_text("echo changed\n", encoding="utf-8", newline="")
    _recommit(repo, "change a hook")
    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = _by_id(res)
    assert by_id["template_commit_known"]["status"] == "PASS"
    assert "differs" in by_id["template_behind_head"]["measured"]


# --- MCP tool wiring -----------------------------------------------------


def test_mcp_tool_wraps_verify_run(tmp_path):
    import asyncio
    repo, proj, commit = _good_fixture(tmp_path)
    out = json.loads(asyncio.run(ts.template_verify(str(proj), str(repo), "post_commit")))
    assert out["ok"] is True
    assert out["mode"] == "post_commit"
    assert "PASS" in out["summary"]


def test_cli_verify_exit_code_and_output(tmp_path, capsys):
    repo, proj, commit = _good_fixture(tmp_path)
    rc = ts._cli_verify([str(proj), "--template-repo", str(repo), "--mode", "post_commit"])
    out = capsys.readouterr().out
    assert rc == 0
    assert "PASS, 0 FAIL" in out

    m = _read_manifest(proj)
    m["requires_server"] = ">=99.0.0"
    _write_manifest(proj, m)
    _recommit(proj)
    rc2 = ts._cli_verify([str(proj), "--template-repo", str(repo)])
    out2 = capsys.readouterr().out
    assert rc2 == 1
    assert "FAIL requires_server" in out2


# =============================================================================
# v4.1.1 Task 2 (spec sections 1.3, 1.4, 2.1): manifest_migration, per-consumer
# case 2 (consumer_template_paths), and the seed line that cannot lie
# (project_md_seed_differs). Fixtures below wrap the SAME builders the rest
# of this file already uses (_good_fixture = a v3 "legacy" situation,
# _good_fixture_v4 = v4, _window_fixture = the v3-manifest window) so the
# three SITUATIONS the last test in this section needs are the same ones
# test_pass_fixture_is_all_green / test_v4_fixture_is_all_green /
# test_window_fixture_status_clean_is_the_one_fail already exercise.
# =============================================================================

# OWNERSHIP_V4 (module-level, above) already declares rules for BOTH v4-only
# marker paths (.claude/project-instructions.md, .claude/agent-grants.json)
# -- exactly the signal _manifest_migration_to (mcp.py) reads to answer "to":
# 4. Reusing it (rather than the plain OWNERSHIP dict, which lacks both) for
# v3_consumer is what makes a v3 manifest against THIS template read
# manifest_migration.to == 4 -- "a v3 manifest against a v4-capable
# template" (spec §1.3's witness) is exactly what a v3-manifest-shaped
# _good_fixture with OWNERSHIP_V4 is.


def template_verify_lines(consumer, mode: str = "post_commit") -> dict:
    return _by_id(verify.run(str(consumer.root), str(consumer.repo), mode))


class _Task2Consumer:
    """Adapter exposing `.root` (project dir), `.repo` (template repo dir),
    `.manifest` (the on-disk manifest dict) and `.rules` (freshly re-loaded
    OwnershipRules) -- plus `.write` (hand-edit a once-class file and
    recommit, e.g. .claude/rules/project.md) and `.track` (add a path to
    this consumer's OWN manifest as a template-owned entry; only `ownership`
    is read by consumer_template_paths, so no hash is needed)."""

    def __init__(self, repo, root, manifest):
        self.repo = repo
        self.root = root
        self.manifest = manifest

    @property
    def rules(self):
        return v3.load_ownership(str(self.repo))

    def write(self, rel_path: str, content: str):
        p = self.root / rel_path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
        _recommit(self.root, f"edit {rel_path}")

    def track(self, proj_rel: str):
        files = dict(self.manifest.get("files", {}))
        files[proj_rel] = {"ownership": "template"}
        self.manifest = dict(self.manifest, files=files)
        _write_manifest(self.root, self.manifest)
        _recommit(self.root, f"track {proj_rel}")


@pytest.fixture
def v3_consumer(tmp_path):
    # A distinct subdirectory per fixture (test_lines_count_is_31_and_every_
    # situation_table_lists_the_new_line requests v4_consumer,
    # v3_legacy_consumer AND v3_window_consumer in ONE test -- tmp_path is
    # shared across all fixtures a single test requests, and each builder
    # below does `(tmp_path / "toolkit" / ...).mkdir(parents=True)` with no
    # exist_ok, so three builders sharing one bare tmp_path collide).
    repo, proj, commit = _good_fixture(tmp_path / "v3-consumer", ownership=OWNERSHIP_V4)
    return _Task2Consumer(repo, proj, _read_manifest(proj))


@pytest.fixture
def v3_legacy_consumer(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path / "v3-legacy")
    return _Task2Consumer(repo, proj, _read_manifest(proj))


@pytest.fixture
def v4_consumer(tmp_path):
    # consumer_template_paths (v3.py) resolves a project-relative path to a
    # repo-root git path via core._template_git_path: "hooks/g.sh" is
    # already root-tracked (core._ROOT_TRACKED_PREFIXES, UNMODIFIED here)
    # and "CLAUDE.md" / ".claude/agents/foo.md" get the
    # "templates/<variant>/" prefix -- all production-real, no test-only
    # widening of that constant. Fix round 1 dropped an earlier version of
    # this fixture that widened _ROOT_TRACKED_PREFIXES via monkeypatch so a
    # single synthetic path (user-level-reference/README.md) could serve as
    # BOTH the #9 case-2 ("does not track") and case-3 ("tracks it")
    # witnesses -- the reviewer measured that with the real constant
    # emptied, those tests stayed green only because the monkeypatch
    # supplied its own prefix (11 OTHER tests went red on the same change),
    # i.e. redundancy lost, not protection. The two witnesses below (in the
    # case2/case3 tests, not this fixture) now stand on two DIFFERENT
    # real, root-tracked hooks/ paths: hooks/g.sh (this fixture's own
    # already-template-owned entry, for "tracks it") and hooks/other.sh (a
    # path this fixture's manifest does NOT hold, for "does not track") --
    # both resolve under the SAME unmodified "hooks/" prefix, so the
    # discriminator is genuinely "tracked or not", not "resolved correctly
    # or not" (see the report's fix-round-1 section for the emptied-prefix
    # RED confirmation on the tracked one).
    repo, proj, commit = _good_fixture_v4(tmp_path / "v4")
    return _Task2Consumer(repo, proj, _read_manifest(proj))


@pytest.fixture
def v3_window_consumer(tmp_path):
    repo, proj, commit = _window_fixture(tmp_path / "v3-window")
    return _Task2Consumer(repo, proj, _read_manifest(proj))


class _TemplateRepoHandle:
    def __init__(self, path):
        self.path = path

    @property
    def head(self) -> str:
        return _git_out(self.path, "rev-parse", "HEAD")

    def tag(self, name: str):
        _git(self.path, "tag", name)

    def commit_edit(self, repo_rel_path: str, content: str):
        p = self.path / repo_rel_path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")
        _git(self.path, "add", "-A")
        _git(self.path, "commit", "-q", "-m", f"edit {repo_rel_path}")


@pytest.fixture
def template_repo(v4_consumer):
    """The SAME repo `v4_consumer` already points at -- the case2/case3
    witnesses mutate the template repo a consumer has already loaded, then
    re-derive against it; a separately-built repo would make every
    tag/commit these tests make invisible to v4_consumer.manifest/.rules."""
    return _TemplateRepoHandle(v4_consumer.repo)


# --- manifest_migration (spec §1.3) -----------------------------------------


def test_manifest_migration_reports_v3_to_v4(v3_consumer):
    out = json.loads(asyncio.run(ts.template_load_manifest(str(v3_consumer.root))))
    assert out["manifest_migration"] == {"from": 3, "to": 4, "required": True}
    assert out["migration_required"] is False          # unchanged: the v2->v3 answer


def test_manifest_migration_false_on_v4(v4_consumer):
    out = json.loads(asyncio.run(ts.template_load_manifest(str(v4_consumer.root))))
    assert out["manifest_migration"] == {"from": 4, "to": 4, "required": False}


# --- per-consumer case 2 (spec §1.4) ----------------------------------------


def test_case2_survives_commit_to_path_this_consumer_does_not_track(template_repo, v4_consumer):
    # hooks/other.sh is root-tracked under the SAME unmodified "hooks/"
    # prefix as v4_consumer's own hooks/g.sh entry -- it resolves correctly
    # (no templates/<variant>/ misprefix to hide behind); it is green
    # because this consumer's manifest simply does not hold it, not because
    # it resolved somewhere consumer_template_paths never looks.
    template_repo.tag("v9.9.9")
    template_repo.commit_edit("hooks/other.sh", "echo other\n")
    version, warn = v3.derive_template_version(
        str(template_repo.path), template_repo.head,
        v3.consumer_template_paths(v4_consumer.manifest, v4_consumer.rules))
    assert (version, warn) == ("v9.9.9", None)


def test_case3_on_commit_to_tracked_path(template_repo, v4_consumer):
    template_repo.tag("v9.9.9")
    template_repo.commit_edit("templates/general/CLAUDE.md", "changed\n")
    version, warn = v3.derive_template_version(
        str(template_repo.path), template_repo.head,
        v3.consumer_template_paths(v4_consumer.manifest, v4_consumer.rules))
    assert (version, warn) == (None, "untagged_template_tree")


def test_case3_when_this_consumer_tracks_the_touched_path(template_repo, v4_consumer):
    # per-consumer set, not a global exclusion: hooks/g.sh is a
    # template-owned entry v4_consumer ALREADY holds (_good_fixture_v4's
    # template_files dict) -- no synthetic .track() needed. It resolves
    # under the SAME unmodified "hooks/" root-tracked prefix as
    # test_case2's hooks/other.sh above; the difference between the two
    # tests is purely "does this consumer's manifest hold this path",
    # which is exactly what #9 (spec §1.4) is about. This is also the
    # discriminating witness: emptying core._ROOT_TRACKED_PREFIXES makes
    # this test fail (see the report's fix-round-1 section) -- it is not
    # accidentally green.
    template_repo.tag("v9.9.9")
    template_repo.commit_edit("hooks/g.sh", "echo changed\n")
    version, warn = v3.derive_template_version(
        str(template_repo.path), template_repo.head,
        v3.consumer_template_paths(v4_consumer.manifest, v4_consumer.rules))
    assert version is None


# --- the seed line that cannot lie (spec §2.1) ------------------------------

# Both names resolve to the file's own PROJECT_MD_CONTENT (the CURRENT,
# R-G-reworded shipped seed: "# Project instructions" + v3.PROJECT_MD_SEED_BODY
# -- already ships the ".claude/project-instructions.md (imported at the end
# of CLAUDE.md)" sentence). The two replace() calls below each need their
# target substring present in the base text -- both are, in this one shape --
# so there is only one "current" shape to mutate away from in either
# direction; the brief's two names do not need two different base strings.
SEED_V402_HEADER = PROJECT_MD_CONTENT
SEED_V411_HEADER = PROJECT_MD_CONTENT


def test_seed_current_flags_project_custom_reference(v4_consumer):
    # NOTE (brief line found wrong): the brief's literal replace() target
    # (".claude/project-instructions.md (imported at the end of CLAUDE.md)")
    # does not occur in the live v3.PROJECT_MD_SEED_BODY -- the real
    # sentence wraps the path in backticks AND breaks the line inside the
    # parenthetical ("`.claude/project-instructions.md` (imported at\nthe
    # end of CLAUDE.md)"), so the brief's exact string is never a substring
    # match; using it verbatim leaves the header BYTE-IDENTICAL to what
    # _good_fixture_v4 already committed (a silent no-op .write() that then
    # fails the fixture's own git commit with "nothing to commit"). Matched
    # against the real text below.
    assert SEED_V402_HEADER.replace(
        "Always-on project rules belong in `.claude/project-instructions.md` (imported at\n"
        "the end of CLAUDE.md), not here;",
        "Always-on project rules belong in CLAUDE.md's PROJECT-CUSTOM region, not here;",
    ) != SEED_V402_HEADER, "replace() target must actually match the live seed text"
    v4_consumer.write(".claude/rules/project.md", SEED_V402_HEADER.replace(
        "Always-on project rules belong in `.claude/project-instructions.md` (imported at\n"
        "the end of CLAUDE.md), not here;",
        "Always-on project rules belong in CLAUDE.md's PROJECT-CUSTOM region, not here;",
    ))
    line = template_verify_lines(v4_consumer)["project_md_seed_current"]
    assert line["status"] == "INFO" and "PROJECT-CUSTOM" in line["measured"]
    assert "repoint" in line["remedy"] and "project-instructions.md" in line["remedy"]


def test_seed_current_on_consumer_reworded_header_without_marker(v4_consumer):
    # Guard (fix round 1, item 4): without it a no-op replace() (target
    # substring absent) would leave the seed UNMUTATED, which also reads
    # "current" -- a false PASS that tests nothing. Same shape as the
    # PROJECT-CUSTOM fixture's guard above.
    assert SEED_V411_HEADER.replace("Always-on project rules", "Our always-on rules") != SEED_V411_HEADER, \
        "replace() target must actually match the live seed text"
    v4_consumer.write(".claude/rules/project.md", SEED_V411_HEADER.replace(
        "Always-on project rules", "Our always-on rules"))
    line = template_verify_lines(v4_consumer)["project_md_seed_current"]
    assert line["measured"].endswith("seed is current")


def test_seed_differs_is_a_fact_with_no_remedy(v4_consumer):
    assert SEED_V411_HEADER.replace("Always-on project rules", "Our always-on rules") != SEED_V411_HEADER, \
        "replace() target must actually match the live seed text"
    v4_consumer.write(".claude/rules/project.md", SEED_V411_HEADER.replace(
        "Always-on project rules", "Our always-on rules"))
    line = template_verify_lines(v4_consumer)["project_md_seed_differs"]
    assert line["status"] == "INFO" and "differs from the shipped seed" in line["measured"]
    assert not any(verb in line.get("remedy", "") for verb in ("replace", "update", "consider", "should"))


def test_seed_differs_matches_when_consumer_appended_rules_after_the_seed(v4_consumer):
    """Prefix, not byte-compare: appending after the shipped seed still
    reads as a match (the header text itself is untouched)."""
    v4_consumer.write(".claude/rules/project.md", PROJECT_MD_CONTENT + "\nOur own extra rule.\n")
    line = template_verify_lines(v4_consumer)["project_md_seed_differs"]
    assert line["status"] == "INFO"
    assert "matches the shipped seed" in line["measured"]
    assert "remedy" not in line or line["remedy"] in ("", "n/a (informational)")


def test_lines_count_is_31_and_every_situation_table_lists_the_new_line(
        v4_consumer, v3_legacy_consumer, v3_window_consumer):
    for c in (v4_consumer, v3_legacy_consumer, v3_window_consumer):
        lines = template_verify_lines(c)
        assert len(lines) == 31 and "project_md_seed_differs" in lines
