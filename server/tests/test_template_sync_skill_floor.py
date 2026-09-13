"""The skill_version floor on template_migrate_manifest (0.3.7, item 6).

The checking was one-directional: the toolkit's sync skill checks the server's
version, and the server checked nothing about the skill. New-skill + old-server
is gated by the skill; OLD-SKILL + NEW-SERVER was gated by nothing -- and it is
the likelier direction, because this server advances on any pull from a working
tree while the skill needs a deliberate re-copy into ~/.claude/skills/, and a
`/mcp` reconnect gives a session a brand-new server while its loaded skill body
stays whatever it was. Found by a consumer session (yutraffic).

TWO DESIGN FACTS THESE TESTS PIN, because both are easy to "simplify" away:

1. ABSENCE is the load-bearing signal, not a low version. A skill body too old
   to carry the instruction does not pass a low version -- it passes nothing.
2. The value MUST come from the caller, never from reading
   ~/.claude/skills/sync-template/SKILL.md. That file reports the DISK; the
   failure being gated is a session running a body it read at startup, so a disk
   read returns a confident green in exactly the stale case. It works because
   the threat is staleness, not deceit.

Fact 2 is why arm B exists (penumbra's correction to their own test): a test
that only asserts the wrong implementation FAILS is passed by a
refuse-everything bug. Arm B asserts the right implementation SUCCEEDS where
neither a disk-reader nor a refuse-everything bug can -- installed file stale or
absent, declaration good, proceed.
"""

import asyncio
import json
import subprocess

import pytest

from template_sync import mcp as ts

SENTINEL = "not-a-skill"

OWNERSHIP = {
    "tracked_paths": ["templates"],
    "rules": [
        {"pattern": "CLAUDE.md", "ownership": "template"},
        {"pattern": ".claude/rules/project.md", "ownership": "once"},
    ],
}

TPL_V2 = "# Project\n\nRules line for {{NAME}}.\n"
PROJ_CLAUDE = (
    "# Project\n\nRules line for Demo.\nMy extra rule.\n\n"
    "<!-- PROJECT-CUSTOM:BEGIN -->\nKeep this region.\n<!-- PROJECT-CUSTOM:END -->\n"
)


def _git(repo, *args):
    subprocess.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", *args],
                   cwd=str(repo), check=True, capture_output=True)


def _mk_v2(tmp_path, project_claude):
    """Minimal v2 project plus a template repo whose history holds the base."""
    repo = tmp_path / "toolkit"
    vdir = repo / "templates" / "general"
    vdir.mkdir(parents=True)
    (vdir / "CLAUDE.md").write_text(TPL_V2, encoding="utf-8", newline="")
    (repo / "templates" / "ownership.json").write_text(
        json.dumps(OWNERSHIP), encoding="utf-8", newline="")
    _git(repo, "init", "-q")
    _git(repo, "add", "-A")
    _git(repo, "commit", "-q", "-m", "v2")
    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=str(repo), check=True,
                            capture_output=True, text=True).stdout.strip()

    proj = tmp_path / "proj"
    (proj / ".claude").mkdir(parents=True)
    (proj / "CLAUDE.md").write_text(project_claude, encoding="utf-8", newline="")
    (proj / ".claude" / "template-manifest.json").write_text(json.dumps({
        "version": 2, "templateRepo": str(repo), "variant": "general",
        "lastSynced": commit, "placeholders": {"NAME": "Demo"},
        "files": {"CLAUDE.md": {
            "templateHash": ts._sha256(TPL_V2.replace("{{NAME}}", "Demo")),
            "localHash": ts._sha256(project_claude), "locallyModified": True}},
    }), encoding="utf-8", newline="")
    return repo, proj, commit


def _migrate(proj, **kw):
    return json.loads(asyncio.run(ts.template_migrate_manifest(str(proj), **kw)))


def _declare(repo, value):
    """Put requires_skill into the template repo's ownership.json."""
    table = dict(OWNERSHIP)
    if value is not None:
        table["requires_skill"] = value
    (repo / "templates" / "ownership.json").write_text(
        json.dumps(table), encoding="utf-8", newline="")


def _blank_home(monkeypatch, tmp_path):
    """Point HOME at a directory with no installed skill at all.

    If the check reads the installed SKILL.md, this is where it breaks. If it
    reads only the caller's argument -- the contract -- this changes nothing,
    which is what makes a pass here evidence rather than coincidence.
    """
    empty = tmp_path / "empty-home"
    (empty / ".claude" / "skills").mkdir(parents=True)
    monkeypatch.setenv("HOME", str(empty))
    monkeypatch.setenv("USERPROFILE", str(empty))
    return empty


# ---------------------------------------------------------------------------
# Arm A: declared floor, caller says nothing, write mode -> REFUSE.
# ---------------------------------------------------------------------------

def test_absent_skill_version_refuses_in_write_mode(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    before = (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8")

    res = _migrate(proj, backup_dir=str(tmp_path / "b"))

    assert "error" in res
    assert "skill_version" in res["error"]
    assert ">=v3.1.3" in res["error"]
    # TWO populations reach this refusal and their remedies differ, so the text
    # must run both arms in parallel rather than diagnosing one and mentioning
    # the other last. A stale skill body passes nothing because it has no
    # instruction to; a caller that is NOT the skill passes nothing whatever body
    # the session loaded, because the step that passes the value only runs when
    # the skill runs. Addressing only the first sends the second to restart, call
    # again, and read the same message -- measured on a consumer who was both at
    # once, so the diagnosis was true of them by coincidence.
    assert "IF YOU ARE THE sync-template SKILL" in res["error"]
    assert "IF YOU ARE NOT THE SKILL" in res["error"]
    assert SENTINEL in res["error"]
    assert "dry_run" in res["error"]
    # The two sentences the toolkit asked to survive any edit, in its own later
    # wording: a fresh session, and that a re-copy alone does nothing for this one.
    assert "FRESH SESSION" in res["error"]
    assert "without restarting" in res["error"]
    assert res.get("migrated") is not True
    # Nothing written, and no backup taken either: the refusal precedes both.
    assert (proj / ".claude" / "template-manifest.json").read_text(encoding="utf-8") == before
    assert not (proj / ".claude" / "rules" / "project.md").exists()
    assert not (tmp_path / "b").exists()


# ---------------------------------------------------------------------------
# Arm B: the discriminator. Installed skill absent, declaration good -> PROCEED.
# A disk-reading implementation fails this. So does a refuse-everything bug.
# ---------------------------------------------------------------------------

def test_good_skill_version_proceeds_with_no_installed_skill(tmp_path, monkeypatch):
    _blank_home(monkeypatch, tmp_path)
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")

    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="v3.1.3")

    assert "error" not in res
    assert res["migrated"] is True
    assert res["skill_version"] == "v3.1.3"          # echoed as CLAIMED
    assert "skill_version_unknown" not in res        # presence-keyed
    assert "skill_version_bypassed" not in res


def test_newer_skill_version_than_the_floor_proceeds(tmp_path, monkeypatch):
    _blank_home(monkeypatch, tmp_path)
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="v3.1.5")
    assert "error" not in res and res["migrated"] is True


# ---------------------------------------------------------------------------
# Arm C: dry_run is never refused -- inspection stays open.
# ---------------------------------------------------------------------------

def test_absent_skill_version_proceeds_in_dry_run(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")

    res = _migrate(proj, dry_run=True)

    assert "error" not in res
    assert res["skill_version_unknown"] is True
    assert res["migrated"] is False and res["dry_run"] is True
    # Refusing dry_run would break the step that makes a migration safe:
    # gate_self_reference only surfaces in a preview.
    assert "gate_self_reference" in res


# ---------------------------------------------------------------------------
# Below the floor.
# ---------------------------------------------------------------------------

def test_below_the_floor_refuses_and_names_both_values(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="v3.0.3")
    assert "error" in res
    assert "v3.0.3" in res["error"] and ">=v3.1.3" in res["error"]
    assert "FRESH SESSION" in res["error"]
    assert "without restarting" in res["error"]
    # No population split here, deliberately: a caller that passed a tag-shaped
    # value IS the skill, or is impersonating one on purpose. Offering it the
    # not-a-skill bypass would read as "say you are not the skill and proceed".
    assert SENTINEL not in res["error"]


# ---------------------------------------------------------------------------
# The sentinel, and the fail-closed near misses.
# ---------------------------------------------------------------------------

def test_exact_sentinel_bypasses_and_is_flagged(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version=SENTINEL)
    assert "error" not in res
    assert res["migrated"] is True
    assert res["skill_version_bypassed"] is True
    assert res["skill_version"] == SENTINEL


@pytest.mark.parametrize("near_miss", [
    "not_a_skill", "Not-A-Skill", "NOT-A-SKILL", "notaskill", "not-a-skill-",
    "not-a-skillx", "xnot-a-skill", "not a skill",
])
def test_near_miss_sentinels_fail_closed(tmp_path, near_miss):
    """A mistyped sentinel that REFUSES is a nuisance. A mistyped sentinel that
    BYPASSES is the guard quietly not existing -- so every near miss refuses."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version=near_miss)
    assert "error" in res, f"{near_miss!r} must not bypass"
    assert "skill_version_bypassed" not in res


def test_sentinel_tolerates_only_surrounding_whitespace(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="  not-a-skill\n")
    assert "error" not in res and res["skill_version_bypassed"] is True


# ---------------------------------------------------------------------------
# Namespace: a version number is not a tag name.
# ---------------------------------------------------------------------------

def test_unprefixed_version_is_a_named_mismatch_not_normalised(tmp_path):
    """The floor is ">=v3.1.3" and the marker is "v3.1.3": tag-shaped on both
    sides. Silently stripping the `v` is how two normalisations end up
    disagreeing -- so a bare 3.1.3 is refused and named."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="3.1.3")
    assert "error" in res
    assert "3.1.3" in res["error"]


# ---------------------------------------------------------------------------
# Nothing declared, and a floor this server cannot parse.
# ---------------------------------------------------------------------------

def test_no_requires_skill_declared_means_absence_is_not_fatal(tmp_path):
    """Every consumer whose toolkit predates the declaration must keep working:
    there is nothing to enforce, so nothing is enforced."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, None)
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert "error" not in res and res["migrated"] is True
    assert res["skill_version_unknown"] is True      # reported, not enforced


def test_unparseable_floor_warns_and_proceeds(tmp_path):
    """Same rule as requires_server: a floor this server cannot read is left as
    found. Refusing on a value my parser failed to understand would turn my bug
    into the consumer's outage, and guessing a floor is worse than having none.
    """
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=banana")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert "error" not in res and res["migrated"] is True
    assert any("requires_skill_unparseable" in w for w in res["warnings"])


def test_floor_without_the_comparison_operator_is_unparseable(tmp_path):
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, "v3.1.3")
    res = _migrate(proj, backup_dir=str(tmp_path / "b"))
    assert "error" not in res
    assert any("requires_skill_unparseable" in w for w in res["warnings"])


# ---------------------------------------------------------------------------
# An already-v3 manifest is still a no-op, ahead of the floor check.
# ---------------------------------------------------------------------------

def test_already_v3_is_still_a_noop_even_with_a_declared_floor(tmp_path):
    """The no-op must not become a refusal: a caller that calls migrate
    unconditionally on an already-migrated project is doing nothing wrong."""
    repo, proj, commit = _mk_v2(tmp_path, PROJ_CLAUDE)
    _declare(repo, ">=v3.1.3")
    first = _migrate(proj, backup_dir=str(tmp_path / "b"), skill_version="v3.1.5")
    assert first["migrated"] is True
    again = _migrate(proj, backup_dir=str(tmp_path / "b2"))
    assert "error" not in again
    assert again["migrated"] is False and "reason" in again
