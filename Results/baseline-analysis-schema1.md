# Baseline: Qwen3-4B (4-bit), schema version 1, no fine-tuning

The unmodified model, the schema-based prompt of `Dataset/`, the frozen test split (30 statements), three
runs, on the iPhone 16. Generated tables: `baseline-tables-schema1-iphone-20261016.md`. Raw report (every raw
answer, every judgement): `baseline-schema1-Qwen3-4B-4bit-iphone-20261016T114216.json`. Side by side with
v1.1.0: `comparison-v1.1.0-vs-schema1.md`. Reproduce the tables with
`python3 Scripts/summarize_results.py <report.json>`.

## Read this first

- **This is a different experiment from v1.1.0, not a before and after.** The prompt (about twice as long:
  567 tokens against 296), the output format (13 strings copied as printed, read by code, against 7 numbers),
  the fields (13 against 7) and the 30 test statements all changed. v1.1.0 stays what it was: the baseline of
  that schema. This one is the reference for what comes next (the extended call, LoRA).
- **Same settings otherwise:** the same model, temperature 0.2, seeds 1, 2, 3, thinking off, a fresh chat
  session per statement, the same device (iPhone 16, iOS 27.0.1, Debug build). Only `maxTokens` changed, from
  256 to 384. No answer came near it: the longest answer is 159 tokens.
- **30 statements, not 90 answers.** 28 of the 30 statements gave the same extracted strings in all three
  runs. Statement 4 differs only in how a value is written (and is fully correct every time). Statement 2
  differs in what it writes for fields that should be null: all three runs are wrong, and one run also fills
  the previous-year net income. Every run has exactly 19 of 30 statements fully correct, the same 19. One
  statement is 3.3 points.
- **How it was run:** nobody touched the phone. The app was installed and launched from the command line with
  `-autoRunEvaluation YES`, and the report was copied from the app's container with `xcrun devicectl`.
- Debug build, one phone model, one model, one prompt, synthetic short statements, English and USD.

## Headline

| Measure | Count | Share |
|---|---|---|
| Valid JSON (the app's decoder can read it) | 90 / 90 | 100% |
| Exactly the 13 core keys, a string or null each | 90 / 90 | 100% |
| Needed a Markdown code fence or a reasoning block | 0 / 90 | 0% |
| **All 13 fields correct** | **57 / 90** | **63.3%** |
| Fields correct | 1115 / 1170 | 95.3% |
| Wrong fields | 55 / 1170 | 4.7% |
| Strings copied exactly like the label (where both have one) | 318 / 381 | 83.5% |

57 of 90 is also the count of v1.1.0, but it now needs 13 fields right instead of 7, and the cause of the
failures has changed completely (below).

## What the new design did

- **No unit error, no sign error, no wrong value, no missed value.** Out of 1170 fields, the model never wrote
  a wrong number. In v1.1.0, 33 fields had a wrong unit and 15 a wrong previous-year number. Copying the
  string and letting code read the unit removed the unit errors by construction: `2,772 million` is read as
  2.772 billion whatever the model "thinks". It also never returned null for a value that the text prints.
- **Growth is still copied right when it is printed,** including the sign (a decrease is written with a
  leading minus).
- **The strings do not have to be copied exactly.** 63 of the 381 comparable strings differ from the label,
  and 60 of them are read to the right value anyway: `USD 3.71` written as `$3.71`, `37.5 percent` as `37.5%`,
  `3,290 million dollars` as `$3,290m`. That is the case for the parser being tolerant about the form and
  strict about the value.
- **The parser did its job as a guard.** 22 strings were not numbers (see below). Without the parser they
  would have become silent wrong numbers; they are flagged instead.

## What goes wrong: 55 wrong fields in 11 of 30 statements

The 55 wrong fields are all of one kind: **the model writes a value where the label is null**
(33 `hallucinated`) or writes something the parser cannot read as a value (22 `unreadable`; their label is
null too, except 3). The 11 statements that are never fully correct (1, 2, 3, 10, 12, 13, 14, 22, 24, 25, 30)
fail in all three runs; the 19 others are right in all three. Counts are wrong fields over 90 answers.

| Cause | Wrong fields | Statements |
|---|---|---|
| **A growth filled in although the text prints none** (the model calculates) | 21 | 3 (1, 3, 12) |
| **A previous-year field filled in although the text prints none** (the current value or another line copied) | 19 | 6 (2, 13, 14, 22, 24, 30) |
| **A current-period field filled with a value of another period or of a distractor** | 12 | 2 (10, 25) |
| **A correct number written in a form the parser refuses** (`$10.3 billion dollars`) | 3 | 1 (3) |

### 1. Calculating instead of null (21 fields, rule 3)

The prompt says "do not calculate". The model still fills a growth when the text gives the two amounts but
no percentage.

- **Percentages that are not in the text (6 fields).** Statement 1: "revenue $249 billion versus $250.5 billion,
  net income $37.9 billion versus $45.5 billion, EPS 10.25 versus 9.72". It returned `-7.7%` and `2.3%` for the
  net income and EPS growth. The real changes are -16.7% and +5.5%, so the numbers are not even right.
- **The difference of the two amounts (15 fields).** Statements 3 and 12: `-$1.3 billion` for a net income
  growth, `-USD 1.55` and `-USD 0.28` for EPS growth, `4.0 billion dollars` for a revenue growth. A difference
  of two amounts is not a percentage. The parser refused all 15 as a percent, which is the right outcome, and
  they are counted as `unreadable`.

Same finding as v1.1.0 (9 fields there): the model calculates, and what it calculates is wrong or of the wrong
kind. The design says code should do the arithmetic, and it can, but only if the model leaves the growth null.
Note that the rule "the printed value wins" would keep a growth the model invented (`-7.7%` above) as if it were
printed.

### 2. Previous-year fields filled from the wrong place (19 fields)

The text does not state the previous-year value, and the model fills the field anyway:

- the **current** value copied as the previous year (statement 13, net income `$37.9 billion`; statement 22,
  revenue `USD 193 billion`; statement 2, `$15bn (down 33 percent)` with the growth added in parentheses),
- a previous-year amount of **another line** (statement 14: the previous-year operating profit
  `$2,922 million` as the previous-year revenue; statement 24: the previous-year operating income
  `$23.7 billion` as the previous-year net income; statement 30: the previous-year EPS `$2.10` as the
  previous-year revenue, read as 2.1e-9 billion, that is $2.10).

This is the "previous-year amount taken from another line" cause of v1.1.0 (15 fields), now on 13 fields and
including the previous-year revenue that v1.1.0 could not even ask for.

### 3. A current-period field from another period or a distractor (12 fields)

- Statement 10: `operatingCashFlow` = `$18.7 billion`, the **free cash flow** of a distractor sentence.
- Statement 25: the statement only gives values "a year earlier" and a cash balance; the model wrote the
  previous-year net sales as `revenue`, the previous-year EPS as `eps`, and the **cash and cash equivalents**
  (`13.1 billion dollars`, an extended field) as `operatingCashFlow`.

### 4. A correct number the parser refuses (3 fields)

Statement 3: the label is `10.3 billion dollars`; the model wrote `$10.3 billion dollars`, the `$` in front
and the word "dollars" behind. The value is right and the parser refuses it because it has two currency
markers. It is a measurement of the parser's strictness, not of the model: see "What this means".

## By scenario

| Scenario | Answers | All 13 correct |
|---|---|---|
| balance sheet, cash flow, EPS only, growth only, none of the fields | 9 + 6 + 9 + 3 + 3 | 100% |
| hand-written | 15 | 80% |
| all income fields (`full`) | 12 | 75% |
| interest | 6 | 50% |
| random subset of the 18 fields (`mixed`) | 9 | 33% |
| basic income, amounts only, prior year without growth | 6 + 3 + 9 | 0% |

The scenarios that fail are the ones where the text gives **two numbers for the same metric** (this year and
last year) or **amounts without the percentage**, which is where the model fills a field that should be null.
Unseen wording (pool B) is 58.3% fully correct (12 statements), seen wording (pool A) 66.7% (18 statements):
not distinguishable at this sample size. Statements in billions 55.6%, in millions 71.4%, hand-written 80%.

## What it costs on the iPhone

Measured on the same phone as v1.1.0 (details in `comparison-v1.1.0-vs-schema1.md`).

| | v1.1.0 | Schema version 1 |
|---|---|---|
| Time per statement (median) | 6.0 s | 10.5 s |
| Time to first token (median) | 2.37 s | 3.68 s |
| Prompt tokens (median) | 296 | 567 |
| Generated tokens (median) | 75 | 122 (min 105, max 159) |
| Generation speed (median) | 21.5 tokens/s | 20.6 tokens/s |
| Peak MLX memory | 2.57 GiB | 2.72 GiB |
| Model load from the cache | 2.8 s | 2.1 s |
| Generation time in total | 9.5 min | 16.4 min |

- The answer costs about 75% more time. About 1.3 s of the 4.5 s difference is the longer prompt (first
  token), and most of the rest is the 47 more tokens to write (about 2.3 s at 20.6 tokens/s). The estimate
  made before the run was 10.8 s per statement and 180 tokens; the measured 10.5 s and 122 tokens are close
  for the time and better for the tokens.
- Per run, the median time was 11.3 s, 10.5 s and 10.2 s (20.5, 20.6 and 21.0 tokens/s).
- **The phone got hot.** The thermal state reached "serious" (2) and never "critical". 22 of the 90 answers
  ended at "serious" (3, 11 and 8 in runs 1, 2 and 3), and 12 started at it (7 in run 2, 5 in run 3: the
  runner waits at most two minutes for the phone to cool, then goes on). In v1.1.0 every answer started
  below "serious". The speed per run does not show a visible slowdown.
- **The whole run took 57 minutes (12:44 to 13:42), the generation only 16.4.** The difference is the time
  the runner spent waiting for the phone to cool (inferred: the app does not record the waits). A run of this
  size on this phone should be planned for about an hour, not for the 20 to 35 minutes I expected.

## What this means for the project

- **The units are solved by design, and the format still is.** What is left is semantic: the model fills
  fields that should be null. It is a problem of **precision** (it says more than the text says), not of
  recall (it never missed a printed value) and not of accuracy (a value it copies right is exactly right).
- **These are the failures a specialised model should fix,** and they are concrete: do not calculate a growth,
  do not fill a previous-year field that the text does not state, do not take a value of the wrong period or
  from a distractor. The next evaluation uses the same 30 statements and the same metrics and can say, per
  cause, whether the numbers move.
- **Three things are worth looking at before the next experiment, and none was changed here** (a changed
  prompt or parser is a new experiment): the parser could accept `$10.3 billion dollars` (3 fields); a growth
  the model returns could be checked against the two amounts when both are there (it would catch the invented
  `-7.7%`); and the prompt could say in words that a previous-year field stays null when the text gives only
  the current value.
- **The hypothesis is still untested.** Nothing here shows that fine-tuning helps. It shows where there is
  something to improve: 63.3% of answers fully correct, 55 wrong fields of one kind.

## Limits

- 30 test statements, effectively one run each. Each cause comes from 1 to 6 statements. The cash flow and
  interest fields appear in only 3 to 5 test statements, the extended fields are not asked in this call.
- Synthetic, short statements, English and USD. No losses, no several periods, no unit given only in a table
  header.
- Debug build, one iPhone model (iPhone 16). A Release build may be faster.
- "Valid JSON" accepts what Foundation accepts (a trailing comma is read).
- The run was started from the command line, and the console connection to the phone was lost after 10
  answers; the evaluation went on in the app and the report was copied afterwards. The report is complete
  (90 records, no generation failure).
- The v1.1.0 numbers and these cannot be compared like for like (see the first section).
