"""
Template Sync MCP Server Tools

Tools for synchronizing project files with claude-code-toolkit templates:
- Load and validate template manifests (v1/v2)
- Compute sync status across all tracked files
- Generate diffs (two-way and three-way merge)
- Apply file updates with placeholder replacement
- Reverse placeholders for upstream contribution
- Cross-variant propagation
"""

import hashlib
import json
import os
import pathlib
import re
import subprocess
import shutil
import tempfile
import time
from difflib import SequenceMatcher, unified_diff
from mcp.server.fastmcp import FastMCP

from . import __version__

mcp = FastMCP("template-sync-tools")

_SUBPROCESS_FLAGS = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0

# Manifest schema version produced by this server
MANIFEST_VERSION = 2

# Files that are always project-specific (never auto-updated)
ALWAYS_PROJECT_SPECIFIC = {"PROJECT_CONTEXT.md"}

# Known variant directories
KNOWN_VARIANTS = ["general", "dotnet", "dotnet-maui", "rust-tauri", "java", "python"]


# -------------------------
# Helpers
# -------------------------

def _server_source() -> str:
    """Directory of the package this process actually imported.

    An editable install's dist-info is stamped once and never re-stamped, so
    `pip show` can report a version three releases behind the code that is
    running. `server_version` already reads from the imported source; this
    says WHICH checkout that source is, so an editable install can be
    diagnosed rather than inferred. It is a local filesystem path.
    """
    return str(pathlib.Path(__file__).parent)


def _sha256(content: str) -> str:
    """SHA-256 hash of a string (UTF-8, BOM stripped)."""
    if content.startswith("\ufeff"):
        content = content[1:]
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _read_file(path: pathlib.Path) -> str | None:
    """Read a UTF-8 file, return None if missing."""
    try:
        content = path.read_text(encoding="utf-8")
        if content.startswith("\ufeff"):
            content = content[1:]
        return content
    except (FileNotFoundError, OSError):
        return None


def _part_hashes(proj_content: str, tpl_content: str) -> tuple[str, str]:
    """Hash both sides with their PROJECT-CUSTOM region stripped.

    Falls back to full-file content when either side lacks the markers --
    template_apply_file only splices the region when BOTH carry them, so a
    single-sided region is not project-owned.
    """
    proj_part, proj_region = _split_custom_region(proj_content)
    tpl_part, tpl_region = _split_custom_region(tpl_content)
    if proj_region is None or tpl_region is None:
        proj_part, tpl_part = proj_content, tpl_content
    return _sha256(proj_part), (_sha256(tpl_part) if tpl_content else "")


def _write_file_atomic(
    path: pathlib.Path,
    content: str,
    *,
    retries: int = 5,
    backoff: float = 0.2,
) -> None:
    """Write file atomically via temp + rename.

    newline="" disables universal-newline translation so template LF content
    lands as LF on Windows too (text-mode default would produce CRLF churn
    in every synced consumer — downstream finding 2026-07-19 #5).

    On Windows, os.replace raises PermissionError (WinError 5) while another
    process holds the target open -- e.g. a live hook run executing the very
    script being synced (downstream finding 2026-09-05, MM-Agent v3.0.3).
    The rename is retried `retries` times with linear backoff; if it still
    fails the temp file is removed so no `.tmp` litters the project, and the
    last error propagates.
    """
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(content, encoding="utf-8", newline="")
    try:
        for attempt in range(1, retries + 1):
            try:
                os.replace(str(tmp), str(path))
                return
            except PermissionError:
                if attempt == retries:
                    raise
                time.sleep(backoff * attempt)
    except BaseException:
        try:
            tmp.unlink()
        except OSError:
            pass
        raise


# --- PROJECT-CUSTOM region (downstream finding 2026-07-19 #2) ---------------
# Templates may end with a sentinel region that is PROJECT-owned:
#   <!-- PROJECT-CUSTOM:BEGIN ... -->
#   ...project content...
#   <!-- PROJECT-CUSTOM:END -->
# Region handling activates only when BOTH the template and the project file
# carry the markers. Stored manifest hashes remain FULL-content (backward
# compatible); the region influences classification via post-classification
# reclassification and apply-time splicing only.

CUSTOM_REGION_BEGIN = "<!-- PROJECT-CUSTOM:BEGIN"
CUSTOM_REGION_END = "PROJECT-CUSTOM:END -->"


def _split_custom_region(content: str) -> tuple[str, str | None]:
    """Split content into (template_part, region_block).

    region_block spans from the BEGIN marker through the END marker inclusive.
    Requires BEGIN before END; absent or malformed markers return
    (content, None) — legacy full-file behavior.
    """
    begin = content.find(CUSTOM_REGION_BEGIN)
    if begin == -1:
        return content, None
    end = content.find(CUSTOM_REGION_END, begin)
    if end == -1:
        return content, None
    end += len(CUSTOM_REGION_END)
    return content[:begin] + content[end:], content[begin:end]


def _normalize_path(p: str) -> str:
    """Normalize path to forward slashes."""
    return p.replace("\\", "/")


def _resolve_path(p: str) -> pathlib.Path:
    """Resolve a path, converting MSYS /x/... to X:\\ on Windows."""
    import re
    if os.name == "nt" and re.match(r"^/[a-zA-Z]/", p):
        p = p[1].upper() + ":" + p[2:]
    return pathlib.Path(p).resolve()


def _apply_placeholders(content: str, placeholders: dict[str, str]) -> str:
    """Replace {{KEY}} tokens with concrete values."""
    for key, val in placeholders.items():
        content = content.replace("{{" + key + "}}", val)
    return content


def _reverse_placeholders(content: str, placeholders: dict[str, str]) -> tuple[str, list[dict]]:
    """
    Reverse placeholder replacement: concrete values -> {{KEY}}.

    Sorts by value length descending (longest first) to avoid partial matches.
    Returns (reversed_content, list of replacements made).
    """
    sorted_ph = sorted(placeholders.items(), key=lambda x: (-len(x[1]), x[0]))
    replacements = []
    for key, val in sorted_ph:
        if not val:
            continue
        count = content.count(val)
        if count > 0:
            content = content.replace(val, "{{" + key + "}}")
            replacements.append({"placeholder": key, "value": val, "count": count})
    return content, replacements


def _git_exe() -> str:
    """Find the git executable, preferring .exe on Windows."""
    if os.name == "nt":
        p = shutil.which("git.exe")
        if p:
            return p
    p = shutil.which("git")
    return p or ("git.exe" if os.name == "nt" else "git")


def _run_git(args: list[str], cwd: str, timeout_s: int = 10) -> dict:
    """Run a git command safely."""
    env = os.environ.copy()
    env.update({
        "GIT_TERMINAL_PROMPT": "0",
        "GIT_PAGER": "cat",
        "PAGER": "cat",
        "LC_ALL": "C",
    })
    exe = _git_exe()
    try:
        p = subprocess.run(
            [exe] + args,
            cwd=cwd,
            capture_output=True,
            text=True,
            # Git blobs are UTF-8. Without an explicit codec Python decodes
            # with the locale encoding (cp1252 on Windows), so an em dash in
            # a template came back as mojibake in the reconstructed merge base
            # -- and got committed by anyone pasting auto_merged back.
            encoding="utf-8",
            errors="replace",
            timeout=timeout_s,
            stdin=subprocess.DEVNULL,
            creationflags=_SUBPROCESS_FLAGS,
        )
        return {"exit_code": p.returncode, "stdout": p.stdout, "stderr": p.stderr}
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        return {"exit_code": 1, "stdout": "", "stderr": str(e)}


def _git_head(repo: str) -> str | None:
    """Get short HEAD commit of a repo."""
    r = _run_git(["rev-parse", "--short", "HEAD"], cwd=repo)
    if r["exit_code"] == 0:
        return r["stdout"].strip()
    return None


def _git_show_file(repo: str, commit: str, file_path: str) -> str | None:
    """Retrieve file content at a specific commit via git show."""
    r = _run_git(["show", f"{commit}:{file_path}"], cwd=repo, timeout_s=10)
    if r["exit_code"] == 0:
        content = r["stdout"]
        if content.startswith("\ufeff"):
            content = content[1:]
        return content
    return None


def _load_manifest(project_path: pathlib.Path) -> tuple[dict | None, list[str]]:
    """Load and parse the manifest file. Returns (manifest, errors).

    v3 manifests (manifest_version == 3) require template_commit and
    requires_server on top of the v2 fields; lastSynced is accepted as an
    alias of template_commit.
    """
    manifest_path = project_path / ".claude" / "template-manifest.json"
    content = _read_file(manifest_path)
    if content is None:
        return None, ["No template manifest found at .claude/template-manifest.json"]
    try:
        manifest = json.loads(content)
    except json.JSONDecodeError as e:
        return None, [f"Invalid JSON in manifest: {e}"]

    errors = []
    required = ["variant", "templateRepo", "placeholders", "files"]
    if manifest.get("manifest_version") == 3:
        required += ["requires_server"]
        if not (manifest.get("template_commit") or manifest.get("lastSynced")):
            errors.append("Missing required field: template_commit")
    for field in required:
        if field not in manifest:
            errors.append(f"Missing required field: {field}")
    return manifest, errors


def _template_repo_resolved(manifest: dict) -> str:
    """Get the resolved templateRepo path as a string (handles MSYS paths on Windows)."""
    return str(_resolve_path(manifest["templateRepo"]))


def _get_template_dir(manifest: dict) -> pathlib.Path:
    """Get the template variant directory from manifest."""
    repo = _resolve_path(manifest["templateRepo"])
    return repo / "templates" / manifest["variant"]


# Manifest paths copied from the toolkit repo root rather than from
# templates/<variant>/. Shared hook scripts live at <repo>/hooks/ and are
# copied by the setup script from there, so they must be resolved against the
# repo root -- otherwise sync looks under templates/<variant>/hooks/, finds
# nothing, and falsely reports them TEMPLATE_DELETED.
_ROOT_TRACKED_PREFIXES = ("hooks/",)


def _is_root_tracked(rel_path: str) -> bool:
    """True if rel_path is tracked from the repo root, not the variant dir."""
    norm = _normalize_path(rel_path)
    return any(norm.startswith(prefix) for prefix in _ROOT_TRACKED_PREFIXES)


def _template_file_path(manifest: dict, rel_path: str) -> pathlib.Path:
    """Get full path to a template file.

    Most files live under templates/<variant>/, but root-tracked paths
    (e.g. shared hooks/) are resolved against the toolkit repo root.
    """
    if _is_root_tracked(rel_path):
        return _resolve_path(manifest["templateRepo"]) / _normalize_path(rel_path)
    return _get_template_dir(manifest) / rel_path


def _template_git_path(manifest: dict, rel_path: str) -> str:
    """Repo-root-relative path of a template file (for `git show`)."""
    norm = _normalize_path(rel_path)
    if _is_root_tracked(norm):
        return norm
    return f"templates/{manifest.get('variant', '')}/{norm}"


def _scan_template_files(
    template_dir: pathlib.Path,
    repo_root: pathlib.Path | None = None,
) -> list[str]:
    """Scan for every template-owned file, return sorted relative paths.

    Walks templates/<variant>/ and -- when repo_root is given -- the
    root-tracked trees (<repo>/hooks/**, recursively, including lib/).
    Without the second walk a newly added shared hook never surfaces in
    `new_template_files`, so a consumer applies a settings.json that
    references scripts it does not have and the git gates fail open.
    """
    files = set()
    if template_dir.is_dir():
        for p in template_dir.rglob("*"):
            if p.is_file():
                rel = _normalize_path(str(p.relative_to(template_dir)))
                # Skip gitignore (merge-only, not template-owned)
                if rel == "gitignore":
                    continue
                files.add(rel)
    if repo_root is not None:
        for prefix in _ROOT_TRACKED_PREFIXES:
            root = repo_root / prefix.rstrip("/")
            if not root.is_dir():
                continue
            for p in root.rglob("*"):
                if p.is_file():
                    files.add(_normalize_path(str(p.relative_to(repo_root))))
    return sorted(files)


def _split_merge_ops(ops) -> tuple[dict, dict]:
    """Split difflib opcodes into per-base-line changes and insertion points.

    An `insert` opcode has `i1 == i2`: it sits *before* base line `i1` and
    consumes no base line. Recording it against base line `i1` (which the
    original implementation did, via `range(i1, max(i2, i1 + 1))`) made the
    walk emit the inserted lines *in place of* a line that is still present
    on both sides -- the silent dropped-line bug.
    """
    changes: dict = {}
    inserts: dict = {}
    for tag, i1, i2, j1, j2 in ops:
        if tag == "insert":
            inserts[i1] = (j1, j2)
        elif tag != "equal":
            for i in range(i1, i2):
                changes[i] = (tag, i1, i2, j1, j2)
    return changes, inserts


def _merge_walk(base: str, theirs: str, ours: str) -> tuple[list[str], int]:
    """Line-based three-way merge walk. Returns (merged lines, conflict count)."""
    base_lines = base.splitlines(keepends=True)
    theirs_lines = theirs.splitlines(keepends=True)
    ours_lines = ours.splitlines(keepends=True)

    # Get opcodes for base->theirs and base->ours.
    # autojunk=False: the default treats a line occurring more than
    # len(b)//100 + 1 times as junk once the sequence reaches 200 lines, which
    # on a 1000-line AGENT_TEAM.md excludes every blank line from the matcher
    # -- distorting the merge and blinding the dropped-line guard.
    sm_theirs = SequenceMatcher(None, base_lines, theirs_lines, autojunk=False)
    sm_ours = SequenceMatcher(None, base_lines, ours_lines, autojunk=False)

    theirs_changes, theirs_inserts = _split_merge_ops(sm_theirs.get_opcodes())
    ours_changes, ours_inserts = _split_merge_ops(sm_ours.get_opcodes())

    merged: list[str] = []
    conflict_count = 0
    processed_theirs = set()
    processed_ours = set()

    def emit_inserts(pos: int) -> int:
        """Emit any insertions anchored before base line `pos`."""
        t = theirs_inserts.pop(pos, None)
        o = ours_inserts.pop(pos, None)
        if t is None and o is None:
            return 0
        t_new = theirs_lines[t[0]:t[1]] if t else []
        o_new = ours_lines[o[0]:o[1]] if o else []
        if t and o:
            if t_new == o_new:
                merged.extend(o_new)
                return 0
            merged.append("<<<<<<< PROJECT\n")
            merged.extend(o_new)
            merged.append("=======\n")
            merged.extend(t_new)
            merged.append(">>>>>>> TEMPLATE\n")
            return 1
        merged.extend(o_new if o else t_new)
        return 0

    # Walk through base line by line and decide
    i = 0
    while i < len(base_lines):
        conflict_count += emit_inserts(i)
        in_theirs = i in theirs_changes
        in_ours = i in ours_changes

        if not in_theirs and not in_ours:
            # No changes, keep base
            merged.append(base_lines[i])
            i += 1
        elif in_theirs and not in_ours:
            # Only template changed this region
            tag, i1, i2, j1, j2 = theirs_changes[i]
            if (i1, i2) not in processed_theirs:
                processed_theirs.add((i1, i2))
                merged.extend(theirs_lines[j1:j2])
            i = max(i + 1, i2) if i >= i1 else i + 1
        elif not in_theirs and in_ours:
            # Only project changed this region
            tag, i1, i2, j1, j2 = ours_changes[i]
            if (i1, i2) not in processed_ours:
                processed_ours.add((i1, i2))
                merged.extend(ours_lines[j1:j2])
            i = max(i + 1, i2) if i >= i1 else i + 1
        else:
            # Both changed -- conflict
            t_tag, t_i1, t_i2, t_j1, t_j2 = theirs_changes[i]
            o_tag, o_i1, o_i2, o_j1, o_j2 = ours_changes[i]

            # Check if changes are identical (both made same edit)
            theirs_new = theirs_lines[t_j1:t_j2]
            ours_new = ours_lines[o_j1:o_j2]

            region_key = (t_i1, t_i2, o_i1, o_i2)
            if region_key not in processed_theirs:
                processed_theirs.add(region_key)
                if theirs_new == ours_new:
                    # Same change on both sides, no conflict
                    merged.extend(ours_new)
                else:
                    conflict_count += 1
                    merged.append("<<<<<<< PROJECT\n")
                    merged.extend(ours_new)
                    merged.append("=======\n")
                    merged.extend(theirs_new)
                    merged.append(">>>>>>> TEMPLATE\n")

            end = max(t_i2, o_i2)
            i = max(i + 1, end) if i >= min(t_i1, o_i1) else i + 1

    # Insertions anchored past the last base line are plain appends.
    conflict_count += emit_inserts(len(base_lines))

    # Anything still pending is an insertion whose anchor the walk jumped over
    # because the other side replaced the region containing it. Emitting it
    # inline would be a guess and appending it silently would relocate it to
    # the end of the file -- so surface it as a conflict instead.
    for pos in sorted(set(theirs_inserts) | set(ours_inserts)):
        t = theirs_inserts.pop(pos, None)
        o = ours_inserts.pop(pos, None)
        body: list[str] = []
        if o:
            body.extend(ours_lines[o[0]:o[1]])
        if t:
            body.extend(theirs_lines[t[0]:t[1]])
        merged.append(_conflict_hunk("insertion anchor lost", body))
        conflict_count += 1

    return merged, conflict_count


def _dropped_lines(base: str, theirs: str, ours: str, merged: str) -> list[str]:
    """Lines the merge lost silently.

    A line qualifies when it is present in `base`, left untouched by the
    project (`ours`) and kept by the template (`theirs`) -- yet does not
    appear, *in order*, in `merged`. Order-aware rather than counted: a copy
    of the line reinserted somewhere else must not mask the loss at its own
    position.
    """
    base_lines = base.splitlines(keepends=True)

    def kept_indices(other: str) -> set[int]:
        keep: set[int] = set()
        sm = SequenceMatcher(
            None, base_lines, other.splitlines(keepends=True), autojunk=False
        )
        for tag, i1, i2, _j1, _j2 in sm.get_opcodes():
            if tag == "equal":
                keep.update(range(i1, i2))
        return keep

    required_idx = sorted(kept_indices(theirs) & kept_indices(ours))
    if not required_idx:
        return []
    required = [base_lines[i] for i in required_idx]

    sm = SequenceMatcher(
        None, required, merged.splitlines(keepends=True), autojunk=False
    )
    matched: set[int] = set()
    for tag, i1, i2, _j1, _j2 in sm.get_opcodes():
        if tag == "equal":
            matched.update(range(i1, i2))
    return sorted({required[i] for i in range(len(required)) if i not in matched})


# `node -e <js>` embedded in a hook script, single- or double-quoted. Most of
# the toolkit's hooks use double quotes, so matching only `'...'` missed them.
_NODE_E_RE = re.compile(
    r"""node\s+(?:--[\w-]+\s+)*-e\s+(?:'([^']*)'|"((?:[^"\\]|\\.)*)")""",
    re.DOTALL,
)
# Inside double quotes bash strips a backslash only before these.
_DQ_UNESCAPE = re.compile(r"\\([\"\\$`\n])")


def _node_e_blocks(text: str) -> list[str]:
    """Extract the JS source of every `node -e` invocation in a shell script."""
    blocks = []
    for single, double in _NODE_E_RE.findall(text):
        if single:
            blocks.append(single)
        elif double:
            blocks.append(
                _DQ_UNESCAPE.sub(
                    lambda m: "" if m.group(1) == "\n" else m.group(1), double
                )
            )
    return blocks


def _run_syntax_tool(cmd: list[str], label: str, cwd: str) -> tuple[bool, str | None]:
    """Run a syntax checker. Returns (ran, error).

    A missing tool, a spawn failure or a timeout yields (False, None) -- the
    check could not be performed, which is never treated as a pass.
    """
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
            errors="replace", timeout=20, stdin=subprocess.DEVNULL,
            creationflags=_SUBPROCESS_FLAGS,
        )
    except (OSError, subprocess.SubprocessError):
        return False, None
    if proc.returncode == 0:
        return True, None
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    first = detail[0] if detail else f"exit {proc.returncode}"
    return True, f"{label}: {first}"


def _syntax_check_shell(text: str) -> tuple[bool, str | None]:
    """Best-effort syntax check of merged shell content.

    Runs `bash -n` on the merged script and `node --check` on every embedded
    `node -e` block. A merge that produces a broken hook must never be
    reported clean: hooks fail open, so a JS syntax error silently disables
    enforcement. Returns (checked, error); a tool that is missing, fails to
    spawn or times out yields (False, None) -- never a silent pass.

    Callers must only pass conflict-free content: conflict markers are not
    valid shell and would fail every check.
    """
    bash = shutil.which("bash")
    if not bash:
        return False, None
    tmpdir = tempfile.mkdtemp(prefix="tplsync-syntax-")
    try:
        script = pathlib.Path(tmpdir) / "merged.sh"
        script.write_text(text, encoding="utf-8", newline="")
        ran, err = _run_syntax_tool([bash, "-n", script.name], "bash -n", tmpdir)
        if not ran:
            return False, None
        if err:
            return True, err
        node = shutil.which("node")
        if node:
            for idx, block in enumerate(_node_e_blocks(text)):
                js = pathlib.Path(tmpdir) / f"block{idx}.js"
                js.write_text(block, encoding="utf-8", newline="")
                ran, err = _run_syntax_tool(
                    [node, "--check", js.name], "node --check", tmpdir
                )
                if not ran:
                    return False, None
                if err:
                    return True, err
        return True, None
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def _conflict_hunk(label: str, body: list[str]) -> str:
    lines = "".join(ln if ln.endswith("\n") else ln + "\n" for ln in body)
    return f"<<<<<<< PROJECT ({label})\n{lines}=======\n>>>>>>> TEMPLATE\n"


def _three_way_merge(base: str, theirs: str, ours: str, file_path: str = "") -> dict:
    """
    Line-based three-way merge with a lossy-merge safety net.

    base: common ancestor (template at last sync, post-replacement)
    theirs: template current (post-replacement)
    ours: project current
    file_path: optional relative path, used to pick a syntax checker

    Returns dict with auto_merged content, has_conflicts, conflict_count,
    dropped_lines, syntax_checked and syntax_error.
    """
    merged_lines, conflict_count = _merge_walk(base, theirs, ours)
    auto_merged = "".join(merged_lines)

    # Safety net: the walk must never lose a line both sides kept. If it does,
    # refuse to present the result as clean -- the consumer would apply it.
    dropped = _dropped_lines(base, theirs, ours, auto_merged)
    if dropped:
        conflict_count += 1
        if auto_merged and not auto_merged.endswith("\n"):
            auto_merged += "\n"
        auto_merged += _conflict_hunk("dropped by merge", dropped)

    # Only syntax-check a clean merge: conflict markers are not valid shell,
    # so checking a conflicted result would report a bogus syntax error and
    # double-count the conflict.
    syntax_checked = False
    syntax_error = None
    if conflict_count == 0 and _normalize_path(file_path).endswith(".sh"):
        syntax_checked, syntax_error = _syntax_check_shell(auto_merged)
        if syntax_error:
            conflict_count += 1
            if auto_merged and not auto_merged.endswith("\n"):
                auto_merged += "\n"
            auto_merged += _conflict_hunk("syntax error in merge", [syntax_error])

    return {
        "auto_merged": auto_merged,
        "has_conflicts": conflict_count > 0,
        "conflict_count": conflict_count,
        "dropped_lines": dropped,
        "syntax_checked": syntax_checked,
        "syntax_error": syntax_error,
    }


# -------------------------
# MCP Tools
# -------------------------

@mcp.tool()
async def template_load_manifest(project_path: str) -> str:
    """
    Load and validate the template manifest from a project.
    Auto-migrates v1 manifests to v2 format by computing missing hashes.
    A v3 manifest is validated against requires_server and returns
    server_version; a v2 manifest reports migration_required when the
    template repo ships templates/ownership.json (call
    template_migrate_manifest before any other step).

    Args:
        project_path: Path to the project root directory

    Returns:
        JSON with manifest data, validation status, errors, and warnings
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        from . import v3 as _v3
        return json.dumps({"valid": False, "errors": errors, "server_version": __version__,
                           "server_source": _server_source(),
                           "capabilities": list(_v3.CAPABILITIES)}, ensure_ascii=False)

    if errors:
        from . import v3 as _v3
        return json.dumps({"valid": False, "errors": errors, "server_version": __version__,
                           "server_source": _server_source(),
                           "capabilities": list(_v3.CAPABILITIES)}, ensure_ascii=False)

    from . import v3

    warnings = []
    template_dir = _get_template_dir(manifest)
    if not template_dir.is_dir():
        errors.append(
            f"Template directory not found: {template_dir}. "
            f"Update templateRepo in .claude/template-manifest.json."
        )

    if v3.is_v3(manifest):
        ok, reason = v3.requires_server_satisfied(manifest.get("requires_server", ""), __version__)
        if not ok:
            errors.append(reason)
        rules = v3.load_ownership(manifest["templateRepo"]) if not errors else None
        if not errors and rules is None:
            errors.append(
                f"manifest v3 needs {v3.OWNERSHIP_FILE} in the template repo -- "
                "the toolkit checkout predates v3.1"
            )
        if rules is not None:
            warnings.extend(rules.warnings)
        return json.dumps({
            "valid": len(errors) == 0,
            "manifest_version": 3,
            "server_version": __version__,
            "server_source": _server_source(),
            "capabilities": list(v3.CAPABILITIES),
            "migration_required": False,
            "variant": manifest.get("variant", ""),
            "templateRepo": manifest.get("templateRepo", ""),
            "template_commit": v3.manifest_commit(manifest),
            "template_version": manifest.get("template_version"),
            "requires_server": manifest.get("requires_server", ""),
            "placeholders": manifest.get("placeholders", {}),
            "files": manifest.get("files", {}),
            "unknown_keys": v3.unknown_top_level_keys(manifest),
            "errors": errors,
            "warnings": warnings,
        }, ensure_ascii=False)

    version = manifest.get("version", 1)

    # Auto-migrate v1 -> v2
    if version < 2:
        warnings.append("Migrating v1 manifest to v2 -- will compute localHash and templateRawHash fields")
        placeholders = manifest.get("placeholders", {})
        files = manifest.get("files", {})

        for rel_path, entry in files.items():
            # Compute templateRawHash from current template file
            tpl_content = _read_file(_template_file_path(manifest, rel_path))
            if tpl_content is not None:
                entry["templateRawHash"] = _sha256(tpl_content)
            else:
                entry["templateRawHash"] = ""

            # localHash: if not locally modified, same as templateHash
            # if locally modified, hash the current project file
            if entry.get("locallyModified", False):
                proj_content = _read_file(pp / rel_path)
                entry["localHash"] = _sha256(proj_content) if proj_content else ""
            else:
                entry["localHash"] = entry.get("templateHash", "")

        manifest["version"] = MANIFEST_VERSION
        warnings.append("v1 -> v2 migration complete. Run sync to persist updated manifest.")

    # A v2 manifest migrates to v3 only when the toolkit checkout ships the
    # ownership table -- without it the server behaves exactly as 0.2.x.
    migration_required = v3.load_ownership(manifest["templateRepo"]) is not None

    return json.dumps({
        "valid": len(errors) == 0,
        "version": manifest.get("version", 1),
        "manifest_version": manifest.get("version", 1),
        "server_version": __version__,
        "server_source": _server_source(),
        "capabilities": list(v3.CAPABILITIES),
        "migration_required": migration_required,
        "variant": manifest.get("variant", ""),
        "templateRepo": manifest.get("templateRepo", ""),
        "lastSynced": manifest.get("lastSynced", ""),
        "placeholders": manifest.get("placeholders", {}),
        "files": manifest.get("files", {}),
        "errors": errors,
        "warnings": warnings,
    }, ensure_ascii=False)


@mcp.tool()
async def template_compute_status(
    project_path: str,
    template_repo: str = "",
    variant: str = "",
) -> str:
    """
    Compute sync status for all tracked template files.
    Classifies each file as: UP_TO_DATE, PROJECT_CUSTOM, AUTO_UPDATE, CONFLICT,
    TEMPLATE_DELETED. Also detects new files added to the template.

    Classification keys off whether the project file DEVIATES from the template
    revision it was synced against -- NOT off whether it changed since the last
    sync. A deviating file is never AUTO_UPDATE: template changed -> CONFLICT,
    template unchanged -> PROJECT_CUSTOM.

    Deviation is measured on the TEMPLATE PART: the file with its
    PROJECT-CUSTOM region stripped. The project deviates when its current
    template part matches NEITHER the current template's part NOR
    `templatePartHashAtSync` (the template part at the last sync, recorded by
    template_apply_file). A region-preserving apply rewrites only the region,
    so it stays AUTO_UPDATE when the template moves again. Entries predating
    `templatePartHashAtSync` fall back to whole-file hash inequality
    (conservative: CONFLICT) and carry a `hint`.

    Per-file fields:
        deviates_from_template: project content OUTSIDE its PROJECT-CUSTOM
            region differs from the template revision recorded at sync time
            (applying the template would destroy project content)
        region_only: the project differs from the template only inside its
            own PROJECT-CUSTOM region -- safe to auto-update
        hint: remediation note for legacy entries, else ""
        locally_modified: alias of deviates_from_template
        changed_since_sync: project file changed since the last sync
            (compared against `localHash`)
        resolution_at_sync: "keep-mine" when the entry was registered via
            template_apply_file(source="skip"), else "". Reporting only --
            classification is hash-based and does not read it.
        project_file_missing: the manifest tracks the file but the project
            does not have it (drop the entry via
            template_finalize_sync(deleted_files=[...]) if that is intended)
        region_reclassified: true when the only difference is inside the
            PROJECT-CUSTOM region, so the status already accounts for the
            deviation (the raw deviation fields stay honest)

    Args:
        project_path: Path to the project root directory
        template_repo: Override templateRepo from manifest (optional)
        variant: Override variant from manifest (optional)

    Returns:
        JSON with per-file status, new/deleted file lists, and summary counts,
        including `deviating` -- genuine deviations only (region-only
        differences are not counted).

        For a v3 manifest the statuses are IDENTICAL / TEMPLATE_UPDATED /
        LOCAL_EDITED / TEMPLATE_DELETED (template class) and PRESENT / MISSING
        (once class); the result also carries `orphans`,
        `unclassified_template_files`, `local_diff` per LOCAL_EDITED file,
        `key_audit` per audited once file, `encoding_drift` per file (BOM/EOL
        only differences, informational), and `gate_self_reference` /
        `gate_unverified` at top level. CONFLICT never appears for v3.
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        return json.dumps({"error": errors[0]}, ensure_ascii=False)

    if template_repo:
        manifest["templateRepo"] = template_repo
    if variant:
        manifest["variant"] = variant

    from . import v3
    if v3.is_v3(manifest):
        rules = v3.load_ownership(manifest["templateRepo"])
        if rules is None:
            return json.dumps({"error": f"manifest v3 needs {v3.OWNERSHIP_FILE} in the template repo"}, ensure_ascii=False)
        return json.dumps(v3.compute_status_v3(pp, manifest, rules), ensure_ascii=False)

    placeholders = manifest.get("placeholders", {})
    template_dir = _get_template_dir(manifest)
    template_commit = _git_head(_template_repo_resolved(manifest)) or "unknown"
    files_status = {}
    summary = {
        "up_to_date": 0, "project_custom": 0, "auto_update": 0,
        "conflict": 0, "template_deleted": 0, "deviating": 0,
    }

    for rel_path, entry in manifest.get("files", {}).items():
        tpl_content = _read_file(_template_file_path(manifest, rel_path))

        if tpl_content is None:
            files_status[rel_path] = {"status": "TEMPLATE_DELETED"}
            summary["template_deleted"] += 1
            continue

        # Current template hash (after placeholder replacement)
        tpl_replaced = _apply_placeholders(tpl_content, placeholders)
        tpl_hash_new = _sha256(tpl_replaced)

        # Previous template hash from manifest
        tpl_hash_old = entry.get("templateHash", "")

        # Check if template changed
        template_changed = tpl_hash_new != tpl_hash_old

        proj_content = _read_file(pp / rel_path)
        proj_hash_current = _sha256(proj_content) if proj_content is not None else ""

        # "Changed since the last sync" -- for v1 manifests without localHash,
        # fall back to the locallyModified flag.
        local_hash_at_sync = entry.get("localHash", "")
        if local_hash_at_sync:
            changed_since_sync = proj_hash_current != local_hash_at_sync
        else:
            changed_since_sync = bool(entry.get("locallyModified", False))

        # "Deviates from the template it was synced against" -- the property
        # that decides whether applying the template would DESTROY project
        # content. A file registered via template_apply_file(source="skip")
        # ("keep mine") deviates while being unchanged since the last sync;
        # classifying it off changed_since_sync reported AUTO_UPDATE and the
        # next sync overwrote it (consumer findings 2026-08-29).
        # Deviation is measured on the TEMPLATE PART -- the content outside the
        # project-owned PROJECT-CUSTOM region. A region-preserving apply
        # rewrites the region and nothing else, so it must not read as drift.
        resolution_at_sync = entry.get("resolution", "")
        tpl_part, tpl_region = _split_custom_region(tpl_replaced)
        proj_part, proj_region = (
            _split_custom_region(proj_content) if proj_content is not None else ("", None)
        )
        # _part_hashes applies the single-sided-marker fallback, exactly as the
        # recording side in template_apply_file does.
        proj_part_hash, tpl_part_hash_new = _part_hashes(
            proj_content if proj_content is not None else "", tpl_replaced
        )

        tpl_part_hash_at_sync = entry.get("templatePartHashAtSync", "")
        hint = ""
        if tpl_part_hash_at_sync:
            # The project part must match the template part of EITHER the
            # current template or the revision it was synced against -- the
            # latter is what keeps a region-preserving apply an AUTO_UPDATE.
            deviates = proj_part_hash not in (tpl_part_hash_new, tpl_part_hash_at_sync)
        else:
            # Legacy entry: no recorded template part -- fall back to whole-file
            # hash inequality, which is conservative (CONFLICT over AUTO_UPDATE).
            # An entry without templateHash has no baseline at all; comparing
            # against the CURRENT template is the only safe reading (an empty
            # baseline would otherwise read as "clean" and be overwritten).
            deviates = bool(entry.get("locallyModified", False)) or (
                proj_hash_current != (tpl_hash_old or tpl_hash_new)
            )
            if deviates:
                hint = (
                    'entry predates localPartHash/templatePartHashAtSync — re-register '
                    'with template_apply_file(source="skip") to record them and get '
                    'region-aware classification'
                )

        # The project differs from the template ONLY inside its own region.
        region_only = (
            not deviates
            and proj_content is not None
            and proj_hash_current != tpl_hash_new
            and tpl_region is not None
            and proj_region is not None
        )

        # Classify
        if deviates:
            status = "CONFLICT" if template_changed else "PROJECT_CUSTOM"
        else:
            status = "AUTO_UPDATE" if template_changed else "UP_TO_DATE"

        # PROJECT-CUSTOM region reclassification: when BOTH sides carry the
        # markers and the content OUTSIDE the region is identical, the only
        # difference is project-owned region content — not drift.
        #   PROJECT_CUSTOM -> UP_TO_DATE  (region-only project edit)
        #   CONFLICT       -> AUTO_UPDATE (applying the template is a no-op
        #                     outside the region; apply splices the project
        #                     region back and refreshes stale manifest hashes)
        # Reachable for LEGACY entries only: a modern entry with part hashes
        # never classifies a region-only difference as deviating.
        region_reclassified = False
        if proj_content is not None and status in ("PROJECT_CUSTOM", "CONFLICT"):
            if tpl_region is not None and proj_region is not None and tpl_part == proj_part:
                status = "UP_TO_DATE" if status == "PROJECT_CUSTOM" else "AUTO_UPDATE"
                region_reclassified = True

        summary[status.lower()] += 1
        if deviates and not region_reclassified:
            summary["deviating"] += 1
        files_status[rel_path] = {
            "status": status,
            "template_changed": template_changed,
            "locally_modified": deviates,
            "deviates_from_template": deviates,
            "changed_since_sync": changed_since_sync,
            "resolution_at_sync": resolution_at_sync,
            "region_only": region_only,
            "project_file_missing": proj_content is None,
            "hint": hint,
            "template_hash_new": tpl_hash_new,
            "template_hash_old": tpl_hash_old,
            "local_hash_current": proj_hash_current,
            "local_hash_at_sync": local_hash_at_sync,
            "region_reclassified": region_reclassified,
        }

    # Detect new template files not in manifest
    all_template_files = _scan_template_files(
        template_dir, _resolve_path(manifest["templateRepo"])
    )
    tracked = set(manifest.get("files", {}).keys())
    new_files = [f for f in all_template_files if f not in tracked and f not in ALWAYS_PROJECT_SPECIFIC]

    # Detect deleted template files already counted above
    deleted_files = [p for p, s in files_status.items() if s["status"] == "TEMPLATE_DELETED"]

    return json.dumps({
        "template_commit": template_commit,
        "last_synced_commit": manifest.get("lastSynced", ""),
        "files": files_status,
        "new_template_files": new_files,
        "deleted_template_files": deleted_files,
        "summary": summary,
    }, ensure_ascii=False)


@mcp.tool()
async def template_get_diff(
    project_path: str,
    file_path: str,
    diff_type: str = "full",
) -> str:
    """
    Generate a diff for a template-tracked file.

    Supports four diff types:
    - template_changes: what changed in the template since last sync
    - local_changes: what the user changed since last sync
    - full: template-current vs project-current ("unified" is an alias)
    - three_way: three-way merge with conflict markers

    For three_way, reconstructs the common ancestor via git show at lastSynced commit.
    Falls back to two-way if git history is unavailable.

    Args:
        project_path: Path to the project root directory
        file_path: Relative path of the file (e.g. "CLAUDE.md")
        diff_type: One of: template_changes, local_changes, full, unified, three_way

    Returns:
        JSON with content versions, unified diff, and merge result (for three_way)
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        return json.dumps({"error": errors[0]}, ensure_ascii=False)

    placeholders = manifest.get("placeholders", {})
    last_synced = manifest.get("lastSynced", "")

    # Read current template content (post-replacement)
    tpl_raw = _read_file(_template_file_path(manifest, file_path))
    if tpl_raw is None:
        return json.dumps({"error": f"Template file not found: {file_path}"}, ensure_ascii=False)
    tpl_current = _apply_placeholders(tpl_raw, placeholders)

    # Read current project content
    proj_current = _read_file(pp / file_path)
    if proj_current is None:
        return json.dumps({"error": f"Project file not found: {file_path}"}, ensure_ascii=False)

    # Reconstruct base (common ancestor) via git show
    base_content = None
    if last_synced:
        git_path = _template_git_path(manifest, file_path)
        base_raw = _git_show_file(_template_repo_resolved(manifest), last_synced, git_path)
        if base_raw is not None:
            base_content = _apply_placeholders(base_raw, placeholders)

    # Fallback: if no base available, use current template as base (two-way)
    fallback_used = False
    if base_content is None:
        base_content = tpl_current
        fallback_used = True

    result = {
        "file_path": file_path,
        "diff_type": diff_type,
        "fallback_to_two_way": fallback_used,
    }

    if diff_type == "template_changes":
        diff = list(unified_diff(
            base_content.splitlines(keepends=True),
            tpl_current.splitlines(keepends=True),
            fromfile=f"{file_path} (base @ {last_synced})",
            tofile=f"{file_path} (template current)",
        ))
        result["unified_diff"] = "".join(diff)
        result["has_changes"] = len(diff) > 0

    elif diff_type == "local_changes":
        diff = list(unified_diff(
            base_content.splitlines(keepends=True),
            proj_current.splitlines(keepends=True),
            fromfile=f"{file_path} (base @ {last_synced})",
            tofile=f"{file_path} (project current)",
        ))
        result["unified_diff"] = "".join(diff)
        result["has_changes"] = len(diff) > 0

    elif diff_type in ("full", "unified"):
        diff = list(unified_diff(
            tpl_current.splitlines(keepends=True),
            proj_current.splitlines(keepends=True),
            fromfile=f"{file_path} (template)",
            tofile=f"{file_path} (project)",
        ))
        result["unified_diff"] = "".join(diff)
        result["has_changes"] = len(diff) > 0

    elif diff_type == "three_way":
        # PROJECT-CUSTOM region: when both template and project carry the
        # markers, exclude the region from the merge (it is project-owned and
        # must never conflict) and reattach the project's region to the
        # merged output. Pure diff displays above stay full-content.
        merge_base, merge_tpl, merge_proj = base_content, tpl_current, proj_current
        reattach_region = None
        _tpl_part, tpl_region = _split_custom_region(tpl_current)
        _proj_part, proj_region = _split_custom_region(proj_current)
        if tpl_region is not None and proj_region is not None:
            base_part, _base_region = _split_custom_region(base_content)
            merge_base, merge_tpl, merge_proj = base_part, _tpl_part, _proj_part
            reattach_region = proj_region

        merge = _three_way_merge(merge_base, merge_tpl, merge_proj, file_path=file_path)
        if reattach_region is not None and isinstance(merge.get("auto_merged"), str):
            merged_text = merge["auto_merged"]
            if merged_text and not merged_text.endswith("\n"):
                merged_text += "\n"
            merge["auto_merged"] = merged_text + reattach_region + "\n"
            merge["region_reattached"] = True
        result["base_content"] = base_content
        result["template_content"] = tpl_current
        result["project_content"] = proj_current
        result["merge_result"] = merge

        # Also include a full diff for context
        diff = list(unified_diff(
            tpl_current.splitlines(keepends=True),
            proj_current.splitlines(keepends=True),
            fromfile=f"{file_path} (template)",
            tofile=f"{file_path} (project)",
        ))
        result["unified_diff"] = "".join(diff)
    else:
        return json.dumps({"error": f"Unknown diff_type: {diff_type}"}, ensure_ascii=False)

    return json.dumps(result, ensure_ascii=False)


@mcp.tool()
async def template_apply_file(
    project_path: str,
    file_path: str,
    source: str = "template",
    content: str = "",
    backup_dir: str = "",
) -> str:
    """
    Apply a template file to the project and return the updated manifest entry.
    Does NOT write the manifest itself -- call template_finalize_sync for that.

    Args:
        project_path: Path to the project root directory
        file_path: Relative path of the file (e.g. "CLAUDE.md")
        source: One of:
            - "template": copy from template with placeholder replacement
            - "provided": use the content parameter as-is
            - "skip": don't change the project file, just update manifest hashes
              ("keep mine" -- the entry records resolution="keep-mine" for
              reporting; the CONFLICT the next status call reports comes from
              the recorded part hashes, not from that field)
        content: File content to write (only used when source="provided")
        backup_dir: Manifest v3 only. Directory that receives `<file>.pre-sync`
            and `<file>.diff` before a LOCAL_EDITED template-class file is
            overwritten. Required in that state -- the call is refused without
            it. Ignored for v2 manifests.

    Returns:
        JSON with the new manifest entry for this file (hashes, modification
        status, and resolution="keep-mine" for source="skip"; "template" and
        "provided" omit the key, which clears any previous resolution).
        Every entry also carries `localPartHash` (the project file hashed with
        its PROJECT-CUSTOM region stripped) and `templatePartHashAtSync` (the
        same for the template) -- template_compute_status needs the latter to
        tell a preserved region apart from real drift. Both fall back to
        full-file hashes when only one side carries the markers.
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        return json.dumps({"error": errors[0]}, ensure_ascii=False)

    placeholders = manifest.get("placeholders", {})

    from . import v3
    if v3.is_v3(manifest):
        rules = v3.load_ownership(manifest["templateRepo"])
        if rules is None:
            return json.dumps({"error": f"manifest v3 needs {v3.OWNERSHIP_FILE} in the template repo"}, ensure_ascii=False)
        return json.dumps(
            v3.apply_file_v3(pp, manifest, rules, file_path, source, content, backup_dir),
            ensure_ascii=False,
        )

    # Read current template content
    tpl_raw = _read_file(_template_file_path(manifest, file_path))
    tpl_replaced = _apply_placeholders(tpl_raw, placeholders) if tpl_raw else ""
    tpl_raw_hash = _sha256(tpl_raw) if tpl_raw else ""
    tpl_hash = _sha256(tpl_replaced) if tpl_replaced else ""

    target_path = pp / file_path

    if source == "template":
        if not tpl_raw:
            return json.dumps({"error": f"Template file not found: {file_path}"}, ensure_ascii=False)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        # PROJECT-CUSTOM region: when both the template and the existing
        # project file carry the markers, preserve the project's region by
        # splicing it in place of the template's sentinel block.
        write_content = tpl_replaced
        region_preserved = False
        proj_existing = _read_file(target_path)
        if proj_existing is not None:
            _tpl_part, tpl_region = _split_custom_region(tpl_replaced)
            _proj_part, proj_region = _split_custom_region(proj_existing)
            if tpl_region is not None and proj_region is not None and proj_region != tpl_region:
                write_content = tpl_replaced.replace(tpl_region, proj_region, 1)
                region_preserved = True
        _write_file_atomic(target_path, write_content)
        local_hash = _sha256(write_content)
        action = "written_from_template"
        locally_modified = local_hash != tpl_hash

    elif source == "provided":
        if not content:
            return json.dumps({"error": "source='provided' requires content parameter"}, ensure_ascii=False)
        target_path.parent.mkdir(parents=True, exist_ok=True)
        _write_file_atomic(target_path, content)
        local_hash = _sha256(content)
        action = "written_from_provided"
        locally_modified = local_hash != tpl_hash

    elif source == "skip":
        # Don't touch the project file, just acknowledge the template change
        proj_content = _read_file(target_path)
        local_hash = _sha256(proj_content) if proj_content else ""
        action = "skipped"
        locally_modified = local_hash != tpl_hash

    else:
        return json.dumps({"error": f"Unknown source: {source}"}, ensure_ascii=False)

    # Region-aware bookkeeping: hash the project file WITHOUT its
    # PROJECT-CUSTOM region, and record whether that part matched the
    # template at sync time. template_compute_status measures deviation on
    # this part, so a region-preserving apply stays an AUTO_UPDATE next time.
    final_content = (
        write_content if source == "template"
        else content if source == "provided"
        else (proj_content or "")
    )
    local_part_hash, tpl_part_hash = _part_hashes(final_content, tpl_replaced)

    manifest_entry = {
        "templateHash": tpl_hash,
        "templateRawHash": tpl_raw_hash,
        "localHash": local_hash,
        "locallyModified": locally_modified,
        "localPartHash": local_part_hash,
        "templatePartHashAtSync": tpl_part_hash,
    }
    if source == "skip":
        # "Keep mine": the project deliberately deviates from this template
        # revision. Recorded so a later status call can say WHY the file
        # deviates. "template"/"provided" leave the key out, which clears it
        # (template_finalize_sync replaces the entry wholesale).
        manifest_entry["resolution"] = "keep-mine"

    return json.dumps({
        "file_path": file_path,
        "action": action,
        "manifest_entry": manifest_entry,
        "region_preserved": region_preserved if source == "template" else False,
        "bytes_written": len(write_content.encode("utf-8")) if source == "template"
            else len(content.encode("utf-8")) if source == "provided"
            else 0,
    }, ensure_ascii=False)


@mcp.tool()
async def template_finalize_sync(
    project_path: str,
    applied_files: str = "[]",
    new_files: str = "[]",
    deleted_files: str = "[]",
    applied_files_path: str = "",
) -> str:
    """
    Finalize a sync operation by writing the updated manifest.
    This is the ONLY tool that writes .claude/template-manifest.json.

    Manifest entries are dropped when the template no longer ships the file
    AND the project no longer has it -- otherwise a resolved TEMPLATE_DELETED
    is re-reported by every later status call, forever.

    Args:
        project_path: Path to the project root directory
        applied_files: JSON array of template_apply_file results
            (each must have file_path and manifest_entry)
        new_files: JSON array of new file paths added from template (optional).
            Entries not already applied get real hashes computed from the
            template and the project file on disk -- never empty placeholders,
            which would read as "no baseline" and invite an overwrite.
        deleted_files: JSON array of relative paths the project deliberately
            removed; their entries are dropped even if the template still
            ships the file (optional)
        applied_files_path: Path to a local JSON file holding the same array
            as applied_files, written by the caller from the tool results so
            nothing is retyped. When given, applied_files is ignored.

    Returns:
        JSON confirmation with counts, the dropped entries, and what was
        consumed: `consumed_entries` and `consumed` = [{path, hash}] with the
        hash exactly as stored (sha256:-prefixed under v3, templateHash under
        v2) for the caller's post-finalize self-check.

    Manifest v3: entries carry `hash` (sha256:-prefixed) and `ownership`;
    `template_commit` is HEAD of the template repo and `template_version` the
    nearest reachable tag whose tracked tree is identical (null when none).
    Unknown top-level keys are preserved and listed in `unknown_keys`.
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        return json.dumps({"error": errors[0]}, ensure_ascii=False)

    if applied_files_path:
        raw = _read_file(_resolve_path(applied_files_path))
        if raw is None:
            return json.dumps({"error": f"applied_files_path not readable: {applied_files_path}"}, ensure_ascii=False)
        try:
            applied = json.loads(raw)
        except json.JSONDecodeError as e:
            return json.dumps({"error": f"applied_files_path is not valid JSON: {e}"}, ensure_ascii=False)
        if not isinstance(applied, list):
            return json.dumps({"error": "applied_files_path must hold a JSON array of apply results"}, ensure_ascii=False)
    else:
        try:
            applied = json.loads(applied_files)
        except json.JSONDecodeError as e:
            return json.dumps({"error": f"Invalid applied_files JSON: {e}"}, ensure_ascii=False)

    try:
        new = json.loads(new_files)
    except json.JSONDecodeError:
        new = []

    try:
        deleted = json.loads(deleted_files)
    except json.JSONDecodeError:
        deleted = []

    from . import v3
    if v3.is_v3(manifest):
        rules = v3.load_ownership(manifest["templateRepo"])
        if rules is None:
            return json.dumps({"error": f"manifest v3 needs {v3.OWNERSHIP_FILE} in the template repo"}, ensure_ascii=False)
        return json.dumps(v3.finalize_v3(pp, manifest, rules, applied, new, deleted), ensure_ascii=False)

    # Validate before touching the manifest (downstream finding 2026-07-19 #6:
    # hand-typed hashes with stray characters silently corrupted a manifest).
    import re as _re
    hex64 = _re.compile(r"^[0-9a-f]{64}$")
    invalid: list[str] = []
    for item in applied:
        fp = item.get("file_path", "")
        entry = item.get("manifest_entry", {})
        norm = _normalize_path(fp)
        if not fp or not norm.strip("/") or ".." in norm.split("/"):
            invalid.append(f"invalid file_path: {fp!r}")
            continue
        for key in (
            "templateHash", "templateRawHash", "localHash",
            "localPartHash", "templatePartHashAtSync",
        ):
            value = entry.get(key, "")
            if value and not hex64.match(value):
                invalid.append(f"{fp}: {key} is not a 64-char lowercase hex SHA-256")
    if invalid:
        return json.dumps({
            "error": "applied_files validation failed — manifest NOT written",
            "invalid_entries": invalid,
        }, ensure_ascii=False)

    files = manifest.get("files", {})

    # Update entries from applied files
    updated_count = 0
    for item in applied:
        fp = item.get("file_path", "")
        entry = item.get("manifest_entry", {})
        if fp and entry:
            # Preserve reason field if it existed and file is still locally modified
            old_entry = files.get(fp, {})
            new_entry = dict(entry)
            if new_entry.get("locallyModified") and old_entry.get("reason"):
                new_entry["reason"] = old_entry["reason"]
            elif not new_entry.get("locallyModified") and "reason" in new_entry:
                del new_entry["reason"]
            files[fp] = new_entry
            updated_count += 1

    # Add new files. Real hashes only -- an entry with an empty templateHash
    # has no baseline, and template_compute_status would have offered to
    # overwrite whatever the project has there.
    added_count = 0
    placeholders = manifest.get("placeholders", {})
    for fp in new:
        if fp not in files:
            tpl_raw = _read_file(_template_file_path(manifest, fp))
            tpl_replaced = _apply_placeholders(tpl_raw, placeholders) if tpl_raw else ""
            proj_content = _read_file(pp / _normalize_path(fp))
            local_part_hash, tpl_part_hash = _part_hashes(proj_content or "", tpl_replaced)
            files[fp] = {
                "templateHash": _sha256(tpl_replaced) if tpl_replaced else "",
                "templateRawHash": _sha256(tpl_raw) if tpl_raw else "",
                "localHash": _sha256(proj_content) if proj_content is not None else "",
                "locallyModified": proj_content is not None and proj_content != tpl_replaced,
                "localPartHash": local_part_hash,
                "templatePartHashAtSync": tpl_part_hash,
            }
            added_count += 1

    # Drop dead entries: the template stopped shipping the file and the
    # project removed it too, or the project deliberately deleted it.
    explicit_deletes = {_normalize_path(p) for p in deleted if isinstance(p, str) and p}
    dropped_entries = []
    for fp in list(files.keys()):
        norm = _normalize_path(fp)
        if norm in explicit_deletes:
            del files[fp]
            dropped_entries.append(fp)
            continue
        if _template_file_path(manifest, fp).is_file():
            continue
        if (pp / norm).exists():
            continue
        del files[fp]
        dropped_entries.append(fp)

    # Update lastSynced
    new_head = _git_head(_template_repo_resolved(manifest)) or manifest.get("lastSynced", "")
    manifest["lastSynced"] = new_head
    manifest["version"] = MANIFEST_VERSION
    manifest["files"] = dict(sorted(files.items()))

    # Write manifest atomically
    manifest_path = pp / ".claude" / "template-manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)
    manifest_json = json.dumps(manifest, indent=2, ensure_ascii=False)
    _write_file_atomic(manifest_path, manifest_json)

    consumed = sorted(
        ({"path": _normalize_path(i["file_path"]),
          "hash": manifest["files"].get(i["file_path"], {}).get("templateHash")}
         for i in applied if i.get("file_path") and i.get("manifest_entry")),
        key=lambda d: d["path"],
    )

    return json.dumps({
        "manifest_path": ".claude/template-manifest.json",
        "last_synced": new_head,
        "files_updated": updated_count,
        "files_added": added_count,
        "files_dropped": len(dropped_entries),
        "dropped_entries": sorted(dropped_entries),
        "consumed_entries": len(consumed),
        "consumed": consumed,
        "manifest_written": True,
    }, ensure_ascii=False)


@mcp.tool()
async def template_migrate_manifest(
    project_path: str,
    backup_dir: str = "",
    dry_run: bool = False,
    skill_version: str = "",
) -> str:
    """
    Migrate a v2 template manifest to v3 (three-class ownership). Call it at
    step 1 of a sync when template_load_manifest reports migration_required.

    Steps (toolkit spec §7): extract the PROJECT-CUSTOM region from CLAUDE.md;
    diff the remainder against the template CLAUDE.md at the held revision
    (template_commit, else the template_version tag, never the current
    template), placeholder-rendered; write .claude/rules/project.md with a
    header and the out-of-region hunks fenced as ```diff; rewrite the
    manifest as v3 (entries classified by templates/ownership.json,
    project-class entries dropped, unknown top-level keys preserved).

    The PROJECT-CUSTOM region is NOT copied into project.md. Under the toolkit
    v3.1 reversal the region STAYS in CLAUDE.md, so copying it would not
    relocate it, it would duplicate it -- and the duplicate is the dangerous
    half, because an unscoped project.md is delivered to no agent. The region
    is reported instead: region_left_in_place, region_bytes, region_was_seed.
    (Until 0.3.5 this text claimed the opposite while the code did this --
    measured by two consumers who documented the artifact over the docstring,
    correctly. tests/test_template_sync_docstring_contract.py now pins the two
    together so the prose cannot drift back alone.)
    Idempotent: an existing project.md is never overwritten and a v3 manifest
    is skipped. CLAUDE.md itself is not touched here -- the apply step
    overwrites it in the same sync. A v1 manifest is REFUSED (a missing
    `version` key reads as 1, as in template_load_manifest): a v1 entry has no
    localHash, so migrating it would baseline against the current template and
    report a deviating file as identical. Run template_load_manifest and
    template_finalize_sync to persist v2 first.

    Args:
        project_path: Path to the project root directory
        backup_dir: Receives CLAUDE.md.pre-migration and
            template-manifest.json.pre-migration. Required unless dry_run.
        dry_run: Compute and return everything (project_md content, manifest,
            hunk_count, redundant_project_file, warnings) without writing.
        skill_version: The caller's sync-template skill version, taken from the
            marker in the BODY being executed -- never from
            ~/.claude/skills/sync-template/SKILL.md, which reports the disk while
            the hazard is a session running a body it read at startup. Tag-shaped
            ("v3.1.3"); a bare "3.1.3" is a named mismatch, not a synonym. When
            templates/ownership.json declares requires_skill, a WRITE with no
            value is REFUSED -- a body too old to carry this instruction sends
            nothing, so absence is the signal rather than a low number. dry_run
            is never refused. A caller that is not that skill passes exactly
            "not-a-skill" and is reported as skill_version_bypassed; every near
            miss refuses.

    Returns:
        JSON with migrated, dry_run, migration_base, hunk_count, project_md,
        project_md_bytes, project_md_existing, region_was_seed (the region
        was the toolkit's untouched seed and is omitted), dropped_entries,
        dropped_file_keys ([{path, keys}] -- consumer annotations on entries
        being dropped, which no other field would report; the values survive in
        the pre-migration manifest copied to backup_dir),
        redundant_project_file (byte-identical copies of files that are now
        project-owned; suggestion only, never deleted), dropped_resolutions
        ([{path, resolution, ownership}] -- entries whose v2 "keep-mine" record
        is discarded, since v3 has no keep-mine class. `ownership` is the class
        the file LANDS in and is what decides whether the drop matters:
        "template" means the next sync overwrites the deviation, "once" means
        apply keeps the consumer's file, "project"/null means the server never
        writes it), gate_self_reference
        (a **Gate**:/**Test**: value pointing at a template-class path --
        write mode refuses), gate_unverified (a **Gate**: is declared and this
        tool did not run it), unknown_keys, warnings, backup, written.
    """
    from . import v3
    pp = pathlib.Path(project_path).resolve()
    return json.dumps(v3.migrate_manifest(pp, backup_dir, dry_run, skill_version),
                      ensure_ascii=False)


@mcp.tool()
async def template_reverse_placeholders(
    project_path: str,
    file_path: str,
    content: str = "",
) -> str:
    """
    Reverse placeholder replacement in a project file, producing template-ready content.
    Sorts placeholders by value length descending to avoid partial matches.

    Args:
        project_path: Path to the project root directory
        file_path: Relative path of the file to reverse
        content: Content to reverse (if empty, reads the project file)

    Returns:
        JSON with reversed content, replacements made, and replacement order
    """
    pp = pathlib.Path(project_path).resolve()
    manifest, errors = _load_manifest(pp)
    if manifest is None:
        return json.dumps({"error": errors[0]}, ensure_ascii=False)

    placeholders = manifest.get("placeholders", {})

    if not content:
        content = _read_file(pp / file_path)
        if content is None:
            return json.dumps({"error": f"File not found: {file_path}"}, ensure_ascii=False)

    reversed_content, replacements = _reverse_placeholders(content, placeholders)

    # Show the replacement order used
    sorted_order = [k for k, v in sorted(placeholders.items(), key=lambda x: (-len(x[1]), x[0])) if v]

    return json.dumps({
        "file_path": file_path,
        "original_content": content,
        "reversed_content": reversed_content,
        "replacements_made": replacements,
        "replacement_order": sorted_order,
    }, ensure_ascii=False)


@mcp.tool()
async def template_check_cross_variant(
    template_repo: str,
    variant: str,
    file_path: str,
) -> str:
    """
    Check if a file is shared across template variants by comparing content.

    Args:
        template_repo: Path to the claude-code-toolkit repo
        variant: Current variant name
        file_path: Relative path within the variant (e.g. "AGENT_TEAM.md")

    Returns:
        JSON with which variants are identical, which differ, and whether propagation is safe
    """
    repo = pathlib.Path(template_repo).resolve()
    templates_dir = repo / "templates"

    current_content = _read_file(templates_dir / variant / file_path)
    if current_content is None:
        return json.dumps({"error": f"File not found in current variant: {variant}/{file_path}"}, ensure_ascii=False)

    current_hash = _sha256(current_content)
    identical = []
    different = []
    missing = []

    for v in KNOWN_VARIANTS:
        other_content = _read_file(templates_dir / v / file_path)
        if other_content is None:
            missing.append(v)
        elif _sha256(other_content) == current_hash:
            identical.append(v)
        else:
            different.append(v)

    return json.dumps({
        "file_path": file_path,
        "source_variant": variant,
        "is_shared": len(different) == 0 and len(missing) == 0,
        "variants_identical": identical,
        "variants_different": different,
        "variants_missing": missing,
        "can_propagate": len(different) == 0,
    }, ensure_ascii=False)


@mcp.tool()
async def template_propagate_to_variants(
    template_repo: str,
    file_path: str,
    content: str,
    target_variants: str,
) -> str:
    """
    Write template-ready content to multiple variant directories.

    Args:
        template_repo: Path to the claude-code-toolkit repo
        file_path: Relative path within each variant (e.g. "AGENT_TEAM.md")
        content: Template-ready content with {{PLACEHOLDERS}}
        target_variants: JSON array of variant names to update

    Returns:
        JSON with which variants were written, skipped, or errored
    """
    repo = pathlib.Path(template_repo).resolve()
    templates_dir = repo / "templates"

    try:
        variants = json.loads(target_variants)
    except json.JSONDecodeError as e:
        return json.dumps({"error": f"Invalid target_variants JSON: {e}"}, ensure_ascii=False)

    written = []
    errors_list = []

    for v in variants:
        target = templates_dir / v / file_path
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            _write_file_atomic(target, content)
            written.append(v)
        except OSError as e:
            errors_list.append({"variant": v, "error": str(e)})

    return json.dumps({
        "file_path": file_path,
        "written_to": written,
        "errors": errors_list,
    }, ensure_ascii=False)


def main():
    mcp.run(transport="stdio")


if __name__ == "__main__":
    main()
