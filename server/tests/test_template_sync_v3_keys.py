"""key_audit.missing_declared_keys / optional_absent_detail (v4.0.1, item 2, 18).

Everything here runs `v3.audit_keys` directly against the REAL
`templates/ownership.json` PROJECT_CONTEXT.md rule and the REAL python-variant
`PROJECT_CONTEXT.md` text, read off disk -- expectations are derived from
those files, never hard-coded (spec constraint 6), so a future edit to either
file cannot leave this test silently checking a stale shape.
"""

import json
import pathlib

from template_sync import v3

REPO_ROOT = pathlib.Path(__file__).resolve().parents[2]
OWNERSHIP = json.loads((REPO_ROOT / "templates" / "ownership.json").read_text(encoding="utf-8"))
RULE = next(r for r in OWNERSHIP["rules"] if r["pattern"] == "PROJECT_CONTEXT.md")
PY_TPL_TEXT = (REPO_ROOT / "templates" / "python" / "PROJECT_CONTEXT.md").read_text(encoding="utf-8")
PY_TPL_KEYS = v3.parse_keys(PY_TPL_TEXT)


def _mdk_by_key(res: dict) -> dict:
    return {e["key"]: e for e in res["missing_declared_keys"]}


# --- case 1: required key absent -------------------------------------------


def test_required_key_absent_is_missing_declared_absent():
    proj = "- **Protected branches**: main master\n- **Test**: pytest\n"
    res = v3.audit_keys(proj, PY_TPL_TEXT, None, RULE)
    assert "Gate" in res["missing_required"]
    entry = _mdk_by_key(res)["Gate"]
    assert entry == {"key": "Gate", "reason": "absent", "template_default": PY_TPL_KEYS.get("Gate")}


# --- case 2: deprecated spelling --------------------------------------------


def test_deprecated_spelling_reports_canonical_key():
    proj = "- **Protected branches**: main master\n- **Gate Command**: old-gate.sh\n"
    res = v3.audit_keys(proj, PY_TPL_TEXT, None, RULE)
    # Held under its deprecated spelling -- NOT missing_required (pinned
    # unchanged shape, test_template_sync_v3_status.py:107).
    assert res["missing_required"] == []
    assert {"key": "Gate Command", "replacement": "Gate"} in res["deprecated_keys"]
    entry = _mdk_by_key(res)["Gate"]
    assert entry == {"key": "Gate", "reason": "deprecated_spelling",
                      "template_default": PY_TPL_KEYS.get("Gate")}


def test_deprecated_spelling_on_an_OPTIONAL_key_is_excluded_by_the_ownership_rule():
    """Not structurally impossible like the other two exclusions: `Test` is
    optional, `find_key` does not recognise the deprecated spelling, so a
    consumer holding only `**Test Command**:` lands in BOTH `optional_absent`
    (find_key finds nothing under the canonical name) and would land in
    missing_declared_keys too unless excluded. The ownership rule says
    optional-absent wins; this is the case that actually exercises the
    exclusion rather than merely documenting it.
    """
    proj = "- **Protected branches**: main master\n- **Gate**: g\n- **Test Command**: pytest\n"
    res = v3.audit_keys(proj, PY_TPL_TEXT, None, RULE)
    assert "Test" in res["optional_absent"]
    assert "Test" not in _mdk_by_key(res)


# --- case 3: unfilled placeholder -------------------------------------------


def test_unfilled_placeholder_key_is_missing_declared_unfilled():
    proj = ("- **Protected branches**: main master\n- **Gate**: g\n"
            "- **Post-edit build**: {{POST_EDIT_BUILD}}\n")
    res = v3.audit_keys(proj, PY_TPL_TEXT, None, RULE)
    assert "Post-edit build" in res["placeholder_keys"]
    entry = _mdk_by_key(res)["Post-edit build"]
    assert entry == {"key": "Post-edit build", "reason": "unfilled",
                      "template_default": PY_TPL_KEYS.get("Post-edit build")}


# --- case 4: optional absent -------------------------------------------------


def test_optional_absent_key_is_detailed_and_never_missing_declared():
    proj = "- **Protected branches**: main master\n- **Gate**: g\n"
    res = v3.audit_keys(proj, PY_TPL_TEXT, None, RULE)
    assert "Test" in res["optional_absent"]
    assert "Test" not in _mdk_by_key(res)
    detail = next(d for d in res["optional_absent_detail"] if d["key"] == "Test")
    rule_detail = RULE["optional_keys"]["Test"]
    assert detail["template_default"] == PY_TPL_KEYS.get("Test")
    assert detail["effect_when_absent"] == rule_detail["effect_when_absent"]
    assert detail["none_meaning"] == rule_detail["none_meaning"]


# --- case 5: per-variant count, derived -------------------------------------


VARIANTS = ["general", "dotnet", "dotnet-maui", "rust-tauri", "java", "python"]


def test_log_location_optional_absent_has_specific_none_meaning():
    """v4.0.2 item 4: the `Log location` key (general/dotnet/dotnet-maui/
    rust-tauri spelling; rust-tauri carries a fixed value, never a
    placeholder, so it never lands in optional_absent) gets its own
    none_meaning in ownership.json's optional_keys instead of the generic
    'not defined for this key' fallback. General's own template text is
    used to exercise it."""
    gen_tpl_text = (REPO_ROOT / "templates" / "general" / "PROJECT_CONTEXT.md").read_text(encoding="utf-8")
    res = v3.audit_keys("- **Protected branches**: main\n- **Gate**: g\n", gen_tpl_text, None, RULE)
    assert "Log location" in res["optional_absent"]
    detail = next(d for d in res["optional_absent_detail"] if d["key"] == "Log location")
    assert detail["none_meaning"] == "no log directory declared"
    assert detail["none_meaning"] != "not defined for this key"


def test_log_path_spelling_optional_absent_has_the_same_none_meaning():
    """Task 3 addendum item B / ruling R7: python and java spell this key
    `Log Path`, not `Log location` (measured: templates/python/
    PROJECT_CONTEXT.md:29, templates/java/PROJECT_CONTEXT.md:30). Data-only
    fix -- ownership.json's optional_keys gets a SECOND entry with the SAME
    none_meaning text, no template rename (renaming a once-class key would
    surface as missing_declared_keys on every python/java consumer; the
    spelling unification itself is deferred). python's own template text
    (PY_TPL_TEXT, already loaded above) is used since it carries the 'Log
    Path' spelling, unlike general's 'Log location'."""
    res = v3.audit_keys("- **Protected branches**: main master\n- **Gate**: g\n", PY_TPL_TEXT, None, RULE)
    assert "Log Path" in res["optional_absent"]
    detail = next(d for d in res["optional_absent_detail"] if d["key"] == "Log Path")
    assert detail["none_meaning"] == "no log directory declared"
    assert detail["none_meaning"] != "not defined for this key"


def test_every_declared_key_is_accounted_for_exactly_once_per_variant():
    """Audited against an EMPTY project, every key the variant's own
    PROJECT_CONTEXT.md declares must land in exactly one of
    missing_declared_keys (required, reason=absent) or optional_absent --
    together they must equal the full declared-key set, with no key double
    counted. No constant: each variant's key count comes from parse_keys on
    that variant's real file.
    """
    for variant in VARIANTS:
        tpl_text = (REPO_ROOT / "templates" / variant / "PROJECT_CONTEXT.md").read_text(encoding="utf-8")
        tpl_keys = set(v3.parse_keys(tpl_text))
        res = v3.audit_keys("", tpl_text, None, RULE)
        mdk_keys = {e["key"] for e in res["missing_declared_keys"]}
        optional_keys = set(res["optional_absent"])
        assert not (mdk_keys & optional_keys), \
            f"{variant}: a key is in both missing_declared_keys and optional_absent"
        assert mdk_keys | optional_keys == tpl_keys, \
            f"{variant}: declared keys {tpl_keys} not fully covered by " \
            f"missing_declared_keys {mdk_keys} | optional_absent {optional_keys}"
        assert len(tpl_keys) == len(mdk_keys) + len(optional_keys)
