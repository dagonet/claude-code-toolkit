"""C1 distribution (v4.4.0): the sync replaces .claude/settings.json hook strings
wholesale -- never duplicates, never drops a matcher group (spec R-5).

Old template = the v4.3.1 templates/general settings.json (fixture copy, so no
git history is needed). New template = the live templates/general one.
The matcher-group table is shared with check 71 of
scripts/verify-template-consistency.sh (fixtures/hook-registrations-v4.4.0.json).
"""

import json
import re
from pathlib import Path

from template_sync import mcp as ts

from test_template_sync_v3_apply import _apply, _mk_v3, _tpl_entry

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
REL = ".claude/settings.json"
OLD = (HERE / "fixtures" / "template-v4.3.1-general-settings.json").read_text(encoding="utf-8")
NEW = (REPO / "templates" / "general" / ".claude" / "settings.json").read_text(encoding="utf-8")
OLD_WRAPPER = 'c=$?; if [ \\"$c\\" = \\"127\\" ]'
LOCAL_LINE = '      "Bash(make lint*)",\n'


def _local_edited(text: str) -> str:
    first, rest = text.split('      "Read",\n', 1)
    return first + '      "Read",\n' + LOCAL_LINE + rest


def _frozen_general():
    rows = json.loads((HERE / "fixtures" / "hook-registrations-v4.4.0.json").read_text(encoding="utf-8"))["rows"]
    return sorted((r[1], r[2], r[3]) for r in (x.split(";") for x in rows) if r[0] == "general")


def _registrations(text: str):
    out = []
    for ev, groups in json.loads(text)["hooks"].items():
        for g in groups:
            for h in g["hooks"]:
                m = re.search(r"hooks/([A-Za-z0-9_-]+)\.sh", h["command"])
                if m:  # inline commands without a hooks/ script are not in the frozen table
                    out.append((ev, g.get("matcher", ""), m.group(1)))
    return sorted(out)


def _mk(tmp_path, project_text):
    return _mk_v3(tmp_path, template={REL: NEW}, project={REL: project_text},
                  entries={REL: _tpl_entry(OLD)})


def test_fixtures_are_the_old_and_new_shapes():
    # the test is vacuous unless the old template really has the wrapper and the new one does not
    assert OLD_WRAPPER in OLD
    assert OLD_WRAPPER not in NEW
    assert OLD != NEW


def test_unedited_settings_replaced_byte_for_byte(tmp_path):
    repo, proj = _mk(tmp_path, OLD)
    res = _apply(proj, file_path=REL)
    assert res["action"] == "written_from_template", res
    assert res["local_edit_overwritten"] is False
    got = (proj / REL).read_bytes()
    assert got == NEW.encode("utf-8")
    assert not any(OLD_WRAPPER in line for line in got.decode("utf-8").splitlines())


def test_local_edit_refused_without_backup_dir_then_backed_up(tmp_path):
    edited = _local_edited(OLD)
    repo, proj = _mk(tmp_path, edited)
    res = _apply(proj, file_path=REL)
    assert "backup_dir" in res["error"], res
    assert "migrate first" not in res["error"], res
    assert (proj / REL).read_text(encoding="utf-8") == edited

    backup = tmp_path / "backup"
    res = _apply(proj, file_path=REL, backup_dir=str(backup))
    assert res["local_edit_overwritten"] is True, res
    assert (backup / ".claude" / "settings.json.pre-sync").read_text(encoding="utf-8") == edited
    assert (proj / REL).read_bytes() == NEW.encode("utf-8")


def test_three_way_merge_keeps_local_line_and_every_new_string(tmp_path):
    merge = ts._three_way_merge(OLD, NEW, _local_edited(OLD), file_path=REL)
    assert merge["has_conflicts"] is False, merge
    merged = merge["auto_merged"]
    json.loads(merged)  # parses
    assert LOCAL_LINE in merged
    new_cmds = [h["command"] for gs in json.loads(NEW)["hooks"].values() for g in gs for h in g["hooks"]]
    assert new_cmds
    for cmd in new_cmds:
        assert json.dumps(cmd)[1:-1] in merged, cmd
    assert OLD_WRAPPER not in merged


def test_result_matcher_groups_equal_the_frozen_table(tmp_path):
    frozen = _frozen_general()
    assert len(frozen) >= 19
    # the template itself, and the file after a wholesale apply, register exactly the frozen set
    assert _registrations(NEW) == frozen
    repo, proj = _mk(tmp_path, OLD)
    _apply(proj, file_path=REL)
    assert _registrations((proj / REL).read_text(encoding="utf-8")) == frozen
    # a three-way merge result also neither duplicates nor drops a group
    merged = ts._three_way_merge(OLD, NEW, _local_edited(OLD), file_path=REL)["auto_merged"]
    assert _registrations(merged) == frozen
    # control: a dropped group would be detected
    d = json.loads(NEW)
    d["hooks"]["PreToolUse"].pop(0)
    assert _registrations(json.dumps(d)) != frozen
