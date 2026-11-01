#!/usr/bin/env python3
"""Counts of every core-prompt report of the Phase 2d comparison, side by side, and nothing else: no statement, no label,
no model answer (the real-style sets are private, Specs/phase-2b-lora-wording.md D28). Standard library only.

It reads every report in Results/ and in RealSet/reports/ (git-ignored, present on the author's Mac) whose prompt hash is the
core prompt of schema 1 (`7779853b346c`) and whose answer count is complete, and prints one line per (model, set) with:
answers, decodable answers, fully correct answers, invented values (hallucinated), missed values, other wrong fields,
undecodable answers, median time per statement, peak memory, highest thermal state.

Usage: python3 Scripts/phase2d_table.py [--all]      (--all also lists the file name of every report)
"""
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROMPT = "7779853b346c"
ANSWERS = {"test": 90, "test2": 90, "test3": 90, "real1": 63, "real2": 30, "real3": 36}
SETS = ["test", "test2", "test3", "real1", "real2", "real3"]
MODELS = ["none", "lora-v1", "lora-v2", "lora-v2-s2", "lora-v2-s3", "lora-v3", "lora-v3-s2", "lora-v3-s3"]
THERMAL = {0: "nominal", 1: "fair", 2: "serious", 3: "critical"}


def row(report):
    meta, recs, summary = report["metadata"], report["records"], report["summary"]
    outcomes = [v for x in recs for v in x["fields"].values()]
    full = sum(1 for x in recs if x["isValidJSON"] and x["isSchemaValid"] and all(v == "correct" for v in x["fields"].values()))
    decodable = sum(1 for x in recs if x["isValidJSON"] and x["isSchemaValid"])
    invented = outcomes.count("hallucinated")
    missed = outcomes.count("missed")
    other = sum(1 for v in outcomes if v not in ("correct", "hallucinated", "missed", "unparsed"))
    peak = summary["peakMemory"]
    return {
        "answers": len(recs), "decodable": decodable, "full": full, "invented": invented, "missed": missed,
        "other": other, "undecodable": len(recs) - decodable, "time": summary["medianTotalTime"],
        "memory": peak / 2**30 if peak > 1000 else peak, "thermal": summary["maxThermalState"],
    }


def collect():
    found = defaultdict(list)
    for folder in (ROOT / "Results", ROOT / "RealSet" / "reports"):
        if not folder.exists():
            continue
        for path in sorted(folder.glob("*.json")):
            try:
                report = json.loads(path.read_text())
                meta = report["metadata"]
            except (ValueError, KeyError, TypeError):
                continue
            if not str(meta.get("promptHash", "")).startswith(PROMPT) or meta.get("tier", "core") != "core":
                continue
            name = (meta.get("adapter") or {}).get("name", "none")
            which = meta.get("evaluationSet", "test")
            if which not in ANSWERS or len(report["records"]) != ANSWERS[which]:
                continue
            found[(name, which)].append((path, report))
    return found


def main():
    show_files = "--all" in sys.argv
    found = collect()
    print(f"{'model':11s} {'set':6s} {'answers':>7s} {'decod.':>6s} {'full':>5s} {'invent.':>7s} {'missed':>6s} {'other':>5s} "
          f"{'undec.':>6s} {'median s':>8s} {'GiB':>5s} {'thermal':>8s}")
    for which in SETS:
        for model in MODELS:
            for path, report in found.get((model, which), []):
                r = row(report)
                print(f"{model:11s} {which:6s} {r['answers']:7d} {r['decodable']:6d} {r['full']:5d} {r['invented']:7d} {r['missed']:6d} "
                      f"{r['other']:5d} {r['undecodable']:6d} {r['time']:8.1f} {r['memory']:5.2f} {THERMAL.get(r['thermal'], r['thermal']):>8s}"
                      + (f"  {path.name}" if show_files else ""))
        print()


if __name__ == "__main__":
    main()
