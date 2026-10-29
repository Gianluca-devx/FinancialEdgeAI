#!/usr/bin/env python3
"""Phase 2f, conditions A and C on the Mac (Specs/phase-2f-pdf-pilot.md, P1): the model reads one page per call.

The same model, adapter, prompt and settings as the phone runs: Qwen3-4B-4bit with `lora-v3` seed 1 (checkpoint 600),
the core prompt of schema 1, thinking off, temperature 0.2, at most 384 tokens, seeds 1, 2, 3. The adapter is checked by
the hash of its weights before any call. Needs mlx-lm (Scripts/lora/requirements.txt).

  venv/bin/python Scripts/lora/pdf_generate.py --inputs RealSet/pdf/inputs.A.pdfkit.jsonl \
      --answers RealSet/pdf/answers.A.pdfkit.jsonl [--adapter adapters/phone/lora-v3] [--seeds 1 2 3]

Each line of the answers file: {"report", "page", "priority", "seed", "answer" (the raw text), "promptTokens", "seconds"}.
A run can be resumed: a (report, page, seed) already in the answers file is skipped. Nothing is printed from the text.
"""
import argparse
import hashlib
import json
import time
from pathlib import Path

MODEL = "mlx-community/Qwen3-4B-4bit"
WEIGHTS = {"lora-v3": "26a0d90702e19f00"}      # seed 1, checkpoint 600 (Scripts/lora/runs/lora-v3.md)
TEMPERATURE = 0.2
MAX_TOKENS = 384


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", required=True)
    parser.add_argument("--answers", required=True)
    parser.add_argument("--adapter", default="adapters/phone/lora-v3")
    parser.add_argument("--seeds", type=int, nargs="+", default=[1, 2, 3])
    args = parser.parse_args()

    adapter = Path(args.adapter)
    digest = hashlib.sha256((adapter / "adapters.safetensors").read_bytes()).hexdigest()
    expected = WEIGHTS.get(adapter.name)
    if expected is None or not digest.startswith(expected):
        raise SystemExit(f"adapter {adapter} has weights {digest[:16]}, expected {expected}")

    import mlx.core as mx
    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_sampler

    model, tokenizer = load(MODEL, adapter_path=str(adapter))
    sampler = make_sampler(temp=TEMPERATURE)
    rows = [json.loads(line) for line in Path(args.inputs).read_text().splitlines() if line.strip()]
    out = Path(args.answers)
    done = set()
    if out.exists():
        for line in out.read_text().splitlines():
            if line.strip():
                r = json.loads(line)
                done.add((r["report"], r["page"], r["seed"]))
    with out.open("a") as f:
        for seed in args.seeds:
            for row in rows:
                if (row["report"], row["page"], seed) in done:
                    continue
                prompt = tokenizer.apply_chat_template(row["messages"], tokenize=False, add_generation_prompt=True,
                                                       enable_thinking=False)
                mx.random.seed(seed)
                start = time.time()
                answer = generate(model, tokenizer, prompt=prompt, max_tokens=MAX_TOKENS, sampler=sampler)
                f.write(json.dumps({"report": row["report"], "page": row["page"], "priority": row["priority"], "seed": seed,
                                    "answer": answer, "promptTokens": len(tokenizer.encode(prompt)),
                                    "seconds": round(time.time() - start, 2)}) + "\n")
                f.flush()
    print(f"answers in {out}: {len(rows) * len(args.seeds)} expected, {len(done)} were already there")


if __name__ == "__main__":
    main()
