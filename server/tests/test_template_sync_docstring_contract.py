"""The published tool docstring must not contradict the behaviour (0.3.5 item 2).

The migrate docstring promised project.md received "the region verbatim" while
build_project_md deliberately did the opposite and documented WHY in its own
docstring. Implementation right, published surface wrong -- and the surface is
what a caller reads: two consumer sessions read it, measured the artifact, and
documented the artifact over it. A stale docstring is not a cosmetic defect when
the thing it is wrong about is where a consumer's content lives.

These tests pin the two claims against each other, so the prose cannot drift
back on its own.
"""

import inspect

from template_sync import mcp as ts
from template_sync import v3


def _doc(tool) -> str:
    """The docstring as an MCP caller sees it (FastMCP wraps the function)."""
    fn = getattr(tool, "fn", tool)
    return inspect.getdoc(fn) or ""


def test_migrate_docstring_does_not_promise_the_region_is_copied():
    doc = _doc(ts.template_migrate_manifest)
    assert doc, "the tool must have a docstring -- it is the caller's contract"
    assert "region verbatim" not in doc
    # It must say the opposite, in the direction that matters.
    assert "NOT copied" in doc and "CLAUDE.md" in doc


def test_migrate_docstring_agrees_with_build_project_md():
    """Both surfaces describe the same decision, so neither can drift alone."""
    impl = inspect.getdoc(v3.build_project_md) or ""
    assert "NOT copied" in impl                      # the function's own claim
    assert "NOT copied" in _doc(ts.template_migrate_manifest)


def test_the_artifact_itself_has_no_region(tmp_path):
    """The behavioural arm. Without it these are prose tests: a docstring that
    merely agrees with another docstring proves nothing about the file written.
    """
    md = v3.build_project_md("@@ -1 +1 @@\n-a\n+b\n", "abc1234", "v3.1.0")
    assert v3.core.CUSTOM_REGION_BEGIN not in md
    assert v3.core.CUSTOM_REGION_END not in md
    assert "```diff" in md and "+b" in md
