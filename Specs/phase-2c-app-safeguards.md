# Spec: Phase 2c, safeguards in the app (repair a garbled key, show a possible miss)

Status: **approved by the user on 2026-10-19** (written 2026-10-18). Nothing was built when it was approved. The decisions below are mine, each
with the alternative; the user approved them with the spec. Depends on `Specs/phase-2b-lora-wording.md` and its results
(`Results/lora-v2-analysis.md`, tag `v2.3.0`). It follows the sketch "Phase 2c" at the end of the Phase 2b spec.

**Goal:** make two failures of an adapted model **visible and recoverable in the app**, without touching the model, the prompt, the
dataset or the schema: (A) an answer that cannot be used because one JSON key is garbled; (B) a stated value that the model silently
leaves out.

**Out of scope:** training (a new adapter, other seeds, real-text distractors in the data: a later phase); any change to the prompt, the
schema, the dataset, or the way an evaluation **judges** an answer (the strict decoding of the model's raw output stays the
measure, so every number of every earlier report stays valid and comparable); asking the model again (a retry); the balance
sheet call's own failures; the overview and business sections.

## Why these two, and what the data says (probes run before writing the criteria)

Both come from `Results/phase-2b-references.md` and `lora-v2-analysis.md`. Before fixing the criteria I ran two probes on the saved
answers, with no change to the app. They are feasibility evidence: the thresholds below were set **with these numbers in view**, so
they are not a blind test; the real test is the Swift implementation measured on the same answers, and on the real sets as counts only.

| Probe (saved reports, core call) | Result |
|---|---|
| Undecodable answers in the 14 saved reports of the core call (999 answers; the 6 real-set reports are only on this machine) | **14**: 12 are valid JSON with exactly one wrong key, at the same position (`previousYearEps`: `previous6YearEps` for `lora-v1`, `previous5000` or `previous500` for `lora-v2`, in the real sets); 2 are not JSON (a checkpoint of `lora-v1`) |
| If the one wrong key is renamed by its position | **all 12 become fully correct** (the value is null and the 12 other fields are right) |
| A statement's amounts with a unit word ("$46.9 billion", "11.6 billion dollars") that **no extracted amount used** | present on **92% to 100%** of the answers that miss an amount (adapters on the old test and test 2) |
| The same check on **fully correct** answers | present on **22% to 38%** of them (distractor amounts: total assets, free cash flow, guidance; and the balance sheet amounts that belong to the second call) |

So the key repair looks safe and complete for what has been seen, and the possible-miss hint catches almost every silent miss of an
amount at the price of noise on about a third of the good answers. Not measured by the probe and **not detectable by this check**:
a missed percentage (growth) or a missed per-share value, because only amounts with a unit word are looked for.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D29 | **Key repair by position, in the app path only.** If an answer is valid JSON, has exactly 13 keys (the core call; 5 for the extended call), every value is a string or null, and **exactly one key differs from the schema's key at its position** (all the others are where they should be, in order), that key is read as the schema's key, and the screen says so. Anything else is not repaired: two keys wrong, a missing or extra key, a value that is not a string, a different order. The repair is a flag `repairKeys` of the answer parser, **off by default**: evaluations stay strict. | A similarity rule on the key names (`previous5000` is nowhere near `previousYearEps`: it would miss the case that happens). A retry (asking again): the garble came back in all three seeds, so a retry costs about 10 s and may not help. Constrained decoding (a grammar that forces the keys): the right fix, but not available in `mlx-swift-lm` today; noted for later. |
| D30 | **The possible-miss hint, a pure type.** `UnusedAmounts` takes the statement and what was extracted, finds every amount **with a unit word** in the statement (`$ 46.9 billion`, `USD 11.6 billion`, `11.6 billion dollars`, `$25.6bn`, `$924 million`, `$1,817M`) read by the same `ValueParser` rules, and lists those whose value (in billions, same tolerance as the evaluation) is **not equal to any amount field that was extracted**. When the balance sheet call has been made, its amounts count as used. Percentages, per-share values and bare numbers are not looked for. It never changes a value. | A keyword-guided check (only amounts near "revenue", "net income"...): it would ignore exactly the unfamiliar wording where the misses happen. An ignore list of distractors ("total assets", "free cash flow"): it would be fitted to my generator, and real text has other distractors. |
| D31 | **Shown as a hint, not a warning, on the Extract tab.** A "Check" group under the fields: for the hint, "Possible miss: $46.9 billion is in the text but in no field" (an info icon, secondary colour, the amounts listed, an accessibility label that says the same); for a repair, "A key was repaired: `previous6YearEps` was read as `previousYearEps`" (a caution icon). Nothing is shown when there is nothing to say. | A red warning: on about a third of the good answers it would be noise that teaches the user to ignore it. A hidden option: the hint is only useful if it is seen. |
| D32 | **Measured by tests on the saved answers, with the real implementation.** A Swift test decodes every saved core report in `Results/` (and, if the folder is present on the machine, `RealSet/reports/`, counts only, never printing a statement), joins each answer to its statement from the dataset files, and computes the numbers of the criteria below. The Python probe is not the measure; it only gave the feasibility. | Measuring on the phone: it needs no phone, the raw answers are saved and the check is pure. |
| D33 | **The evaluation code does not change.** `EvaluationMetrics`, `EvaluationRunner` and the reports keep their strict meaning; the new types are used by the view model and the presenter only. A test checks that those files are byte-identical to `v2.3.0`. | Letting the evaluation use the repair: it would change what "decodable" means and break the comparison with every earlier result. |

## Success criteria (fixed before building)

**A. Key repair** (the 14 saved reports of the core call: 999 answers, 14 of them undecodable; the 12 repairable answers are all in the
real-set reports, which exist only on this machine, so criterion 1 is measured where `RealSet/reports/` is present and said to be skipped elsewhere):
1. The **12 answers with exactly one garbled key become decodable, and all 12 are fully correct** after the repair (the probe says
   so; the test must find it with the Swift implementation). The 2 answers that are not JSON stay undecodable: no guessing.
2. **No answer that is already decodable changes:** parsed with and without `repairKeys`, every decodable answer gives the
   same strings (0 differences).
3. **No false repair:** at least 8 unit-test cases are not repaired (two keys wrong; a key missing and none extra; an extra key and none
   missing; 12 keys; 14 keys; a number as a value; the right keys in another order; a duplicate key), and the repaired case is read as
   the schema's key with the value kept.

**B. Possible-miss hint** (answers of the adapters, `lora-v1`, its two checkpoints and `lora-v2`, on the old test and on test 2, the
answers that have at least one missed **amount** field):
4. **Recall: the hint is shown on at least 85%** of those answers (the probe: 92% to 100% per report).
5. **Noise: the hint is shown on at most 40%** of the fully correct answers of the same reports (the probe: 22% to 38%).
6. **The limit is stated with numbers:** how many missed fields are percentages or per-share values, invisible to the check.
7. On the real sets (counts only, no criterion): how often the hint is shown. It is expected to be high, because real text is full of
   amounts; it is reported, not hidden.

**C. The app:**
8. The presenter shows the hint and the repair row exactly when there is something to say (tests), with the text above and an accessibility label.
9. All 238 earlier tests pass; the app builds with no warning in the touched files; the prompt, the dataset, the schema, `EvaluationMetrics`
   and `EvaluationRunner` are byte-identical to `v2.3.0` (checked).

**Gate:** if criterion 4 or 5 is not met, the hint is **not shipped as built**: the numbers are reported and a stricter variant is a new spec.
The key repair (1 to 3) does not depend on it and ships on its own. A mixed or negative result is a valid result.

## Design

- **`KeyRepair`** (pure, `Services/`): the position rule, returns the repaired object and what was renamed, or nothing.
  `MetricsParser.parse(_:schema:tier:repairKeys:)` uses it only when `repairKeys` is true, and then reports the rename in its outcome.
- **`UnusedAmounts`** (pure, `Services/`): the amount finder (a regular expression for amounts with a unit word) and the
  comparison with the extracted amount values. Reuses `ValueParser`, so a form the parser reads is a form the check reads.
- **`ChatViewModel`** passes `repairKeys: true` and the statement to the check; **`MetricsPresenter`** builds the "Check" rows.
  The evaluation path does not use either.
- **Tests:** `KeyRepairTests` (the cases above, with invented keys, never real text); `UnusedAmountsTests` (each amount form, a used
  amount, an unused amount, the balance sheet case, a statement with none); presenter tests; `SafeguardMeasurementTests` (the
  criteria 1, 2, 4, 5, 6 on the saved reports; the real-set part runs only where their folder is present and says when it is skipped; asserts the thresholds).
- **Files committed:** code and tests only; the real sets' numbers (counts) go into the results note, never a passage.

## UI / UX

The Extract tab's field rows do not change. Below them a "Check" group appears only when needed, with one row per message: an info
row for the hint, a caution row for a repair. A user who wants to ignore the hint loses nothing; a user who reads it sees the amount
that may have been missed. The Evaluate tab is not touched.

## Steps (each one commit, branch `feature/app-safeguards`)

1. **GATE: approve this spec.**
2. `KeyRepair`, `MetricsParser` flag and tests (`feat`, `test`).
3. `UnusedAmounts`, view model and presenter rows, tests (`feat`, `test`).
4. `SafeguardMeasurementTests` on the saved reports; the numbers for the criteria (`test`, `eval`).
5. A check on the iPhone: install the build and use the Extract tab on three statements from `test2` (the Xcode tools cannot tap the
   phone: I run the app and you look at the screen, or the presenter tests stand in and I say so) (`eval`).
6. Results note (`Results/phase-2c-safeguards.md`), README, PR to `main`, tag after the merge (proposed `v2.4.0`) (`docs`).

## Cost

No phone time for the measurement (the answers are saved), a short check on the phone at step 5. My work: two small pure types, their
tests, two presenter rows and the measurement test.

## Acceptance

1. The 12 garbled-key answers are decodable and fully correct with the repair; 0 other answer changes; the no-repair cases pass.
2. The hint's recall and noise are measured with the Swift implementation and each criterion is stated as met or not.
3. The limits of the hint (percentages and per-share values; noise on distractors and on real text) are written in the results note.
4. The evaluation code and every earlier result are unchanged (byte-identical files, all earlier tests green).

## Risks

- **The hint is noisy on real text** (annual reports are full of amounts); it will fire on most real passages. It is reported as it is.
  A noisy hint can teach users to ignore it; the wording and the neutral colour are the only mitigation here.
- **The repair could hide a format drift.** It is shown on screen, never silent, and the evaluation stays strict, so a drift still shows
  in every report.
- **The thresholds were set after the probe.** The Swift measurement is the real test, but it is on the answers the probe saw; a fresh
  adapter or set would be the blind test.
- **A wrong repair:** the position rule cannot tell that a model wrote a value for the wrong field under a garbled key; the value is
  the model's, flagged, and not trusted more than any other.
- **Constrained decoding** would remove garbled keys by construction; if it becomes available it replaces D29.
