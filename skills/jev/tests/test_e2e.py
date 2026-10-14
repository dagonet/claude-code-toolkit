"""jev_route end to end: the real resolver lib, a loopback stub, the real process (v4.4.0 Task 7)."""
import json
import os
import sys
import time
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import jev_route as jr  # noqa: E402
import jevtest as jt  # noqa: E402


def model_of(cp):
    return json.loads(cp.stdout.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]["model"] if cp.stdout else None


def last_event(sb):
    names = sb.events()
    with open(sb.gd + "/jev/events/" + names[-1], encoding="utf-8") as fh:
        return fh.read()


class ResolverAndTransportTests(unittest.TestCase):
    def test_resolver_answers_like_model_floor(self):
        sb = jt.Sandbox(self)
        res = jr.run_resolver("general-purpose", sb.repo, sb.env())
        self.assertEqual((res.kind, res.model, res.jev, res.effort), ("floor", "sonnet", True, ""))
        self.assertEqual(jt.fwd(res.gd), sb.gd)
        # The resolver never needs the key: it must not be in the subprocess env.
        seen = []
        real = jr.subprocess.run

        def spy(*a, **kw):
            seen.append(kw.get("env"))
            return real(*a, **kw)

        env = dict(sb.env(), TYPESAFE_API_KEY=jt.KEY)
        jr.subprocess.run = spy
        try:
            res = jr.run_resolver("general-purpose", sb.repo, env)
        finally:
            jr.subprocess.run = real
        self.assertEqual(res.kind, "floor")
        self.assertEqual(len(seen), 1)
        self.assertFalse("TYPESAFE_API_KEY" in seen[0])  # MH-2: a failure never prints the environment
        self.assertTrue("PATH" in seen[0])

    def test_test_slack_only_in_test_mode(self):
        sb = jt.Sandbox(self)
        base = sb.env()
        envs = [base,
                {k: v for k, v in base.items() if k != "JEV_TEST_SLACK"},
                {k: v for k, v in base.items() if k != "JEV_TEST_MODE"},
                dict(base, JEV_TEST_SLACK="99")]
        seen = []
        real = jr.subprocess.run

        def spy(*a, **kw):
            seen.append(kw.get("timeout"))
            return real(*a, **kw)

        jr.subprocess.run = spy
        try:
            for env in envs:
                jr.run_resolver("general-purpose", sb.repo, env)
        finally:
            jr.subprocess.run = real
        self.assertEqual(seen, [17.0, 2.0, 2.0, 2.0])

    def test_resolver_without_lib_is_none(self):
        sb = jt.Sandbox(self, lib_in_home=False)
        real, jr.__file__ = jr.__file__, sb.home + "/elsewhere/skills/jev/jev_route.py"  # a router outside any plugin
        self.addCleanup(setattr, jr, "__file__", real)
        self.assertIsNone(jr.run_resolver("general-purpose", sb.repo, sb.env()))

    def test_post_sends_bearer_and_returns_body(self):
        stub = jt.Stub(self, "ok", jt.ok_answer("opus", 0.9))
        raw = jr.post_with_deadline(stub.url, b'{"x": 1}', jt.KEY, 2.0, {"JEV_TEST_MODE": "1"})
        self.assertEqual(json.loads(raw.decode("utf-8"))["answers"]["model"]["choice"], "opus")
        self.assertEqual(stub.requests[0]["auth"], "Bearer " + jt.KEY)
        # A redirect is never followed: urllib would resend the Bearer key to the Location host.
        target = jt.Stub(self, "ok", jt.ok_answer())
        redirector = jt.Stub(self, "302", location=target.url)
        with self.assertRaises(jr.HttpError):
            jr.post_with_deadline(redirector.url, b"{}", jt.KEY, 2.0, {"JEV_TEST_MODE": "1"})
        self.assertEqual((len(redirector.requests), target.requests), (1, []))

    def test_post_with_deadline_bounds_a_hang(self):
        stub = jt.Stub(self, "hang")
        t0 = time.monotonic()
        with self.assertRaises(jr.JevTimeout):
            jr.post_with_deadline(stub.url, b"{}", jt.KEY, 0.5, {"JEV_TEST_MODE": "1"})
        self.assertLess(time.monotonic() - t0, 1.5)


class HookTests(unittest.TestCase):
    def test_hook_routes_a_spawn_end_to_end(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "ok", jt.ok_answer("opus", 0.95))
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb, prompt="x " * 4000 + jt.MARK), stub.url)
        self.assertEqual((cp.returncode, model_of(cp)), (0, "opus"))
        req = stub.requests[0]
        body = json.loads(req["body"].decode("utf-8"))
        self.assertEqual((req["auth"], body["model"]), ("Bearer " + jt.KEY, "jev-1.13.0"))
        self.assertLessEqual(len(body["state"]), 4000)
        ev = last_event(sb)
        self.assertNotIn(jt.MARK, ev)
        self.assertNotIn(jt.KEY, ev)
        self.assertEqual(json.loads(ev)["reason"], "applied")

    def test_hook_hang_falls_back_to_floor_in_time(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "hang")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        ev = json.loads(last_event(sb))
        self.assertEqual(ev["reason"], "timeout")
        # The hook's own clock, not the wall clock: interpreter start-up is host load,
        # which pushed the wall time to 5.14 s on a loaded Windows PC (v4.5.2).
        self.assertLess(ev["latency_s"], 5.0)  # the registration's hook timeout

    def test_hook_slow_drip_falls_back_to_floor_in_time(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "drip")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        ev = json.loads(last_event(sb))
        self.assertEqual(ev["reason"], "timeout")
        self.assertLess(ev["latency_s"], 5.0)  # the hook's own clock, as above

    def test_hook_http_500_falls_back(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "500")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertEqual(json.loads(last_event(sb))["reason"], "http-error")

    def test_hook_garbage_falls_back(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "garbage")
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual(model_of(cp), "sonnet")
        self.assertEqual(json.loads(last_event(sb))["reason"], "bad-response")

    def test_hook_off_sends_nothing_writes_nothing(self):
        sb = jt.Sandbox(self, route=False)
        stub = jt.Stub(self, "ok", jt.ok_answer())
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url)
        self.assertEqual((cp.returncode, cp.stdout, stub.requests, sb.events()), (0, b"", [], []))

    def test_hook_unregistered_checkout_is_off(self):
        sb = jt.Sandbox(self, register=False)
        stub = jt.Stub(self, "ok", jt.ok_answer())
        # the v4 path: CLAUDE_PLUGIN_ROOT names no plugin, so the repo's own plugin router cannot answer for it
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url, extra={"CLAUDE_PLUGIN_ROOT": sb.home + "/no-plugin"})
        self.assertEqual((cp.stdout, stub.requests, sb.events()), (b"", [], []))

    def test_hook_explicit_model_sends_nothing(self):
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "ok", jt.ok_answer("haiku", 0.99))
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb, model="opus"), stub.url)
        self.assertEqual((cp.stdout, stub.requests), (b"", []))
        self.assertEqual(json.loads(last_event(sb))["reason"], "explicit")

    def test_hook_env_default_does_not_stop_jev(self):
        # U-1: with CLAUDE_CODE_SUBAGENT_MODEL set and Jev on, a model-less
        # general-purpose spawn gets Jev's pick (model-floor alone would step aside).
        sb = jt.Sandbox(self)
        stub = jt.Stub(self, "ok", jt.ok_answer("opus", 0.95))
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), stub.url, extra={"CLAUDE_CODE_SUBAGENT_MODEL": "sonnet"})
        self.assertEqual((model_of(cp), len(stub.requests)), ("opus", 1))
        ev = json.loads(last_event(sb))
        self.assertEqual((ev["kind"], ev["default"], ev["reason"]), ("env", "sonnet", "applied"))

    def test_floor_holds_in_a_v5_consumer_with_no_resolver_outside_the_plugin(self):
        # C1: no project hooks/lib, an empty HOME (Task 13 removes ~/.claude/hooks), no API key.
        # The router must find the plugin's own agent-model.sh, or the spawn inherits the orchestrator's model.
        sb = jt.Sandbox(self, register=False, skill=False, lib_in_home=False)  # the v5 shape: nothing user-level
        cp, _ = jt.run_hook(sb, jt.agent_payload(sb), "http://127.0.0.1:9/v1/systemone", key=None)
        self.assertEqual((cp.returncode, model_of(cp)), (0, "sonnet"))

    def test_hook_garbage_stdin_exits_zero_silently(self):
        sb = jt.Sandbox(self)
        cp, _ = jt.run_hook(sb, None, "http://127.0.0.1:9/v1/systemone", raw=b"\xff\xfe not json")
        self.assertEqual((cp.returncode, cp.stdout), (0, b""))


if __name__ == "__main__":
    unittest.main()
