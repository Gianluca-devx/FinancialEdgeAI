# Phase 2g, step 2: the table reader on the development reports (counts only)

Spec: `Specs/phase-2g-table-reader.md` (approved 2026-11-02). The development set is the 5 reports of the PDF pilot, with the
pilot's frozen labels (`c087c0da286b`, 45 stated amounts and 5 null). These are the only reports the reader was written and tuned
on. Run on 2026-11-02 on the Mac with `Scripts/table_reader.sh` (the app's own sources compiled with a driver that first checks a
made-up statement), PDFKit text and positions, scored by the pilot's scorer unchanged (`Scripts/pdf_pilot.py score`). No report
text, page or answer is committed; no company is named.

## Result

| On the 5 development reports | Stated amounts correct | Confidently wrong (wrong, column, unit, invented) | Missed | Null labels left null |
|---|---|---|---|---|
| **Reader, A (true statement pages)** | **38/45 (84.4%)** | **0** | 7 | 5/5 |
| **Reader, C (keywords' top 3, first page recognised)** | **38/45 (84.4%)** | **0** | 7 | 5/5 |
| Pilot's row matcher, A (Phase 2f, for comparison) | 31/45 (68.9%) | 4 (2 wrong, 2 unit) | 10 | 5/5 |
| Model `lora-v3`, A (Phase 2f, mean of 3 seeds) | 24.0/45 (53.3%) | 21.7 per run | 0.7 | 3.7/5 |

- **Every miss is one report**, which prints no dollar unit on either statement page (only "(in millions of shares)", which the
  reader skips by rule T5). The reader leaves all 7 of its amounts null (`noUnit`) instead of guessing a unit (T6). Its per-share
  values are read.
- The 5 null labels (an operating income or an interest expense the statement does not print) are all left null (`noRow`).
- In C the reader took the true statement page for every statement it read.
- The sensitivity reading of the pilot (the literal schema wording for previous-year values) gives the same 38/45.
- Time: 0.08 to 0.11 s for the 5 reports (10 pages) on the Mac, without the keyword search.
- 84.4% is under the 85% that the decision rule asks; the rule applies to the 12 held-out reports, not to these.

## Changes made during development (disclosed)

The first run gave 38/45 on A and 36/45 on C, with no confidently wrong amount in either. Two changes followed, each with a test,
both from the development reports only:

1. **A year header that repeats a year is not a statement header.** In C, a page of supplemental consolidating data (four groups of
   columns, the years printed four times) was recognised as a cash flow statement. Its rows did not line up with the header, so no
   value came out, but a row that did would have given a segment's figure as the company's. Such a page now has no years, so it is
   not recognised and its fields would be null.
2. **"Consolidated" is ignored in a title**, so "statements of consolidated income" and "statements of consolidated cash flows" are
   recognised like "consolidated statements of ...".

The reader is frozen after this commit (step 3): its commit is recorded before any statement page of the 12 held-out reports is read.
