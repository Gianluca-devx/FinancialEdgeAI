# Dataset

Labelled financial statements for the extraction task: unstructured text in, the 7-field
`FinancialMetrics` JSON out. 300 examples, in the chat format that `mlx_lm.lora` reads.

| File | Examples | Purpose |
|---|---|---|
| `train.jsonl` | 240 | Fine-tuning |
| `valid.jsonl` | 30 | Validation loss while fine-tuning |
| `test.jsonl` | 30 | Frozen. Used only for the baseline and the final comparison. Never edit it. |
| `prompt_template.txt` | | The exact user prompt. `<<STATEMENT>>` is replaced by the statement. |
| `index.csv` | 300 rows | Split, line, source, scenario, phrasing pool, unit, distractors. For error analysis. |

Each line of a `.jsonl` file is `{"messages": [system, user, assistant]}`. The assistant message is
the target JSON, with no Markdown fence.

## Labelling rules

They are the rules of the prompt:

- Monetary values are in billions of USD. A statement written in millions is converted
  (`$410 million` becomes `0.41`).
- Growth is a percentage number without `%`. A decline is negative.
- `null` when a value is not stated. A value is never calculated, even when it could be: if a
  statement gives this year and last year but no percentage, the growth is `null`.
- `previousYearNetIncome` is the prior-year net income. Prior-year revenue or operating income is
  not requested, so it is ignored.
- Numbers that are not requested (margins, EPS, dividends, headcount, guidance for next year) are
  ignored.

## How it was built

- **Generated (280):** `Scripts/generate_dataset.py` builds statements from templates with a fixed
  seed, so every label is correct by construction and the files are reproducible.
  Scenarios: all fields, no prior year, prior year without growth, amounts only, no operating
  income, revenue only, net income only, growth without amounts, a random subset, and statements
  with none of the requested metrics. On top of that: figures in millions (about 19%), distractor
  sentences (about 31% of the statements that contain metrics), and prior-year amounts for
  revenue and operating income in some statements.
- **Hand-written (20):** fictional companies, labels checked by hand. They are in `train`, `valid`
  and `test`. The statement used for the first on-device test (revenue 94, net income 21 down 4%
  from 21.9) is in `test`.
- **Held-out wording:** 13 of the 30 test statements use verbs, metric names, amount formats and
  sentence patterns that never appear in `train` or `valid`, so the test split also measures
  unseen phrasing. Their rows have `pool = B` in `index.csv`.

## Commands

```
python3 Scripts/generate_dataset.py   # rewrites the files (same seed, same output)
python3 Scripts/validate_dataset.py   # checks format, labels and leakage
```

The validator checks that every line parses, the target has exactly the 7 keys with a number or
`null` per key, every non-null value appears in the statement (a growth may be negative, an amount
may be written in millions), and no statement is shared between files. It does not check the sign
of a growth value: signs are right by construction in the generated part and were checked by hand
in the hand-written part.

## Differences from the Step 1 prompt and the app

Results measured with the first prompt cannot be compared with this dataset as if they were the
same experiment. This prompt differs in two ways:

- The duplicated bullets (`net income`, `net income growth`) are removed, and the last bullet reads
  `Previous-year net income`.
- The system message is `You are a financial expert that is able to retrieve JSON from unstructured
  text`. `LLMService.swift` has the same sentence with two spelling mistakes (`retrive`,
  `unstructed`). Before the baseline, the app and the evaluation must use the identical system
  message and prompt text.

## Limits

- The statements are synthetic and short. A model that does well here may still fail on real
  reports. The held-out wording only partly tests that.
- English and USD only. No net losses (a negative net income) and no statements with several
  periods or segments.
- 30 test statements is small: one example is 3.3 percentage points.
