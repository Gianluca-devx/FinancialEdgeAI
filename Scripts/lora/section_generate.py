#!/usr/bin/env python3
"""Phase 3 on the Mac (Specs/phase-3-report-sections.md, S1 and S5): the overview and business answers of the model.

Qwen3-4B-4bit, thinking off, temperature 0.2, at most 256 tokens, seeds 1, 2, 3, the prompts of Prompts/. Condition B is
the base model (no --adapter); condition L is `lora-v3` seed 1, checked by the hash of its weights before any call.
Needs mlx-lm (Scripts/lora/requirements.txt).

  window --located FILE --out FILE   the texts of `Scripts/sections.py locate`, cut at 2,500 tokens of the model's
                                     tokenizer at a word boundary: the exact texts the model reads and the labels come from
  run --texts FILE --answers FILE [--adapter adapters/phone/lora-v3] [--sections overview business] [--seeds 1 2 3]

Each answer line: {"id", "section", "seed", "condition", "answer" (the raw text), "finish", "promptTokens",
"generationTokens", "seconds", "prompts" (the hash of the four prompt files)}. A run can be resumed: an (id, section, seed)
already in the answers file is skipped; a file written with another condition or other prompts is refused. Nothing is
printed from the text.
"""
import argparse
import hashlib
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import sections  # noqa: E402

MODEL = "mlx-community/Qwen3-4B-4bit"
WEIGHTS = {"lora-v3": "26a0d90702e19f00"}      # seed 1, checkpoint 600 (Scripts/lora/runs/lora-v3.md)
TEMPERATURE = 0.2
MAX_TOKENS = 256


def window(located: Path, out: Path):
    from mlx_lm import load
    _, tokenizer = load(MODEL)
    encode = lambda text: tokenizer.encode(text, add_special_tokens=False)  # noqa: E731
    reports = json.loads(located.read_text())["reports"]
    texts = []
    for name, report in reports.items():
        text, count = sections.cut(report["text"], encode, tokenizer.decode)
        texts.append({"id": name, "text": text, "tokens": count, "pages": report["pages"]})
    out.write_text(json.dumps({"kind": "reports", "from": located.name, "limit": sections.TOKEN_LIMIT, "texts": texts},
                              indent=1))
    print(f"texts: {len(texts)}, tokens {min(t['tokens'] for t in texts)} to {max(t['tokens'] for t in texts)}")


def condition_of(adapter):
    if adapter is None:
        return "B", None
    path = Path(adapter)
    digest = hashlib.sha256((path / "adapters.safetensors").read_bytes()).hexdigest()
    expected = WEIGHTS.get(path.name)
    if expected is None or not digest.startswith(expected):
        raise SystemExit(f"adapter {path} has weights {digest[:16]}, expected {expected}")
    return "L", str(path)


def run(texts_path: Path, answers: Path, adapter, chosen, seeds):
    condition, adapter_path = condition_of(adapter)
    snapshot, prompts = sections.load_prompts()
    texts = json.loads(texts_path.read_text())["texts"]
    done = set()
    if answers.exists():
        for row in sections.read_jsonl(answers):
            if row["condition"] != condition or row["prompts"] != prompts:
                raise SystemExit(f"{answers} holds answers of condition {row['condition']} with prompts {row['prompts']}")
            done.add((row["id"], row["section"], row["seed"]))

    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler

    model, tokenizer = load(MODEL, adapter_path=adapter_path)
    sampler = make_sampler(temp=TEMPERATURE)
    written = 0
    with answers.open("a") as f:
        for seed in seeds:
            for section in chosen:
                for text in texts:
                    if (text["id"], section, seed) in done:
                        continue
                    prompt = tokenizer.apply_chat_template(sections.messages(section, text["text"], snapshot),
                                                           tokenize=False, add_generation_prompt=True,
                                                           enable_thinking=False)
                    mx.random.seed(seed)
                    start = time.time()
                    parts, last = [], None
                    for response in stream_generate(model, tokenizer, prompt, max_tokens=MAX_TOKENS, sampler=sampler):
                        parts.append(response.text)
                        last = response
                    f.write(json.dumps({"id": text["id"], "section": section, "seed": seed, "condition": condition,
                                        "answer": "".join(parts), "finish": last.finish_reason,
                                        "promptTokens": last.prompt_tokens, "generationTokens": last.generation_tokens,
                                        "seconds": round(time.time() - start, 2), "prompts": prompts}) + "\n")
                    f.flush()
                    written += 1
    print(f"answers in {answers}: {written} written, {len(done)} were already there (condition {condition}, "
          f"prompts {prompts})")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", choices=["window", "run"])
    parser.add_argument("--located")
    parser.add_argument("--out")
    parser.add_argument("--texts")
    parser.add_argument("--answers")
    parser.add_argument("--adapter")
    parser.add_argument("--sections", nargs="+", default=list(sections.SECTIONS), choices=sections.SECTIONS)
    parser.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3])
    args = parser.parse_args()
    if args.command == "window":
        window(Path(args.located), Path(args.out))
    else:
        run(Path(args.texts), Path(args.answers), args.adapter, args.sections, args.seeds)


if __name__ == "__main__":
    main()
