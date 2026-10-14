"""scripts/jev-tally.py: the cross-machine trial tally (v5.1)."""
import importlib.util
import json
import os
import shutil
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "..", "..", "scripts", "jev-tally.py")


def load():
    spec = importlib.util.spec_from_file_location("jev_tally", SCRIPT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TallyTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp(prefix="jev-tally-")
        self.addCleanup(shutil.rmtree, self.root, True)
        self.t = load()

    def ev(self, repo, name, **kw):
        d = os.path.join(self.root, repo, ".git", "jev", "events")
        os.makedirs(d, exist_ok=True)
        base = {"ts": "2026-10-20T10:00:00.000Z", "subagent_type": "coder", "kind": "own", "default": "sonnet",
                "choice": "opus", "confidence": 0.9, "applied": True, "reason": "applied", "emitted": "opus",
                "latency_s": 0.3, "effort_emitted": None}
        base.update(kw)
        with open(os.path.join(d, name), "w") as fh:
            json.dump(base, fh)

    def test_counts_applied_up_and_reasons(self):
        self.ev("a", "1.json")
        self.ev("a", "2.json", applied=False, reason="low-confidence", emitted=None, confidence=0.5)
        self.ev("b", "3.json", default="opus", emitted="sonnet", effort_emitted="high")
        r = self.t.tally([self.root], None)
        self.assertEqual((r["events"], r["repos"], r["applied"], r["up"], r["down"]), (3, 2, 2, 1, 1))
        self.assertEqual(r["not_applied"], {"low-confidence": 1})
        self.assertEqual(r["effort_applied"], 1)

    def test_since_filters_by_date(self):
        self.ev("a", "1.json", ts="2026-10-01T10:00:00.000Z")
        self.ev("a", "2.json")
        self.assertEqual(self.t.tally([self.root], "2026-10-15")["events"], 1)

    def test_corrupt_event_skipped_and_counted(self):
        self.ev("a", "1.json")
        with open(os.path.join(self.root, "a", ".git", "jev", "events", "bad.json"), "w") as fh:
            fh.write("{not json")
        r = self.t.tally([self.root], None)
        self.assertEqual((r["events"], r["skipped_files"]), (1, 1))

    def test_empty_root_is_zero_not_a_crash(self):
        self.assertEqual(self.t.tally([self.root], None)["events"], 0)
