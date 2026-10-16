#!/usr/bin/env python3
"""Validate the FinancialEdgeAI dataset files.

Checks, for every line of train/valid/test.jsonl:
  - valid JSON with a system, user and assistant message
  - the user message is the prompt template around one statement
  - the assistant message is JSON with exactly the 7 FinancialMetrics keys,
    each a number or null (the same shape as the Swift Decodable struct)
  - every non-null value is grounded in the statement: its number appears in
    the text (a percentage may be negative, an amount may be stated in millions)
and across files: no statement appears twice (no train/test leakage), and the copies of the
prompt files bundled in the app (FinancialEdgeAI/Resources) are byte-identical to Dataset/.

Usage: python3 Scripts/validate_dataset.py
Exit code 0 if everything is valid, 1 otherwise.
"""
import json
import re
import sys
from collections import Counter
from decimal import Decimal
from pathlib import Path

from prompt_from_schema import EXAMPLE_NUMBERS, render_prompt

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"
BUNDLE = ROOT / "FinancialEdgeAI" / "Resources"
# Files that the app bundles; the copy must never drift from Dataset/.
BUNDLED = ["prompt_template.txt", "system_prompt.txt", "test.jsonl", "index.csv", "schema.json"]
KEYS = [
    "revenue", "revenueGrowth", "operatingIncome", "operatingIncomeGrowth",
    "netIncome", "netIncomeGrowth", "previousYearNetIncome",
]
NUMBER = re.compile(r"\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?")


def numbers_in(text):
    return {Decimal(n.replace(",", "")).normalize() for n in NUMBER.findall(text)}


def grounded(value, nums):
    d = Decimal(str(abs(value))).normalize()
    return d in nums or (d * 1000).normalize() in nums


def check_schema():
    """Dataset/schema.json is the only field list: check it is consistent. Returns (problems, schema)."""
    problems = []
    try:
        schema = json.loads((DATASET / "schema.json").read_text())
    except (OSError, ValueError) as e:
        return [f"schema.json is unreadable ({e})"], None
    if schema.get("version") != 1:
        problems.append(f"schema.json: unsupported version {schema.get('version')!r}")
    fields, derived = schema.get("fields", []), schema.get("derived", [])
    kinds = {"amount", "percent", "perShare", "ratio"}
    keys = [f["key"] for f in fields] + [d["key"] for d in derived]
    for key in sorted({k for k in keys if keys.count(k) > 1}):
        problems.append(f"schema.json: the key {key} is used twice")
    if not any(f["tier"] == "core" for f in fields):
        problems.append("schema.json: no core field")
    by_key = {f["key"]: f for f in fields}
    for f in fields:
        if f["tier"] not in ("core", "extended") or f["kind"] not in kinds - {"ratio"}:
            problems.append(f"schema.json: {f['key']} has a bad tier or kind")
    for d in derived:
        if d["kind"] not in kinds:
            problems.append(f"schema.json: {d['key']} has a bad kind")
        for i in d["inputs"]:
            if i not in by_key:
                problems.append(f"schema.json: {d['key']} reads {i}, which is not an extracted field")
        target = d.get("fills")
        if target is not None and by_key.get(target, {}).get("kind") != d["kind"]:
            problems.append(f"schema.json: {d['key']} cannot fill {target}")
    return problems, schema


SCHEMA_PROMPT_MARKER = "Extract the following fields:"


def check_prompt(template, schema):
    """Once the prompt is the schema-based one, it must be exactly what the schema renders.

    The prompt of v1.1.0 (7 metrics) has no marker and is left alone: Phase 1 step 4 replaces it
    together with the dataset, and from then on this check is always active.
    """
    if schema is None or SCHEMA_PROMPT_MARKER not in template:
        return []
    if template != render_prompt(schema).rstrip("\n"):
        return ["prompt_template.txt differs from what Dataset/schema.json renders "
                "(python3 Scripts/prompt_from_schema.py --write)"]
    return []


def example_leaks(statement):
    """The numbers of the prompt's own examples that a statement also contains."""
    return [n for n in EXAMPLE_NUMBERS if re.search(rf"(?<![\d.,]){re.escape(n)}(?!\d)", statement)]


def main():
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    system = (DATASET / "system_prompt.txt").read_text().strip()
    errors, schema = check_schema()
    errors += check_prompt(template, schema)
    seen = {}
    counts = {}
    non_null = Counter()

    for split in ("train", "valid", "test"):
        path = DATASET / f"{split}.jsonl"
        lines = path.read_text().splitlines()
        counts[split] = len(lines)
        for n, raw in enumerate(lines, start=1):
            where = f"{split}.jsonl:{n}"
            try:
                messages = json.loads(raw)["messages"]
                roles = [m["role"] for m in messages]
                if roles != ["system", "user", "assistant"]:
                    errors.append(f"{where}: roles are {roles}")
                    continue
                if messages[0]["content"] != system:
                    errors.append(f"{where}: system message does not match system_prompt.txt")
                user, assistant = messages[1]["content"], messages[2]["content"]
                if not (user.startswith(prefix) and user.endswith(suffix)):
                    errors.append(f"{where}: user message does not match prompt_template.txt")
                    continue
                statement = user[len(prefix):len(user) - len(suffix)]
                label = json.loads(assistant)
            except (ValueError, KeyError, TypeError) as e:
                errors.append(f"{where}: unreadable ({e})")
                continue

            if '"' in statement or not statement.strip():
                errors.append(f"{where}: statement is empty or contains a double quote")
            if leaks := example_leaks(statement):
                errors.append(f"{where}: statement contains {', '.join(leaks)}, a number of the prompt's examples")
            if list(label) != KEYS:
                errors.append(f"{where}: keys are {list(label)}")
                continue
            nums = numbers_in(statement)
            for key, value in label.items():
                if value is None:
                    continue
                if isinstance(value, bool) or not isinstance(value, (int, float)):
                    errors.append(f"{where}: {key} is not a number or null ({value!r})")
                    continue
                non_null[key] += 1
                if not grounded(value, nums):
                    errors.append(f"{where}: {key}={value} does not appear in the statement")
            if statement in seen:
                errors.append(f"{where}: statement already used in {seen[statement]}")
            seen[statement] = where

    for name in BUNDLED:
        copy = BUNDLE / name
        if not copy.exists():
            errors.append(f"FinancialEdgeAI/Resources/{name} is missing")
        elif copy.read_bytes() != (DATASET / name).read_bytes():
            errors.append(f"FinancialEdgeAI/Resources/{name} differs from Dataset/{name}")

    if schema:
        core = sum(f["tier"] == "core" for f in schema["fields"])
        print(f"schema: {core} core, {len(schema['fields']) - core} extended, {len(schema['derived'])} derived")
    print("lines per split:", counts)
    print("non-null labels per field (all splits):")
    for key in KEYS:
        print(f"  {key:24s} {non_null[key]}")
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors[:50]:
            print(" -", e)
        sys.exit(1)
    print("\nOK: all files are valid, every label is grounded, no statement is shared between files, bundled copies match.")


if __name__ == "__main__":
    main()
