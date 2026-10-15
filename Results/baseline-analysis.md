# Baseline: Qwen3-4B (4-bit), no fine-tuning

The unmodified model, the prompt of `Dataset/`, the frozen test split (30 statements), three runs.
Generated tables: `baseline-tables-mac-20261015.md`. Raw report: `baseline-Qwen3-4B-4bit-mac-20261015T002540.json`
(every raw answer, every judgement). Reproduce the tables with `python3 Scripts/summarize_results.py <report.json>`.

## Read this first: what this run is, and is not

- **It ran on a Mac, not on the iPhone.** The iPhone dropped its connection during the night, so the
  evaluation was run on a Mac16,13 (24 GB) as an iOS app ("Designed for iPad") with the same app, model,
  prompt, seeds and test split. The `device` field of the JSON says `iPad8,6`, because an iOS app on a Mac
  reports an emulated identifier. The app now labels such runs; the committed file predates that fix.
- **The accuracy numbers do not depend on the device.** Same weights, same prompts, same seeds.
- **The speed and memory numbers of this run are not iPhone numbers** (here: 8.0 s per statement median,
  10.3 tokens/s, 2.7 GB peak, Debug build, an iOS app emulated on a Mac). The iPhone numbers are in
  `model-gate.md` (about 21.8 tokens/s, 5.4 s per statement, 2.6 GB peak, 7 statements). A run on the
  iPhone itself is still to be done and will be added next to this one.
- **Debug build, one model, one prompt, 30 statements.** One statement is 3.3 points.
- **The three runs are identical.** At temperature 0.2 the model gave exactly the same values for all 30
  statements in all three runs (30 of 30). The effective sample is therefore 30 statements, not 90 answers,
  and the 90 answers are not independent evidence.

## Headline

| Measure | Count | Share |
|---|---|---|
| Valid JSON (the app's decoder can read it) | 90 / 90 | 100% |
| Exactly the 7 keys, a number or null each | 90 / 90 | 100% |
| Needed a Markdown code fence or a reasoning block | 0 / 90 | 0% |
| **All 7 fields correct** | **57 / 90** | **63.3%** |
| Fields correct | 570 / 630 | 90.5% |
| All 7 correct, if a x1000 unit error is accepted | 66 / 90 | 73.3% |
| Fields correct, if a x1000 unit error is accepted | 603 / 630 | 95.7% |

"Valid JSON" means the app's own decoder can read it. Foundation's parsers also accept a trailing comma,
so this is slightly looser than strict JSON (documented in `MetricsParserTests`).

## What the model does well

- **The format is not a problem.** With thinking switched off and temperature 0.2, all 90 answers were
  readable, none used a fence. (The fence seen in the very first test on the iPhone came from another model,
  `gemma3_1B_qat_4bit`, and another prompt. The two experiments are not comparable.)
- **Growth values are exact:** `revenueGrowth` and `operatingIncomeGrowth` are 100% correct (90 / 90 each),
  including the sign.
- **It stays quiet when it should.** The 2 statements with no requested metric (6 answers) all returned
  seven nulls. Statements with only amounts, only growths, only revenue, or no operating income: 100%.
- **No visible phrasing effect.** Wording seen in training (pool A) 64.7% (11 of 17 statements), unseen
  wording (pool B) 61.5% (8 of 13): not distinguishable at this sample size.

## What goes wrong: 60 wrong fields in 11 of 30 statements

The 11 statements that are never fully correct have four causes. The counts are wrong fields over 90 answers.
Statements 15 and 28 appear in two causes each, so the statement counts add up to more than 11.

| Cause | Wrong fields | Statements |
|---|---|---|
| **Wrong unit** (a x1000 error) | 33 | 4 |
| **Invented previous-year net income**, usually the previous-year revenue or operating income | 15 | 5 |
| **Calculated or invented net income growth** instead of null | 9 | 3 |
| **Invented revenue** (it took the net income) | 3 | 1 |

### 1. Wrong unit (33 fields, 4 statements)

The labels are in billions of USD, so "$410 million" is 0.41.

- **Statements written in millions:** 2 of the 4 (statements 9 and 16) were answered with the figure left in
  millions (`2,772 million` returned as 2772, expected 2.772). The other 2 (4 and 30) were converted correctly,
  so the model can do it. Strict score on
  statements written in millions: 3 / 12 answers; if the unit is accepted: 9 / 12.
- **Statements written in billions:** 2 statements were answered in millions (`$6.9bn` returned as 6900,
  `$2.1 billion` returned as 2100). The model converted in the wrong direction.

**This result is partly a fault of the experiment.** Rule 8 of the prompt says "Preserve the units by
assuming all monetary values are in billions of USD". It does not ask the model to convert millions to
billions, but the dataset labels do. So a model that copies "2,772" is following a reasonable reading of the
prompt, and is scored wrong. The two cases where billions became millions are real errors. Before any
fine-tuning, the prompt rule must say what is wanted, and the baseline must be run again with it: a changed
prompt is a different experiment and must not be compared silently with this one.

### 2. Previous-year net income taken from the wrong line (15 fields)

Statement 5: "Net sales ... 143.7 billion ... Operating profit slipped by 8% to $46.4bn, versus 50.4 billion
dollars in the prior year. Net profit expanded by 35.1%, reaching 26.6 billion." Expected
`previousYearNetIncome = null`. Returned: 50.4, the previous-year **operating profit**. The same happens with
the previous-year revenue (statements 3, 21). This is exactly what the dataset's "prior-year amounts for
revenue and operating income" were meant to probe. The model takes a previous-year number of the wrong
metric in 4 of 30 statements (3, 5, 15, 21: 12 fields). The other 3 wrong fields are statement 28, below.

### 3. Calculating instead of returning null (9 fields, rule 7)

Rule 7: "Do not calculate values that are not explicitly provided in the text."

- Statement 17: net income 10 billion against 9.7 billion, no percentage. Returned `netIncomeGrowth = 0.3`
  (the difference, not even a percentage; the real change is +3.1%).
- Statement 12: 30.7 against 35.6. Returned -4.9 (again the difference; the real change is -13.8%).
- Statement 4: 1,081 against 1,006 million. Returned -1.
- Statement 28: "net income of $2.1 billion, with year-over-year growth of 14%". Returned
  `previousYearNetIncome = 1836.36`, a number that is not in the text, and the net income as 2100.

The model does not obey rule 7: it computes, and the numbers it computes are wrong. Same finding as in the
gate test on the iPhone ("5.6 down from 6.1" gave -0.5).

### 4. Distractors read as metrics

Statement 15: "Total revenue grew 28.3% ... Net income was $3.6 billion." Returned `revenue = 3.6`, the net
income. One statement, three runs.

## Which statements fail, by scenario

| Scenario | Answers | All 7 correct |
|---|---|---|
| amounts only, growth only, revenue only, no operating income, none of the metrics | 9 + 9 + 6 + 9 + 6 | 100% |
| net income only | 6 | 50% |
| all fields | 15 | 60% |
| hand-written | 9 | 66.7% |
| prior-year amounts without the net income growth | 9 | 0% |
| growth stated, previous year not stated | 9 | 0% |
| random subset | 3 | 0% |

The scenarios that fail are the ones that put several numbers for the same metric in the text, which is
where the model has to choose.

## What this means for the project

- **Reading the format is solved for this model and prompt. Choosing the right number is not.** The failures
  are semantic: units, which of two numbers belongs to which metric, and not calculating.
- **These failures are the ones a specialised model should fix**, and they are concrete enough to measure:
  the next evaluation uses the same 30 statements and the same metrics, and can say, per cause, whether
  the numbers move. They are also the ones a better prompt might fix, which is why the prompt rule 8 must be
  settled first.
- **The hypothesis stays untested.** Nothing here shows that fine-tuning helps. It shows where there is
  something to improve: 63.3% of records fully correct, and a list of what is wrong.

## Limits

- 30 test statements, effectively one run each. Counts per cause are 3 or 4 statements.
- Synthetic, short statements.
- A Mac run in a Debug build: speed and memory here do not describe the iPhone.
- The labelling convention (convert to billions) is stricter than the prompt (see 1).
- "Valid JSON" accepts what Foundation accepts.
