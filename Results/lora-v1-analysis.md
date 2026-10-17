# LoRA adapter lora-v1: Qwen3-4B (4-bit) specialised for the 13 core fields

The base model with a LoRA adapter trained on the 240 train statements, the same prompt, the same frozen test
split (30 statements), three runs, on the iPhone 16. Generated tables: `lora-v1-tables-iphone-20261016.md`.
Field by field against the schema 1 baseline: `comparison-schema1-vs-lora-v1.md`. Raw report (every raw answer,
every judgement): `lora-v1-Qwen3-4B-4bit-iphone-20261016T153448.json`. The run record (hyperparameters, losses,
hashes, the early stop): `Scripts/lora/runs/lora-v1.md`. Spec and criteria: `Specs/phase-2-lora.md`.

## Read this first

- **The same experiment as the schema 1 baseline, with one change: the adapter.** The prompt, the test set and
  the schema have the same hashes as the baseline report (`7779853b346c`, `1eb1fc231078`, `f70490659aa3`), the
  same seeds, temperature and `maxTokens`, the same phone and build. The comparison is answer by answer.
- **30 statements, not 90 answers.** All 30 statements gave the same extracted strings in the three runs. One
  statement is 3.3 points. The 15 wrong fields are 5 (statement, field) cases, each repeated three times.
- **The test split comes from the same generator as the train split.** The adapter may have learned the
  templates, not the task. The 12 statements with wording that is in no train or valid statement (pool B) are the
  only indication of generalisation, and they are where the adapter fails (below). Real reports are untested.
- **Training was stopped by hand at iteration about 170 of 300**, because the validation loss was flat at
  0.001 to 0.003 from iteration 50 and the training loss was 0.000 from iteration 160; the speed had also
  dropped (the Mac was under memory pressure). The adapter of iteration 150 (validation loss 0.001) is the one
  evaluated. The test split was never used to choose it. Details in the run record.

## Headline

| Measure | Baseline | lora-v1 |
|---|---|---|
| Valid JSON (the app's decoder can read it) | 90 / 90 | 90 / 90 |
| Exactly the 13 core keys, a string or null each | 90 / 90 | 90 / 90 |
| **All 13 fields correct** | 57 / 90 (63.3%) | **78 / 90 (86.7%)** |
| Fields correct | 1115 / 1170 (95.3%) | 1155 / 1170 (98.7%) |
| Wrong fields | 55 | 15 |
| Strings copied exactly like the label (where both have one) | 318 / 381 (83.5%) | 324 / 366 (88.5%) |

## The four criteria of the spec

| # | Criterion (fixed before training) | Result | Verdict |
|---|---|---|---|
| 1 | Fully correct answers at least 68 / 90 | **78 / 90** | **met** |
| 2 | Wrong fields at most 28 of 1170 | **15** | **met** |
| 3 | No loss on what is right: unit, sign, wrong number and missed value each 0, at most 5 fields in total; 90 / 90 decodable | 90 / 90 decodable, no unit, sign or wrong-number error, but **15 missed values** | **not met** |
| 4 | Practical: median time at most 12 s, peak memory at most 3.0 GiB, thermal no worse than "serious" | **11.6 s**, **2.86 GiB**, "serious" | **met**, with little margin on the time |

Three of four are met. The third is not, and it is the interesting one: the adapter did not make the model
wrong, it made it **silent**.

## What it fixed: all 55 wrong fields of the baseline

Of the same answers (same statement, same run), 55 fields that were wrong before are correct now, and none
that was wrong is still wrong. The baseline errors were all the model writing something where the label is
null; the adapter removed every kind:

| Baseline error | Fields before | Now |
|---|---|---|
| Growth the model calculated instead of leaving it null | 21 | 0 |
| A previous-year field filled from the wrong place | 19 | 0 |
| A value of another period or of a distractor | 12 | 0 |
| A correct number in a form the parser refuses (`$10.3 billion dollars`) | 3 | 0 |

The last row is worth a note: the adapter learned to write `10.3 billion dollars` as the label does, so the
parser's limit no longer shows. The parser was not changed (the cause is only hidden).

## What it broke: 15 missed values in 4 statements

The model writes `null` where the text states the value. Always the same 5 cases, in all three runs:

| Statement (pool) | Field | The text says | In train or valid? |
|---|---|---|---|
| 6 (B) | `netIncome` | "net earnings stood at 11.6 billion dollars" | the phrase "net earnings" appears in none of the 270 statements |
| 8 (B) | `operatingCashFlow` | "Cash generated from operations came to 46.9 billion dollars" | the phrase appears in none |
| 25 (B) | `netIncome` | "Net earnings stood at 7.3 billion dollars" | as statement 6 |
| 25 (B) | `previousYearRevenue` | "net sales a year earlier stood at 36.6 billion dollars" | the phrase appears in none |
| 17 (hand, A) | `netIncomeGrowth` | "net income of $2.1 billion, with year-over-year growth of 14%" | "year-over-year growth of" appears in none |

Every missed value is a **wording the adapter never saw**. The base model read all five correctly (it had no
missed value at all). So the adapter traded a model that over-reads (fills fields from other lines, calculates
growth) for one that under-reads: for a phrase outside what it was trained on, it answers null. The new error
is the mirror of the old one, and the training signal explains it: in the train data many fields are null, and
a null is the answer that is always safe in training.

Other fields with unusual wording were still read: the pool B statements are not all lost (27 of 36 answers
fully correct), but all of the failures are there except one hand-written sentence.

| Pool | Baseline, all 13 correct | lora-v1, all 13 correct | Fields correct before / now |
|---|---|---|---|
| A (wording seen in training) | 36 / 54 (66.7%) | 51 / 54 (94.4%) | 96.6% / 99.6% |
| B (wording not in train or valid) | 21 / 36 (58.3%) | 27 / 36 (75.0%) | 93.4% / 97.4% |

The adapter helps on unseen wording too (58.3% to 75.0%), but much less than on seen wording (66.7% to
94.4%). With 12 statements, this is an indication, not a measure.

## By scenario (where it still fails)

| Scenario | Answers | All 13 correct, baseline | lora-v1 |
|---|---|---|---|
| balance sheet | 9 | 100% | 66.7% (statement 6) |
| cash flow | 6 | 100% | 50.0% (statement 8) |
| mixed | 9 | 33.3% | 66.7% (statement 25) |
| hand-written | 15 | 80.0% (statement 30 failed) | 80.0% (statement 17 fails; statement 30 is fixed) |
| all other scenarios (amounts only, EPS only, full, growth only, income basic, interest, none, prior year without growth) | 51 | 52.9% (27 of 51) | 100% |

The scenarios that failed because of a null the model filled (prior year without growth: 0 of 9 before, 9 of
9 now; income basic 0 of 6 before, 6 of 6 now; amounts only 0 of 3 before, 3 of 3 now) are all fixed. Two
scenarios that were 100% in the baseline now fail: the balance sheet and the cash flow (one statement each,
both with unseen wording).

## What it costs on the iPhone

| | Baseline | lora-v1 |
|---|---|---|
| Time per statement (median) | 10.5 s | 11.6 s (+10%) |
| Time to first token (median) | 3.68 s | 3.80 s |
| Generated tokens (median) | 122 | 120 |
| Generation speed (median) | 20.6 tokens/s | 18.1 tokens/s (-12%) |
| Peak MLX memory | 2.72 GiB | 2.86 GiB (+0.14 GiB) |
| Generation time in total (90 answers) | 16.4 min | 18.5 min |
| Highest thermal state | 2 ("serious") | 2 ("serious") |
| Model load | 2.1 s | 2.5 s |

- **The adapter is not free, and it is not heavy.** It runs unfused on top of the 4-bit weights, which adds
  a little computation per token: -12% speed, +10% time per answer. The adapter file is 29.4 MB (2.28 GB for the
  model). Peak memory grows by 0.14 GiB.
- **The speed of the three runs differs more than the adapter does:** the medians are 12.9 s, 10.8 s and 10.8 s
  (14.6, 18.7 and 18.9 tokens/s). The first run is slower, as in the baseline, when the phone is cold and the
  app is still being set up; the thermal state is the likely cause of the rest (38 of 90 answers ended at
  "serious", 21 started at it). The time criterion (12 s) is met by the median of 90 answers, not by every run
  (run 1 is 12.9 s). Debug build.

## What this means for the project

- **Specialising a small model on 240 examples works for the thing it was trained on, and only there.** The
  errors the baseline made are gone (55 of 55). It is not a general gain in ability: the adapter learned
  "when in doubt, leave it null", which is right for the templates it saw and wrong for new wording.
- **The right next experiment is data, not hyperparameters:** more synonyms (net earnings, cash generated from
  operations, "a year earlier" wordings, year-over-year growth) in the train split, hand-written statements in
  the training data, and a test split with real reports. It is a new dataset and so a new experiment (no
  silent change of the dataset). Alternatively a lower learning rate or the checkpoint of iteration 50 or 100
  (the validation loss was already 0.002 and 0.003 there): the adapter may have overfitted the templates for
  100 more iterations; this was not tested because the validation loss cannot show it (the validation split
  has the same wording as the train split).
- **Is local deployment practical?** Yes for what was measured: the specialised model fits on an iPhone 16
  (2.86 GiB peak, an adapter of 29.4 MB, a model load of 2.5 s, 11.6 s per statement) and it makes the answers more reliable on known wording (86.7%
  against 63.3%). It is **not yet trustworthy on new wording**: a missed value is silent, the app shows an empty
  field and the user cannot tell it from a statement that does not give the value. For a financial tool, that
  has to be handled (the app could show "not found" differently, or check the text for the number).

## Limits

- 30 test statements, effectively one run each (the three runs are identical). Pool B has 12 statements.
- The test split is from the same generator as the train split; no real report was tested.
- Debug build, one iPhone model, one model, one prompt. The thermal state and the speed differ run by run.
- One training run (seed 1), stopped by hand at iteration about 170 of 300, one checkpoint (150) evaluated.
  Other checkpoints and other seeds were not measured.
- "Valid JSON" accepts what Foundation accepts (a trailing comma is read).
- The extended call (balance sheet) has no adapter: it is the base model, as in `baseline-analysis-extended.md`.
