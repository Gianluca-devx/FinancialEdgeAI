# Dataset v2 (Phase 2b)

Written by `Scripts/generate_dataset_v2.py`, checked by `Scripts/validate_dataset_v2.py` (and by
`Scripts/validate_dataset.py`, which calls it). Spec: `Specs/phase-2b-lora-wording.md`. Nothing in `Dataset/` outside
this folder is changed by it: the validator proves every other file is byte-identical to the tag `v2.2.0`.

Same chat format, same system message, same core prompt, same 13 core fields, same labelling rules as `Dataset/`.

| File | Statements | Wording | Purpose |
|---|---|---|---|
| `train.jsonl` | 480 (456 generated, 24 hand-written) | pool A (the first dataset's) and A2 (new) | Training |
| `valid.jsonl` | 48 | pool V | Validation loss: its wording is not in train, so the loss shows overfitting to the training wording |
| `test2.jsonl` | 30 (20 generated, 10 hand-written) | pool C | A second test set, frozen before training, never used to choose a checkpoint |
| `*.labels.jsonl` | one line per statement | | The sidecar: all 18 fields, `{"text", "value"}` or `null` |
| `index.csv` | 558 rows | | Split, line, source, scenario, wording pool, unit, distractors, structure |

The old test (`Dataset/test.jsonl`, pool B) stays the primary comparison. The wording of pools B, V and C is
**held out**: the validator fails if a phrase of B, V or C is in train, if B or C is in valid, or if B or V is in test 2.

What is new compared with the first dataset: several names for every metric (the first training pool had one phrase
for net income and for operating income), other forms for the previous period and for growth, other number forms
the parser reads (`US$11.3 billion`, `11.3 billion USD`), other structures (lines, bullet lists, table rows in
train; the group in validation; first person, headings and dashes in test 2), and every core field stated in at
least 25% of the training statements. The null scenarios stay.
