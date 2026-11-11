"""Project-owned hook handlers in a template-owned .claude/settings.json (#30).

A settings.json that is "the template plus the project's own hook handlers"
must not read LOCAL_EDITED; every near miss must.
"""

import copy
import json
import pathlib
import subprocess

import pytest

from template_sync import mcp as ts
from template_sync.project_hooks import readd
from test_template_sync_v3_status import _REGION, _mk_v3, _run, _status, _tpl_entry

SETTINGS = ".claude/settings.json"
TOOLKIT_HANDLER = {"type": "command", "command": "bash hooks/no-push-main.sh"}
TPL = {
    "permissions": {"allow": ["Read"]},
    "hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [copy.deepcopy(TOOLKIT_HANDLER)]}]},
}
H = {"type": "command", "command": "bash hooks/seal-grep-guard.sh"}


def dumps(obj) -> str:
    return json.dumps(obj, indent=2) + "\n"


def with_handler(handler=H, event="PreToolUse", base=TPL):
    """`base` with `handler` appended to the first group of `event`."""
    obj = copy.deepcopy(base)
    obj["hooks"][event][0]["hooks"].append(copy.deepcopy(handler))
    return obj


def mk(tmp_path, project_obj, *, toolkit_scripts=("no-push-main.sh",),
       project_scripts=("seal-grep-guard.sh",), tpl_obj=TPL, project_text=None, entry_obj=None):
    repo, proj = _mk_v3(
        tmp_path,
        template={SETTINGS: dumps(tpl_obj)},
        project={SETTINGS: project_text if project_text is not None else dumps(project_obj)},
        entries={SETTINGS: _tpl_entry(dumps(entry_obj if entry_obj is not None else tpl_obj))},
    )
    for name in toolkit_scripts:
        (repo / "hooks").mkdir(exist_ok=True)
        (repo / "hooks" / name).write_text("#!/bin/bash\n", encoding="utf-8")
    for name in project_scripts:
        (proj / "hooks").mkdir(exist_ok=True)
        (proj / "hooks" / name).write_text("#!/bin/bash\n", encoding="utf-8")
    return repo, proj


def info_of(proj) -> dict:
    return _status(proj)["files"][SETTINGS]


def assert_local_edited(info: dict) -> None:
    assert info["status"] == "LOCAL_EDITED"
    assert "project_hooks" not in info
    assert "local_diff_kind" in info


def test_project_handler_reads_identical(tmp_path):
    _, proj = mk(tmp_path, with_handler())
    result = _status(proj)
    info = result["files"][SETTINGS]
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]
    assert "local_diff" not in info
    assert "local_diff_kind" not in info
    assert result["summary"]["local_edited"] == 0


def test_project_handler_new_group_reads_identical(tmp_path):
    obj = copy.deepcopy(TPL)
    obj["hooks"]["PreToolUse"].append({"matcher": "Edit", "hooks": [copy.deepcopy(H)]})
    _, proj = mk(tmp_path, obj)
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["PreToolUse Edit bash hooks/seal-grep-guard.sh"]


def move_template(repo, proj, new_tpl) -> None:
    """Commit the template as synced, record that commit in the manifest, then move the template on."""
    git = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
    subprocess.run([*git, "init", "-q"], cwd=str(repo), check=True, capture_output=True)
    subprocess.run([*git, "add", "-A"], cwd=str(repo), check=True, capture_output=True)
    subprocess.run([*git, "commit", "-q", "-m", "at sync"], cwd=str(repo), check=True, capture_output=True)
    head = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                          capture_output=True, text=True).stdout.strip()
    manifest_path = proj / ".claude" / "template-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["template_commit"] = head
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    tpl_file = ts._template_file_path({"templateRepo": str(repo), "variant": "general"}, SETTINGS)
    tpl_file.write_text(dumps(new_tpl), encoding="utf-8")


def test_template_moved_reads_template_updated(tmp_path):
    old_tpl = TPL
    new_tpl = copy.deepcopy(TPL)
    new_tpl["permissions"]["allow"].append("Grep")
    repo, proj = mk(tmp_path, with_handler(base=old_tpl), tpl_obj=old_tpl)
    move_template(repo, proj, new_tpl)
    info = info_of(proj)
    assert info["status"] == "TEMPLATE_UPDATED"
    assert info["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]
    assert "local_diff" not in info


@pytest.mark.parametrize("command", [
    "bash  hooks/seal-grep-guard.sh",
    "bash hooks/seal-grep-guard.sh arg",
    "bash hooks/seal-grep-guard.sh; rm -rf x",
    "bash hooks/seal-grep-guard.sh && true",
    "bash hooks/seal-grep-guard.sh | cat",
    "bash hooks/../hooks/seal-grep-guard.sh",
    "bash hooks/../seal-grep-guard.sh",
    'bash "$HOME/hooks/seal-grep-guard.sh"',
    "bash $HOME/hooks/seal-grep-guard.sh",
    "bash /abs/hooks/seal-grep-guard.sh",
    'bash "$CLAUDE_PROJECT_DIR/hooks/seal-grep-guard.sh',
    'bash $CLAUDE_PROJECT_DIR/hooks/seal-grep-guard.sh',
    'bash "$CLAUDE_PROJECT_DIR"/hooks/seal-grep-guard.sh',
    '"$CLAUDE_PROJECT_DIR/hooks/seal-grep-guard.sh"',
    "bash hooks/seal-grep-guard.sh\n",
    "bash hooks/seal-grep-guard.SH",
    "sh hooks/seal-grep-guard.sh",
    "bash\thooks/seal-grep-guard.sh",
    'bash "${CLAUDE_PROJECT_DIR}/hooks/seal-grep-guard.sh"',
    "bash ${CLAUDE_PROJECT_DIR}/hooks/seal-grep-guard.sh",
    '"${CLAUDE_PROJECT_DIR}"/hooks/seal-grep-guard.sh',
])
def test_grammar_rejects_near_misses(tmp_path, command):
    _, proj = mk(tmp_path, with_handler({"type": "command", "command": command}))
    assert_local_edited(info_of(proj))


def test_handler_with_args_stays_local_edited(tmp_path):
    handler = {"type": "command", "command": "bash hooks/seal-grep-guard.sh", "args": ["x"]}
    _, proj = mk(tmp_path, with_handler(handler))
    assert_local_edited(info_of(proj))


def test_non_command_type_stays_local_edited(tmp_path):
    handler = {"type": "prompt", "command": "bash hooks/seal-grep-guard.sh"}
    _, proj = mk(tmp_path, with_handler(handler))
    assert_local_edited(info_of(proj))


@pytest.mark.parametrize("command", [
    "bash hooks/seal-grep-guard.sh",
    'bash "$CLAUDE_PROJECT_DIR/hooks/seal-grep-guard.sh"',
    '"$CLAUDE_PROJECT_DIR"/hooks/seal-grep-guard.sh',
])
def test_all_three_shapes_are_project_owned(tmp_path, command):
    _, proj = mk(tmp_path, with_handler({"type": "command", "command": command}))
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == [f"PreToolUse Bash {command}"]


def test_missing_script_stays_local_edited(tmp_path):
    _, proj = mk(tmp_path, with_handler(), project_scripts=())
    assert_local_edited(info_of(proj))


def test_directory_in_place_of_script_stays_local_edited(tmp_path):
    _, proj = mk(tmp_path, with_handler(), project_scripts=())
    (proj / "hooks" / "seal-grep-guard.sh").mkdir(parents=True)
    assert_local_edited(info_of(proj))


def test_symlink_script_is_not_project_owned(tmp_path):
    _, proj = mk(tmp_path, with_handler(), project_scripts=())
    (proj / "hooks").mkdir(exist_ok=True)
    (proj / "hooks" / "real.sh").write_text("#!/bin/bash\n", encoding="utf-8")
    (proj / "hooks" / "seal-grep-guard.sh").symlink_to(proj / "hooks" / "real.sh")
    assert_local_edited(info_of(proj))


def test_toolkit_name_collision_stays_local_edited(tmp_path):
    # Under an event the template lacks, so only the name check can refuse it.
    obj = copy.deepcopy(TPL)
    obj["hooks"]["Stop"] = [{"hooks": [{"type": "command", "command": "bash hooks/no-push-main.sh"}]}]
    _, proj = mk(tmp_path, obj, project_scripts=("no-push-main.sh",))
    assert_local_edited(info_of(proj))


def test_toolkit_name_case_insensitive(tmp_path):
    handler = {"type": "command", "command": "bash hooks/No-Push-Main.sh"}
    _, proj = mk(tmp_path, with_handler(handler), project_scripts=("No-Push-Main.sh",))
    assert_local_edited(info_of(proj))


def test_template_handler_changed_stays_local_edited(tmp_path):
    obj = copy.deepcopy(TPL)
    obj["hooks"]["PreToolUse"][0]["hooks"][0]["command"] = "bash hooks/no-push-main.sh --x"
    _, proj = mk(tmp_path, obj)
    assert_local_edited(info_of(proj))


def test_permission_added_stays_local_edited(tmp_path):
    obj = with_handler()
    obj["permissions"]["allow"].append("Bash(ls)")
    _, proj = mk(tmp_path, obj)
    assert_local_edited(info_of(proj))


def test_unreadable_toolkit_hooks_dir_fails_closed(tmp_path):
    _, proj = mk(tmp_path, with_handler(), toolkit_scripts=())
    assert_local_edited(info_of(proj))


def test_not_json_stays_local_edited(tmp_path):
    _, proj = mk(tmp_path, None, project_text="{ not json\n")
    assert_local_edited(info_of(proj))


def test_json_array_stays_local_edited(tmp_path):
    _, proj = mk(tmp_path, None, project_text="[]\n")
    assert_local_edited(info_of(proj))


def test_two_events_listed_twice(tmp_path):
    obj = with_handler()
    obj["hooks"]["PostToolUse"] = [{"matcher": "Bash", "hooks": [copy.deepcopy(H)]}]
    _, proj = mk(tmp_path, obj)
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == [
        "PreToolUse Bash bash hooks/seal-grep-guard.sh",
        "PostToolUse Bash bash hooks/seal-grep-guard.sh",
    ]


def test_matcherless_group_label_uses_none(tmp_path):
    obj = copy.deepcopy(TPL)
    obj["hooks"]["Stop"] = [{"hooks": [copy.deepcopy(H)]}]
    _, proj = mk(tmp_path, obj)
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["Stop None bash hooks/seal-grep-guard.sh"]


@pytest.mark.parametrize("bom", [False, True])
def test_crlf_and_bom_project_file(tmp_path, bom):
    text = dumps(with_handler()).replace("\n", "\r\n")
    if bom:
        text = "\ufeff" + text
    _, proj = mk(tmp_path, None, project_text=text)
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]


def test_other_paths_untouched(tmp_path):
    body = "# Toolkit\n" + _REGION
    _, proj = _mk_v3(
        tmp_path,
        template={"CLAUDE.md": body},
        project={"CLAUDE.md": "# Toolkit\nextra line\n" + _REGION},
        entries={"CLAUDE.md": _tpl_entry(body)},
    )
    info = _status(proj)["files"]["CLAUDE.md"]
    assert info["status"] == "LOCAL_EDITED"
    assert "local_diff_kind" in info
    assert "project_hooks" not in info


# --- fix round 1 -------------------------------------------------------------


@pytest.mark.parametrize("constant", [float("nan"), float("inf"), float("-inf")])
def test_non_json_constant_in_a_handler_stays_local_edited(tmp_path, constant):
    handler = {**H, "timeout": constant}
    text = dumps(with_handler(handler))  # json.dumps writes NaN / Infinity / -Infinity
    assert any(token in text for token in ("NaN", "Infinity"))
    _, proj = mk(tmp_path, None, project_text=text)
    assert_local_edited(info_of(proj))


def test_true_is_not_one_in_the_remainder(tmp_path):
    tpl = {**copy.deepcopy(TPL), "enable": True}
    obj = with_handler(base=tpl)
    obj["enable"] = 1
    _, proj = mk(tmp_path, obj, tpl_obj=tpl)
    assert_local_edited(info_of(proj))


def test_five_is_not_five_point_zero_in_template_handler_identity(tmp_path):
    t_handler = {**H, "timeout": 5}
    tpl = with_handler(t_handler)
    obj = with_handler({**H, "timeout": 5.0}, base=tpl)
    _, proj = mk(tmp_path, obj, tpl_obj=tpl)
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]


def test_symlinked_hooks_dir_pointing_outside_is_not_project_owned(tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    (outside / "seal-grep-guard.sh").write_text("#!/bin/bash\n", encoding="utf-8")
    _, proj = mk(tmp_path, with_handler(), project_scripts=())
    (proj / "hooks").symlink_to(outside, target_is_directory=True)
    assert_local_edited(info_of(proj))


def test_deeply_nested_json_fails_closed(tmp_path):
    deep: list = []
    for _ in range(500):
        deep = [deep]
    obj = with_handler()
    obj["deep"] = deep
    _, proj = mk(tmp_path, obj)
    assert_local_edited(info_of(proj))


def test_unresolvable_base_fails_closed(tmp_path):
    old_tpl = TPL
    new_tpl = copy.deepcopy(TPL)
    new_tpl["permissions"]["allow"].append("Grep")
    # the toolkit repo is not a git repository, so the base cannot be resolved
    _, proj = mk(tmp_path, with_handler(base=old_tpl), tpl_obj=new_tpl, entry_obj=old_tpl)
    assert_local_edited(info_of(proj))


def test_cyrillic_lookalike_name_stays_local_edited(tmp_path):
    name = "seal-grep-guіd.sh"  # Cyrillic i
    handler = {"type": "command", "command": f"bash hooks/{name}"}
    _, proj = mk(tmp_path, with_handler(handler), project_scripts=(name,))
    assert_local_edited(info_of(proj))


def test_subdirectory_script_stays_local_edited(tmp_path):
    _, proj = mk(tmp_path, with_handler({"type": "command", "command": "bash hooks/sub/x.sh"}))
    (proj / "hooks" / "sub").mkdir()
    (proj / "hooks" / "sub" / "x.sh").write_text("#!/bin/bash\n", encoding="utf-8")
    assert_local_edited(info_of(proj))


# --- apply carries the handlers across ---------------------------------------


def apply_settings(proj, **kw) -> dict:
    return _run(ts.template_apply_file(str(proj), file_path=SETTINGS, **kw))


def moved(permission="Grep"):
    new_tpl = copy.deepcopy(TPL)
    new_tpl["permissions"]["allow"].append(permission)
    return new_tpl


def test_apply_keeps_project_handler(tmp_path):
    new_tpl = moved()
    repo, proj = mk(tmp_path, with_handler(), tpl_obj=TPL)
    move_template(repo, proj, new_tpl)
    res = apply_settings(proj, source="template")
    assert "error" not in res
    assert res["backup"] is None
    assert res["local_edit_overwritten"] is False
    assert res["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]
    assert res["manifest_entry"] == {"hash": "sha256:" + ts._sha256(dumps(new_tpl)), "ownership": "template"}
    written = (proj / SETTINGS).read_text(encoding="utf-8")
    assert json.loads(written) == with_handler(base=new_tpl)
    assert written == dumps(with_handler(base=new_tpl))
    # finalize records the entry; a fresh status then reads the carried file as clean
    manifest_path = proj / ".claude" / "template-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest["files"][SETTINGS] = res["manifest_entry"]
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    info = info_of(proj)
    assert info["status"] == "IDENTICAL"
    assert info["project_hooks"] == ["PreToolUse Bash bash hooks/seal-grep-guard.sh"]


def test_apply_matcher_gone_appends_group(tmp_path):
    new_tpl = copy.deepcopy(TPL)
    new_tpl["hooks"]["PreToolUse"][0]["matcher"] = "Edit"
    repo, proj = mk(tmp_path, with_handler(), tpl_obj=TPL)
    move_template(repo, proj, new_tpl)
    res = apply_settings(proj, source="template")
    assert res["local_edit_overwritten"] is False
    written = json.loads((proj / SETTINGS).read_text(encoding="utf-8"))
    assert written["hooks"]["PreToolUse"] == [
        {"matcher": "Edit", "hooks": [TOOLKIT_HANDLER]},
        {"matcher": "Bash", "hooks": [H]},
    ]


def test_apply_mixed_edit_keeps_old_path(tmp_path):
    obj = with_handler()
    obj["permissions"]["allow"].append("Bash(ls)")
    repo, proj = mk(tmp_path, obj, tpl_obj=TPL)
    move_template(repo, proj, moved())
    before = (proj / SETTINGS).read_text(encoding="utf-8")
    res = apply_settings(proj, source="template")
    assert "LOCAL_EDITED" in res["error"]
    assert (proj / SETTINGS).read_text(encoding="utf-8") == before
    backups = tmp_path / "backups"
    res = apply_settings(proj, source="template", backup_dir=str(backups))
    assert res["local_edit_overwritten"] is True
    assert "project_hooks" not in res
    assert (proj / SETTINGS).read_text(encoding="utf-8") == dumps(moved())
    assert "seal-grep-guard.sh" in pathlib.Path(res["backup"]["pre_sync"]).read_text(encoding="utf-8")


def test_apply_without_project_handlers_unchanged(tmp_path):
    new_tpl = moved()
    repo, proj = mk(tmp_path, TPL, tpl_obj=TPL)
    move_template(repo, proj, new_tpl)
    res = apply_settings(proj, source="template")
    assert res["backup"] is None
    assert res["local_edit_overwritten"] is False
    assert "project_hooks" not in res
    assert (proj / SETTINGS).read_bytes() == dumps(new_tpl).encode("utf-8")


def test_apply_provided_content_is_not_rewritten(tmp_path):
    repo, proj = mk(tmp_path, with_handler(), tpl_obj=TPL)
    move_template(repo, proj, moved())
    res = apply_settings(proj, source="provided", content='{"permissions": {}}\n',
                         backup_dir=str(tmp_path / "backups"))
    assert "project_hooks" not in res
    assert (proj / SETTINGS).read_text(encoding="utf-8") == '{"permissions": {}}\n'


def test_apply_extra_group_key_is_not_carried(tmp_path):
    # Pins the KISS ruling: a project-only group's keys other than matcher/hooks are not tracked.
    obj = copy.deepcopy(TPL)
    obj["hooks"]["PreToolUse"].append({"matcher": "Edit", "note": "mine", "hooks": [copy.deepcopy(H)]})
    repo, proj = mk(tmp_path, obj, tpl_obj=TPL)
    move_template(repo, proj, moved())
    res = apply_settings(proj, source="template")
    assert res["local_edit_overwritten"] is False
    written = json.loads((proj / SETTINGS).read_text(encoding="utf-8"))
    assert written["hooks"]["PreToolUse"][-1] == {"matcher": "Edit", "hooks": [H]}


def test_readd_does_not_mutate_and_omits_absent_matcher():
    tpl = copy.deepcopy(TPL)
    before = copy.deepcopy(tpl)
    out = readd(tpl, [("Stop", None, H), ("PreToolUse", "Bash", H)])
    assert tpl == before
    assert out["hooks"]["Stop"] == [{"hooks": [H]}]
    assert out["hooks"]["PreToolUse"][0]["hooks"] == [TOOLKIT_HANDLER, H]
