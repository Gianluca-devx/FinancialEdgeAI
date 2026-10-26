# Phase 2e, step 2: diagnosis of the missed values (no phone, no training, synthetic sets only)

Draft spec: `Specs/phase-2e-missed-values.md` (not approved; this step is the diagnosis it asks for before any data is written). Source: the saved reports of `lora-v2` and `lora-v3`, all seeds, on the old test, test 2 and
test 3 (`Results/`), 14 report files; test 2 exists for seed 1 only of each recipe. A value is "missed" when the label has a value and the answer has null. The statements are synthetic, so they can be quoted.

## Which statements are missed, and by whom

Adapters that missed a value of the statement (all three runs unless a number is given); `v2` = `lora-v2` seeds 1, 2, 3, `v3` = `lora-v3` seeds 1, 2, 3.

| Set, statement | Field | Missed by | Wording involved |
|---|---|---|---|
| test3 2 | `revenueGrowth` | v2 s1, v2 s3, v3 s1, v3 s2, v3 s3 (5 of 6) | "Operating revenues were 16% above the earlier year" |
| test3 2 | `netIncomeGrowth` | v2 s3, v3 s1 | "net income after tax sank 7%" |
| test3 10 | `netIncomeGrowth` | v2 s3, v3 s1 (2 runs of 3) | "Net income ... fell by $149.1B, or 2.5%, against 2024" |
| test3 21 | `netIncomeGrowth`, `epsGrowth` | v2 s3, v3 s1 | "net income ... sank 12%; per-share earnings showed an advance of 17.1%" |
| test3 14 | 5 fields (growths, previous-year amounts, `revenue`) | v2 s1, v2 s3, v3 s2, v3 s3 | a long paragraph: "rallied 12% to $21B from ...", "an advance of 16.1%", "swelled 35%", "down 23% from ..." |
| test3 12, 18, 30 | `netIncome` | 12: five of six; 18: v2 s1, v2 s3, v3 s2; 30: v2 s1, v2 s3 | a net income named inside a cash-flow sentence: "built from $101.9 billion of profit for the period" |
| test3 6 | `revenue` | v3 s2 | "Gross revenue was $115.5B", after "a USD 44.8 billion decrease in revenue (32.2%)" of a region |
| test3 27 | `revenue`, `netIncome` | v2 s3 | after "Revenue of USD 295.4 billion recorded between related entities ..." |
| test2 6, 15 | `previousYearNetIncome` | v3 s1 (3 runs) | "Profit for the period was $40 billion, compared with $38.2 billion in the earlier year" |
| test2 17 | `previousYearRevenue` | v2 s1, v3 s1 | "Gross revenue for 2024 was USD 47.3 billion" in a statement about 2025 (the prior year given as "for 2024": the answer writes it into `revenue`) |
| test2 21 | `operatingIncome` | v2 s1 | "Result from operations was $32.9B, compared with $34.6B" |
| test 17 | `netIncomeGrowth` | v2 s3, v3 s1 | "with year-over-year growth of 14%" |
| test 19 | `netIncomeGrowth` | v2 s3 | "Net income was down 20.4% year over year" |
| test 25 | `previousYearRevenue` | v3 s1 (1 run), v3 s3 | "net sales a year earlier stood at 36.6 billion dollars" |
| test 27 | `revenueGrowth` | v3 s1, s2, s3 (1, 1, 2 runs) | "Top-line revenue saw a 24.7 percent drop" |

## What the training data contains of these wordings (Dataset/v3/train.jsonl, 720 statements)

| Wording | In train | Where it is missed |
|---|---|---|
| "sank", "rallied", "swelled" | 0 | test 3 (2, 3 and 2 statements) |
| "above the earlier year", "an advance of" | 0 | test 2 (2), test 3 (5) |
| "built from", "profit for the period" | 0 | test 3 (3 and 7), test 2 (5) |
| "a year earlier stood at", "year-over-year", "for 2024 was" | 0 | test (1), test 2 (1) |
| "year over year" | 54 | test 19 ("Net income was down 20.4% year over year") is missed by `lora-v2` seed 3 only: **not every miss is unseen wording** |

The held-out design of Phase 2b (the wording pools of train, validation and the tests are disjoint) is what makes these zeros: **most of the missed values are growth and previous-year values written in wording the training never contained** (test 19 is one exception), the
lesson of `lora-v1` (more data variety) in a smaller form.

## Reading

1. **There is a pattern, and it is the wording, not the recipe.** The same statements are missed by several adapters of both recipes, in all three runs (test 3 statement 2: five of six adapters). `lora-v3` does not miss them for a reason
   of its own: its misses on test 3 (17, 15, 18) are within `lora-v2`'s (24, 0, 36), whose spread is the larger.
2. **The first explanation of the Phase 2d analysis is only partly right.** "A percent next to a change is taught as not the company's" fits "fell by $149.1B, or 2.5%" (test 3 statement 10) but not "16% above the earlier year", "sank 7%" or "year-over-year growth of 14%",
   which carry no amount; those are unseen verbs and phrases. The explanation is a hypothesis that this diagnosis does not support in general.
3. **Three groups, with different remedies:**
   - **Growth in verb forms** (sank, rallied, swelled, advance of, above the earlier year, saw a ... drop): new wording for the growth fields. The remedy is variety in the training data.
   - **Previous-year amounts in unusual framing** ("a year earlier stood at", "for 2024 was", "compared with ... in the earlier year" under a new name of the current figure): the same remedy.
   - **A net income inside a cash-flow sentence** ("built from ... of profit for the period"): a family that has no counterpart in the training data and whose label is a convention (a defensible one: it is the company's net income); it can be left out of the experiment or taught as its own kind.
4. **What this does not show.** It does not show that more wording variety will fix real text (the real sets hold four stated fields in total; real passages use their own verbs), and test 2 has one seed only. The effect of any new data has to be measured on a **new held-out wording
   pool (`test4`)**, as the draft says, otherwise it would only measure the new training wording.
5. **Verdict for D41: a pattern exists, so the draft's step 3 is justified** (a `Dataset/v4` with new growth and previous-year wording, a new held-out `test4`), but it is a new data-variety experiment of the kind `lora-v1` already showed to matter, not a repair of a flaw of `lora-v3`.
   It needs the user's decision (the draft spec is not approved) and about 10 to 15 hours of phone time with three seeds.
