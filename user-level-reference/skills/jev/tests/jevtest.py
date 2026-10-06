"""Shared fixtures for the Jev skill tests: a git repo, a fake HOME, a loopback stub.

Never the real API: every environment built here sets JEV_TEST_MODE=1 (the
registry is never read, and only http://127.0.0.1 may be reached) and drops
the caller's TYPESAFE_API_KEY. Paths are forward-slashed for Git Bash.
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True

SKILL = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.environ.get("JEV_REPO_ROOT") or os.path.abspath(os.path.join(SKILL, "..", "..", ".."))
LIB = os.path.join(REPO_ROOT, "hooks", "lib", "agent-model.sh")
ROUTE = os.path.join(SKILL, "jev_route.py")
KEY = "fake-key-0123456789"
MARK = "PROMPT-MARKER-7391"
REGISTRATION = {"hooks": {"PreToolUse": [{"matcher": "Agent", "hooks": [{
    "type": "command", "command": 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && python3 "$f"; exit 0',
    "timeout": 5}]}]}}


def fwd(path):
    return path.replace("\\", "/")


def git(*args):
    return subprocess.run(["git"] + list(args), capture_output=True, check=True).stdout.decode("utf-8").strip()


class Sandbox:
    """A repo with one commit and a HOME holding the resolver lib; flags switch the Jev pieces."""

    def __init__(self, case, register=True, route=True, skill=True, lib_in_home=True):
        if not os.path.isfile(LIB):
            case.skipTest("hooks/lib/agent-model.sh not found (set JEV_REPO_ROOT)")
        tmp = fwd(tempfile.mkdtemp(prefix="jev-"))
        case.addCleanup(shutil.rmtree, tmp, True)
        self.repo, self.home = tmp + "/repo", tmp + "/home"
        os.makedirs(self.repo + "/.claude")
        os.makedirs(self.home + "/.claude/hooks/lib")
        git("init", "-q", "-b", "main", self.repo)
        git("-C", self.repo, "-c", "user.name=t", "-c", "user.email=t@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-q", "--allow-empty", "-m", "init")
        self.gd = fwd(git("-C", self.repo, "rev-parse", "--path-format=absolute", "--git-common-dir"))
        self.home_lib = self.home + "/.claude/hooks/lib/agent-model.sh"
        if lib_in_home:
            shutil.copyfile(LIB, self.home_lib)
        self.skill_file = self.home + "/.claude/skills/jev/jev_route.py"
        if skill:
            os.makedirs(os.path.dirname(self.skill_file))
            open(self.skill_file, "w").close()
        self.settings = self.repo + "/.claude/settings.local.json"
        if register:
            with open(self.settings, "w", encoding="utf-8", newline="\n") as fh:
                json.dump(REGISTRATION, fh)
        self.config = self.gd + "/jev/config.json"
        if route is not None:
            os.makedirs(self.gd + "/jev", exist_ok=True)
            with open(self.config, "w", encoding="utf-8", newline="\n") as fh:
                json.dump({"model": "jev-1.13.0", "threshold": 0.8, "route": route, "legs": False}, fh)

    def env(self, endpoint="http://127.0.0.1:9/v1/systemone", key=KEY, extra=None):
        drop = {"TYPESAFE_API_KEY", "CLAUDE_PROJECT_DIR", "CLAUDE_CODE_SUBAGENT_MODEL",
                "CLAUDE_CODE_SUBAGENT_MODEL_FORCE", "JEV_ENDPOINT", "XDG_CONFIG_HOME"}  # J-6: no user git config
        env = {k: v for k, v in os.environ.items() if k not in drop}
        env.update({"HOME": self.home, "JEV_TEST_MODE": "1", "JEV_ENDPOINT": endpoint,
                    "PYTHONDONTWRITEBYTECODE": "1"})
        if key:
            env["TYPESAFE_API_KEY"] = key
        env.update(extra or {})
        return env

    def events(self):
        d = self.gd + "/jev/events"
        return sorted(os.listdir(d)) if os.path.isdir(d) else []

    def lib_cli(self, stype):
        env = self.env()
        bash = shutil.which("bash", path=env.get("PATH")) or "bash"  # not System32's WSL launcher on Windows
        cp = subprocess.run([bash, LIB, stype, self.repo], capture_output=True, env=env, timeout=20)
        return cp.stdout.decode("utf-8", "replace").strip()


class Stub:
    """A loopback /v1/systemone: mode ok | hang | drip | 500 | garbage. Records requests."""

    def __init__(self, case, mode, body=None, location=None):
        self.mode, self.body, self.requests, self.location = mode, body, [], location
        stub = self

        class Handler(http.server.BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):  # only a followed redirect lands here: record it, answer 404
                stub.requests.append({"auth": self.headers.get("Authorization"), "body": b""})
                self.send_response(404)
                self.send_header("Content-Length", "0")
                self.end_headers()

            def do_POST(self):
                n = int(self.headers.get("Content-Length") or 0)
                stub.requests.append({"auth": self.headers.get("Authorization"), "body": self.rfile.read(n)})
                if stub.mode == "hang":
                    time.sleep(10)
                    return
                if stub.mode == "drip":  # headers at once, then one byte every 0.5 s
                    self.send_response(200)
                    self.send_header("Content-Length", "1000")
                    self.end_headers()
                    try:
                        for _ in range(20):
                            self.wfile.write(b" ")
                            self.wfile.flush()
                            time.sleep(0.5)
                    except OSError:  # the client gave up, as the test expects
                        pass
                    return
                if stub.mode == "302":  # redirect to stub.location
                    self.send_response(302)
                    self.send_header("Location", stub.location)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                if stub.mode == "500":
                    self.send_response(500)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                data = b"not json" if stub.mode == "garbage" else json.dumps(stub.body).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

        self.server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.daemon_threads = True
        self.server.block_on_close = False
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = "http://127.0.0.1:%d/v1/systemone" % self.server.server_address[1]
        case.addCleanup(self.close)

    def close(self):
        self.server.shutdown()
        self.server.server_close()


def ok_answer(choice="opus", conf=0.95):
    return {"model": "jev-1.13.0", "answers": {
        "model": {"type": "choice", "choice": choice, "confidence": conf, "probabilities": {choice: conf}},
        "effort": {"type": "choice", "choice": "medium", "confidence": 0.7, "probabilities": {}}},
        "usage": {"input_tokens": 1, "output_tokens": 1}}


def agent_payload(sandbox, stype="general-purpose", model=None, prompt="Summarise the README. " + MARK):
    ti = {"subagent_type": stype, "prompt": prompt, "description": "d", "zz": 1}
    if model:
        ti["model"] = model
    return {"session_id": "t", "hook_event_name": "PreToolUse", "tool_name": "Agent",
            "tool_input": ti, "cwd": sandbox.repo}


def run_hook(sandbox, payload, endpoint, key=KEY, raw=None, extra=None):
    """Run jev_route.py as the registration would. -> (CompletedProcess, seconds)."""
    t0 = time.monotonic()
    data = raw if raw is not None else json.dumps(payload).encode("utf-8")
    cp = subprocess.run([sys.executable, ROUTE], input=data, capture_output=True,
                        env=sandbox.env(endpoint, key, extra), timeout=20)
    return cp, time.monotonic() - t0
