#!/usr/bin/env bash
# scripts/count-hook-procs.sh -- processes per Bash call, old vs new (v4.4.0 C-verify, cost criteria 1-2).
#
# Runs ONE simulated Bash call (PreToolUse + PostToolUse, for `git status` and `ls -la`)
# through ALL registrations that apply, as Claude Code runs them (shell form as
# `/bin/sh -c "<command>"`, exec form as an argv, CLAUDE_PROJECT_DIR set, payload on
# stdin), each under `strace -ff -e trace=execve,fork,vfork,clone,clone3`, and counts:
#   procs = forks/clones without CLONE_THREAD + 1 root per hook (cross-checked against the
#           per-process strace -ff file count minus thread files; a mismatch warns on stderr)
#   execs = successful execve calls          node = execs of a node/node.exe binary
# old = the repository at --base (git archive); new = the working tree.
# Scenarios (built like scripts/hook-equivalence.sh builds them, Test/Gate = `true`):
#   S1 plain project (temp git repo, no hooks/): user-level hooks only. Old: the old
#      reference settings with @BASH@/@HOOKS@ resolved to a temp HOME; new: that set's
#      scripts/render-user-hooks.sh --print merged into the reference settings.
#   S2 toolkit project bootstrapped by THAT set's setup-project.sh --variant general,
#      plus the same user-level hooks.
# Acceptance on Linux (criteria 1-2): the TOTAL ratio new/old <= 50 % in S1 and S2.
# Always exits 0 (a measurement tool, not a gate: read the ACCEPTANCE line). Skips (exit 0) with a message when strace is absent.
#
# Usage: scripts/count-hook-procs.sh [--base <sha>]
#   default base: .superpowers/sdd/.../base.txt PHASEC_BASE if present, else
#   scripts/fixtures/hook-equivalence/base.sha (as the equivalence harness).

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if ! command -v strace >/dev/null 2>&1; then
  echo "count-hook-procs: strace not found -- skipped (on Windows use the dashboard counter)"
  exit 0
fi
PYBIN=$(command -v python3 || true)
if [ -z "$PYBIN" ]; then echo "count-hook-procs: python3 is required" >&2; exit 2; fi
exec "$PYBIN" - "$ROOT" "$@" <<'PYEOF'
import sys, os, re, json, shutil, subprocess, tempfile, shlex, glob

ROOT = sys.argv[1]
args = sys.argv[2:]
base = ""
if args[:1] == ["--base"] and len(args) == 2:
    base = args[1]
elif args:
    print("usage: count-hook-procs.sh [--base <sha>]", file=sys.stderr); sys.exit(2)
if not base:
    for f, rx in ((ROOT + "/.superpowers/sdd/2026-10-04-hook-slimming/base.txt", r"PHASEC_BASE=([0-9a-f]{7,40})"),
                  (ROOT + "/scripts/fixtures/hook-equivalence/base.sha", r"([0-9a-f]{7,40})")):
        try:
            for line in open(f):
                m = re.fullmatch(rx, line.strip())
                if m: base = m.group(1)
        except OSError:
            pass
        if base: break
if not base:
    print("count-hook-procs: no --base and no base.sha", file=sys.stderr); sys.exit(2)

WORK = tempfile.mkdtemp(prefix="hookprocs-")
PATH = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
BASH = shutil.which("bash") or "/bin/bash"
GITENV = {"PATH": PATH, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
          "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com", "GIT_CONFIG_NOSYSTEM": "1"}

def die(msg):
    print("count-hook-procs: " + msg, file=sys.stderr)
    shutil.rmtree(WORK, ignore_errors=True)
    sys.exit(2)

def run(argv, **kw):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)

def git(proj, *a):
    r = run(["git", "-C", proj] + list(a), env=dict(GITENV, HOME=WORK))
    if r.returncode != 0: die("git %s failed: %s" % (" ".join(a), r.stdout.decode("utf-8", "replace")))

def wfile(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", newline="\n") as f: f.write(text)

old_root = WORK + "/oldroot"
os.makedirs(old_root)
r = subprocess.run("git -C %s archive %s | tar -x -C %s" % (shlex.quote(ROOT), shlex.quote(base), shlex.quote(old_root)),
                   shell=True, stderr=subprocess.PIPE)
if r.returncode != 0 or not os.path.isfile(old_root + "/setup-project.sh"):
    die("git archive %s failed: %s" % (base, r.stderr.decode("utf-8", "replace")))

def finish_repo(proj):
    wfile(proj + "/README.md", "# demo\n"); wfile(proj + "/src/a.txt", "one\n")
    git(proj, "config", "user.name", "t"); git(proj, "config", "user.email", "t@example.com")
    git(proj, "add", "-A"); git(proj, "commit", "-q", "-m", "init", "--no-verify")
    wfile(proj + "/src/a.txt", "one\ntwo\n"); git(proj, "add", "src/a.txt")

BUILT = {}
def build(name, root, scen):
    if (name, scen) not in BUILT: BUILT[(name, scen)] = build1(name, root, scen)
    return BUILT[(name, scen)]

def build1(name, root, scen):
    d = "%s/%s-%s" % (WORK, name, scen)
    home, proj = d + "/home", d + "/proj"
    os.makedirs(home + "/.claude"); os.makedirs(proj)
    shutil.copytree(root + "/user-level-reference/hooks", home + "/.claude/hooks", symlinks=True)
    text = open(root + "/user-level-reference/settings.json", encoding="utf-8").read()
    sf = home + "/.claude/settings.json"
    ruh = root + "/scripts/render-user-hooks.sh"
    if os.path.isfile(ruh):
        r = subprocess.run(["bash", ruh, "--print"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           env=dict(os.environ, HOME=home, RUH_TEST_BASH=BASH))
        if r.returncode != 0: die("%s --print failed: %s" % (ruh, r.stderr.decode()[-400:]))
        doc = json.loads(text); doc["hooks"] = json.loads(r.stdout.decode("utf-8"))
        wfile(sf, json.dumps(doc, indent=2) + "\n")
    else:
        wfile(sf, text.replace("@BASH@", BASH).replace("@HOOKS@", home + "/.claude/hooks"))
    git(proj, "init", "-q", "-b", "main")
    if scen == "S2":
        r = run(["bash", root + "/setup-project.sh", "--variant", "general", "--project-name", "Demo",
                 "--target-path", proj, "--default-branch", "main", "--build-cmd", "true",
                 "--test-cmd", "true", "--gate-cmd", "true"], env=dict(GITENV, HOME=home))
        if r.returncode != 0: die("%s setup-project.sh failed: %s" % (name, r.stdout.decode()[-400:]))
    finish_repo(proj)
    return home, proj

def load_regs(paths, event, tool):
    regs = []
    for sp in paths:
        if not os.path.isfile(sp): continue
        doc = json.load(open(sp, encoding="utf-8"))
        for grp in (doc.get("hooks") or {}).get(event, []) or []:
            m = grp.get("matcher")
            if m not in (None, "", "*") and not re.fullmatch(m, tool): continue
            regs += [h for h in grp.get("hooks", []) or [] if h.get("type", "command") == "command"]
    return regs

def hook_name(h):
    if isinstance(h.get("args"), list) and h["args"]:
        m = re.search(r"([A-Za-z0-9_-]+)\.sh$", h["args"][-1])
        if m: return m.group(1)
    m = re.search(r"hooks/([A-Za-z0-9_-]+)\.sh", h.get("command", ""))
    return m.group(1) if m else "inline"

def count_trace(prefix):
    # strace -ff writes one file per task (<prefix>.<pid>), so no call is ever split by
    # "<unfinished ...>"/"<... resumed>" interleaving. Threads get files too; they are the
    # tasks created by a clone WITH CLONE_THREAD, so processes = files - thread files.
    files = sorted(glob.glob(glob.escape(prefix) + ".*"))
    procs, execs, node, forks, threads = 1, 0, 0, 0, 0
    for path in files:
        for line in open(path, errors="replace"):
            m = re.match(r"(execve|fork|vfork|clone3?)\(", line)
            if not m: continue
            if m.group(1) == "execve":
                if re.search(r"\)\s+=\s+0\s*$", line):
                    execs += 1
                    em = re.match(r'execve\("([^"]*)"', line)
                    if em and os.path.basename(em.group(1)) in ("node", "node.exe"): node += 1
            elif re.search(r"=\s+\d+\s*$", line):      # a successful fork/clone returns the child tid
                if "CLONE_THREAD" in line: threads += 1
                else: forks += 1
    procs = 1 + forks
    if len(files) - threads != procs:
        print("count-hook-procs: WARNING process cross-check differs (%d files - %d threads vs %d forks+1) for %s"
              % (len(files), threads, procs, prefix), file=sys.stderr)
    return procs, execs, node

def call_hook(h, proj, home, payload, n):
    tmp = tempfile.mkdtemp(prefix="t", dir=WORK)
    env = {"PATH": PATH, "HOME": home, "CLAUDE_PROJECT_DIR": proj, "TMPDIR": tmp,
           "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "USER": "t"}
    if isinstance(h.get("args"), list):
        sub = lambda s: s.replace("${CLAUDE_PROJECT_DIR}", proj)
        argv = [sub(h["command"])] + [sub(a) for a in h["args"]]
    else:
        argv = ["/bin/sh", "-c", h["command"]]
    tf = "%s/trace.%d" % (WORK, n)
    subprocess.run(["strace", "-ff", "-s", "64", "-e", "trace=execve,fork,vfork,clone,clone3", "-o", tf] + argv,
                   input=payload, cwd=proj, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=120)
    return count_trace(tf)

def payload_for(event, cmd, proj):
    d = {"session_id": "s1", "transcript_path": "", "cwd": proj, "hook_event_name": event,
         "tool_name": "Bash", "tool_input": {"command": cmd}}
    if event == "PostToolUse":
        d["tool_response"] = {"stdout": "ok\n", "stderr": "", "interrupted": False}
    return json.dumps(d).encode()

counter = [0]
def measure(root_name, root, scen, cmd):
    home, proj = build(root_name, root, scen)
    sp = [home + "/.claude/settings.json", proj + "/.claude/settings.json", proj + "/.claude/settings.local.json"]
    per = {}
    for event in ("PreToolUse", "PostToolUse"):
        seen = {}
        for h in load_regs(sp, event, "Bash"):
            nm = hook_name(h)
            seen[nm] = seen.get(nm, 0) + 1
            counter[0] += 1
            per[(event[:-7] + ":" + nm, seen[nm])] = call_hook(h, proj, home, payload_for(event, cmd, proj), counter[0])
    return per

def ratio(o, n): return "%3d%%" % round(100.0 * n / o) if o else "  - "

try:
    print("count-hook-procs: base %s (old) vs working tree (new); strace -ff; one Bash call = Pre + Post" % base[:12])
    print("%-4s %-10s %-34s %17s  %17s  %5s" % ("scen", "command", "registration", "old procs/ex/node", "new procs/ex/node", "ratio"))
    miss = False
    for scen in ("S1", "S2"):
        for cmd in ("git status", "ls -la"):
            old = measure("old", old_root, scen, cmd)
            new = measure("new", ROOT, scen, cmd)
            to, tn = [0, 0, 0], [0, 0, 0]
            for k in list(old) + [k for k in new if k not in old]:
                o, n = old.get(k, (0, 0, 0)), new.get(k, (0, 0, 0))
                to = [a + b for a, b in zip(to, o)]; tn = [a + b for a, b in zip(tn, n)]
                label = k[0] + ("#%d" % k[1] if k[1] > 1 else "")
                print("%-4s %-10s %-34s %5d/%4d/%4d  %5d/%4d/%4d  %5s" % (scen, cmd, label, *o, *n, ratio(o[0], n[0])))
            print("%-4s %-10s %-34s %5d/%4d/%4d  %5d/%4d/%4d  %5s" % (scen, cmd, "TOTAL", *to, *tn, ratio(to[0], tn[0])))
            print("")
            if to[0] and tn[0] * 2 > to[0]: miss = True
    print("ACCEPTANCE (new <= 50%% of old procs, every scenario/command): %s" % ("MET" if not miss else "MISSED"))
finally:
    shutil.rmtree(WORK, ignore_errors=True)
sys.exit(0)
PYEOF
