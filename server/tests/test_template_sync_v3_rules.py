"""Ownership rules: templates/ownership.json loader and glob matcher (review §2.3, §6.6)."""

import json

import pytest

from template_sync import v3


def _write_rules(tmp_path, data):
    repo = tmp_path / "toolkit"
    (repo / "templates").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(data), encoding="utf-8")
    return repo


@pytest.mark.parametrize("pattern,path,expected", [
    ("hooks/**", "hooks/gate.sh", True),
    ("hooks/**", "hooks/lib/git-cmd.sh", True),
    ("hooks/**", "hookshot.sh", False),
    (".claude/agents/*.md", ".claude/agents/coder.md", True),
    (".claude/agents/*.md", ".claude/agents/sub/coder.md", False),
    ("CLAUDE.md", "CLAUDE.md", True),
    ("CLAUDE.md", "CLAUDE.local.md", False),
    ("gitignore", "gitignore", True),
    ("*.md", "README.md", True),
    ("*.md", "docs/README.md", False),
])
def test_glob_to_regex(pattern, path, expected):
    assert bool(v3.glob_to_regex(pattern).match(path)) is expected


def test_load_ownership_returns_none_when_file_absent(tmp_path):
    (tmp_path / "toolkit").mkdir()
    assert v3.load_ownership(str(tmp_path / "toolkit")) is None


def test_first_match_wins_and_project_rule_silences(tmp_path):
    repo = _write_rules(tmp_path, {"rules": [
        {"pattern": ".claude/agents/local-*.md", "ownership": "project"},
        {"pattern": ".claude/agents/*.md", "ownership": "template"},
    ]})
    rules = v3.load_ownership(str(repo))
    assert rules.class_of(".claude/agents/local-notes.md") == "project"
    assert rules.class_of(".claude/agents/coder.md") == "template"
    assert rules.class_of("README.md") is None


def test_target_maps_both_directions(tmp_path):
    repo = _write_rules(tmp_path, {"rules": [
        {"pattern": "gitignore", "ownership": "once", "target": ".gitignore"},
        {"pattern": "CLAUDE.md", "ownership": "template"},
    ]})
    rules = v3.load_ownership(str(repo))
    assert rules.project_path_for("gitignore") == ".gitignore"
    assert rules.template_path_for(".gitignore") == "gitignore"
    assert rules.project_path_for("CLAUDE.md") == "CLAUDE.md"
    assert rules.template_path_for("CLAUDE.md") == "CLAUDE.md"


def test_tracked_paths_default_and_warning(tmp_path):
    repo = _write_rules(tmp_path, {"rules": [{"pattern": "hooks/**", "ownership": "template"}]})
    rules = v3.load_ownership(str(repo))
    assert rules.tracked_paths == ["templates", "hooks"]
    assert any("tracked_paths" in w for w in rules.warnings)

    repo2 = _write_rules(tmp_path / "b", {
        "tracked_paths": ["hooks", "scripts", "templates", "user-level-reference"],
        "rules": [],
    })
    rules2 = v3.load_ownership(str(repo2))
    assert rules2.tracked_paths == ["hooks", "scripts", "templates", "user-level-reference"]
    assert rules2.warnings == []


def test_malformed_rule_is_skipped_with_warning(tmp_path):
    repo = _write_rules(tmp_path, {"tracked_paths": ["templates"], "rules": [
        {"pattern": "CLAUDE.md"},
        {"pattern": "x.md", "ownership": "merge"},
        {"ownership": "template"},
        {"pattern": "hooks/**", "ownership": "template"},
    ]})
    rules = v3.load_ownership(str(repo))
    assert [r["pattern"] for r in rules.rules] == ["hooks/**"]
    assert len(rules.warnings) == 3


def test_template_class_rules_filters(tmp_path):
    repo = _write_rules(tmp_path, {"rules": [
        {"pattern": "hooks/**", "ownership": "template"},
        {"pattern": "PROJECT_CONTEXT.md", "ownership": "once"},
        {"pattern": "notes/*", "ownership": "project"},
    ]})
    rules = v3.load_ownership(str(repo))
    assert [r["pattern"] for r in rules.template_class_rules()] == ["hooks/**"]
