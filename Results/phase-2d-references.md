# Phase 2d, steps 3 and 4: the references before `lora-v3` is run

The unmodified model and `lora-v2` (iteration 200, weights `ffbdc621dc725d57`) on the two new sets, with the same prompt (`7779853b346c`), seeds 1, 2, 3, temperature 0.2,
`maxTokens` 384, thinking off, the same iPhone 16 and the same Debug build. Criteria: `Specs/phase-2d-real-distractors.md`. Nothing here was used to train, and **no `lora-v3`
adapter has been run on any set yet** (D40). `real3` is a private set: counts only, no passage, no per-statement table.

## Test 3 (`Dataset/v3/test3.jsonl`: 30 synthetic real-style statements, templates in no training statement)

Raw reports: `baseline-test3-Qwen3-4B-4bit-iphone-20261023T074852.json` (unmodified), `lora-v2-test3-Qwen3-4B-4bit-iphone-20261019T110341.json`. Counts printed by
`Scripts/report_counts.py`. (`summarize_results.py` and `compare_baselines.py` read the old test split only; no table was produced for test 3.)

| | Unmodified model | `lora-v2` |
|---|---|---|
| Decodable answers | 90 / 90 | 90 / 90 |
| **All 13 fields correct** | 14 / 90 (15.6%) | **27 / 90 (30.0%)** |
| Fields correct | 981 / 1170 (83.8%) | 1039 / 1170 (88.8%) |
| Invented values (hallucinated) | 145 | **99** |
| Missed values | 24 | 24 |
| Other (sign, unreadable, wrong number) | 20 (4, 13, 3) | 8 (0, 5, 3) |
| Time per statement (median) / peak memory | 11.5 s / 2.54 GiB | 11.8 s / 2.70 GiB |

By kind of statement (answers, fully correct, invented values, missed values; 3 runs each):

| Kind (statements) | Unmodified | `lora-v2` |
|---|---|---|
| null-only paragraphs (8) | 24, **0**, 58, 0 | 24, **0**, 48, 0 |
| paragraphs with fields among distractors (17) | 51, 12, 62, 18 | 51, 24, 27, 15 |
| positive sentences (5) | 15, 2, 25, 6 | 15, 3, 24, 9 |

- **`lora-v2` is better than the unmodified model on test 3 but far from good: 27 of 90.** It halves the invented values on the paragraphs that also state fields (62 to 27), but on the
  paragraphs with **no stated field it is still wrong every time** (0 of 24 fully correct, 48 invented values): these are the sentences Phase 2d is about. Invented values by field for
  `lora-v2`: `revenue` 42, `revenueGrowth` 33, `previousYearRevenue` 18, `netIncome` 6 (the unmodified model: `revenueGrowth` 41, `revenue` 40, `previousYearRevenue` 34, `netIncomeGrowth` 11,
  `epsGrowth` 9, `previousYearNetIncome` 6, `operatingCashFlow` 3, `netIncome` 1). The mistake is the one the spec expected: a segment, product or change figure read as the company's revenue.
- **Statements fully correct in all three runs:** 4 of 30 for the unmodified model, 9 of 30 for `lora-v2`; correct in none: 25 and 21.
- **Missed values are the same for both (24).** `lora-v2` does not leave out more than the unmodified model here; the missed values come from paragraphs where the stated figure sits among distractors.

**Thresholds this fixes for criterion 3** (written in the spec as "9 more than `lora-v2`" and "at most half of `lora-v2`'s invented values"): `lora-v3` seed 1 must reach **at least 36 / 90**
fully correct and at most **49** invented values (half of 99, rounded down).

## `real3` (12 passages, no stated field: every answer should be all null)

Set hash `c242e9d301bb`. Reports in `RealSet/reports/` (git-ignored). Counts only.

| | Unmodified model | `lora-v2` |
|---|---|---|
| Answers / decodable | **not measured yet** | 36 / 33 (**3 undecodable**) |
| **All 13 fields null (fully correct)** | **not measured yet** | 19 / 36 |
| Invented values | **not measured yet** | 13 |
| Median time per statement / peak memory | | 13.3 s / 2.67 GiB |

- The unmodified model's run on `real3` was started on 19 October and **never produced a report** (the one report of that day for `real3` is `lora-v2`'s); it is to be run again,
  and criterion 5 cannot be read until it exists: its two thresholds are "fully correct at least the unmodified model's" and "invented values at most 70% of `lora-v2`'s", that is
  **at most 9 of 13** invented values (0.7 x 13 = 9.1).
- `lora-v2` has **3 undecodable answers** on `real3` (one passage, all three runs: valid JSON with a wrong key, `previous500` or `previous5`, the same failure as on `real1` and `real2`; only key names are quoted): criterion 6 (0 undecodable on every set) is the reference to beat.

## What happened to the runs, for the record

- The unmodified model on `test3` was started on 19 October and **killed after 7 minutes by a fault in my queue script** (a copied `.jsonl` counted as a new report and a relaunch ended it), then
  started again and stopped on request (a partial report of 16 of 90 answers exists on the phone and is **not used**). It was run completely on 23 October (09:03 to 09:50), alone on the phone.
- The Mac was restarted on 22 October and wiped the copies of the reports in the scratchpad; the phone still held them and they were copied again on 23 October. No report was changed.
- The adapters of `lora-v3` and the two seed-2 runs were trained (see `Scripts/lora/runs/lora-v3.md`) before these references were complete; none of them has been evaluated, so no
  threshold above depends on them.
