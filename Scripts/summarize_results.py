#!/usr/bin/env python3
"""Turn an evaluation report exported by the app into Markdown tables.

The app (Evaluate tab) writes one JSON report per evaluation. This script reads it and prints:
run information, headline numbers, outcome counts per field, results per scenario and per
phrasing pool, how stable the answers are across the runs, and every failing statement with
what was expected and what the model returned. Standard library only.

It reads both report formats:
  - schema version 1 (Phase 1): `metadata.coreKeys` (v2.0.0) or `metadata.keys` and `metadata.tier`
    (core or extended call) are there; the model returns strings, and the numbers are read by code.
    The statements come from Dataset/ (the extended call has its own chat file).
  - v1.1.0: seven numeric fields. The statements come from Dataset/archive/v1.1.0/.

Usage: python3 Scripts/summarize_results.py Results/baseline-<model>-<date>.json > tables.md
"""
import csv
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
V1_KEYS = [
    "revenue", "revenueGrowth", "operatingIncome", "operatingIncomeGrowth",
    "netIncome", "netIncomeGrowth", "previousYearNetIncome",
]


def pct(part, whole):
    return f"{100 * part / whole:.1f}%" if whole else "n/a"


def fmt(value):
    return "null" if value is None else f"{value:g}"


def values_of(side):
    """The numbers of an `extracted` or `expected` entry (None, v1.1.0 flat dict, or {texts, values})."""
    if not side:
        return {}
    return side["values"] if "values" in side else side


def texts_of(side):
    return side.get("texts", {}) if side else {}


def describe(side, key, new_format):
    """How one side of a comparison reads: the number, or the printed string and its number."""
    value = values_of(side).get(key)
    if not new_format:
        return fmt(value)
    text = texts_of(side).get(key)
    if text is None:
        return "null"
    return f'"{text}" = ' + ("unreadable" if value is None else fmt(value))


def dataset_dir(new_format):
    return ROOT / "Dataset" if new_format else ROOT / "Dataset" / "archive" / "v1.1.0"


def load_statements(directory, tier="core"):
    """Statement text per line of the test chat file of the tier (the report only stores example ids)."""
    extended = tier == "extended"
    template = (directory / ("prompt_template_extended.txt" if extended else "prompt_template.txt")).read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    statements = {}
    lines = (directory / ("test.extended.jsonl" if extended else "test.jsonl")).read_text().splitlines()
    for number, line in enumerate(lines, start=1):
        user = json.loads(line)["messages"][1]["content"]
        statements[number] = user[len(prefix):len(user) - len(suffix)]
    return statements


def load_units(directory):
    """Unit the statement is written in: b (billions), m (millions) or - (hand-written)."""
    with open(directory / "index.csv", newline="") as f:
        return {int(r["line"]): r["unit"] for r in csv.DictReader(f) if r["split"] == "test"}


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(["---"] * len(headers)) + "|"]
    out += ["| " + " | ".join(str(c) for c in row) + " |" for row in rows]
    return "\n".join(out)


def stats(records, keys):
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
        # The same, if a number written in the wrong unit (x1000) is accepted.
        "full_unit_tolerant": sum(all(v in ("correct", "unitError") for v in r["fields"].values()) for r in records),
        "correct_fields_unit_tolerant": fields["correct"] + fields["unitError"],
        "correct_fields": fields["correct"],
        "fields": n * len(keys),
        "outcomes": fields,
    }


def main(path):
    report = json.loads(Path(path).read_text())
    meta, records = report["metadata"], report["records"]
    new_format = "coreKeys" in meta or "keys" in meta
    tier = meta.get("tier", "core")
    keys = meta.get("keys") or meta.get("coreKeys") or V1_KEYS
    outcomes = ["correct", "hallucinated", "missed", "wrongValue", "signError", "unitError"]
    outcomes += ["unreadable", "unparsed"] if new_format else ["unparsed"]
    directory = dataset_dir(new_format)
    statements = load_statements(directory, tier)
    s = stats(records, keys)
    generations = [r["generation"] for r in records if "generation" in r]

    def median(values):
        values = sorted(values)
        mid = len(values) // 2
        return (values[mid - 1] + values[mid]) / 2 if len(values) % 2 == 0 else values[mid]

    print("## Run\n")
    run_rows = [
        ["Model", meta["model"]],
        ["Device", f'{meta["device"]}, {meta["system"]}'],
        ["Date", meta["date"]],
        ["Statements x runs", f'{meta["examples"]} x {meta["runs"]} = {s["n"]} answers'],
        ["Seeds", ", ".join(map(str, meta["seeds"]))],
        ["Temperature / max tokens", f'{meta["temperature"]} / {meta["maxTokens"]}'],
        ["Prompt hash (SHA-256)", f'`{meta["promptHash"][:16]}...`'],
        ["Test set hash (SHA-256)", f'`{meta["testSetHash"][:16]}...`'],
    ]
    if new_format:
        run_rows.append(["Schema hash (SHA-256)", f'`{meta["schemaHash"][:16]}...`'])
        run_rows.append(["Core fields asked and judged" if "coreKeys" in meta
                         else f"Fields asked and judged ({tier} call)", len(keys)])
    adapter = meta.get("adapter")
    if adapter:
        run_rows.append(["LoRA adapter", f'{adapter["name"]}: rank {adapter["rank"]}, {adapter["layers"]} layers, scale {adapter["scale"]:g}'])
        run_rows.append(["Adapter weights hash (SHA-256)", f'`{adapter["weightsHash"][:16]}...`'])
        run_rows.append(["Adapter config hash (SHA-256)", f'`{adapter["configHash"][:16]}...`'])
    run_rows.append(["Model load (first launch includes download)",
                     f'{meta["modelLoadSeconds"]:.1f} s' if meta.get("modelLoadSeconds") else "n/a"])
    print(table(["", ""], run_rows))

    print("\n## Headline\n")
    headline = [
        ["Valid JSON (the app's decoder can read it)", f'{s["valid"]} / {s["n"]}', pct(s["valid"], s["n"])],
        [f"Exactly the {tier} keys, a string or null each" if new_format else "Exactly the 7 keys, number or null",
         f'{s["schema"]} / {s["n"]}', pct(s["schema"], s["n"])],
        [f"All {len(keys)} fields correct", f'{s["full"]} / {s["n"]}', pct(s["full"], s["n"])],
        ["Fields correct", f'{s["correct_fields"]} / {s["fields"]}', pct(s["correct_fields"], s["fields"])],
        [f"All {len(keys)} fields correct, if a x1000 unit error is accepted",
         f'{s["full_unit_tolerant"]} / {s["n"]}', pct(s["full_unit_tolerant"], s["n"])],
        ["Fields correct, if a x1000 unit error is accepted",
         f'{s["correct_fields_unit_tolerant"]} / {s["fields"]}', pct(s["correct_fields_unit_tolerant"], s["fields"])],
        ["Needed a code fence", f'{s["fenced"]} / {s["n"]}', pct(s["fenced"], s["n"])],
    ]
    if new_format:
        copies = [v for r in records for v in r.get("exactCopies", {}).values()]
        headline.append(["Strings copied exactly like the label (where both have one)",
                         f"{sum(copies)} / {len(copies)}", pct(sum(copies), len(copies))])
    print(table(["Measure", "Count", "Share"], headline))

    print("\n## Performance on the device\n")
    print(table(["Measure", "Value"], [
        ["Median time per statement", f'{median([g["totalTime"] for g in generations]):.1f} s'],
        ["Median time to first token", f'{median([g["promptTime"] for g in generations]):.2f} s'],
        ["Median tokens per second", f'{median([g["tokensPerSecond"] for g in generations]):.1f}'],
        ["Median generated tokens", f'{median([g["generatedTokens"] for g in generations]):.0f}'],
        ["Peak MLX memory", f'{max(g["peakMemory"] for g in generations) / 2**20:.0f} ' + ("MiB" if new_format else "MB")],
        ["Highest thermal state (0 nominal, 3 critical)", max(max(r["thermalBefore"], r["thermalAfter"]) for r in records)],
        ["Generation failures", sum("generation" not in r for r in records)],
    ]))

    print("\n## Outcome per field (all answers)\n")
    rows = []
    for key in keys:
        c = Counter(r["fields"][key] for r in records)
        rows.append([key] + [c[o] for o in outcomes] + [pct(c["correct"], s["n"])])
    print(table(["Field"] + outcomes + ["Accuracy"], rows))
    print("\n" + ", ".join(f"{o} {s['outcomes'][o]}" for o in outcomes if o != "correct" and s["outcomes"][o]))

    for title, key in (("scenario", "scenario"), ("phrasing pool (B = wording not in train or valid)", "pool")):
        print(f"\n## By {title}\n")
        groups = defaultdict(list)
        for r in records:
            groups[r[key]].append(r)
        rows = []
        for name in sorted(groups):
            g = stats(groups[name], keys)
            rows.append([name, g["n"], f'{g["full"]} ({pct(g["full"], g["n"])})', pct(g["correct_fields"], g["fields"])])
        print(table([key.capitalize(), "Answers", f"All {len(keys)} correct", "Fields correct"], rows))

    print("\n## By unit the statement is written in\n")
    units = load_units(directory)
    groups = defaultdict(list)
    for r in records:
        groups[units.get(r["exampleID"], "?")].append(r)
    names = {"b": "billions", "m": "millions", "-": "hand-written (mixed)"}
    rows = []
    for name in sorted(groups):
        g = stats(groups[name], keys)
        unit_errors = g["outcomes"]["unitError"]
        rows.append([names.get(name, name), g["n"], f'{g["full"]} ({pct(g["full"], g["n"])})',
                     f'{g["full_unit_tolerant"]} ({pct(g["full_unit_tolerant"], g["n"])})', unit_errors])
    print(table(["Written in", "Answers", f"All {len(keys)} correct", f"All {len(keys)} correct, unit errors accepted", "Unit-error fields"], rows))

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
        for key in keys:
            outcome = first["fields"][key]
            if outcome != "correct":
                print(f"- `{key}` ({outcome}): {describe(first['expected'], key, new_format)} -> "
                      f"{describe(first.get('extracted'), key, new_format)}")
        print()


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
