"""v3.template_content(): the ONE producer of `tpl_replaced` (v4.1 plan Task 1
commit 2, spec §5 reviewer D3/H2).

The invariant this commit establishes: every caller that wants "the template
as it applies to this project" routes through template_content() -- never
calls _apply_placeholders() directly. The test below is a whole-package grep,
the same one the plan's commit body cites (measured whole-file on 7f9634e:
TEN real call sites -- v3.py: resolve_base, compute_status_v3, apply_file_v3,
finalize_v3, migrate_v2_to_v3; mcp.py: template_compute_status,
template_get_diff x2, template_apply_file, template_finalize_sync). Asserting
the INVARIANT (zero call sites outside template_content's own body), not the
count: a producer added later fails on arrival rather than against a stale
constant (constraint 9).
"""

import pathlib
import re

from template_sync import v3 as v3_mod

# Matches a CALL to _apply_placeholders(, excluding its own `def` line (the
# four characters immediately before the name would read "def " there).
_CALL_RE = re.compile(r"(?<!def )_apply_placeholders\(")


def _template_content_span(lines: list[str]) -> tuple[int, int] | None:
    """[start, end) line-index span of template_content()'s body in v3.py,
    or None if the function does not exist yet (pre-refactor RED state)."""
    start = None
    for i, line in enumerate(lines):
        if line.startswith("def template_content("):
            start = i
            break
    if start is None:
        return None
    end = len(lines)
    for i in range(start + 1, len(lines)):
        if re.match(r"^def [A-Za-z_]", lines[i]):
            end = i
            break
    return start, end


def test_apply_placeholders_called_only_inside_template_content():
    """Fix round 1, F1-c2: this must sweep the WHOLE package (the docstring
    above already claimed "whole-package grep" -- the implementation only
    scanned v3.py and mcp.py, so a producer in any OTHER module in the
    package, e.g. a future verify.py call, would have passed silently)."""
    pkg = pathlib.Path(v3_mod.__file__).parent

    outside: list[str] = []
    for path in sorted(pkg.glob("*.py")):
        lines = path.read_text(encoding="utf-8").splitlines()
        span = _template_content_span(lines) if path.name == "v3.py" else None
        for i, line in enumerate(lines):
            if _CALL_RE.search(line):
                if span is None or not (span[0] <= i < span[1]):
                    outside.append(f"{path.name}:{i + 1}: {line.strip()}")

    assert outside == [], (
        "_apply_placeholders() called outside template_content()'s body -- "
        "route through v3.template_content() instead:\n" + "\n".join(outside)
    )


def test_template_content_none_when_template_missing():
    assert v3_mod.template_content(
        pathlib.Path("."), {"manifest_version": 3}, None, "CLAUDE.md", None) is None


def test_template_content_applies_placeholders():
    out = v3_mod.template_content(
        pathlib.Path("."), {"manifest_version": 3, "placeholders": {"NAME": "world"}},
        None, "CLAUDE.md", "hello {{NAME}}\n")
    assert out == "hello world\n"


def test_template_content_v2_manifest_is_placeholder_only(tmp_path):
    """No manifest_version key at all (a v2 manifest) -- must not crash on
    the missing key and must not attempt a splice."""
    (tmp_path / ".claude").mkdir()
    out = v3_mod.template_content(
        tmp_path, {"placeholders": {}}, None, ".claude/agents/foo.md",
        "---\nname: foo\ntools: Read\n---\nbody\n")
    assert out == "---\nname: foo\ntools: Read\n---\nbody\n"


def test_template_content_v3_manifest_agent_path_is_placeholder_only_noop(tmp_path):
    """A v3 manifest never splices, even for an agents/ path with a grants
    file present -- the splice is v4-only."""
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        '{"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}', encoding="utf-8")
    out = v3_mod.template_content(
        tmp_path, {"manifest_version": 3, "placeholders": {}}, None,
        ".claude/agents/foo.md", "---\nname: foo\ntools: Read\n---\nbody\n")
    assert out == "---\nname: foo\ntools: Read\n---\nbody\n"


def test_template_content_v4_manifest_no_grants_file_is_noop(tmp_path):
    (tmp_path / ".claude").mkdir()
    out = v3_mod.template_content(
        tmp_path, {"manifest_version": 4, "placeholders": {}}, None,
        ".claude/agents/foo.md", "---\nname: foo\ntools: Read\n---\nbody\n")
    assert out == "---\nname: foo\ntools: Read\n---\nbody\n"


def test_template_content_v4_manifest_empty_grants_file_is_noop(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        '{"schema": 1, "grants": {}}', encoding="utf-8")
    out = v3_mod.template_content(
        tmp_path, {"manifest_version": 4, "placeholders": {}}, None,
        ".claude/agents/foo.md", "---\nname: foo\ntools: Read\n---\nbody\n")
    assert out == "---\nname: foo\ntools: Read\n---\nbody\n"


def test_template_content_v4_manifest_non_agent_path_is_noop_even_with_grants(tmp_path):
    (tmp_path / ".claude").mkdir()
    (tmp_path / ".claude" / "agent-grants.json").write_text(
        '{"schema": 1, "grants": {"foo": ["mcp__glider__symbol_lookup"]}}', encoding="utf-8")
    out = v3_mod.template_content(
        tmp_path, {"manifest_version": 4, "placeholders": {}}, None,
        "CLAUDE.md", "# hello\n")
    assert out == "# hello\n"
