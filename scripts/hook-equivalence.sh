#!/usr/bin/env bash
# scripts/hook-equivalence.sh -- old-vs-new hook equivalence harness (v4.4.0 C-verify).
#
# Runs every payload of scripts/fixtures/hook-equivalence/corpus.tsv through TWO
# hook sets "as Claude Code would" and reports every payload on which the merged
# decision differs:
#   old = the repository at PHASEC_BASE (`git archive`, extracted to a temp dir)
#   new = the working tree (or --new-root <dir>, a scratch copy; this is how the
#         harness's own control is run without touching a tracked hook)
#
# "As Claude Code would": the registrations are READ from the settings.json
# files (user-level + project + settings.local.json), selected by event and
# matcher (missing/empty/"*" = all, otherwise a regex FULL match of the tool
# name, `|` alternation), and each is run in its own form -- shell form as
# `/bin/sh -c "<command>"`, exec form (`command` + `args`) as an argv with
# `${CLAUDE_PROJECT_DIR}` substituted as a plain string -- with CLAUDE_PROJECT_DIR
# set, the payload on stdin, a 60 s timeout and a fresh TMPDIR per hook run.
# Results merge as Claude Code merges them: deny > ask > context > allow.
#   deny    exit 2, or JSON permissionDecision "deny" / decision "block"
#   ask     JSON permissionDecision "ask"
#   context exit 0 with additionalContext / updatedToolOutput, or any non-empty
#           stdout on PostToolUse / SessionStart
#   allow   exit 0, or any non-zero exit other than 2 (a non-blocking error,
#           spec 2.5); that case is annotated allow* and only ever printed as a
#           NOTE when it is the sole difference -- it is never a decision change
# Reason category = the SET of hook basenames that denied (the basename of the
# registered script, taken from the registration, not from message wording).
# An `updatedInput` / `updatedToolOutput` emission is compared too (name and a
# digest of its content); a change there is reported as a difference.
#
# Scenarios (each payload runs in all four, in a normal and a "missing" mode):
#   S1 plain project (git repo, no hooks/, no project settings): user-level only
#   S2 toolkit project, bootstrapped by THAT set's own setup-project.sh
#      (--variant general): user-level + the project's template registrations
#   S4 the S2 project with NO user-level hooks/settings (project registrations alone)
#   S3 this repo's own registration shape: a temp project holding that set's root
#      .claude/settings.json + hooks/ (registers only some hooks: the C5 fixture)
#   missing mode (S1m..S4m): the same, with every hooks/*.sh and
#      ~/.claude/hooks/*.sh renamed away (lib/ stays), old and new alike
# Every row runs in its own copy of the scenario (a temp repo on branch main with
# a staged change), so rows cannot influence each other and run in parallel.
# No real suite runs: PROJECT_CONTEXT.md carries Test/Gate = `true`.
#
# Parser configurations (--config): full (normal PATH), python3 (a whitelist
# shim directory with no node and no jq), jq (no node and no python3). Each
# restricted configuration is self-checked with `command -v`; a restriction that
# did not apply aborts the run (a restriction that did not apply is not a pass).
# The registration reader (python3, this process) runs outside the restricted PATH.
#
# Usage:
#   scripts/hook-equivalence.sh [--config full|python3|jq] [--base <sha>]
#       [--only <id-glob>] [--new-root <dir>] [--mode normal|missing|both]
#       [--scenarios S1,S2,S3,S4] [--workers N] [--list 1]   (--list: print every row's result)
# Output: one `DIFF <scenario> <config> <id>: old=<class>{<cats>} new=<class>{<cats>}`
# per difference, a per-class TALLY per scenario, and a last line
# `EQUIVALENCE: <n> decision changes`. Exit 0 only when n = 0 and every normal
# scenario has >= 25 deny and >= 25 allow rows (a corpus that all allows proves
# nothing). Exit 2 on a harness/environment failure.

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PYBIN=$(command -v python3 || true)
if [ -z "$PYBIN" ]; then echo "hook-equivalence: python3 is required (it reads the settings.json files)" >&2; exit 2; fi
exec "$PYBIN" - "$ROOT" "$@" <<'PYEOF'
import sys, os, re, json, shutil, subprocess, tempfile, fnmatch, hashlib, time, glob
from concurrent.futures import ThreadPoolExecutor

ROOT = sys.argv[1]
args = sys.argv[2:]
opt = {"config": "full", "base": "", "only": "", "new-root": "", "mode": "both",
       "scenarios": "S1,S2,S3,S4", "list": "", "workers": str(os.cpu_count() or 2)}
i = 0
while i < len(args):
    a = args[i]
    if a.startswith("--") and a[2:] in opt and i + 1 < len(args):
        opt[a[2:]] = args[i + 1]; i += 2
    else:
        print("hook-equivalence: unknown or incomplete option: %s" % a, file=sys.stderr); sys.exit(2)
if opt["config"] not in ("full", "python3", "jq"):
    print("hook-equivalence: --config must be full|python3|jq", file=sys.stderr); sys.exit(2)

T0 = time.time()
ORIG_PATH = os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin")
BASH = shutil.which("bash") or "/bin/bash"
CORPUS = os.path.join(ROOT, "scripts/fixtures/hook-equivalence/corpus.tsv")

def die(msg):
    print("hook-equivalence: " + msg, file=sys.stderr)
    try: shutil.rmtree(WORK, ignore_errors=True)
    except NameError: pass
    sys.exit(2)

def sh(argv, **kw):
    return subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **kw)

# ---- base sha -------------------------------------------------------------
base = opt["base"]
if not base:   # then base.txt (the SDD scratch override, git-ignored), then the committed base.sha
    bf = os.path.join(ROOT, ".superpowers/sdd/2026-10-04-hook-slimming/base.txt")
    try:
        for line in open(bf):
            m = re.match(r"PHASEC_BASE=([0-9a-f]{7,40})", line.strip())
            if m: base = m.group(1)
    except OSError:
        pass
if not base:
    try:
        for line in open(os.path.join(ROOT, "scripts/fixtures/hook-equivalence/base.sha")):
            if re.fullmatch(r"[0-9a-f]{7,40}", line.strip()): base = line.strip(); break
    except OSError:
        pass
if not base:
    die("no --base given, no PHASEC_BASE in base.txt and no scripts/fixtures/hook-equivalence/base.sha")
NEW_ROOT = os.path.abspath(opt["new-root"] or ROOT)

WORK = tempfile.mkdtemp(prefix="hookeq-")
OLD_ROOT = os.path.join(WORK, "oldroot")
os.makedirs(OLD_ROOT)
import shlex
r = subprocess.run("git -C %s archive %s | tar -x -C %s" % (shlex.quote(ROOT), shlex.quote(base), shlex.quote(OLD_ROOT)),
                   shell=True, stderr=subprocess.PIPE)
if r.returncode != 0 or not os.path.isfile(os.path.join(OLD_ROOT, "setup-project.sh")):
    die("git archive %s failed: %s" % (base, r.stderr.decode("utf-8", "replace")))

# ---- the parser configurations -------------------------------------------
TOOLS = ("sh bash dash git grep egrep fgrep sed awk gawk mawk tr head tail cut cat wc stat date mktemp "
         "dirname basename sort uniq mkdir rmdir rm ls env find touch cp mv ln chmod expr od xxd cksum "
         "md5sum sha1sum sha256sum base64 diff cmp timeout sleep tee xargs readlink realpath id uname "
         "whoami hostname true false test tput ps kill pgrep nohup setsid seq paste comm join fold tac rev "
         "nl iconv locale printf echo pwd tty uniq nproc df du sync").split()
PATHS = {}

def make_shim(name, extra):
    d = os.path.join(WORK, "path-" + name)
    os.makedirs(d)
    for t in TOOLS + extra:
        p = shutil.which(t, path=ORIG_PATH)
        if p and not os.path.exists(os.path.join(d, t)):
            os.symlink(p, os.path.join(d, t))
    return d

def selfcheck(name, d, want_present, want_absent):
    for t in want_present:
        r = subprocess.run(["/bin/sh", "-c", "command -v " + t], env={"PATH": d}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode != 0:
            die("self-check: config %s: `command -v %s` FAILED but must succeed (shim %s)" % (name, t, d))
    for t in want_absent:
        r = subprocess.run(["/bin/sh", "-c", "command -v " + t], env={"PATH": d}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if r.returncode == 0:
            die("self-check: config %s: `command -v %s` SUCCEEDED (%s) but must fail -- the restriction did not apply" % (name, t, r.stdout.decode().strip()))
    r = subprocess.run(["/bin/sh", "-c", "python3 -c 'import json;print(json.dumps(1))'" if "python3" in want_present else "echo '{}' | jq -c ." if "jq" in want_present else "true"],
                       env={"PATH": d}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        die("self-check: config %s: the permitted parser does not run: %s" % (name, r.stderr.decode()[:200]))

cfg = opt["config"]
if cfg == "full":
    HOOK_PATH = ORIG_PATH
    selfcheck("full", ORIG_PATH, ["node", "python3", "jq"], [])
elif cfg == "python3":
    HOOK_PATH = make_shim("python3", ["python3"])
    selfcheck("python3", HOOK_PATH, ["python3", "bash", "git", "sh"], ["node", "jq"])
else:
    HOOK_PATH = make_shim("jq", ["jq"])
    selfcheck("jq", HOOK_PATH, ["jq", "bash", "git", "sh"], ["node", "python3"])
print("CONFIG %s: PATH=%s" % (cfg, HOOK_PATH))
for t in ("node", "python3", "jq", "bash"):
    r = subprocess.run(["/bin/sh", "-c", "command -v " + t], env={"PATH": HOOK_PATH}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    print("  %-8s -> %s" % (t, r.stdout.decode().strip() or "(absent)"))

# ---- scenario construction ------------------------------------------------
GITENV = {"PATH": ORIG_PATH, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.com",
          "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.com", "HOME": WORK,
          "GIT_CONFIG_NOSYSTEM": "1"}

def git(proj, *a):
    r = subprocess.run(["git", "-C", proj] + list(a), env=GITENV, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        die("git %s failed in %s: %s" % (" ".join(a), proj, r.stdout.decode("utf-8", "replace")))

def wfile(p, text):
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", newline="\n") as f: f.write(text)

def fixtures(proj):
    wfile(proj + "/push.sh", "#!/bin/sh\ngit push origin main\n")
    wfile(proj + "/push.ps1", "git push origin main\n")
    wfile(proj + "/.env", "KEY=secret\n")
    wfile(proj + "/.env.local", "KEY=secret\n")
    wfile(proj + "/.env.production", "KEY=secret\n")
    wfile(proj + "/.env.example", "KEY=\n")
    wfile(proj + "/.environment", "x\n")
    wfile(proj + "/config/.env.staging", "KEY=secret\n")
    wfile(proj + "/README.md", "# demo\n")
    wfile(proj + "/src/a.txt", "one\n")
    wfile(proj + "/big.txt", "".join("line %d\n" % n for n in range(2000)))
    wfile(proj + "/n.ipynb", "{}\n")
    # SubagentStop transcripts: a compliant coder report and a non-compliant one
    for nm, txt in (("tr-ok", "done\n## Gate Results\nok\n## Spec Compliance\n1 DONE"), ("tr-bad", "I am finished")):
        wfile(proj + "/" + nm + ".jsonl", json.dumps({"type": "assistant", "message": {"content": txt}}) + "\n")

def finish_repo(proj):
    fixtures(proj)
    git(proj, "config", "user.name", "t"); git(proj, "config", "user.email", "t@example.com")
    git(proj, "add", "-A"); git(proj, "commit", "-q", "-m", "init", "--no-verify")
    wfile(proj + "/src/a.txt", "one\ntwo\n")
    git(proj, "add", "src/a.txt")   # a staged change, so `git commit` has something to commit

def render_user_settings(text, home):
    # render-user-hooks.sh's substitution, done directly: the absolute bash path
    # and this row's own ~/.claude/hooks (the template copy is per row)
    return text.replace("@BASH@", BASH).replace("@HOOKS@", home + "/.claude/hooks")

def build_set(name, root):
    """Returns {scenario: template dir containing home/ and proj/}; normal mode only."""
    out = {}
    base_dir = os.path.join(WORK, name)
    for scen in ("S1", "S2", "S3", "S4"):
        d = os.path.join(base_dir, scen)
        home, proj = d + "/home", d + "/proj"
        os.makedirs(home + "/.claude")
        out[scen] = d
        if scen == "S4": continue      # S4 is copied from S2 below, with an EMPTY ~/.claude
        os.makedirs(proj)
        shutil.copytree(root + "/user-level-reference/hooks", home + "/.claude/hooks", symlinks=True)
        wfile(home + "/.claude/settings.json", open(root + "/user-level-reference/settings.json", encoding="utf-8").read())
    # S1: plain project
    p = out["S1"] + "/proj"
    git(p, "init", "-q", "-b", "main"); finish_repo(p)
    # S2: bootstrapped by THAT set's setup-project.sh
    p = out["S2"] + "/proj"
    git(p, "init", "-q", "-b", "main")
    r = subprocess.run(["bash", root + "/setup-project.sh", "--variant", "general", "--project-name", "Demo",
                        "--target-path", p, "--default-branch", "main", "--build-cmd", "true",
                        "--test-cmd", "true", "--gate-cmd", "true"],
                       env=dict(GITENV, HOME=out["S2"] + "/home"), stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if r.returncode != 0:
        die("%s setup-project.sh failed: %s" % (name, r.stdout.decode("utf-8", "replace")[-600:]))
    finish_repo(p)
    # S3: this repo's root registration shape (settings.json + hooks/), Test/Gate = true
    p3 = out["S3"] + "/proj"
    git(p3, "init", "-q", "-b", "main")
    shutil.copytree(root + "/hooks", p3 + "/hooks", symlinks=True)
    wfile(p3 + "/.claude/settings.json", open(root + "/.claude/settings.json", encoding="utf-8").read())
    shutil.copy(out["S2"] + "/proj/PROJECT_CONTEXT.md", p3 + "/PROJECT_CONTEXT.md")
    finish_repo(p3)
    # S4: the S2 project with NO user-level hooks or settings, so a regression of a
    # PROJECT registration is not masked by the user-level copy of the same guard
    shutil.copytree(out["S2"] + "/proj", out["S4"] + "/proj", symlinks=True)
    return out

def make_missing(tmpl_dir):
    md = tmpl_dir + "-missing"
    shutil.copytree(tmpl_dir, md, symlinks=True)
    for hd in (md + "/home/.claude/hooks", md + "/proj/hooks"):
        for f in glob.glob(hd + "/*.sh"):
            os.rename(f, f + ".offline")
    return md

SCENS = [s for s in opt["scenarios"].split(",") if s]
SETS = {}
for nm, rt in (("old", OLD_ROOT), ("new", NEW_ROOT)):
    t = build_set(nm, rt)
    SETS[nm] = {}
    for s in SCENS:
        SETS[nm][(s, "normal")] = t[s]
        if opt["mode"] in ("missing", "both"):
            SETS[nm][(s, "missing")] = make_missing(t[s])
MODES = (["normal"] if opt["mode"] in ("normal", "both") else []) + (["missing"] if opt["mode"] in ("missing", "both") else [])

# ---- the corpus -----------------------------------------------------------
def expand(text, cwd):
    text = re.sub(r"@REP:(\d+):(.*?)@", lambda m: m.group(2) * int(m.group(1)), text)
    text = re.sub(r"@EMOJI:(\d+)@", lambda m: "\U0001F600" * int(m.group(1)), text)
    return text.replace("@BOM@", "﻿").replace("@CWD@", cwd)

rows = []
for line in open(CORPUS, encoding="utf-8", newline=""):
    line = line.rstrip("\n")
    if not line or line.startswith("#") or line.startswith("id\t"):
        continue
    parts = line.split("\t", 3)
    while len(parts) < 4: parts.append("")
    if opt["only"] and not fnmatch.fnmatch(parts[0], opt["only"]):
        continue
    rows.append(parts)
if not rows:
    die("no corpus rows selected")

# ---- registrations --------------------------------------------------------
def load_regs(settings_paths, event, tool):
    regs = []
    for sp in settings_paths:
        if not os.path.isfile(sp): continue
        try:
            doc = json.load(open(sp, encoding="utf-8"))
        except Exception as e:
            die("cannot parse %s: %s" % (sp, e))
        for grp in (doc.get("hooks") or {}).get(event, []) or []:
            m = grp.get("matcher")
            # Claude Code tests a matcher as a regex; fullmatch is equivalent for the
            # current `A|B` matchers (plain names joined by |)
            if m not in (None, "", "*") and not re.fullmatch(m, tool or ""):
                continue
            for h in grp.get("hooks", []) or []:
                if h.get("type", "command") != "command": continue
                regs.append(h)
    return regs

def hook_name(h):
    if isinstance(h.get("args"), list) and h["args"]:
        m = re.search(r"([A-Za-z0-9_-]+)\.sh(?:\.offline)?$", h["args"][-1])
        if m: return m.group(1)
    m = re.search(r"hooks/([A-Za-z0-9_-]+)\.sh", h.get("command", ""))
    return m.group(1) if m else "inline"

def run_hook(h, proj, home, payload, sandbox):
    tmp = tempfile.mkdtemp(prefix="t", dir=sandbox)
    env = {"PATH": HOOK_PATH, "HOME": home, "CLAUDE_PROJECT_DIR": proj, "TMPDIR": tmp,
           "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8", "USER": "t"}
    if isinstance(h.get("args"), list):
        sub = lambda s: s.replace("${CLAUDE_PROJECT_DIR}", proj)
        argv = [sub(h["command"])] + [sub(a) for a in h["args"]]
    else:
        argv = ["/bin/sh", "-c", h["command"]]
    try:
        r = subprocess.run(argv, input=payload, cwd=proj, env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=60)
        return r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired:
        return "timeout", b"", b"hook timed out after 60 s"
    except OSError as e:
        return 126, b"", ("exec failed: %s" % e).encode()

def classify(event, rc, out, norm):
    """-> (class, star, upd) for ONE hook run."""
    if rc == 2: return "deny", False, []
    if rc != 0: return "allow", True, []
    text = out.decode("utf-8", "replace")
    objs = []
    try: objs = [json.loads(text)]
    except Exception:
        for ln in text.splitlines():
            try: objs.append(json.loads(ln))
            except Exception: pass
    cls = "allow"; upd = []
    for o in objs:
        if not isinstance(o, dict): continue
        hso = o.get("hookSpecificOutput") if isinstance(o.get("hookSpecificOutput"), dict) else {}
        pd = hso.get("permissionDecision") or o.get("permissionDecision")
        if pd == "deny" or o.get("decision") == "block": cls = "deny"
        elif pd == "ask" and cls != "deny": cls = "ask"
        elif (("additionalContext" in hso) or ("updatedToolOutput" in hso)) and cls == "allow": cls = "context"
        for k in ("updatedInput", "updatedToolOutput"):
            if k in hso:
                upd.append(hashlib.sha1(norm(json.dumps(hso[k], sort_keys=True)).encode()).hexdigest()[:8])
    if cls == "allow" and text.strip() and event in ("PostToolUse", "SessionStart", "UserPromptSubmit"):
        cls = "context"
    return cls, False, upd

RANK = {"deny": 3, "ask": 2, "context": 1, "allow": 0}

def run_row(job):
    setname, scen, mode, row = job
    rid, event, tool, payload_t = row
    tmpl = SETS[setname][(scen, mode)]
    sb = tempfile.mkdtemp(prefix="r", dir=WORK)
    try:
        shutil.copytree(tmpl, sb + "/s", symlinks=True)
        home, proj = sb + "/s/home", sb + "/s/proj"
        uf = home + "/.claude/settings.json"
        if os.path.isfile(uf):
            wfile(uf, render_user_settings(open(uf, encoding="utf-8").read(), home))
        # the sandbox path, and the spill-log name (TMPDIR + a timestamp) that
        # bash-output-guard embeds in its truncation marker, are not decisions
        norm = lambda s: re.sub(r"[^\"\s]*claude-bash-out/[^\"\s\]]*\.log", "@LOG@", s.replace(sb, "@SB@"))
        payload = expand(payload_t, proj).encode("utf-8")
        sp = [home + "/.claude/settings.json", proj + "/.claude/settings.json", proj + "/.claude/settings.local.json"]
        hooks_run = []; merged = "allow"; star = False; cats = set(); upd = []
        stderr_all = b""
        for h in load_regs(sp, event, tool):
            rc, out, err = run_hook(h, proj, home, payload, sb)
            stderr_all += err
            cls, st, u = classify(event, rc, out, norm)
            nm = hook_name(h)
            if cls == "deny": cats.add(nm)
            if RANK[cls] > RANK[merged]: merged = cls
            if st: star = True
            upd += ["%s:%s" % (nm, x) for x in u]
        if merged != "deny": cats = set()
        if merged != "allow": star = False
        nf = [l for l in stderr_all.decode("utf-8", "replace").splitlines() if "command not found" in l]
        return (merged, tuple(sorted(cats)), star, tuple(sorted(set(upd))), nf[:2])
    finally:
        shutil.rmtree(sb, ignore_errors=True)

jobs = []
for s in SCENS:
    for m in MODES:
        for row in rows:
            jobs.append((s, m, row))

def pair(j):
    s, m, row = j
    return (run_row(("old", s, m, row)), run_row(("new", s, m, row)))

with ThreadPoolExecutor(max_workers=max(1, int(opt["workers"]))) as ex:
    results = list(ex.map(pair, jobs))

# ---- report ---------------------------------------------------------------
def fmt(r): return "%s{%s}" % (r[0], ",".join(r[1]))
changes = 0; notes = 0; envbad = 0; tally = {}
for (s, m, row), (o, n) in zip(jobs, results):
    scen = s + ("m" if m == "missing" else "")
    t = tally.setdefault((scen, m), {"deny": 0, "ask": 0, "context": 0, "allow": 0})
    t[o[0]] += 1
    if opt["list"]:
        print("ROW %s %s %s: old=%s%s new=%s%s" % (scen, cfg, row[0], fmt(o), "*" if o[2] else "", fmt(n), "*" if n[2] else ""))
    for who, r in (("old", o), ("new", n)):
        if r[4]:
            envbad += 1
            print("ENV-INCOMPLETE %s %s %s %s: %s" % (scen, cfg, row[0], who, r[4][0][:160]))
    if (o[0], o[1], o[3]) != (n[0], n[1], n[3]):
        changes += 1
        extra = "" if o[3] == n[3] else " upd:old=%s new=%s" % (list(o[3]), list(n[3]))
        print("DIFF %s %s %s: old=%s new=%s%s" % (scen, cfg, row[0], fmt(o), fmt(n), extra))
    elif o[2] != n[2]:
        notes += 1
        print("NOTE %s %s %s: only the non-blocking-error annotation differs (old=%s%s new=%s%s)"
              % (scen, cfg, row[0], o[0], "*" if o[2] else "", n[0], "*" if n[2] else ""))
bad_tally = 0
for (scen, m), t in sorted(tally.items()):
    line = "TALLY %s %s: rows=%d deny=%d ask=%d context=%d allow=%d" % (
        scen, cfg, sum(t.values()), t["deny"], t["ask"], t["context"], t["allow"])
    if m == "normal" and not opt["only"] and (t["deny"] < 25 or t["allow"] < 25):
        line += "  FAIL: need >= 25 deny and >= 25 allow"; bad_tally += 1
    print(line)
shutil.rmtree(WORK, ignore_errors=True)
print("WALL: %.0f s (config %s, %d rows x %d scenario-modes, %s workers, %d notes)"
      % (time.time() - T0, cfg, len(rows), len(tally), opt["workers"], notes))
if envbad:
    print("hook-equivalence: %d run(s) hit `command not found` -- the restricted PATH is incomplete" % envbad)
print("EQUIVALENCE: %d decision changes" % changes)
sys.exit(0 if (changes == 0 and bad_tally == 0 and envbad == 0) else 1)
PYEOF
