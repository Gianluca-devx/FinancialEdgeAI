# Spec: Phase 2, LoRA

Status: **approved by delegation** on 2026-10-16 (the user asked to continue without stopping for approvals; the
decisions below are mine, with the alternative). Depends on `Specs/phase-1-schema-prompt.md` (the schema 1
baseline is the reference) and `Specs/phase-1b-extended-call.md`.

**Goal:** specialise Qwen3-4B for the 13 core fields with a LoRA adapter trained on the train split, measure it
on the frozen test split on the iPhone, and say whether it improves on the schema 1 baseline and stays practical
on the phone.

**Out of scope:** the extended call (a second adapter would be a later experiment); changing the prompt, the
schema, the parser or the dataset (the adapter is trained on the dataset as it is); training on the phone;
publishing the weights.

**Inputs:** `Dataset/train.jsonl` and `valid.jsonl` (core prompt, 240 and 30 examples); the baseline report
`Results/baseline-schema1-Qwen3-4B-4bit-iphone-20261016T114216.json` and its analysis.

## The target, from the baseline

The schema 1 baseline has 57 / 90 fully correct (63.3%) and 55 wrong fields, all of them the model writing something
where the label is null: a growth it calculated (21 fields), a previous-year field filled from the wrong place (19),
a value of another period or of a distractor (12), and a correct number written in a form the parser refuses (3).
No unit, sign or wrong-number error, nothing missed. A specialised model should learn to leave those fields null.

## Success criteria (fixed before training)

1. **Fully correct answers: at least 68 / 90 (75.6%)**, against 57 / 90.
2. **Wrong fields: at most 28 of 1170**, against 55 (half).
3. **No loss on what is right:** no unit error, sign error, wrong number or missed value (each stays at 0, or at
   most 5 fields in total), and every answer decodable (90 / 90).
4. **Practical on the phone:** median time per statement at most 12 s (the baseline is 10.5 s), peak memory at
   most 3.0 GiB (2.72 GiB), the thermal state no worse than "serious".
A mixed or negative result is a valid result and is reported as it is.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D15 | Train on the Mac with the Python tool `mlx_lm.lora` (M4, 24 GB), in a virtual environment. | The Swift trainer `LoRATrain`: its loader needs `{"text": ...}` lines and it is less used; the Python tool reads the dataset directly. |
| D16 | The training data is **the chat files as they are** (`train.jsonl`, `valid.jsonl`, messages: system, user, assistant), with the loss on the answer only (`--mask-prompt`). For Qwen3 the chat template renders the last assistant turn with the same empty reasoning block that the app's `enable_thinking: false` puts in the prompt, so the training text is the inference text followed by the answer. `Scripts/lora/prepare_data.py` **checks it for every example** (270), copies the two files to `adapters/data/` and also compares Python's prompt token counts with those the iPhone reported (they must be equal: it proves the app and the training tool template the prompt in the same way). The test split is never read; the tool's `--test` option is not used. | Converting to prompt and completion pairs: the tool wraps a prompt as a single user message, which would lose the system message. |
| D17 | LoRA on the 4-bit base `mlx-community/Qwen3-4B-4bit` (the model of the app): rank 8, scale 20, dropout 0, the last 16 layers, the default keys. Learning rate 1e-4, batch size 4, 300 iterations (5 epochs of 240 examples), validation every 50 iterations, a checkpoint every 50, seed fixed. The checkpoint with the lowest validation loss is the one used. | A higher rank or more layers: more to train and to load, no reason yet. A lower learning rate (the tool's default 1e-5): too slow for 300 iterations. |
| D18 | The adapter is loaded **at run time from a folder** (`adapter_config.json`, `adapters.safetensors`) with `mlx-swift-lm` (`LoRAContainer`), not fused into the weights and not bundled in the app. The folder is copied to the app's `Documents/Adapters/<name>` with `devicectl`. A launch argument `-adapterName <name>` selects it; the Evaluate tab shows which adapter is on. | Fusing and re-quantising a new model: a 2.3 GB model to move to the phone. Bundling the weights: they would be committed (the weights are excluded by `.gitignore` on purpose). |
| D19 | A report records the adapter (name, hashes of its two files, rank, layers). Without an adapter the app behaves exactly as in v2.0.0. | |
| D20 | The same evaluation as the baseline: the 30 test statements, 3 runs, seeds 1, 2, 3, temperature 0.2, `maxTokens` 384, the core prompt. `compare_baselines.py` compares two reports of the same schema field by field. | |

## Design

- **Data:** `Scripts/lora/prepare_data.py` copies the two files to `adapters/data/` (gitignored), checks that
  the training text equals the inference text, that no test statement is in them, and prints token counts.
  `Scripts/lora/` is the one folder of `Scripts/` that needs packages (`mlx-lm`), with a `requirements.txt`.
- **Training:** a documented command with fixed hyperparameters and seed; the log (`adapters/lora-v1/train.log`)
  is kept; only `adapter_config.json` and a `README` of the run are committed, never the weights.
- **App:** `LLMService` can load an adapter from a directory on top of the loaded model (and keeps the model
  untouched when none is given), the name and hashes go into `EvaluationReport.Metadata`, the Evaluate tab shows
  the active adapter. Pure parts (the adapter description, the report fields) are unit-tested.
- **Evaluation:** the baseline procedure, on the iPhone, unlocked, about an hour.

## UI / UX

The Evaluate tab shows "Adapter: none" or the adapter name. The Extract tab is not changed; with an adapter on, the
performance line says so. If the adapter folder is missing or does not fit the model, the app says so and runs
without it (it never silently runs the base model while the screen says "adapter").

## Tests

- The adapter description (name, hashes, rank, layers) is read from `adapter_config.json` and hashed by a pure
  type, with a test on a fixture folder written by the test.
- A report with and without an adapter encodes both cases.
- The data script is checked by running it: training text equals inference text in all 270 examples, the prompt
  token counts equal the iPhone's in 90 of 90 cases, and no test statement is in the training data.
- All earlier tests stay green.

## Acceptance

1. Training finishes; the training and validation loss are logged; the chosen checkpoint is named.
2. The adapter loads on the iPhone and the evaluation runs: 90 answers, every one decodable, the report records the adapter.
3. Results saved under new names, a written analysis with every criterion above checked, and a comparison with
   the schema 1 baseline field by field. The v2.0.0 result files are unchanged.
4. A conclusion on whether local deployment of the specialised model is practical.

## Risks

- **The test split comes from the same generator as the train split.** The adapter may learn the templates, not the
  task. The 12 statements with unseen wording (pool B) are the only indication of generalisation; the result is reported
  with that caveat. Real reports are the open question.
- 240 training examples and 5 epochs: overfitting is possible; the validation loss is watched and the best
  checkpoint kept.
- The adapter runs unfused, which adds a little compute per token; the time criterion has a margin for it.
- A longer run on the phone: the thermal state, as before.
- The Python environment (Python 3.14) may not have wheels for `mlx`; then another Python is used.

## Steps (each one commit)

1. `Scripts/lora/` (data check, config, README) (`data`).
2. Train the adapter on the Mac; keep the log and `adapter_config.json`, never the weights (`model`).
3. The app: load an adapter from a folder, record it in the report, show it (`feat`, `test`).
4. Copy the adapter to the phone and run the evaluation (needs the phone unlocked) (`eval`).
5. Results, analysis, comparison, README (`eval`, `docs`); merge into `dev`, PR to `main`, tag after the merge.

**Branch and commits:** `feature/model-adaptation`; `data`, `model`, `feat`, `test`, `eval`, `docs`. No attribution
lines. Never stage `xcshareddata/` or `xcuserdata/`, never commit weights.
