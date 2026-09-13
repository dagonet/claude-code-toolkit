"""Atomic write retry tests.

Consumer finding (Motorsport-Manager-AI-Agent v3.0.3 sync, 2026-09-05):
`template_apply_file` on `hooks/gate-before-merge.sh` failed three times with
`WinError 5` (access denied) while a live run was executing that hook and
held the file open. Each failure left a `.tmp` beside the target. The final
`os.replace` must retry with backoff and remove its own temp file when it
gives up.
"""

import os

import pytest

from template_sync import mcp as ts


def _flaky_replace(fail_times: int):
    """Return an os.replace stand-in that raises PermissionError for the
    first `fail_times` calls, then delegates to the real os.replace."""
    real_replace = os.replace
    calls = {"n": 0}

    def replace(src, dst):
        calls["n"] += 1
        if calls["n"] <= fail_times:
            raise PermissionError(13, "Access is denied")
        return real_replace(src, dst)

    return replace, calls


def test_write_file_atomic_retries_transient_permission_error(tmp_path, monkeypatch):
    target = tmp_path / "hook.sh"
    target.write_text("old", encoding="utf-8")
    replace, calls = _flaky_replace(fail_times=2)
    monkeypatch.setattr(ts.os, "replace", replace)

    ts._write_file_atomic(target, "new", backoff=0)

    assert target.read_text(encoding="utf-8") == "new"
    assert calls["n"] == 3
    assert list(tmp_path.glob("*.tmp")) == []


def test_write_file_atomic_cleans_tmp_when_rename_keeps_failing(tmp_path, monkeypatch):
    target = tmp_path / "hook.sh"
    target.write_text("old", encoding="utf-8")
    replace, calls = _flaky_replace(fail_times=10_000)
    monkeypatch.setattr(ts.os, "replace", replace)

    with pytest.raises(PermissionError):
        ts._write_file_atomic(target, "new", retries=3, backoff=0)

    assert calls["n"] == 3
    assert target.read_text(encoding="utf-8") == "old"
    assert list(tmp_path.glob("*.tmp")) == []


def test_write_file_atomic_does_not_retry_other_errors(tmp_path, monkeypatch):
    target = tmp_path / "hook.sh"
    calls = {"n": 0}

    def replace(src, dst):
        calls["n"] += 1
        raise FileNotFoundError(2, "No such file")

    monkeypatch.setattr(ts.os, "replace", replace)

    with pytest.raises(FileNotFoundError):
        ts._write_file_atomic(target, "new", retries=3, backoff=0)

    assert calls["n"] == 1
    assert list(tmp_path.glob("*.tmp")) == []
