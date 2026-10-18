# lora-v2: LoRA with more varied wording, against the criteria of Phase 2b

The adapter trained on `Dataset/v2` (480 statements with several names for every metric, other structures, every core field in at
least a quarter of the statements, a validation split with held-out wording), checkpoint of iteration 200 chosen by a stop
rule that is a program (`Scripts/lora/runs/lora-v2.md`). Evaluated like every earlier run (prompt `7779853b346c`, seeds 1, 2, 3,
temperature 0.2, `maxTokens` 384, iPhone 16, Debug build) on four sets. Spec and criteria: `Specs/phase-2b-lora-wording.md`.
Tables: `lora-v2-tables-iphone-20261018.md` (old test), `lora-v2-test2-tables-iphone-20261018.md` (test 2). Comparisons:
`comparison-lora-v1-vs-lora-v2.md`, `comparison-schema1-vs-lora-v2.md`, `comparison-test2-lora-v1-vs-lora-v2.md`,
`comparison-test2-base-vs-lora-v2.md`. The real sets are described by counts only (`phase-2b-references.md`, below).

## Read this first

- **Same experiment as before, one change: the adapter.** Prompt, test split and schema hashes equal those of the baseline and
  `lora-v1` on the old test; the adapter's weights hash in each report is that of the chosen checkpoint (`ffbdc621dc725d57`).
- **30 statements, not 90 answers.** Three runs at temperature 0.2 are nearly identical. One statement is 3.3 points.
- **One training run, one seed.** `lora-v1`'s checkpoints varied from 42 to 78 fully correct answers (`lora-v1-checkpoints.md`): a
  single adapter's result is a draw. The validation split of `lora-v2` was built to make the draw less blind, and it is, but this
  analysis cannot say how another seed would turn out.
- **Test 2 and the training data come from the same author and the same generator family** (other pools and structures, written by me). The
  real sets are real text, but tiny, mostly null, and labelled by me (the user confirmed 3 of the 5 labels I was unsure about; 2 stay uncertain, 3 fields per model, with no effect on the order of the models).

## The criteria of the spec

On the **old test** (30 statements x 3 runs, the frozen split of every earlier experiment):

| # | Criterion (fixed before training) | `lora-v2` | Verdict |
|---|---|---|---|
| 1 | Fully correct answers at least 84 / 90 (`lora-v1` 78, baseline 57) | **85 / 90** (94.4%) | **met** |
| 2 | Missed values at most 5 fields (`lora-v1` 15) | **0** | **met** |
| 3 | The old errors do not return: hallucinated + unreadable + unit + sign + wrong number at most 6; 90 / 90 decodable | **5** (2 hallucinated, 3 unreadable); 90 / 90 | **met** |
| 4 | Pool B (unseen wording, 36 answers) at least 30 fully correct; pool A (54) at least 49 | **34 / 36** (94.4%) and **51 / 54** | **met** |
| 5 | Practical: median time at most 12 s; peak memory at most 3.0 GiB; thermal no worse than "serious" | **12.006 s**; 2.86 GiB; "serious" | **memory and thermal met; time missed by 6 milliseconds** |

On **test 2** (30 new statements, wording and structures in no training statement):

| Criterion | `lora-v2` | Verdict |
|---|---|---|
| At least 9 more fully correct answers than `lora-v1` (48), so at least 57 / 90 | **77 / 90** (85.6%) | **met** |
| No fewer than the unmodified model (34) | 77 | **met** |
| Fewer wrong fields than `lora-v1` (59) | **22** | **met** |

**The time criterion, honestly.** The median over the 90 answers is 12.0058 s: over the limit of 12 s by 6 milliseconds. By the letter it is
missed. It is also well inside the noise of this measurement: the first run of every evaluation is slower (run 1: 14.0 s, runs 2 and 3:
10.7 s and 10.8 s, a cold phone and a cold app), and the median of all 90 answers sits between the two groups. `lora-v1` had 11.6 s with
the same pattern. The adapter's cost is what it was (the same adapter size and the same unfused computation): 16.9 tokens/s against
18.1 for `lora-v1` and 21 for the unmodified model, 4.33 s to the first token. I report the criterion as missed and do not re-measure
it to make it pass.

## What changed against `lora-v1`

|  | Baseline | `lora-v1` | **`lora-v2`** |
|---|---|---|---|
| **Old test:** fully correct | 57 / 90 | 78 / 90 | **85 / 90** |
| fields correct | 1115 / 1170 | 1155 / 1170 | **1165 / 1170** |
| invented values | 33 | 0 | 2 |
| unreadable | 22 | 0 | 3 |
| **missed values** | 0 | 15 | **0** |
| pool B (unseen wording) | 21 / 36 | 27 / 36 | **34 / 36** |
| **Test 2:** fully correct | 34 / 90 | 48 / 90 | **77 / 90** |
| fields correct | 1073 / 1170 | 1111 / 1170 | **1148 / 1170** |
| invented values | 75 | 3 | 14 |
| **missed values** | 9 | 56 | **6** |
| unreadable | 7 | 0 | 2 |

- **The diagnosis was right.** The misses of `lora-v1` came from the wording of the training data. With several names for every metric in
  the training statements, **all 15 missed values on the old test are fixed** (`netIncome` 6, `operatingCashFlow` 3, `netIncomeGrowth` 3,
  `previousYearRevenue` 3: the four statements that failed in all runs), and **the misses on test 2 fall from 56 to 6**. The invented
  values did not come back as they were: 2 on the old test (baseline 33) and 14 on test 2 (baseline 75).
- **What got worse, a little.** On the old test the 5 new wrong fields are all `previousYearNetIncome` in two statements: in
  statement 13 the model copies "19.7%" (a percentage) into the previous-year net income (unreadable), in statement 25 it writes the current
  net earnings as the previous-year value. On test 2 there are 14 invented values, in four statements: a free cash flow ("$2.8
  billion", a distractor) taken for the operating cash flow in all three runs (3 values); in one mixed statement the EPS written as net
  income and the previous-year revenue written as the current revenue, in all three runs (9 values); a revenue and a net income growth
  invented once each in two other statements (1 value each). Two more statements fail without an invented value: a percentage written as a
  previous-year EPS (unreadable, 2 answers) and an operating income missed in all three runs (3 missed values, plus 3 more missed values in the
  mixed statement above). These are the old kinds of mistake (the previous year taken for the current, a distractor taken for a field) at a
  much lower rate than the baseline's.
- **Structures.** On test 2, 0 of 12 answers fail for first-person statements and 0 of 12 for statements with headings, 1 of 12 with
  dashes, 9 of 24 for plain prose, 3 of 30 (answers) for the hand-written ones. What is left is chained prose with a distractor or a
  previous period.
- **The training loss and the validation loss.** Training fell to 0.000; the held-out validation loss was 0.027 at best and noisy
  (0.027 to 0.041 from iteration 100). It bottomed at iteration 200 and the program stopped at 350. The evaluation, not the loss,
  is what shows the adapter is better; here it is, on two sets.

## The real-style sets (from the user's annual reports): counts only

The passages are not in the repository. `real1` has 21 passages with 1 stated field (a test of not inventing values), `real2` 10
passages with 3 stated fields (9 over the three runs). Both are mostly null. **The user spot-checked the labels I was unsure about on 18 October:
3 of 5 confirmed, 2 uncertain (kept as written, 3 fields per model; at most 3 answers per model would change sides in each set, not the
order of the models: see `phase-2b-references.md`).**

| | `real1`: base | `real1`: `lora-v1` | `real1`: **`lora-v2`** | `real2`: base | `real2`: `lora-v1` | `real2`: **`lora-v2`** |
|---|---|---|---|---|---|---|
| Fully correct answers | 39 / 63 | 50 / 63 | **37 / 63** | 21 / 30 | 12 / 30 | **10 / 30** |
| Invented values | 42 | 16 | **33** | 21 | 24 | **29** |
| Missed or wrong stated values | 0 | 0 | **0** | 0 | 3 | **3** |
| Decodable answers | 63 / 63 | 60 / 63 | **60 / 63** | 30 / 30 | 27 / 30 | **27 / 30** |

- **On real text `lora-v2` is not better than the unmodified model, and it is worse than `lora-v1` on the distractor-heavy set.** It invents 33
  values on `real1` (base 42, `lora-v1` 16) and 29 on `real2` (base 21), and its fully correct answers are 37 / 63 and 10 / 30
  (base 39 and 21). Varied wording in synthetic statements fixed the synthetic misses and did not teach the adapter to leave out the
  amounts that a real annual report is full of (segment figures, changes, costs, deferred items). That is a different gap: the
  training data has no such distractors in that density.
- **The garbled key remains.** The same passage makes `lora-v2` write `previous5000` or `previous500` instead of `previousYearEps`, in all
  three runs, in both sets: valid JSON, wrong schema, unusable answer (3 undecodable in each set, as with `lora-v1`'s `previous6YearEps`). The
  unmodified model never does it. It is not one adapter's accident: two adapters with different data break on the same passage
  (a long paragraph of cross-references and footnote numbers), so it is a property of how an adapted model reads that text.
- **What this means.** The result on synthetic statements is real and now replicated on two sets; the result on real text is a warning that the
  synthetic task is easier than the real one. The real sets are small and mostly null, so it is a warning and not a measurement.

## Is local deployment practical?

- **For the task as defined and tested (short synthetic statements): yes, and clearly better than `lora-v1`.** 94% of the answers fully
  correct on the frozen test (63% unmodified), 86% on a harder set of new wording (38% unmodified), no missed value on the old test, 2.86 GiB
  peak memory, an adapter of 29.4 MB that loads in 2.7 s, 10.7 to 14 s per statement on an iPhone 16 in a Debug build.
- **For real annual-report text: not yet.** The adapter does not help there, and it can break the output format on text it has not seen. A
  product would need training data with real distractors, a schema check with a retry for an undecodable answer (the key typo is visible and
  cheap to catch), and a test on more real text than 31 passages.

## Limits

One adapter (one run, one seed) per experiment; 30 statements per synthetic test, effectively one run each; 21 and 10 real passages with 3 and 9
stated fields, labelled by me (3 of the 5 doubtful labels confirmed by the user, 2 uncertain); Debug build, one phone; the synthetic data and test 2 have one author. The stop rule picked
iteration 200 by a loss that is flat and noisy there: another seed or another checkpoint (100: 0.029, 250: 0.030) could give a different
adapter.

## Next experiments

1. Real-text distractors in the training data (segment figures, changes in amount, deferred and adjusted items, cost lines), with a
   test on more real passages than the 31 here, with the labels confirmed against the whole report.
2. A schema check with one retry in the app for an answer whose keys are wrong (the undecodable answers).
3. Other seeds of the same training, to see how much of 85 / 90 and 77 / 90 is the data and how much the draw.
4. The balance sheet call has no adapter; its `cash` field has the same kind of weakness the core call had.
