#!/usr/bin/env python3
"""Validate the FinancialEdgeAI dataset files (schema version 1, Phase 1).

Checks Dataset/schema.json (the only list of fields), that prompt_template.txt is exactly what the
schema renders, and, for every line of train/valid/test.jsonl:
  - valid JSON with a system, user and assistant message
  - the user message is the prompt template around one statement
  - the assistant message is JSON with exactly the core keys of the schema, each a string or null
  - the sidecar line in <split>.labels.jsonl has all 18 fields, each null or {"text", "value"},
    and the core texts are the ones of the assistant message
  - every non-null text is grounded: it appears verbatim in the statement (a decrease may add a
    leading minus to the printed percent: "-4%" for "down 4%")
  - no statement contains a number of the prompt's own examples
and across files: no statement appears twice (no train/test leakage), and the copies of the files
bundled in the app (FinancialEdgeAI/Resources) are byte-identical to Dataset/.

The parser is not checked here: the Swift tests check ValueParser(text) == value for every line.

Usage: python3 Scripts/validate_dataset.py
Exit code 0 if everything is valid, 1 otherwise.
"""
import json
import sys
from collections import Counter
from pathlib import Path

from prompt_from_schema import example_leaks, render_prompt

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"
BUNDLE = ROOT / "FinancialEdgeAI" / "Resources"
# Files that the app bundles; the copy must never drift from Dataset/.
BUNDLED = ["prompt_template.txt", "system_prompt.txt", "test.jsonl", "test.labels.jsonl", "index.csv", "schema.json"]
SPLITS = ("train", "valid", "test")


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


def check_prompt(template, schema):
    """The prompt must be exactly what the schema renders, so the field list cannot drift."""
    if template != render_prompt(schema).rstrip("\n"):
        return ["prompt_template.txt differs from what Dataset/schema.json renders "
                "(python3 Scripts/prompt_from_schema.py --write)"]
    return []


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def main():
    errors, schema = check_schema()
    if schema is None:
        print("\n".join(errors))
        sys.exit(1)
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    errors += check_prompt(template, schema)
    prefix, suffix = template.split("<<STATEMENT>>")
    system = (DATASET / "system_prompt.txt").read_text().strip()
    kinds = {f["key"]: f["kind"] for f in schema["fields"]}
    all_keys = list(kinds)
    core_keys = [f["key"] for f in schema["fields"] if f["tier"] == "core"]
    seen = {}
    counts = {}
    non_null = {split: Counter() for split in SPLITS}

    for split in SPLITS:
        chat_lines = (DATASET / f"{split}.jsonl").read_text().splitlines()
        side_lines = (DATASET / f"{split}.labels.jsonl").read_text().splitlines()
        counts[split] = len(chat_lines)
        if len(side_lines) != len(chat_lines):
            errors.append(f"{split}.labels.jsonl has {len(side_lines)} lines, {split}.jsonl has {len(chat_lines)}")
            continue
        for n, (raw, side_raw) in enumerate(zip(chat_lines, side_lines), start=1):
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
                side = json.loads(side_raw)
            except (ValueError, KeyError, TypeError) as e:
                errors.append(f"{where}: unreadable ({e})")
                continue

            if '"' in statement or not statement.strip():
                errors.append(f"{where}: statement is empty or contains a double quote")
            if leaks := example_leaks(statement):
                errors.append(f"{where}: statement contains {', '.join(leaks)}, a number of the prompt's examples")
            if statement in seen:
                errors.append(f"{where}: statement already used in {seen[statement]}")
            seen[statement] = where

            if list(label) != core_keys:
                errors.append(f"{where}: assistant keys are {list(label)}")
                continue
            if side.get("line") != n or list(side.get("fields", {})) != all_keys:
                errors.append(f"{split}.labels.jsonl:{n}: wrong line number or fields")
                continue
            for key in all_keys:
                entry = side["fields"][key]
                if entry is None:
                    if key in label and label[key] is not None:
                        errors.append(f"{where}: {key} is in the assistant message but not in the sidecar")
                    continue
                text = entry.get("text") if isinstance(entry, dict) else None
                if not isinstance(text, str) or not text or not is_number(entry.get("value")):
                    errors.append(f"{where}: {key} must be null or {{text, value}} ({entry!r})")
                    continue
                non_null[split][key] += 1
                if key in label and label[key] != text:
                    errors.append(f"{where}: {key} is {label[key]!r} in the assistant message, {text!r} in the sidecar")
                printed = text[1:] if kinds[key] == "percent" and text.startswith("-") else text
                if printed not in statement:
                    errors.append(f"{where}: {key}={text!r} does not appear in the statement")
                if key not in label and key in core_keys:
                    errors.append(f"{where}: {key} is missing from the assistant message")

    for name in BUNDLED:
        copy = BUNDLE / name
        if not copy.exists():
            errors.append(f"FinancialEdgeAI/Resources/{name} is missing")
        elif copy.read_bytes() != (DATASET / name).read_bytes():
            errors.append(f"FinancialEdgeAI/Resources/{name} differs from Dataset/{name}")

    core = len(core_keys)
    print(f"schema: {core} core, {len(all_keys) - core} extended, {len(schema['derived'])} derived")
    print("lines per split:", counts)
    print(f"non-null labels per field {'':14s}" + "".join(f"{s:>7s}" for s in SPLITS))
    for key in all_keys:
        print(f"  {key:30s}" + "".join(f"{non_null[s][key]:7d}" for s in SPLITS))
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors[:50]:
            print(" -", e)
        sys.exit(1)
    print("\nOK: schema, prompt and files are valid, every label is grounded, no statement is shared between files, bundled copies match.")


if __name__ == "__main__":
    main()
