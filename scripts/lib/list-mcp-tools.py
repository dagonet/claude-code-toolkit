#!/usr/bin/env python3
"""list-mcp-tools.py -- two independent censuses of one mcp-dev-servers
FastMCP module's exported tool names.

Used by scripts/verify-template-consistency.sh (check 50, v4.0.1 item 23)
to catch a tool renamed or removed in mcp-dev-servers before it turns an
agent's `tools:` allowlist entry (`mcp__<alias>__<tool>`) into a dead token.

Runs under SYSTEM `python` -- it must not require `server/.venv`.

  static census -- regex scan of <source-dir>/src/mcp_dev_servers/*.py for
                   bare, column-0 `@mcp.tool()` decorated function names.
                   Needs only a source checkout; no venv, no registration.
  import census -- `asyncio.run(mcp.list_tools())` run in the SERVER's own
                   venv interpreter (mcp-dev-servers' `.venv`). Only
                   possible when the alias is registered in ~/.claude.json
                   and that venv exists and imports cleanly.

Disagreement between the two censuses -- a tool the static scan finds that
the running server does not export, or vice versa -- is the defect this
check exists to catch, so both are reported and the caller compares them.

Usage:
    python scripts/lib/list-mcp-tools.py \\
        --source-dir <mcp-dev-servers checkout> \\
        --registration <path to ~/.claude.json> \\
        --alias <alias>

    python scripts/lib/list-mcp-tools.py --self-test

Output (one line of JSON on stdout):
    {"alias": ..., "module": ..., "static": [...], "imported": [...]|null,
     "skip_reason": ...|null}
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Tuple

# A tool is registered with a bare `@mcp.tool()` at column 0, no arguments,
# immediately followed by a (possibly async) def line -- verified against
# every module in mcp-dev-servers today (item 23 design note).
TOOL_RE = re.compile(
    r"^@mcp\.tool\(\)[ \t]*\r?\n[ \t]*(?:async[ \t]+)?def[ \t]+(\w+)",
    re.MULTILINE,
)

# The FastMCP instance name is how a module declares which registration
# alias it answers to -- e.g. `mcp = FastMCP("github-tools")`.
FASTMCP_RE = re.compile(r"""FastMCP\(\s*["']([^"']+)["']""")

# The static scanner only reads the ONE module file named by FastMCP(<alias>)
# -- it does not follow imports. A module that aggregates tools from a
# sibling file via a relative import (`from .x import ...`) would silently
# under-report, so that shape is detected and refused rather than guessed at
# (fix round 1, F2: no module in mcp-dev-servers does this today -- zero
# matches across all six -- so there is nothing to verify a sibling-follow
# against; asserting flatness and refusing is safer than exercising untested
# code on the day it finally matters).
MULTI_MODULE_IMPORT_RE = re.compile(r"^from[ \t]+\.\w+[ \t]+import\b", re.MULTILINE)

SELF_TEST_SAMPLE = '''\
from fastmcp import FastMCP

mcp = FastMCP("sample-tools")


@mcp.tool()
def real_tool(x: int) -> int:
    return x


def not_a_tool(x: int) -> int:
    return x
'''


def static_scan(text: str) -> List[str]:
    """Every @mcp.tool()-decorated function name found in `text`."""
    return [m.group(1) for m in TOOL_RE.finditer(text)]


def assert_no_dunder(names: List[str], context: str) -> None:
    """Fail loudly (rc 1) if any exported tool name contains a literal
    double underscore. Every downstream consumer of a census -- most
    concretely, check 50's `awk -F'__'` split of a `mcp__<alias>__<tool>`
    token in verify-template-consistency.sh -- assumes the alias and the
    tool name never contain "__" themselves, only the separators between
    "mcp", the alias and the tool. A tool name that broke that assumption
    would silently corrupt the split rather than raise anywhere, so it is
    checked here, at the one place that sees every tool name mcp-dev-servers
    exports, and refused outright rather than passed on to be misread.
    """
    bad = sorted(n for n in names if "__" in n)
    if bad:
        print(
            f"FATAL: {context} exports tool name(s) containing '__' "
            f"(double underscore), which breaks the mcp__<alias>__<tool> "
            f"token split every downstream reader assumes: {bad!r}",
            file=sys.stderr,
        )
        sys.exit(1)


def find_module_for_alias(source_dir: Path, alias: str) -> Optional[str]:
    """The module (file stem) under <source_dir>/src/mcp_dev_servers whose
    FastMCP instance is named `alias`, or None if no module declares it.
    """
    pkg_dir = source_dir / "src" / "mcp_dev_servers"
    if not pkg_dir.is_dir():
        return None
    for path in sorted(pkg_dir.glob("*.py")):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError:
            continue
        m = FASTMCP_RE.search(text)
        if m and m.group(1) == alias:
            return path.stem
    return None


def static_census(source_dir: Path, module: str) -> Tuple[List[str], Optional[str]]:
    """Static census for `module`. Returns (names, None) normally, or
    ([], skip_reason) when the module cannot be safely censused -- today
    that is only a module shaped like a multi-file aggregator (see
    MULTI_MODULE_IMPORT_RE): the static scanner reads exactly one file, so
    scanning it alone would silently under-report rather than merely skip.
    """
    pkg_dir = source_dir / "src" / "mcp_dev_servers"
    main_text = (pkg_dir / f"{module}.py").read_text(encoding="utf-8")
    if MULTI_MODULE_IMPORT_RE.search(main_text):
        return [], "multi-module server not supported"
    names = sorted(set(static_scan(main_text)))
    assert_no_dunder(names, f"{module} static census")
    return names, None


def venv_python(source_dir: Path) -> Optional[Path]:
    for candidate in (
        source_dir / ".venv" / "Scripts" / "python.exe",
        source_dir / ".venv" / "bin" / "python",
    ):
        if candidate.is_file():
            return candidate
    return None


def is_registered(registration_path: Path, alias: str) -> bool:
    try:
        data = json.loads(registration_path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return alias in data.get("mcpServers", {})


def import_census(
    source_dir: Path, module: str
) -> Tuple[Optional[List[str]], Optional[str]]:
    """Returns (sorted tool names, None) on success, or (None, skip_reason)."""
    py = venv_python(source_dir)
    if py is None:
        return None, "no venv"
    code = (
        f"import mcp_dev_servers.{module} as m, asyncio, json; "
        "print(json.dumps(sorted(t.name for t in asyncio.run(m.mcp.list_tools()))))"
    )
    try:
        proc = subprocess.run(
            [str(py), "-c", code],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"import failed: {exc}"
    if proc.returncode != 0:
        first_line = next(
            (
                line.strip()
                for line in (proc.stderr or proc.stdout or "").splitlines()
                if line.strip()
            ),
            f"exit {proc.returncode}",
        )
        return None, f"import failed: {first_line}"
    try:
        names = json.loads(proc.stdout)
    except ValueError:
        return None, "import failed: unparseable output"
    assert_no_dunder(names, f"{module} import census")
    return names, None


def run_self_test() -> int:
    names = static_scan(SELF_TEST_SAMPLE)
    if names == ["real_tool"]:
        print("self-test OK: static scanner found exactly one tool name (real_tool)")
        return 0
    print(f"self-test FAILED: expected ['real_tool'], got {names!r}", file=sys.stderr)
    return 1


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", help="mcp-dev-servers checkout root")
    parser.add_argument("--registration", help="path to ~/.claude.json")
    parser.add_argument("--alias", help="registration alias, e.g. github-tools")
    parser.add_argument(
        "--self-test",
        action="store_true",
        help="run the embedded static-scanner self-test and exit",
    )
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_test()

    if not args.source_dir or not args.registration or not args.alias:
        parser.error(
            "--source-dir, --registration and --alias are all required "
            "(or pass --self-test alone)"
        )

    source_dir = Path(args.source_dir)
    registration_path = Path(args.registration).expanduser()
    alias = args.alias

    result = {
        "alias": alias,
        "module": None,
        "static": [],
        "imported": None,
        "skip_reason": None,
    }

    module = find_module_for_alias(source_dir, alias)
    if module is None:
        result["skip_reason"] = f'no FastMCP("{alias}") found under {source_dir}'
        print(json.dumps(result))
        return 0
    result["module"] = module
    static_names, static_skip = static_census(source_dir, module)
    result["static"] = static_names
    if static_skip:
        result["skip_reason"] = static_skip
        print(json.dumps(result))
        return 0

    if not is_registered(registration_path, alias):
        result["skip_reason"] = "unregistered"
        print(json.dumps(result))
        return 0

    imported, skip_reason = import_census(source_dir, module)
    result["imported"] = imported
    result["skip_reason"] = skip_reason
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
