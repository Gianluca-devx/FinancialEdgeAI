# Run record: lora-v2

How the adapter of Phase 2b was trained (`Specs/phase-2b-lora-wording.md`, D26). The weights are not in the repository
(`.gitignore`); this record, `Scripts/lora/lora-v2.yaml`, `Scripts/lora/stop_rule.py` and the data
(`Dataset/v2/train.jsonl`, `valid.jsonl`) reproduce the run. A new run with the same seed on the same Mac is not guaranteed
to give the same bytes.

| | |
|---|---|
| Date | 2026-10-18, started 11:08 local, stopped by the stop rule at about 13:10 (about 2 hours) |
| Machine | Mac with an M4 chip, 24 GB; mlx 0.32.4, mlx-lm 0.32.2, Python 3.14.6 (virtual environment recreated for this run) |
| Command | `mlx_lm.lora -c Scripts/lora/lora-v2.yaml`, with `Scripts/lora/stop_rule.py --pid <pid>` following the log |
| Base model | `mlx-community/Qwen3-4B-4bit` |
| Data | `adapters/data-v2/train.jsonl` (480) and `valid.jsonl` (48, wording held out of the training data), copied by `prepare_data.py --source Dataset/v2`; no test statement (the 60 statements of `Dataset/test.jsonl` and `Dataset/v2/test2.jsonl` were checked) |
| Data check | training text equals inference text in all 528 examples; the longest example has 835 tokens (limit 1024); Python counts the same prompt tokens as the iPhone (90 of 90 on test 2) |
| Method | LoRA, rank 8, scale 20, dropout 0, the last 16 layers, loss on the answer only (`mask_prompt`): as `lora-v1` |
| Optimiser | Adam, learning rate 1e-4, batch size 4, seed 1: as `lora-v1` |
| Planned | up to 600 iterations, validation and checkpoint every 50; the stop rule may end the run earlier |
| Trainable parameters | 7.340 M of 4022.468 M (0.182%) |

## Losses

| Iteration | Validation loss (held-out wording) | Training loss | |
|---|---|---|---|
| 1 | 0.390 | | |
| 10 | | 0.113 | |
| 50 | 0.051 | 0.021 | |
| 100 | 0.029 | 0.005 | |
| 150 | 0.040 | 0.008 | miss 1 |
| 200 | **0.027** | 0.002 | **best, chosen** |
| 250 | 0.030 | 0.001 | miss 1 |
| 300 | 0.041 | 0.001 | miss 2 |
| 350 | 0.032 | 0.000 | miss 3: the rule stops |

## The stop rule, as written before the run

Stop after 3 validations in a row without a strictly lower loss, once that iteration's checkpoint is saved; use the saved
checkpoint with the lowest validation loss (the earliest on a tie). It was applied by `stop_rule.py`, not by me: the best
validation was at iteration 200 (0.027); iterations 250 (0.030), 300 (0.041) and 350 (0.032) did not improve; the program
saw the checkpoint of 350 saved and stopped the process. The rule was tested before the run on synthetic logs (trigger, tie,
wait for the save, reset after an improvement, a repeated line) and on the log of `lora-v1`.

The test splits were never evaluated by the training tool (`--test` is not used) and were not looked at before the
checkpoint was chosen. The choice used the validation split only.

## What was chosen

**Iteration 200** (`0000200_adapters.safetensors`). The `iters: 600` in its `adapter_config.json` is the planned value, not
what ran (350).

| File | Size | SHA-256 |
|---|---|---|
| `adapter_config.json` | | `b3316f1d50b823bb...` |
| `adapters.safetensors` (iteration 200) | 29,384,266 bytes | `ffbdc621dc725d57...` |

For reference, the last checkpoint (iteration 350, the `adapters.safetensors` the tool leaves in its folder) is `d573143213e0be56...`
and is **not** the one chosen. Assembled in `adapters/phone/lora-v2/` for the phone: `Documents/Adapters/lora-v2/`, loaded with
`-adapterName lora-v2`. The two hashes (first 16 characters) will be in the evaluation reports.

## What the losses say

- **The validation split now carries information.** In `lora-v1` the validation loss was 0.001 to 0.003 from iteration 50 (the
  wording equalled the training wording); here, with held-out wording, it is 0.027 at best: more than twenty times higher,
  and it moves (0.051, 0.029, 0.040, 0.027, 0.030, 0.041, 0.032). The training loss falls to 0.000: the adapter fits the training
  wording perfectly and the held-out loss does not follow, which is the gap that `lora-v1` could not see.
- **The curve is noisy and flat after iteration 100** (0.027 to 0.041 over 48 validation statements): the choice of iteration 200 over
  100 (0.029) is a difference of 0.002, within the noise of the curve. The evaluation on the test sets, not this loss, says whether
  the adapter is better.
- One training run, one seed.
