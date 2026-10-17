#!/usr/bin/env python3
"""Compare two evaluation reports: the v1.1.0 baseline (7 numeric fields) and a schema version 1 baseline.

The two runs are different experiments: the prompt, the output format (numbers against strings
copied as printed), the fields (7 against 13) and the statements all changed. So this prints
side by side what can be put side by side, and says what cannot:

  - the headline measures of each run,
  - the six fields that exist in both runs, one by one (indicative only: other statements),
  - how the mistakes are spread, per kind,
  - what the run cost on the device.

Standard library only.

If the first report is a v1.1.0 report, it prints the side by side of v1.1.0 and schema version 1. If both are
reports of the same schema and tier (for example the base model and a LoRA adapter), it prints a field by field
comparison: what changed between the runs, the headline, each field, and which wrong fields became right and
which right fields became wrong, answer by answer.

Usage: python3 Scripts/compare_baselines.py OLD_REPORT.json NEW_REPORT.json > comparison.md
"""
import json
import sys
from collections import Counter
from pathlib import Path

OLD_FIELDS = [
    "revenue", "revenueGrowth", "operatingIncome", "operatingIncomeGrowth",
    "netIncome", "netIncomeGrowth", "previousYearNetIncome",
]
SHARED = ["revenue", "operatingIncome", "netIncome", "previousYearNetIncome", "revenueGrowth", "netIncomeGrowth"]
KINDS = ["hallucinated", "missed", "wrongValue", "signError", "unitError", "unreadable", "unparsed"]


def pct(part, whole):
    return f"{100 * part / whole:.1f}%" if whole else "n/a"


def median(values):
    values = sorted(values)
    if not values:
        return 0.0
    mid = len(values) // 2
    return (values[mid - 1] + values[mid]) / 2 if len(values) % 2 == 0 else values[mid]


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(out)


def load(path):
    report = json.loads(Path(path).read_text())
    meta, records = report["metadata"], report["records"]
    keys = meta.get("keys") or meta.get("coreKeys") or OLD_FIELDS
    n = len(records)
    fields = Counter()
    for r in records:
        fields.update(r["fields"].values())
    generations = [r["generation"] for r in records if "generation" in r]
    return {
        "meta": meta, "records": records, "keys": keys, "n": n, "fields": fields,
        "valid": sum(r["isValidJSON"] for r in records),
        "schema": sum(r["isSchemaValid"] for r in records),
        "fenced": sum(r["hadFence"] for r in records),
        "full": sum(all(v == "correct" for v in r["fields"].values()) for r in records),
        "full_tolerant": sum(all(v in ("correct", "unitError") for v in r["fields"].values()) for r in records),
        "per_field": {k: Counter(r["fields"].get(k) for r in records) for k in keys},
        "time": median([g["totalTime"] for g in generations]),
        "first": median([g["promptTime"] for g in generations]),
        "speed": median([g["tokensPerSecond"] for g in generations]),
        "tokens": median([g["generatedTokens"] for g in generations]),
        "prompt_tokens": median([g.get("promptTokens", 0) for g in generations]),
        "memory": max((g["peakMemory"] for g in generations), default=0) / 2**30,
        "thermal": max((max(r["thermalBefore"], r["thermalAfter"]) for r in records), default=0),
        "total_time": sum(g["totalTime"] for g in generations) / 60,
    }


def adapter_text(meta):
    adapter = meta.get("adapter")
    if not adapter:
        return "none (the base model)"
    return f'{adapter["name"]}: rank {adapter["rank"]}, {adapter["layers"]} layers, weights `{adapter["weightsHash"][:12]}`'


def same_schema(old, new, old_path, new_path):
    """Two reports of the same schema and tier (for example the base model and a LoRA adapter), field by field."""
    if old["keys"] != new["keys"]:
        sys.exit("The two reports ask different fields: compare reports of the same tier.")
    keys = new["keys"]
    sets = [r["meta"].get("evaluationSet", "test") for r in (old, new)]
    if sets[0] != sets[1]:
        sys.exit(f"The two reports ran on different statements ({sets[0]} and {sets[1]}): compare reports of the same set.")
    set_rows = [["Evaluation set", sets[0], sets[1]]] if any("evaluationSet" in r["meta"] for r in (old, new)) else []
    print("## What changed between the two runs\n")
    print(table(["", "Before", "After"], [
        ["Report", f"`{Path(old_path).name}`", f"`{Path(new_path).name}`"],
        ["Adapter", adapter_text(old["meta"]), adapter_text(new["meta"])],
        *set_rows,
        ["Device", f'{old["meta"]["device"]}, {old["meta"]["system"]}', f'{new["meta"]["device"]}, {new["meta"]["system"]}'],
        ["Statements x runs", f'{old["meta"]["examples"]} x {old["meta"]["runs"]}', f'{new["meta"]["examples"]} x {new["meta"]["runs"]}'],
        ["Temperature / max tokens / seeds", f'{old["meta"]["temperature"]} / {old["meta"]["maxTokens"]} / {old["meta"]["seeds"]}',
         f'{new["meta"]["temperature"]} / {new["meta"]["maxTokens"]} / {new["meta"]["seeds"]}'],
        ["Prompt hash", f'`{old["meta"]["promptHash"][:12]}`', f'`{new["meta"]["promptHash"][:12]}`'],
        ["Test set hash", f'`{old["meta"]["testSetHash"][:12]}`', f'`{new["meta"]["testSetHash"][:12]}`'],
        ["Schema hash", f'`{old["meta"].get("schemaHash", "")[:12]}`', f'`{new["meta"].get("schemaHash", "")[:12]}`'],
    ]))
    same = (old["meta"]["promptHash"] == new["meta"]["promptHash"]
            and old["meta"]["testSetHash"] == new["meta"]["testSetHash"])
    print("\nThe prompt and the test set are " + ("**identical**, so the two runs differ only by what is listed above." if same
          else "**different**: the two runs are not one change."))

    print("\n## Headline\n")
    fa, fb = len(keys) * old["n"], len(keys) * new["n"]
    def row(label, a, b, wa, wb):
        return [label, f"{a} / {wa} ({pct(a, wa)})", f"{b} / {wb} ({pct(b, wb)})"]
    print(table(["Measure", "Before", "After"], [
        row("Answers the app can decode (valid JSON)", old["valid"], new["valid"], old["n"], new["n"]),
        row("Exactly the asked keys, right types", old["schema"], new["schema"], old["n"], new["n"]),
        row(f"**All {len(keys)} fields correct**", old["full"], new["full"], old["n"], new["n"]),
        row("Fields correct", old["fields"]["correct"], new["fields"]["correct"], fa, fb),
        row("Wrong fields", fa - old["fields"]["correct"], fb - new["fields"]["correct"], fa, fb),
    ]))

    print("\n## Field by field\n")
    rows = []
    for key in keys:
        a, b = old["per_field"][key], new["per_field"][key]
        rows.append([f"`{key}`", f'{a["correct"]} ({pct(a["correct"], old["n"])})', f'{b["correct"]} ({pct(b["correct"], new["n"])})',
                     ", ".join(f"{k} {a[k]}" for k in KINDS if a[k]) or "-", ", ".join(f"{k} {b[k]}" for k in KINDS if b[k]) or "-"])
    print(table(["Field", "Correct before", "Correct after", "Mistakes before", "Mistakes after"], rows))

    print("\n## Mistakes, over all fields of all answers\n")
    rows = []
    for kind in KINDS:
        a, b = old["fields"][kind], new["fields"][kind]
        if a or b:
            rows.append([kind, f"{a} ({pct(a, fa)})", f"{b} ({pct(b, fb)})"])
    print(table(["Kind", "Before", "After"], rows))

    # The same statement, run and field in the two reports (the seeds are the same).
    old_by = {(r["exampleID"], r["run"]): r for r in old["records"]}
    fixed, broken, still, changed = [], [], 0, 0
    for r in new["records"]:
        o = old_by.get((r["exampleID"], r["run"]))
        if not o:
            continue
        for key in keys:
            a, b = o["fields"][key], r["fields"][key]
            if a != "correct" and b == "correct":
                fixed.append((r["exampleID"], r["run"], key, a))
            elif a == "correct" and b != "correct":
                broken.append((r["exampleID"], r["run"], key, b))
            elif a != "correct" and b != "correct":
                still += 1
                changed += a != b
    print("\n## What moved, answer by answer\n")
    print(table(["Of the same answers (same statement, same run)", "Fields"], [
        ["wrong before, **correct now**", len(fixed)],
        ["correct before, **wrong now**", len(broken)],
        ["wrong before and still wrong", f"{still} (of which {changed} with another kind of mistake)"],
    ]))
    if fixed:
        print("\nFixed, by field: " + ", ".join(f"`{k}` {n}" for k, n in Counter(f[2] for f in fixed).most_common()) + ".")
    if broken:
        print("\nBroken, by field: " + ", ".join(f"`{k}` {n}" for k, n in Counter(b[2] for b in broken).most_common()) + ".")
        print("\n" + table(["Statement", "Run", "Field", "Now"], [[b[0], b[1], f"`{b[2]}`", b[3]] for b in sorted(broken)[:30]]))

    print("\n## What it cost on the device\n")
    print(table(["Measure", "Before", "After"], [
        ["Median time per statement", f'{old["time"]:.1f} s', f'{new["time"]:.1f} s'],
        ["Median time to first token", f'{old["first"]:.2f} s', f'{new["first"]:.2f} s'],
        ["Median generated tokens", f'{old["tokens"]:.0f}', f'{new["tokens"]:.0f}'],
        ["Median tokens per second", f'{old["speed"]:.1f}', f'{new["speed"]:.1f}'],
        ["Peak MLX memory", f'{old["memory"]:.2f} GiB', f'{new["memory"]:.2f} GiB'],
        ["Highest thermal state (0 nominal, 3 critical)", old["thermal"], new["thermal"]],
        ["Generation time in total", f'{old["total_time"]:.1f} min', f'{new["total_time"]:.1f} min'],
    ]))


def main(old_path, new_path):
    old, new = load(old_path), load(new_path)
    if "coreKeys" in old["meta"] or "keys" in old["meta"]:
        return same_schema(old, new, old_path, new_path)
    if "coreKeys" not in new["meta"] and "keys" not in new["meta"]:
        sys.exit("The second report must be a schema version 1 report (it has no coreKeys or keys).")
    if new["meta"].get("tier", "core") != "core":
        sys.exit("The comparison with v1.1.0 is for core reports; read an extended report with summarize_results.py.")

    print("## What changed between the two runs\n")
    print(table(["", "v1.1.0", "Schema version 1"], [
        ["Report", f"`{Path(old_path).name}`", f"`{Path(new_path).name}`"],
        ["Model", old["meta"]["model"], new["meta"]["model"]],
        ["Device", f'{old["meta"]["device"]}, {old["meta"]["system"]}', f'{new["meta"]["device"]}, {new["meta"]["system"]}'],
        ["Fields asked", f'{len(old["keys"])} numbers', f'{len(new["keys"])} strings, read by code'],
        ["Statements x runs", f'{old["meta"]["examples"]} x {old["meta"]["runs"]}', f'{new["meta"]["examples"]} x {new["meta"]["runs"]}'],
        ["Temperature / max tokens", f'{old["meta"]["temperature"]} / {old["meta"]["maxTokens"]}', f'{new["meta"]["temperature"]} / {new["meta"]["maxTokens"]}'],
        ["Prompt hash", f'`{old["meta"]["promptHash"][:12]}`', f'`{new["meta"]["promptHash"][:12]}`'],
        ["Test set hash", f'`{old["meta"]["testSetHash"][:12]}`', f'`{new["meta"]["testSetHash"][:12]}`'],
    ]))
    print("\nThe prompt, the output format, the fields and the statements are all different, so the two runs are "
          "**different experiments**. The numbers below sit side by side; they are not a before and after of one change.")

    print("\n## Headline\n")
    def row(label, a, b, whole_a, whole_b):
        return [label, f"{a} / {whole_a} ({pct(a, whole_a)})", f"{b} / {whole_b} ({pct(b, whole_b)})"]
    fa, fb = len(old["keys"]) * old["n"], len(new["keys"]) * new["n"]
    print(table(["Measure", "v1.1.0", "Schema version 1"], [
        row("Answers the app can decode (valid JSON)", old["valid"], new["valid"], old["n"], new["n"]),
        row("Exactly the asked keys, right types", old["schema"], new["schema"], old["n"], new["n"]),
        row("Needed a Markdown fence", old["fenced"], new["fenced"], old["n"], new["n"]),
        row("**All fields correct** (7 against 13 fields)", old["full"], new["full"], old["n"], new["n"]),
        row("Fields correct", old["fields"]["correct"], new["fields"]["correct"], fa, fb),
        row("All fields correct, if a x1000 unit error is accepted", old["full_tolerant"], new["full_tolerant"], old["n"], new["n"]),
    ]))
    print("\nA fully correct answer needs 13 fields right in the new run and 7 in the old one, so the first row is "
          "harder in the new run by construction.")

    print("\n## The six fields that exist in both runs\n")
    rows = []
    for key in SHARED:
        a, b = old["per_field"][key], new["per_field"][key]
        rows.append([f"`{key}`", pct(a["correct"], old["n"]), pct(b["correct"], new["n"]),
                     ", ".join(f"{k} {a[k]}" for k in KINDS if a[k]) or "-",
                     ", ".join(f"{k} {b[k]}" for k in KINDS if b[k]) or "-"])
    print(table(["Field", "v1.1.0 correct", "Schema 1 correct", "v1.1.0 mistakes", "Schema 1 mistakes"], rows))
    print("\nOther statements, another prompt and another output format: this is an indication, not a measurement of "
          "one change. `operatingIncomeGrowth` of v1.1.0 is no longer a field.")

    print("\n## Mistakes, over all fields of all answers\n")
    rows = []
    for kind in KINDS:
        a, b = old["fields"][kind], new["fields"][kind]
        if a or b:
            rows.append([kind, f"{a} ({pct(a, fa)})", f"{b} ({pct(b, fb)})"])
    print(table(["Kind", "v1.1.0", "Schema version 1"], rows))

    print("\n## All 13 fields of the new run\n")
    rows = []
    for key in new["keys"]:
        c = new["per_field"][key]
        rows.append([f"`{key}`", pct(c["correct"], new["n"]),
                     ", ".join(f"{k} {c[k]}" for k in KINDS if c[k]) or "-"])
    print(table(["Field", "Correct", "Mistakes"], rows))

    print("\n## What it cost on the device\n")
    print(table(["Measure", "v1.1.0", "Schema version 1"], [
        ["Median time per statement", f'{old["time"]:.1f} s', f'{new["time"]:.1f} s'],
        ["Median time to first token", f'{old["first"]:.2f} s', f'{new["first"]:.2f} s'],
        ["Median prompt tokens", f'{old["prompt_tokens"]:.0f}', f'{new["prompt_tokens"]:.0f}'],
        ["Median generated tokens", f'{old["tokens"]:.0f}', f'{new["tokens"]:.0f}'],
        ["Median tokens per second", f'{old["speed"]:.1f}', f'{new["speed"]:.1f}'],
        ["Peak MLX memory", f'{old["memory"]:.2f} GiB', f'{new["memory"]:.2f} GiB'],
        ["Highest thermal state (0 nominal, 3 critical)", old["thermal"], new["thermal"]],
        ["Generation time in total", f'{old["total_time"]:.1f} min', f'{new["total_time"]:.1f} min'],
    ]))
    print("\nThe v1.1.0 numbers on the phone are those of the iPhone 16 report; compare time and tokens only between "
          "reports of the same device.")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
