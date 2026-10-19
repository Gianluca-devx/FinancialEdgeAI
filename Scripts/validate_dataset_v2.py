#!/usr/bin/env python3
"""Validate the Phase 2b dataset in Dataset/v2/ (Specs/phase-2b-lora-wording.md). Standard library only.

Checks:
  1. Every file of Dataset/ (outside v2/) is byte-identical to the frozen tag (v2.2.0): the test split, the
     prompt and the schema of every earlier experiment are untouched.
  2. For every line of v2/train, v2/valid and v2/test2: the chat messages are the core prompt around one
     statement, the assistant message has exactly the core keys (a string or null each), the sidecar has the 18
     fields, every label is grounded (appears in the statement, a decrease may add a leading minus), no
     statement contains a double quote or a number of the prompt's examples.
  3. Held-out wording: train contains no phrase of pool B (the old test), V (validation) or C (test 2); valid
     none of B or C; test 2 none of B or V (`forbidden_hits` of generate_dataset_v2.py).
  4. No statement is shared where it must not be: v2 valid and test 2 against every other split of both
     datasets; v2 train against the old valid and test and against test 2.
  5. Coverage: every core field is stated in at least 25% of the training statements; each name-based field
     has at least 4 different wordings in train, each seen at least 5 times (printed as a table).

Usage: python3 Scripts/validate_dataset_v2.py [--dir Dataset/v2]
Exit code 0 if everything is valid, 1 otherwise. validate_dataset.py calls it when Dataset/v2 exists.
"""
import argparse
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import generate_dataset_v2 as gen
from prompt_from_schema import example_leaks, load_schema

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"
FROZEN_TAG = "v2.2.0"
SPLITS = ("train", "valid", "test2")
BUNDLE = ROOT / "FinancialEdgeAI" / "Resources"
# Files of Dataset/v2 that the app bundles (published name in Resources, source in Dataset/v2).
BUNDLED = {"test2.jsonl": "test2.jsonl", "test2.labels.jsonl": "test2.labels.jsonl", "index.v2.csv": "index.csv"}
MIN_COVERAGE = 0.25
MIN_WORDINGS, MIN_SEEN = 4, 5


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True)


def check_frozen(errors):
    listing = git("ls-tree", "-r", "--name-only", FROZEN_TAG, "Dataset")
    if listing.returncode != 0:
        errors.append(f"git tag {FROZEN_TAG} not found (fetch the tags): cannot prove Dataset/ is unchanged")
        return 0
    files = [f for f in listing.stdout.decode().split("\n") if f and not f.startswith("Dataset/v2/")]
    for path in files:
        frozen = git("show", f"{FROZEN_TAG}:{path}").stdout
        current = ROOT / path
        if not current.exists():
            errors.append(f"{path} is missing (it exists in {FROZEN_TAG})")
        elif current.read_bytes() != frozen:
            errors.append(f"{path} differs from {FROZEN_TAG}")
    extra = [p.relative_to(ROOT).as_posix() for p in DATASET.rglob("*") if p.is_file()
             and p.relative_to(DATASET).parts[0] not in ("v2", "v3") and p.relative_to(ROOT).as_posix() not in files
             and p.name != ".DS_Store"]
    for path in extra:
        errors.append(f"{path} is not in {FROZEN_TAG}: Dataset/ outside v2/ must not change")
    return len(files)


def statement_of(user, prefix, suffix):
    return user[len(prefix):len(user) - len(suffix)]


def read_statements(path, prefix, suffix, errors):
    """The statements of an existing chat file; a line that cannot be read is an error, not a crash."""
    found = []
    for n, line in enumerate(path.read_text().splitlines(), start=1):
        try:
            found.append(statement_of(json.loads(line)["messages"][1]["content"], prefix, suffix))
        except (ValueError, KeyError, TypeError, IndexError):
            errors.append(f"{path.relative_to(ROOT).as_posix()}:{n}: unreadable line")
    return found


def phrase_counts(statements, phrases):
    """Longest phrases first; a matched phrase is removed so that "net income" is not counted inside a longer one."""
    counts = Counter()
    for text in statements:
        low = text.lower()
        for phrase in sorted(phrases, key=len, reverse=True):
            pattern = rf"(?<![a-z]){re.escape(phrase)}(?![a-z])"
            found = re.findall(pattern, low)
            if found:
                counts[phrase] += len(found)
                low = re.sub(pattern, " ", low)
    return counts


def check(v2_dir, errors):
    schema = load_schema()
    core = [f["key"] for f in schema["fields"] if f["tier"] == "core"]
    all_keys = [f["key"] for f in schema["fields"]]
    kinds = {f["key"]: f["kind"] for f in schema["fields"]}
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    system = (DATASET / "system_prompt.txt").read_text().strip()

    frozen_files = check_frozen(errors)
    statements, non_null, where_seen = {}, {s: Counter() for s in SPLITS}, {}
    for split in SPLITS:
        chat = (v2_dir / f"{split}.jsonl").read_text().splitlines()
        side = (v2_dir / f"{split}.labels.jsonl").read_text().splitlines()
        if len(chat) != len(side):
            errors.append(f"v2/{split}: {len(chat)} statements, {len(side)} label lines")
            continue
        statements[split] = []
        for n, (raw, side_raw) in enumerate(zip(chat, side), start=1):
            where = f"v2/{split}.jsonl:{n}"
            try:
                messages = json.loads(raw)["messages"]
                if [m["role"] for m in messages] != ["system", "user", "assistant"]:
                    errors.append(f"{where}: roles")
                    continue
                if messages[0]["content"] != system:
                    errors.append(f"{where}: system message")
                user, assistant = messages[1]["content"], messages[2]["content"]
                if not (user.startswith(prefix) and user.endswith(suffix)):
                    errors.append(f"{where}: user message is not the core prompt around a statement")
                    continue
                statement = statement_of(user, prefix, suffix)
                label, sidecar = json.loads(assistant), json.loads(side_raw)
            except (ValueError, KeyError, TypeError) as e:
                errors.append(f"{where}: unreadable ({e})")
                continue
            statements[split].append(statement)
            if '"' in statement or not statement.strip():
                errors.append(f"{where}: statement is empty or contains a double quote")
            if leaks := example_leaks(statement):
                errors.append(f"{where}: contains {', '.join(leaks)}, a number of the prompt's examples")
            for pool, what in gen.forbidden_hits(statement, split):
                errors.append(f"{where}: held-out wording of pool {pool} in {split}: {what!r}")
            if statement in where_seen:
                errors.append(f"{where}: statement already used in {where_seen[statement]}")
            where_seen[statement] = where
            if list(label) != core:
                errors.append(f"{where}: assistant keys are {list(label)}")
                continue
            if sidecar.get("line") != n or list(sidecar.get("fields", {})) != all_keys:
                errors.append(f"v2/{split}.labels.jsonl:{n}: wrong line number or fields")
                continue
            for key in all_keys:
                entry = sidecar["fields"][key]
                if entry is None:
                    if key in label and label[key] is not None:
                        errors.append(f"{where}: {key} is in the assistant message but not in the sidecar")
                    continue
                text = entry.get("text") if isinstance(entry, dict) else None
                if not isinstance(text, str) or not text or isinstance(entry.get("value"), bool) \
                        or not isinstance(entry.get("value"), (int, float)):
                    errors.append(f"{where}: {key} must be null or {{text, value}} ({entry!r})")
                    continue
                non_null[split][key] += 1
                if key in label and label[key] != text:
                    errors.append(f"{where}: {key} differs between the assistant message and the sidecar")
                printed = text[1:] if kinds[key] == "percent" and text.startswith("-") else text
                if printed not in statement:
                    errors.append(f"{where}: {key}={text!r} does not appear in the statement")
                if key in core and key not in label:
                    errors.append(f"{where}: {key} is missing from the assistant message")

    # Other datasets: nothing of the old valid and test, and nothing of test 2, may be in the training data.
    old = {s: set(read_statements(DATASET / f"{s}.jsonl", prefix, suffix, errors)) for s in ("train", "valid", "test")}
    for split in SPLITS:
        for n, statement in enumerate(statements.get(split, []), start=1):
            if statement in old["valid"] or statement in old["test"]:
                errors.append(f"v2/{split}.jsonl:{n}: statement is in the old valid or test split")
            if split != "train" and statement in old["train"]:
                errors.append(f"v2/{split}.jsonl:{n}: statement is in the old train split")

    for published, source in BUNDLED.items():
        copy = BUNDLE / published
        if not copy.exists():
            errors.append(f"FinancialEdgeAI/Resources/{published} is missing")
        elif copy.read_bytes() != (v2_dir / source).read_bytes():
            errors.append(f"FinancialEdgeAI/Resources/{published} differs from Dataset/v2/{source}")

    # Coverage and wordings.
    train_n = len(statements.get("train", []))
    print(f"frozen files identical to {FROZEN_TAG}: {frozen_files}")
    print("lines:", {s: len(statements.get(s, [])) for s in SPLITS})
    print(f"\n{'stated (not null) per core field':34s}" + "".join(f"{s:>12s}" for s in SPLITS))
    for key in core:
        cells = "".join(f"{non_null[s][key]:>6d} {non_null[s][key] / max(len(statements.get(s, [])), 1):>4.0%}  " for s in SPLITS)
        print(f"  {key:32s}{cells}")
        if train_n and non_null["train"][key] / train_n < MIN_COVERAGE:
            errors.append(f"train: {key} is stated in {non_null['train'][key] / train_n:.1%} of the statements "
                          f"(at least {MIN_COVERAGE:.0%})")

    train = statements.get("train", [])
    groups = {key: [p.lower() for pool in ("A", "A2") for p, _ in gen.NAMES[key][pool]] for key in gen.NAMES}
    for key in ("interestExpense", "operatingCashFlow", "capex"):
        groups[key] = [f for pool in ("A", "A2") for t in gen.SINGLE[key][pool] for f in gen._fragments(t)[:1]]
    print(f"\ndifferent wordings in train (seen at least {MIN_SEEN} times, at least {MIN_WORDINGS} needed)")
    for key, phrases in groups.items():
        counts = phrase_counts(train, set(phrases))
        seen = {p: c for p, c in counts.items() if c >= MIN_SEEN}
        print(f"  {key:18s} {len(seen)} of {len(set(phrases))}: " + ", ".join(f"{p} ({c})" for p, c in sorted(seen.items(), key=lambda x: -x[1])))
        if len(seen) < MIN_WORDINGS:
            errors.append(f"train: {key} has {len(seen)} wordings seen at least {MIN_SEEN} times (need {MIN_WORDINGS})")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default=str(DATASET / "v2"))
    args = parser.parse_args()
    errors = []
    check(Path(args.dir), errors)
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors[:60]:
            print(" -", e)
        sys.exit(1)
    print("\nOK: Dataset/ is unchanged, every v2 line is valid and grounded, no held-out wording in a split that may not "
          "see it, no shared statement, coverage and wording variety reached.")


if __name__ == "__main__":
    main()
