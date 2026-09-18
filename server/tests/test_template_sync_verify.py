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

import json
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync import v3
from template_sync import verify

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

CLAUDE_CONTENT = "# T\nrule one\n"
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
    # running server process was imported from.
    assert skip_ids == {"server_skew"}
    # v4.0.2 extends this to six: the three new INFO lines (legacy_gate_dir,
    # once_notes_changed, project_md_scoped_consistent) all emit their null
    # case on this healthy fixture -- none may SKIP here (a SKIP would be a
    # defect in the line, not grounds to widen this set).
    assert info_ids == {"template_behind_head", "encoding_drift", "project_md_seed_current",
                        "legacy_gate_dir", "once_notes_changed", "project_md_scoped_consistent"}

    n_pass = len(verify.LINES) - len(skip_ids) - len(info_ids) - len(fail_ids)
    assert res["summary"] == f"{n_pass} PASS, 0 FAIL, {len(skip_ids)} SKIP, {len(info_ids)} INFO"
    assert res["ok"] is True
    assert res["mode"] == "post_commit"


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


def test_manifest_version_3_fails_alone(tmp_path):
    repo, proj, commit = _good_fixture(tmp_path)
    m = _read_manifest(proj)
    m["manifest_version"] = 2
    m["version"] = 2
    _write_manifest(proj, m)
    _recommit(proj)
    res = verify.run(str(proj), str(repo), "post_commit")
    assert res["ok"] is False
    assert _only_fail(res) == ["manifest_version_3"]


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
    """Review round 1: a template-class manifest path compute_status_v3
    does not report at all (entry_status resolves to None via .get(...,
    {}).get("status")) must not raise -- sorting a mix of None and string
    unenumerated values crashes a plain sorted(set(...)) with TypeError."""
    repo, proj, commit = _good_fixture(tmp_path)
    real_compute = v3.compute_status_v3

    def _patched(pp, manifest, rules):
        result = real_compute(pp, manifest, rules)
        for path in list(result["files"]):
            if result["files"][path].get("ownership") == "template":
                del result["files"][path]
                break
        return result

    monkeypatch.setattr(v3, "compute_status_v3", _patched)
    res = verify.run(str(proj), str(repo), "post_commit")  # must not raise
    line = _by_id(res)["classes_and_hashes"]
    assert line["status"] == "FAIL", line
    assert "unenumerated=None" in line["measured"], line


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
    (V401_SEED, "predates", "n/a"),
    (V402_SEED, "current", "n/a"),
    ("---\npaths:\n  - \"src/**\"\n---\n# mine\n", "scoped", "clean"),
    ("---\npaths:\n  - \"src/**\"\n---\n" + V402_SEED, "scoped", "contradiction"),
])
def test_project_md_lines(tmp_path, body, seed, scoped):
    repo, proj, commit = _good_fixture(tmp_path)
    (proj / ".claude" / "rules" / "project.md").write_text(body, encoding="utf-8", newline="")
    _recommit(proj)
    by_id = _by_id(verify.run(str(proj), str(repo), "post_commit"))

    seed_map = {"stale": "pre-v4.0.1", "predates": "predates v4.0.2",
               "current": "seed is current", "scoped": "scoped"}
    scoped_map = {"n/a": "n/a", "clean": "no unscoped sentence", "contradiction": "still carries"}
    assert seed_map[seed] in by_id["project_md_seed_current"]["measured"], by_id["project_md_seed_current"]
    assert scoped_map[scoped] in by_id["project_md_scoped_consistent"]["measured"], \
        by_id["project_md_scoped_consistent"]


def test_project_md_remedies_hand_edit_and_move_hunks(tmp_path):
    """Both project_md_seed_current remedy arms (items 9, 11) say the
    consumer HAND-EDITS the once-class file the sync never writes, name the
    sentence that must be added, and tell a consumer migrated before
    v4.0.1 to move any migration hunks out of the header FIRST."""
    repo, proj, commit = _good_fixture(tmp_path)

    (proj / ".claude" / "rules" / "project.md").write_text(V401_SEED, encoding="utf-8", newline="")
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
