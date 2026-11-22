#!/usr/bin/env python3
"""self-review-count.py -- counts for the toolkit self-review report (stage 1).

Read-only over Claude Code JSONL transcripts, stdlib only, never shipped to consumers.
It never calls a model or the network. The shared JSON holds counts only: no
conversation text, no path below the clone root, no project name, no env value.
Per-project detail goes to a sibling <out>.local.json that stays on the machine.

  python3 scripts/self-review-count.py [--since YYYY-MM-DD] [--until YYYY-MM-DD]
         [--root DIR] [--clone-root DIR ...] [--toolkit DIR] [--machine LABEL] [--out FILE]
  python3 scripts/self-review-count.py --merge DIR     # one table from every shared JSON in DIR
  python3 scripts/self-review-count.py --self-test
"""
import argparse
import glob
import importlib.util
import json
import math
import os
import platform
import re
import secrets
import shutil
import sys
import tempfile
from datetime import date, timedelta, timezone

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, 'fixtures', 'self-review')
SCHEMA = 1
TOKEN_FIELDS = (('input', 'input_tokens'), ('cache_read', 'cache_read_input_tokens'),
                ('output', 'output_tokens'))
AGENT_TOOLS = {'Agent', 'Task'}
PLUGIN_PREFIX = 'cct:'
BUILTIN_AGENTS = {'general-purpose', 'Explore', 'Plan', 'statusline-setup', 'claude-code-guide'}
SYNTHETIC = '<synthetic>'
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
MODEL_RE = re.compile(r'claude-[a-z0-9.-]+')
# Only a family and short digit groups may follow `claude-`: no dots, no words, no long numbers (an
# account id), so no host or project names.
MODEL_ALLOWED_RE = re.compile(r'claude-(?:(?:opus|sonnet|haiku|fable|instant)(?:-[0-9]{1,8})*'
                              r'|[0-9]{1,8}(?:-[0-9]{1,8})*-(?:opus|sonnet|haiku|instant)(?:-[0-9]{1,8})*)')
HOOK_PATH_RE = re.compile(r'hooks[/\\]([A-Za-z0-9._-]+?)\.sh')
HOOK_NAME_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._-]*')
WRAPPER_HOOKS = {'dispatch', 'run-hook'}  # the plugin's launchers: the hook they run is not in their path
BLOCKED_RE = re.compile(r'BLOCKED: (\S+)')
BLOCKED_TEXT_RE = re.compile(r'BLOCKED: ([^"\'$`\\(\r\n]+)')  # the literal start of a refusal text in a hook
COMMAND_RE = re.compile(r'<command-name>/cct:([A-Za-z0-9._-]+)</command-name>')
MIN_PREFIX = 12  # a shorter prefix would match too much
# Texts the plugin's launcher prints when it cannot start a hook; they are not in a hooks/*.sh file.
DISPATCH_REFUSALS = ('cct plugin files are missing', 'bash not found on PATH')
UNATTRIBUTED = '<unattributed>'
MAX_COUNT = 10 ** 15  # a usage field above this is garbage and counts as 0
CORRECTION_RE = re.compile(
    r"^(no\b|nope\b|don['’]?t\b|do not\b|stop\b|wrong\b|that['’]?s (not|wrong)\b|not what\b|i said\b"
    r"|i told you\b|why did you\b|you (forgot|missed|didn['’]?t)\b)", re.IGNORECASE)
CORRECTION_CHARS = 300
OTHER = 'other'
NOTE_KINDS = ('helped', 'recurring_failure', 'rule_unused')
# The shared JSON keys merge() handles: the header ones are not table rows. The self-test fails when
# count() writes a key outside these, so a new measure cannot silently miss the merged table.
HEADER_KEYS = {'schema', 'machine', 'since', 'until', 'claude_code_versions'}
MEASURE_KEYS = {'spawns', 'tokens_by_model', 'token_share', 'toolkit_use', 'hook_blocks', 'correction_candidates',
                'correction_kinds', 'notes', 'notes_malformed', 'jev', 'unreadable_files'}
SURFACE_RE = re.compile(r'[A-Za-z0-9][A-Za-z0-9._:+-]{0,63}')  # a name, never a path


def _load_script(filename):
    spec = importlib.util.spec_from_file_location(filename[:-len('.py')].replace('-', '_'),
                                                  os.path.join(HERE, filename))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_MP = _load_script('measure-process.py')
load_rows, parse_ts, compare = _MP.load_rows, _MP.parse_ts, _MP.compare
_JT = _load_script('jev-tally.py')


def default_machine(system, id_path):
    """A label that tells machines apart without being derived from anything about the host:
    `<os>-<6 hex>`, the hex random, made once and kept in `id_path` for the next run. A missing or
    garbled file gets a new id; if it cannot be written the label is still returned, unstored."""
    try:
        with open(id_path, encoding='utf-8') as fh:
            token = fh.read().strip()
    except OSError:
        token = ''
    if not re.fullmatch(r'[0-9a-f]{6}', token):
        token = secrets.token_hex(3)
        try:
            os.makedirs(os.path.dirname(id_path), exist_ok=True)
            with open(id_path, 'w', encoding='utf-8', newline='\n') as fh:
                fh.write(token + '\n')
        except OSError:
            pass
    return '%s-%s' % (system.lower(), token)


def toolkit_name(called, names):
    """The bare toolkit name behind a call, or None. Only `cct:<name>` is the toolkit's: a bare name
    may be a Claude Code built-in (Explore) or another plugin's."""
    if isinstance(called, str) and called.startswith(PLUGIN_PREFIX) and called[len(PLUGIN_PREFIX):] in names:
        return called[len(PLUGIN_PREFIX):]
    return None


def num(value):
    """A usage field as an int; anything non-numeric, NaN, infinite or above MAX_COUNT counts as 0."""
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return 0
    if isinstance(value, float) and not math.isfinite(value):
        return 0
    return int(value) if abs(value) <= MAX_COUNT else 0


def norm_model(model):
    """A model string that is safe to share: the `claude-...` name (after any provider prefix, without a
    `-v<n>`, `:<n>` or `@...` suffix) when it is a known model family, else 'other-model'. A gateway or
    cloud provider's model id can carry a host name, a project name or an account id (an ARN)."""
    hit = MODEL_RE.search(model)
    name = re.sub(r'-v\d+$', '', hit.group()) if hit else ''
    return name if MODEL_ALLOWED_RE.fullmatch(name) else 'other-model'


def cut_text(text):
    return text[:CORRECTION_CHARS]


def in_window(day, since, until):
    return since <= day and (not until or day <= until)


def toolkit_names(toolkit_root):
    """-> (skill names, agent names) the toolkit ships, from its skills/ dirs and agents/*.md."""
    skills_dir, agents_dir = os.path.join(toolkit_root, 'skills'), os.path.join(toolkit_root, 'agents')
    skills = []
    agents = []
    if os.path.isdir(skills_dir):
        skills = [n for n in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, n))]
    if os.path.isdir(agents_dir):
        agents = [n[:-len('.md')] for n in os.listdir(agents_dir) if n.endswith('.md')]
    return sorted(skills), sorted(agents)


def user_parts(msg):
    """-> (typed text or None, [(is_error, tool result text)]) of a user message. A message holding
    any tool result is not typed by the user."""
    content = msg.get('content')
    if isinstance(content, str):
        return content, []
    blocks = [b for b in content if isinstance(b, dict)] if isinstance(content, list) else []
    results = []
    for b in blocks:
        if b.get('type') != 'tool_result':
            continue
        inner = b.get('content')
        if isinstance(inner, list):
            inner = '\n'.join(x['text'] for x in inner if isinstance(x, dict) and isinstance(x.get('text'), str))
        results.append((b.get('is_error') is True, inner if isinstance(inner, str) else ''))
    if results:
        return None, results
    texts = [b['text'] for b in blocks if b.get('type') == 'text' and isinstance(b.get('text'), str)]
    return ('\n'.join(texts) if texts else None), []


def hook_token(token):
    """A `BLOCKED:` token as a hook name: lower-cased, without a trailing `:` or `.sh`."""
    name = token.lower()
    name = name[:-1] if name.endswith(':') else name
    return name[:-len('.sh')] if name.endswith('.sh') else name


def refusal_table(toolkit_root, hook_names):
    """-> [(prefix, hook)], longest prefix first: the toolkit's own refusal texts that do not start with
    a hook name, from the `BLOCKED: ` strings in hooks/*.sh (the hook is the file) and hooks/hooks.json
    (the hook is `dispatch`), plus DISPATCH_REFUSALS. The prefix is the literal text after `BLOCKED: `
    up to the first quote, `$`, backtick, backslash or `(`, and up to the end of its first sentence.
    A prefix found in two hooks maps to `other`."""
    found = {p: {'dispatch'} for p in DISPATCH_REFUSALS}
    paths = [(p, os.path.basename(p)[:-len('.sh')]) for p in glob.glob(os.path.join(toolkit_root, 'hooks', '*.sh'))]
    paths.append((os.path.join(toolkit_root, 'hooks', 'hooks.json'), 'dispatch'))
    for path, hook in paths:
        try:
            with open(path, encoding='utf-8', errors='replace') as fh:
                text = fh.read()
        except OSError:
            continue
        for hit in BLOCKED_TEXT_RE.finditer(text):
            prefix = hit.group(1).strip()
            sentence = re.match(r'(.*?\.)(?:\s|$)', prefix)  # the first sentence, when it ends inside
            prefix = sentence.group(1) if sentence else prefix
            if len(prefix) >= MIN_PREFIX and hook_token(prefix.split()[0]) not in hook_names:
                found.setdefault(prefix, set()).add(hook)
    table = [(p, next(iter(h)) if len(h) == 1 else OTHER) for p, h in found.items()]
    return sorted(table, key=lambda e: (-len(e[0]), e[0]))


def block_hook(text, is_error, refusals=()):
    """The hook behind a real hook denial, else None.

    A denial is an error tool result that starts `PreToolUse:` and has `hook error:` in its first 200
    characters; a result that only quotes `BLOCKED:` is not one. The hook is the first `hooks/<name>.sh`
    in the bracketed command, else the hook of the first `refusals` prefix (see refusal_table) the text
    after the first `BLOCKED: ` starts with, else its first token (lower-cased, without a trailing `:`
    or `.sh`), else `<unattributed>`. The plugin's launchers `dispatch.sh` and
    `run-hook.sh` are not the hook: for `run-hook.sh <name>` the hook is the command's last word, else
    (and for `dispatch.sh`) the `BLOCKED:` text decides.
    """
    if is_error is not True or not text.startswith('PreToolUse:') or 'hook error:' not in text[:200]:
        return None
    head, sep, tail = text.partition(']: ')
    hit = HOOK_PATH_RE.search(head) if sep else None
    if hit and hit.group(1) not in WRAPPER_HOOKS:
        return hit.group(1)
    if hit and hit.group(1) == 'run-hook':
        last = head.split()[-1]
        if HOOK_NAME_RE.fullmatch(last):
            return last.lower()[:-len('.sh')] if last.lower().endswith('.sh') else last.lower()
    hit = BLOCKED_RE.search(tail)
    if not hit:
        return UNATTRIBUTED
    rest = tail[hit.start() + len('BLOCKED: '):]
    for prefix, hook in refusals:
        if rest.startswith(prefix):
            return hook
    return hook_token(hit.group(1)) or UNATTRIBUTED


def correction_text(typed):
    """The stripped text when a typed user turn reads as a correction, else None."""
    text = (typed or '').strip()
    return text if text and not text.startswith('<') and CORRECTION_RE.match(text) else None


def assistant_text(msg):
    """The text blocks of an assistant message, joined (a plain string content is the text), or ''."""
    content = msg.get('content')
    if isinstance(content, str):
        return content
    return '\n'.join(b['text'] for b in content if isinstance(b, dict) and b.get('type') == 'text'
                     and isinstance(b.get('text'), str)) if isinstance(content, list) else ''


def scan(rows, since, until, refusals=()):
    """Reduce one transcript to what counts inside the window.

    -> dict: first_day (of the first timestamped row, in or out of the window), first_model (first
    non-synthetic model in the whole transcript) or None, and, for in-window rows only:
    versions {v: n}, usage {message id: (model, {field: n})}, calls [(tool name, input)],
    commands [skill name of each `/cct:<skill>` command row, once per row],
    blocks [attributed hook name of each real hook denial, see block_hook],
    corrections [(timestamp, text) of each typed user turn that reads as a correction and does not
    answer a question: the latest assistant text before it does not end in `?`].
    A message split over several rows repeats its usage, so usage is kept once per message id.
    """
    out = {'first_day': None, 'first_model': None, 'versions': {}, 'usage': {}, 'calls': [],
           'commands': [], 'blocks': [], 'corrections': []}
    asked = False  # the latest assistant text, in or out of the window, ends in a question mark
    for i, row in enumerate(rows):
        msg = row.get('message')
        model = None
        if isinstance(msg, dict) and row.get('type') == 'assistant':
            said = assistant_text(msg).rstrip()
            if said:
                asked = said.endswith('?')
            model = msg.get('model') if isinstance(msg.get('model'), str) else None
            if model == SYNTHETIC:
                model = None
            if model:
                model = norm_model(model)
            if model and out['first_model'] is None:
                out['first_model'] = model
        t = parse_ts(row)
        if t is None:
            continue
        if t.tzinfo is not None:
            t = t.astimezone(timezone.utc)
        day = t.date().isoformat()
        if out['first_day'] is None:
            out['first_day'] = day
        if not in_window(day, since, until):
            continue
        version = row.get('version')
        if isinstance(version, str):
            out['versions'][version] = out['versions'].get(version, 0) + 1
        if isinstance(msg, dict) and row.get('type') == 'user':
            typed, results = user_parts(msg)
            for is_error, text in results:
                hook = block_hook(text, is_error, refusals)
                if hook:
                    out['blocks'].append(hook)
            command = COMMAND_RE.search(typed) if typed else None
            if command:
                out['commands'].append(command.group(1))
            text = None if row.get('isMeta') or asked else correction_text(typed)
            if text:
                out['corrections'].append((row['timestamp'] if isinstance(row.get('timestamp'), str) else '', text))
        if not isinstance(msg, dict) or row.get('type') != 'assistant':
            continue
        usage = msg.get('usage')
        if isinstance(usage, dict):
            mid = msg.get('id') or 'row%d' % i
            old_model, old = out['usage'].get(mid, (None, {}))
            merged = {f: max(old.get(f, 0), num(usage.get(src))) for f, src in TOKEN_FIELDS}
            out['usage'][mid] = (old_model or model, merged)
        content = msg.get('content')
        for block in content if isinstance(content, list) else []:
            if isinstance(block, dict) and block.get('type') == 'tool_use' and isinstance(block.get('input'), dict):
                out['calls'].append((block.get('name'), block['input']))
    return out


def agent_type_of(sub_path, agent_names):
    """-> (shared key, verbatim type) for a subagent, from its .meta.json agentType.

    The shared key never carries a project-specific name: `cct:<toolkit agent>` and the Claude Code
    built-ins pass through, a missing or unreadable meta or no agentType is 'unknown', the rest 'other'.
    The verbatim type is for the local-only file.
    """
    try:
        with open(sub_path[:-len('.jsonl')] + '.meta.json', encoding='utf-8') as fh:
            name = json.load(fh).get('agentType')
    except (OSError, ValueError, AttributeError):
        return 'unknown', 'unknown'
    if not isinstance(name, str) or not name:
        return 'unknown', 'unknown'
    if name in BUILTIN_AGENTS or toolkit_name(name, agent_names):
        return name, name
    return 'other', name


def _zero():
    return {f: 0 for f, _ in TOKEN_FIELDS}


def toolkit_hooks(toolkit_root):
    """The names (file name without .sh) of the hooks the toolkit ships in hooks/*.sh."""
    return sorted(os.path.basename(p)[:-len('.sh')] for p in glob.glob(os.path.join(toolkit_root, 'hooks', '*.sh')))


def toolkit_surfaces(toolkit_root, skill_names, agent_names, hook_names):
    """Every name a note's surface may carry into the shared file: the toolkit's skills, agents and
    hooks, and each path (with `/`) that exists under templates/general/."""
    surfaces = set(skill_names) | set(agent_names) | set(hook_names)
    base = os.path.join(toolkit_root, 'templates', 'general')
    for cur, dirs, files in os.walk(base):
        for name in dirs + files:
            surfaces.add(os.path.relpath(os.path.join(cur, name), base).replace(os.sep, '/'))
    return surfaces


def parse_note(line, known=()):
    """One improvement-notes line -> the note dict, or None when it is not a valid note: a JSON
    object with a known kind, a YYYY-MM-DD date, a surface that is a toolkit surface (`known`) or a
    plain name (not a path) and a count that is a whole number >= 0 (default 1)."""
    try:
        note = json.loads(line)
    except ValueError:
        return None
    if not isinstance(note, dict) or note.get('kind') not in NOTE_KINDS:
        return None
    day, surface, n = note.get('date'), note.get('surface'), note.get('count', 1)
    if not isinstance(day, str) or not DATE_RE.match(day):
        return None
    try:
        date.fromisoformat(day)  # DATE_RE has the shape; this rejects 2026-13-45
    except ValueError:
        return None
    if not isinstance(surface, str) or not (surface in known or SURFACE_RE.fullmatch(surface)):
        return None
    if isinstance(n, bool) or not isinstance(n, int) or n < 0:
        return None
    return note


def read_notes(clone_roots, known, since, until):
    """Read <root>/*/.claude/improvement-notes.jsonl under every clone root; keep the notes dated in
    [since, until].

    -> (shared notes {kind: {surface: {count, projects}}}, local notes {project: [note]}, malformed
    lines, unreadable files). A surface outside `known` is counted under `other` in the shared notes.
    `projects` is how many distinct projects hold the surface; none is named.
    """
    seen, malformed, unreadable = {}, 0, 0
    local = {}
    for root in clone_roots:
        pattern = os.path.join(os.path.expanduser(root), '*', '.claude', 'improvement-notes.jsonl')
        for path in sorted(glob.glob(pattern)):
            project_dir = os.path.dirname(os.path.dirname(path))
            try:
                with open(path, encoding='utf-8', errors='replace') as fh:
                    lines = [ln for ln in fh.read().splitlines() if ln.strip()]
            except OSError:
                unreadable += 1
                continue
            for ln in lines:
                note = parse_note(ln, known)
                if note is None:
                    malformed += 1
                    continue
                if not in_window(note['date'], since, until):
                    continue
                local.setdefault(os.path.basename(project_dir), []).append(note)
                key = note['surface'] if note['surface'] in known else OTHER
                slot = seen.setdefault(note['kind'], {}).setdefault(key, {'count': 0, 'projects': set()})
                slot['count'] += note.get('count', 1)
                slot['projects'].add(project_dir)
    shared = {kind: {s: {'count': v['count'], 'projects': len(v['projects'])} for s, v in by_surface.items()}
              for kind, by_surface in seen.items()}
    return shared, local, malformed, unreadable


def jev_counts(clone_roots, since, until):
    """Jev router events in the window across the clone roots -> {events, applied, up, down, skipped_files}.
    up/down count applied events whose emitted model ranks above/below the default, as jev-tally does."""
    events, skipped = _JT._load_events(clone_roots, since)
    events = [e for e in events if not until or e['ts'][:10] <= until]
    applied = [e for e in events if e.get('applied') is True]
    rank = _JT._rank
    return {'events': len(events), 'applied': len(applied),
            'up': sum(rank(e.get('emitted')) > rank(e.get('default')) for e in applied),
            'down': sum(rank(e.get('emitted')) < rank(e.get('default')) for e in applied),
            'skipped_files': skipped}


def inputs_line(clone_roots):
    """What the clone roots held, so a run from the wrong place does not pass for a quiet one:
    'clone roots: N, notes files: N, Jev event files: N' (the files count() looks for, windowed or not)."""
    roots = list(dict.fromkeys(os.path.realpath(os.path.expanduser(r)) for r in clone_roots))

    def found(*parts):
        return sum(len(glob.glob(os.path.join(r, '*', *parts))) for r in roots)

    return 'clone roots: %d, notes files: %d, Jev event files: %d' % (
        len(roots), found('.claude', 'improvement-notes.jsonl'), found('.git', 'jev', 'events', '*.json'))


def count(projects_root, clone_roots, toolkit_root, since, until, machine):
    """Count one machine's transcripts in [since, until], plus the notes and Jev events under the
    clone roots. -> (shared, local)."""
    skill_names, agent_names = toolkit_names(toolkit_root)
    use = {'skills': {n: 0 for n in skill_names}, 'agents': {n: 0 for n in agent_names}}
    versions, spawns, by_model, per_project = {}, {}, {}, {}
    share = {'main': _zero(), 'sub': _zero()}
    hook_names = toolkit_hooks(toolkit_root)
    refusals = refusal_table(toolkit_root, hook_names)
    hook_blocks, local_hooks, corrections = {}, {}, []
    unreadable = 0
    clone_roots = list(dict.fromkeys(os.path.realpath(os.path.expanduser(r)) for r in clone_roots))
    for slug in sorted(os.listdir(projects_root)):
        pdir = os.path.join(projects_root, slug)
        if not os.path.isdir(pdir):
            continue
        local = per_project[slug] = {'spawns': {}, 'tokens': 0}
        files = [(p, False) for p in glob.glob(os.path.join(pdir, '*.jsonl'))]
        files += [(p, True) for p in glob.glob(os.path.join(pdir, '*', 'subagents', 'agent-*.jsonl'))]
        for path, is_sub in sorted(files):
            try:
                rows = load_rows(path)
            except OSError:
                unreadable += 1
                continue
            s = scan(rows, since, until, refusals)
            for v, n in s['versions'].items():
                versions[v] = versions.get(v, 0) + n
            for model, tok in s['usage'].values():
                for f, _ in TOKEN_FIELDS:
                    share['sub' if is_sub else 'main'][f] += tok[f]
                    local['tokens'] += tok[f]
                    if model:
                        by_model.setdefault(model, _zero())[f] += tok[f]
            for hook in s['blocks']:
                key = hook if hook in hook_names else OTHER  # a project's own hook name stays local
                hook_blocks[key] = hook_blocks.get(key, 0) + 1
                local_hooks[hook] = local_hooks.get(hook, 0) + 1
            if not is_sub:  # a subagent's user rows are its parent's prompts, not the user's words
                corrections += [{'project': slug, 'ts': ts, 'text': cut_text(text)} for ts, text in s['corrections']]
            for skill in [] if is_sub else s['commands']:  # a `/cct:<skill>` row starts the skill like a Skill call
                key = toolkit_name(PLUGIN_PREFIX + skill, use['skills'])
                if key:
                    use['skills'][key] += 1
            for name, inp in s['calls']:
                if name == 'Skill':
                    called, names = inp.get('skill'), use['skills']
                elif name in AGENT_TOOLS:
                    called, names = inp.get('subagent_type'), use['agents']
                else:
                    continue
                key = toolkit_name(called, names)
                if key:
                    names[key] += 1
            if is_sub and s['first_day'] and in_window(s['first_day'], since, until):
                model = s['first_model'] or 'unknown'
                key, verbatim = agent_type_of(path, agent_names)
                by_type = spawns.setdefault(key, {})
                by_type[model] = by_type.get(model, 0) + 1
                local['spawns'][verbatim] = local['spawns'].get(verbatim, 0) + 1
    main_total, sub_total = sum(share['main'].values()), sum(share['sub'].values())
    share['sub_share'] = round(sub_total / (main_total + sub_total), 4) if main_total + sub_total else 0.0
    known = toolkit_surfaces(toolkit_root, skill_names, agent_names, hook_names)
    notes, local_notes, notes_malformed, notes_unreadable = read_notes(clone_roots, known, since, until)
    shared = {'schema': SCHEMA, 'machine': machine, 'since': since, 'until': until,
              'claude_code_versions': versions, 'spawns': spawns, 'tokens_by_model': by_model,
              'token_share': share, 'toolkit_use': use, 'hook_blocks': hook_blocks,
              'correction_candidates': len(corrections), 'notes': notes, 'notes_malformed': notes_malformed,
              'jev': jev_counts(clone_roots, since, until), 'unreadable_files': unreadable + notes_unreadable}
    return shared, {'per_project': per_project, 'corrections': corrections, 'notes': local_notes,
                    'hook_blocks': local_hooks}


def key_diffs(got, want, path):
    """Lines for every dict in `want` whose key set differs from the matching dict in `got`."""
    if not isinstance(want, dict):
        return []
    if not isinstance(got, dict) or sorted(got) != sorted(want):
        return ['%s: keys want %s, got %s' % (path, sorted(want), sorted(got) if isinstance(got, dict) else got)]
    return [line for k in want for line in key_diffs(got[k], want[k], path + '/' + k)]


def copy_fixture_clones(dest):
    """Copy the fixture clones to dest, renaming each `dot-git` to `.git` (git cannot track a `.git` path)."""
    shutil.copytree(os.path.join(FIXTURES, 'clones'), dest)
    for path in glob.glob(os.path.join(dest, '*', 'dot-git')):
        os.rename(path, os.path.join(os.path.dirname(path), '.git'))


def leak_probes(shared, local):
    """Lines for every private fixture string found in the shared JSON, with a control for each that
    proves the probe can see the string where it is allowed to be."""
    bad = []
    flat_shared, flat_local = json.dumps(shared), json.dumps(local)
    # (string, why it must not be shared, whether it must be in the local file)
    for needle, what, in_local in (
            ('alpha-db-expert', 'a project-specific agent type', True),
            ('ZZ-PRIVATE-MARKER-7f3a', 'conversation text', True),
            ('ZZ-NOTE-MARKER-2c9d', 'a note summary', True),
            ('seal-guard', 'a project hook name', True),
            ('zz-private-surface', 'a project-specific note surface', True),
            ('zz-other-surface', 'a project-specific note surface', True),
            ('alpha', 'the project name', True),
            ('beta', 'a clone (project) name', True),
            ('gamma', 'a clone (project) name', True),
            ('123456789012', 'an account id from a model string', False),
            ('corp.example', 'a gateway host name in a model string', False),
            ('secretproject', 'a project name in a model string', False),
            ('acme', 'a project name after a model family', False),
            ('internal', 'a word after a model name', False)):
        if needle in flat_shared:
            bad.append('/shared: %s leaked (%r)' % (what, needle))
        if in_local and needle not in flat_local:
            bad.append('CONTROL FAILED: %s (%r) is not in the local file' % (what, needle))
    return bad


def inbox_paths(directory):
    """The shared JSON files in a directory: every *.json that is not a *.local.json, sorted."""
    return sorted(p for p in glob.glob(os.path.join(glob.escape(directory), '*.json')) if not p.endswith('.local.json'))


def _dict(value):
    return value if isinstance(value, dict) else {}


def measures(data):
    """One machine's shared JSON -> {row label: count}, one row per measure leaf. A key a machine
    lacks is simply not there (the table reads it as 0). `sub_share` is computed in merge()."""
    rows = {}

    def add(label, n):
        rows[label] = rows.get(label, 0) + num(n)

    def safe_model(model):  # a file may come from an older or hand-made run: never trust its model keys
        return model if model == 'unknown' else norm_model(model)

    for kind, by_model in _dict(data.get('spawns')).items():
        for model, n in _dict(by_model).items():
            add('spawns %s %s' % (kind, safe_model(model)), n)
    for model, by_field in _dict(data.get('tokens_by_model')).items():
        for field, n in _dict(by_field).items():
            add('tokens %s %s' % (safe_model(model), field), n)
    for word, key in (('skill', 'skills'), ('agent', 'agents')):
        for name, n in _dict(_dict(data.get('toolkit_use')).get(key)).items():
            rows['%s %s' % (word, name)] = num(n)
    for key in ('hook_blocks', 'jev'):
        for name, n in _dict(data.get(key)).items():
            rows['%s %s' % (key, name)] = num(n)
    for key in ('correction_candidates', 'notes_malformed', 'unreadable_files'):
        rows[key] = num(data.get(key))
    kinds = data.get('correction_kinds')
    for item in kinds if isinstance(kinds, list) else []:
        if isinstance(item, dict) and isinstance(item.get('kind'), str):
            label = 'correction_kind %s' % item['kind']
            rows[label] = rows.get(label, 0) + num(item.get('count'))
    for kind, by_surface in _dict(data.get('notes')).items():
        for surface, slot in _dict(by_surface).items():
            rows['notes %s %s count' % (kind, surface)] = num(_dict(slot).get('count'))
            rows['notes %s %s projects (sum over machines)' % (kind, surface)] = num(_dict(slot).get('projects'))
    return rows


def version_key(version):
    """Sort 2.1.9 before 2.1.10: a run of digits compares by length, then text (never int(), which
    refuses a very long run)."""
    return [(0, len(p.lstrip('0')), p.lstrip('0')) if p.isdecimal() else (1, 0, p)
            for p in re.split(r'([0-9]+)', version) if p]


def sub_share(main, sub):
    return '%.4f' % (round(sub / (main + sub), 4) if main + sub else 0.0)


def cell(text):
    return re.sub(r'[|\r\n]', ' ', str(text))


def merge(paths):
    """Merge the shared JSONs at `paths` into one Markdown table: a row per measure, a column per
    machine label (sorted) and a `total` column; `sub_share`'s total is recomputed from the summed
    main/sub tokens, as is each machine's own. A file that does not parse, is not schema 1 or has no
    valid machine label or dates is listed after the table as `skipped: <file name>`. When several
    files carry one machine label the one with the latest `since` is kept (a tie: the later file
    name); each other is listed as `skipped: <file> (machine <label> also in <kept file>)`."""
    machines, skipped, dropped = {}, [], []
    for path in paths:
        name = os.path.basename(path)
        try:
            with open(path, encoding='utf-8') as fh:
                data = json.load(fh)
            label, since, until = data.get('machine'), data.get('since'), data.get('until')
            if isinstance(data.get('schema'), bool) or data.get('schema') != SCHEMA \
                    or not isinstance(label, str) or not label \
                    or not isinstance(since, str) or not DATE_RE.fullmatch(since) \
                    or not (until is None or isinstance(until, str) and DATE_RE.fullmatch(until)):
                raise ValueError(path)
            share = _dict(data.get('token_share'))
            entry = {'name': name, 'data': data, 'rows': measures(data),
                     'main': sum(num(_dict(share.get('main')).get(f)) for f, _ in TOKEN_FIELDS),
                     'sub': sum(num(_dict(share.get('sub')).get(f)) for f, _ in TOKEN_FIELDS)}
        except (OSError, ValueError, TypeError, AttributeError, RecursionError):
            skipped.append('skipped: %s' % cell(name))
            continue
        old = machines.get(label)
        if old and (old['data']['since'], old['name']) > (since, name):
            dropped.append((name, label))
            continue
        if old:
            dropped.append((old['name'], label))
        machines[label] = entry
    skipped += ['skipped: %s (machine %s also in %s)' % (cell(n), cell(x), cell(machines[x]['name']))
                for n, x in dropped]
    labels = sorted(machines)
    versions = {v for m in machines.values() for v in _dict(m['data'].get('claude_code_versions'))}
    untils = [m['data'].get('until') for m in machines.values()]
    window = '-'
    if machines:
        window = '%s .. %s' % (min(m['data']['since'] for m in machines.values()),
                               'open' if None in untils else max(untils))
    out = ['claude_code_versions: %s' % (', '.join(cell(v) for v in sorted(versions, key=lambda v: (version_key(v), v)))
                                         or '-'),
           'window: %s' % window]
    if len({(m['data']['since'], m['data'].get('until')) for m in machines.values()}) > 1:
        out.append('windows differ: %s' % '; '.join(
            '%s %s..%s' % (cell(x), machines[x]['data']['since'], machines[x]['data'].get('until') or 'open')
            for x in labels))
    out += ['', '| %s |' % ' | '.join(['measure'] + [cell(x) for x in labels] + ['total']),
            '| %s |' % ' | '.join(['---'] + ['---:'] * (len(labels) + 1))]
    main_sum, sub_sum = sum(m['main'] for m in machines.values()), sum(m['sub'] for m in machines.values())
    for row in sorted({r for m in machines.values() for r in m['rows']} | ({'sub_share'} if machines else set())):
        if row == 'sub_share':
            cells = [sub_share(machines[x]['main'], machines[x]['sub']) for x in labels] + [sub_share(main_sum, sub_sum)]
        else:
            values = [machines[x]['rows'].get(row, 0) for x in labels]
            cells = [str(v) for v in values] + [str(sum(values))]
        out.append('| %s |' % ' | '.join([cell(row)] + cells))
    if skipped:
        out.append('')
        out += sorted(skipped)
    return '\n'.join(out) + '\n'


def merge_checks():
    """Lines for every merge() self-test that fails."""
    inbox = os.path.join(FIXTURES, 'inbox')
    with open(os.path.join(FIXTURES, 'expected-merge.md'), encoding='utf-8') as fh:
        want = fh.read()

    def fixture(name, **changes):
        with open(os.path.join(inbox, name), encoding='utf-8') as fh:
            data = json.load(fh)
        data.update(changes)
        return data

    bad = []
    try:
        if merge(inbox_paths(inbox)) != want:
            bad.append('/merge: the fixture inbox does not give expected-merge.md')
        with tempfile.TemporaryDirectory() as tmp:
            copy = os.path.join(tmp, 'inbox')
            shutil.copytree(inbox, copy)
            # old.json is a full, valid file but for its schema: only the schema check may skip it
            write_json(os.path.join(copy, 'old.json'), fixture('windows-bbbbbb.json', schema=2, machine='linux-cccccc'))
            for name, text in (('broken.json', '{not json'), ('linux-aaaaaa.local.json', '{"per_project": {}}')):
                with open(os.path.join(copy, name), 'w', encoding='utf-8', newline='\n') as fh:
                    fh.write(text)
            if merge(inbox_paths(copy)) != want + '\nskipped: broken.json\nskipped: old.json\n':
                bad.append('/merge: a malformed or schema 2 file is not listed as skipped, or a .local.json is read')
        one = merge([os.path.join(inbox, 'linux-aaaaaa.json')])
        if '| measure | linux-aaaaaa | total |' not in one or '| sub_share | 0.3571 | 0.3571 |' not in one:
            bad.append('/merge: one machine has no total column')
        if 'windows differ' in one:
            bad.append('/merge: one machine reports differing windows')
        if '\nwindow: 2026-11-01 .. 2026-12-06\nwindows differ: linux-aaaaaa 2026-11-01..2026-11-30; ' \
                'windows-bbbbbb 2026-11-08..2026-12-06\n\n' not in want:
            bad.append('/merge: the fixture inbox differs in window but expected-merge.md has no windows-differ line')
        with tempfile.TemporaryDirectory() as tmp:  # one window on two machines: no windows-differ line
            write_json(os.path.join(tmp, 'a.json'), fixture('linux-aaaaaa.json'))
            write_json(os.path.join(tmp, 'b.json'), fixture('windows-bbbbbb.json', since='2026-11-01', until='2026-11-30'))
            if 'windows differ' in merge(inbox_paths(tmp)):
                bad.append('/merge: two machines with one window report differing windows')
        with tempfile.TemporaryDirectory() as tmp:  # one label in four files: the latest since wins, a tie the later name
            for name, since, n in (('a-old.json', '2026-11-01', 11), ('b-new.json', '2026-11-15', 99),
                                   ('c-tie.json', '2026-11-15', 55), ('z-stale.json', '2026-10-02', 7)):
                write_json(os.path.join(tmp, name), fixture('linux-aaaaaa.json', since=since, correction_candidates=n))
            got = merge(inbox_paths(tmp))
            lost = ''.join('skipped: %s (machine linux-aaaaaa also in c-tie.json)\n' % n
                           for n in ('a-old.json', 'b-new.json', 'z-stale.json'))
            if not got.endswith('\n\n' + lost) or '| correction_candidates | 55 | 55 |' not in got \
                    or 'window: 2026-11-15 .. 2026-11-30\n' not in got or '| measure | linux-aaaaaa | total |' not in got:
                bad.append('/merge: a repeated machine label is not won by the newest run, or the reason is wrong')
        with tempfile.TemporaryDirectory() as tmp:  # an open-ended window
            write_json(os.path.join(tmp, 'a.json'), fixture('linux-aaaaaa.json'))
            write_json(os.path.join(tmp, 'b.json'), fixture('windows-bbbbbb.json', until=None))
            got = merge(inbox_paths(tmp))
            if 'window: 2026-11-01 .. open\n' not in got:
                bad.append('/merge: a machine without an until does not give an open window')
            if 'windows differ: linux-aaaaaa 2026-11-01..2026-11-30; windows-bbbbbb 2026-11-08..open\n' not in got:
                bad.append('/merge: an open window is not named in the windows-differ line')
        with tempfile.TemporaryDirectory() as tmp:  # a bad schema-1 file must not crash the merge
            write_json(os.path.join(tmp, 'a.json'), fixture('linux-aaaaaa.json'))
            odd = fixture('windows-bbbbbb.json', machine='windows-eeeeee')
            odd['token_share']['sub_share'] = 10 ** 400
            odd['claude_code_versions'] = {'2\u00b2': 1, '9' * 5000: 1, 'v|1\n2': 1}
            write_json(os.path.join(tmp, 'b.json'), odd)
            write_json(os.path.join(tmp, 'c-bad-date.json'), fixture('windows-bbbbbb.json', since='11/08/2026'))
            got = merge(inbox_paths(tmp))
            if not got.endswith('\nskipped: c-bad-date.json\n') or '| measure | linux-aaaaaa | windows-eeeeee | total |' not in got \
                    or '2\u00b2' not in got.split('\n')[0]:
                bad.append('/merge: a huge sub_share, an odd version key or a bad date is not handled')
            if 'v 1 2' not in got.split('\n')[0] or not got.split('\n')[1].startswith('window: '):
                bad.append('/merge: a version with a pipe or a newline breaks the header line')
        with tempfile.TemporaryDirectory() as tmp:  # a model key from an older or hand-made file is normalised
            leaky = fixture('windows-bbbbbb.json')
            leaky['tokens_by_model'] = {'other-model': {'input': 1, 'cache_read': 0, 'output': 0},
                                        'claude-gateway.corp.example.com': {'input': 2, 'cache_read': 0, 'output': 0},
                                        'claude-opus-5-5[1m]': {'input': 4, 'cache_read': 0, 'output': 0}}
            leaky['spawns'] = {'cct:coder': {'claude-gateway.corp.example.com': 3, 'other-model': 1, 'unknown': 5}}
            write_json(os.path.join(tmp, 'a.json'), leaky)
            got = merge(inbox_paths(tmp))
            if 'corp.example' in got or '| tokens other-model input | 3 | 3 |' not in got \
                    or '| tokens claude-opus-5-5 input | 4 | 4 |' not in got \
                    or '| spawns cct:coder other-model | 4 | 4 |' not in got \
                    or '| spawns cct:coder unknown | 5 | 5 |' not in got:
                bad.append('/merge: a model key is not normalised and summed, or a host name reaches the table')
    except Exception as exc:  # a crash must read as a failed test, not a traceback
        bad.append('/merge: exception %s: %s' % (type(exc).__name__, exc))
    return bad


def machine_checks():
    """Lines for every default_machine() self-test that fails. The id file is always in a temp dir."""
    bad = []
    with tempfile.TemporaryDirectory() as tmp:
        id_file = os.path.join(tmp, 'sub', 'machine-id')
        label = default_machine('Linux', id_file)
        if not re.fullmatch(r'linux-[0-9a-f]{6}', label):
            bad.append('/default_machine: %r does not match linux-<6 hex>' % label)
        if not os.path.isfile(id_file):
            bad.append('/default_machine: a missing id file was not created')
        elif default_machine('Linux', id_file) != label:
            bad.append('/default_machine: one id file gave two labels')
        if default_machine('Windows', id_file) != 'windows-' + label[len('linux-'):]:
            bad.append('/default_machine: the stored id is not reused under another os name')
        os.makedirs(os.path.dirname(id_file), exist_ok=True)
        with open(id_file, 'w', encoding='utf-8') as fh:
            fh.write('not an id')
        fresh = default_machine('Linux', id_file)
        if not re.fullmatch(r'linux-[0-9a-f]{6}', fresh) or default_machine('Linux', id_file) != fresh:
            bad.append('/default_machine: a garbled id file is not replaced by a stored id')
        bad_dir = os.path.join(tmp, 'blocker')
        with open(bad_dir, 'w', encoding='utf-8') as fh:  # a file where the directory should be: still a label
            fh.write('x')
        if not re.fullmatch(r'linux-[0-9a-f]{6}', default_machine('Linux', os.path.join(bad_dir, 'machine-id'))):
            bad.append('/default_machine: an id file that cannot be written gave no label')
    return bad


def self_test():
    with open(os.path.join(FIXTURES, 'expected.json'), encoding='utf-8') as fh:
        expected = json.load(fh)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            clones = os.path.join(tmp, 'clones')
            copy_fixture_clones(clones)
            shared, local = count(os.path.join(FIXTURES, 'projects'), [clones], os.path.join(FIXTURES, 'toolkit'),
                                  expected['since'], expected['until'], expected['machine'])
            inputs = inputs_line([clones, clones])
            empty = inputs_line([os.path.join(tmp, 'no-such-dir')])
    except Exception as exc:  # a crash must read as a failed test, not a traceback
        print('SELF-TEST FAIL exception: %s: %s' % (type(exc).__name__, exc))
        return 1
    bad = compare(shared, expected)
    if not set(shared) <= HEADER_KEYS | MEASURE_KEYS:
        bad.append('/merge: count() writes keys merge() does not handle: %s' % sorted(set(shared) - HEADER_KEYS - MEASURE_KEYS))
    if not set(shared['toolkit_use']) <= {'skills', 'agents'}:
        bad.append('/merge: toolkit_use has keys merge() does not handle: %s' % sorted(set(shared['toolkit_use'])))
    # compare() ignores keys the expectation lacks; these maps must hold exactly the expected keys,
    # all the way down (so "one model per spawn" is pinned too).
    for key in ('claude_code_versions', 'spawns', 'tokens_by_model', 'toolkit_use', 'hook_blocks', 'notes', 'jev'):
        bad += key_diffs(shared.get(key), expected[key], '/' + key)
    want_local = {'-home-u-git-alpha': {'spawns': {'cct:coder': 1, 'Explore': 1, 'alpha-db-expert': 1, 'unknown': 2},
                                        'tokens': 9127}}
    if local['per_project'] != want_local:
        bad.append('/per_project: got %s' % local['per_project'])
    bad += leak_probes(shared, local)
    with open(os.path.join(FIXTURES, 'projects', '-home-u-git-alpha', 'main-3.jsonl'), encoding='utf-8') as fh:
        raw = fh.read()
    for needle in ('corp.example', 'secretproject', 'acme', 'internal'):  # control: the rows the two probes are about are in the input,
        if needle not in raw:                          # and expected.json's other-model tokens count them
            bad.append('CONTROL FAILED: the fixture has no model string with %r' % needle)
    corrections, notes = local.get('corrections', []), local.get('notes', {})
    texts = [c.get('text') for c in corrections]
    if sorted(texts) != sorted(["no, don't run the gate without asking ZZ-PRIVATE-MARKER-7f3a",
                                "that's not what I asked", "no, wrong file"]):
        bad.append('/local/corrections: got %s' % texts)
    if any(set(c) != {'project', 'ts', 'text'} or c['project'] != '-home-u-git-alpha' for c in corrections):
        bad.append('/local/corrections: wrong shape %s' % corrections)
    if {k: len(v) for k, v in notes.items()} != {'beta': 4, 'gamma': 2}:
        bad.append('/local/notes: got %s' % notes)
    if len(cut_text('x' * 400)) != 300:
        bad.append('/cut_text: not cut to 300 chars')
    for value in (float('nan'), float('inf'), float('-inf'), True, '7', None, 10 ** 400, -10 ** 400, 1e300):
        if num(value) != 0:
            bad.append('/num(%r): want 0, got %s' % (value, num(value)))
    if num(7) != 7 or num(7.9) != 7:
        bad.append('/num: a finite number must pass through')
    if sorted(local.get('hook_blocks', {}).items()) != [('<unattributed>', 1), ('deny-hang-shapes', 2),
                                                        ('gate-before-merge', 3), ('other', 1), ('seal-guard', 1)]:
        bad.append('/local/hook_blocks: got %s' % local.get('hook_blocks'))
    pre = 'PreToolUse:Bash hook error: '
    fixture_hooks = os.path.join(FIXTURES, 'toolkit')
    table = refusal_table(fixture_hooks, toolkit_hooks(fixture_hooks))
    # the fixture hooks hold: a text of a hook-name token (not in the table), one no-name text of
    # gate-before-merge, and one text found in two hooks; the dispatch texts are always there
    if sorted(table) != sorted([('No gate artifact found.', 'gate-before-merge'),
                                ('Shared state file unreadable here.', OTHER),
                                ('cct plugin files are missing', 'dispatch'),
                                ('bash not found on PATH', 'dispatch')]):
        bad.append('/refusal_table: got %s' % table)
    for text, want in (
            (pre + '[command hook 4]: BLOCKED: No gate artifact found. Run the gate.', 'gate-before-merge'),
            (pre + '[command hook 4]: BLOCKED: Shared state file unreadable here.', OTHER),
            (pre + '[command hook 4]: BLOCKED: cct plugin files are missing (the plugin was upgraded).', 'dispatch'),
            (pre + '[command hook 4]: BLOCKED: bash not found on PATH', 'dispatch'),
            (pre + '[command hook 4]: BLOCKED: gate-before-merge refuses: x', 'gate-before-merge'),
            (pre + '[command hook 4]: BLOCKED: Unknown refusal text', 'unknown'),
            (pre + '[f="${P}/hooks/deny-hang-shapes.sh"; bash "$f"]: BLOCKED: No gate artifact found.', 'deny-hang-shapes')):
        if block_hook(text, True, table) != want:
            bad.append('/block_hook table (%r): want %s, got %s' % (text[-50:], want, block_hook(text, True, table)))
    for text, is_error, want in (
            (pre + '[f="${X:-.}/hooks/deny-hang-shapes.sh"; [ -f "$f" ] && bash "$f"]: BLOCKED: use', True,
             'deny-hang-shapes'),
            (pre + '[command hook 3]: BLOCKED: gate-before-merge refuses', True, 'gate-before-merge'),
            (pre + '[command hook 3]: BLOCKED: Deny-Hang-Shapes: use', True, 'deny-hang-shapes'),
            (pre + '[command hook 3]: BLOCKED: seal-guard.sh: no', True, 'seal-guard'),
            (pre + '[command hook 4]: BLOCKED: No gate artifact found.', True, 'no'),
            (pre + '[inline]: refused', True, '<unattributed>'),
            (pre + '[f="${P}/hooks/run-hook.sh"; [ -r "$f" ] || exit 2; exec "$f" deny-hang-shapes]: BLOCKED: use', True,
             'deny-hang-shapes'),
            (pre + '[bash "${P}/hooks/run-hook.sh" Gate-Before-Merge.sh]: BLOCKED: gate-before-merge refuses', True,
             'gate-before-merge'),
            (pre + '[bash "${P}/hooks/run-hook.sh"]: BLOCKED: seal-guard: no', True, 'seal-guard'),
            (pre + '[f="${P}/hooks/dispatch.sh"; exec "$f" bash]: BLOCKED: gate-before-merge refuses', True,
             'gate-before-merge'),
            (pre + '[f="${P}/hooks/dispatch.sh"; exec "$f" bash]: refused', True, '<unattributed>'),
            (pre + '[command hook 3]: BLOCKED: gate-before-merge refuses', False, None),
            (pre + '[command hook 3]: BLOCKED: gate-before-merge refuses', None, None),
            ('Error: BLOCKED: gate-before-merge refuses', True, None),
            ('PreToolUse:Bash ' + 'x' * 200 + ' hook error: [c]: BLOCKED: gate-before-merge', True, None),
            ('PreToolUse:Bash [c]: BLOCKED: gate-before-merge', True, None)):
        if block_hook(text, is_error) != want:
            bad.append('/block_hook(%r, %s): want %s, got %s' % (text[:60], is_error, want, block_hook(text, is_error)))
    known = {'.claude/rules/project.md'}
    for line, ok in (('{"date": "2026-11-15", "kind": "helped", "surface": "x-hook", "count": 2}', True),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": "x-hook"}', True),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": ".claude/rules/project.md"}', True),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": "rules/private.md", "count": 1}', False),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": ".hidden", "count": 1}', False),
                     ('{"kind": "helped", "surface": "x-hook", "count": 1}', False),
                     ('{"date": "2026-13-45", "kind": "helped", "surface": "x-hook", "count": 1}', False),
                     ('{"date": "2026-1-5", "kind": "helped", "surface": "x-hook", "count": 1}', False),
                     ('{"date": 20261115, "kind": "helped", "surface": "x-hook", "count": 1}', False),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": "x", "count": true}', False),
                     ('{"date": "2026-11-15", "kind": "helped", "surface": "x", "count": -1}', False),
                     ('{"date": "2026-11-15", "kind": "surprise", "surface": "x", "count": 1}', False),
                     ('[1, 2]', False), ('not json', False)):
        if (parse_note(line, known) is not None) != ok:
            bad.append('/parse_note(%s): want %s' % (line, 'accepted' if ok else 'rejected'))
    for model, want in (('claude-sonnet-5-5', 'claude-sonnet-5-5'),
                        ('us.anthropic.claude-opus-5-5-v1:0', 'claude-opus-5-5'),
                        ('claude-opus-4-1@20250805', 'claude-opus-4-1'),
                        ('claude-3-5-sonnet-20241022-v2:0', 'claude-3-5-sonnet-20241022'),
                        ('arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/abc', 'other-model'),
                        ('anthropic.claude-haiku-5-5-v2:1', 'claude-haiku-5-5'),
                        ('claude-fable-5', 'claude-fable-5'),
                        ('claude-gateway.corp.example.com', 'other-model'),
                        ('claude-acme-secretproject', 'other-model'),
                        ('claude-opus-5.5', 'other-model'),
                        ('claude-sonnet-acme-project', 'other-model'),
                        ('claude-opus-5-5-internal', 'other-model'),
                        ('claude-opus-5-5[1m]', 'claude-opus-5-5'),
                        ('claude-3-5-sonnet-20241022', 'claude-3-5-sonnet-20241022'),
                        ('claude-sonnet-4-5-20250929', 'claude-sonnet-4-5-20250929'),
                        ('claude-instant-1', 'claude-instant-1'),
                        ('claude-3-5-haiku-internal', 'other-model'),
                        ('claude-3-5-fable', 'other-model'),
                        ('claude-3-5', 'other-model'),
                        ('claude-opus-123456789012', 'other-model'),
                        ('claude-3-5-sonnet-123456789', 'other-model'),
                        ('claude-opus-12345678', 'claude-opus-12345678'),
                        ('claude-', 'other-model'),
                        ('gpt-x', 'other-model')):
        if norm_model(model) != want:
            bad.append('/norm_model(%r): want %s, got %s' % (model, want, norm_model(model)))
    # Control: a deliberately wrong expected share must be reported, or the comparison is vacuous.
    wrong = json.loads(json.dumps(expected))
    wrong['token_share']['sub_share'] = round(wrong['token_share']['sub_share'] - 0.05, 4)
    if not compare(shared, wrong):
        bad.append('CONTROL FAILED: a wrong expected sub_share compared equal')
    if inputs != 'clone roots: 1, notes files: 2, Jev event files: 4':
        bad.append('/inputs_line: got %r' % inputs)
    if empty != 'clone roots: 1, notes files: 0, Jev event files: 0':  # the silent-zero case reads as zeros
        bad.append('/inputs_line: a root with no clones: got %r' % empty)
    bad += machine_checks()
    bad += merge_checks()
    for line in bad:
        print('SELF-TEST FAIL ' + line)
    if bad:
        return 1
    print('SELF-TEST PASS: sub_share %s, %d spawn types; control fires' % (shared['token_share']['sub_share'],
                                                                         len(shared['spawns'])))
    return 0


def write_json(path, obj):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as fh:
        fh.write(json.dumps(obj, indent=2, sort_keys=True) + '\n')


def main(argv):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(newline='\n')
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--since', help='YYYY-MM-DD, inclusive; default 30 days ago')
    ap.add_argument('--until', help='YYYY-MM-DD, inclusive; default no upper bound')
    ap.add_argument('--root', help='transcript directory; default $CLAUDE_CONFIG_DIR/projects, else ~/.claude/projects')
    ap.add_argument('--clone-root', action='append', help='directory of repository clones; repeatable; '
                    'default the parent directory of the toolkit checkout; if this checkout is a git worktree, '
                    'pass the directory that holds your clones')
    ap.add_argument('--toolkit', default=os.path.dirname(HERE), help='toolkit checkout; default this script\'s repository')
    ap.add_argument('--machine', help='label for this machine; default <os>-<6 random hex>, made once and kept '
                    'in ~/.cache/cct-self-review/machine-id')
    ap.add_argument('--out', help='shared JSON; default ~/.cache/cct-self-review/<machine>-<today>.json')
    ap.add_argument('--merge', metavar='DIR', help='merge the shared JSONs in DIR (not *.local.json) into one '
                    'table on stdout; needs no transcripts')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    if a.merge is not None:
        merge_dir = os.path.expanduser(a.merge)
        if not os.path.isdir(merge_dir):
            print('self-review-count: no directory at %s' % merge_dir, file=sys.stderr)
            return 2
        sys.stdout.write(merge(inbox_paths(merge_dir)))
        return 0
    since = a.since or (date.today() - timedelta(days=30)).isoformat()
    for flag, value in (('--since', since), ('--until', a.until)):
        if value is not None and not DATE_RE.match(value):
            ap.error('%s wants YYYY-MM-DD' % flag)
    config = os.environ.get('CLAUDE_CONFIG_DIR')
    root = os.path.expanduser(a.root) if a.root else os.path.join(
        config or os.path.join(os.path.expanduser('~'), '.claude'), 'projects')
    toolkit = os.path.abspath(a.toolkit)
    clone_roots = [os.path.expanduser(r) for r in a.clone_root] if a.clone_root else [os.path.dirname(toolkit)]
    exchange = os.path.join(os.path.expanduser('~'), '.cache', 'cct-self-review')
    machine = a.machine or default_machine(platform.system(), os.path.join(exchange, 'machine-id'))
    out = os.path.expanduser(a.out) if a.out else os.path.join(exchange, '%s-%s.json' % (machine, date.today().isoformat()))
    if not os.path.isdir(root):
        print('self-review-count: no transcript directory at %s' % root, file=sys.stderr)
        return 2
    shared, local = count(root, clone_roots, toolkit, since, a.until, machine)
    local_out = (out[:-len('.json')] if out.endswith('.json') else out) + '.local.json'
    write_json(out, shared)
    write_json(local_out, local)
    print('wrote %s and %s' % (out, local_out))
    print(inputs_line(clone_roots))
    print('Next: in a Claude session on this machine, ask it to group the "corrections" in %s into '
          'generic agent-behaviour kinds, no project, repo, path or person names, no quoted words, and add '
          '"correction_kinds": [{"kind": ..., "count": ...}] to %s; then copy %s into ~/.cache/cct-self-review/ '
          'on the machine that runs /self-review.' % (local_out, out, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
