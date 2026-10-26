# Phase 2d, Amendment 4: a third seed of `lora-v3` and `lora-v2`

Spec: `Specs/phase-2d-real-distractors.md`, Amendment 4 (committed before any run: how the result is read was fixed there). The earlier analysis, `lora-v3-analysis.md`, is **not edited**; its verdict
(seven of eight criteria met for `lora-v3` seed 1, criterion 6 not met) stands. Every number is a count printed by `Scripts/phase2d_table.py` from the saved reports (`Results/` for the synthetic sets,
`RealSet/reports/` for the real ones, **counts only: no passage, no per-statement table of a real set**). Same iPhone 16, Debug build, prompt `7779853b346c`, seeds 1 to 3, temperature 0.2, `maxTokens` 384.

The two new adapters, trained with `--seed 3` on the frozen data (`Dataset/v3` and `Dataset/v2`, checked byte-identical to the training folders), the stop rule applied by `stop_rule.py`:

| | `lora-v3-s3` | `lora-v2-s3` |
|---|---|---|
| Stopped after (the rule) | 400 | 300 |
| Chosen checkpoint, validation loss | 250, 0.032 | 150, 0.029 |
| Duration | 164 min | 110 min |
| Weights SHA-256 | `3a1eacbeee6e2bf5…` | `0745f63d140cb17e…` |
| Config SHA-256 | `d850923a59d9deab…` | `de67b7f68949d53a…` |

All ten reports carry these hashes and the right answer counts. `lora-v3` stopped after 750, 300 and 400 iterations in its three seeds, `lora-v2` after 350, 300 and 300.

## The three seeds, per set (fully correct / invented / missed / undecodable)

| Set | `lora-v3` seed 1 | seed 2 | seed 3 | `lora-v2` seed 1 | seed 2 | seed 3 |
|---|---|---|---|---|---|---|
| Old test (90) | 85 / 1 / 5 / 0 | 85 / 4 / 1 / 0 | 85 / 1 / 5 / 0 | 85 / 2 / 0 / 0 | 80 / 6 / 0 / 0 | 81 / 3 / 6 / 0 |
| Test 3 (90) | 66 / 13 / 17 / 0 | 57 / 24 / 15 / 0 | **78** / 1 / 18 / 0 | 27 / 99 / 24 / 0 | 16 / 122 / 0 / 0 | 42 / 47 / 36 / 0 |
| `real1` (63) | 57 / 3 / 0 / 0 | 57 / 9 / 0 / 0 | 60 / 3 / 0 / 0 | 37 / 33 / 0 / 3 | 30 / 39 / 0 / 3 | 49 / 15 / 0 / 3 |
| `real2` (30) | 24 / 8 / 0 / 0 | 27 / 6 / 0 / 0 | 30 / 0 / 0 / 0 | 10 / 29 / 0 / 3 | 11 / 30 / 0 / 4 | 13 / 19 / 3 / 3 |
| `real3` (36, all-null) | 33 / 0 / 0 / **3** | 36 / 0 / 0 / 0 | 33 / **3** / 0 / 0 | 19 / 13 / 0 / 3 | 12 / 21 / 0 / 6 | 24 / 0 / 0 / 3 |

(The unmodified model: old test 57, test 3 14, `real1` 39, `real2` 21, `real3` 24 with 12 invented.)

## The rule of Amendment 4 (D39 with three seeds) applied

Mean over the three seeds, spread = maximum minus minimum over the three, and a difference counts only if it **exceeds the larger of the two spreads**. Reading from the two-seed analysis in the last column.

| Measure | `lora-v3` mean (spread) | `lora-v2` mean (spread) | Difference | Reading with 3 seeds | Reading with 2 seeds |
|---|---|---|---|---|---|
| Old test, fully correct | 85.0 (0) | 82.0 (5) | 3.0 | not distinguishable | same |
| Old test, invented | 2.0 (3) | 3.7 (4) | 1.7 | not distinguishable | same |
| Old test, missed | 3.7 (4) | 2.0 (6) | 1.7 | not distinguishable | same |
| Test 3, fully correct | 67.0 (21) | 28.3 (26) | 38.7 | **beyond the noise** | same |
| Test 3, invented | 12.7 (23) | 89.3 (75) | 76.7 | **beyond the noise** (76.7 against 75: close) | same |
| Test 3, missed | 16.7 (3) | 20.0 (36) | 3.3 | not distinguishable | same |
| `real1`, fully correct | 58.0 (3) | 38.7 (19) | 19.3 | **beyond the noise** | same |
| `real1`, invented | 5.0 (6) | 29.0 (24) | 24.0 | **not distinguishable (24.0 is exactly the spread of `lora-v2`)** | beyond the noise: **reversed** |
| `real2`, fully correct | 27.0 (6) | 11.3 (3) | 15.7 | **beyond the noise** | same |
| `real2`, invented | 4.7 (8) | 26.0 (11) | 21.3 | **beyond the noise** | same |
| `real3`, all-null | 34.0 (3) | 18.3 (12) | 15.7 | **beyond the noise** | same |
| `real3`, invented | 1.0 (3) | 11.3 (21) | 10.3 | **not distinguishable** | beyond the noise: **reversed** |
| `real3`, undecodable | 1.0 (3) | 4.0 (3) | 3.0 | not distinguishable | same |

**Two readings of Phase 2d are reversed by the third seed, and one is close.** `lora-v2` seed 3 is much better on real text than seeds 1 and 2 (`real1` 49 fully correct and 15 invented values against 37 and 30, and 33 and 39; `real3`
**0 invented values** against 13 and 21), so the spread of `lora-v2` grows (24 invented values on `real1`, 21 on `real3`) and the difference of the means no longer exceeds it. What is left of the claim "`lora-v3` removes the invented values on real text" is:
- on `real2` and on test 3 it is beyond the noise, and on test 3 only barely (76.7 against 75);
- on `real1` and `real3` the rule says not distinguishable, although **every one of the three `lora-v3` seeds has fewer invented values than every one of the three `lora-v2` seeds on `real1`** (3, 9, 3 against 33, 39, 15: the ranges do not overlap), and on `real3` the ranges overlap at zero (`lora-v3` 0, 0, 3; `lora-v2` 13, 21, 0). The rule is mechanical and conservative; this is stated as an observation, not a replacement of the rule.
- the fully-correct gains stay beyond the noise on test 3, `real1`, `real2` and `real3`.

Counted separately, per recipe (Amendment 4, 3):
- **Undecodable answers (the garbled key):** `lora-v2` in **3 of 3 seeds** (on `real1`, `real2` and `real3` in every seed: 3, 3, 3; 3, 4, 3; 3, 6, 3), `lora-v3` in **1 of 3 seeds** (seed 1, on `real3`, 3 answers; seeds 2 and 3: 0 on every set). So the recipe does not remove the failure,
  but it is much rarer; with three seeds, "criterion 6 not met" for `lora-v3` is a property of one seed in three, and the app's repair by position stays the safeguard. Criterion 6 was and stays judged on seed 1 (not met).
- **Missed values on the old test (criterion 1, met with zero margin in seed 1):** `lora-v3` 5, 1, 5; `lora-v2` 0, 0, 6. The claim of the earlier analysis that `lora-v3` misses more on the old test **is weakened**: `lora-v2` seed 3 misses 6, more than the limit of 5.
  Missed values on test 3: `lora-v3` 17, 15, 18; `lora-v2` 24, 0, 36 (the spread of `lora-v2` is 36). **Every seed of `lora-v3` misses some values on both sets, and only `lora-v2` seed 2 has none on both**, and the cause is not established (see the draft `Specs/phase-2e-missed-values.md`).
- **New invented values on `real3`:** `lora-v3` seed 3 writes 3 (seeds 1 and 2: 0), so "0 invented values in every seed" of the earlier analysis is no longer true; the count is small and the rule calls the difference with `lora-v2` not distinguishable.

## Time and the one disturbed run

The time per statement is not comparable for `lora-v2-s3` on test 3: median **24.3 s** (tokens per second 7.9 against 14 to 18 in the other test 3 runs, with the same number of generated tokens, about 120). This run was the first after the phone's battery had been drained and recharged (the earlier attempt
produced no report and is not a result); the most likely cause is a throttled phone (not verified), not a different model, and it does not change any answer count (temperature 0.2, same seeds, same tokens). The four other `lora-v2-s3` runs have the usual 9.5 to 10.9 s medians. The old-test medians of the three `lora-v3` seeds are 11.1, 10.9 and 10.6 s (criterion 7 unchanged: 2.86 GiB, "serious").

## What the third seed changes, in one reading

1. **The direction of Phase 2d holds, the size of its claim is smaller.** `lora-v3` is better than `lora-v2` on fully correct answers beyond the noise on four sets and on invented values beyond the noise on two; on two others the three-seed spread of `lora-v2` swallows the difference.
2. **`lora-v2`'s noise was larger than two seeds showed** (up to 49 fully correct on `real1` for one seed, 30 for another): one training run of any recipe is a draw, as D39 said, and two draws were still too few.
3. **The garbled key** is a failure of `lora-v2` in every seed and of `lora-v3` in one of three.
4. **The earlier analysis is not rewritten** (Amendment 4, 5): its table and verdict stay as published, this file corrects the readings that the third seed reverses.

## `real3` labels

The three doubtful `real3` labels (all null, counts only here) were put to the user, who confirmed all three on 2026-10-26. All 12 `real3` labels are therefore confirmed and no `real3` count in this or the earlier analysis changes.
