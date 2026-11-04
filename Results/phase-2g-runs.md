# Phase 2g, step 4: the held-out run (counts only)

Spec: `Specs/phase-2g-table-reader.md`. Run on 2026-11-03 on the Mac, no phone. Nothing from a report is committed and no company
is named; the predictions and answers stay in `RealSet/pdf-heldout/` (git-ignored).

- **The reader** is the frozen one: before the run, its three sources and the driver were checked against the hashes of the freeze
  record (`Results/phase-2g-heldout.md`, reader commit 6919bd6): all five match.
- **The set and labels:** the 12 held-out reports (set hash `601acb43f7dc`), labels `acf0568af1f5`, 112 stated amounts and 8 null.
  The user spot-checked the report chosen by seed (10 of 10 confirmed) and one more report (confirmed); no label changed.
- **The sensitivity values** (the literal schema wording, as in the pilot: 15 alternative values, sha256 `6b02305acf85`) were written
  before the reader or the model ran.
- **The model:** `lora-v3` seed 1 (weights `26a0d90702e1`), the core prompt, one true statement page per call, seeds 1 to 3, as in the
  pilot; `mlx-lm` 0.32.2, `mlx` 0.32.4 (the scratchpad environment was emptied by the system's temp cleaner and rebuilt with the same
  versions before this run). 72 calls, 8.0 s per call (median), 1,320 prompt tokens (median, at most 1,790).

## Result

Stated amounts correct out of 112 per run; "confidently wrong" is wrong + column + unit + invented (an amount shown that is not the
printed one). The 8 null labels count as kept when the answer is null.

| On the 12 held-out reports | Stated amounts correct | Per seed | Confidently wrong | Missed | Nulls kept | Literal reading also accepted |
|---|---|---|---|---|---|---|
| **Reader, C (the whole path; the decision rule's condition)** | **91/112 (81.2%)** | - | **0** | 21 | 8/8 | 91/112 |
| Reader, A (true statement pages) | 96/112 (85.7%) | - | 0 | 16 | 8/8 | 96/112 |
| Model `lora-v3`, A, 3 seeds | 187/336 (55.7%) | 65, 61, 61 | 137 (125 wrong, 12 invented) | 24 | 12/24 | 200/336 (59.5%) |
| Reader, A, with the model filling only the reader's nulls | 316/336 (94.0%) | 106, 105, 105 | 27 (15 wrong, 12 invented) | 5 | 12/24 | - |

- **The reader never shows a wrong amount**, on either condition: every amount it does not read is null with its reason.
- **The development reports against the held-out ones** (the gap measures how much the reader was fitted to its five reports):
  A 84.4% against 85.7%, C 84.4% against 81.2%.
- **The model on fresh reports** gives 55.7%, against 53.3% on the pilot's reports: the pilot's result holds.
- **The fallback** (the model filling the reader's nulls) adds, over the 3 seeds, **28 correct and 27 confidently wrong amounts**: 12
  invented interest expenses (the label is null; the model copies a component or a net line) and 15 amounts from the oldest year's
  column (3 of them in a report that prints its years oldest first). From 0 confidently wrong amounts per run, it goes to 9.
- The reader reads the 12 reports in 0.16 s (A) and 0.20 s (C) on the Mac, without the keyword search.

## The reader's nulls by kind

On A, the 16 missed amounts:

| Kind | Missed |
|---|---|
| Wording not in the synonym table: a loss year ("Operating loss", "Net loss", one "Basic and diluted" EPS row) | 5 |
| Wording not in the synonym table: "Consolidated net income attributable to ..." (current and previous year) | 2 |
| Wording not in the synonym table: "Net cash from operations" | 1 |
| Wording not in the synonym table: capex lines named "Investment in ...", "Purchases related to ...", "Payments for property and equipment" | 3 |
| Two capex lines with the same name and different values (null by T6, as designed) | 3 |
| A note reference in the EPS rows ("(Note 12)") read as an extra cell (null by the cell count) | 2 |

C misses 5 more, because 3 of the 24 statement pages were not recognised among the keywords' top 3: two cash flow statements titled
"... cash flows statements" (the title rule expects "statements of cash flows"), and one loss-year income statement with fewer than
three rows the reader knows (its loss wording is not in the table).

The 8 null labels were all left null (`noRow` on interest expense).

## The model's errors on the held-out pages

`Scripts/pdf_pilot.py kinds`, the 137 confidently wrong amounts over 3 seeds:

| Where the model's number sits | Count |
|---|---|
| Previous year, the oldest (third) column, labelled row | 29 |
| Previous year, the oldest column, another row | 21 |
| Previous year, the right column, another row | 11 |
| Current year, the labelled row, first column: in the two reports that print their years oldest first, the oldest year taken as the current one (all 35) | 35 |
| Current year, another row | 26 |
| Invented (label null): interest expense | 12 |
| Other | 3 |
