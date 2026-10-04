#!/usr/bin/env python3
"""measure-process.py -- process vs progress in Claude Code transcripts (v4.5 Part F).

Read-only, stdlib only, never shipped to consumers. Every tool call -- and every
text-only assistant turn, and a subagent's spawn prompt -- goes to exactly one
bucket (first matching rule wins, spec F2). Per bucket it reports:
  load  -- context load: result bytes x the assistant turns that still carry
           them; shown in tokens (/4). Cache reads dominate cost, so a byte in
           context is paid on every later turn.
  out   -- usage.output_tokens of the issuing turn, split over its tool calls.
  wall  -- tool_result timestamp minus tool_use timestamp.
The headline is process / (process + progress) for each measure.

A Skill call's text is NOT in its tool_result ("Launching skill: X"); it arrives
as a separate isMeta user row whose sourceToolUseID names the call (measured
2026-10-03). Both are counted for the call.

Run on an idle machine, never beside a gate.
  python3 scripts/measure-process.py --project <slug>[,<slug>...] [--since D] [--until D] [--json]
  python3 scripts/measure-process.py --all [...]
  python3 scripts/measure-process.py --self-test
"""
import argparse
import bisect
import glob
import json
import os
import re
import statistics
import sys
from datetime import datetime

sys.dont_write_bytecode = True

PROCESS = ('process:review', 'process:test', 'process:rules', 'process:prod',
           'process:report', 'process:gate', 'process:wait')
PROGRESS = ('progress:commit', 'progress:edit', 'progress:deliver')
NEUTRAL = ('neutral:orient', 'neutral:spawn')
BUCKETS = PROCESS + PROGRESS + NEUTRAL + ('unclassified',)

GATE_RE = re.compile(r'run-gate\.sh|\b(pytest|dotnet (test|build)|npm (run )?test|cargo (test|build)'
                     r'|mvn|gradle|go test|jest|vitest)\b|scripts/(test|verify)-')
COMMIT_RE = re.compile(r'(^|[;&|(\s])git(\s+-C\s+\S+)?\s+commit\b')
DELIVER_RE = re.compile(r'(^|[;&|(\s])git(\s+-C\s+\S+)?\s+(push|rebase|pull|merge)\b')
SLEEP_ONLY_RE = re.compile(r'^\s*sleep\s+[0-9.]+[smhd]?\s*$')
DELIVER_MCP_RE = re.compile(r'__(create_pull_request|merge_pull_request|update_pull_request)$')
KEY_RE = re.compile(r'^[-*\s]*\*\*(Test|Gate|Gate extra|Build)( Command)?\*\*:\s*`?([^`]*?)`?\s*$')
EDIT_TOOLS = {'Edit', 'Write', 'MultiEdit', 'NotebookEdit'}
WAIT_TOOLS = {'Monitor', 'TaskOutput', 'BashOutput', 'TaskStop'}
ORIENT_TOOLS = {'Read', 'Grep', 'Glob', 'WebFetch', 'WebSearch', 'ToolSearch', 'Bash', 'PowerShell'}
SHELL_TOOLS = {'Bash', 'PowerShell'}
REVIEW_TYPES = {'code-reviewer', 'architect'}
FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'fixtures', 'measure-process')


def is_coder(agent_type):
    return agent_type == 'coder' or agent_type.endswith('-coder')


def nbytes(s):
    return len(s.encode('utf-8'))


def text_of(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return ''.join(text_of(b.get('content', b.get('text', ''))) if isinstance(b, dict) else ''
                       for b in content)
    return ''


def parse_ts(row):
    t = row.get('timestamp')
    if not isinstance(t, str):
        return None
    try:
        return datetime.fromisoformat(t.replace('Z', '+00:00'))
    except ValueError:
        return None


def load_rows(path):
    rows = []
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if isinstance(r, dict):
                rows.append(r)
    return rows


_declared_cache = {}


def declared_commands(cwd):
    """The project's **Test**/**Gate**/**Gate extra**/**Build** values, from <cwd>/PROJECT_CONTEXT.md."""
    if not cwd:
        return []
    if cwd not in _declared_cache:
        cmds = []
        try:
            with open(os.path.join(cwd, 'PROJECT_CONTEXT.md'), encoding='utf-8', errors='replace') as fh:
                for line in fh:
                    m = KEY_RE.match(line.rstrip('\r\n'))
                    if m and m.group(3).strip() and '{{' not in m.group(3):
                        cmds.append(m.group(3).strip())
        except OSError:
            pass
        _declared_cache[cwd] = cmds
    return _declared_cache[cwd]


def call_bucket(name, inp, agent_type, is_sub, after_prod, declared):
    if is_sub and agent_type in REVIEW_TYPES:
        return 'process:review'
    if is_sub and agent_type == 'tester':
        return 'process:test'
    if name == 'Skill':
        return 'process:rules'
    if after_prod:
        return 'process:prod'
    if is_sub and name == 'SubagentHandback':
        return 'process:report'
    cmd = inp.get('command', '') if name in SHELL_TOOLS and isinstance(inp.get('command'), str) else ''
    if cmd and (GATE_RE.search(cmd) or any(d in cmd for d in declared)):
        return 'process:gate'
    if name in WAIT_TOOLS or (name == 'Bash' and SLEEP_ONLY_RE.match(cmd)):
        return 'process:wait'
    if cmd and COMMIT_RE.search(cmd):
        return 'progress:commit'
    if name in EDIT_TOOLS:
        return 'progress:edit'
    if (cmd and DELIVER_RE.search(cmd)) or DELIVER_MCP_RE.search(name):
        return 'progress:deliver'
    if name in ORIENT_TOOLS:
        return 'neutral:orient'
    if name in ('Agent', 'Task') and not is_sub:
        return 'neutral:spawn'
    return 'unclassified'


def text_bucket(agent_type, is_sub, after_prod, is_final):
    if is_sub and agent_type in REVIEW_TYPES:
        return 'process:review'
    if is_sub and agent_type == 'tester':
        return 'process:test'
    if after_prod:
        return 'process:prod'
    if is_sub and is_final:
        return 'process:report'
    return 'neutral:orient'


def analyse(rows, agent_type, is_sub):
    """One transcript -> dict(events=[...], prompt=str, skills=[(name, bytes)], final=str, prodded=bool, span=s)."""
    turn_start, turn_out, turn_calls, turn_text = {}, {}, {}, {}
    order = []
    calls = []
    for i, r in enumerate(rows):
        m = r.get('message')
        if r.get('type') != 'assistant' or not isinstance(m, dict):
            continue
        mid = m.get('id') or ('row%d' % i)
        if mid not in turn_start:
            turn_start[mid] = i
            order.append(mid)
        turn_out[mid] = max(turn_out.get(mid, 0), (m.get('usage') or {}).get('output_tokens') or 0)
        c = m.get('content')
        blocks = [{'type': 'text', 'text': c}] if isinstance(c, str) else [b for b in (c or []) if isinstance(b, dict)]
        for b in blocks:
            if b.get('type') == 'tool_use':
                calls.append((i, mid, b))
                turn_calls[mid] = turn_calls.get(mid, 0) + 1
            elif b.get('type') == 'text' and str(b.get('text', '')).strip():
                turn_text[mid] = turn_text.get(mid, '') + str(b['text'])
    starts = sorted(turn_start.values())

    def later(idx):
        return len(starts) - bisect.bisect_right(starts, idx)

    results, extra = {}, {}
    prompt, prompt_idx, prod_idx, cwd = None, None, None, None
    for i, r in enumerate(rows):
        cwd = cwd or r.get('cwd')
        m = r.get('message')
        if r.get('type') != 'user' or not isinstance(m, dict):
            continue
        c = m.get('content')
        src = r.get('sourceToolUseID')
        if src:
            extra[src] = extra.get(src, 0) + nbytes(text_of(c))
            continue
        if isinstance(c, list) and any(isinstance(b, dict) and b.get('type') == 'tool_result' for b in c):
            for b in c:
                if isinstance(b, dict) and b.get('type') == 'tool_result':
                    results[b.get('tool_use_id')] = (i, nbytes(text_of(b.get('content'))), parse_ts(r))
            continue
        t = text_of(c)
        if prompt is None and not r.get('isMeta'):
            prompt, prompt_idx = t, i
        if prod_idx is None and t.startswith('Stop hook feedback') and 'CONTRACT VIOLATION' in t:
            prod_idx = i
    declared = declared_commands(cwd)

    events = []
    if is_sub and prompt is not None:
        b = 'process:rules' if re.search(r'^## Required Skills\s*$', prompt, re.M) else 'neutral:spawn'
        events.append({'bucket': b, 'wall_bucket': b, 'tool': '(spawn prompt)',
                       'load': nbytes(prompt) * later(prompt_idx), 'out': 0.0, 'wall': 0.0})
    skills, handback = [], None
    for i, mid, b in calls:
        name = str(b.get('name', ''))
        inp = b.get('input') if isinstance(b.get('input'), dict) else {}
        res = results.get(b.get('id'))
        size = (res[1] if res else 0) + extra.get(b.get('id'), 0)
        load = size * later(res[0] if res else i)
        t0 = parse_ts(rows[i])
        wall = (res[2] - t0).total_seconds() if res and res[2] and t0 else 0.0
        bucket = call_bucket(name, inp, agent_type, is_sub, prod_idx is not None and i > prod_idx, declared)
        wall_bucket = 'process:gate' if bucket == 'progress:commit' and wall > 10 else bucket
        events.append({'bucket': bucket, 'wall_bucket': wall_bucket, 'tool': name, 'load': load,
                       'out': turn_out[mid] / turn_calls[mid], 'wall': wall})
        if name == 'Skill':
            skills.append((str(inp.get('skill', '')), size))
        if name == 'SubagentHandback':
            handback = str(inp.get('message', ''))
    final = ''
    for mid in order:
        if turn_calls.get(mid) or mid not in turn_text:
            continue
        is_final = mid == order[-1]
        if is_final:
            final = turn_text[mid]
        bucket = text_bucket(agent_type, is_sub, prod_idx is not None and turn_start[mid] > prod_idx, is_final)
        events.append({'bucket': bucket, 'wall_bucket': bucket, 'tool': '(text)', 'load': 0,
                       'out': float(turn_out[mid]), 'wall': 0.0})
    stamps = [t for t in (parse_ts(r) for r in rows) if t]
    span = (max(stamps) - min(stamps)).total_seconds() if stamps else 0.0
    return {'events': events, 'prompt': prompt or '', 'skills': skills,
            'final': handback if handback is not None else final,
            'prodded': prod_idx is not None, 'span': span}


def project_dirs(root, slugs, all_projects):
    names = sorted(n for n in os.listdir(root) if os.path.isdir(os.path.join(root, n)))
    if all_projects:
        return [os.path.join(root, n) for n in names]
    keep = []
    for s in slugs:
        repo = s.split('--git-', 1)[1] if '--git-' in s else None
        for n in names:
            if n == s or n.startswith(s + '--') or (repo and ('--worktrees-' + repo + '-') in n):
                keep.append(os.path.join(root, n))
    return sorted(set(keep))


def first_date(rows):
    for r in rows:
        t = parse_ts(r)
        if t:
            return t.date().isoformat()
    return None


def collect(root, slugs, all_projects, since, until):
    runs = {'main': [], 'sub': []}
    for d in project_dirs(root, slugs, all_projects):
        paths = [(p, False) for p in glob.glob(os.path.join(d, '*.jsonl'))]
        paths += [(p, True) for p in glob.glob(os.path.join(d, '*', 'subagents', 'agent-*.jsonl'))]
        for path, is_sub in sorted(paths):
            rows = load_rows(path)
            day = first_date(rows)
            if day is None or (since and day < since) or (until and day > until):
                continue
            agent_type = ''
            if is_sub:
                try:
                    with open(path[:-len('.jsonl')] + '.meta.json', encoding='utf-8') as fh:
                        agent_type = str(json.load(fh).get('agentType', ''))
                except (OSError, ValueError):
                    agent_type = ''
            a = analyse(rows, agent_type, is_sub)
            a['agent_type'] = agent_type
            runs['sub' if is_sub else 'main'].append(a)
    return runs


def share(totals, measure):
    p = sum(totals[b][measure] for b in PROCESS)
    g = sum(totals[b][measure] for b in PROGRESS)
    return round(p / (p + g), 4) if p + g else None


def summarise(analyses):
    totals = {b: {'events': 0, 'load': 0, 'out': 0.0, 'wall': 0.0} for b in BUCKETS}
    unclassified, tool_wall, span = {}, 0.0, 0.0
    for a in analyses:
        span += a['span']
        for e in a['events']:
            t = totals[e['bucket']]
            t['events'] += 1
            t['load'] += e['load']
            t['out'] += e['out']
            totals[e['wall_bucket']]['wall'] += e['wall']
            tool_wall += e['wall']
            if e['bucket'] == 'unclassified':
                unclassified[e['tool']] = unclassified.get(e['tool'], 0) + 1
    top = sorted(unclassified.items(), key=lambda kv: (-kv[1], kv[0]))[:10]
    return {'runs': len(analyses), 'totals': totals,
            'share': {m: share(totals, m) for m in ('load', 'out', 'wall')},
            'model_wall': round(span - tool_wall, 1), 'unclassified_top': [list(x) for x in top]}


def tier_of(prompt):
    tiers = set(re.findall(r'\bT([1-4])\b', prompt))
    return 'T' + tiers.pop() if len(tiers) == 1 else 'unknown'


def extra_tables(subs):
    spawn = {}
    for a in subs:
        s = spawn.setdefault(a['agent_type'] or '(none)',
                             {'runs': 0, 'prompt': 0, 'skill': 0, 'skill_runs': 0, 'tdd': {}, 'names': {}})
        s['runs'] += 1
        s['prompt'] += nbytes(a['prompt'])
        s['skill'] += sum(b for _, b in a['skills'])
        s['skill_runs'] += 1 if a['skills'] else 0
        for n, _ in a['skills']:
            s['names'][n] = s['names'].get(n, 0) + 1
        tier = s['tdd'].setdefault(tier_of(a['prompt']), [0, 0])
        tier[1] += 1
        tier[0] += 1 if any(n.endswith('test-driven-development') for n, _ in a['skills']) else 0
    coders = [a for a in subs if is_coder(a['agent_type'])]
    sizes = [nbytes(a['final']) for a in coders]
    gate = sum(nbytes(m.group(0)) for a in coders
               for m in [re.search(r'^## Gate Results.*?(?=^## |\Z)', a['final'], re.M | re.S)] if m)
    short = sum(1 for a in coders if re.search(r'^\s*[-*]\s+\[(pass|fail|n/a)\]\s+\S', a['final'], re.M | re.I))
    legacy = sum(1 for a in coders if '## Gate Results' in a['final'] and '## Spec Compliance' in a['final'])
    report = {'n': len(sizes), 'mean': round(statistics.mean(sizes)) if sizes else 0,
              'median': statistics.median(sizes) if sizes else 0,
              'gate_share': round(gate / sum(sizes), 4) if sum(sizes) else 0.0, 'short': short, 'legacy': legacy}
    prod = {'prodded': sum(1 for a in coders if a['prodded']), 'runs': len(coders)}
    return spawn, report, prod


def run(root, slugs, all_projects, since, until):
    runs = collect(root, slugs, all_projects, since, until)
    spawn, report, prod = extra_tables(runs['sub'])
    return {'subagents': summarise(runs['sub']), 'main': summarise(runs['main']),
            'spawn': spawn, 'report': report, 'prod': prod}


def markdown(res, title):
    out = ['# ' + title, '']
    for scope in ('subagents', 'main'):
        s = res[scope]
        out += ['## %s (%d transcripts)' % (scope, s['runs']), '',
                '| Bucket | Events | Load (tokens) | Output tokens | Wall (s) |', '|---|---|---|---|---|']
        for b in BUCKETS:
            t = s['totals'][b]
            if t['events'] or t['wall']:
                out.append('| %s | %d | %d | %d | %.0f |' % (b, t['events'], t['load'] / 4, t['out'], t['wall']))
        out += ['', 'Process share, process / (process + progress): load %s, output %s, wall %s. Model time (span minus tool time): %.0f s.'
                % (s['share']['load'], s['share']['out'], s['share']['wall'], s['model_wall']),
                'Unclassified, top tools: %s' % (', '.join('%s %d' % (n, c) for n, c in s['unclassified_top']) or 'none'), '']
    out += ['## spawn', '', '| Agent type | Runs | Mean prompt B | Mean Skill B | Runs with a Skill | TDD opened, by tier | Skills opened |',
            '|---|---|---|---|---|---|---|']
    for k in sorted(res['spawn']):
        v = res['spawn'][k]
        tdd = ', '.join('%s %d/%d' % (t, o, n) for t, (o, n) in sorted(v['tdd'].items()))
        names = ', '.join('%s %d' % (n, c) for n, c in sorted(v['names'].items(), key=lambda kv: (-kv[1], kv[0])))
        out.append('| %s | %d | %d | %d | %d | %s | %s |' % (k, v['runs'], v['prompt'] / v['runs'], v['skill'] / v['runs'],
                                                           v['skill_runs'], tdd, names or 'none'))
    r, p = res['report'], res['prod']
    out += ['', '## report', '', 'Coder final reports: n %d, mean %d B, median %s B, `## Gate Results` share %s; short form %d, legacy form %d.'
            % (r['n'], r['mean'], r['median'], r['gate_share'], r['short'], r['legacy']),
            '', '## prod', '', 'Coder runs with at least one contract prod: %d of %d.' % (p['prodded'], p['runs']), '']
    return '\n'.join(out)


def compare(actual, expected, path=''):
    """Every key in expected must equal actual's (floats to 4 places). -> list of mismatch lines."""
    bad = []
    for k, want in expected.items():
        got = actual.get(k) if isinstance(actual, dict) else None
        here = path + '/' + k
        if isinstance(want, dict):
            bad += compare(got if isinstance(got, dict) else {}, want, here)
        elif isinstance(want, float) or isinstance(got, float):
            if got is None or round(float(got), 4) != round(float(want), 4):
                bad.append('%s: want %s, got %s' % (here, want, got))
        elif got != want:
            bad.append('%s: want %s, got %s' % (here, want, got))
    return bad


def self_test():
    res = run(os.path.join(FIXTURES, 'projects'), [], True, None, None)
    flat = {'subagents': {'events': {b: t['events'] for b, t in res['subagents']['totals'].items() if t['events']},
                          'load': {b: t['load'] for b, t in res['subagents']['totals'].items() if t['events']},
                          'wall': {b: t['wall'] for b, t in res['subagents']['totals'].items()},
                          'share': res['subagents']['share'],
                          'unclassified_top': res['subagents']['unclassified_top']},
            'main': {'events': {b: t['events'] for b, t in res['main']['totals'].items() if t['events']},
                     'load': {b: t['load'] for b, t in res['main']['totals'].items() if t['events']}},
            'prod': res['prod'], 'report': res['report']}
    with open(os.path.join(FIXTURES, 'expected.json'), encoding='utf-8') as fh:
        expected = json.load(fh)
    bad = compare(flat, expected)
    for scope in ('subagents', 'main'):
        extra_keys = set(flat[scope]['events']) - set(expected[scope]['events'])
        bad += ['/%s/events: unexpected bucket %s' % (scope, k) for k in sorted(extra_keys)]
    # Control: a deliberately wrong expected share must be reported, or the comparison is vacuous.
    wrong = json.loads(json.dumps(expected))
    wrong['subagents']['share']['load'] = round(wrong['subagents']['share']['load'] - 0.05, 4)
    if not compare(flat, wrong):
        bad.append('CONTROL FAILED: a wrong expected share compared equal')
    for line in bad:
        print('SELF-TEST FAIL ' + line)
    if bad:
        return 1
    print('SELF-TEST PASS: %d buckets, share load %s; control fires'
          % (len(expected['subagents']['events']), flat['subagents']['share']['load']))
    return 0


def main(argv):
    if hasattr(sys.stdout, 'reconfigure'):
        sys.stdout.reconfigure(newline='\n')  # LF on Windows too: the output gets committed (check 33)
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--project', help='comma-separated slugs under ~/.claude/projects; worktree slugs fold in')
    ap.add_argument('--all', action='store_true', help='every project, one combined result')
    ap.add_argument('--since', help='YYYY-MM-DD, by a transcript\'s first timestamp (inclusive)')
    ap.add_argument('--until', help='YYYY-MM-DD, inclusive')
    ap.add_argument('--json', action='store_true')
    ap.add_argument('--self-test', action='store_true')
    ap.add_argument('--root', default=os.path.join(os.path.expanduser('~'), '.claude', 'projects'))
    a = ap.parse_args(argv)
    if a.self_test:
        return self_test()
    if not a.all and not a.project:
        ap.error('give --project <slug>[,<slug>...] or --all')
    if not os.path.isdir(a.root):
        print('measure-process: no transcript directory at %s' % a.root, file=sys.stderr)
        return 2
    slugs = [s for s in (a.project or '').split(',') if s]
    res = run(a.root, slugs, a.all, a.since, a.until)
    if a.json:
        print(json.dumps(res, indent=1, sort_keys=True))
    else:
        title = 'Process vs progress: %s, %s to %s' % ('all projects' if a.all else ', '.join(slugs),
                                                      a.since or 'start', a.until or 'today')
        print(markdown(res, title))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
