#!/usr/bin/env python3
"""Cross-machine tally of the Jev router's per-spawn event files (v5.1).

Usage: python3 scripts/jev-tally.py [--since YYYY-MM-DD] [--threshold N] [ROOT ...]

A root's events are <root>/*/.git/jev/events/*.json (default ROOT: ~/git; the PC
passes G:/git). Read-only; events hold decisions and confidences, never prompt
text or env values, so the report prints none.
"""
import argparse
import datetime
import glob
import json
import os
import statistics
import sys
from collections import Counter

sys.dont_write_bytecode = True

ORDER = ("haiku", "sonnet", "opus", "fable")
BASELINE = ("baseline 2026-10-14 (both machines): 582 events, 4 applied (0.7%), "
            "low-confidence 40%, egress-refused 33%, kept 26%")


def _rank(model):
    m = (model or "").lower()
    for i, name in enumerate(ORDER):
        if name in m:
            return i
    return -1


def _load_events(roots, since):
    events, skipped = [], 0
    for root in roots:
        pattern = os.path.join(os.path.expanduser(root), "*", ".git", "jev", "events", "*.json")
        for path in sorted(glob.glob(pattern)):
            repo = path.replace("\\", "/").split("/")[-5]
            try:
                with open(path, encoding="utf-8") as fh:
                    e = json.load(fh)
                if not isinstance(e, dict) or not isinstance(e.get("ts"), str):
                    raise ValueError("not an event")
                ts = e["ts"]
            except (OSError, ValueError):
                skipped += 1
                continue
            if since and ts[:10] < since:
                continue
            e["_repo"] = repo
            events.append(e)
    return events, skipped


def _median(xs):
    return round(statistics.median(xs), 2) if xs else None


def tally(roots, since, threshold=0.65):
    events, skipped = _load_events(roots, since)
    applied = [e for e in events if e.get("applied") is True]
    confs = [e["confidence"] for e in events
             if isinstance(e.get("confidence"), (int, float)) and not isinstance(e["confidence"], bool)]
    lat = sorted(e["latency_s"] for e in events
                 if isinstance(e.get("latency_s"), (int, float)) and not isinstance(e["latency_s"], bool))
    return {
        "events": len(events),
        "repos": len({e["_repo"] for e in events}),
        "first": min((e["ts"] for e in events), default=None),
        "last": max((e["ts"] for e in events), default=None),
        "per_repo": dict(Counter(e["_repo"] for e in events).most_common()),
        "per_day": dict(sorted(Counter(e["ts"][:10] for e in events).items())),
        "applied": len(applied),
        "up": sum(_rank(e.get("emitted")) > _rank(e.get("default")) for e in applied),
        "down": sum(_rank(e.get("emitted")) < _rank(e.get("default")) for e in applied),
        "not_applied": dict(Counter(e.get("reason") for e in events
                                    if e.get("applied") is not True).most_common()),
        "confidence": {"lt05": sum(c < 0.5 for c in confs),
                       "05_t": sum(0.5 <= c < threshold for c in confs),
                       "ge_t": sum(c >= threshold for c in confs),
                       "median": _median(confs)},
        "effort_applied": sum(1 for e in events if e.get("effort_emitted")),
        "effort_events": sum(1 for e in events if "effort_emitted" in e),
        "latency": {"median": _median(lat),
                    "p95": round(lat[int(0.95 * (len(lat) - 1))], 2) if lat else None,
                    "max": round(lat[-1], 2) if lat else None},
        "skipped_files": skipped,
    }


def report(r, threshold):
    out = ["events %d in %d repos, %s to %s" % (r["events"], r["repos"], r["first"], r["last"]),
           "per repo: %s" % r["per_repo"],
           "per day: %s" % r["per_day"],
           "applied %d (up %d, down %d, same %d)" % (r["applied"], r["up"], r["down"],
                                                    r["applied"] - r["up"] - r["down"]),
           "not applied: %s" % r["not_applied"]]
    c = r["confidence"]
    out.append("confidence <0.5: %d, 0.5-%s: %d, >=%s: %d, median %s"
               % (c["lt05"], threshold, c["05_t"], threshold, c["ge_t"], c["median"]))
    out.append("effort applied %d (of %d events carrying the field)" % (r["effort_applied"], r["effort_events"]))
    lt = r["latency"]
    out.append("latency_s median %s, p95 %s, max %s" % (lt["median"], lt["p95"], lt["max"]))
    out.append("skipped files %d" % r["skipped_files"])
    out.append(BASELINE)
    return "\n".join(out)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Cross-machine Jev trial tally")
    ap.add_argument("roots", nargs="*", default=["~/git"], help="clone roots (default ~/git)")
    ap.add_argument("--since", type=lambda s: datetime.date.fromisoformat(s).isoformat(),
                    help="only events on or after YYYY-MM-DD")
    ap.add_argument("--threshold", type=float, default=0.65, help="confidence threshold (default 0.65)")
    a = ap.parse_args(argv)
    print(report(tally(a.roots, a.since, a.threshold), a.threshold))
    return 0


if __name__ == "__main__":
    sys.exit(main())
