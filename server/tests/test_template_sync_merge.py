"""Three-way merge tests for template_sync_mcp.

Regression coverage for the "merge silently drops lines" bug reported by a
consumer /sync-template run (panoscribe, 2026-08-29): `difflib` reports an
insertion as an opcode with `i1 == i2`, and the merge walk recorded that
opcode against base line `i1` -- a line that is *retained*, not changed.
The walk then emitted the inserted lines in place of `base_lines[i1]`,
dropping it, while still reporting `has_conflicts: false`.
"""

import shutil

import pytest

from template_sync import mcp as ts


# --- Feedback case (a): PROJECT_STATE.md lost its "## Backlog" heading -------

BACKLOG_BASE = (
    "# Project State â€” panoscribe\n"
    "\n"
    "## Backlog\n"
    "\n"
    "_See GitHub Issues._\n"
)

# Template's only change: mojibake fixed in the H1.
BACKLOG_THEIRS = (
    "# Project State — panoscribe\n"
    "\n"
    "## Backlog\n"
    "\n"
    "_See GitHub Issues._\n"
)

# Project inserted a "## Phase Status" section above Backlog.
BACKLOG_OURS = (
    "# Project State â€” panoscribe\n"
    "\n"
    "## Phase Status\n"
    "\n"
    "Phase 3 in progress.\n"
    "\n"
    "## Backlog\n"
    "\n"
    "_See GitHub Issues._\n"
)


def test_project_insert_above_heading_keeps_the_heading():
    merge = ts._three_way_merge(BACKLOG_BASE, BACKLOG_THEIRS, BACKLOG_OURS)
    merged = merge["auto_merged"]

    assert "## Backlog\n" in merged, merged
    assert "## Phase Status\n" in merged, merged
    assert "_See GitHub Issues._\n" in merged, merged
    assert merged.index("## Phase Status") < merged.index("## Backlog")
    assert merge["has_conflicts"] is False
    assert merge["conflict_count"] == 0
    assert merge["dropped_lines"] == []


# --- Feedback case (b): hooks/read-size-gate.sh lost LOG_FILE= --------------

GATE_BASE = (
    "#!/usr/bin/env bash\n"
    "THRESHOLD=500\n"
    'LOG_FILE="$HOME/.claude/read-size.log"\n'
    'exec bash gate.sh "$1" "$LOG_FILE"\n'
)

# Template inserted a comment + BIG_FILE_BYTES between THRESHOLD and LOG_FILE
# and kept LOG_FILE.
GATE_THEIRS = (
    "#!/usr/bin/env bash\n"
    "THRESHOLD=500\n"
    "# hard cap for binary reads\n"
    "BIG_FILE_BYTES=10485760\n"
    'LOG_FILE="$HOME/.claude/read-size.log"\n'
    'exec bash gate.sh "$1" "$LOG_FILE"\n'
)

# Project edited an unrelated later line.
GATE_OURS = (
    "#!/usr/bin/env bash\n"
    "THRESHOLD=500\n"
    'LOG_FILE="$HOME/.claude/read-size.log"\n'
    'exec bash gate.sh "$1" "$LOG_FILE" "$2"\n'
)


def test_template_insert_between_lines_keeps_the_following_line():
    merge = ts._three_way_merge(GATE_BASE, GATE_THEIRS, GATE_OURS)
    merged = merge["auto_merged"]

    assert 'LOG_FILE="$HOME/.claude/read-size.log"\n' in merged, merged
    assert "BIG_FILE_BYTES=10485760\n" in merged, merged
    assert 'exec bash gate.sh "$1" "$LOG_FILE" "$2"\n' in merged, merged
    assert merge["has_conflicts"] is False
    assert merge["conflict_count"] == 0
    assert merge["dropped_lines"] == []


def test_untouched_project_file_takes_the_template_verbatim():
    """ours == base: the merge must reproduce theirs byte for byte."""
    merge = ts._three_way_merge(GATE_BASE, GATE_THEIRS, GATE_BASE)

    assert merge["auto_merged"] == GATE_THEIRS
    assert merge["has_conflicts"] is False


def test_identical_insert_on_both_sides_is_emitted_once():
    both = GATE_THEIRS
    merge = ts._three_way_merge(GATE_BASE, both, both)

    assert merge["auto_merged"] == both
    assert merge["has_conflicts"] is False
    assert merge["conflict_count"] == 0


def test_template_deletion_is_honoured_and_not_flagged_as_dropped():
    base = "a\nb\nc\n"
    theirs = "a\nc\n"  # template removed b
    ours = "a\nb\nc\nd\n"  # project appended d

    merge = ts._three_way_merge(base, theirs, ours)

    assert "b\n" not in merge["auto_merged"]
    assert merge["dropped_lines"] == []
    assert merge["has_conflicts"] is False


def test_insert_whose_anchor_was_replaced_is_flagged_not_relocated():
    """The other side replaced the region the insertion was anchored in.

    Emitting it at the end of the file would look clean and silently move the
    line; it must surface as a conflict instead.
    """
    base = "a\nb\nc\nd\ne\n"
    theirs = "a\nb\nX\nc\nd\ne\n"  # insert anchored at base index 2
    ours = "a\nB2\nC2\nD2\ne\n"  # replaces base 1..4

    merge = ts._three_way_merge(base, theirs, ours)

    assert merge["has_conflicts"] is True
    assert merge["conflict_count"] == 1
    assert "insertion anchor lost" in merge["auto_merged"]
    assert "X\n" in merge["auto_merged"]
    assert not merge["auto_merged"].endswith("e\nX\n")


def test_conflicting_edits_still_produce_a_conflict_hunk():
    base = "a\nb\nc\n"
    theirs = "a\nTEMPLATE\nc\n"
    ours = "a\nPROJECT\nc\n"

    merge = ts._three_way_merge(base, theirs, ours)

    assert merge["has_conflicts"] is True
    assert merge["conflict_count"] == 1
    assert "<<<<<<< PROJECT" in merge["auto_merged"]
    assert ">>>>>>> TEMPLATE" in merge["auto_merged"]


# --- The post-merge safety net ---------------------------------------------


def test_dropped_lines_detects_a_lossy_merge():
    base = "a\nb\nc\n"
    theirs = "a\nb\nc\nd\n"
    ours = "a\nb\nc\n"
    lossy = "a\nc\nd\n"  # b was present in base AND ours, kept by theirs

    assert ts._dropped_lines(base, theirs, ours, lossy) == ["b\n"]


def test_dropped_lines_counts_duplicates():
    base = "x\nx\ny\n"
    theirs = "x\nx\ny\n"
    ours = "x\nx\ny\n"
    lossy = "x\ny\n"  # one of the two x lines vanished

    assert ts._dropped_lines(base, theirs, ours, lossy) == ["x\n"]


def test_dropped_lines_ignores_lines_the_template_deleted():
    base = "a\nb\nc\n"
    theirs = "a\nc\n"
    ours = "a\nb\nc\n"

    assert ts._dropped_lines(base, theirs, ours, "a\nc\n") == []


def test_dropped_lines_ignores_lines_the_project_changed():
    base = "a\nb\nc\n"
    theirs = "a\nb\nc\n"
    ours = "a\nB\nc\n"

    assert ts._dropped_lines(base, theirs, ours, "a\nB\nc\n") == []


def test_guard_forces_a_conflict_when_the_merge_is_lossy(monkeypatch):
    """A lossy merge must never come back as clean, whatever caused it."""
    monkeypatch.setattr(ts, "_merge_walk", lambda b, t, o: (["a\n", "c\n"], 0))

    merge = ts._three_way_merge("a\nb\nc\n", "a\nb\nc\n", "a\nb\nc\n")

    assert merge["dropped_lines"] == ["b\n"]
    assert merge["has_conflicts"] is True
    assert merge["conflict_count"] == 1
    assert "<<<<<<< PROJECT (dropped by merge)" in merge["auto_merged"]


# --- Feedback case (c): hooks/enforce-delegation.sh lost the closing "];" ----

DELEGATION_BASE = """#!/usr/bin/env bash
INPUT=$(cat)
node -e '
const allowPatterns = [
  /^git /,
  /^ls /,
];
process.exit(0);
'
"""

# Template edited the line adjacent to the array.
DELEGATION_THEIRS = """#!/usr/bin/env bash
INPUT=$(cat 2>/dev/null)
node -e '
const allowPatterns = [
  /^git /,
  /^ls /,
];
process.exit(0);
'
"""

# Project appended an array element -- an insert directly above "];".
DELEGATION_OURS = """#!/usr/bin/env bash
INPUT=$(cat)
node -e '
const allowPatterns = [
  /^git /,
  /^ls /,
  /^rg /,
];
process.exit(0);
'
"""


def test_project_appended_array_element_keeps_the_closing_bracket():
    merge = ts._three_way_merge(
        DELEGATION_BASE, DELEGATION_THEIRS, DELEGATION_OURS,
        file_path="hooks/enforce-delegation.sh",
    )
    merged = merge["auto_merged"]

    assert "];\n" in merged, merged
    assert "  /^rg /,\n" in merged, merged
    assert "  /^ls /,\n" in merged, merged
    assert merge["has_conflicts"] is False
    assert merge["dropped_lines"] == []
    assert merge.get("syntax_error") is None


# --- Syntax validation of merged shell hooks --------------------------------

_BROKEN_BASH = ["#!/usr/bin/env bash\n", "if [ -z \"$X\" ]; then\n"]  # no `fi`
_BROKEN_JS = [
    "#!/usr/bin/env bash\n",
    "node -e '\n",
    "const a = [\n",
    "1,\n",
    "'\n",
]


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash not on PATH")
def test_broken_shell_merge_is_never_reported_clean(monkeypatch):
    monkeypatch.setattr(ts, "_merge_walk", lambda b, t, o: (list(_BROKEN_BASH), 0))
    src = "".join(_BROKEN_BASH)

    merge = ts._three_way_merge(src, src, src, file_path="hooks/x.sh")

    assert merge["syntax_checked"] is True
    assert merge["syntax_error"] and merge["syntax_error"].startswith("bash -n:")
    assert merge["has_conflicts"] is True
    assert merge["conflict_count"] >= 1
    assert "<<<<<<< PROJECT (syntax error in merge)" in merge["auto_merged"]


@pytest.mark.skipif(
    shutil.which("bash") is None or shutil.which("node") is None,
    reason="bash or node not on PATH",
)
def test_broken_embedded_js_is_never_reported_clean(monkeypatch):
    monkeypatch.setattr(ts, "_merge_walk", lambda b, t, o: (list(_BROKEN_JS), 0))
    src = "".join(_BROKEN_JS)

    merge = ts._three_way_merge(src, src, src, file_path="hooks/x.sh")

    assert merge["syntax_error"] and merge["syntax_error"].startswith("node --check:")
    assert merge["has_conflicts"] is True


def test_syntax_check_skips_gracefully_without_bash(monkeypatch):
    monkeypatch.setattr(ts.shutil, "which", lambda name: None)
    monkeypatch.setattr(ts, "_merge_walk", lambda b, t, o: (list(_BROKEN_BASH), 0))
    src = "".join(_BROKEN_BASH)

    merge = ts._three_way_merge(src, src, src, file_path="hooks/x.sh")

    assert merge["syntax_checked"] is False
    assert merge.get("syntax_error") is None
    assert merge["has_conflicts"] is False


def test_non_shell_files_are_not_syntax_checked():
    merge = ts._three_way_merge("a\n", "a\n", "a\n", file_path="CLAUDE.md")

    assert merge["syntax_checked"] is False
    assert merge.get("syntax_error") is None


@pytest.mark.skipif(shutil.which("bash") is None, reason="bash not on PATH")
def test_conflicted_shell_merge_reports_no_syntax_error():
    """Conflict markers are not shell. Checking a script that already carries
    them would fail `bash -n` every time and double-count the conflict."""
    base = "#!/usr/bin/env bash\nX=1\necho hi\n"
    theirs = "#!/usr/bin/env bash\nX=2\necho hi\n"
    ours = "#!/usr/bin/env bash\nX=3\necho hi\n"

    merge = ts._three_way_merge(base, theirs, ours, file_path="hooks/x.sh")

    assert "<<<<<<< PROJECT\n" in merge["auto_merged"]
    assert merge["conflict_count"] == 1
    assert merge["syntax_checked"] is False
    assert merge["syntax_error"] is None


@pytest.mark.skipif(
    shutil.which("bash") is None or shutil.which("node") is None,
    reason="bash or node not on PATH",
)
def test_double_quoted_node_block_is_checked(monkeypatch):
    """Most `node -e` blocks in the toolkit's hooks are double-quoted."""
    lines = [
        "#!/usr/bin/env bash\n",
        'node -e "\n',
        "const a = [\n",
        "1,\n",
        '"\n',
    ]
    monkeypatch.setattr(ts, "_merge_walk", lambda b, t, o: (list(lines), 0))
    src = "".join(lines)

    merge = ts._three_way_merge(src, src, src, file_path="hooks/x.sh")

    assert merge["syntax_error"] and merge["syntax_error"].startswith("node --check:")
    assert merge["has_conflicts"] is True


# --- Guard robustness on large, blank-line-heavy files -----------------------


def test_guard_sees_blank_lines_in_a_large_file():
    """`SequenceMatcher(autojunk=True)` treats a line occurring more than
    `len(b)//100 + 1` times as junk once the sequence reaches 200 elements.
    On a 300-line doc whose template side was rewritten wholesale, that made
    every blank line junk, `equal` came back empty, and the guard's
    `required` set was empty -- so a dropped blank line looked clean.
    """
    base_lines = [ln for i in range(150) for ln in (f"unique-{i}\n", "\n")]
    base = "".join(base_lines)
    # Template rewrote every content line but kept the blank separators.
    theirs = "".join(
        f"rewritten-{i}\n" if ln.startswith("unique") else ln
        for i, ln in enumerate(base_lines)
    )
    lossy = "".join(base_lines[:41] + base_lines[42:])  # one blank separator gone

    assert ts._dropped_lines(base, theirs, base, lossy) == ["\n"]


def test_guard_is_order_aware_not_just_counted():
    """A line re-inserted elsewhere must not mask a loss at its own position."""
    base = "a\nb\nc\nd\n"
    # `b` is gone from its place but a stray copy appears at the end.
    lossy = "a\nc\nd\nb\n"

    assert ts._dropped_lines(base, base, base, lossy) == ["b\n"]
