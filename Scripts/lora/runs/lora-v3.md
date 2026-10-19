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

(added after the runs)
