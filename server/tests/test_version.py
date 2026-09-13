import importlib
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]


def test_version_matches_repo_root_line_1():
    import template_sync
    root_line_1 = (ROOT / "VERSION").read_text(encoding="utf-8").splitlines()[0].strip()
    assert template_sync.__version__ == root_line_1


def test_version_is_bare_x_y_z():
    import template_sync
    parts = template_sync.__version__.split(".")
    assert len(parts) == 3 and all(p.isdigit() for p in parts), template_sync.__version__


def test_hatch_reads_the_same_version_file():
    # The editable install is a real hatchling build. If the [tool.hatch.version]
    # pattern does not match a bare X.Y.Z file, the install fails or stamps the
    # wrong version; this catches it in Task 1 rather than at release.
    from importlib.metadata import version
    import template_sync
    assert version("claude-code-toolkit-template-sync") == template_sync.__version__


def test_missing_version_file_raises_at_import(tmp_path, monkeypatch):
    # Copy the package without VERSION into a scratch dir and import it there in a
    # subprocess: absence must be an ImportError naming the file, never a fallback.
    pkg_src = ROOT / "server" / "src" / "template_sync"
    scratch = tmp_path / "template_sync"
    scratch.mkdir()
    for p in pkg_src.iterdir():
        if p.name != "VERSION" and p.is_file():
            (scratch / p.name).write_bytes(p.read_bytes())
    r = subprocess.run(
        [sys.executable, "-c", "import template_sync"],
        cwd=tmp_path, capture_output=True, text=True,
        env={"PYTHONPATH": str(tmp_path), "PATH": ""},
    )
    assert r.returncode != 0
    assert "VERSION" in r.stderr
