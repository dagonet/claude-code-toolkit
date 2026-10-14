"""/jev on | off | status | report (v4.4.0 Task 8)."""
import base64
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

# What a v4 `/jev on` wrote as its SessionStart entry (the plugin's hooks/jev-notice.sh prints the notice now).
V4_SESSION_COMMAND = 'f="$HOME/.claude/skills/jev/jev_route.py"; [ -f "$f" ] && echo "Jev routing is ON in this repo (/jev on): omit model on Agent spawns -- Jev picks one per launch (user ruling U-1; an explicit model is never changed). /jev off restores naming it."; exit 0'

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

    def legacy_on(self, original=None):
        """What a v4 `/jev on` left behind: the registration, a snapshot of the bytes before it, a config."""
        before = original
        obj = jc.parse_settings(before)
        hooks = obj.setdefault("hooks", {})
        hooks.setdefault("PreToolUse", []).append({"matcher": "Agent", "hooks": [
            {"type": "command", "command": jc.REG_COMMAND, "timeout": 5}]})
        hooks.setdefault("SessionStart", []).append({"hooks": [
            {"type": "command", "command": V4_SESSION_COMMAND, "timeout": 5}]})
        snap = {"existed": before is not None, "before_b64": base64.b64encode(before or b"").decode("ascii"), "after": obj}
        top, gd = jc.locate(self.t.repo, self.t.env())
        jc._write(jc._snapshot_path(gd, top), jc._dumps(snap))
        jc._write(self.t.settings, jc._dumps(obj))
        jc._write(self.t.config, jc._dumps(jc.CONFIG_ON))

    def test_on_writes_config_and_nothing_else(self):
        rc, text = self.ctl("on")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.config)), jc.CONFIG_ON)
        self.assertEqual(json.loads(self.read(self.t.config))["threshold"], 0.65)
        self.assertIn("any model", text)
        self.assertNotIn("one step", text)
        self.assertFalse(os.path.exists(self.t.settings))  # v5: the plugin registers Jev, not this checkout
        self.assertFalse(os.path.exists(self.t.gd + "/info/exclude")
                         and b"settings.local.json" in self.read(self.t.gd + "/info/exclude"))
        self.assertIn("omit `model`", text)
        self.assertIn("/cct:jev off", text)
        self.assertNotIn(" /jev ", text)

    def test_on_twice_is_idempotent(self):
        self.ctl("on")
        first = self.read(self.t.config)
        rc, _ = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.config)), (0, first))
        self.assertFalse(os.path.exists(self.t.settings))

    def test_on_leaves_an_unrelated_settings_file_alone(self):
        mine = b'{"permissions": {"allow": ["Bash(ls)"]}}'
        self.write(self.t.settings, mine)
        rc, _ = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (0, mine))

    def test_on_drops_a_v4_registration(self):
        original = b'{"permissions": {"allow": ["Bash(ls)"]}}\n'
        self.write(self.t.settings, original)
        self.legacy_on(original)
        rc, text = self.ctl("on")
        self.assertEqual((rc, self.read(self.t.settings)), (0, original), text)
        self.assertEqual(json.loads(self.read(self.t.config)), jc.CONFIG_ON)

    def test_round_trip_restores_existing_bytes(self):
        original = ('\ufeff{\r\n  "permissions": {"allow": ["Bash(ls)"]},\r\n  "hooks": {"PreToolUse": '
                    '[{"matcher": "Agent", "hooks": [{"type": "command", "command": "echo mine"}]}]}\r\n}\r\n').encode("utf-8")
        self.write(self.t.settings, original)
        self.legacy_on(original)
        self.assertNotEqual(self.read(self.t.settings), original)
        rc, text = self.ctl("off")
        self.assertEqual((rc, self.read(self.t.settings)), (0, original), text)

    def test_round_trip_deletes_a_file_the_v4_on_created(self):
        self.legacy_on(None)
        self.assertTrue(os.path.exists(self.t.settings))
        _, text = self.ctl("off")
        self.assertFalse(os.path.exists(self.t.settings))
        self.assertIn("name `model` on every Agent spawn again", text)  # U-1: the rule returns

    def test_off_without_a_v4_registration_touches_no_settings(self):
        self.ctl("on")
        rc, _ = self.ctl("off")
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(self.t.settings))

    def test_off_after_user_edit_removes_only_the_jev_entry(self):
        self.legacy_on(None)
        obj = json.loads(self.read(self.t.settings))
        obj["permissions"] = {"allow": ["Bash(git status)"]}
        self.write(self.t.settings, json.dumps(obj).encode("utf-8"))
        rc, text = self.ctl("off")
        self.assertEqual(rc, 0, text)
        self.assertEqual(json.loads(self.read(self.t.settings)), {"permissions": {"allow": ["Bash(git status)"]}})
        self.assertIn("removed only the Jev entry", text)

    def test_off_writes_route_false_before_touching_settings(self):
        self.legacy_on(None)
        self.write(self.t.settings, b"[1, 2]")  # off cannot parse this: the switch must already be false
        rc, _ = self.ctl("off")
        self.assertEqual(rc, 1)
        self.assertIs(json.loads(self.read(self.t.config))["route"], False)

    def test_usage_names_the_plugin_command(self):
        rc, text = self.ctl("bogus")
        self.assertEqual(rc, 2)
        self.assertIn("/cct:jev on | off | status | report", text)

    def test_off_sets_route_false_and_the_floor_returns(self):
        self.ctl("on")
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "1")
        self.ctl("off")
        self.assertIs(json.loads(self.read(self.t.config))["route"], False)
        self.assertEqual(self.t.lib_cli("general-purpose").split()[2], "0")

    def elsewhere(self, router):
        """Point jev_ctl at a copy of itself outside the plugin: no resolver above it, a router only if asked."""
        d = os.path.join(os.path.dirname(self.t.repo), "ctlcopy", "skills", "jev")
        os.makedirs(d)
        if router:
            open(os.path.join(d, "jev_route.py"), "w").close()
        real, jc.HERE = jc.HERE, d
        self.addCleanup(setattr, jc, "HERE", real)
        real_file = jc.jev_route.__file__  # resolver_candidates looks for the plugin's own lib next to the router
        jc.jev_route.__file__ = os.path.join(d, "jev_route.py")
        self.addCleanup(setattr, jc.jev_route, "__file__", real_file)

    def test_on_refuses_without_resolver(self):
        self.elsewhere(router=True)
        os.remove(self.t.home_lib)
        rc, text = self.ctl("on")
        self.assertEqual(rc, 1)
        self.assertIn("agent-model.sh", text)
        self.assertFalse(os.path.exists(self.t.settings) or os.path.exists(self.t.config))

    def test_on_refuses_without_installed_router(self):
        self.elsewhere(router=False)
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
        rc, _ = self.ctl("on")  # on looks for a v4 registration, so it must read the file
        self.assertEqual((rc, self.read(self.t.settings)), (1, b"[1, 2]"))
        self.assertFalse(os.path.exists(self.t.config))

    def test_status_never_prints_the_key(self):
        env = self.t.env()
        env["TYPESAFE_API_KEY"] = "env-secret-4567"
        seen, real = [], jc.subprocess.run

        def spy(*a, **kw):
            seen.append(kw.get("env"))
            return real(*a, **kw)

        jc.subprocess.run = spy
        try:
            self.ctl("on", env=env)
            _, text = self.ctl("status", env=env, registry=lambda: "hkcu-secret-8910")
        finally:
            jc.subprocess.run = real
        self.assertTrue(seen)  # MH-1: no subprocess (git, check-ignore, resolver) is handed the key
        self.assertFalse(any(e is None or "TYPESAFE_API_KEY" in e for e in seen))
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
                 agent_effort="high", effort_choice="medium", effort_emitted="medium", effort_reason="applied"),
        ])
        rc, text = self.ctl("report")
        self.assertEqual(rc, 0, text)
        for line in ("jev report: 4 spawns seen", "applied: 2 (up 1, down 1)",
                     "not applied: explicit 1, low-confidence 1",
                     "model confidence: <0.5: 0, 0.5-0.8: 1, >=0.8: 2",
                     "differs from the agent file's effort: 1 of 1",
                     "effort applied: 1 of 4"):
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
