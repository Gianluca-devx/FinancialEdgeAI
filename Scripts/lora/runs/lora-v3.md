# Run record: lora-v3 (and the second seeds)

How the adapters of Phase 2d are trained (`Specs/phase-2d-real-distractors.md`, D38, D39). **This first part is the plan,
committed before any of the three runs starts**; the results are added below it after the runs. The weights are not in the repository.

## The plan

| | |
|---|---|
| Data | `adapters/data-v3/train.jsonl` (720 = 480 of v2 + 240 new) and `valid.jsonl` (72), copied by `prepare_data.py --source Dataset/v3`. Frozen in Amendment 2 of the spec: SHA-256 of the seven files in order `66181954b3c74c17519096a3c3bc3e01bef3702784d3962171b066699bea4a12` (`Dataset/v3` unchanged since 0b40ca6) |
| Data check (run on 2026-10-19) | training text equals inference text in all 792 examples; longest example 964 tokens (limit 1024); **0 of the 90 test statements** (`Dataset/test.jsonl`, `Dataset/v2/test2.jsonl`, `Dataset/v3/test3.jsonl`) in the training data; no passage of the real reports has a run of 6 words in any statement (validator) |
| Method | as `lora-v2`: LoRA rank 8, scale 20, dropout 0, the last 16 layers, loss on the answer only (`mask_prompt`), Adam, learning rate 1e-4, batch size 4 |
| Runs (in this order, one after another on the Mac) | (1) `lora-v3` seed 1: `mlx_lm.lora -c Scripts/lora/lora-v3.yaml`, adapter folder `adapters/lora-v3`; (2) `lora-v3` seed 2: the same with `--seed 2 --adapter-path adapters/lora-v3-s2`; (3) `lora-v2` seed 2: `mlx_lm.lora -c Scripts/lora/lora-v2.yaml --seed 2 --adapter-path adapters/lora-v2-s2` (on `adapters/data-v2`, the data of the first `lora-v2`, which was seed 1) |
| Length | up to 900 iterations for v3 (5 epochs of 720), up to 600 for `lora-v2` (as the first run), validation and checkpoint every 50 |
| Stop rule | unchanged, applied by `Scripts/lora/stop_rule.py` (program): stop after 3 validations in a row without a strictly lower loss, once that checkpoint is saved; use the saved checkpoint with the lowest validation loss, the earliest on a tie. No judgement and no test split in the choice |
| Environment | the same Mac (M4, 24 GB), `mlx-lm` 0.32.2, `mlx` 0.32.4, the virtual environment of the session; `HF_HUB_OFFLINE=1` (the model is in the cache; the network was unreliable) |
| Not done | `--test` is never used; no test split is evaluated by the training tool |

**Order of work, disclosed.** The spec lists the references on `real3` (step 4) before the training (step 5), but the two do not depend on each other: the phone is busy
with the references on `test3` and then on `real3`, and the Mac is free. The training starts now, and **no `lora-v3` adapter is run on any set before the references on `test3` and
`real3` exist** (D40: the thresholds that depend on the references cannot depend on `lora-v3`). The criteria were written before the runs and do not change.

## Results

### Run 1: `lora-v3`, seed 1 (2026-10-22, 00:42 to 05:32, 289 minutes)

Same Mac, `mlx-lm` 0.32.2, `mlx` 0.32.4, `HF_HUB_OFFLINE=1`, started by `mlx_lm.lora -c Scripts/lora/lora-v3.yaml`, followed by `stop_rule.py --pid <pid>`.
Trainable parameters 7.340 M of 4022.468 M (0.182%). Data check as in the plan (training data byte-identical to `Dataset/v3`).

| Iteration | Validation loss (72 statements, wording and templates held out) | |
|---|---|---|
| 1 | 0.418 | |
| 50 | 0.043 | |
| 100 | 0.036 | |
| 150 | 0.037 | |
| 200 | 0.030 | |
| 250 | 0.039 | |
| 300 | 0.031 | |
| 350 | 0.026 | |
| 400 | 0.036 | |
| 450 | 0.023 | |
| 500 | 0.027 | |
| 550 | 0.035 | |
| 600 | **0.020** | **best, chosen** |
| 650 | 0.021 | miss 1 |
| 700 | 0.020 | miss 2 (equal to the best, not strictly lower) |
| 750 | 0.023 | miss 3: the rule stops |

**The stop rule, applied by the program:** the best validation is iteration 600 (0.020); 650, 700 (a tie, which is not an improvement) and 750 did not improve, so the program
stopped the process after the checkpoint of 750 was saved. The chosen checkpoint is the lowest loss, the earliest on the tie: **iteration 600**
(`0000600_adapters.safetensors`). The `iters: 900` in the saved `adapter_config.json` is the planned value, not what ran (750). Assembled in `adapters/phone/lora-v3/`.

| File | Size | SHA-256 |
|---|---|---|
| `adapter_config.json` | | `a5a91a164061b1c1b4084046c99bf2a9f6783d2c9010258206864af1ba0b6b11` |
| `adapters.safetensors` (iteration 600) | 29,384,266 bytes | `26a0d90702e19f00e97ba73555c0084d91d9432a10dceddf1c56c0deb0527959` |

**What the losses say.** The validation loss goes from 0.043 (iteration 50) to 0.020 (600), lower than `lora-v2`'s best (0.027 on its own, smaller validation set of 48; the two
numbers are on different validation sets and are not compared). The curve is noisy (0.020 to 0.039 from iteration 200), so the choice of 600 over 450 (0.023) is a difference within the
noise of the curve, as for `lora-v2`: the evaluation, not this loss, says whether the adapter is better. The run is longer than `lora-v2`'s (750 against 350 iterations) because the
loss kept improving with a slow trend. One seed.

**An interrupted first attempt, kept as evidence, not used.** The same command was started on 2026-10-19 (15:19) and killed by hand at iteration 310 because the Mac was needed
(an earlier start was killed at iteration 0). Its seven validations (iterations 1 to 300) are **identical to the three decimals** to the first seven of the finished run: with the same seed the
training is reproducible here, which also means the interruption did not change the run. Its folder is `adapters/lora-v3-interrupted-it310` (not in the repository).

### Runs 2 and 3: seed 2 of `lora-v3` and seed 2 of `lora-v2`

Skipped on the night of 2026-10-22 by the time guard (the first run took 289 minutes and the Mac was needed at 08:30), started the same evening at 17:58, one after the other. (added after the runs)
