# Spec: Phase 2e, the missed growth and previous-year values (DRAFT)

Status: **DRAFT, not approved** (written 2026-10-25 while the third seeds of Phase 2d train). Nothing in this spec has been built or run. It becomes binding only when the user
approves it; the decisions are mine, each with the alternative, and the user may change any of them. Depends on `Specs/phase-2d-real-distractors.md` (tag `v2.5.0`, and its
Amendment 4, the third seeds) and `Results/lora-v3-analysis.md`.

**Goal:** find out whether the values `lora-v3` leaves as null although the text states them (mostly a growth percent or a previous-year amount) can be recovered **without
bringing back the invented values** that Phase 2d removed, and find out first whether these misses are a pattern at all.

**Out of scope:** the prompt, the schema, the parser, the app, the way an evaluation judges an answer; real text in the training data (D34 of Phase 2d stays); the balance sheet
call; the overview and business sections; PDF input.

## What the data says (synthetic sets only, counts and invented-example text; no real text was used)

The missed values of `lora-v3` on the three synthetic sets, from the saved reports (`Results/`), by statement (3 runs each):

| Set | Seed 1 | Seed 2 |
|---|---|---|
| Old test | 5 missed: statement 17 (`netIncomeGrowth`) in 3 runs, statements 25 and 27 once each | 1 missed: statement 27 once |
| Test 2 | 9 missed: statements 6 and 15 (`previousYearNetIncome`) and 17 (`previousYearRevenue`), each in all 3 runs | not run |
| Test 3 | 17 missed: statement 2 (two growths), 10 (a growth), 12 (`netIncome`), 21 (two growths), each in 2 or 3 runs | 15 missed: `revenue` 6, `revenueGrowth` 5, `netIncome` 4 |

What this shows, and what it does not:
- The misses are **statement-specific and repeat across the three runs** (temperature 0.2): they are not sampling noise. Seed 1 and seed 2 miss **different** statements, so they are not one
  failure of the recipe either; the first reading, "the adapter learned that a percent next to a change is not the company's", fits part of test 3 (a sentence such as "net income ... fell by $149.1B, or 2.5%"
  next to a cost line that moved by an amount and percent, which is a distractor) and does **not** explain the old test (a short sentence, "net income of $2.1 billion, with year-over-year growth of 14%").
- It is **not new in `lora-v3`**: `lora-v2` seed 1 missed 24 values on test 3 (`netIncome` 9, `revenueGrowth` 6, ...) and 6 on test 2; `lora-v3` misses more only on the old test (5 and 1 against 0 and 0) and on test 2 (9 against 6, seed 1 only), and fewer on test 3
  (17 and 15 against 24 and 0). The Phase 2d analysis says "in places" for this reason.
- On real text the four stated fields of `real1` and `real2` were all found by every seed of `lora-v3`; `real3` has no stated field. **The cost on real text is therefore not measured**; the real sets cannot decide this
  experiment (D44).
- One test 3 label is debatable (statement 12: a net income named inside a cash-flow sentence); it is counted as the label says, and a diagnosis may show it is not a model failure.

## Decisions (mine, with the alternative)

| | Decision | Alternative and why not |
|---|---|---|
| D41 | **Diagnose before building.** Step 2 reads every missed and wrong-field answer of `lora-v2` and `lora-v3` (all seeds, the three synthetic sets) and sorts them by the wording of the sentence; the result is a table and a written reading, committed, and **the data change of D42 follows what it shows**. If there is no pattern (misses scattered over different wording per seed), the experiment stops there and says so: that is a valid result. | Writing new training data from the first hypothesis, which the old test already contradicts. |
| D42 | **If a pattern exists: `Dataset/v4` = `Dataset/v3` + new synthetic statements in which the company's own change or previous value is stated in the wording that D41 found missed, next to a distractor change of the same shape that stays null** (a contrast pair in one paragraph). Fictional companies, generated numbers, wording pools disjoint from train, valid and the three test sets, the same validator style (grounded labels, no leak, tamper tests), `Dataset/` to `Dataset/v3` byte-identical to `v2.5.0`. | More null-only statements (the opposite direction); changing the loss or the recipe (Phase 2b showed the weakness is data, not hyperparameters). |
| D43 | **Same recipe, same stop rule, three seeds for `lora-v4`** (1, 2, 3), compared with the three seeds of `lora-v3` by the D39 rule with three seeds (Phase 2d Amendment 4). A new held-out test, `test4` (30 statements, new wording pool), is added so the new wording is not graded on data it was written from. | One seed (Phase 2d showed one run is a draw). |
| D44 | **Real text needs fresh stated fields to say anything about growth and previous-year values.** The 17 reports are used up (Phase 2d Amendment 3: 53 paragraphs with an amount, 16 used). Options: the user supplies more reports for a fresh blind set `real4` (a new experiment, drawn after `Dataset/v4` is frozen, by the same committed rule); or the real sets serve only as a guard (no more invented values than `lora-v3`). | Reusing `real1` to `real3` as a test of extraction: they were read, or have no stated field. |

## Success criteria (to be fixed before training, once D41 has shown what is being fixed; the form is fixed now)

For `lora-v4`, three seeds, three runs each, thresholds computed from the `lora-v3` references **on `test4` before any `lora-v4` run** (as D40 did):
1. **Misses recovered:** missed values on `test4` and test 3, mean over the seeds, at most **half** of `lora-v3`'s, and the difference larger than both spreads (D39).
2. **No invented values back:** invented values on test 3, `real1`, `real2` and `real3` (counts) **not above** the largest of the three `lora-v3` seeds on each set, plus a margin of **3** answers on each real set.
3. **Old test and test 2 kept:** at least **82 / 90** fully correct on the old test and **72 / 90** on test 2 for every seed, at most **5** and **10** missed values.
4. **Decodable:** the number of undecodable answers per set is **reported per seed**; criterion 6 of Phase 2d (zero) is stated again and may fail again (the garbled key is a property of the model, left to the app's repair).
5. **Practical:** peak memory at most 3.0 GiB, thermal no worse than "serious", median time on the old test at most 12.5 s.
6. **If `real4` exists:** the stated growth and previous-year fields found on it by `lora-v4` against `lora-v3` and the unmodified model (counts only).

A mixed or negative result is valid and is reported as it is.

## Steps (branch `feature/lora-v4`, each one commit)

1. **GATE: approve this spec** (and answer the open choices below).
2. Diagnosis table and reading (D41), no phone, no training (`docs`). **GATE: I show the table and say whether there is a pattern; stop if there is none.**
3. `Scripts/generate_dataset_v4.py`, `Dataset/v4/`, validator, tamper tests, `test4` bundled in the app like `test3` (`data`, `feat`, `test`).
4. References on `test4`: the three seeds of `lora-v3` and the unmodified model (phone, about 1 hour each), then **freeze `Dataset/v4` by hash**; if `real4` is wanted, draw it after the freeze.
5. Train `lora-v4` seeds 1 to 3 (Mac, about 2 to 5 hours each); evaluate on test4, test 3, old test, test 2 (one seed), `real1` to `real3` (and `real4`) (`model`, `eval`).
6. Analysis against the criteria and the spread, README, PR, tag after the merge (proposed `v2.6.0`) (`docs`).

## Cost

About 3 hours of Mac work for the diagnosis and the data; training 6 to 15 hours on the Mac for three seeds; phone time about 4 hours of references plus about 10 to 12 hours of evaluations. Step 2 costs no phone time and
can end the experiment.

## Open choices for the user

- Approve the spec as it is, or change the decisions (D41 to D44).
- Whether to supply more annual reports for a fresh real set `real4` (D44); without it the real sets only guard against invented values.

## Risks

- **No pattern:** the misses may be scattered; the experiment then ends at step 2 with a table (a valid result).
- **Invented values return:** more positives about changes may bring back values for a part's change; criterion 2 and the contrast pairs are the guard.
- **Small tests:** 30 statements per test and three seeds; a difference smaller than the spread is reported as "not distinguishable".
- **Overfitting the wording:** the new statements are written from the misses; `test4` has its own wording pool and is never used in training.
