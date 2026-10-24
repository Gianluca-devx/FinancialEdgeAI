#!/usr/bin/env python3
"""Prepare the training data of the LoRA adapter and check that training sees what inference sees.

Needs the packages of Scripts/lora/requirements.txt (mlx-lm, which brings transformers). The other
scripts of Scripts/ use the standard library only; this folder is the exception, on purpose.

What it does:
  1. Copies train.jsonl and valid.jsonl of the source folder (Dataset by default, Dataset/v2 for Phase 2b) to <out>/
     (the chat format `mlx_lm.lora` reads). The test splits (Dataset/test.jsonl, Dataset/v2/test2.jsonl and Dataset/v3/test3.jsonl) are
     and Dataset/v3/test3.jsonl) are never copied or listed: they stay unseen by the training. They are only read to
     check that none of their statements is in the training data.
  2. For every example, builds the text the training sees (the chat template over system, user and
     assistant messages) and the text the app feeds the model at inference (system and user messages,
     generation prompt, `enable_thinking` off), and checks that the training text is exactly the inference
     prompt followed by the answer and the end of turn. A difference would mean the adapter learns on text
     the app never produces.
  3. Optionally (--report, with --report-test for a test other than Dataset/test.jsonl): compares the number of
     prompt tokens counted here with the one the iPhone reported for each test statement in an evaluation report.
     They must be equal: it proves that Python and the app tokenize and template the prompt in the same way.
  4. Prints the token counts, to set the maximum sequence length.

Usage:
  python3 Scripts/lora/prepare_data.py --out adapters/data [--report Results/baseline-schema1-....json]
  python3 Scripts/lora/prepare_data.py --source Dataset/v2 --out adapters/data-v2 \
      [--report Results/baseline-test2-....json --report-test Dataset/v2/test2.jsonl]
  python3 Scripts/lora/prepare_data.py --source Dataset/v3 --out adapters/data-v3
"""
import argparse
import json
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
DATASET = ROOT / "Dataset"
MODEL = "mlx-community/Qwen3-4B-4bit"
END_OF_TURN = "<|im_end|>\n"


def load_tokenizer():
    from transformers import AutoTokenizer
    return AutoTokenizer.from_pretrained(MODEL)


def read_jsonl(path):
    return [json.loads(line) for line in path.read_text().splitlines()]


def inference_prompt(tok, messages):
    """What the app feeds the model: the system and user messages and the generation prompt, thinking off."""
    return tok.apply_chat_template(messages[:2], tokenize=False, add_generation_prompt=True, enable_thinking=False)


def check_split(tok, rows, name):
    problems = []
    lengths = []
    for n, row in enumerate(rows, start=1):
        messages = row["messages"]
        assert [m["role"] for m in messages] == ["system", "user", "assistant"], f"{name}:{n} roles"
        trained = tok.apply_chat_template(messages, tokenize=False)
        prompt = inference_prompt(tok, messages)
        expected = prompt + messages[2]["content"] + END_OF_TURN
        if trained != expected:
            problems.append((n, trained, expected))
        lengths.append(len(tok.apply_chat_template(messages, tokenize=True, return_dict=False)))
    return problems, lengths


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", default="Dataset", help="folder with train.jsonl and valid.jsonl (Dataset or Dataset/v2)")
    parser.add_argument("--out", required=True, help="folder for train.jsonl and valid.jsonl (e.g. adapters/data)")
    parser.add_argument("--report", help="an evaluation report whose prompt token counts are compared")
    parser.add_argument("--report-test", default="Dataset/test.jsonl", help="the chat file of the test the report ran on")
    args = parser.parse_args()

    tok = load_tokenizer()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    failed = False

    source = (ROOT / args.source).resolve()
    for name in ("train", "valid"):
        rows = read_jsonl(source / f"{name}.jsonl")
        problems, lengths = check_split(tok, rows, name)
        (out / f"{name}.jsonl").write_text((source / f"{name}.jsonl").read_text())
        print(f"{name}: {len(rows)} examples, tokens min {min(lengths)}, median {int(statistics.median(lengths))}, "
              f"max {max(lengths)}; training text != inference text in {len(problems)} examples")
        if problems:
            failed = True
            n, trained, expected = problems[0]
            print(f"  first difference, example {n}:\n  trained : {trained[-160:]!r}\n  expected: {expected[-160:]!r}")

    test_files = [DATASET / "test.jsonl", DATASET / "v2" / "test2.jsonl", DATASET / "v3" / "test3.jsonl"]
    test_statements = {row["messages"][1]["content"] for f in test_files if f.exists() for row in read_jsonl(f)}
    leaked = sum(row["messages"][1]["content"] in test_statements
                 for name in ("train", "valid") for row in read_jsonl(out / f"{name}.jsonl"))
    print(f"test statements ({len(test_statements)} in {', '.join(f.name for f in test_files if f.exists())}) "
          f"found in the training data: {leaked}")
    failed = failed or leaked > 0
    for forbidden in ("test.jsonl", "test2.jsonl", "test3.jsonl"):
        assert not (out / forbidden).exists(), "the data folder must not hold a test split"

    if args.report:
        report = json.loads(Path(args.report).read_text())
        test_rows = read_jsonl(ROOT / args.report_test)
        mismatches, compared = 0, 0
        for record in report["records"]:
            row = test_rows[record["exampleID"] - 1]
            counted = len(tok(inference_prompt(tok, row["messages"]), add_special_tokens=False)["input_ids"])
            reported = record["generation"]["promptTokens"]
            compared += 1
            mismatches += counted != reported
        print(f"prompt tokens, Python against the iPhone: {compared - mismatches} of {compared} equal")
        failed = failed or mismatches > 0

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
