"""scripts/jev-tally.py: the cross-machine trial tally (v5.1)."""
import contextlib
import importlib.util
import io
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
        for k in kw.pop("drop", ()):
            base.pop(k, None)
        base.update(kw)
        with open(os.path.join(d, name), "w") as fh:
            json.dump(base, fh)

    def test_counts_applied_up_and_reasons(self):
        self.ev("a", "1.json")
        self.ev("a", "2.json", applied=False, reason="low-confidence", emitted=None, confidence=0.5)
        self.ev("b", "3.json", default="opus", emitted="sonnet", effort_emitted="high")
        self.ev("b", "4.json", default="claude-opus-4-1", emitted="fable")
        self.ev("b", "5.json", default="claude-opus-4-1", emitted="opus")
        r = self.t.tally([self.root], None)
        self.assertEqual((r["events"], r["repos"], r["applied"], r["up"], r["down"]), (5, 2, 4, 2, 1))
        self.assertEqual(r["not_applied"], {"low-confidence": 1})
        self.assertEqual(r["effort_applied"], 1)

    def test_since_filters_by_date(self):
        self.ev("a", "1.json", ts="2026-10-01T10:00:00.000Z")
        self.ev("a", "0.json", ts="2026-10-14T23:59:59.999Z")
        self.ev("a", "3.json", ts="2026-10-15T00:00:00.000Z")
        self.ev("a", "2.json")
        r = self.t.tally([self.root], "2026-10-15")
        self.assertEqual(r["per_day"], {"2026-10-15": 1, "2026-10-20": 1})

    def test_stats_buckets_latency_repos_span_effort(self):
        rows = [("x", 0.49, 0.1, "2026-10-12T08:00:00.000Z"), ("x", 0.5, 0.2, "2026-10-11T08:00:00.000Z"),
                ("x", 0.64, 0.3, "2026-10-13T08:00:00.000Z"), ("y", 0.65, 0.4, "2026-10-12T09:00:00.000Z"),
                ("y", 0.9, 1.0, "2026-10-14T08:00:00.000Z")]
        for i, (repo, c, lat, ts) in enumerate(rows):
            self.ev(repo, "%d.json" % i, confidence=c, latency_s=lat, ts=ts,
                    drop=("effort_emitted",) if i == 0 else ())
        r = self.t.tally([self.root], None, 0.65)
        self.assertEqual(r["confidence"], {"lt05": 1, "05_t": 2, "ge_t": 2, "median": 0.64})
        r8 = self.t.tally([self.root], None, 0.8)
        self.assertEqual(r8["confidence"], {"lt05": 1, "05_t": 3, "ge_t": 1, "median": 0.64})
        self.assertEqual(r["latency"], {"median": 0.3, "p95": 0.4, "max": 1.0})
        self.assertEqual(r["per_repo"], {"x": 3, "y": 2})
        self.assertEqual((r["first"], r["last"]), ("2026-10-11T08:00:00.000Z", "2026-10-14T08:00:00.000Z"))
        self.assertEqual(r["per_day"], {"2026-10-11": 1, "2026-10-12": 2, "2026-10-13": 1, "2026-10-14": 1})
        self.assertEqual(r["effort_events"], 4)

    def test_non_event_files_skipped_not_crash(self):
        self.ev("a", "1.json")
        d = os.path.join(self.root, "a", ".git", "jev", "events")
        with open(os.path.join(d, "list.json"), "w") as fh:
            fh.write("[1, 2]")
        with open(os.path.join(d, "nots.json"), "w") as fh:
            fh.write('{"applied": true}')
        with open(os.path.join(d, "nullts.json"), "w") as fh:
            fh.write('{"ts": null}')
        r = self.t.tally([self.root], None)
        self.assertEqual((r["events"], r["skipped_files"]), (1, 3))

    def test_since_rejects_loose_dates(self):
        for bad in ("2026-10-9", "2026/10/13"):
            with self.assertRaises(SystemExit), contextlib.redirect_stderr(io.StringIO()):
                self.t.main(["--since", bad, self.root])

    def test_corrupt_event_skipped_and_counted(self):
        self.ev("a", "1.json")
        with open(os.path.join(self.root, "a", ".git", "jev", "events", "bad.json"), "w") as fh:
            fh.write("{not json")
        r = self.t.tally([self.root], None)
        self.assertEqual((r["events"], r["skipped_files"]), (1, 1))

    def test_empty_root_is_zero_not_a_crash(self):
        self.assertEqual(self.t.tally([self.root], None)["events"], 0)
