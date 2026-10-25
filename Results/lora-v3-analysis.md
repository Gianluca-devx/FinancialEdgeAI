# Phase 2d: `lora-v3` against its criteria and against the noise of a training run

Spec: `Specs/phase-2d-real-distractors.md` (criteria written and committed before any training, thresholds for criteria 3 and 5 fixed from the references in
`phase-2d-references.md` before any `lora-v3` adapter was run). Training: `Scripts/lora/runs/lora-v3.md`. Every number below is a count printed by
`Scripts/phase2d_table.py` from the saved reports (`Results/` for the synthetic sets, `RealSet/reports/` for the real ones, which are private: **counts only, no passage, no per-statement
table of a real set**). All runs: the same iPhone 16, the same Debug build, prompt `7779853b346c`, seeds 1, 2, 3, temperature 0.2, `maxTokens` 384, thinking off. Every report carries the adapter
name, its configuration hash and its weights hash, and each one was checked against the hashes of the files that were trained: `lora-v3` (seed 1, iteration 600, `26a0d90702e19f00`),
`lora-v3-s2` (seed 2, iteration 150, `e00e658338352a5c`), `lora-v2-s2` (seed 2, iteration 150, `ef41cf860ced63ad`); `lora-v2` is the adapter of Phase 2b (iteration 200, `ffbdc621dc725d57`).

## The comparison (answers over 3 runs: 90 for the 30-statement sets, 63 for `real1`, 30 for `real2`, 36 for `real3`)

Fully correct answers, invented values, missed values, undecodable answers. "Invented" is a value written where the label is null; "missed" is null where the text states one.

| Set | Unmodified | `lora-v2` seed 1 | `lora-v2` seed 2 | `lora-v3` seed 1 | `lora-v3` seed 2 |
|---|---|---|---|---|---|
| Old test (90) full | 57 | 85 | 80 | **85** | **85** |
| invented / missed / undecodable | 33 / 0 / 0 | 2 / 0 / 0 | 6 / 0 / 0 | 1 / **5** / 0 | 4 / 1 / 0 |
| Test 2 (90) full | 34 | 77 | not run | **81** | not run |
| invented / missed / undecodable | 75 / 9 / 0 | 14 / 6 / 0 | | 3 / 9 / 0 | |
| Test 3 (90) full | 14 | 27 | 16 | **66** | **57** |
| invented / missed / undecodable | 145 / 24 / 0 | 99 / 24 / 0 | 122 / 0 / 0 | 13 / 17 / 0 | 24 / 15 / 0 |
| `real1` (63) full | 39 | 37 | 30 | **57** | **57** |
| invented / undecodable | 42 / 0 | 33 / 3 | 39 / 3 | 3 / 0 | 9 / 0 |
| `real2` (30) full | 21 | 10 | 11 | **24** | **27** |
| invented / undecodable | 21 / 0 | 29 / 3 | 30 / 4 | 8 / 0 | 6 / 0 |
| `real3` (36, blind) all-null | 24 | 19 | 12 | **33** | **36** |
| invented / undecodable | 12 / 0 | 13 / 3 | 21 / 6 | **0** / 3 | **0** / 0 |

Practical (old test): median time per statement 11.1 s (seed 1) and 10.9 s (seed 2) for `lora-v3`; peak memory 2.86 GiB; highest thermal state "serious" in every run. On `test3`, whose statements are longer
(about 660 prompt tokens), the medians are 12.2 s and 13.3 s.

## Every criterion, for `lora-v3` seed 1 (the spec's thresholds)

| # | Criterion | Result | |
|---|---|---|---|
| 1 | Old test: at least 82 / 90, at most 5 missed, 90 / 90 decodable | 85, **5**, 90 | **met**, the missed values exactly at the limit |
| 2 | Test 2: at least 72 / 90, at most 10 missed, 90 / 90 decodable | 81, 9, 90 | **met** |
| 3 | Test 3: at least 36 / 90 (`lora-v2` 27 + 9), at most 49 invented (half of 99) | 66, 13 | **met**, with a large margin |
| 4 | `real1` + `real2` together (93 answers, not blind): at least 62 fully correct, at most 40 invented | 81, 11 | **met** |
| 5 | `real3` (blind): at least the unmodified model's 24 all-null answers, at most 9 invented (70% of 13) | 33, **0** | **met** |
| 6 | No garbled key, no broken answer: 0 undecodable on every set | `real3`: **3 undecodable** (one passage, all three runs: valid JSON with a wrong key, `previous4YearEps`); 0 on the five other sets | **NOT met** |
| 7 | Practical: peak memory at most 3.0 GiB, thermal no worse than "serious", median time at most 12.5 s | 2.86 GiB, serious, 11.1 s on the old test | **met** (see the note on the time) |
| 8 | The seeds: both seed-2 adapters on the old test, `test3`, `real1`, `real2`, `real3`; each conclusion against the spread | done (below) | **done** |

**Seven of eight met; criterion 6 is not.** The garbled key is the old failure of `lora-v1` and `lora-v2` (`previous6YearEps`, `previous500`, `previous5`): the model writes a key with a number
inside where `previousYearEps` should be, on one passage of `real3`. Seed 2 of `lora-v3` does not do it (0 undecodable on all five sets), and `lora-v2` seed 2 does it more (6 on `real3`, 4 on `real2`). So
the failure is not removed by the recipe; whether it happens depends on the seed. The app repairs this particular garble by position (Phase 2c, v2.4.0); the criterion measures the model's own output and is
reported as it is.

Notes on the thresholds: criterion 1 is met by zero margin (5 missed against the limit of 5, all on growth and previous-year fields: `netIncomeGrowth` 3, `revenueGrowth` 1, `previousYearRevenue` 1), and
seed 2 has 1. Criterion 7 does not name a set for the time: Phase 2b measured it on the old test, which is how it is read here; on `test3`, seed 2's median (13.3 s) is above 12.5 s because those statements are longer.

## Against the noise (D39)

The rule: a difference between two recipes counts only if it is larger than the spread between the two seeds of the same recipe. With two seeds the spread is one range of two points, a weak estimate; the rule is applied
mechanically and conservatively: the difference of the two means must exceed the larger of the two spreads (max minus min).

| Measure | `lora-v3` mean (spread) | `lora-v2` mean (spread) | Difference | Reading |
|---|---|---|---|---|
| Old test, fully correct | 85 (0) | 82.5 (5) | 2.5 | not distinguishable |
| Old test, invented | 2.5 (3) | 4 (4) | 1.5 | not distinguishable |
| Old test, missed | 3 (4) | 0 (0) | 3 | not distinguishable (but see below) |
| Test 3, fully correct | 61.5 (9) | 21.5 (11) | 40 | **beyond the noise** |
| Test 3, invented | 18.5 (11) | 110.5 (23) | 92 | **beyond the noise** |
| Test 3, missed | 16 (2) | 12 (24) | 4 | not distinguishable |
| `real1`, fully correct | 57 (0) | 33.5 (7) | 23.5 | **beyond the noise** |
| `real1`, invented | 6 (6) | 36 (6) | 30 | **beyond the noise** |
| `real2`, fully correct | 25.5 (3) | 10.5 (1) | 15 | **beyond the noise** |
| `real2`, invented | 7 (2) | 29.5 (1) | 22.5 | **beyond the noise** |
| `real3`, all-null | 34.5 (3) | 15.5 (7) | 19 | **beyond the noise** |
| `real3`, invented | 0 (0) | 17 (8) | 17 | **beyond the noise** |
| `real3`, undecodable | 1.5 (3) | 4.5 (3) | 3 | not distinguishable |
| Test 2 | | | | cannot be judged: the seed-2 adapters were not run on test 2 (as the spec says) |

**The answer to the question of the spec** (acceptance 6): yes. Real-style distractors in the training data reduce the invented values on real text, and by far more than the noise of a training run, on all three real sets
(`real3` is the blind one: 0 invented values in both seeds, against 12 for the unmodified model and 13 and 21 for the two seeds of `lora-v2`) and on the synthetic real-style set. There is no loss on the old test that can
be told apart from the noise, and a test 2 score (81) that is the best of all adapters but cannot be compared with a spread. The garbled key is not fixed by this recipe (criterion 6, above).

The spread also re-reads the earlier result: **`lora-v2` seed 2 is clearly worse than seed 1 on real text** (`real1` 30 against 37 fully correct, `real3` 12 against 19, 21 invented values on `real3`), so "`lora-v2` is no better than the unmodified model on real
text" held for both seeds; what one training run could show was a spread of 5 to 11 answers on the same set.

## What the result does not say

- **It is a result on these kinds of sentences.** The nine kinds came from what two small real sets showed; `real3` has only 12 passages and **no stated field at all**, so it measures the refusal to invent a value, not the extraction of one.
  The stated fields of `real1` and `real2` (4 in total) were all found by `lora-v3` (0 missed on both sets, both seeds).
- **`real1` and `real2` are not blind** (I read them while writing the catalogue); `real3` is, and gives the same direction, which is the evidence that the templates did not simply fit what I read. 12 passages is a small blind test.
- **The cost is more missed values, mostly on growth and previous-year fields.** On the synthetic sets `lora-v3` misses more than `lora-v2` seed 1 in places (old test 5 against 0, test 2 9 against 6). On the old test and test 2 the missed fields
  are growths and previous-year values (`netIncomeGrowth` 3, `revenueGrowth` 1, `previousYearRevenue` 1 on the old test; `previousYearNetIncome` 6, `previousYearRevenue` 3 on test 2); on `test3` they include current-year amounts too
  (seed 1: `netIncome` 3 with `netIncomeGrowth` 8, `revenueGrowth` 3, `epsGrowth` 3; seed 2: `revenue` 6, `netIncome` 4, `revenueGrowth` 5). A plausible reason, **not tested**, is that the "change in amount and percent" distractors teach the model
  that an amount or percent beside a change is not the company's own figure. Seed 2 misses less on the old test (1), and the differences are within the noise by the rule above, but this is the direction to watch.
- **Two seeds are a thin measure of noise.** A third seed would tighten the spread; the conclusions marked "beyond the noise" are 15 to 90 answers or values wide against spreads of 0 to 24, which is why they are not borderline.
- **The checkpoint was chosen by the validation loss alone** (iteration 600 for seed 1, 150 for seed 2); the losses (0.020, 0.028) did not tell which would answer better. Both give the same direction on real text.

## What was learned

1. Training data written to look like the sentences that cause the mistakes (change, part, cost, deferred, adjusted, capital-return amounts, with the labels null) removes most invented values on real text without
   a loss that the noise cannot hide on the synthetic sets. `lora-v3` is better than the unmodified model on all three real sets in both seeds (`lora-v1` was better on `real1` and worse on `real2`; `lora-v2` was worse on `real2` and `real3`); the sets are small and `real3` has no stated field.
2. A recipe must be judged on more than one seed: two runs of the same recipe differed by up to 11 correct answers on one set, and `lora-v3`'s two runs stopped at different iterations (750 and 300).
3. The garbled key survives a better recipe; it is a property of how the model writes a key that has a number in its name, and the app's repair by position stays the right place to deal with it until constrained decoding is available.
