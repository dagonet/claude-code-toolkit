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
import pathlib

from template_sync import mcp as ts
from template_sync import v3

ROOT = pathlib.Path(__file__).resolve().parents[2]


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

    v4.0.1 item 14: `hunks` is accepted for backward compatibility but
    IGNORED -- project.md is header-plus-seed only; the caller
    (migrate_manifest) writes any hunks to backup_dir instead, because this
    file has no `paths:` key and loads at every session start.
    """
    md = v3.build_project_md("@@ -1 +1 @@\n-a\n+b\n", "abc1234", "v3.1.0")
    assert v3.core.CUSTOM_REGION_BEGIN not in md
    assert v3.core.CUSTOM_REGION_END not in md
    assert "```diff" not in md and "+b" not in md
    # F1 (controller, fix round 1): "paths:"/"PROJECT-CUSTOM" alone also
    # match the OLD pre-item-14 seed ("delivered to nobody"); compare
    # directly against the real constant to distinguish old from new.
    assert v3.PROJECT_MD_SEED_BODY in md
    assert "delivered to nobody" not in md


def test_new_seed_assertion_rejects_the_old_seed_the_weak_one_could_not():
    """F1's two-sided proof, pinned as a real test rather than a one-off
    check (controller fix round 1). The OLD project.md seed (pre-item-14,
    toolkit commit f10c39f, "delivered to nobody") PASSES the weak
    assertion this fix replaces ("paths:" and "PROJECT-CUSTOM" both
    present, both also true of the old body) -- proving that assertion
    could not tell old from new -- and correctly FAILS the corrected one.
    """
    old_seed = (
        "# Project rules (yours; sync never overwrites this file)\n\n"
        "<!-- template-sync: project-owned, and never overwritten by a sync; "
        "introduced in v3.1.0 -->\n\n"
        "Add `paths:`-scoped conventions here — style, language and file-type "
        "rules that\nshould arrive when a matching file is opened.\n\n"
        "A rules file is delivered ONLY when a tool call touches a file its "
        "`paths:` key\nmatches, and it is never present when a session or a "
        "subagent starts. A rules\nfile with no `paths:` key is delivered to "
        "nobody. So anything that must be true\nBEFORE work begins — safety "
        "rules, prohibitions, which tool to reach for —\nbelongs in CLAUDE.md's "
        "PROJECT-CUSTOM region, not here.\n"
    )
    # The weak assertion this fix replaces: it PASSES on the old seed, which
    # is exactly the defect (it cannot distinguish old from new).
    assert "paths:" in old_seed and "PROJECT-CUSTOM" in old_seed
    # The corrected assertion correctly FAILS on the old seed.
    assert v3.PROJECT_MD_SEED_BODY not in old_seed
    assert "delivered to nobody" in old_seed


def test_compute_status_docstring_names_template_deleted_as_the_once_class_route_to_acknowledged_kept():
    """Task 1 review F1: the PUBLISHED docstring of template_compute_status
    (the surface an MCP caller reads, not an internal v3.py comment) listed
    the once-class statuses as PRESENT / MISSING / ACKNOWLEDGED_KEPT --
    but a once-class entry only ever reaches ACKNOWLEDGED_KEPT via
    TEMPLATE_DELETED (template stopped shipping the file AND it is off
    disk); PRESENT and MISSING never become it. TEMPLATE_DELETED belongs in
    the once-class list too, and the route must be named.
    """
    doc = _doc(ts.template_compute_status)
    assert doc, "the tool must have a docstring -- it is the caller's contract"
    assert "PRESENT / MISSING / TEMPLATE_DELETED / ACKNOWLEDGED_KEPT (once" in doc
    assert "ACKNOWLEDGED_KEPT replaces TEMPLATE_DELETED" in doc
    # Two-sided: the template-class list is untouched by this fix.
    assert "IDENTICAL / TEMPLATE_UPDATED" in doc
    assert "LOCAL_EDITED / TEMPLATE_DELETED / ACKNOWLEDGED_KEPT (template class)" in doc


def test_seed_body_pinned_inside_the_template_seed_file():
    """v4.0.1 item 14 has TWO seed prose sources: `v3.PROJECT_MD_SEED_BODY`
    (what a MIGRATED consumer gets, via build_project_md) and
    `templates/general/.claude/rules/project.md` (what a BOOTSTRAPPED
    consumer gets, via setup-project.sh/.ps1). Nothing pinned them together,
    so they could drift apart silently (controller fix round 1, F2).
    """
    tpl_seed = (ROOT / "templates" / "general" / ".claude" / "rules" / "project.md").read_text(encoding="utf-8")
    assert v3.PROJECT_MD_SEED_BODY.strip() in tpl_seed

    # Two-sided: a body that disagrees by one word must NOT match -- proves
    # this assertion is discriminating, not vacuously true because both
    # sides are short, generic substrings.
    mutated = v3.PROJECT_MD_SEED_BODY.strip().replace("EVERY session start", "SOME sessions", 1)
    assert mutated != v3.PROJECT_MD_SEED_BODY.strip(), "fixture did not actually change anything"
    assert mutated not in tpl_seed
