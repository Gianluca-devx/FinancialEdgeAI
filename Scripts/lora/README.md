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

## Phase 2b: `lora-v2` (more varied wording, `Dataset/v2`)

```
venv/bin/python Scripts/lora/prepare_data.py --source Dataset/v2 --out adapters/data-v2 \
    [--report <evaluation report> --report-test Dataset/v2/test2.jsonl]
mkdir -p adapters/lora-v2
venv/bin/mlx_lm.lora -c Scripts/lora/lora-v2.yaml > adapters/lora-v2/train.log 2>&1 &
python3 Scripts/lora/stop_rule.py --log adapters/lora-v2/train.log --pid <pid of mlx_lm.lora>
python3 Scripts/lora/stop_rule.py --log adapters/lora-v2/train.log --select      # which checkpoint, after the run
```

- Same method and hyperparameters as `lora-v1`; the data is `Dataset/v2` (480 training statements, a validation split
  whose wording is held out of training) and the run is up to 600 iterations.
- **The stop rule is a program, not a judgement** (`stop_rule.py`, from the spec): the run stops after 3 validations in a
  row without a strictly lower loss, and the checkpoint with the lowest validation loss is used (the earliest on a tie).
- `prepare_data.py` checks, as before, that the training text equals the inference text and that no statement of
  `Dataset/test.jsonl` or `Dataset/v2/test2.jsonl` is in the training data; the test splits are never copied.

