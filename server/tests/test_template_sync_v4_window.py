"""The v3-manifest window: MIGRATION_REQUIRED and the CLAUDE.md refusal
(v4.1 plan Task 1 commit 4 -- spec §7, ruling R-J, reviewer F3).

A v4.1+ server serving a consumer whose manifest is still v3 must not apply a
region-less template CLAUDE.md over a consumer whose project content still
lives in the region. Detected against the CURRENT checkout's template, never
the held commit (a v3 consumer's held commit always carries the region) --
so a LEGACY v3 consumer (synced from a pre-v4.1, region-carrying checkout) is
NOT in the window and behaves exactly as before (the two-sided witness at the
bottom of this file).
"""

import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3
from template_sync import verify

OWNERSHIP = {
    "tracked_paths": ["templates"],
    "rules": [
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/rules/project.md", "ownership": "once"},
    ],
}

REGION = "<!-- PROJECT-CUSTOM:BEGIN -->\n<!-- PROJECT-CUSTOM:END -->\n"
LEGACY_CLAUDE = "# T\nrule one\n" + REGION
WINDOW_CLAUDE = "# T\nrule one\n@.claude/project-instructions.md\n"  # no markers -- the v4.1 shape


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _init_repo(repo):
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "init")
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()


def _mk_v3_fixture(tmp_path, claude_template_content: str):
    repo = tmp_path / "toolkit"
    (repo / "templates" / "general").mkdir(parents=True)
    (repo / "templates" / "ownership.json").write_text(json.dumps(OWNERSHIP), encoding="utf-8")
    (repo / "templates" / "general" / "CLAUDE.md").write_text(
        claude_template_content, encoding="utf-8", newline="")
    commit = _init_repo(repo)

    proj = tmp_path / "proj"
    (proj / ".claude" / "rules").mkdir(parents=True)
    # The project's held CLAUDE.md always carries the region (R-J: a v3
    # consumer's own committed copy always has it -- the window is a
    # property of the CURRENT template, never the consumer's held file).
    (proj / "CLAUDE.md").write_text(LEGACY_CLAUDE, encoding="utf-8", newline="")
    (proj / ".claude" / "rules" / "project.md").write_text("rules\n", encoding="utf-8", newline="")
    manifest = {
        "manifest_version": 3,
        "template_version": "v3.1.0",
        "template_commit": commit,
        "variant": "general",
        "templateRepo": str(repo),
        "placeholders": {},
        "requires_server": ">=0.3.2",
        "files": {
            "CLAUDE.md": {"hash": "sha256:" + ts._sha256(LEGACY_CLAUDE), "ownership": "template"},
            ".claude/rules/project.md": {"ownership": "once"},
        },
    }
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps(manifest), encoding="utf-8", newline="")
    _init_repo(proj)
    return repo, proj, manifest


def _rules(repo):
    return v3.load_ownership(str(repo))


# --- compute_status_v3 --------------------------------------------------


def test_window_active_when_v3_and_current_template_has_no_markers(tmp_path):
    repo, proj, manifest = _mk_v3_fixture(tmp_path, WINDOW_CLAUDE)
    rules = _rules(repo)
    status = v3.compute_status_v3(proj, manifest, rules)
    info = status["files"]["CLAUDE.md"]
    assert info["status"] == "MIGRATION_REQUIRED", info
    assert info["remedy"] == v3.MIGRATION_REQUIRED_REMEDY
    assert status["summary"]["migration_required"] == 1


def test_window_inactive_for_a_legacy_v3_consumer(tmp_path):
    """Two-sided: the SAME manifest version, a template that still carries
    the region (a v4.0.x toolkit checkout) -> NOT in the window, CLAUDE.md
    reads its ordinary status."""
    repo, proj, manifest = _mk_v3_fixture(tmp_path, LEGACY_CLAUDE)
    rules = _rules(repo)
    status = v3.compute_status_v3(proj, manifest, rules)
    info = status["files"]["CLAUDE.md"]
    assert info["status"] == "IDENTICAL", info
    assert status["summary"]["migration_required"] == 0


def test_window_predicate_direct():
    assert v3.claude_md_window_active({"manifest_version": 3}, "CLAUDE.md", WINDOW_CLAUDE) is True
    assert v3.claude_md_window_active({"manifest_version": 3}, "CLAUDE.md", LEGACY_CLAUDE) is False
    # Not CLAUDE.md -- never active regardless of markers.
    assert v3.claude_md_window_active({"manifest_version": 3}, "AGENT_TEAM.md", WINDOW_CLAUDE) is False
    # v4 manifest -- never active (the window is specifically about a v3
    # manifest meeting a v4.1 template).
    assert v3.claude_md_window_active({"manifest_version": 4}, "CLAUDE.md", WINDOW_CLAUDE) is False
    # tpl_raw None (template no longer ships the file) -- never active.
    assert v3.claude_md_window_active({"manifest_version": 3}, "CLAUDE.md", None) is False


# --- classes_and_hashes PASS while CLAUDE.md reads MIGRATION_REQUIRED ------


def test_classes_and_hashes_passes_explicitly_while_claude_md_is_migration_required(tmp_path):
    """Reviewer criterion 1: assert the PASS status explicitly, not 'did not
    crash'."""
    repo, proj, manifest = _mk_v3_fixture(tmp_path, WINDOW_CLAUDE)
    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = {l["id"]: l for l in res["lines"]}
    assert by_id["classes_and_hashes"]["status"] == "PASS", by_id["classes_and_hashes"]
    assert "migration_required=1" in by_id["classes_and_hashes"]["measured"]


def test_status_clean_fails_naming_claude_md_with_the_remedy(tmp_path):
    repo, proj, manifest = _mk_v3_fixture(tmp_path, WINDOW_CLAUDE)
    res = verify.run(str(proj), str(repo), "post_commit")
    by_id = {l["id"]: l for l in res["lines"]}
    line = by_id["status_clean"]
    assert line["status"] == "FAIL", line
    assert "CLAUDE.md" in line["measured"]
    assert line["remedy"] == v3.MIGRATION_REQUIRED_REMEDY


# --- apply refusal --------------------------------------------------------


def test_apply_refused_in_the_window_region_bytes_intact(tmp_path):
    repo, proj, manifest = _mk_v3_fixture(tmp_path, WINDOW_CLAUDE)
    rules = _rules(repo)
    before = (proj / "CLAUDE.md").read_bytes()
    res = v3.apply_file_v3(proj, manifest, rules, "CLAUDE.md", "template", "", "")
    assert "error" in res, res
    assert "CLAUDE.md" in res["error"] and "migrate first" in res["error"]
    after = (proj / "CLAUDE.md").read_bytes()
    assert after == before, "the region body on disk must be byte-identical before and after"


def test_apply_not_refused_for_a_legacy_v3_consumer(tmp_path):
    repo, proj, manifest = _mk_v3_fixture(tmp_path, LEGACY_CLAUDE)
    rules = _rules(repo)
    res = v3.apply_file_v3(proj, manifest, rules, "CLAUDE.md", "template", "", "")
    assert "error" not in res, res
