#!/usr/bin/env python3
"""Counts of one or more evaluation reports, and nothing else: no statement, no label, no model answer.

For the real-style sets, whose text is never committed (Specs/phase-2b-lora-wording.md, D28), only these numbers
may go into the repository. Standard library only.

Usage: python3 Scripts/report_counts.py <report.json> [<report.json> ...]
"""
import json
import sys
from collections import Counter
from pathlib import Path


def counts(path):
    r = json.loads(Path(path).read_text())
    meta, recs = r["metadata"], r["records"]
    n = len(recs)
    outcomes = Counter(o for x in recs for o in x["fields"].values())
    total = sum(outcomes.values())
    stated = sum(1 for x in recs for k, v in x["expected"]["texts"].items())
    times = sorted(x["generation"]["totalTime"] for x in recs if x["generation"])
    return {
        "file": Path(path).name,
        "set": meta.get("evaluationSet", "test"),
        "adapter": (meta.get("adapter") or {}).get("name", "none"),
        "answers": n,
        "statements": meta["examples"],
        "decodable": sum(1 for x in recs if x["isValidJSON"] and x["isSchemaValid"]),
        "fully correct": sum(1 for x in recs if x["isSchemaValid"] and all(v == "correct" for v in x["fields"].values())),
        "fields correct": f"{outcomes['correct']} / {total}",
        "fields stated (labels, over all answers)": stated,
        **{f"fields {k}": c for k, c in sorted(outcomes.items()) if k != "correct"},
        "median time per statement (s)": round(times[len(times) // 2], 1) if times else None,
        "median prompt tokens": sorted(x["generation"]["promptTokens"] for x in recs if x["generation"])[n // 2],
        "peak memory (GiB)": round(max(x["generation"]["peakMemory"] for x in recs if x["generation"]) / 2**30, 2),
        "highest thermal state": max(x["thermalAfter"] for x in recs),
        "prompt hash": meta["promptHash"][:12],
        "set hash": meta["testSetHash"][:12],
    }


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    for path in sys.argv[1:]:
        for key, value in counts(path).items():
            print(f"{key:44s} {value}")
        print()


if __name__ == "__main__":
    main()
