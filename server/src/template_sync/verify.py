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

import pathlib

from . import mcp as core
from . import v3

FAIL_LINE = "FAIL_LINE"
INFO_LINE = "INFO_LINE"

# Order is the contract: the CLI and the fleet script print in this order,
# and test_template_sync_verify.py derives its PASS-fixture counts from it.
LINES = (
    ("manifest_valid", FAIL_LINE),
    ("manifest_version_3", FAIL_LINE),
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
    ("manifest_bytes", FAIL_LINE),
    ("declared_keys", FAIL_LINE),
    ("encoding_drift", INFO_LINE),
    ("project_md_seed_current", INFO_LINE),
    ("legacy_gate_dir", INFO_LINE),
    ("once_notes_changed", INFO_LINE),
    ("project_md_scoped_consistent", INFO_LINE),
    ("tree_clean", FAIL_LINE),
)

_IDS = tuple(i for i, _ in LINES)

# Ids computed independently of manifest shape (raw bytes / project git
# state) -- these still run even when every v3-dependent id below them is
# short-circuited to SKIP.
_SHAPE_INDEPENDENT = ("manifest_valid", "manifest_version_3", "manifest_bytes", "tree_clean",
                      "legacy_gate_dir")


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
    if mv == 3:
        emit(_line("manifest_version_3", "PASS", f"manifest_version={mv}", "3"))
    else:
        emit(_line("manifest_version_3", "FAIL", f"manifest_version={mv!r}", "3",
                   "run template_migrate_manifest to upgrade this manifest to v3"))

    if mv != 3 or "templateRepo" not in manifest or "variant" not in manifest:
        reason = ("manifest is not v3, or is missing templateRepo/variant -- "
                  "see manifest_valid / manifest_version_3")
        _cascade_skip(results, done, reason)
        emit(_check_manifest_bytes(pp))
        emit(_check_legacy_gate_dir(pp))
        emit(_check_tree_clean(pp, mode))
        return _finalize(results, mode)

    # --- requires_server / no_errors / no_warnings ---------------------------
    ok_rs, reason_rs = v3.requires_server_satisfied(manifest.get("requires_server", ""), core.__version__)
    if ok_rs:
        emit(_line("requires_server", "PASS",
                   f"requires_server={manifest.get('requires_server', '')!r} satisfied by server {core.__version__}",
                   "satisfied"))
    else:
        emit(_line("requires_server", "FAIL", reason_rs, f"satisfied by server {core.__version__}",
                   "upgrade template-sync-tools (bash server/install.sh in the toolkit checkout) and restart"))

    template_dir = core._get_template_dir(manifest)
    if template_dir.is_dir():
        emit(_line("no_errors", "PASS", f"template directory found: {template_dir}",
                   "template variant directory exists"))
    else:
        emit(_line("no_errors", "FAIL", f"template directory not found: {template_dir}",
                   "template variant directory exists",
                   "fix templateRepo/variant in .claude/template-manifest.json"))

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
    summary = status["summary"]
    conflicts = [p for p, info in status["files"].items() if info.get("status") == "CONFLICT"]
    updated, edited, missing = (summary.get("template_updated", 0), summary.get("local_edited", 0),
                                summary.get("missing", 0))
    if updated or edited or missing or conflicts:
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

    gate_hits = status["gate_self_reference"]
    if gate_hits:
        emit(_line("gate_self_reference_empty", "FAIL", f"{gate_hits}", "[]",
                   "move the **Gate**/**Test** command off a template-class path "
                   "(e.g. scripts/gate.sh) and point the key there"))
    else:
        emit(_line("gate_self_reference_empty", "PASS", "no gate self-reference", "[]"))

    unclassified = status["unclassified_template_files"]
    if unclassified:
        emit(_line("unclassified_empty", "FAIL", f"{unclassified}", "[]",
                   f"add a rule for these paths to {v3.OWNERSHIP_FILE}, or reclassify them as project-owned"))
    else:
        emit(_line("unclassified_empty", "PASS", "no unclassified template files", "[]"))

    new_files = status["new_template_files"]
    if new_files:
        mapping = ", ".join(f"{p} -> {core.template_path_for(p, manifest)}" for p in new_files)
        emit(_line("new_template_files_empty", "FAIL", f"{new_files}", "[]",
                   "register once-class files via template_finalize_sync(new_files=[...]) "
                   f"(zero bytes written) or apply template-class files; template paths: {mapping}"))
    else:
        emit(_line("new_template_files_empty", "PASS", "no new, unregistered template files", "[]"))

    acknowledged = {p for p, info in status["files"].items() if info.get("status") == "ACKNOWLEDGED_KEPT"}
    invalid_entries = []
    template_class_count = 0
    for path, entry in manifest.get("files", {}).items():
        ownership = entry.get("ownership")
        if ownership == "template":
            if core._normalize_path(path) not in acknowledged:
                template_class_count += 1
            if not v3.parse_hash(entry.get("hash", "")):
                invalid_entries.append(f"{path}: ownership=template but hash is not sha256:<64 hex>")
        elif ownership == "once":
            if "hash" in entry:
                invalid_entries.append(f"{path}: ownership=once but carries a hash key")
        else:
            invalid_entries.append(f"{path}: ownership is {ownership!r}, not template/once")
    identical_count = summary.get("identical", 0)
    if invalid_entries or identical_count != template_class_count:
        emit(_line("classes_and_hashes", "FAIL",
                   f"identical={identical_count}, template_class_count={template_class_count}, "
                   f"acknowledged_kept={len(acknowledged)}; invalid entries: {invalid_entries}",
                   "every files entry is template-with-hash or once-without-hash; "
                   "IDENTICAL count == template-class count (acknowledged-kept entries excluded)",
                   "run /sync-template to bring template-class files up to date; fix any malformed manifest entry"))
    else:
        emit(_line("classes_and_hashes", "PASS",
                   f"identical={identical_count} == template_class_count={template_class_count}, "
                   f"acknowledged_kept={len(acknowledged)}; "
                   "every entry template-with-hash or once-without-hash",
                   "every files entry is template-with-hash or once-without-hash; "
                   "IDENTICAL count == template-class count (acknowledged-kept entries excluded)"))

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

    # --- declared_keys ----------------------------------------------------
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
    elif "delivered to nobody" in project_md:
        emit(_line("project_md_seed_current", "INFO",
                   f"{v3.PROJECT_MD} still carries the pre-v4.0.1 seed's false 'delivered to nobody' sentence",
                   "n/a (informational)",
                   "replace the header of .claude/rules/project.md with the v4.0.1 seed (or add a paths: block) "
                   "-- see CHANGELOG.md's v4.0.1 downstream-migration section"))
    elif "picked up at the NEXT session start" not in project_md:
        emit(_line("project_md_seed_current", "INFO",
                   f"{v3.PROJECT_MD} seed predates v4.0.2 (no next-session sentence)",
                   "n/a (informational)",
                   "replace the header of .claude/rules/project.md with the v4.0.2 seed (or add a paths: block) "
                   "-- see CHANGELOG.md's v4.0.2 downstream-migration section"))
    else:
        emit(_line("project_md_seed_current", "INFO", f"{v3.PROJECT_MD} seed is current", "n/a (informational)"))

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
