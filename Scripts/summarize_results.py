#!/usr/bin/env python3
"""Turn an evaluation report exported by the app into Markdown tables.

The app (Evaluate tab) writes one JSON report per evaluation. This script reads it and prints:
run information, headline numbers, outcome counts per field, results per scenario and per
phrasing pool, how stable the answers are across the runs, and every failing statement with
what was expected and what the model returned. Standard library only.

Usage: python3 Scripts/summarize_results.py Results/baseline-<model>-<date>.json > tables.md
"""
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
KEYS = [
    "revenue", "revenueGrowth", "operatingIncome", "operatingIncomeGrowth",
    "netIncome", "netIncomeGrowth", "previousYearNetIncome",
]
OUTCOMES = ["correct", "hallucinated", "missed", "wrongValue", "signError", "unitError", "unparsed"]


def pct(part, whole):
    return f"{100 * part / whole:.1f}%" if whole else "n/a"


def fmt(value):
    return "null" if value is None else f"{value:g}"


def load_statements():
    """Statement text per line of Dataset/test.jsonl (the report only stores example ids)."""
    template = (ROOT / "Dataset" / "prompt_template.txt").read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    statements = {}
    lines = (ROOT / "Dataset" / "test.jsonl").read_text().splitlines()
    for number, line in enumerate(lines, start=1):
        user = json.loads(line)["messages"][1]["content"]
        statements[number] = user[len(prefix):len(user) - len(suffix)]
    return statements


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(out)


def stats(records):
    """The same numbers the app shows for a set of records."""
    n = len(records)
    fields = Counter()
    for r in records:
        fields.update(r["fields"].values())
    return {
        "n": n,
        "valid": sum(r["isValidJSON"] for r in records),
        "schema": sum(r["isSchemaValid"] for r in records),
        "fenced": sum(r["hadFence"] for r in records),
        "full": sum(all(v == "correct" for v in r["fields"].values()) for r in records),
        "correct_fields": fields["correct"],
        "fields": n * len(KEYS),
        "outcomes": fields,
    }


def main(path):
    report = json.loads(Path(path).read_text())
    meta, records = report["metadata"], report["records"]
    statements = load_statements()
    s = stats(records)
    generations = [r["generation"] for r in records if "generation" in r]

    def median(values):
        values = sorted(values)
        mid = len(values) // 2
        return (values[mid - 1] + values[mid]) / 2 if len(values) % 2 == 0 else values[mid]

    print("## Run\n")
    print(table(["", ""], [
        ["Model", meta["model"]],
        ["Device", f'{meta["device"]}, {meta["system"]}'],
        ["Date", meta["date"]],
        ["Statements x runs", f'{meta["examples"]} x {meta["runs"]} = {s["n"]} answers'],
        ["Seeds", ", ".join(map(str, meta["seeds"]))],
        ["Temperature / max tokens", f'{meta["temperature"]} / {meta["maxTokens"]}'],
        ["Prompt hash (SHA-256)", f'`{meta["promptHash"][:16]}...`'],
        ["Test set hash (SHA-256)", f'`{meta["testSetHash"][:16]}...`'],
        ["Model load (first launch includes download)", f'{meta["modelLoadSeconds"]:.1f} s' if meta.get("modelLoadSeconds") else "n/a"],
    ]))

    print("\n## Headline\n")
    print(table(["Measure", "Count", "Share"], [
        ["Valid JSON (the app's decoder can read it)", f'{s["valid"]} / {s["n"]}', pct(s["valid"], s["n"])],
        ["Exactly the 7 keys, number or null", f'{s["schema"]} / {s["n"]}', pct(s["schema"], s["n"])],
        ["All 7 fields correct", f'{s["full"]} / {s["n"]}', pct(s["full"], s["n"])],
        ["Fields correct", f'{s["correct_fields"]} / {s["fields"]}', pct(s["correct_fields"], s["fields"])],
        ["Needed a code fence", f'{s["fenced"]} / {s["n"]}', pct(s["fenced"], s["n"])],
    ]))

    print("\n## Performance on the device\n")
    print(table(["Measure", "Value"], [
        ["Median time per statement", f'{median([g["totalTime"] for g in generations]):.1f} s'],
        ["Median time to first token", f'{median([g["promptTime"] for g in generations]):.2f} s'],
        ["Median tokens per second", f'{median([g["tokensPerSecond"] for g in generations]):.1f}'],
        ["Median generated tokens", f'{median([g["generatedTokens"] for g in generations]):.0f}'],
        ["Peak MLX memory", f'{max(g["peakMemory"] for g in generations) / 2**20:.0f} MB'],
        ["Highest thermal state (0 nominal, 3 critical)", max(max(r["thermalBefore"], r["thermalAfter"]) for r in records)],
        ["Generation failures", sum("generation" not in r for r in records)],
    ]))

    print("\n## Outcome per field (all answers)\n")
    rows = []
    for key in KEYS:
        c = Counter(r["fields"][key] for r in records)
        rows.append([key] + [c[o] for o in OUTCOMES] + [pct(c["correct"], s["n"])])
    print(table(["Field"] + OUTCOMES + ["Accuracy"], rows))
    print("\n" + ", ".join(f"{o} {s['outcomes'][o]}" for o in OUTCOMES if o != "correct" and s["outcomes"][o]))

    for title, key in (("scenario", "scenario"), ("phrasing pool (B = wording not in train or valid)", "pool")):
        print(f"\n## By {title}\n")
        groups = defaultdict(list)
        for r in records:
            groups[r[key]].append(r)
        rows = []
        for name in sorted(groups):
            g = stats(groups[name])
            rows.append([name, g["n"], f'{g["full"]} ({pct(g["full"], g["n"])})', pct(g["correct_fields"], g["fields"])])
        print(table([key.capitalize(), "Answers", "All 7 correct", "Fields correct"], rows))

    print("\n## Stability across the runs\n")
    by_example = defaultdict(list)
    for r in records:
        by_example[r["exampleID"]].append(r)
    identical = sum(len({json.dumps(r.get("extracted"), sort_keys=True) for r in rs}) == 1 for rs in by_example.values())
    always = sum(all(all(v == "correct" for v in r["fields"].values()) for r in rs) for rs in by_example.values())
    never = sum(not any(all(v == "correct" for v in r["fields"].values()) for r in rs) for rs in by_example.values())
    total = len(by_example)
    print(table(["Statements", "Count"], [
        ["Same extracted values in every run", f"{identical} / {total}"],
        ["Fully correct in every run", f"{always} / {total}"],
        ["Never fully correct", f"{never} / {total}"],
        ["Fully correct in some runs only", f"{total - always - never} / {total}"],
    ]))

    print("\n## Failing statements\n")
    print("`expected -> got`, for the first failing run of each statement. The count is the number of runs "
          f"(out of {meta['runs']}) that were not fully correct.\n")
    for example_id in sorted(by_example):
        rs = by_example[example_id]
        failed = [r for r in rs if not all(v == "correct" for v in r["fields"].values())]
        if not failed:
            continue
        first = failed[0]
        print(f"### Statement {example_id} ({first['scenario']}, pool {first['pool']}): {len(failed)} of {len(rs)} runs failed\n")
        print(f"> {statements[example_id]}\n")
        if not first["isValidJSON"] or not first["isSchemaValid"]:
            print(f"- answer not readable: {first.get('parseFailure') or first.get('generationError')}")
        for key in KEYS:
            outcome = first["fields"][key]
            if outcome != "correct":
                print(f"- `{key}` ({outcome}): {fmt(first['expected'].get(key))} -> "
                      f"{fmt((first.get('extracted') or {}).get(key))}")
        print()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
