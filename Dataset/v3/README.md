# Dataset v3 (Phase 2d)

Written by `Scripts/generate_dataset_v3.py`, checked by `Scripts/validate_dataset_v3.py` (and by `Scripts/validate_dataset.py`, which calls
it). Spec: `Specs/phase-2d-real-distractors.md`. `Dataset/` and `Dataset/v2/` are not changed: the validator proves they are byte-identical
to the tag `v2.4.0`.

Same chat format, system message, core prompt, 13 core fields and labelling rules as the earlier datasets.

| File | Statements | What |
|---|---|---|
| `train.jsonl` | 720 = the 480 of `v2/train` (unchanged) + 240 new | Training |
| `valid.jsonl` | 72 = the 48 of `v2/valid` (unchanged) + 24 new | Validation loss: its wording and templates are held out of train |
| `test3.jsonl` | 30 new | A synthetic test of real-style distractors; its wording and templates are held out of train and valid |
| `*.labels.jsonl` | one line per statement | The sidecar: all 18 fields, `{"text", "value"}` or `null` |
| `index.csv` | 822 rows | Split, line, source, scenario, pool, unit, distractors, style, kinds |

The new statements are **synthetic** (fictional companies, generated numbers) and modelled on the **kinds** of sentences that real annual-report
prose holds and the earlier statements lack: a change in amount of a named part, a segment or product figure, cost lines and margins, deferred
revenue and remaining obligations, adjusted and constant-currency figures, dividends and repurchases, footnotes with rates and years in names,
longer paragraphs that chain these. **No real text is in the dataset**: the validator checks, where the private real passages exist on the
machine, that no run of 6 consecutive words of one is in a statement (the date phrase "for the year ended December 31" excepted).

The rule of the labels: a figure of a named part, a change, an adjusted or hypothetical figure, a cost, deferred or capital-return item is
`null`; a figure that the sentence calls the company's own is labelled as printed. Three kinds of new statement: `real_null` (only
distractors, nothing stated), `real_composite` (a statement of the earlier kind that states fields, with two to four distractor
sentences inserted) and `real_positive` (a sentence that states a company field among its figures, with distractors). Every core field is stated in at
least 25% of the training statements.
