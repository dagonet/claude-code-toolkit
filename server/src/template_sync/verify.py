"""template_verify: read-only consumer consistency check (v4.0.1, item 22).

Pure, synchronous, no MCP dependency -- `run()` takes a resolved project path,
an optional template_repo override and a mode, and returns
`{ok, mode, summary, lines: [{id, status, measured, expected, remedy}]}`.
The MCP tool in mcp.py is a thin async wrapper around `run()`; the CLI
(`mcp-template-sync-tools --verify`) is a thin wrapper around the same JSON.

`ok` is true only when no line is FAIL. `status` is one of PASS/FAIL/SKIP/
INFO. Only conditions that CAN fail are FAIL_LINE kind (constraint: item 22
spec, "placeholder_key_divergence" and "orphans" are deliberately excluded --
they live in compute_status_v3 as informational, never here).

LINES is the single source of truth for which ids exist and in what order;
`run()` guarantees exactly one entry per id in the output regardless of which
cascade short-circuited the computation (a manifest that fails to load, is
not v3, or whose template repo lacks templates/ownership.json short-circuits
every id that depends on that prerequisite to SKIP, with a reason -- never a
crash and never a silently-missing line). `_finalize` sweeps in a defensive
catch-all SKIP for any id no branch reached, so LINES and the returned list
can never disagree in length.
"""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import time

from . import mcp as core
from . import v3

FAIL_LINE = "FAIL_LINE"
INFO_LINE = "INFO_LINE"

# Order is the contract: the CLI and the fleet script print in this order,
# and test_template_sync_verify.py derives its PASS-fixture counts from it.
LINES = (
    ("manifest_valid", FAIL_LINE),
    ("manifest_version_supported", FAIL_LINE),
    ("template_commit_known", FAIL_LINE),
    ("template_behind_head", INFO_LINE),
    ("requires_server", FAIL_LINE),
    ("no_errors", FAIL_LINE),
    ("no_warnings", FAIL_LINE),
    ("unknown_keys_empty", FAIL_LINE),
    ("superseded_absent", FAIL_LINE),
    ("server_skew", FAIL_LINE),
    ("status_clean", FAIL_LINE),
    ("gate_self_reference_empty", FAIL_LINE),
    ("unclassified_empty", FAIL_LINE),
    ("new_template_files_empty", FAIL_LINE),
    ("classes_and_hashes", FAIL_LINE),
    ("region_markers", FAIL_LINE),
    # v4.1 (spec §6, §7; rulings R-J, R-K): six new ids, appended in this
    # order right after region_markers. claude_md_identical /
    # import_line_present / instructions_file_present run under v4 only and
    # SKIP under v3 (legacy: "manifest v3: no import yet"; window: "manifest
    # v3: migrate first (owned by status_clean)" -- R-K, ONE fact ONE FAIL).
    # The agent_grants_* three run under every manifest version this server
    # dispatches on (v3 and v4 alike).
    ("claude_md_identical", FAIL_LINE),
    ("import_line_present", FAIL_LINE),
    ("instructions_file_present", FAIL_LINE),
    ("agent_grants_resolvable", FAIL_LINE),
    ("agent_grants_names_known", FAIL_LINE),
    ("agent_grants_extendable", FAIL_LINE),
    ("manifest_bytes", FAIL_LINE),
    ("declared_keys", FAIL_LINE),
    ("encoding_drift", INFO_LINE),
    ("project_md_seed_current", INFO_LINE),
    # v4.1.1 (spec §2.1): a harm-keyed FACT, separate from project_md_seed_current's
    # harm-keyed JUDGEMENT -- "mine differs" and "mine is harmful" never share
    # an answer. A prefix test against the shipped seed, no remedy (a
    # deliberate, once-class edit is not something this line tells the
    # consumer to undo).
    ("project_md_seed_differs", INFO_LINE),
    ("legacy_gate_dir", INFO_LINE),
    ("once_notes_changed", INFO_LINE),
    ("project_md_scoped_consistent", INFO_LINE),
    ("tree_clean", FAIL_LINE),
)

_IDS = tuple(i for i, _ in LINES)

# Ids computed independently of manifest shape (raw bytes / project git
# state) -- these still run even when every v3-dependent id below them is
# short-circuited to SKIP.
_SHAPE_INDEPENDENT = ("manifest_valid", "manifest_version_supported", "manifest_bytes", "tree_clean",
                      "legacy_gate_dir")

# classes_and_hashes (item 10): the closed enumeration of statuses a
# template-class manifest entry can carry. A status not listed here falls
# OUTSIDE the partition and fails the line as `unenumerated=<status>` --
# never add a catch-all `else` bucket and never derive the total from
# `len(entries)`, either of which would make the sum equal the
# template-class count BY CONSTRUCTION and defeat the check (reviewer's
# acceptance rule: a one-line change to compute_status_v3 that adds a new
# status without extending this tuple must make classes_and_hashes FAIL --
# see test_classes_and_hashes_fails_on_unenumerated_status).
TEMPLATE_CLASS_STATUSES = (
    "IDENTICAL", "TEMPLATE_UPDATED", "LOCAL_EDITED",
    "TEMPLATE_DELETED", "ACKNOWLEDGED_KEPT", "CONFLICT",
    # v4.1, the v3-manifest window (spec §7, ruling R-J): a NEW template-class
    # status, added BY HAND (constraint 5) -- a v3 consumer's CLAUDE.md read
    # by a v4.1+ toolkit checkout that has already dropped the region.
    "MIGRATION_REQUIRED",
)

# v4.1.2 (spec §2): project_md_seed_current's harm-keyed arm fires on the
# GUIDANCE LINE -- the one that starts with this stem and tells the consumer
# where always-on project rules belong -- not on the PROJECT-CUSTOM token
# anywhere in the file. A consumer's own migration note ("this used to live
# in ... PROJECT-CUSTOM region") is prose ABOUT the retired region, not a
# pointer AT it, and must not trip this arm once the guidance line itself has
# been repointed.
PROJECT_MD_GUIDANCE_STEM = "Always-on project rules belong in"


def _guidance_line_names_region(project_md: str) -> bool:
    """True when the FIRST line beginning with PROJECT_MD_GUIDANCE_STEM names
    PROJECT-CUSTOM. Reads that one line only; a file with no such line is
    False and falls through to the older-seed arms."""
    for line in project_md.splitlines():
        if line.lstrip().startswith(PROJECT_MD_GUIDANCE_STEM):
            return "PROJECT-CUSTOM" in line
    return False


def _line(id_: str, status: str, measured: str, expected: str, remedy: str = "") -> dict:
    return {"id": id_, "status": status, "measured": measured, "expected": expected, "remedy": remedy}


def _skip(id_: str, reason: str) -> dict:
    return _line(id_, "SKIP", reason, "", "")


def _cascade_skip(results: list[dict], done: set, reason: str) -> None:
    """SKIP every id not yet in `done` and not shape-independent."""
    for id_, _kind in LINES:
        if id_ in done or id_ in _SHAPE_INDEPENDENT:
            continue
        results.append(_skip(id_, reason))
        done.add(id_)


def _check_manifest_bytes(pp: pathlib.Path) -> dict:
    manifest_path = pp / ".claude" / "template-manifest.json"
    try:
        data = manifest_path.read_bytes()
    except OSError as e:
        return _skip("manifest_bytes", f"cannot read {manifest_path}: {e}")
    problems = []
    if data.startswith(b"\xef\xbb\xbf"):
        problems.append("BOM present")
    if b"\r\n" in data:
        problems.append("CRLF present")
    if not data.endswith(b"\n") or data.endswith(b"\n\n"):
        problems.append("does not end with exactly one LF")
    if problems:
        return _line("manifest_bytes", "FAIL", "; ".join(problems),
                     "ends with exactly one LF, no BOM, no CRLF",
                     "re-run template_finalize_sync (writes exactly one trailing LF, no BOM, LF only) "
                     "or normalize the file's line endings")
    return _line("manifest_bytes", "PASS", "ends with one LF, no BOM, no CRLF",
                 "ends with exactly one LF, no BOM, no CRLF")


def _check_tree_clean(pp: pathlib.Path, mode: str) -> dict:
    expected = "manifest committed and working tree clean"
    if not pp.is_dir():
        # A nonexistent cwd raises NotADirectoryError from subprocess itself
        # (WinError 267), which _run_git's except clause does not catch --
        # this check must not crash the whole tool over a bad project_path.
        return _skip("tree_clean", f"{pp} does not exist -- cannot verify")
    inside = core._run_git(["rev-parse", "--is-inside-work-tree"], cwd=str(pp))
    if inside["exit_code"] != 0 or inside["stdout"].strip() != "true":
        return _skip("tree_clean", f"{pp} is not a git checkout -- cannot verify")
    if mode == "pre_commit":
        return _skip("tree_clean", "pre_commit: the sync leaves the manifest and applied "
                                   "files uncommitted by design (SKILL.md step 8 runs before the commit)")
    st = core._run_git(["status", "--porcelain"], cwd=str(pp))
    if st["exit_code"] != 0:
        return _skip("tree_clean", f"git status --porcelain failed: {st['stderr'].strip()}")
    dirty = [l for l in st["stdout"].splitlines() if l.strip()]
    if dirty:
        preview = "; ".join(dirty[:5]) + (f" (+{len(dirty) - 5} more)" if len(dirty) > 5 else "")
        return _line("tree_clean", "FAIL", f"{len(dirty)} dirty path(s): {preview}", expected,
                     "commit the sync (SKILL.md step 9) before verifying with mode=post_commit -- "
                     "or, if the named paths are unrelated in-flight work, commit or stash them "
                     "separately first")
    return _line("tree_clean", "PASS", "0 dirty paths", expected)


def _check_legacy_gate_dir(pp: pathlib.Path) -> dict:
    """v4.0.1 moved the gate artifact under <common git dir>/gate/; a
    leftover project-relative .gate/ is never itself a defect (item 4,
    penumbra: a **Log location** can legitimately point there), so this
    never fails -- it only names the three known artifact-file names, by
    name, for deletion, and counts (never names) everything else so a
    consumer's own logs are never listed as if they were gate output. Reads
    only `pp` -- no manifest, no rules, no status -- so it is
    shape-independent (Task 3 addendum, ruling R8) and runs at every early
    return in `run()`, not just the full success path."""
    gate_dir = pp / ".gate"
    if not gate_dir.is_dir():
        return _line("legacy_gate_dir", "INFO", "no legacy .gate/ directory", "n/a (informational)")
    artifact_names = ("last-pass.json", "last-precommit.json", "last-precommit-noop.json")
    arts = [n for n in artifact_names if (gate_dir / n).is_file()]
    others = sum(1 for e in gate_dir.iterdir() if e.name not in arts)
    return _line("legacy_gate_dir", "INFO",
                 f"legacy .gate/ present: artifact files {arts}; {others} other entries",
                 "n/a (informational)",
                 "delete the listed artifact files by name (the gate now writes under "
                 "<common git dir>/gate/); these are not gate artifacts -- leave them "
                 "(a **Log location** may point here); never delete the directory")


def _project_md_scoped(project_md: str) -> bool:
    """True when `project_md` opens with a `---\\n ... \\n---\\n` frontmatter
    block that declares a `paths:` key (v4.0.2, item 12) -- the shape
    `.claude/rules/project.md` takes when a consumer has scoped it away from
    the unscoped, always-loaded default the seed sentences describe."""
    if not project_md.startswith("---\n"):
        return False
    end = project_md.find("\n---\n", 4)
    if end == -1:
        return False
    return "paths:" in project_md[4:end]


# --- v4.1: claude_md_identical / import_line_present / instructions_file_present
# --- (spec §6, §7; rulings R-J, R-K) ---------------------------------------

INSTRUCTIONS_FILE_DEFAULT = ".claude/project-instructions.md"


def _claude_md_window_reason(manifest: dict, rules) -> str:
    """The SKIP reason for the three CLAUDE.md-related lines under a v3
    manifest: legacy (nothing to import yet) or window (migrate first, owned
    by status_clean) -- R-K: the two SKIP sets are equal and told apart only
    by this reason string."""
    tpl_rel = rules.template_path_for("CLAUDE.md")
    tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
    if v3.claude_md_window_active(manifest, tpl_rel, tpl_raw):
        return "manifest v3: migrate first (owned by status_clean)"
    return "manifest v3: no import yet"


def _check_claude_md_identical(pp: pathlib.Path, manifest: dict, rules) -> dict:
    tpl_rel = rules.template_path_for("CLAUDE.md")
    tpl_raw = core._read_file(core._template_file_path(manifest, tpl_rel))
    try:
        tpl_content = v3.template_content(pp, manifest, rules, "CLAUDE.md", tpl_raw)
    except (v3.GrantsError, v3.GrantRefused) as e:
        # v4.1 commit-3 concern 3, narrowed: this line is now defended;
        # status_clean/classes_and_hashes (which read compute_status_v3
        # directly) remain the ones still exposed to a malformed grants file.
        return _line("claude_md_identical", "FAIL", str(e), "byte-identical to template_content()",
                     "fix .claude/agent-grants.json")
    proj_claude = core._read_file(pp / "CLAUDE.md")
    if tpl_content is None:
        return _line("claude_md_identical", "FAIL", "template CLAUDE.md not found",
                     "byte-identical to template_content()",
                     "the toolkit no longer ships CLAUDE.md for this variant")
    if proj_claude is None:
        return _line("claude_md_identical", "FAIL", "CLAUDE.md not found in the project",
                     "byte-identical to template_content()", "run /sync-template")
    if proj_claude == tpl_content:
        return _line("claude_md_identical", "PASS", "byte-identical to template_content()",
                     "byte-identical to template_content()")
    diff = v3._unified(tpl_content, proj_claude, "template", "project")
    return _line("claude_md_identical", "FAIL", f"diverges from template_content():\n{diff}",
                 "byte-identical to template_content()",
                 "run /sync-template -- CLAUDE.md is template-owned under v4; move project text into "
                 ".claude/project-instructions.md")


def _check_import_line_present(pp: pathlib.Path) -> dict:
    """v4-only (R-K amended): the stated case is the TEMPLATE regression
    route -- a variant template loses the @ line, a consumer syncs from a
    branch/fork/unreleased checkout where the toolkit's own last-line check
    never ran, their CLAUDE.md becomes byte-identical to the broken
    template, claude_md_identical PASSes, and this is the only line that can
    report the import silently gone."""
    proj_claude = core._read_file(pp / "CLAUDE.md")
    if proj_claude is None:
        return _line("import_line_present", "FAIL", "CLAUDE.md not found in the project",
                     "last line is @.claude/project-instructions.md", "run /sync-template")
    last_line = proj_claude.splitlines()[-1] if proj_claude.strip() else ""
    if last_line == "@.claude/project-instructions.md":
        return _line("import_line_present", "PASS", "last line is the @ import line",
                     "last line is @.claude/project-instructions.md")
    return _line("import_line_present", "FAIL", f"last line is {last_line!r}",
                 "last line is @.claude/project-instructions.md",
                 "the template's import line was lost upstream -- see docs/template-sync.md")


def _check_instructions_file_present(pp: pathlib.Path, manifest: dict) -> dict:
    inst_path = core._normalize_path(manifest.get("instructions_file", INSTRUCTIONS_FILE_DEFAULT))
    if (pp / inst_path).is_file():
        return _line("instructions_file_present", "PASS", f"{inst_path} exists", f"{inst_path} exists")
    return _line("instructions_file_present", "FAIL", f"{inst_path} not found", f"{inst_path} exists",
                 "the once-class file was deleted by hand -- restore it (an ordinary sync never re-seeds it)")


# --- v4.1: agent_grants_resolvable / agent_grants_names_known /
# --- agent_grants_extendable (spec §4) -- run under every manifest version.


def _shipped_agent_names(manifest: dict) -> set[str]:
    agents_dir = core._get_template_dir(manifest) / ".claude" / "agents"
    names: set[str] = set()
    if agents_dir.is_dir():
        for p in sorted(agents_dir.glob("*.md")):
            text = core._read_file(p)
            if text is not None:
                name = v3.agent_name_of(text)
                if name:
                    names.add(name)
    return names


def _agent_template_path_by_name(manifest: dict, agent_name: str) -> pathlib.Path | None:
    agents_dir = core._get_template_dir(manifest) / ".claude" / "agents"
    if not agents_dir.is_dir():
        return None
    for p in sorted(agents_dir.glob("*.md")):
        text = core._read_file(p)
        if text is not None and v3.agent_name_of(text) == agent_name:
            return p
    return None


# R-N (fix round 1): the "mcp-dev-servers family" -- aliases whose source
# tree and census route check 50 (scripts/verify-template-consistency.sh)
# already knows how to find, via a REGISTERED alias's venv path in
# ~/.claude.json. Kept as the SAME six names check 50 uses (C50_FAMILY),
# never re-derived, so the two lists cannot silently disagree about which
# aliases have a real census route.
MCP_DEV_SERVERS_FAMILY = ("git-tools", "github-tools", "dotnet-tools", "ollama-tools",
                          "rust-tools", "python-tools")

# Ceiling on ONE alias's census subprocess (scripts/lib/list-mcp-tools.py).
# Named so the "why 30" sits beside the value it bounds; kept as a FLOOR
# inside AGENT_GRANTS_CENSUS_BUDGET_S below (fix round 2, J2) -- an alias
# census already STARTED is never truncated early just because the
# remaining total budget is smaller than this ceiling; it is simply never
# STARTED once the total budget is already spent.
AGENT_GRANTS_CENSUS_PER_ALIAS_TIMEOUT_S = 30.0

# J2 (fix round 2): a TOTAL budget for the WHOLE agent_grants_resolvable
# computation in one template_verify call, not a per-alias ceiling alone --
# worst case before this existed was ~7 aliases x 30s = 3.5 minutes of
# apparent hang if every venv were broken, and a verify that hangs is a
# verify people stop running. The accepted trade: one hanging/broken
# server's census must not blind the rest of the line -- bounded and
# honest (some aliases SKIP, named, with a reason) beats unbounded and
# complete (a report nobody waits for). Consumed across aliases, iterated
# in SORTED order so which alias lands on which side of the cutoff depends
# on the data, never on dict/set iteration order; every alias the budget
# does not reach SKIPs naming itself and "census budget exhausted before it
# was reached" -- NEVER PASSes on that account. Per-call cache is kept
# alongside this budget (cross-call caching would go stale when a server is
# re-registered).
AGENT_GRANTS_CENSUS_BUDGET_S = 30.0


def _mcp_registration_path() -> pathlib.Path:
    override = os.environ.get("MCP_TOOLS_REGISTRATION")
    return pathlib.Path(override) if override else pathlib.Path.home() / ".claude.json"


def _derive_mcp_dev_servers_source_dir(registration_path: pathlib.Path, alias: str) -> str | None:
    """Exactly check 50's own derivation: `mcpServers.<alias>.command`,
    normalized to forward slashes, everything before the FIRST
    `/.venv/Scripts/` or `/.venv/bin/` segment. None when the registration
    file is unreadable, the alias is not registered, or its command carries
    neither marker."""
    try:
        data = json.loads(registration_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    cmd = (data.get("mcpServers", {}).get(alias) or {}).get("command", "")
    if not cmd:
        return None
    norm = cmd.replace("\\", "/")
    for marker in ("/.venv/Scripts/", "/.venv/bin/"):
        idx = norm.find(marker)
        if idx != -1:
            return norm[:idx]
    return None


def _census_mcp_dev_servers_alias(template_repo: str, source_dir: str, registration_path: pathlib.Path,
                                  alias: str) -> tuple[list[str] | None, str | None]:
    """(names, skip_reason) via scripts/lib/list-mcp-tools.py (system
    python, resolved from the manifest's OWN templateRepo -- the toolkit
    checkout the consumer already points at), run exactly as check 50 runs
    it. The STATIC census is the membership set check 50 itself checks
    tokens against (the import census there is used only for drift
    detection, never as the primary "does this exist" source), so a
    registered alias with no live venv still resolves via the static
    scan -- consistent with check 50's own tolerant fallback."""
    lib = pathlib.Path(template_repo) / "scripts" / "lib" / "list-mcp-tools.py"
    if not lib.is_file():
        return None, f"{lib} not found"
    py = shutil.which("python") or shutil.which("python3")
    if py is None:
        return None, "no system python on PATH"
    try:
        proc = subprocess.run(
            [py, str(lib), "--source-dir", source_dir, "--registration", str(registration_path),
             "--alias", alias],
            capture_output=True, text=True, timeout=AGENT_GRANTS_CENSUS_PER_ALIAS_TIMEOUT_S,
        )
    except (OSError, subprocess.TimeoutExpired) as e:
        return None, f"list-mcp-tools.py failed: {e}"
    if proc.returncode != 0:
        return None, f"list-mcp-tools.py exit {proc.returncode}: {(proc.stderr or proc.stdout).strip()[:200]}"
    out = proc.stdout.strip()
    if not out:
        return None, "list-mcp-tools.py produced no output"
    try:
        data = json.loads(out.splitlines()[-1])
    except ValueError:
        return None, "list-mcp-tools.py: unparseable output"
    static = data.get("static")
    if not static:
        return None, data.get("skip_reason") or f'no FastMCP("{alias}") module found under {source_dir}'
    return static, None


def _check_agent_grants_resolvable(pp: pathlib.Path, manifest: dict) -> dict:
    """Every granted token must exist in its server's exports -- a typo must
    never silently grant nothing, and this line must never PASS a token it
    could not actually resolve (R-N). Two real census routes:
    `template-sync-tools` (this process's own live registry, via
    `_registered_tool_names()`) and the mcp-dev-servers family (source dir
    derived from a REGISTERED alias's venv path exactly as check 50 derives
    it, censused via `scripts/lib/list-mcp-tools.py`'s import route,
    resolved against the manifest's own `templateRepo`). PASS/FAIL by token
    where a route exists; SKIP naming the alias ("alias X: no census
    route") for every other alias, or when the family alias has no
    registration/venv to derive a source dir from -- SKIP is the honest
    cannot-determine answer for a read-only reporting line, and it is not
    fail-open, since the shape/policy refusal already happened in
    `load_grants` at apply time."""
    try:
        grants = v3.load_grants(pp)
    except (v3.GrantsError, v3.GrantRefused) as e:
        return _line("agent_grants_resolvable", "FAIL", str(e),
                     "every granted token exists in its server's exports",
                     "fix .claude/agent-grants.json")
    if not (pp / v3.AGENT_GRANTS_FILE).is_file():
        return _line("agent_grants_resolvable", "PASS", "no grants file", "n/a (informational)")
    tokens = sorted({t for toks in grants.values() for t in toks})
    if not tokens:
        return _line("agent_grants_resolvable", "PASS", "grants=0", "n/a (informational)")

    registered = set(core._registered_tool_names())
    registration_path = _mcp_registration_path()
    template_repo = manifest.get("templateRepo", "")
    census_cache: dict[str, tuple[list[str] | None, str | None]] = {}
    not_exported: list[str] = []
    skip_aliases: dict[str, str] = {}
    resolved = 0

    # Group by alias and iterate ALIASES in SORTED order (fix round 2,
    # controller addendum (a)): the census budget is consumed per ALIAS
    # (one subprocess per alias, cached), so which alias lands on which
    # side of the budget cutoff must depend on the data (alphabetical),
    # never on dict/set iteration order.
    alias_tokens: dict[str, list[tuple[str, str]]] = {}
    for tok in tokens:
        alias, _sep, name = tok[len("mcp__"):].partition("__")
        alias_tokens.setdefault(alias, []).append((tok, name))

    budget_start = time.monotonic()
    for alias in sorted(alias_tokens):
        toks_for_alias = alias_tokens[alias]
        if alias == "template-sync-tools":
            for tok, name in toks_for_alias:
                if name in registered:
                    resolved += 1
                else:
                    not_exported.append(tok)
            continue
        if alias in MCP_DEV_SERVERS_FAMILY:
            if alias not in census_cache:
                if time.monotonic() - budget_start >= AGENT_GRANTS_CENSUS_BUDGET_S:
                    census_cache[alias] = (
                        None, f"alias {alias}: census budget exhausted before it was reached")
                else:
                    source_dir = _derive_mcp_dev_servers_source_dir(registration_path, alias)
                    if source_dir is None:
                        census_cache[alias] = (None, f"alias {alias}: no census route (not registered)")
                    elif not pathlib.Path(source_dir).is_dir():
                        census_cache[alias] = (None, f"alias {alias}: no census route (source dir not found)")
                    elif not template_repo:
                        census_cache[alias] = (None, f"alias {alias}: no census route (templateRepo unknown)")
                    else:
                        names_c, reason_c = _census_mcp_dev_servers_alias(
                            template_repo, source_dir, registration_path, alias)
                        # J1 (fix round 2): prefix the alias HERE, at the one
                        # place `_census_mcp_dev_servers_alias`'s own reason
                        # (list-mcp-tools.py exit code, unparseable output,
                        # etc.) enters the cache -- that function does not
                        # name the alias itself, and a SKIP with a generic or
                        # alias-less reason is a silent hole the consumer
                        # cannot act on. Every other branch above already
                        # constructs its reason pre-prefixed.
                        census_cache[alias] = (
                            names_c, f"alias {alias}: {reason_c}" if reason_c else None)
            names, skip_reason = census_cache[alias]
            for tok, name in toks_for_alias:
                if names is not None:
                    if name in names:
                        resolved += 1
                    else:
                        not_exported.append(tok)
                else:
                    skip_aliases[alias] = skip_reason or f"alias {alias}: no census route"
            continue
        skip_aliases.setdefault(alias, f"alias {alias}: no census route")

    if not_exported:
        return _line("agent_grants_resolvable", "FAIL", f"not exported: {not_exported}",
                     "every granted token exists in its server's exports",
                     "fix the token name in .claude/agent-grants.json (or remove it if the tool was "
                     "renamed/removed)")
    if skip_aliases:
        return _skip("agent_grants_resolvable", "; ".join(sorted(skip_aliases.values())))
    return _line("agent_grants_resolvable", "PASS", f"resolved={resolved}", "n/a (informational)")


def _check_agent_grants_names_known(pp: pathlib.Path, manifest: dict) -> dict:
    try:
        grants = v3.load_grants(pp)
    except (v3.GrantsError, v3.GrantRefused) as e:
        return _line("agent_grants_names_known", "FAIL", str(e),
                     "every grant key names a shipped agent", "fix .claude/agent-grants.json")
    if not grants:
        return _line("agent_grants_names_known", "PASS", "grants=0",
                     "every grant key names a shipped agent")
    shipped = _shipped_agent_names(manifest)
    unknown = sorted(k for k in grants if k not in shipped)
    if unknown:
        return _line("agent_grants_names_known", "FAIL", f"unknown agent name(s): {unknown}",
                     f"every grant key in {sorted(shipped)}",
                     "fix the agent name in .claude/agent-grants.json")
    return _line("agent_grants_names_known", "PASS",
                 f"{len(grants)} grant key(s), all shipped agents",
                 "every grant key names a shipped agent")


def _check_agent_grants_extendable(pp: pathlib.Path, manifest: dict) -> dict:
    try:
        grants = v3.load_grants(pp)
    except (v3.GrantsError, v3.GrantRefused) as e:
        return _line("agent_grants_extendable", "FAIL", str(e),
                     "every grant key names an agent with a one-line tools:",
                     "fix .claude/agent-grants.json")
    if not grants:
        return _line("agent_grants_extendable", "PASS", "grants=0",
                     "every grant key names an agent with a one-line tools:")
    bad: list[str] = []
    # Force template_content()'s placeholder-only path (F1-c2 fix): this
    # loop needs the UN-spliced rendering to test splice_tools() itself --
    # calling template_content() with the REAL (v4) manifest would already
    # splice this exact agent's own grants (it is iterating grants.items()),
    # double-splicing when splice_tools() runs again below. A shallow copy
    # with manifest_version forced to 3 is inert for this purpose (rules is
    # never consulted by template_content -- see its docstring).
    plain_manifest = dict(manifest, manifest_version=3)
    for agent_name, agent_grants in grants.items():
        path = _agent_template_path_by_name(manifest, agent_name)
        if path is None:
            continue  # unknown name -- owned by agent_grants_names_known, not duplicated here
        raw = core._read_file(path)
        rendered = v3.template_content(pp, plain_manifest, None, f"{v3.AGENTS_DIR_PREFIX}{path.name}", raw)
        if rendered is None:
            continue
        try:
            v3.splice_tools(rendered, agent_grants)
        except v3.GrantRefused:
            bad.append(agent_name)
        except v3.GrantsError:
            continue  # a shape defect (list-form/*), not "no tools: line" -- a different check's business
    if bad:
        return _line("agent_grants_extendable", "FAIL",
                     f"agent(s) with no tools: line: {sorted(bad)}",
                     "every grant key names an agent with a one-line tools:",
                     "remove the grant, or give the agent a tools: line")
    return _line("agent_grants_extendable", "PASS",
                 f"{len(grants)} grant key(s), all extendable",
                 "every grant key names an agent with a one-line tools:")


def run(project_path: str, template_repo: str = "", mode: str = "post_commit") -> dict:
    pp = pathlib.Path(project_path).resolve()
    results: list[dict] = []
    done: set[str] = set()

    def emit(line: dict) -> None:
        results.append(line)
        done.add(line["id"])

    manifest, load_errors = core._load_manifest(pp)
    if manifest is None:
        emit(_line("manifest_valid", "FAIL", load_errors[0] if load_errors else "manifest missing",
                   "manifest loads with no errors",
                   "run /sync-template, or setup-project.sh/.ps1, to create "
                   ".claude/template-manifest.json"))
        _cascade_skip(results, done, "no manifest at .claude/template-manifest.json")
        emit(_check_manifest_bytes(pp))
        emit(_check_legacy_gate_dir(pp))
        emit(_check_tree_clean(pp, mode))
        return _finalize(results, mode)

    if template_repo:
        manifest = dict(manifest)
        manifest["templateRepo"] = template_repo

    if load_errors:
        emit(_line("manifest_valid", "FAIL", "; ".join(load_errors), "no errors",
                   "fix the manifest field(s) named above"))
    else:
        emit(_line("manifest_valid", "PASS", "no errors", "no errors"))

    mv = manifest.get("manifest_version")
    mv_supported = v3.manifest_supported(manifest)
    if mv_supported:
        emit(_line("manifest_version_supported", "PASS", f"manifest_version={mv}", "3 or 4"))
    else:
        emit(_line("manifest_version_supported", "FAIL", f"manifest_version={mv!r}", "3 or 4",
                   "run template_migrate_manifest to upgrade this manifest to v3 or v4"))

    if not mv_supported or "templateRepo" not in manifest or "variant" not in manifest:
        reason = ("manifest is not v3 or v4, or is missing templateRepo/variant -- "
                  "see manifest_valid / manifest_version_supported")
        _cascade_skip(results, done, reason)
        emit(_check_manifest_bytes(pp))
        emit(_check_legacy_gate_dir(pp))
        emit(_check_tree_clean(pp, mode))
        return _finalize(results, mode)

    # --- requires_server / no_errors / no_warnings ---------------------------
    ok_rs, reason_rs = v3.requires_server_satisfied(
        v3.effective_requires_server_spec(manifest), core.__version__)
    if ok_rs:
        emit(_line("requires_server", "PASS",
                   f"requires_server={manifest.get('requires_server', '')!r} satisfied by server {core.__version__}",
                   "satisfied"))
    else:
        emit(_line("requires_server", "FAIL", reason_rs, f"satisfied by server {core.__version__}",
                   "upgrade template-sync-tools (bash server/install.sh in the toolkit checkout) and restart"))

    template_dir = core._get_template_dir(manifest)
    # R-C (original brief): a malformed .claude/agent-grants.json is an
    # apply/status ERROR for every agent path, reported through THIS
    # existing FAIL line -- no new line. Checked here (before `rules` is
    # even loaded) so a shape defect is visible even when the rest of the
    # v3-dependent chain below never runs.
    grants_shape_error = None
    try:
        v3.load_grants(pp)
    except v3.GrantsError as e:
        grants_shape_error = str(e)
    if not template_dir.is_dir():
        emit(_line("no_errors", "FAIL", f"template directory not found: {template_dir}",
                   "template variant directory exists",
                   "fix templateRepo/variant in .claude/template-manifest.json"))
    elif grants_shape_error:
        emit(_line("no_errors", "FAIL", grants_shape_error,
                   "template variant directory exists; .claude/agent-grants.json is well-formed",
                   "fix .claude/agent-grants.json"))
    else:
        emit(_line("no_errors", "PASS", f"template directory found: {template_dir}",
                   "template variant directory exists"))

    rules = v3.load_ownership(manifest["templateRepo"])
    if rules is None:
        reason = f"{v3.OWNERSHIP_FILE} not found in template repo -- this checkout predates v3.1"
        _cascade_skip(results, done, reason)
        emit(_check_manifest_bytes(pp))
        emit(_check_legacy_gate_dir(pp))
        emit(_check_tree_clean(pp, mode))
        return _finalize(results, mode)

    if rules.warnings:
        emit(_line("no_warnings", "FAIL", "; ".join(rules.warnings), "no warnings",
                   f"fix {v3.OWNERSHIP_FILE} in the template repo"))
    else:
        emit(_line("no_warnings", "PASS", "no warnings", "no warnings"))

    repo = core._template_repo_resolved(manifest)

    # --- template_commit_known / template_behind_head -----------------------
    commit = v3.manifest_commit(manifest)
    if not commit:
        emit(_line("template_commit_known", "FAIL", "no template_commit/lastSynced in manifest",
                   "manifest names a known commit", "run a full /sync-template to record template_commit"))
        emit(_line("template_behind_head", "INFO", "template_commit unknown -- cannot compare to HEAD",
                   "n/a (informational)"))
    else:
        known = core._run_git(["cat-file", "-e", f"{commit}^{{commit}}"], cwd=repo)["exit_code"] == 0
        if not known:
            emit(_line("template_commit_known", "FAIL", f"{commit!r} is unknown to the template repo at {repo}",
                       "git cat-file -e <template_commit>^{commit} succeeds",
                       "fetch/pull the template repo, or fix templateRepo in the manifest"))
            emit(_line("template_behind_head", "INFO",
                       "template_commit is unknown to this template repo -- cannot compare to HEAD",
                       "n/a (informational)"))
        else:
            describe = core._run_git(["describe", "--tags", commit], cwd=repo)
            label = describe["stdout"].strip() if describe["exit_code"] == 0 else "no tag reaches this commit"
            emit(_line("template_commit_known", "PASS", f"{commit} known; describe --tags = {label}",
                       "known commit; template_version derivable via describe --tags"))
            head_r = core._run_git(["rev-parse", "HEAD"], cwd=repo)
            head_sha = head_r["stdout"].strip() if head_r["exit_code"] == 0 else None
            if head_sha is None:
                emit(_line("template_behind_head", "INFO", "template repo HEAD unavailable",
                           "n/a (informational)"))
            else:
                head_describe = core._run_git(["describe", "--tags", "HEAD"], cwd=repo)
                head_label = head_describe["stdout"].strip() if head_describe["exit_code"] == 0 else head_sha
                if head_sha == commit:
                    emit(_line("template_behind_head", "INFO",
                               f"HEAD describe: {head_label}; template repo is at the synced commit",
                               "n/a (informational)"))
                else:
                    same_tree = all(
                        v3._tree_id(repo, commit, p) == v3._tree_id(repo, head_sha, p)
                        for p in rules.tracked_paths
                    )
                    tree_word = "unchanged" if same_tree else "differs"
                    emit(_line("template_behind_head", "INFO",
                               f"HEAD describe: {head_label}; template-tracked tree ({', '.join(rules.tracked_paths)}) "
                               f"{tree_word} since template_commit {commit}",
                               "n/a (informational) -- the template repo advancing past the synced "
                               "commit is not a failure"))

    # --- unknown_keys_empty / superseded_absent ------------------------------
    unknown = v3.unknown_top_level_keys(manifest)
    if unknown:
        emit(_line("unknown_keys_empty", "FAIL", f"unknown top-level keys: {unknown}", "[]",
                   "remove or rename the key (a key starting 'x-' is consumer-owned and is never "
                   "promoted; every other unknown key is preserved but read by nothing)"))
    else:
        emit(_line("unknown_keys_empty", "PASS", "no unknown top-level keys", "[]"))

    superseded = [k for k in v3.SUPERSEDED_KEYS if k in manifest]
    if superseded:
        emit(_line("superseded_absent", "FAIL", f"still present: {superseded}", "[]",
                   "run /sync-template on toolkit >= 4.0.1; finalize drops these keys unconditionally"))
    else:
        emit(_line("superseded_absent", "PASS", "none of lastSynced/lastSyncedVersion/lastSyncedVersionOf present",
                   "[]"))

    # --- server_skew ----------------------------------------------------------
    server_in_repo = core._server_in_template_repo(manifest.get("templateRepo", ""))
    if not server_in_repo:
        emit(_skip("server_skew", "the running server is not installed from this template repo -- skew not checked"))
    elif core.SERVER_COMMIT is None:
        emit(_skip("server_skew", "server_commit unavailable (server source is not a git checkout)"))
    else:
        server_commit = core.SERVER_COMMIT
        diff = core._run_git(["diff", "--quiet", server_commit, "HEAD", "--", "server/"], cwd=repo)
        status_out = core._run_git(["status", "--porcelain", "--", "server/"], cwd=repo)
        dirty_diff = diff["exit_code"] != 0
        dirty_status = bool(status_out["stdout"].strip())
        head_r = core._run_git(["rev-parse", "HEAD"], cwd=repo)
        head_sha = head_r["stdout"].strip() if head_r["exit_code"] == 0 else None
        if dirty_diff or dirty_status:
            emit(_line("server_skew", "FAIL",
                       f"server/ differs from the imported commit {server_commit} "
                       f"(committed diff dirty={dirty_diff}, working tree dirty={dirty_status})",
                       "server/ matches the running server's imported commit", "restart the session"))
        elif head_sha is not None and head_sha != server_commit:
            emit(_line("server_skew", "INFO",
                       f"template repo HEAD {head_sha} advanced past imported server_commit {server_commit} "
                       f"(server/ itself unchanged)", "n/a (informational)"))
        else:
            emit(_line("server_skew", "PASS", f"server_commit {server_commit} == HEAD; server/ unchanged",
                       "server_commit == HEAD, or server/ unchanged since"))

    # --- status_clean / gate_self_reference_empty / unclassified_empty / ----
    # --- new_template_files_empty / classes_and_hashes / region_markers -----
    status = v3.compute_status_v3(pp, manifest, rules)
    # R-P (fix round 1): compute_status_v3 returns {"error": ...} on a
    # malformed grants file (R-C) rather than raising -- every line below
    # that reads status[...] must report FAIL with that message instead of
    # crashing with a KeyError (never a null-case green either). Grepped
    # (constraint 11) -- every `status[` / status-dict read in this module:
    # status["summary"], status["files"] (x6, including the entry_status
    # lookup for classes_and_hashes and the key_audit/encoding_drift/
    # once_notes_changed loops below), status["gate_self_reference"],
    # status["unclassified_template_files"], status["new_template_files"].
    # All are inside this block or the declared_keys/encoding_drift/
    # once_notes_changed blocks further down, each now guarded the same way.
    status_error = status.get("error") if isinstance(status, dict) else "compute_status_v3 returned a non-dict result"

    if status_error:
        emit(_line("status_clean", "FAIL", status_error, "0 updated / 0 edited / 0 missing, no CONFLICT",
                   "fix the error above (see no_errors)"))
    else:
        summary = status["summary"]
        conflicts = [p for p, info in status["files"].items() if info.get("status") == "CONFLICT"]
        updated, edited, missing = (summary.get("template_updated", 0), summary.get("local_edited", 0),
                                    summary.get("missing", 0))
        migration_required = [p for p, info in status["files"].items()
                              if info.get("status") == "MIGRATION_REQUIRED"]
        if migration_required:
            # The v3-manifest window (R-J, R-K): ONE fact, ONE FAIL, ONE remedy --
            # reported alone, ahead of any other drift this consumer may also
            # carry, because migrating is the one action that resolves it.
            emit(_line("status_clean", "FAIL", f"MIGRATION_REQUIRED: {sorted(migration_required)}",
                       "0 updated / 0 edited / 0 missing, no CONFLICT", v3.MIGRATION_REQUIRED_REMEDY))
        elif updated or edited or missing or conflicts:
            # A stale STORED hash (v4.0.2, item 16): `finalize_sync(new_files=...)`
            # only ADDS entries -- a tracked path updated on disk outside
            # template_apply_file keeps its stale hash and reads LOCAL_EDITED with
            # an EMPTY local_diff (the overwrite-would-discard diff is empty
            # because the project already equals the template; only the STORED
            # hash disagrees). That is a different remedy than a real local edit.
            stale = [p for p, i in status["files"].items()
                     if i.get("status") == "LOCAL_EDITED" and i.get("local_diff") == ""]
            measured = (f"template_updated={updated}, local_edited={edited}, missing={missing}, "
                        f"CONFLICT={len(conflicts)}")
            remedy = "run /sync-template to bring the project back up to date"
            if stale:
                measured += f"; stale stored hash (LOCAL_EDITED, empty local_diff): {stale}"
                remedy += ("; for a stale stored hash pass the path in "
                           "template_finalize_sync(applied_files=[...]) -- new_files never refreshes "
                           "a tracked entry")
            emit(_line("status_clean", "FAIL", measured,
                       "0 updated / 0 edited / 0 missing, no CONFLICT", remedy))
        else:
            emit(_line("status_clean", "PASS",
                       f"template_updated=0, local_edited=0, missing=0, CONFLICT=0 (of {len(status['files'])} tracked)",
                       "0 updated / 0 edited / 0 missing, no CONFLICT"))

    if status_error:
        emit(_line("gate_self_reference_empty", "FAIL", status_error, "[]",
                   "fix the error above (see no_errors)"))
    else:
        gate_hits = status["gate_self_reference"]
        if gate_hits:
            emit(_line("gate_self_reference_empty", "FAIL", f"{gate_hits}", "[]",
                       "move the **Gate**/**Test** command off a template-class path "
                       "(e.g. scripts/gate.sh) and point the key there"))
        else:
            emit(_line("gate_self_reference_empty", "PASS", "no gate self-reference", "[]"))

    if status_error:
        emit(_line("unclassified_empty", "FAIL", status_error, "[]", "fix the error above (see no_errors)"))
    else:
        unclassified = status["unclassified_template_files"]
        if unclassified:
            emit(_line("unclassified_empty", "FAIL", f"{unclassified}", "[]",
                       f"add a rule for these paths to {v3.OWNERSHIP_FILE}, or reclassify them as project-owned"))
        else:
            emit(_line("unclassified_empty", "PASS", "no unclassified template files", "[]"))

    if status_error:
        emit(_line("new_template_files_empty", "FAIL", status_error, "[]", "fix the error above (see no_errors)"))
    else:
        new_files = status["new_template_files"]
        if new_files:
            mapping = ", ".join(f"{p} -> {core.template_path_for(p, manifest)}" for p in new_files)
            emit(_line("new_template_files_empty", "FAIL", f"{new_files}", "[]",
                       "register once-class files via template_finalize_sync(new_files=[...]) "
                       f"(zero bytes written) or apply template-class files; template paths: {mapping}"))
        else:
            emit(_line("new_template_files_empty", "PASS", "no new, unregistered template files", "[]"))

    # classes_and_hashes (item 10): SHAPE (template-with-hash / once-
    # without-hash, as before) plus a closed status PARTITION over every
    # template-class entry. Drift itself -- whether the partition holds
    # anything other than all-IDENTICAL -- is status_clean's assertion
    # alone; duplicating it here (the old `identical_count !=
    # template_class_count` arm) made one accepted deviation (e.g. an
    # ACKNOWLEDGED_KEPT or a LOCAL_EDITED file) FAIL two lines for the same
    # reason.
    if status_error:
        expected = ("every files entry is template-with-hash or once-without-hash; "
                    "every template-class entry's status is one of "
                    + ", ".join(TEMPLATE_CLASS_STATUSES))
        emit(_line("classes_and_hashes", "FAIL", status_error, expected, "fix the error above (see no_errors)"))
    else:
        invalid_entries = []
        template_class_paths = []
        for path, entry in manifest.get("files", {}).items():
            ownership = entry.get("ownership")
            if ownership == "template":
                template_class_paths.append((path, core._normalize_path(path)))
                if not v3.parse_hash(entry.get("hash", "")):
                    invalid_entries.append(f"{path}: ownership=template but hash is not sha256:<64 hex>")
            elif ownership == "once":
                if "hash" in entry:
                    invalid_entries.append(f"{path}: ownership=once but carries a hash key")
            else:
                invalid_entries.append(f"{path}: ownership is {ownership!r}, not template/once")

        buckets = {s: 0 for s in TEMPLATE_CLASS_STATUSES}
        unenumerated = []
        for path, norm in template_class_paths:
            entry_status = status["files"].get(norm, {}).get("status")
            if entry_status in buckets:
                buckets[entry_status] += 1
            else:
                unenumerated.append(entry_status)

        # unenumerated may mix None (a template-class path compute_status_v3
        # omitted from `files`, .get(...).get("status") resolving to None) with
        # a str (an actual unenumerated status name) -- sorted(set(...)) alone
        # raises TypeError comparing str and NoneType, so the dedupe sorts by
        # str() (review round 1: test_classes_and_hashes_unenumerated_none_no_crash).
        unenumerated_distinct = sorted(set(unenumerated), key=str)
        partition_text = " ".join(f"{s.lower()}={buckets[s]}" for s in TEMPLATE_CLASS_STATUSES)
        if unenumerated_distinct:
            partition_text += " " + " ".join(f"unenumerated={u}" for u in unenumerated_distinct)
        expected = ("every files entry is template-with-hash or once-without-hash; "
                    "every template-class entry's status is one of "
                    + ", ".join(TEMPLATE_CLASS_STATUSES))

        if invalid_entries or unenumerated:
            measured = partition_text
            if invalid_entries:
                measured += f"; invalid entries: {invalid_entries}"
            emit(_line("classes_and_hashes", "FAIL", measured, expected,
                       "run /sync-template to bring template-class files up to date; fix any malformed manifest entry"))
        else:
            emit(_line("classes_and_hashes", "PASS", partition_text, expected))

    tracked_paths = list(manifest.get("files", {}).keys())
    malformed = []
    for proj_rel in tracked_paths:
        content = core._read_file(pp / core._normalize_path(proj_rel))
        if content is not None and v3.markers_malformed(content):
            malformed.append(proj_rel)
    if malformed:
        emit(_line("region_markers", "FAIL", f"malformed PROJECT-CUSTOM markers: {malformed}",
                   "no malformed PROJECT-CUSTOM markers",
                   "fix the BEGIN/END marker pair in the file(s) named above (see docs/template-sync.md)"))
    else:
        emit(_line("region_markers", "PASS",
                   f"markers well-formed on {len(tracked_paths)} of {len(tracked_paths)} tracked files",
                   "no malformed PROJECT-CUSTOM markers"))

    # --- claude_md_identical / import_line_present / instructions_file_present
    if v3.is_v4_manifest(manifest):
        emit(_check_claude_md_identical(pp, manifest, rules))
        emit(_check_import_line_present(pp))
        emit(_check_instructions_file_present(pp, manifest))
    else:
        reason = _claude_md_window_reason(manifest, rules)
        emit(_skip("claude_md_identical", reason))
        emit(_skip("import_line_present", reason))
        emit(_skip("instructions_file_present", reason))

    # --- agent_grants_resolvable / agent_grants_names_known / agent_grants_extendable
    emit(_check_agent_grants_resolvable(pp, manifest))
    emit(_check_agent_grants_names_known(pp, manifest))
    emit(_check_agent_grants_extendable(pp, manifest))

    # --- declared_keys ----------------------------------------------------
    if status_error:
        emit(_line("declared_keys", "FAIL", status_error, "[]", "fix the error above (see no_errors)"))
    else:
        missing_all = []
        audited_count = 0
        for path, info in status["files"].items():
            ka = info.get("key_audit")
            if ka is None:
                continue
            audited_count += 1
            for item in ka.get("missing_declared_keys", []):
                missing_all.append({"path": path, **item})
        if missing_all:
            emit(_line("declared_keys", "FAIL", f"{missing_all}", "[]",
                       "declare the missing keys, or run /sync-template to re-derive template_default"))
        else:
            emit(_line("declared_keys", "PASS", f"0 missing across {audited_count} audited file(s)", "[]"))

    # --- encoding_drift (INFO) ---------------------------------------------
    # INFO_LINE kind (never FAIL_LINE): an error dict is reported as INFO
    # naming the error, never as a null-case "no drift" green and never a
    # crash -- but never "FAIL" either, which would be the wrong kind for an
    # id that can never affect `ok` by design.
    if status_error:
        emit(_line("encoding_drift", "INFO", f"cannot compute -- {status_error}", "n/a (informational)"))
    else:
        drift = [{"path": p, "drift": info["encoding_drift"]}
                 for p, info in status["files"].items() if info.get("encoding_drift")]
        if drift:
            emit(_line("encoding_drift", "INFO", f"{drift}", "n/a (informational)"))
        else:
            emit(_line("encoding_drift", "INFO", "no encoding drift (bom/crlf) on any tracked file",
                       "n/a (informational)"))

    # --- project_md_seed_current / project_md_scoped_consistent (INFO) ------
    # A `paths:`-scoped project.md is exempt from the seed-sentence check:
    # the seed sentences are ABOUT being unscoped ("This file has no
    # `paths:` key...", "...loads it at EVERY session start"), so a scoped
    # file has made them inapplicable by its own edit -- do not "fix" this
    # exemption by flagging scoped files on THIS line; a scoped file that
    # still carries either sentence verbatim is a self-contradiction, and
    # that has its own line below.
    project_md = core._read_file(pp / v3.PROJECT_MD)
    scoped = project_md is not None and _project_md_scoped(project_md)
    if project_md is None:
        emit(_line("project_md_seed_current", "INFO", f"{v3.PROJECT_MD} not present", "n/a (informational)"))
    elif scoped:
        emit(_line("project_md_seed_current", "INFO",
                   "scoped (paths: present); seed sentences not applicable",
                   "n/a (informational)"))
    elif _guidance_line_names_region(project_md):
        # Harm-keyed on the SENTENCE, not the token (v4.1.2 spec §2): the line
        # that starts "Always-on project rules belong in" is the one that points
        # a consumer somewhere; only when THAT line names PROJECT-CUSTOM is the
        # consumer being pointed at the region v4.1.0 removed. Prose elsewhere
        # in the file -- a consumer's own note that the region was retired --
        # is prose ABOUT the thing, and never fires this arm (panoscribe
        # measured the substring form firing on exactly such a note, with the
        # guidance already repointed, and a remedy that had nothing to fix).
        emit(_line("project_md_seed_current", "INFO",
                   f"{v3.PROJECT_MD} guidance line points at PROJECT-CUSTOM, a region v4.1.0 removed",
                   "n/a (informational)",
                   "hand-edit .claude/rules/project.md (once-class: the sync never writes it): "
                   "repoint the 'Always-on project rules belong in' sentence at "
                   ".claude/project-instructions.md; an older seed sentence may also be present; "
                   "re-run after fixing"))
    elif "delivered to nobody" in project_md:
        emit(_line("project_md_seed_current", "INFO",
                   f"{v3.PROJECT_MD} still carries the pre-v4.0.1 seed's false 'delivered to nobody' sentence",
                   "n/a (informational)",
                   "hand-edit .claude/rules/project.md (once-class: the sync never writes it): "
                   "remove the false 'This file has been delivered to nobody' sentence and add the sentence "
                   "'A new or edited rules file is picked up at the NEXT session start, not the current one' "
                   "to the header, or replace the whole header with the v4.0.2 seed; if the body holds "
                   "migration hunks (a pre-v4.0.1 migration), move them into the region or a scoped rules "
                   "file FIRST -- see CHANGELOG.md's v4.0.2 downstream-migration section"))
    elif "picked up at the NEXT session start" not in project_md:
        emit(_line("project_md_seed_current", "INFO",
                   f"{v3.PROJECT_MD} seed predates v4.0.2 (no next-session sentence)",
                   "n/a (informational)",
                   "hand-edit .claude/rules/project.md (once-class: the sync never writes it): "
                   "add the sentence 'A new or edited rules file is picked up at the NEXT session start, "
                   "not the current one' to the header, or replace the whole header with the v4.0.2 seed; "
                   "if the body holds migration hunks (a pre-v4.0.1 migration), move them into the region "
                   "or a scoped rules file FIRST -- see CHANGELOG.md's v4.0.2 downstream-migration section"))
    else:
        emit(_line("project_md_seed_current", "INFO", f"{v3.PROJECT_MD} seed is current", "n/a (informational)"))

    # --- project_md_seed_differs (INFO, fact only, no remedy) ---------------
    # Two questions, two lines (§2.1): project_md_seed_current is a JUDGEMENT
    # ("is this seed current / harmful"); this one is a FACT ("does this
    # consumer's file still start with the shipped seed text"), answered by a
    # PREFIX test, never a byte-compare of the whole file -- a consumer who
    # appended their own rules after the seed is not "different" by this
    # line's answer, only one who edited the seed text itself is. No remedy:
    # a deliberate, once-class edit is not something this line tells the
    # consumer to undo -- it only points at where the shipped text lives.
    if project_md is None:
        emit(_line("project_md_seed_differs", "INFO", f"{v3.PROJECT_MD} not present", "n/a (informational)"))
    else:
        shipped_seed_path = core._template_file_path(manifest, v3.PROJECT_MD)
        shipped_seed = core._read_file(shipped_seed_path)
        if shipped_seed is None:
            emit(_line("project_md_seed_differs", "INFO",
                       f"shipped seed not found at {shipped_seed_path} -- cannot compare",
                       "n/a (informational)"))
        elif project_md.startswith(shipped_seed):
            emit(_line("project_md_seed_differs", "INFO",
                       "seed matches the shipped seed (rules appended after it)", "n/a (informational)"))
        else:
            emit(_line("project_md_seed_differs", "INFO",
                       "seed text differs from the shipped seed at this template "
                       "(an annotation inserted INSIDE the seed text also reads as differs -- that is the "
                       "consumer's own edit, and it carries no remedy by design)", "n/a (informational)",
                       "shipped seed: templates/<variant>/.claude/rules/project.md; this file is once-class "
                       "and no sync writes it"))

    if not scoped:
        emit(_line("project_md_scoped_consistent", "INFO", "n/a (unscoped or absent)", "n/a (informational)"))
    else:
        unscoped_sentences = ("This file has no `paths:` key", "loads it at EVERY session start")
        if any(s in project_md for s in unscoped_sentences):
            emit(_line("project_md_scoped_consistent", "INFO",
                       "scoped file still carries the unscoped seed sentence(s)",
                       "n/a (informational)",
                       "delete the unscoped seed sentences -- they describe a file without paths:"))
        else:
            emit(_line("project_md_scoped_consistent", "INFO", "scoped, no unscoped sentence",
                       "n/a (informational)"))

    # --- legacy_gate_dir (INFO) ---------------------------------------------
    emit(_check_legacy_gate_dir(pp))

    # --- once_notes_changed (INFO) ------------------------------------------
    if status_error:
        emit(_line("once_notes_changed", "INFO", f"cannot compute -- {status_error}", "n/a (informational)"))
    else:
        notes_changed = [
            (path, info["key_audit"]["template_notes_changed"])
            for path, info in status["files"].items()
            if info.get("ownership") == "once" and info.get("key_audit", {}).get("template_notes_changed")
        ]
        if notes_changed:
            # `_finalize` requires exactly one result row per id (the
            # `template_verify` witness asserts len(lines) == len(LINES)), so a
            # once-class file per row would break that invariant on a consumer
            # with more than one changed file -- emit ONE line, every file
            # "; "-joined (ruling R2).
            parts = "; ".join(f"{path}: template guidance comments changed (hunks: {len(hunks)})"
                              for path, hunks in notes_changed)
            emit(_line("once_notes_changed", "INFO", parts, "n/a (informational)",
                       "read the hunks with template_get_diff and update your copy by hand -- "
                       "once-class files are never overwritten"))
        else:
            emit(_line("once_notes_changed", "INFO", "no once-class file has changed template notes",
                       "n/a (informational)"))

    emit(_check_manifest_bytes(pp))
    emit(_check_tree_clean(pp, mode))
    return _finalize(results, mode)


def _finalize(results: list[dict], mode: str) -> dict:
    done = {r["id"] for r in results}
    for id_, _kind in LINES:
        if id_ not in done:
            results.append(_skip(id_, "not evaluated (a prerequisite failed earlier in the chain)"))
    order = {id_: i for i, (id_, _kind) in enumerate(LINES)}
    results.sort(key=lambda r: order[r["id"]])
    pass_n = sum(1 for r in results if r["status"] == "PASS")
    fail_n = sum(1 for r in results if r["status"] == "FAIL")
    skip_n = sum(1 for r in results if r["status"] == "SKIP")
    info_n = sum(1 for r in results if r["status"] == "INFO")
    summary = f"{pass_n} PASS, {fail_n} FAIL, {skip_n} SKIP, {info_n} INFO"
    return {"ok": fail_n == 0, "mode": mode, "summary": summary, "lines": results}
