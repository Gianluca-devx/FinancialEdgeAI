#!/usr/bin/env python3
"""Validate the FinancialEdgeAI dataset files.

Checks, for every line of train/valid/test.jsonl:
  - valid JSON with a system, user and assistant message
  - the user message is the prompt template around one statement
  - the assistant message is JSON with exactly the 7 FinancialMetrics keys,
    each a number or null (the same shape as the Swift Decodable struct)
  - every non-null value is grounded in the statement: its number appears in
    the text (a percentage may be negative, an amount may be stated in millions)
and across files: no statement appears twice (no train/test leakage).

Usage: python3 Scripts/validate_dataset.py
Exit code 0 if everything is valid, 1 otherwise.
"""
import json
import re
import sys
from collections import Counter
from decimal import Decimal
from pathlib import Path

DATASET = Path(__file__).resolve().parent.parent / "Dataset"
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


def main():
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    errors = []
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

    print("lines per split:", counts)
    print("non-null labels per field (all splits):")
    for key in KEYS:
        print(f"  {key:24s} {non_null[key]}")
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors[:50]:
            print(" -", e)
        sys.exit(1)
    print("\nOK: all files are valid, every label is grounded, no statement is shared between files.")


if __name__ == "__main__":
    main()
