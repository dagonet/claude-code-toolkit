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
import os
import platform
import re
import socket
import sys
from datetime import date, timedelta, timezone

sys.dont_write_bytecode = True

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.path.join(HERE, 'fixtures', 'self-review')
SCHEMA = 1
TOKEN_FIELDS = (('input', 'input_tokens'), ('cache_read', 'cache_read_input_tokens'),
                ('output', 'output_tokens'))
AGENT_TOOLS = {'Agent', 'Task'}
SYNTHETIC = '<synthetic>'
DATE_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')


def _load_measure_process():
    spec = importlib.util.spec_from_file_location('measure_process', os.path.join(HERE, 'measure-process.py'))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_MP = _load_measure_process()
load_rows, parse_ts, compare = _MP.load_rows, _MP.parse_ts, _MP.compare


def default_machine(hostname, system):
    """A label that tells machines apart without naming the host."""
    return '%s-%s' % (system.lower(), hashlib.sha256(hostname.encode('utf-8')).hexdigest()[:6])


def strip_prefix(name):
    return name[len('cct:'):] if name.startswith('cct:') else name


def toolkit_names(toolkit_root):
    """-> (skill names, agent names) the toolkit ships, from its skills/ dirs and agents/*.md."""
    skills_dir, agents_dir = os.path.join(toolkit_root, 'skills'), os.path.join(toolkit_root, 'agents')
    skills = agents = []
    if os.path.isdir(skills_dir):
        skills = [n for n in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, n))]
    if os.path.isdir(agents_dir):
        agents = [n[:-len('.md')] for n in os.listdir(agents_dir) if n.endswith('.md')]
    return sorted(skills), sorted(agents)


def scan(rows, since, until):
    """Reduce one transcript to what counts inside the window.

    -> dict: rows (in window), versions {v: n}, usage {message id: (model, {field: n})},
    calls [(tool name, input)], first_model (first non-synthetic model) or None.
    A message split over several rows repeats its usage, so usage is kept once per message id.
    """
    out = {'rows': 0, 'versions': {}, 'usage': {}, 'calls': [], 'first_model': None}
    for i, row in enumerate(rows):
        t = parse_ts(row)
        if t is None:
            continue
        if t.tzinfo is not None:
            t = t.astimezone(timezone.utc)
        day = t.date().isoformat()
        if day < since or (until and day > until):
            continue
        out['rows'] += 1
        version = row.get('version')
        if isinstance(version, str):
            out['versions'][version] = out['versions'].get(version, 0) + 1
        msg = row.get('message')
        if not isinstance(msg, dict) or row.get('type') != 'assistant':
            continue
        model = msg.get('model') if isinstance(msg.get('model'), str) else None
        if model == SYNTHETIC:
            model = None
        if model and out['first_model'] is None:
            out['first_model'] = model
        usage = msg.get('usage')
        if isinstance(usage, dict):
            mid = msg.get('id') or 'row%d' % i
            old_model, old = out['usage'].get(mid, (None, {}))
            merged = {f: max(old.get(f, 0), int(usage.get(src) or 0)) for f, src in TOKEN_FIELDS}
            out['usage'][mid] = (old_model or model, merged)
        content = msg.get('content')
        for block in content if isinstance(content, list) else []:
            if isinstance(block, dict) and block.get('type') == 'tool_use' and isinstance(block.get('input'), dict):
                out['calls'].append((block.get('name'), block['input']))
    return out


def agent_type_of(sub_path):
    """The subagent's type from its .meta.json, cct: prefix stripped; 'unknown' when absent or unreadable."""
    try:
        with open(sub_path[:-len('.jsonl')] + '.meta.json', encoding='utf-8') as fh:
            name = json.load(fh).get('agentType')
    except (OSError, ValueError, AttributeError):
        return 'unknown'
    return strip_prefix(name) if isinstance(name, str) and name else 'unknown'


def _zero():
    return {f: 0 for f, _ in TOKEN_FIELDS}


def count(projects_root, clone_roots, toolkit_root, since, until, machine):
    """Count one machine's transcripts in [since, until]. -> (shared, local).

    clone_roots is accepted for the measures later tasks add (Jev events, project notes);
    nothing here reads it.
    """
    skill_names, agent_names = toolkit_names(toolkit_root)
    use = {'skills': {n: 0 for n in skill_names}, 'agents': {n: 0 for n in agent_names}}
    versions, spawns, by_model, per_project = {}, {}, {}, {}
    share = {'main': _zero(), 'sub': _zero()}
    unreadable = 0
    for slug in sorted(os.listdir(projects_root)):
        pdir = os.path.join(projects_root, slug)
        if not os.path.isdir(pdir):
            continue
        local = per_project[slug] = {'spawns': 0, 'tokens': 0}
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
            for name, inp in s['calls']:
                if name == 'Skill':
                    called, names = inp.get('skill'), use['skills']
                elif name in AGENT_TOOLS:
                    called, names = inp.get('subagent_type'), use['agents']
                else:
                    continue
                if isinstance(called, str) and strip_prefix(called) in names:
                    names[strip_prefix(called)] += 1
            if is_sub and s['rows']:
                model = s['first_model'] or 'unknown'
                by_type = spawns.setdefault(agent_type_of(path), {})
                by_type[model] = by_type.get(model, 0) + 1
                local['spawns'] += 1
    main_total, sub_total = sum(share['main'].values()), sum(share['sub'].values())
    share['sub_share'] = round(sub_total / (main_total + sub_total), 4) if main_total + sub_total else 0.0
    shared = {'schema': SCHEMA, 'machine': machine, 'since': since, 'until': until,
              'claude_code_versions': versions, 'spawns': spawns, 'tokens_by_model': by_model,
              'token_share': share, 'toolkit_use': use, 'unreadable_files': unreadable}
    return shared, {'per_project': per_project}


def self_test():
    with open(os.path.join(FIXTURES, 'expected.json'), encoding='utf-8') as fh:
        expected = json.load(fh)
    shared, local = count(os.path.join(FIXTURES, 'projects'), [], os.path.join(FIXTURES, 'toolkit'),
                          expected['since'], expected['until'], expected['machine'])
    bad = compare(shared, expected)
    # compare() ignores keys the expectation lacks; these maps must hold exactly the expected keys.
    for path in (('claude_code_versions',), ('spawns',), ('tokens_by_model',),
                 ('toolkit_use', 'skills'), ('toolkit_use', 'agents')):
        got, want = shared, expected
        for k in path:
            got, want = got[k], want[k]
        if sorted(got) != sorted(want):
            bad.append('/%s: keys want %s, got %s' % ('/'.join(path), sorted(want), sorted(got)))
    if local['per_project'] != {'-home-u-git-alpha': {'spawns': 2, 'tokens': 8769}}:
        bad.append('/per_project: got %s' % local['per_project'])
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
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
