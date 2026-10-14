"""templateRepo fallback (v4.5.1, item 3).

A project's committed .claude/template-manifest.json stores templateRepo as
the absolute path of the machine that wrote it ("G:/git/claude-code-toolkit").
On any other host that path does not exist and every manifest-based call used
to fail. When the declared repo is not an existing directory here, the server
falls back to the toolkit checkout it itself runs from, says so in the tool
output, and never writes the fallback back into the manifest.
"""

import asyncio
import json
import pathlib

import pytest

from template_sync import mcp as ts
from template_sync import v3

MISSING = "G:/git/claude-code-toolkit-does-not-exist"


def _toolkit(root: pathlib.Path) -> pathlib.Path:
    (root / "templates" / "general").mkdir(parents=True)
    (root / "user-level-reference").mkdir(parents=True)
    return root


def _project(tmp_path: pathlib.Path, template_repo: str) -> tuple[pathlib.Path, pathlib.Path, bytes]:
    pp = tmp_path / "proj"
    (pp / ".claude").mkdir(parents=True)
    mf = pp / ".claude" / "template-manifest.json"
    mf.write_text(json.dumps({
        "version": 2, "variant": "general", "templateRepo": template_repo,
        "placeholders": {}, "files": {}, "lastSynced": "",
    }), encoding="utf-8")
    return pp, mf, mf.read_bytes()


def _load(pp: pathlib.Path) -> dict:
    return json.loads(asyncio.run(ts.template_load_manifest(str(pp), skill_version="v99.0.0")))


def test_existing_template_repo_is_used_unchanged(tmp_path, monkeypatch):
    repo = _toolkit(tmp_path / "declared")
    other = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: other)
    pp, _, _ = _project(tmp_path, str(repo))
    res = _load(pp)
    assert "template_repo_note" not in res
    assert not any("Template directory not found" in e for e in res["errors"])
    assert ts._get_template_dir({"templateRepo": str(repo), "variant": "general"}) == repo.resolve() / "templates" / "general"


def test_missing_repo_falls_back_to_server_checkout_with_note(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    pp, _, _ = _project(tmp_path, MISSING)
    res = _load(pp)
    assert not any("Template directory not found" in e for e in res["errors"])
    assert res["template_repo_note"] == (
        f"templateRepo {MISSING} not found on this machine; using the server's own checkout {checkout}")
    assert ts._template_repo_resolved({"templateRepo": MISSING}) == str(checkout)
    assert ts._get_template_dir({"templateRepo": MISSING, "variant": "general"}) == checkout / "templates" / "general"


def test_every_resolution_site_uses_the_fallback(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    # load_ownership reads <repo>/templates/ownership.json: the path it asks for proves what it resolved
    seen = {}
    real = v3.core._read_file
    monkeypatch.setattr(v3.core, "_read_file", lambda p: seen.setdefault("p", pathlib.Path(p)) and real(p))
    v3.load_ownership(MISSING)
    assert seen["p"] == checkout / "templates" / "ownership.json"
    assert ts._template_file_path({"templateRepo": MISSING, "variant": "general"}, "hooks/git-pre-push.sh") == checkout / "hooks" / "git-pre-push.sh"


def test_missing_repo_and_server_outside_a_checkout_keeps_todays_error(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    pp, _, _ = _project(tmp_path, MISSING)
    res = _load(pp)
    assert "template_repo_note" not in res
    assert any("Template directory not found" in e for e in res["errors"])


def test_manifest_file_is_never_modified(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    pp, mf, before = _project(tmp_path, MISSING)
    mtime = mf.stat().st_mtime_ns
    _load(pp)
    json.loads(asyncio.run(ts.template_compute_status(str(pp))))
    assert mf.read_bytes() == before
    assert mf.stat().st_mtime_ns == mtime


def test_server_toolkit_root_is_derived_from_the_package_location(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "tk")
    src = checkout / "server" / "src" / "template_sync"
    src.mkdir(parents=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(src))
    assert ts._server_toolkit_root() == checkout
    bare = tmp_path / "site-packages" / "template_sync"
    bare.mkdir(parents=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(bare))
    assert ts._server_toolkit_root() is None


# --- v4.5.1 round 2: effective_template_repo + corrected server_in_template_repo ---

def _server_inside(checkout: pathlib.Path, monkeypatch) -> None:
    src = checkout / "server" / "src" / "template_sync"
    src.mkdir(parents=True, exist_ok=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(src))
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)


def test_effective_key_declared_exists_is_verbatim_and_no_note(tmp_path, monkeypatch):
    repo = _toolkit(tmp_path / "declared")
    _server_inside(_toolkit(tmp_path / "server-checkout"), monkeypatch)
    declared = str(repo) + "/"          # a spelling str(Path) would normalise away
    pp, mf, before = _project(tmp_path, declared)
    res = _load(pp)
    assert res["effective_template_repo"] == declared
    assert "template_repo_note" not in res
    assert mf.read_bytes() == before


def test_effective_key_fallback_is_posix_root_with_note_and_server_in_repo(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _server_inside(checkout, monkeypatch)
    pp, mf, before = _project(tmp_path, MISSING)
    res = _load(pp)
    assert res["effective_template_repo"] == checkout.as_posix()
    assert res["effective_template_repo"] != MISSING
    assert res["template_repo_note"]
    assert res["server_in_template_repo"] is True
    assert res["templateRepo"] == MISSING            # declared value still reported as-is
    assert mf.read_bytes() == before


def test_effective_key_no_toolkit_root_is_declared_verbatim_and_server_not_in_repo(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    pp, mf, before = _project(tmp_path, MISSING)
    res = _load(pp)
    assert res["effective_template_repo"] == MISSING
    assert "template_repo_note" not in res
    assert res["server_in_template_repo"] is False
    assert mf.read_bytes() == before


def test_effective_key_present_on_invalid_manifest_returns(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _server_inside(checkout, monkeypatch)
    # no manifest at all -> null
    empty = tmp_path / "empty"
    empty.mkdir()
    res = _load(empty)
    assert "effective_template_repo" in res and res["effective_template_repo"] is None
    # manifest with a validation error but a templateRepo -> the string
    pp, mf, before = _project(tmp_path, MISSING)
    broken = json.loads(before)
    del broken["variant"]
    mf.write_text(json.dumps(broken), encoding="utf-8")
    res = _load(pp)
    assert res["valid"] is False
    assert res["effective_template_repo"] == checkout.as_posix()


def test_effective_key_on_a_v3_manifest_where_real_consumers_land(tmp_path, monkeypatch):
    """The manifest_supported (v3/v4) return branch, not the v2 one."""
    checkout = _toolkit(tmp_path / "server-checkout")
    (checkout / "templates" / "ownership.json").write_text(json.dumps(_v3_ownership()), encoding="utf-8")
    declared_repo = _toolkit(tmp_path / "declared")
    (declared_repo / "templates" / "ownership.json").write_text(json.dumps(_v3_ownership()), encoding="utf-8")
    _server_inside(checkout, monkeypatch)

    def mk(name: str, repo: str) -> tuple[pathlib.Path, bytes]:
        pp = tmp_path / name
        (pp / ".claude").mkdir(parents=True)
        mf = pp / ".claude" / "template-manifest.json"
        mf.write_text(json.dumps({
            "manifest_version": 3, "template_version": "3.1.0", "template_commit": "0000000",
            "variant": "general", "templateRepo": repo, "placeholders": {},
            "requires_server": ">=0.3.0", "files": {}}), encoding="utf-8")
        return pp, mf.read_bytes()

    pp, before = mk("p-fallback", MISSING)
    res = _load(pp)
    assert res["manifest_version"] == 3 and "unknown_keys" in res      # really the v3/v4 branch
    assert res["effective_template_repo"] == checkout.as_posix()
    assert res["template_repo_note"] and res["server_in_template_repo"] is True
    assert (pp / ".claude" / "template-manifest.json").read_bytes() == before

    declared = str(declared_repo) + "/"
    pp, before = mk("p-declared", declared)
    res = _load(pp)
    assert res["manifest_version"] == 3 and "unknown_keys" in res
    assert res["effective_template_repo"] == declared
    assert "template_repo_note" not in res
    assert (pp / ".claude" / "template-manifest.json").read_bytes() == before


def test_server_in_template_repo_true_on_fallback_false_without_root(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _server_inside(checkout, monkeypatch)
    assert ts._server_in_template_repo(MISSING) is True
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    assert ts._server_in_template_repo(MISSING) is False


@pytest.mark.parametrize("only", ["user-level-reference", "templates"])
def test_a_directory_with_only_one_marker_is_not_a_fallback_root(tmp_path, monkeypatch, only):
    half = tmp_path / "half"
    (half / only).mkdir(parents=True)
    src = half / "server" / "src" / "template_sync"
    src.mkdir(parents=True)
    monkeypatch.setattr(ts, "SERVER_SOURCE_DIR", str(src))
    assert ts._server_toolkit_root() is None
    # negative control: adding the other marker makes it a root
    (half / ("templates" if only == "user-level-reference" else "user-level-reference")).mkdir()
    assert ts._server_toolkit_root() == half.resolve()


def _v3_ownership() -> dict:
    return {"tracked_paths": ["hooks", "templates"],
            "rules": [{"pattern": "hooks/**", "ownership": "template"}]}


def test_compute_status_scan_sites_use_the_fallback(tmp_path, monkeypatch):
    """mcp.py _scan_template_files call (v2) and v3.compute_status_v3 repo_root:
    a root-tracked hooks/ file exists ONLY in the fallback checkout."""
    checkout = _toolkit(tmp_path / "server-checkout")
    (checkout / "hooks").mkdir()
    (checkout / "hooks" / "git-pre-push.sh").write_text("#!/bin/sh\n", encoding="utf-8")
    _server_inside(checkout, monkeypatch)

    pp, mf, before = _project(tmp_path, MISSING)                       # v2 manifest, no ownership.json
    res = json.loads(asyncio.run(ts.template_compute_status(str(pp))))
    assert "hooks/git-pre-push.sh" in res["new_template_files"], res
    assert mf.read_bytes() == before

    (checkout / "templates" / "ownership.json").write_text(json.dumps(_v3_ownership()), encoding="utf-8")
    pp3 = tmp_path / "proj3"
    (pp3 / ".claude").mkdir(parents=True)
    mf3 = pp3 / ".claude" / "template-manifest.json"
    mf3.write_text(json.dumps({
        "manifest_version": 3, "template_version": "3.1.0", "template_commit": "0000000",
        "variant": "general", "templateRepo": MISSING, "placeholders": {},
        "requires_server": ">=0.3.0", "files": {}}), encoding="utf-8")
    before3 = mf3.read_bytes()
    res3 = json.loads(asyncio.run(ts.template_compute_status(str(pp3))))
    assert "hooks/git-pre-push.sh" in res3["new_template_files"], res3
    assert mf3.read_bytes() == before3

    # negative control: with no fallback root the same call does not see the file
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    res_none = json.loads(asyncio.run(ts.template_compute_status(str(pp))))
    assert "hooks/git-pre-push.sh" not in json.dumps(res_none)


def test_run_git_treats_any_oserror_as_a_failed_call(monkeypatch):
    # A missing cwd is FileNotFoundError on Linux but NotADirectoryError
    # (WinError 267) on Windows; both must come back as a failed git call.
    def boom(*a, **k):
        raise NotADirectoryError(267, "The directory name is invalid")

    monkeypatch.setattr(ts.subprocess, "run", boom)
    r = ts._run_git(["rev-parse", "--short", "HEAD"], cwd="x")
    assert r["exit_code"] == 1


# --- v4.5.2: check_cross_variant / propagate_to_variants use the fallback ---

def _variants(root: pathlib.Path, content: str = "x\n") -> None:
    for v in ("general", "python"):
        (root / "templates" / v).mkdir(parents=True, exist_ok=True)
        (root / "templates" / v / "A.md").write_text(content, encoding="utf-8")


def _cross(repo: str) -> dict:
    return json.loads(asyncio.run(ts.template_check_cross_variant(repo, "general", "A.md")))


def _propagate(repo: str, variants: str = '["general"]') -> dict:
    return json.loads(asyncio.run(ts.template_propagate_to_variants(repo, "A.md", "new\n", variants)))


def test_cross_variant_falls_back_with_note(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _variants(checkout)
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    res = _cross(MISSING)
    assert "error" not in res and "general" in res["variants_identical"]
    assert "template_repo_note" in res


def test_cross_variant_existing_repo_has_no_note(tmp_path, monkeypatch):
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: _toolkit(tmp_path / "other"))
    res = _cross(str(repo))
    assert "error" not in res and "template_repo_note" not in res


def test_propagate_falls_back_with_note(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _variants(checkout)
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)
    monkeypatch.chdir(tmp_path)
    res = _propagate(MISSING)
    assert res["written_to"] == ["general"] and "template_repo_note" in res
    assert (checkout / "templates" / "general" / "A.md").read_text(encoding="utf-8") == "new\n"
    # Not `tmp_path / "G:"`: on Windows that join yields the drive G: itself.
    assert [p.name for p in tmp_path.iterdir()] == ["server-checkout"]


def test_propagate_existing_repo_has_no_note(tmp_path, monkeypatch):
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: _toolkit(tmp_path / "other"))
    res = _propagate(str(repo))
    assert res["written_to"] == ["general"] and "template_repo_note" not in res


def test_propagate_nonexistent_repo_no_fallback_writes_nothing(tmp_path, monkeypatch):
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: None)
    monkeypatch.chdir(tmp_path)
    res = _propagate(MISSING)
    assert "error" in res
    assert list(tmp_path.iterdir()) == []


def test_repo_note_does_not_leak_into_next_call(tmp_path, monkeypatch):
    checkout = _toolkit(tmp_path / "server-checkout")
    _variants(checkout)
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    monkeypatch.setattr(ts, "_server_toolkit_root", lambda: checkout)

    async def both():
        first = json.loads(await ts.template_check_cross_variant(MISSING, "general", "A.md"))
        second = json.loads(await ts.template_check_cross_variant(str(repo), "general", "A.md"))
        return first, second
    first, second = asyncio.run(both())
    assert "template_repo_note" in first
    assert "template_repo_note" not in second


# --- v4.5.2 review: input validation before any write ---

@pytest.mark.parametrize("bad_path", ["/etc/x.md", "\\abs.md", "../A.md", "a/../../A.md", "a\\..\\..\\A.md", "C:\\x.md"])
def test_propagate_refuses_unsafe_file_path_and_writes_nothing(tmp_path, bad_path):
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    res = json.loads(asyncio.run(ts.template_propagate_to_variants(str(repo), bad_path, "new\n", '["general", "python"]')))
    assert "error" in res and "written_to" not in res
    assert (repo / "templates" / "general" / "A.md").read_text(encoding="utf-8") == "x\n"
    assert not (tmp_path / "A.md").exists()


@pytest.mark.parametrize("variants", ['["general", "../evil"]', '["nope"]', '["general", 3]', '"general"'])
def test_propagate_refuses_unknown_variant_before_any_write(tmp_path, variants):
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    res = json.loads(asyncio.run(ts.template_propagate_to_variants(str(repo), "A.md", "new\n", variants)))
    assert "error" in res and "written_to" not in res
    assert (repo / "templates" / "general" / "A.md").read_text(encoding="utf-8") == "x\n"
    assert not (repo / "templates" / "evil").exists() and not (repo / "evil").exists()


@pytest.mark.parametrize("bad_path", ["/etc/passwd", "../A.md", "a\\..\\A.md"])
def test_cross_variant_refuses_unsafe_file_path(tmp_path, bad_path):
    repo = _toolkit(tmp_path / "declared")
    _variants(repo)
    res = json.loads(asyncio.run(ts.template_check_cross_variant(str(repo), "general", bad_path)))
    assert "error" in res and "is_shared" not in res
