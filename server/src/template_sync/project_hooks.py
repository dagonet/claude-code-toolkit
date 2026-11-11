"""Project-owned hook handlers inside a template-owned .claude/settings.json (#30).

A consumer's settings.json that is "the template plus the project's own hook
handlers" is not drift: the handlers belong to the project. This module holds
the command grammar, the strip operation that takes those handlers out, and the
status verdict built on it. Pure helpers; `v3.compute_status_v3` calls them for
`.claude/settings.json` only.
"""

from __future__ import annotations

import copy
import json
import pathlib
import re

from . import mcp as core

SETTINGS_PATH = ".claude/settings.json"

# The three shapes a project-owned handler's `command` may take. Full match only.
# `q` records that the opening quote of the second shape needs its closing one.
COMMAND_RE = re.compile(
    r'(?:bash (?:hooks/|(?P<q>")\$CLAUDE_PROJECT_DIR/hooks/)|"\$CLAUDE_PROJECT_DIR"/hooks/)'
    r'(?P<name>[A-Za-z0-9._-]+\.sh)(?(q)")'
)

Removed = list[tuple[str, object, dict]]


def toolkit_hook_names(repo_root: pathlib.Path) -> frozenset[str] | None:
    """Lowercase names of `repo_root/hooks/*.sh`, or None if it cannot be listed."""
    try:
        return frozenset(p.name.lower() for p in (repo_root / "hooks").iterdir()
                         if p.name.lower().endswith(".sh"))
    except OSError:
        return None


def _is_project_owned(handler: object, pp: pathlib.Path, names: frozenset[str]) -> bool:
    if not isinstance(handler, dict) or handler.get("type") != "command" or "args" in handler:
        return False
    command = handler.get("command")
    match = COMMAND_RE.fullmatch(command) if isinstance(command, str) else None
    if match is None or match.group("name").lower() in names:
        return False
    script = pp / "hooks" / match.group("name")
    return script.is_file() and not script.is_symlink()


def strip_project_hooks(proj: dict, tpl: dict, pp: pathlib.Path,
                        names: frozenset[str]) -> tuple[dict, Removed]:
    """A deep copy of `proj` without the project's handlers (emptied groups and
    events dropped), plus the removed (event, matcher, handler) triples in file order.

    A handler the template carries under the same event (any matcher group) is
    the template's, never the project's."""
    out = copy.deepcopy(proj)
    removed: Removed = []
    events = out.get("hooks")
    if not isinstance(events, dict):
        return out, removed
    tpl_events = tpl.get("hooks") if isinstance(tpl.get("hooks"), dict) else {}
    for event in list(events):
        groups = events[event]
        if not isinstance(groups, list):
            continue
        template_handlers = [h for g in tpl_events.get(event, []) if isinstance(g, dict)
                             for h in (g.get("hooks") if isinstance(g.get("hooks"), list) else [])]
        kept_groups = []
        for group in groups:
            handlers = group.get("hooks") if isinstance(group, dict) else None
            if not isinstance(handlers, list):
                kept_groups.append(group)
                continue
            kept = []
            for handler in handlers:
                if handler not in template_handlers and _is_project_owned(handler, pp, names):
                    removed.append((event, group.get("matcher"), handler))
                else:
                    kept.append(handler)
            if kept or len(kept) == len(handlers):
                group["hooks"] = kept
                kept_groups.append(group)
        if kept_groups or not groups:
            events[event] = kept_groups
        else:
            del events[event]
    return out, removed


def labels(removed: Removed) -> list[str]:
    return [f"{event} {matcher!s} {handler['command']}" for event, matcher, handler in removed]


def _parse_object(text: str | None) -> dict | None:
    if text is None:
        return None
    try:
        obj = json.loads(text.removeprefix("﻿"))
    except ValueError:
        return None
    return obj if isinstance(obj, dict) else None


def project_hooks_status(entry_hash_hex: str, tpl_replaced: str | None, proj_content: str | None,
                         pp: pathlib.Path, names: frozenset[str] | None,
                         base_provider) -> tuple[str, Removed] | None:
    """Second opinion on a LOCAL_EDITED verdict for settings.json: the project
    minus its own handlers equals the current template, or the one held at sync.

    Returns (status, removed), or None to leave the verdict alone. `base_provider`
    is called only when the stripped project differs from the current template.
    """
    tpl, proj = _parse_object(tpl_replaced), _parse_object(proj_content)
    if tpl is None or proj is None or names is None:
        return None
    stripped, removed = strip_project_hooks(proj, tpl, pp, names)
    if not removed:
        return None
    if stripped != tpl:
        base = _parse_object(base_provider())
        if base is None or stripped != base:
            return None
    status = "TEMPLATE_UPDATED" if core._sha256(tpl_replaced) != entry_hash_hex else "IDENTICAL"
    return status, removed
