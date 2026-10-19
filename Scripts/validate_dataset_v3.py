#!/usr/bin/env python3
"""Validate the Phase 2d dataset in Dataset/v3/ (Specs/phase-2d-real-distractors.md). Standard library only.

Checks:
  1. Dataset/ (outside v3/) and Dataset/v2/ are byte-identical to the frozen tag (v2.4.0).
  2. For every line of v3/train, v3/valid and v3/test3: the chat messages are the core prompt around one statement, the
     assistant message has exactly the core keys, the sidecar has the 18 fields, every label is grounded, no statement
     contains a double quote or a number of the prompt's examples.
  3. v3/train starts with the 480 chat lines of v2/train, and v3/valid with the 48 of v2/valid, unchanged.
  4. Held-out wording: the old pools B, V and C of v2 as before (`forbidden_hits`), and the new template pools: train contains no
     phrase of the V3 or C3 templates, valid none of C3, test 3 none of V3.
  5. No statement is shared between the splits, and none of the new statements is in the old test or in test 2.
  6. Coverage: every core field is stated in at least 25% of the training statements; the share of statements with no stated field
     is printed.
  7. The private check: no run of 6 consecutive words of a real passage (RealSet/passages*.json, only where it exists) is in any
     statement. Counts only, never a passage.

Usage: python3 Scripts/validate_dataset_v3.py [--dir Dataset/v3] [--passages 'RealSet/passages*.json']
Exit code 0 if everything is valid, 1 otherwise. validate_dataset.py calls it when Dataset/v3 exists.
"""
import argparse
import csv
import glob
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

import generate_dataset_v2 as v2
import generate_dataset_v3 as gen
from prompt_from_schema import example_leaks, load_schema

ROOT = Path(__file__).resolve().parent.parent
DATASET = ROOT / "Dataset"
FROZEN_TAG = "v2.4.0"
SPLITS = ("train", "valid", "test3")
MIN_COVERAGE = 0.25
SHINGLE = 6


def git(*args):
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True)


def check_frozen(errors):
    listing = git("ls-tree", "-r", "--name-only", FROZEN_TAG, "Dataset")
    if listing.returncode != 0:
        errors.append(f"git tag {FROZEN_TAG} not found (fetch the tags): cannot prove Dataset/ is unchanged")
        return 0
    files = [f for f in listing.stdout.decode().split("\n") if f and not f.startswith("Dataset/v3/")]
    for path in files:
        current = ROOT / path
        if not current.exists():
            errors.append(f"{path} is missing (it exists in {FROZEN_TAG})")
        elif current.read_bytes() != git("show", f"{FROZEN_TAG}:{path}").stdout:
            errors.append(f"{path} differs from {FROZEN_TAG}")
    for p in DATASET.rglob("*"):
        rel = p.relative_to(ROOT).as_posix()
        if p.is_file() and not rel.startswith("Dataset/v3/") and rel not in files and p.name != ".DS_Store":
            errors.append(f"{rel} is not in {FROZEN_TAG}: Dataset/ outside v3/ must not change")
    return len(files)


def statement_of(user, prefix, suffix):
    return user[len(prefix):len(user) - len(suffix)]


def words(text):
    return re.findall(r"[a-z0-9]+", text.lower())


# The standard date phrase of every annual report is not a copy of a passage: it has been in the dataset since v1.
GENERIC = re.compile(r"year ended december")


def shingles(text, n=SHINGLE):
    w = words(text)
    return {s for s in (" ".join(w[i:i + n]) for i in range(len(w) - n + 1)) if not GENERIC.search(s)}


def check(v3_dir, errors, passages_glob="RealSet/passages*.json"):
    schema = load_schema()
    core = [f["key"] for f in schema["fields"] if f["tier"] == "core"]
    all_keys = [f["key"] for f in schema["fields"]]
    kinds = {f["key"]: f["kind"] for f in schema["fields"]}
    template = (DATASET / "prompt_template.txt").read_text().rstrip("\n")
    prefix, suffix = template.split("<<STATEMENT>>")
    system = (DATASET / "system_prompt.txt").read_text().strip()

    frozen = check_frozen(errors)
    statements, non_null, where_seen = {}, {s: Counter() for s in SPLITS}, {}
    rows_by_split = {s: [r for r in csv.DictReader(open(v3_dir / "index.csv")) if r["split"] == s] for s in SPLITS}
    for split in SPLITS:
        chat = (v3_dir / f"{split}.jsonl").read_text().splitlines()
        side = (v3_dir / f"{split}.labels.jsonl").read_text().splitlines()
        if len(chat) != len(side) or len(chat) != len(rows_by_split[split]):
            errors.append(f"v3/{split}: {len(chat)} statements, {len(side)} label lines, {len(rows_by_split[split])} index rows")
            continue
        statements[split] = []
        for n, (raw, side_raw) in enumerate(zip(chat, side), start=1):
            where = f"v3/{split}.jsonl:{n}"
            try:
                messages = json.loads(raw)["messages"]
                if [m["role"] for m in messages] != ["system", "user", "assistant"] or messages[0]["content"] != system:
                    errors.append(f"{where}: roles or system message")
                    continue
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
            for pool, what in v2.forbidden_hits(statement, gen.V2SPLIT[split]):
                errors.append(f"{where}: held-out wording of pool {pool} in {split}: {what!r}")
            if statement in where_seen:
                errors.append(f"{where}: statement already used in {where_seen[statement]}")
            where_seen[statement] = where
            if list(label) != core:
                errors.append(f"{where}: assistant keys are {list(label)}")
                continue
            if sidecar.get("line") != n or list(sidecar.get("fields", {})) != all_keys:
                errors.append(f"v3/{split}.labels.jsonl:{n}: wrong line number or fields")
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

    # 3. The v2 statements are carried over unchanged.
    for split in ("train", "valid"):
        old = (ROOT / "Dataset" / "v2" / f"{split}.jsonl").read_text().splitlines()
        new = (v3_dir / f"{split}.jsonl").read_text().splitlines()
        if new[:len(old)] != old:
            errors.append(f"v3/{split}.jsonl does not start with the {len(old)} lines of v2/{split}.jsonl")
        old_side = (ROOT / "Dataset" / "v2" / f"{split}.labels.jsonl").read_text().splitlines()
        new_side = (v3_dir / f"{split}.labels.jsonl").read_text().splitlines()
        if [json.loads(l)["fields"] for l in new_side[:len(old_side)]] != [json.loads(l)["fields"] for l in old_side]:
            errors.append(f"v3/{split}.labels.jsonl does not start with the labels of v2/{split}.labels.jsonl")
    n_old = {"train": 480, "valid": 48, "test3": 0}

    # 4. The new template pools are held out of the splits that may not see them.
    pools = {"V3": gen.template_phrases("V3"), "C3": gen.template_phrases("C3")}
    forbidden = {"train": ["V3", "C3"], "valid": ["C3"], "test3": ["V3"]}
    for split in SPLITS:
        for n, statement in enumerate(statements.get(split, []), start=1):
            if n <= n_old[split]:
                continue                                   # a v2 statement: checked by the v2 rules above
            low = statement.lower()
            for pool in forbidden[split]:
                for phrase in sorted(pools[pool]):
                    if re.search(rf"(?<![a-z]){re.escape(phrase)}(?![a-z])", low):
                        errors.append(f"v3/{split}.jsonl:{n}: held-out template wording of pool {pool}: {phrase!r}")

    # 5. Nothing of the new statements is in the old test, test 2.
    def read(path):
        """The statements of an existing chat file; a line that cannot be read is an error, not a crash."""
        out = set()
        for n, l in enumerate(path.read_text().splitlines(), start=1):
            try:
                out.add(statement_of(json.loads(l)["messages"][1]["content"], prefix, suffix))
            except (ValueError, KeyError, TypeError, IndexError):
                errors.append(f"{path.relative_to(ROOT).as_posix()}:{n}: unreadable line")
        return out
    protected = read(DATASET / "test.jsonl") | read(DATASET / "v2" / "test2.jsonl")
    for split in SPLITS:
        for n, statement in enumerate(statements.get(split, []), start=1):
            if statement in protected:
                errors.append(f"v3/{split}.jsonl:{n}: statement is in the old test or in test 2")

    # 6. Coverage.
    train_n = len(statements.get("train", []))
    print(f"frozen files identical to {FROZEN_TAG}: {frozen}")
    print("lines:", {s: len(statements.get(s, [])) for s in SPLITS})
    print(f"\n{'stated (not null) per core field':34s}" + "".join(f"{s:>12s}" for s in SPLITS))
    for key in core:
        cells = "".join(f"{non_null[s][key]:>6d} {non_null[s][key] / max(len(statements.get(s, [])), 1):>4.0%}  " for s in SPLITS)
        print(f"  {key:32s}{cells}")
        if train_n and non_null["train"][key] / train_n < MIN_COVERAGE:
            errors.append(f"train: {key} is stated in {non_null['train'][key] / train_n:.1%} of the statements (at least {MIN_COVERAGE:.0%})")
    for split in SPLITS:
        sidecars = [json.loads(l)["fields"] for l in (v3_dir / f"{split}.labels.jsonl").read_text().splitlines()]
        empty = sum(1 for f in sidecars if not any(f[k] for k in core))
        w = sorted(len(t.split()) for t in statements.get(split, []))
        print(f"{split}: {len(w)} statements, {empty} with no stated core field ({empty / max(len(w), 1):.0%}), words median {w[len(w) // 2]} max {w[-1]}")
    for split in SPLITS:
        counts = Counter(r["scenario"] for r in rows_by_split[split] if r["kinds"] != "v2" and r["scenario"].startswith("real"))
        print(f"  new statements in {split}: {dict(counts)}")

    # 7. The private check against the real passages (counts only).
    files = sorted(glob.glob(str(ROOT / passages_glob)))
    if files:
        real = set()
        for f in files:
            for passage in json.loads(Path(f).read_text()):
                real |= shingles(passage["text"])
        hits = Counter()
        for split in SPLITS:
            for n, statement in enumerate(statements.get(split, []), start=1):
                if shingles(statement) & real:
                    hits[split] += 1
                    errors.append(f"v3/{split}.jsonl:{n}: contains a run of {SHINGLE} words of a real passage")
        print(f"\nreal text check: {len(real)} six-word runs from {len(files)} passage files; statements containing one: "
              f"{dict(hits) if hits else 0}")
    else:
        print("\nreal text check: skipped (no RealSet/passages*.json on this machine)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dir", default=str(DATASET / "v3"))
    parser.add_argument("--passages", default="RealSet/passages*.json")
    args = parser.parse_args()
    errors = []
    check(Path(args.dir), errors, args.passages)
    if errors:
        print(f"\n{len(errors)} problem(s):")
        for e in errors[:60]:
            print(" -", e)
        sys.exit(1)
    print("\nOK: Dataset/ and Dataset/v2/ unchanged, every v3 line valid and grounded, the v2 statements carried over, no held-out wording in "
          "a split that may not see it, no shared statement, coverage reached, no real passage text.")


if __name__ == "__main__":
    main()
