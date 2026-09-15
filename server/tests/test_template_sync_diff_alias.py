"""template_get_diff accepts diff_type="unified" as an alias of "full" (review §2.11)."""

import asyncio
import json
import pathlib

from template_sync import mcp as ts
from template_sync import v3


def test_get_diff_accepts_unified_as_alias_of_full(tmp_path):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "CLAUDE.md").write_text("a\nb\n", encoding="utf-8", newline="")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text("a\nc\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {"CLAUDE.md": {"templateHash": ts._sha256("a\nb\n")}},
    }), encoding="utf-8")
    full = json.loads(asyncio.run(ts.template_get_diff(str(proj), "CLAUDE.md", "full")))
    uni = json.loads(asyncio.run(ts.template_get_diff(str(proj), "CLAUDE.md", "unified")))
    assert uni["diff_type"] == "unified"
    assert uni["unified_diff"] == full["unified_diff"]
    assert "-b" in uni["unified_diff"] and "+c" in uni["unified_diff"]


def test_get_diff_resolves_dotfile_mapping(tmp_path):
    """v4.0.1 item 3: compute_status already maps gitignore -> .gitignore and
    reports it in new_template_files, but template_get_diff(".gitignore")
    looked for a template file literally named ".gitignore" -- which does
    not exist (the template copy is named "gitignore", dotless, so a
    template-owned file does not itself get gitignored) -- and errored.
    """
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "gitignore").write_text("*.log\n", encoding="utf-8", newline="")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".gitignore").write_text("*.log\n*.tmp\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {".gitignore": {"templateHash": ts._sha256("*.log\n")}},
    }), encoding="utf-8")
    res = json.loads(asyncio.run(ts.template_get_diff(str(proj), ".gitignore", "full")))
    assert "error" not in res, res
    assert res.get("file_path") == ".gitignore"


GITIGNORE_OWNERSHIP = {
    "tracked_paths": ["templates"],
    "rules": [{"pattern": "gitignore", "ownership": "once", "target": ".gitignore"}],
}


def _mk_gitignore_v3(tmp_path, project_has_gitignore: bool):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "gitignore").write_text("*.log\n", encoding="utf-8", newline="")
    (repo / "templates" / "ownership.json").write_text(json.dumps(GITIGNORE_OWNERSHIP), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    if project_has_gitignore:
        (proj / ".gitignore").write_text("mine\n", encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3, "template_version": "3.1.0", "template_commit": "0000000",
        "variant": "general", "templateRepo": str(repo), "placeholders": {},
        "requires_server": ">=0.3.0", "files": {},
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")
    return repo, proj


def test_apply_gitignore_present_is_kept_REGRESSION_GUARD(tmp_path):
    """Green BEFORE the v4.0.1 fix too, and proves nothing about it (design
    spec item 3, constraint 5): apply_file_v3 already resolves the dotfile
    mapping through OwnershipRules.template_path_for's ownership.json
    "target" field. As of fix round 1 (item F4) the mcp.py-level
    template_path_for() used by _template_file_path/_template_git_path
    derives from that SAME ownership.json when a manifest is given, so the
    two are no longer independent mechanisms that could silently disagree --
    this still guards that get_diff's fix does not regress apply_file_v3's
    own, separate call path through OwnershipRules directly.
    """
    repo, proj = _mk_gitignore_v3(tmp_path, project_has_gitignore=True)
    res = json.loads(asyncio.run(ts.template_apply_file(str(proj), file_path=".gitignore")))
    assert res["action"] == "kept"


def test_apply_gitignore_absent_creates_from_template_REGRESSION_GUARD(tmp_path):
    """Green BEFORE the v4.0.1 fix too, and proves nothing about it (design
    spec item 3, constraint 5) -- the absent-file twin of the guard above."""
    repo, proj = _mk_gitignore_v3(tmp_path, project_has_gitignore=False)
    res = json.loads(asyncio.run(ts.template_apply_file(str(proj), file_path=".gitignore")))
    assert res["action"] == "created_from_template"
    assert (proj / ".gitignore").read_text(encoding="utf-8") == "*.log\n"


def test_template_path_for_agrees_with_every_target_rule_in_shipped_ownership(tmp_path):
    """v4.0.1 fix round 1, item F4: mcp._DOTFILE_MAP (hardcoded) and
    OwnershipRules' `target` fields in templates/ownership.json (data-driven,
    used by compute_status_v3 via rules.template_path_for) used to be two
    independently maintained dotfile mappings that could silently disagree.
    template_path_for() now derives from the loaded ownership rules whenever
    a manifest is given, so for every `target` rule the SHIPPED
    templates/ownership.json actually declares, the two are now provably one
    mapping, not two that happen to agree today.
    """
    repo_root = pathlib.Path(__file__).resolve().parents[2]
    manifest = {"templateRepo": str(repo_root), "variant": "general"}
    rules = v3.load_ownership(str(repo_root))
    assert rules is not None
    target_rules = [r for r in rules.rules if r.get("target")]
    assert target_rules, "no target rules in the shipped ownership.json -- fixture is vacuous"
    for rule in target_rules:
        assert ts.template_path_for(rule["target"], manifest) == rule["pattern"], rule


def test_template_path_for_generalizes_beyond_gitignore(tmp_path):
    """The generalization fixture: an ownership.json rule the hardcoded
    _DOTFILE_MAP has never heard of (npmrc -> .npmrc) still resolves through
    get_diff, because template_path_for() now asks the loaded ownership
    rules first. Before F4 this would have errored exactly like
    test_get_diff_resolves_dotfile_mapping did before item 3's original fix
    -- "Template file not found: .npmrc" -- since only ".gitignore" was ever
    hardcoded.
    """
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "general" / "npmrc").write_text("registry=x\n", encoding="utf-8", newline="")
    (repo / "templates" / "ownership.json").write_text(json.dumps({
        "tracked_paths": ["templates"],
        "rules": [{"pattern": "npmrc", "ownership": "once", "target": ".npmrc"}],
    }), encoding="utf-8")
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / ".npmrc").write_text("registry=x\nsave-exact=true\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general", "placeholders": {},
        "lastSynced": "", "files": {".npmrc": {"templateHash": ts._sha256("registry=x\n")}},
    }), encoding="utf-8")
    res = json.loads(asyncio.run(ts.template_get_diff(str(proj), ".npmrc", "full")))
    assert "error" not in res, res
    assert res.get("file_path") == ".npmrc"
