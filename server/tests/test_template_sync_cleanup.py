"""Manifest cleanup and git-output encoding tests.

Consumer findings (Yutraffic-Challenge, 2026-08-29):
- H4: manifest entries for template-deleted files that the project also
  removed persisted forever, so every later status reported the same
  `template_deleted` count.
- H5: `git show` output was decoded with the Windows locale codec, so a
  template em dash came back as mojibake in the reconstructed merge base.
"""

import asyncio
import json
import shutil
import subprocess

import pytest

from template_sync import mcp as ts


def _mk(tmp_path, tracked: dict[str, str], project_files: dict[str, str]):
    """Build a toolkit repo + project. `tracked` maps rel path -> template
    content, or None when the template no longer ships the file."""
    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)

    files = {}
    for rel, content in tracked.items():
        if content is not None:
            target = ts._template_file_path(
                {"templateRepo": str(repo), "variant": "general"}, rel
            )
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(content, encoding="utf-8", newline="")
        files[rel] = {
            "templateHash": ts._sha256(content or ""),
            "templateRawHash": ts._sha256(content or ""),
            "localHash": ts._sha256(content or ""),
            "locallyModified": False,
        }
    for rel, content in project_files.items():
        p = proj / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8", newline="")

    (proj / ".claude" / "template-manifest.json").write_text(
        json.dumps({
            "version": 2,
            "templateRepo": str(repo),
            "variant": "general",
            "lastSynced": "abc1234",
            "placeholders": {},
            "files": files,
        }),
        encoding="utf-8",
        newline="",
    )
    return repo, proj


def _finalize(proj, **kwargs):
    return json.loads(asyncio.run(ts.template_finalize_sync(str(proj), "[]", **kwargs)))


def _manifest_files(proj):
    raw = (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8")
    return json.loads(raw)["files"]


# --- H4: dropping dead manifest entries -------------------------------------


def test_entry_dropped_when_template_and_project_both_lack_the_file(tmp_path):
    _, proj = _mk(
        tmp_path,
        tracked={"hooks/block-bash-vcs.sh": None, "CLAUDE.md": "# hi\n"},
        project_files={"CLAUDE.md": "# hi\n"},
    )

    res = _finalize(proj)

    assert res["dropped_entries"] == ["hooks/block-bash-vcs.sh"]
    assert "hooks/block-bash-vcs.sh" not in _manifest_files(proj)
    assert "CLAUDE.md" in _manifest_files(proj)


def test_entry_kept_when_project_still_has_the_file(tmp_path):
    _, proj = _mk(
        tmp_path,
        tracked={"hooks/keep.sh": None},
        project_files={"hooks/keep.sh": "#!/usr/bin/env bash\n"},
    )

    res = _finalize(proj)

    assert res["dropped_entries"] == []
    assert "hooks/keep.sh" in _manifest_files(proj)


def test_explicit_deleted_files_are_dropped_even_if_template_ships_them(tmp_path):
    _, proj = _mk(
        tmp_path,
        tracked={"hooks/unwanted.sh": "#!/usr/bin/env bash\n", "CLAUDE.md": "# hi\n"},
        project_files={"CLAUDE.md": "# hi\n"},
    )

    res = _finalize(proj, deleted_files=json.dumps(["hooks/unwanted.sh"]))

    assert res["dropped_entries"] == ["hooks/unwanted.sh"]
    assert "hooks/unwanted.sh" not in _manifest_files(proj)


# --- H5: git output must be decoded as UTF-8 --------------------------------

EM_DASH_BODY = "# Project State — panoscribe\n\n## Backlog\n"


@pytest.mark.skipif(shutil.which("git") is None, reason="git not on PATH")
def test_git_show_decodes_utf8_not_the_windows_locale(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    for args in (["init"], ["config", "user.email", "t@t"], ["config", "user.name", "t"]):
        subprocess.run(["git"] + args, cwd=repo, capture_output=True, check=True)
    (repo / "PROJECT_STATE.md").write_text(EM_DASH_BODY, encoding="utf-8", newline="")
    subprocess.run(["git", "add", "-A"], cwd=repo, capture_output=True, check=True)
    subprocess.run(["git", "commit", "-m", "x"], cwd=repo, capture_output=True, check=True)

    got = ts._git_show_file(str(repo), "HEAD", "PROJECT_STATE.md")

    assert got == EM_DASH_BODY
    assert "â€”" not in got


@pytest.mark.skipif(shutil.which("git") is None, reason="git not on PATH")
def test_em_dash_round_trips_through_the_three_way_path(tmp_path):
    repo = tmp_path / "repo"
    repo.mkdir()
    for args in (["init"], ["config", "user.email", "t@t"], ["config", "user.name", "t"]):
        subprocess.run(["git"] + args, cwd=repo, capture_output=True, check=True)
    (repo / "f.md").write_text(EM_DASH_BODY, encoding="utf-8", newline="")
    subprocess.run(["git", "add", "-A"], cwd=repo, capture_output=True, check=True)
    subprocess.run(["git", "commit", "-m", "x"], cwd=repo, capture_output=True, check=True)

    base = ts._git_show_file(str(repo), "HEAD", "f.md")
    merge = ts._three_way_merge(base, EM_DASH_BODY, EM_DASH_BODY, file_path="f.md")

    assert merge["auto_merged"] == EM_DASH_BODY
