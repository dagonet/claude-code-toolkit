"""Path-resolution tests for template_sync_mcp.

Regression coverage for the hooks-at-repo-root bug: shared hook scripts live
at <repo>/hooks/, not templates/<variant>/hooks/. Before the fix, the sync
tool resolved every tracked path against templates/<variant>/ and reported
root-tracked hooks as TEMPLATE_DELETED.
"""

import pathlib

from template_sync import mcp as ts


def _manifest(repo: str, variant: str = "rust-tauri") -> dict:
    return {"templateRepo": repo, "variant": variant, "placeholders": {}, "files": {}}


def test_is_root_tracked_only_for_hooks():
    assert ts._is_root_tracked("hooks/no-push-main.sh")
    assert ts._is_root_tracked("hooks/nested/x.sh")
    assert not ts._is_root_tracked("CLAUDE.md")
    assert not ts._is_root_tracked(".claude/agents/coder.md")
    # A variant-local path that merely contains "hooks" later must not match.
    assert not ts._is_root_tracked(".claude/hooks/x.sh")


def test_hook_path_resolves_to_repo_root(tmp_path):
    repo = tmp_path
    (repo / "hooks").mkdir()
    (repo / "hooks" / "no-push-main.sh").write_text("#!/usr/bin/env bash\n")
    (repo / "templates" / "rust-tauri").mkdir(parents=True)

    m = _manifest(str(repo))
    resolved = ts._template_file_path(m, "hooks/no-push-main.sh")

    assert resolved == (repo / "hooks" / "no-push-main.sh").resolve()
    assert ts._read_file(resolved) is not None  # not seen as deleted


def test_scan_discovers_new_root_tracked_hooks(tmp_path):
    """Discovery must walk <repo>/hooks/** too, or new hooks never surface.

    A new root-tracked hook that is absent from the manifest was invisible to
    `template_compute_status`: `_scan_template_files` only walked the variant
    dir, so `new_template_files` never listed it and the v2 git gates shipped
    without their sourced lib -- failing open.
    """
    repo = tmp_path
    vdir = repo / "templates" / "rust-tauri"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text("# hi\n")
    (repo / "hooks" / "lib").mkdir(parents=True)
    (repo / "hooks" / "retro-ledger.sh").write_text("#!/usr/bin/env bash\n")
    (repo / "hooks" / "lib" / "git-cmd.sh").write_text("#!/usr/bin/env bash\n")

    found = ts._scan_template_files(vdir, repo)

    assert "CLAUDE.md" in found
    assert "hooks/retro-ledger.sh" in found
    assert "hooks/lib/git-cmd.sh" in found
    assert found == sorted(set(found))


def test_compute_status_lists_new_root_hooks(tmp_path):
    """Integration: the tool's own JSON must carry the new root hook.

    The unit test above still passes if `template_compute_status` forgets to
    pass `repo_root` -- this one pins the call site.
    """
    import asyncio
    import json

    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text("# hi\n", encoding="utf-8", newline="")
    (repo / "hooks" / "lib").mkdir(parents=True)
    (repo / "hooks" / "retro-ledger.sh").write_text(
        "#!/usr/bin/env bash\n", encoding="utf-8", newline=""
    )
    (repo / "hooks" / "lib" / "git-cmd.sh").write_text(
        "#!/usr/bin/env bash\n", encoding="utf-8", newline=""
    )

    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text("# hi\n", encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps({
            "version": 2,
            "templateRepo": str(repo),
            "variant": "general",
            "lastSynced": "",
            "placeholders": {},
            "files": {},
        }),
        encoding="utf-8",
        newline="",
    )

    res = json.loads(asyncio.run(ts.template_compute_status(str(proj))))

    assert "hooks/retro-ledger.sh" in res["new_template_files"]
    assert "hooks/lib/git-cmd.sh" in res["new_template_files"]
    assert "CLAUDE.md" in res["new_template_files"]


def test_scan_without_repo_root_stays_variant_only(tmp_path):
    repo = tmp_path
    vdir = repo / "templates" / "rust-tauri"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text("# hi\n")
    (repo / "hooks").mkdir()
    (repo / "hooks" / "retro-ledger.sh").write_text("#!/usr/bin/env bash\n")

    assert ts._scan_template_files(vdir) == ["CLAUDE.md"]


def test_discovered_root_hook_still_applies_against_repo_root(tmp_path):
    """Detection change must not disturb the existing resolution behaviour."""
    repo = tmp_path
    (repo / "templates" / "rust-tauri").mkdir(parents=True)
    (repo / "hooks" / "lib").mkdir(parents=True)
    (repo / "hooks" / "lib" / "git-cmd.sh").write_text("gc_guard_off() { return 1; }\n")

    m = _manifest(str(repo))
    resolved = ts._template_file_path(m, "hooks/lib/git-cmd.sh")

    assert resolved == (repo / "hooks" / "lib" / "git-cmd.sh").resolve()
    assert ts._read_file(resolved) == "gc_guard_off() { return 1; }\n"


def test_variant_file_resolves_to_variant_dir(tmp_path):
    repo = tmp_path
    vdir = repo / "templates" / "rust-tauri"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text("# hi\n")

    m = _manifest(str(repo))
    resolved = ts._template_file_path(m, "CLAUDE.md")

    assert resolved == (vdir / "CLAUDE.md").resolve()


def test_git_path_root_tracked_vs_variant():
    m = _manifest("/whatever", variant="java")
    assert ts._template_git_path(m, "hooks/no-push-main.sh") == "hooks/no-push-main.sh"
    assert ts._template_git_path(m, "CLAUDE.md") == "templates/java/CLAUDE.md"


def test_real_toolkit_hooks_not_deleted():
    """If the toolkit checkout is present, every shipped hook must resolve."""
    repo = pathlib.Path("G:/git/claude-code-toolkit")
    if not (repo / "hooks").is_dir():
        import pytest

        pytest.skip("toolkit checkout not present")
    m = _manifest(str(repo))
    for hook in (repo / "hooks").glob("*.sh"):
        rel = f"hooks/{hook.name}"
        assert ts._read_file(ts._template_file_path(m, rel)) is not None, rel
