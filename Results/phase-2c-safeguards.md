# Phase 2c: safeguards in the app (repair a garbled key, show a possible miss)

Spec: `Specs/phase-2c-app-safeguards.md` (approved 2026-10-19). Code: `KeyRepair`, `MetricsParser` (the `repairKeys` flag),
`UnusedAmounts`, `MetricsPresenter.checkRows`, the "Check" group of the Extract tab. Measured by
`FinancialEdgeAITests/SafeguardMeasurementTests.swift` with the real implementation on every saved report of the core call
(14 reports, 999 answers: 8 committed in `Results/`, 6 of the real-style sets, private, in `RealSet/reports/`). Nothing was run on the phone
for the measurement: the raw answers are saved. To reproduce the numbers:
`TEST_RUNNER_SAFEGUARD_OUT=<file> xcodebuild test -scheme FinancialEdgeAITests ... -only-testing:FinancialEdgeAITests/SafeguardMeasurementTests`.

## Read this first

- **The thresholds were set after a feasibility probe on the same answers** (disclosed in the spec). The measurement below is the
  Swift implementation on those answers, not a blind test: a fresh adapter or set would be.
- **Evaluation did not change.** `EvaluationMetrics`, `EvaluationRunner`, the prompt, the dataset, the schema and the resources are byte-identical
  to `v2.3.0` (checked with `git diff v2.3.0`). The repair is an opt-in flag of the answer parser, off in every evaluation, so every earlier
  number stays valid.

## The criteria

**A. Key repair**

| # | Criterion | Measured | Verdict |
|---|---|---|---|
| 1 | The 12 answers with exactly one garbled key become decodable and fully correct; the 2 answers that are not JSON stay undecodable | 14 undecodable answers: **12 repaired, all 12 fully correct** (judged by the evaluation code on the renamed answer); 2 not repaired | **met** |
| 2 | No answer that is already decodable changes | **0 of 985** decodable answers differ with the repair | **met** |
| 3 | At least 8 no-repair cases, and the repaired case reads the schema's key with the value kept | 9 no-repair cases (two keys wrong, a key missing, a key extra, a number as the value, a duplicate key, a nested value, a key of the other call, broken JSON, flag off) plus 5 garbled-key variants and the positions first, middle, last, the extended call, a fence and a thinking block: all pass | **met** |

**B. Possible-miss hint** (the answers of `lora-v1`, its two checkpoints and `lora-v2`, on the old test and on test 2: 6 reports)

| # | Criterion | Measured | Verdict |
|---|---|---|---|
| 4 | Shown on at least 85% of the answers that miss an amount | **85 of 88 (97%)** | **met** |
| 5 | Shown on at most 40% of the fully correct answers | **125 of 398 (31%)** | **met** |
| 6 | The limit, with numbers | 171 missed fields in those answers: **126 are amounts** (visible to the hint), **39 percentages and 6 per-share values** (invisible: 45, or 26%) | stated |
| 7 | On the real sets, how often the hint is shown (counts only, no criterion) | unmodified: 45 / 63 and 24 / 30 answers; `lora-v1`: 54 / 63 and 27 / 30; `lora-v2`: 51 / 63 and 24 / 30 (`real1`, `real2`) | reported |

Per report (answers with a missed amount that are warned; fully correct answers that are warned): `lora-v1` old test 9/9 and 30/78, test 2 33/36 and
15/48; checkpoint 50 9/9 and 20/68; checkpoint 100 28/28 and 12/42; `lora-v2` old test 0/0 and 31/85, test 2 6/6 and 17/77.

**C. The app**

| # | Criterion | Result | Verdict |
|---|---|---|---|
| 8 | The presenter shows the hint and the repair exactly when there is something to say | tests: nothing when nothing to say; the hint with one amount, with several, with a cut list (`and 2 more`); the repair before the hint; the extended call's repair; no hint when the core answer could not be read | **met** |
| 9 | All earlier tests pass; no warning in the touched files; frozen files identical | 310 tests pass (238 before, 72 new); the app builds with no warning; the frozen files are identical to `v2.3.0` | **met** |

**The gate:** criteria 4 and 5 are met, so the hint is shipped as built. A mixed result would have meant not shipping it.

## What it looks like

The Extract tab gets a "Check" group under the fields, only when there is something to say: a grey info row, "Possible miss", that lists the
amounts of the statement that no field used; an orange caution row, "A key was repaired", that says which key the model wrote and which it was
read as. The preview of the two rows was rendered (light and dark, and at a large text size): the icons keep their text aligned, and
VoiceOver reads each row as one phrase. A statement that triggers the hint with `lora-v2` (the model leaves out an operating income):
test 2 statement 21 ("Result from operations was $32.9B, compared with $34.6B in the earlier year. ..."); the hint lists `$32.9B` and
`$34.6B` (the second is the previous year's amount, a distractor: this is the noise).

## What this means, and the limits

- **The repair is complete for what has been seen and costs nothing**: 12 of 12 answers that were unusable are recovered, every one fully correct, and
  no other answer changes. It is shown, never silent, and an evaluation still counts the garbled answer as undecodable. It does not remove the
  cause: the adapters still garble that key on that kind of passage (constrained decoding would, if it becomes available).
- **The hint catches almost every missed amount and is noisy**: about a third of the good answers get it, because distractor amounts (total assets, free cash
  flow, the previous year's value) are "unused" too. It cannot see a missed percentage or per-share value (a quarter of the misses).
- **On real annual-report text the hint is shown on 71% to 90% of the answers, the unmodified model's included**: those passages are full of amounts
  that are not fields. There it carries almost no information. It is calibrated for short statements, and this is the honest limit of the design.
- **The repair could not be shown on the phone on demand**: the garble comes from specific real passages that are not in the repository. It is
  covered by unit tests and by the measurement on the saved answers. The Extract tab's wiring (the view model passes the flag) is checked by the
  build, the preview and a launch of the app on the phone, not by a tap: the Xcode tools cannot drive the physical phone.
- One set of answers (from one training run per adapter); the thresholds were set after a probe on the same answers.
