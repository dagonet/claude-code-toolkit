"""jev_route.run(): the hook's whole decision with fake resolver and transport (v4.4.0 Task 6).

No test here touches the network or the registry: `post` and `registry` are
injected, and JEV_TEST_MODE=1 is set wherever env reaches load_key/pick_endpoint.
"""
import itertools
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import jev_route as jr  # noqa: E402

KEY = "fake-key-0123456789"
MARK = "PROMPT-MARKER-7391"
ENV = {"JEV_TEST_MODE": "1", "JEV_ENDPOINT": "http://127.0.0.1:9/v1/systemone", "TYPESAFE_API_KEY": KEY}


def payload(stype="general-purpose", model=None, tool="Agent", extra=None):
    ti = {"prompt": "Summarise the README. " + MARK, "description": "d", "zz": 1}
    if stype is not None:
        ti["subagent_type"] = stype
    if model is not None:
        ti["model"] = model
    ti.update(extra or {})
    return json.dumps({"tool_name": tool, "tool_input": ti, "cwd": "."}).encode("utf-8")


def answer(choice, conf, effort="medium"):
    return json.dumps({"answers": {
        "model": {"choice": choice, "confidence": conf, "probabilities": {choice: conf}},
        "effort": {"choice": effort, "confidence": 0.7, "probabilities": {}}}}).encode("utf-8")


class Recorder:
    """A fake `post`: records each call, returns `result` or raises `exc`."""
    def __init__(self, result=None, exc=None):
        self.calls, self.result, self.exc = [], result, exc

    def __call__(self, url, body, key, timeout, env):
        self.calls.append({"url": url, "body": body, "key": key, "timeout": timeout})
        if self.exc is not None:
            raise self.exc
        return self.result


class RunTests(unittest.TestCase):
    def setUp(self):
        self.gd = tempfile.mkdtemp(prefix="jev-gd-")
        self.addCleanup(shutil.rmtree, self.gd, True)

    def res(self, kind="floor", model="sonnet", jev=True, effort=""):
        r = jr.Resolution(kind, model, jev, effort, self.gd)
        return lambda t, c, e: r

    def go(self, data, resolver=None, post=None, env=ENV, clock=None):
        kw = {"resolver": resolver or self.res(), "post": post or Recorder(answer("opus", 0.95)),
              "registry": lambda: ""}
        if clock is not None:
            kw["clock"] = clock
        return jr.run(data, dict(env), **kw)

    @staticmethod
    def model_of(out):
        return json.loads(out.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]["model"] if out else None

    def test_off_means_no_output_no_event_no_network(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), resolver=self.res(jev=False), post=post)
        self.assertEqual((out, ev, post.calls), (b"", None, []))

    def test_resolver_unavailable_is_off(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), resolver=lambda t, c, e: None, post=post)
        self.assertEqual((out, ev, post.calls), (b"", None, []))

    def test_not_agent_or_invalid_payload_silent(self):
        for data in (payload(tool="Bash"), b"not json", b"",
                     json.dumps({"tool_name": "Agent", "tool_input": "s"}).encode("utf-8")):
            out, ev, _ = self.go(data)
            self.assertEqual((out, ev), (b"", None), data)

    def test_explicit_model_untouched_and_logged(self):
        post = Recorder(answer("haiku", 0.99))
        out, ev, _ = self.go(payload(model="opus"), post=post)
        self.assertEqual((out, ev["reason"], post.calls), (b"", "explicit", []))

    def test_none_kind_untouched_and_logged(self):
        post = Recorder(answer("haiku", 0.99))
        out, ev, _ = self.go(payload(), resolver=self.res(kind="none", model=""), post=post)
        self.assertEqual((out, ev["reason"], post.calls), (b"", "none", []))

    def test_env_default_does_not_stop_jev(self):
        # U-1: CLAUDE_CODE_SUBAGENT_MODEL=sonnet covers a model-less general-purpose
        # spawn; Jev still routes it, from that value, and a failure emits nothing
        # (the native default applies).
        out, ev, _ = self.go(payload(), resolver=self.res(kind="env", model="sonnet"),
                             post=Recorder(answer("opus", 0.95)))
        self.assertEqual((self.model_of(out), ev["reason"], ev["default"]), ("opus", "applied", "sonnet"))
        out, ev, _ = self.go(payload(), resolver=self.res(kind="env", model="sonnet"),
                             post=Recorder(exc=jr.JevTimeout()))
        self.assertEqual((out, ev["reason"]), (b"", "timeout"))

    def test_floor_spawn_routed_within_bounds(self):
        out, ev, _ = self.go(payload(), post=Recorder(answer("opus", 0.95)))
        self.assertEqual(self.model_of(out), "opus")
        self.assertEqual((ev["applied"], ev["reason"], ev["default"], ev["choice"], ev["emitted"]),
                         (True, "applied", "sonnet", "opus", "opus"))

    def test_typed_spawn_routed_and_input_preserved(self):
        out, _, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"),
                            post=Recorder(answer("sonnet", 0.9)))
        ui = json.loads(out.decode("utf-8"))["hookSpecificOutput"]["updatedInput"]
        self.assertEqual((ui["model"], ui["subagent_type"], ui["zz"], ui["description"]), ("sonnet", "coder", 1, "d"))
        self.assertTrue(ui["prompt"].endswith(MARK))  # the ORIGINAL prompt, not the redacted state

    def test_typed_spawn_low_confidence_silent(self):
        out, ev, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"),
                             post=Recorder(answer("sonnet", 0.5)))
        self.assertEqual((out, ev["reason"], ev["applied"]), (b"", "low-confidence", False))

    def test_floor_spawn_low_confidence_gets_floor(self):
        out, ev, _ = self.go(payload("Plan"), post=Recorder(answer("haiku", 0.5)))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "low-confidence"))

    def test_no_key_floor_gets_floor_without_a_call(self):
        env = dict(ENV)
        del env["TYPESAFE_API_KEY"]
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, env=env)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "no-key", []))

    def test_no_key_typed_silent(self):
        env = dict(ENV)
        del env["TYPESAFE_API_KEY"]
        out, ev, _ = self.go(payload("coder"), resolver=self.res(kind="own", model="opus"), env=env)
        self.assertEqual((out, ev["reason"]), (b"", "no-key"))

    def test_no_endpoint_in_test_mode_means_no_call(self):
        env = dict(ENV, JEV_ENDPOINT="https://api.typesafe.ai/v1/systemone")
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, env=env)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "no-endpoint", []))

    def test_residual_secret_means_no_call(self):
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(extra={"prompt": "use Zq8vN2kLpX4rT7wY1mB6cF9hJ3sD5gA0eU"}), post=post)
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "egress-refused", []))

    def test_transport_failures_fall_back(self):
        for exc, reason in ((jr.JevTimeout(), "timeout"), (jr.HttpError("500"), "http-error"),
                            (OSError("refused"), "http-error")):
            out, ev, _ = self.go(payload(), post=Recorder(exc=exc))
            self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", reason))

    def test_garbage_response_falls_back(self):
        out, ev, _ = self.go(payload(), post=Recorder(b"<html>"))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "bad-response"))

    def test_unexpected_exception_still_floors(self):
        out, ev, _ = self.go(payload(), post=Recorder(exc=RuntimeError("bug")))
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "error"))

    def test_deadline_spent_means_no_call(self):
        ticks = itertools.chain([0.0, 3.49], itertools.repeat(3.6))
        post = Recorder(answer("opus", 0.99))
        out, ev, _ = self.go(payload(), post=post, clock=lambda: next(ticks))
        self.assertEqual((self.model_of(out), ev["reason"], post.calls), ("sonnet", "deadline", []))

    def test_request_carries_key_pinned_model_and_capped_state(self):
        post = Recorder(answer("opus", 0.95))
        self.go(payload(extra={"prompt": "x " * 5000}), post=post)
        call = post.calls[0]
        body = json.loads(call["body"].decode("utf-8"))
        self.assertEqual((call["key"], call["url"], body["model"]), (KEY, ENV["JEV_ENDPOINT"], "jev-1.13.0"))
        self.assertLessEqual(len(body["state"]), 4000)
        self.assertLessEqual(call["timeout"], 2.0)

    def test_config_threshold_and_model_are_read(self):
        os.makedirs(os.path.join(self.gd, "jev"))
        with open(os.path.join(self.gd, "jev", "config.json"), "w", encoding="utf-8") as fh:
            json.dump({"model": "jev-1.14.0", "threshold": 0.95, "route": True}, fh)
        post = Recorder(answer("opus", 0.9))
        out, ev, _ = self.go(payload(), post=post)
        self.assertEqual(json.loads(post.calls[0]["body"].decode("utf-8"))["model"], "jev-1.14.0")
        self.assertEqual((self.model_of(out), ev["reason"]), ("sonnet", "low-confidence"))

    def test_bad_config_uses_defaults(self):
        os.makedirs(os.path.join(self.gd, "jev"))
        with open(os.path.join(self.gd, "jev", "config.json"), "w", encoding="utf-8") as fh:
            fh.write('{"route": true, "threshold": 0.01, "model": "evil"')  # truncated JSON
        post = Recorder(answer("opus", 0.85))
        out, _, _ = self.go(payload(), post=post)
        self.assertEqual(json.loads(post.calls[0]["body"].decode("utf-8"))["model"], "jev-1.13.0")
        self.assertEqual(self.model_of(out), "opus")

    def test_event_never_holds_prompt_or_key_and_reason_is_enum(self):
        for post in (Recorder(answer("opus", 0.95)), Recorder(exc=RuntimeError(MARK + KEY)),
                     Recorder(("garbage " + MARK).encode("utf-8"))):
            _, ev, _ = self.go(payload(), post=post)
            blob = json.dumps(ev)
            self.assertNotIn(MARK, blob)
            self.assertNotIn(KEY, blob)
            self.assertIn(ev["reason"], jr.REASONS)
            self.assertEqual(sorted(ev), sorted(jr.EVENT_FIELDS))

    def test_write_event_file_name_is_ntfs_safe(self):
        jr.write_event(self.gd, {"reason": "kept"})
        names = os.listdir(os.path.join(self.gd, "jev", "events"))
        self.assertEqual(len(names), 1)
        self.assertRegex(names[0], r"^\d{8}T\d{12}Z-\d+\.json$")


class KeyEndpointTests(unittest.TestCase):
    def test_env_key_wins(self):
        self.assertEqual(jr.load_key({"TYPESAFE_API_KEY": " k1 "}, registry=lambda: "k2"), "k1")

    def test_registry_fallback_outside_test_mode(self):
        self.assertEqual(jr.load_key({}, registry=lambda: " k2 "), "k2")

    def test_test_mode_never_reads_the_registry(self):
        def boom():
            raise AssertionError("registry read in test mode")
        self.assertEqual(jr.load_key({"JEV_TEST_MODE": "1"}, registry=boom), "")

    def test_production_endpoint_ignores_overrides(self):
        self.assertEqual(jr.pick_endpoint({"JEV_ENDPOINT": "http://127.0.0.1:1/x"}), jr.ENDPOINT)

    def test_test_mode_endpoint_is_loopback_only(self):
        for url in (jr.ENDPOINT, "http://example.com/x", "http://localhost:1/x", "https://127.0.0.1:1/x", ""):
            self.assertIsNone(jr.pick_endpoint({"JEV_TEST_MODE": "1", "JEV_ENDPOINT": url}), url)
        ok = "http://127.0.0.1:5/v1/systemone"
        self.assertEqual(jr.pick_endpoint({"JEV_TEST_MODE": "1", "JEV_ENDPOINT": ok}), ok)


if __name__ == "__main__":
    unittest.main()
