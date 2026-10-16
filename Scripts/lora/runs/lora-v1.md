# Run record: lora-v1

How the adapter evaluated in `Results/lora-v1-analysis.md` was trained. The weights are not in the repository
(`.gitignore`); this record, `Scripts/lora/lora-v1.yaml` and the data (`Dataset/train.jsonl`, `valid.jsonl`)
reproduce them. A new run with the same seed on the same Mac is not guaranteed to give the same bytes.

| | |
|---|---|
| Date | 2026-10-16, started 14:53 local, stopped by hand after the report of iteration 170 (the log was last written at 16:19) |
| Machine | Mac with an M4 chip, 24 GB; mlx 0.32.4, mlx-lm 0.32.2, Python 3.14.6 |
| Command | `mlx_lm.lora -c Scripts/lora/lora-v1.yaml` |
| Base model | `mlx-community/Qwen3-4B-4bit` |
| Data | `adapters/data/train.jsonl` (240) and `valid.jsonl` (30), copied by `Scripts/lora/prepare_data.py`; no test statement |
| Method | LoRA, rank 8, scale 20, dropout 0, the last 16 layers, loss on the answer only (`mask_prompt`) |
| Optimiser | Adam, learning rate 1e-4, batch size 4, seed 1, `max_seq_length` 1024 (the longest example: 785 tokens) |
| Planned | 300 iterations (5 epochs), validation and checkpoint every 50 |
| Trainable parameters | 7.340 M of 4022.468 M (0.182%) |

## Losses

| Iteration | Validation loss | Training loss |
|---|---|---|
| 1 | 0.372 | |
| 10 | | 0.081 |
| 40 | | 0.018 |
| 50 | 0.002 | |
| 100 | 0.003 | |
| 150 | 0.001 | |
| 160, 170 | | 0.000 |

## The early stop

Training was **stopped by hand at iteration about 170 of 300**. Reason: the validation loss had been flat at
0.001 to 0.003 since iteration 50, the training loss was 0.000, and the speed had dropped from 28 to 15 tokens/s
because the Mac was under memory pressure. More iterations would only have fitted the training data further.
The decision used the validation split only; the test split was never evaluated by the training tool (`--test`
is not used) and was not looked at before the checkpoint was chosen.

The adapter of **iteration 150** (`0000150_adapters.safetensors`, the last checkpoint saved, identical to
`adapters.safetensors`) was evaluated. The `iters: 300` in its `adapter_config.json` is the planned value, not
what ran.

## What was evaluated

| File | Size | SHA-256 |
|---|---|---|
| `adapter_config.json` | | `aefaad21fe0c390f...` |
| `adapters.safetensors` (iteration 150) | 29,384,266 bytes | `aadab981fed8cd97...` |

Copied to the phone as `Documents/Adapters/lora-v1/` and loaded with `-adapterName lora-v1`. The two hashes
(first 16 characters) are in the evaluation report and its tables.
