"""v3 statuses, key audit, and orphans (review §2.9, §5a, §5b, §7a-c, §8, §9a, §10, §11)."""

import asyncio
import json

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
    """Toolkit repo with templates/general + ownership.json, and a project with
    a v3 manifest. `template` maps template-relative path -> content (root-tracked
    hooks/** land at the repo root). `entries` maps project path -> manifest entry."""
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


AUDIT_RULE = OWNERSHIP["rules"][-1]


# --- Task 4: key audit --------------------------------------------------------


def test_parse_keys_first_occurrence_wins_and_list_marker():
    text = "# Ctx\n**Gate**: make check\n- **Test**: pytest\n**Gate**: other\nplain line\n"
    assert v3.parse_keys(text) == {"Gate": "make check", "Test": "pytest"}


def test_find_key_exact_qualified_alias():
    keys = {"Build (desktop)": "x", "Gate": "y", "Test Command": "z"}
    assert v3.find_key(keys, "Gate", AUDIT_RULE) == ["Gate"]
    assert v3.find_key(keys, "Build", AUDIT_RULE) == ["Build (desktop)"]
    assert v3.find_key(keys, "Test", AUDIT_RULE) == []


def test_exact_holdings_is_the_hooks_match():
    keys = {"Gate Command": "old", "Test (frontend unit)": "x", "Protected branches": "main"}
    assert v3.exact_holdings(keys, "Gate", AUDIT_RULE) == ["Gate Command"]
    assert v3.exact_holdings(keys, "Test", AUDIT_RULE) == []
    assert v3.exact_holdings(keys, "Protected branches", AUDIT_RULE) == ["Protected branches"]


def test_audit_reports_lists_and_required_detail():
    proj = ("- **Protected branches**: main\n**Gate Command**: old\n**Build (desktop)**: cargo build\n"
            "**Extra**: {{X}}\n**Mine**: 1\n")
    tpl = ("**Protected branches**: main master\n**Gate**: g\n**Test**: cargo test\n"
           "**Build**: cargo build\n**Extra**: {{X}}\n**Notes**: n\n")
    tpl_at_sync = "**Protected branches**: main\n**Gate**: g\n**Test**: cargo test\n**Build**: cargo build\n**Extra**: {{X}}\n"
    res = v3.audit_keys(proj, tpl, tpl_at_sync, AUDIT_RULE)
    assert res["missing_required"] == []                        # Gate held under its deprecated spelling
    assert res["qualified_only"] == []
    assert res["optional_absent"] == ["Test", "Notes"]          # Build satisfied by the qualified form
    assert res["placeholder_keys"] == ["Extra"]
    assert res["deprecated_keys"] == [{"key": "Gate Command", "replacement": "Gate"}]
    pb = res["required"]["Protected branches"]
    assert pb["value"] == "main"
    assert pb["matched_as"] == ["Protected branches"]
    assert pb["template_value"] == "main master"
    assert pb["template_value_at_sync"] == "main"
    assert pb["template_default_changed"] is True
    assert pb["consumer_holds_old_default"] is True
    assert res["required"]["Gate"]["matched_as"] == ["Gate Command"]
    assert res["warnings"] == []


def test_audit_required_qualified_only_is_its_own_state():
    # yutraffic: the hook matches **Test( Command)?**: exactly, so a qualified
    # holding of a REQUIRED key must never read as present (review §11b).
    proj = "**Protected branches**: main\n**Gate (frontend)**: g\n"
    tpl = "**Protected branches**: main\n**Gate**: g\n"
    res = v3.audit_keys(proj, tpl, None, AUDIT_RULE)
    assert res["missing_required"] == []
    assert res["qualified_only"] == [{
        "key": "Gate", "held_as": ["Gate (frontend)"],
        "note": "the hook matches **Gate**:/**Gate Command**: exactly and will not read it",
    }]
    assert "Gate" not in res["required"]
    res2 = v3.audit_keys("**Protected branches**: main\n", tpl, None, AUDIT_RULE)
    assert res2["missing_required"] == ["Gate"] and res2["qualified_only"] == []


def test_audit_without_base_omits_default_flags():
    text = "**Protected branches**: main\n**Gate**: g\n"
    res = v3.audit_keys(text, text, None, AUDIT_RULE)
    assert res["missing_required"] == []
    assert "template_default_changed" not in res["required"]["Gate"]
    assert res["warnings"] == ["audit_base_unavailable"]


def test_audit_placeholder_key_divergence():
    proj = "**Gate**: g\n**Test**: uv run pytest\n**Build (desktop)**: uv sync --extra dev\n"
    tpl = "**Gate**: g\n**Test**: t\n**Build**: b\n"
    res = v3.audit_keys(proj, tpl, None, AUDIT_RULE,
                        placeholders={"BUILD_COMMAND": "uv run pytest", "TEST_COMMAND": "uv  run pytest"})
    assert res["placeholder_key_divergence"] == [{
        "key": "Build (desktop)", "key_value": "uv sync --extra dev",
        "placeholder": "BUILD_COMMAND", "placeholder_value": "uv run pytest",
    }]                                     # Test matches after whitespace normalisation
    res2 = v3.audit_keys(proj, tpl, None, AUDIT_RULE, placeholders={})
    assert [d["placeholder_value"] for d in res2["placeholder_key_divergence"]] == [None, None]


def test_gate_refs_direct_only():
    rules = v3.OwnershipRules(OWNERSHIP["rules"], ["templates"], [])
    keys = {"Gate": "bash hooks/run-gate.sh --strict", "Test": "pytest -q", "Protected branches": "main master"}
    assert v3.gate_refs(keys, AUDIT_RULE, rules) == [{"key": "Gate", "path": "hooks/run-gate.sh"}]
    # ARM A (open-brain): a wrapper outside template class passes the static check.
    assert v3.gate_refs({"Gate": "bash scripts/gate.sh", "Test": "t"}, AUDIT_RULE, rules) == []
    assert v3.gate_refs({"Gate": "none", "Test": "true"}, AUDIT_RULE, rules) == []
    # open-brain's raw line: list marker + backticked value (review §11a).
    keys_bt = v3.parse_keys("- **Gate**: `bash ./hooks/run-gate.sh`\n**Protected branches**: main\n")
    assert v3.gate_refs(keys_bt, AUDIT_RULE, rules) == [{"key": "Gate", "path": "hooks/run-gate.sh"}]
    # Decoration is stripped from the deprecated spelling too.
    assert v3.gate_refs({"Gate Command": "`hooks/run-gate.sh`"}, AUDIT_RULE, rules) == [
        {"key": "Gate Command", "path": "hooks/run-gate.sh"}]


def test_collect_gate_refs(tmp_path):
    repo, proj = _mk_v3(tmp_path, template={},
                        project={"PROJECT_CONTEXT.md": "**Gate**: bash hooks/run-gate.sh\n**Test**: t\n"},
                        entries={})
    rules = v3.load_ownership(str(repo))
    assert v3.collect_gate_refs(proj, rules) == ([{"key": "Gate", "path": "hooks/run-gate.sh"}], True)
    (proj / "PROJECT_CONTEXT.md").write_text("**Test**: t\n", encoding="utf-8")
    assert v3.collect_gate_refs(proj, rules) == ([], False)


# --- Task 5: orphans, template notes, encoding flags --------------------------


def test_static_prefix():
    assert v3.static_prefix("hooks/**") == "hooks"
    assert v3.static_prefix(".claude/agents/*.md") == ".claude/agents"
    assert v3.static_prefix("CLAUDE.md") == "CLAUDE.md"
    assert v3.static_prefix("*.md") == ""


def test_find_orphans_matches_template_rules_only(tmp_path):
    repo, proj = _mk_v3(
        tmp_path,
        template={"hooks/gate.sh": "g", ".claude/agents/coder.md": "c"},
        project={
            "hooks/gate.sh": "g", "hooks/mine.sh": "m",
            ".claude/agents/coder.md": "c", ".claude/agents/game-tester.md": "t",
            ".claude/agents/local-notes.md": "n",
            ".claude/rules/project.md": "p", "src/main.py": "x",
            "preflight.sh": "gate logic on purpose\n",       # panoscribe's escape hatch (review §10c)
        },
        entries={"hooks/gate.sh": _tpl_entry("g"), ".claude/agents/coder.md": _tpl_entry("c")},
        ownership={"tracked_paths": ["templates", "hooks"],
                   "rules": OWNERSHIP["rules"] + [{"pattern": "*.sh", "ownership": "template"}]},
    )
    rules = v3.load_ownership(str(repo))
    orphans = v3.find_orphans(proj, rules, set(["hooks/gate.sh", ".claude/agents/coder.md"]),
                              set(["hooks/gate.sh", ".claude/agents/coder.md"]))
    assert orphans == [".claude/agents/game-tester.md", "hooks/mine.sh", "preflight.sh"]


def test_notes_hunks_skip_key_line_changes():
    old = "# Ctx\n<!-- how Gate is parsed -->\n**Gate**: a\n**Test**: t\n"
    new = "# Ctx\n<!-- how Gate and Test are parsed -->\n**Gate**: b\n**Test**: t\n"
    hunks = v3.notes_hunks(old, new)
    assert len(hunks) == 1
    assert "how Gate and Test are parsed" in hunks[0]
    assert "**Gate**: b" not in hunks[0]


def test_read_with_flags_and_drift(tmp_path):
    p = tmp_path / "f.txt"
    p.write_bytes(b"\xef\xbb\xbfa\r\nb\r\n")
    text, flags = v3.read_with_flags(p)
    assert text == "a\nb\n"
    assert flags == {"bom": True, "crlf": True}
    assert ts._sha256(text) == ts._sha256("a\nb\n")
    assert v3.encoding_drift(flags, {"bom": False, "crlf": False}) == ["bom", "crlf"]
    assert v3.encoding_drift(flags, flags) == []
    assert v3.read_with_flags(tmp_path / "missing") == (None, {"bom": False, "crlf": False})


# --- Task 6: template_compute_status v3 --------------------------------------


def _status(proj):
    return _run(ts.template_compute_status(str(proj)))


def test_template_status_matrix():
    h = ts._sha256("v1\n")
    assert v3.template_status(h, "v1\n", "v1\n") == ("IDENTICAL", None)
    assert v3.template_status(h, "v2\n", "v1\n") == ("TEMPLATE_UPDATED", None)
    status, diff = v3.template_status(h, "v1\n", "v1 edited\n")
    assert status == "LOCAL_EDITED" and "+v1 edited" in diff
    status, diff = v3.template_status(h, "v2\n", "v1 edited\n")
    assert status == "LOCAL_EDITED" and "-v2" in diff and "+v1 edited" in diff
    assert v3.template_status(h, None, "v1\n") == ("TEMPLATE_DELETED", None)
    assert v3.template_status(h, "v1\n", None) == ("TEMPLATE_UPDATED", None)


def test_compute_status_v3_classifies_every_class(tmp_path):
    repo, proj = _mk_v3(
        tmp_path,
        template={
            "CLAUDE.md": "# {{NAME}}\n", "hooks/gate.sh": "g2", ".claude/agents/coder.md": "c",
            ".claude/rules/project.md": "# Project instructions\n",
            "PROJECT_CONTEXT.md": "**Protected branches**: main\n**Gate**: g\n**Test**: t\n",
            ".claude/agents/new.md": "n", "gitignore": "*.log\n",
            "notes/x.md": "x", ".claude/settings.json": "{}",
        },
        project={
            "CLAUDE.md": "# Demo\n", "hooks/gate.sh": "g1", ".claude/agents/coder.md": "c edited",
            "PROJECT_CONTEXT.md": "**Protected branches**: main\n", ".claude/agents/game-tester.md": "t",
            ".claude/settings.json": "{}",
        },
        entries={
            "CLAUDE.md": _tpl_entry("# {{NAME}}\n", {"NAME": "Demo"}),
            "hooks/gate.sh": _tpl_entry("g1"),
            ".claude/agents/coder.md": _tpl_entry("c"),
            ".claude/settings.json": _tpl_entry("{}"),
            ".claude/rules/project.md": {"ownership": "once"},
            "PROJECT_CONTEXT.md": {"ownership": "once"},
        },
        placeholders={"NAME": "Demo"},
        ownership={"tracked_paths": ["templates", "hooks"], "rules": OWNERSHIP["rules"] + [
            {"pattern": "notes/*", "ownership": "project"},
        ]},
    )
    res = _status(proj)
    f = res["files"]
    assert f["CLAUDE.md"]["status"] == "IDENTICAL"
    assert f["hooks/gate.sh"]["status"] == "TEMPLATE_UPDATED"
    assert f[".claude/agents/coder.md"]["status"] == "LOCAL_EDITED"
    assert "+c edited" in f[".claude/agents/coder.md"]["local_diff"]
    assert f[".claude/settings.json"]["status"] == "IDENTICAL"
    assert f[".claude/rules/project.md"]["status"] == "MISSING"
    assert f["PROJECT_CONTEXT.md"]["status"] == "PRESENT"
    assert f["PROJECT_CONTEXT.md"]["key_audit"]["missing_required"] == ["Gate"]
    assert f["PROJECT_CONTEXT.md"]["key_audit"]["optional_absent"] == ["Test"]
    assert "audit_base_unavailable" in f["PROJECT_CONTEXT.md"]["key_audit"]["warnings"]
    assert res["new_template_files"] == [".claude/agents/new.md", ".gitignore"]
    assert res["unclassified_template_files"] == []
    assert res["orphans"] == [".claude/agents/game-tester.md"]
    assert res["summary"] == {
        "identical": 2, "template_updated": 1, "local_edited": 1, "template_deleted": 0,
        "present": 1, "missing": 1,
    }
    assert "CONFLICT" not in json.dumps(res)


def test_compute_status_v3_unclassified_and_deleted(tmp_path):
    repo, proj = _mk_v3(
        tmp_path,
        template={"CLAUDE.md": "x", "weird.toml": "w"},
        project={"CLAUDE.md": "x", "hooks/gone.sh": "old"},
        entries={"CLAUDE.md": _tpl_entry("x"), "hooks/gone.sh": _tpl_entry("old")},
    )
    res = _status(proj)
    assert res["unclassified_template_files"] == ["weird.toml"]
    assert res["files"]["hooks/gone.sh"]["status"] == "TEMPLATE_DELETED"
    assert res["deleted_template_files"] == ["hooks/gone.sh"]
    assert res["summary"]["template_deleted"] == 1
    assert res["gate_self_reference"] == [] and res["gate_unverified"] is False


def test_compute_status_v3_encoding_drift_and_gate(tmp_path):
    repo, proj = _mk_v3(
        tmp_path,
        template={"hooks/run-gate.sh": "g\n", ".prettierrc": "{}\n",
                  "PROJECT_CONTEXT.md": "**Protected branches**: main\n**Gate**: none\n**Test**: t\n"},
        project={"hooks/run-gate.sh": "g\r\n",
                 "PROJECT_CONTEXT.md": "**Protected branches**: main\n- **Gate**: `bash hooks/run-gate.sh`\n**Test**: t\n"},
        entries={"hooks/run-gate.sh": _tpl_entry("g\n"), ".prettierrc": {"ownership": "once"},
                 "PROJECT_CONTEXT.md": {"ownership": "once"}},
        ownership={"tracked_paths": ["templates", "hooks"],
                   "rules": OWNERSHIP["rules"] + [{"pattern": ".prettierrc", "ownership": "once"}]},
    )
    (proj / ".prettierrc").write_bytes(b"\xef\xbb\xbf{}\r\n")
    res = _status(proj)
    f = res["files"]
    assert f["hooks/run-gate.sh"]["status"] == "IDENTICAL"          # CRLF-only is never LOCAL_EDITED
    assert f["hooks/run-gate.sh"]["encoding_drift"] == ["crlf"]
    assert f[".prettierrc"]["status"] == "PRESENT"
    assert f[".prettierrc"]["encoding_drift"] == ["bom", "crlf"]
    assert f["PROJECT_CONTEXT.md"]["encoding_drift"] == []
    assert res["gate_self_reference"] == [{"key": "Gate", "path": "hooks/run-gate.sh"}]
    assert res["gate_unverified"] is True


def test_diff_kind_insertion_vs_mixed():
    ins = v3._unified("a\nb\n", "a\nx\nb\ny\n", "template", "project")
    assert v3.diff_kind(ins) == "insertion"
    mixed = v3._unified("a\nb\n", "a\nc\n", "template", "project")
    assert v3.diff_kind(mixed) == "mixed"
    deletion = v3._unified("a\nb\n", "a\n", "template", "project")
    assert v3.diff_kind(deletion) == "mixed"
    assert v3.diff_kind("") == "mixed"


def test_compute_status_v3_local_diff_kind(tmp_path):
    # MM-Agent (batch 10): a project rule that landed outside the region is a
    # pure insertion -- the skill prints the "move it to project.md" remedy only then.
    repo, proj = _mk_v3(
        tmp_path,
        template={"CLAUDE.md": "# T\nrule 1\n", ".claude/agents/coder.md": "c\n"},
        project={"CLAUDE.md": "# T\nrule 1\nmy project rule\n", ".claude/agents/coder.md": "c edited\n"},
        entries={"CLAUDE.md": _tpl_entry("# T\nrule 1\n"), ".claude/agents/coder.md": _tpl_entry("c\n")},
    )
    res = _status(proj)
    f = res["files"]
    assert f["CLAUDE.md"]["status"] == "LOCAL_EDITED"
    assert f["CLAUDE.md"]["local_diff_kind"] == "insertion"
    assert f[".claude/agents/coder.md"]["status"] == "LOCAL_EDITED"
    assert f[".claude/agents/coder.md"]["local_diff_kind"] == "mixed"


def test_compute_status_v3_root_consumer_file_stays_project(tmp_path):
    # panoscribe's escape hatch (review §10c): a root-level consumer file that
    # matches a template-class rule but has no manifest entry is never in
    # `files`, never diffed, never applied -- listed only under orphans.
    repo, proj = _mk_v3(
        tmp_path, template={"CLAUDE.md": "x"},
        project={"CLAUDE.md": "x", "preflight.sh": "gate logic on purpose\n"},
        entries={"CLAUDE.md": _tpl_entry("x")},
        ownership={"tracked_paths": ["templates", "hooks"],
                   "rules": OWNERSHIP["rules"] + [{"pattern": "*.sh", "ownership": "template"}]},
    )
    res = _status(proj)
    assert "preflight.sh" not in res["files"]
    assert res["orphans"] == ["preflight.sh"]
    assert res["new_template_files"] == []
