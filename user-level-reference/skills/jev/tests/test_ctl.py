"""/jev on | off | status | report (v4.4.0 Task 8)."""
import datetime
import io
import json
import os
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import jev_ctl as jc  # noqa: E402
import jevtest as jt  # noqa: E402

EV = {"ts": "2026-10-02T10:00:30.000Z", "subagent_type": "general-purpose", "kind": "floor", "default": "sonnet",
      "agent_effort": "", "choice": None, "confidence": None, "probabilities": {}, "effort_choice": None,
      "effort_confidence": None, "applied": False, "reason": "kept", "emitted": None, "latency_s": 0.3}


class CtlTests(unittest.TestCase):
    def setUp(self):
        self.t = jt.Sandbox(self, register=False, route=None)

    def ctl(self, *argv, env=None, registry=lambda: ""):
        out = io.StringIO()
        rc = jc.main(list(argv), cwd=self.t.repo, env=env or self.t.env(), out=out, registry=registry)
        return rc, out.getvalue()

    def read(self, path):
        with open(path, "rb") as fh:
            return fh.read()

    def write(self, path, data):
        with open(path, "wb") as fh:
            fh.write(data)

    def exclude_lines(self):
        return self.read(self.t.gd + "/info/exclude").decode("utf-8").splitlines()

    def test_on_writes_config_registration_and_exclude(self):
        rc, text = self.ctl("on")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.config)), jc.CONFIG_ON)
        obj = json.loads(self.read(self.t.settings))
        self.assertEqual(obj["hooks"]["PreToolUse"], [{"matcher": "Agent", "hooks": [
            {"type": "command", "command": jc.REG_COMMAND, "timeout": 5}]}])
        # U-1: a new session must learn that Jev is on, and to omit `model`
        self.assertEqual(obj["hooks"]["SessionStart"], [{"hooks": [
            {"type": "command", "command": jc.SESSION_COMMAND, "timeout": 5}]}])
        self.assertIn(".claude/settings.local.json", self.exclude_lines())
        self.assertIn("omit `model`", text)

    def test_on_twice_is_idempotent(self):
        self.ctl("on")
        first = self.read(self.t.settings)
        rc, text = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (0, first))
        self.assertEqual(self.exclude_lines().count(".claude/settings.local.json"), 1)
        self.assertIn("already registered", text)

    def test_round_trip_restores_existing_bytes(self):
        original = ('\ufeff{\r\n  "permissions": {"allow": ["Bash(ls)"]},\r\n  "hooks": {"PreToolUse": '
                    '[{"matcher": "Agent", "hooks": [{"type": "command", "command": "echo mine"}]}]}\r\n}\r\n').encode("utf-8")
        self.write(self.t.settings, original)
        self.ctl("on")
        self.assertNotEqual(self.read(self.t.settings), original)
        rc, text = self.ctl("off")
        self.assertEqual((rc, self.read(self.t.settings)), (0, original), text)

    def test_round_trip_deletes_a_file_on_created(self):
        self.assertFalse(os.path.exists(self.t.settings))
        self.ctl("on")
        self.assertTrue(os.path.exists(self.t.settings))
        _, text = self.ctl("off")
        self.assertFalse(os.path.exists(self.t.settings))
        self.assertIn("name `model` on every Agent spawn again", text)  # U-1: the rule returns

    def test_off_after_user_edit_removes_only_the_jev_entry(self):
        self.ctl("on")
        obj = json.loads(self.read(self.t.settings))
        obj["permissions"] = {"allow": ["Bash(git status)"]}
        self.write(self.t.settings, json.dumps(obj).encode("utf-8"))
        rc, text = self.ctl("off")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.settings)), {"permissions": {"allow": ["Bash(git status)"]}})
        self.assertIn("removed only the Jev entry", text)

    def test_off_sets_route_false_and_the_floor_returns(self):
        self.ctl("on")
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "1")
        self.ctl("off")
        self.assertIs(json.loads(self.read(self.t.config))["route"], False)
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "0")

    def test_on_refuses_without_resolver(self):
        os.remove(self.t.home_lib)
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("agent-model.sh", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_without_installed_router(self):
        os.remove(self.t.skill_file)
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("not installed", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_a_pre_v4_4_model_floor(self):
        os.makedirs(self.t.repo + "/hooks")
        self.write(self.t.repo + "/hooks/model-floor.sh", b"#!/usr/bin/env bash\n# v4.3.0 copy, no shared lib\n")
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("predates v4.4.0", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_a_non_object_settings_file(self):
        self.write(self.t.settings, b"[1, 2]")
        rc, _ = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (1, b"[1, 2]"))
        self.assertFalse(os.path.exists(self.t.config))

    def test_status_never_prints_the_key(self):
        env = self.t.env()
        env["TYPESAFE_API_KEY"] = "env-secret-4567"
        self.ctl("on", env=env)
        _, text = self.ctl("status", env=env, registry=lambda: "hkcu-secret-8910")
        self.assertNotIn("env-secret-4567", text)
        self.assertNotIn("hkcu-secret-8910", text)
        self.assertIn("TYPESAFE_API_KEY: set (environment)", text)
        self.assertIn("routing spawns in this checkout: yes", text)
        del env["TYPESAFE_API_KEY"]
        _, text = self.ctl("status", env=env, registry=lambda: "hkcu-secret-8910")
        self.assertNotIn("hkcu-secret-8910", text)
        self.assertIn("TYPESAFE_API_KEY: set (HKCU\\Environment)", text)

    def _events(self, evs):
        d = self.t.gd + "/jev/events"
        os.makedirs(d, exist_ok=True)
        for i, ev in enumerate(evs):
            self.write("{}/20261002T10000{}000000Z-{}.json".format(d, i, i), json.dumps(ev).encode("utf-8"))

    def test_report_summarises_events(self):
        self._events([
            dict(EV, choice="opus", confidence=0.95, applied=True, reason="applied", emitted="opus"),
            dict(EV, subagent_type="coder", kind="own", default="opus", choice="sonnet", confidence=0.9,
                 applied=True, reason="applied", emitted="sonnet"),
            dict(EV, reason="explicit"),
            dict(EV, choice="haiku", confidence=0.6, reason="low-confidence", emitted="sonnet",
                 agent_effort="high", effort_choice="medium"),
        ])
        rc, text = self.ctl("report")
        self.assertEqual(rc, 0, text)
        for line in ("jev report: 4 spawns seen", "applied: 2 (up 1, down 1)",
                     "not applied: explicit 1, low-confidence 1",
                     "model confidence: <0.5: 0, 0.5-0.8: 1, >=0.8: 2",
                     "differs from the agent file's effort: 1 of 1"):
            self.assertIn(line, text)

    def test_report_joins_retro_ledger_rows(self):
        self._events([dict(EV, subagent_type="coder", kind="own", default="opus", choice="sonnet",
                           confidence=0.9, applied=True, reason="applied", emitted="sonnet")])
        top = jc.locate(self.t.repo)[0]
        base = jc._local(EV["ts"]).replace(second=0, microsecond=0)
        row = (base + datetime.timedelta(minutes=5)).strftime("%Y-%m-%d %H:%M") + \
            " | coder | agent-x | dead=[] | blocks=[x.sh] | budget=0 | errors=1"
        far = (base + datetime.timedelta(hours=3)).strftime("%Y-%m-%d %H:%M") + " | coder | agent-y | dead=[] | blocks=[] | budget=0 | errors=1"
        other = (base + datetime.timedelta(minutes=5)).strftime("%Y-%m-%d %H:%M") + " | tester | agent-z | dead=[] | blocks=[] | budget=0 | errors=1"
        ledger = "{}/.claude/projects/{}/memory".format(self.t.home, jc.ledger_slug(top))
        os.makedirs(ledger)
        self.write(ledger + "/retro.md", "\n".join([row, far, other, ""]).encode("utf-8"))
        _, text = self.ctl("report")
        self.assertIn("after a routed spawn of the same type: 1 (", text)
        self.assertIn(row, text)
        self.assertNotIn("agent-y", text)
        self.assertNotIn("agent-z", text)


if __name__ == "__main__":
    unittest.main()
