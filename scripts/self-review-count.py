#!/usr/bin/env python3
"""self-review-count.py -- counts for the toolkit self-review report (stage 1).

Read-only over Claude Code JSONL transcripts, stdlib only, never shipped to consumers.
It never calls a model or the network. The shared JSON holds counts only: no
conversation text, no path below the clone root, no project name, no env value.
Per-project detail goes to a sibling <out>.local.json that stays on the machine.

  python3 scripts/self-review-count.py [--since YYYY-MM-DD] [--until YYYY-MM-DD]
         [--root DIR] [--clone-root DIR ...] [--toolkit DIR] [--machine LABEL] [--out FILE]
  python3 scripts/self-review-count.py --self-test
"""
import argparse
import glob
import hashlib
import importlib.util
import json
import math
import os
import platform
import re
import shutil
import socket
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
BLOCK_RE = re.compile(r'BLOCKED: ([a-z0-9][a-z0-9-]*)')
CORRECTION_RE = re.compile(
    r"^(no\b|nope\b|don['’]?t\b|do not\b|stop\b|wrong\b|that['’]?s (not|wrong)\b|not what\b|i said\b"
    r"|i told you\b|why did you\b|you (forgot|missed|didn['’]?t)\b)", re.IGNORECASE)
CORRECTION_CHARS = 300
NOTE_KINDS = ('helped', 'recurring_failure', 'rule_unused')
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


def default_machine(hostname, system):
    """A label that tells machines apart without naming the host."""
    return '%s-%s' % (system.lower(), hashlib.sha256(hostname.encode('utf-8')).hexdigest()[:6])


def toolkit_name(called, names):
    """The bare toolkit name behind a call, or None. Only `cct:<name>` is the toolkit's: a bare name
    may be a Claude Code built-in (Explore) or another plugin's."""
    if isinstance(called, str) and called.startswith(PLUGIN_PREFIX) and called[len(PLUGIN_PREFIX):] in names:
        return called[len(PLUGIN_PREFIX):]
    return None


def num(value):
    """A usage field as an int; anything non-numeric (or NaN or infinite) counts as 0."""
    ok = isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)
    return int(value) if ok else 0


def norm_model(model):
    """A model string that is safe to share: the `claude-...` name without a `-v<n>` suffix, else
    'other-model'. A cloud provider's model id can be an ARN that carries an account id."""
    hit = MODEL_RE.search(model)
    return re.sub(r'-v\d+$', '', hit.group()) if hit else 'other-model'


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
    """-> (typed text or None, [tool result texts]) of a user message. A message holding any tool
    result is not typed by the user."""
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
        results.append(inner if isinstance(inner, str) else '')
    if results:
        return None, results
    texts = [b['text'] for b in blocks if b.get('type') == 'text' and isinstance(b.get('text'), str)]
    return ('\n'.join(texts) if texts else None), []


def correction_text(typed):
    """The stripped text when a typed user turn reads as a correction, else None."""
    text = (typed or '').strip()
    return text if text and not text.startswith('<') and CORRECTION_RE.match(text) else None


def scan(rows, since, until):
    """Reduce one transcript to what counts inside the window.

    -> dict: first_day (of the first timestamped row, in or out of the window), first_model (first
    non-synthetic model in the whole transcript) or None, and, for in-window rows only:
    versions {v: n}, usage {message id: (model, {field: n})}, calls [(tool name, input)],
    blocks [hook name of each tool result that holds `BLOCKED: <hook>`],
    corrections [(timestamp, text) of each typed user turn that reads as a correction].
    A message split over several rows repeats its usage, so usage is kept once per message id.
    """
    out = {'first_day': None, 'first_model': None, 'versions': {}, 'usage': {}, 'calls': [],
           'blocks': [], 'corrections': []}
    for i, row in enumerate(rows):
        msg = row.get('message')
        model = None
        if isinstance(msg, dict) and row.get('type') == 'assistant':
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
            for text in results:
                hit = BLOCK_RE.search(text)
                if hit:
                    out['blocks'].append(hit.group(1))
            text = None if row.get('isMeta') else correction_text(typed)
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


def parse_note(line):
    """One improvement-notes line -> the note dict, or None when it is not a valid note: a JSON
    object with a known kind, a surface that is a plain name (not a path) and a count that is a
    whole number >= 0 (default 1)."""
    try:
        note = json.loads(line)
    except ValueError:
        return None
    if not isinstance(note, dict) or note.get('kind') not in NOTE_KINDS:
        return None
    surface, n = note.get('surface'), note.get('count', 1)
    if not isinstance(surface, str) or not SURFACE_RE.fullmatch(surface):
        return None
    if isinstance(n, bool) or not isinstance(n, int) or n < 0:
        return None
    return note


def read_notes(clone_roots):
    """Read <root>/*/.claude/improvement-notes.jsonl under every clone root.

    -> (shared notes {kind: {surface: {count, projects}}}, local notes {project: [note]}, malformed
    lines, unreadable files). `projects` is how many distinct projects hold the surface; none is named.
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
                note = parse_note(ln)
                if note is None:
                    malformed += 1
                    continue
                local.setdefault(os.path.basename(project_dir), []).append(note)
                slot = seen.setdefault(note['kind'], {}).setdefault(note['surface'], {'count': 0, 'projects': set()})
                slot['count'] += note.get('count', 1)
                slot['projects'].add(project_dir)
    shared = {kind: {s: {'count': v['count'], 'projects': len(v['projects'])} for s, v in by_surface.items()}
              for kind, by_surface in seen.items()}
    return shared, local, malformed, unreadable


def jev_counts(clone_roots, since, until):
    """Jev router events in the window across the clone roots -> {events, applied, up, down}.
    up/down count applied events whose emitted model ranks above/below the default, as jev-tally does."""
    events, _ = _JT._load_events(clone_roots, since)
    events = [e for e in events if not until or e['ts'][:10] <= until]
    applied = [e for e in events if e.get('applied') is True]
    rank = _JT._rank
    return {'events': len(events), 'applied': len(applied),
            'up': sum(rank(e.get('emitted')) > rank(e.get('default')) for e in applied),
            'down': sum(rank(e.get('emitted')) < rank(e.get('default')) for e in applied)}


def count(projects_root, clone_roots, toolkit_root, since, until, machine):
    """Count one machine's transcripts in [since, until], plus the notes and Jev events under the
    clone roots. -> (shared, local)."""
    skill_names, agent_names = toolkit_names(toolkit_root)
    use = {'skills': {n: 0 for n in skill_names}, 'agents': {n: 0 for n in agent_names}}
    versions, spawns, by_model, per_project = {}, {}, {}, {}
    share = {'main': _zero(), 'sub': _zero()}
    hook_blocks, corrections = {}, []
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
            s = scan(rows, since, until)
            for v, n in s['versions'].items():
                versions[v] = versions.get(v, 0) + n
            for model, tok in s['usage'].values():
                for f, _ in TOKEN_FIELDS:
                    share['sub' if is_sub else 'main'][f] += tok[f]
                    local['tokens'] += tok[f]
                    if model:
                        by_model.setdefault(model, _zero())[f] += tok[f]
            for hook in s['blocks']:
                hook_blocks[hook] = hook_blocks.get(hook, 0) + 1
            if not is_sub:  # a subagent's user rows are its parent's prompts, not the user's words
                corrections += [{'project': slug, 'ts': ts, 'text': cut_text(text)} for ts, text in s['corrections']]
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
    notes, local_notes, notes_malformed, notes_unreadable = read_notes(clone_roots)
    shared = {'schema': SCHEMA, 'machine': machine, 'since': since, 'until': until,
              'claude_code_versions': versions, 'spawns': spawns, 'tokens_by_model': by_model,
              'token_share': share, 'toolkit_use': use, 'hook_blocks': hook_blocks,
              'correction_candidates': len(corrections), 'notes': notes, 'notes_malformed': notes_malformed,
              'jev': jev_counts(clone_roots, since, until), 'unreadable_files': unreadable + notes_unreadable}
    return shared, {'per_project': per_project, 'corrections': corrections, 'notes': local_notes}


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
            ('alpha', 'the project name', True),
            ('beta', 'a clone (project) name', True),
            ('gamma', 'a clone (project) name', True),
            ('123456789012', 'an account id from a model string', False)):
        if needle in flat_shared:
            bad.append('/shared: %s leaked (%r)' % (what, needle))
        if in_local and needle not in flat_local:
            bad.append('CONTROL FAILED: %s (%r) is not in the local file' % (what, needle))
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
    except Exception as exc:  # a crash must read as a failed test, not a traceback
        print('SELF-TEST FAIL exception: %s: %s' % (type(exc).__name__, exc))
        return 1
    bad = compare(shared, expected)
    # compare() ignores keys the expectation lacks; these maps must hold exactly the expected keys,
    # all the way down (so "one model per spawn" is pinned too).
    for key in ('claude_code_versions', 'spawns', 'tokens_by_model', 'toolkit_use', 'hook_blocks', 'notes', 'jev'):
        bad += key_diffs(shared.get(key), expected[key], '/' + key)
    want_local = {'-home-u-git-alpha': {'spawns': {'cct:coder': 1, 'Explore': 1, 'alpha-db-expert': 1, 'unknown': 2},
                                        'tokens': 9055}}
    if local['per_project'] != want_local:
        bad.append('/per_project: got %s' % local['per_project'])
    bad += leak_probes(shared, local)
    texts = [c['text'] for c in local['corrections']]
    if sorted(texts) != sorted(["no, don't run the gate without asking ZZ-PRIVATE-MARKER-7f3a",
                                "that's not what I asked"]):
        bad.append('/local/corrections: got %s' % texts)
    if any(set(c) != {'project', 'ts', 'text'} or c['project'] != '-home-u-git-alpha' for c in local['corrections']):
        bad.append('/local/corrections: wrong shape %s' % local['corrections'])
    if sorted(local['notes']) != ['beta', 'gamma'] or [len(v) for _, v in sorted(local['notes'].items())] != [2, 1]:
        bad.append('/local/notes: got %s' % local['notes'])
    if len(cut_text('x' * 400)) != 300:
        bad.append('/cut_text: not cut to 300 chars')
    for value in (float('nan'), float('inf'), float('-inf'), True, '7', None):
        if num(value) != 0:
            bad.append('/num(%r): want 0, got %s' % (value, num(value)))
    if num(7) != 7 or num(7.9) != 7:
        bad.append('/num: a finite number must pass through')
    for line, ok in (('{"kind": "helped", "surface": "x-hook", "count": 2}', True),
                     ('{"kind": "helped", "surface": "x-hook"}', True),
                     ('{"kind": "helped", "surface": "rules/private.md", "count": 1}', False),
                     ('{"kind": "helped", "surface": "x", "count": true}', False),
                     ('{"kind": "helped", "surface": "x", "count": -1}', False),
                     ('{"kind": "surprise", "surface": "x", "count": 1}', False),
                     ('[1, 2]', False), ('not json', False)):
        if (parse_note(line) is not None) != ok:
            bad.append('/parse_note(%s): want %s' % (line, 'accepted' if ok else 'rejected'))
    for model, want in (('claude-sonnet-5-5', 'claude-sonnet-5-5'),
                        ('us.anthropic.claude-opus-5-5-v1:0', 'claude-opus-5-5'),
                        ('claude-opus-4-1@20250805', 'claude-opus-4-1'),
                        ('claude-3-5-sonnet-20241022-v2:0', 'claude-3-5-sonnet-20241022'),
                        ('arn:aws:bedrock:us-east-1:123456789012:application-inference-profile/abc', 'other-model'),
                        ('gpt-x', 'other-model')):
        if norm_model(model) != want:
            bad.append('/norm_model(%r): want %s, got %s' % (model, want, norm_model(model)))
    # Control: a deliberately wrong expected share must be reported, or the comparison is vacuous.
    wrong = json.loads(json.dumps(expected))
    wrong['token_share']['sub_share'] = round(wrong['token_share']['sub_share'] - 0.05, 4)
    if not compare(shared, wrong):
        bad.append('CONTROL FAILED: a wrong expected sub_share compared equal')
    label = default_machine('host-a', 'Linux')
    if not re.match(r'^linux-[0-9a-f]{6}$', label):
        bad.append('/default_machine: %r does not match linux-<6 hex>' % label)
    if 'host-a' in label:
        bad.append('/default_machine: label contains the hostname')
    if label == default_machine('host-b', 'Linux'):
        bad.append('/default_machine: two hostnames gave one label')
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
                    'default the parent directory of the toolkit checkout')
    ap.add_argument('--toolkit', default=os.path.dirname(HERE), help='toolkit checkout; default this script\'s repository')
    ap.add_argument('--machine', help='label for this machine; default <os>-<6 hex of sha256(hostname)>')
    ap.add_argument('--out', help='shared JSON; default ~/.cache/cct-self-review/<machine>-<today>.json')
    ap.add_argument('--self-test', action='store_true')
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    since = a.since or (date.today() - timedelta(days=30)).isoformat()
    for flag, value in (('--since', since), ('--until', a.until)):
        if value is not None and not DATE_RE.match(value):
            ap.error('%s wants YYYY-MM-DD' % flag)
    config = os.environ.get('CLAUDE_CONFIG_DIR')
    root = a.root or os.path.join(config or os.path.join(os.path.expanduser('~'), '.claude'), 'projects')
    toolkit = os.path.abspath(a.toolkit)
    clone_roots = a.clone_root or [os.path.dirname(toolkit)]
    machine = a.machine or default_machine(socket.gethostname(), platform.system())
    out = a.out or os.path.join(os.path.expanduser('~'), '.cache', 'cct-self-review',
                                '%s-%s.json' % (machine, date.today().isoformat()))
    if not os.path.isdir(root):
        print('self-review-count: no transcript directory at %s' % root, file=sys.stderr)
        return 2
    shared, local = count(root, clone_roots, toolkit, since, a.until, machine)
    local_out = (out[:-len('.json')] if out.endswith('.json') else out) + '.local.json'
    write_json(out, shared)
    write_json(local_out, local)
    print('wrote %s and %s' % (out, local_out))
    print('Next: in a Claude session on this machine, ask it to group the "corrections" in %s into '
          'agent-behaviour kinds and add "correction_kinds": [{"kind": ..., "count": ...}] to %s; then copy %s '
          'to the inbox of the machine that runs /self-review.' % (local_out, out, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
