# LoRA adapter, how it is trained

The written spec is [`Specs/phase-2-lora.md`](../../Specs/phase-2-lora.md). This folder is the only place of
`Scripts/` that is not standard library only: it needs `mlx-lm` (and `transformers`, which comes with it).

```
python3 -m venv venv && venv/bin/pip install -r Scripts/lora/requirements.txt
venv/bin/python Scripts/lora/prepare_data.py --out adapters/data [--report <evaluation report>]
venv/bin/mlx_lm.lora -c Scripts/lora/lora-v1.yaml
```

- `prepare_data.py` copies `Dataset/train.jsonl` and `valid.jsonl` to `adapters/data/` and checks, for every
  example, that the text the training sees is exactly the text the app feeds the model at inference (system and
  user message, generation prompt, thinking off) followed by the answer. With `--report` it also compares the
  prompt token counts of Python with those that the iPhone reported: they must be equal.
- The test split is never read, and `mlx_lm.lora --test` (which evaluates on the test split) is not used.
- `lora-v1.yaml` holds every hyperparameter and the seed. The results are in `adapters/lora-v1/` (the log, the
  checkpoints, `adapter_config.json`). **The weights are never committed** (`.gitignore` excludes `/adapters/` and
  `*.safetensors`); the data, the config and the seed are what reproduce them.
- The adapter is loaded by the app at run time from `Documents/Adapters/<name>` (copy it with
  `xcrun devicectl device copy to`), selected with the launch argument `-adapterName <name>`.
