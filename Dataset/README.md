# Dataset

Labelled financial statements for the extraction task: unstructured text in, the core fields of
`schema.json` out, each as a string copied from the text. 300 examples, in the chat format that
`mlx_lm.lora` reads.

This is **schema version 1 (Phase 1)**. The dataset of v1.1.0 (7 numeric fields) is kept, unchanged,
in [`archive/v1.1.0/`](archive/v1.1.0): the baseline reports of v1.1.0 can only be read with it.

| File | Examples | Purpose |
|---|---|---|
| `schema.json` | | The only list of fields: 13 core, 5 extended, 11 derived. The prompt is rendered from it. |
| `train.jsonl` | 240 | Fine-tuning |
| `valid.jsonl` | 30 | Validation loss while fine-tuning |
| `test.jsonl` | 30 | Frozen. Used only for the baseline and the final comparison. Never edit it. |
| `*.labels.jsonl` | one line per example | The sidecar: all 18 fields, each `{"text", "value"}` or `null`. `text` is the string as printed, `value` the true number. |
| `prompt_template.txt` | | The exact user prompt, rendered from the schema. `<<STATEMENT>>` is replaced by the statement. |
| `system_prompt.txt` | | The system message. |
| `index.csv` | 300 rows | Split, line, source, scenario, phrasing pool, unit, distractors. For error analysis. |

Each line of a `.jsonl` file is `{"messages": [system, user, assistant]}`. The assistant message is the
target JSON with the 13 core keys, no Markdown fence. The 5 extended fields are labelled only in the
sidecar: they belong to a second call with its own prompt, built later.

## Labelling rules

They are the rules of the prompt:

- Every value is a **string copied exactly as printed** in the statement (`"$726 million"`, `"$6.9bn"`,
  `"2,772 million"`, `"23.5%"`, `"USD 1.25"`), or `null` when the statement does not give it. Nothing is
  converted, calculated or rounded by the model: code turns the string into a number.
- A growth is the percent change as stated. A decrease is written with a leading minus: the statement
  says "down 4%", the label is `"-4%"`. The statement may print `(+8%)` or `-2%` itself, then the label
  is that string.
- A value is never calculated, even when it could be: if a statement gives this year and last year but
  no percentage, the growth is `null`. Code derives it afterwards.
- `previousYearRevenue`, `previousYearNetIncome` and `previousYearEps` are the previous-year values of
  the same metric. The previous-year operating income, and the operating income growth, are not fields:
  they are distractors, like margins, headcount, dividends, total assets, free cash flow, the share
  price and guidance for next year.
- `value` in the sidecar is in billions of USD for amounts, a percentage number for growth (4 for 4%),
  and USD per share for EPS. It is written by the generator from the number it printed, not by parsing
  the text, so the Swift tests can check the parser against it.

## How it was built

- **Generated (276):** `Scripts/generate_dataset.py` builds statements from templates with a fixed seed,
  so every label is correct by construction and the files are reproducible. Scenarios (a cycle of 30,
  spread over every split): all income fields, basic income, prior year without growth, amounts only,
  EPS only, cash flow, interest, balance sheet, growth without amounts, a random subset of all 18
  fields, and statements with none of the fields. On top of that: figures in millions (about 20% of the
  statements with amounts), distractor sentences (about 40% of the statements that contain fields),
  and operating income growth or prior year as distractors.
- **Hand-written (24):** fictional companies, labels checked by hand. 20 are the hand-written
  statements of v1.1.0, relabelled for the new schema; 4 are new (EPS, cash flow, balance sheet). They
  are in `train`, `valid` and `test`. The statement used for the first on-device test (revenue 94, net
  income 21 down 4% from 21.9) is in `test`.
- **Held-out wording:** 12 of the 30 test statements use verbs, metric names, amount formats and
  sentence patterns that never appear in `train` or `valid`, so the test split also measures unseen
  phrasing. Their rows have `pool = B` in `index.csv`.
- **No example of the prompt in a statement:** the prompt gives example values (`$7.4 billion`,
  `(2.4) billion`, `8.2%`, `-6.8%`). No statement contains these numbers, so no statement is answered
  by the prompt itself. The generator rejects such statements and the validator checks it.

## Commands

```
python3 Scripts/prompt_from_schema.py --write  # renders prompt_template.txt from schema.json
python3 Scripts/generate_dataset.py            # rewrites the files (same seed, same output)
python3 Scripts/validate_dataset.py            # checks schema, prompt, format, labels, leakage, bundled copies
```

After regenerating, copy `prompt_template.txt`, `test.jsonl`, `test.labels.jsonl` and `index.csv` to
`FinancialEdgeAI/Resources/`; the validator fails if a bundled copy differs.

The validator checks that every line parses, the target has exactly the core keys with a string or
`null` per key, the sidecar agrees with it, every non-null text appears in the statement (a percent
may carry a leading minus), and no statement is shared between files. It does not check the parser: the
Swift tests check `ValueParser(text) == value` for every line of every split, and the signs of the
growth values are right by construction in the generated part and were checked by hand in the
hand-written part.

## Differences from the dataset of v1.1.0

Results measured with the v1.1.0 dataset and prompt cannot be compared with this one as if they were
the same experiment: the prompt, the output format (strings instead of numbers), the fields (13 instead
of 7) and all the statements changed. Only 6 fields exist in both (`revenue`, `operatingIncome`,
`netIncome`, `previousYearNetIncome`, `revenueGrowth`, `netIncomeGrowth`), and even those are only an
indication. `operatingIncomeGrowth` is no longer a field.

## Limits

- The statements are synthetic and short. A model that does well here may still fail on real
  reports. The held-out wording only partly tests that.
- English and USD only. No net losses (a negative net income), no statements with several periods or
  segments, and no unit stated only in a table header ("in millions"). `ValueParser` reads a
  parenthesised negative, but the dataset does not test it.
- 30 test statements is small: one example is 3.3 percentage points. The extended fields appear in
  only 3 or 4 test statements each, and the cash flow and interest fields in 3 to 5, so the accuracy of
  one such field is a rough indication. The test split has 1 statement with none of the fields.
- Test, valid and train sizes (240 / 30 / 30) are unchanged from v1.1.0, so a baseline takes the same
  number of answers. Enlarging the test split is possible but is a new experiment.
