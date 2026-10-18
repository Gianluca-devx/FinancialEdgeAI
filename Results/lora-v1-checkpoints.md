# lora-v1: the checkpoints of iterations 50 and 100, on the old test

Step 2 of `Specs/phase-2b-lora-wording.md` (D27). The adapter `lora-v1` was trained for about 170 iterations and the
checkpoint of iteration 150 was evaluated (`Results/lora-v1-analysis.md`). The checkpoints of iterations 50 and 100 were
kept on the Mac and are evaluated here, with nothing else changed: the same prompt, test split, seeds, settings and phone
(prompt `7779853b346c`, test `1eb1fc231078`, three runs, temperature 0.2). No dataset, no app change: the three
checkpoints and the baseline are compared on the same 30 statements. Tables: `lora-v1-it050-tables-iphone-20261017.md`,
`lora-v1-it100-tables-iphone-20261017.md`. Raw reports: `lora-v1-it050-...json`, `lora-v1-it100-...json`.
Each report records the adapter's weights hash, and each hash is that of the checkpoint file (checked).

## Result

| | Baseline (no adapter) | Iteration 50 | Iteration 100 | Iteration 150 (`lora-v1`) |
|---|---|---|---|---|
| Validation loss (first dataset's validation split) | | 0.002 | 0.003 | 0.001 |
| Decodable answers | 90 / 90 | 88 / 90 | 90 / 90 | 90 / 90 |
| **All 13 fields correct** | 57 / 90 | 68 / 90 | **42 / 90** | **78 / 90** |
| Fields correct | 1115 / 1170 | 1121 / 1170 | 1091 / 1170 | 1155 / 1170 |
| Wrong fields | 55 | 49 | 79 | 15 |
| of which values missed (null where the text states one) | 0 | 15 | **79** | 15 |
| of which hallucinated or unreadable | 55 | 5 | 0 | 0 |
| of which answer not readable, unit, sign, wrong number | 0 | 29 | 0 | 0 |
| Time per statement (median) / peak memory | 10.5 s / 2.72 GiB | 11.9 s / 2.86 GiB | 10.6 s / 2.86 GiB | 11.6 s / 2.86 GiB |

## What it says

- **The misses are not a matter of training too long.** The earlier checkpoints are not better: iteration 50 also has 15
  missed values (in other statements than iteration 150: only statements 8 and 25 fail in both), plus 5 invented or
  unreadable values and two answers that are not valid JSON, and iteration 100 misses 79 values. The idea "stop earlier and it will miss less" is refuted by this test.
- **Quality is not monotonic in the training.** 68, then 42, then 78 fully correct answers. Iteration 100 answers null for most
  of the fields in many statements (for example only the EPS is returned in a statement that also states revenue and income):
  an adapter that has become very cautious for a while. This is one training run with one seed, so the shape of the curve is
  one sample, not a law.
- **The validation loss did not warn.** It was 0.002, 0.003 and 0.001, three numbers that tell nothing about a gap from 42 to 78
  correct answers. The validation split has the same wording as the training split, so it cannot show how the adapter
  behaves on other wording or how cautious it has become. This is the reason for the validation split with held-out wording in
  the Phase 2b dataset (pool V): its loss is the only signal the training will have.
- **A caution about `lora-v1` itself.** The checkpoint that was evaluated (iteration 150) was the one that happened to be the last
  one saved when training was stopped. Its 78 out of 90 is a good draw among checkpoints that vary from 42 to 78, not a
  stable level. The result of `lora-v1` stands as measured, and it should be read with this spread in mind.
- **Practical cost is the same** for the three checkpoints (same adapter size, 2.86 GiB peak, 10.6 s to 11.9 s).

## Limits

One training run, one seed, three checkpoints, 30 statements (effectively one run each, the three runs are identical for
most statements). A different seed could show another shape. Debug build, one phone.
