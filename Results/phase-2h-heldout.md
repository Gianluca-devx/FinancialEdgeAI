# Phase 2h, step 3: the reader frozen, then the new held-out reports (counts only)

Spec: `Specs/phase-2h-table-reader-round2.md` (R7, R8). The new reports, their text and their labels are private (git-ignored);
this file holds counts and hashes only, and names no company.

## The freeze (written and committed before any new report is opened)

The reader is frozen on 2026-11-12 at **commit 7cca894**, the last commit that changes its sources (the development run and the
gate, b51cde4 and bd248bd, change no reader file). Until the held-out run (step 4) is done, these files do not change:

| File | sha256 (first 12) | Last changed |
|---|---|---|
| `FinancialEdgeAI/Services/StatementTable.swift` | `93540c0a1006` | da4e522 |
| `FinancialEdgeAI/Services/StatementTableReader.swift` | `bca7ddea35e5` | 7cca894 |
| `FinancialEdgeAI/Services/PDFStatementLines.swift` | `47d27570587b` | 0ed5517 (as in Phase 2g) |
| `Scripts/table_reader/main.swift` (the driver) | `e7833568b7f4` | ef16fad (as in Phase 2g) |
| `Scripts/table_reader.sh` | `6267c08690c3` | ef16fad (as in Phase 2g) |

At this commit no new report has been opened, listed or extracted. The folder the user supplies, `~/Downloads/Reports2`, was only
tested for existence (an attempt to count its files was refused by the system, so not even the count was seen). After this commit:
the inclusion check of R7, extraction, the keyword ranking, the labels by R8 and the user's spot-check, before the reader runs on
any new report.

## The new held-out set and its labels (2026-11-12, after the freeze above)

- **The inclusion check (R7):** `Scripts/pdf_pilot.py include` (14a41ee), committed before it ran on the new folder (rewritten on
  2026-11-13 before the merge into `main`: its first version used real report names as examples in a docstring and a test; the code
  is unchanged and the examples are now made up). Proven first
  on the 17 known reports: all 17 excluded as known, for that reason only, and no unit in another currency found in any of them.
  On the new folder: **10 of 10 reports included**, 0 excluded; all are US annual reports (Form 10-K), 87 to 479 pages, with
  dollar amounts and no unit in another currency; set hash `7015932f15a8`. Ten is the spec's minimum.
- **The currency check (R10):** no report in another currency was supplied, so the check has no report to run on.
- **Extraction:** both extractions give the same page count for every report. The pilot's retrievers rank the pages (still
  running at this commit; the labels do not use them, and their counts come with the run, step 4). Nothing of the reader was run.
- **The labels:** the income statement and the cash flow statement of each report, located by their titles (a private helper,
  not the reader) and read by hand by the rules of R8; `labels.json` sha256 **`b5536028cc0c`**.
  - **100 amounts** (10 per report), **93 stated** and **7 null**: operating income is not printed in 4 reports (only income
    before taxes), interest expense has no line of its own in 2 (a net interest line, or none), capex has no line in 1 (a bank).
    The three growth fields are null in all 10 (no percent on the statement pages).
  - Every stated label was checked by a script against its page: the number as printed (in the page's unit) appears on the page
    it was read from, **93 of 93**; the check was made to fail by changing one label (92 of 93).
  - Units: 9 reports in millions, 1 in thousands; all print their years newest first. No labelled line is a loss; one report has
    a negative operating cash flow. One report splits its income statement over two PDF pages (the title alone, then the table):
    the label points to the page with the table. One report prints EPS for several share classes: the label is the traded class.
- **The sensitivity values** (R9: the literal schema wording, as in Phases 2f and 2g: previous-year basic EPS, previous-year net
  income including noncontrolling interests, net sales beside a larger total), 15 alternative values in 10 reports, sha256
  `1f576169107a`, written with the labels, before any run.
- **Spot-check:** one report, chosen by the pilot's committed seed (`random.Random(20261029).choice` over the sorted names), is
  checked by the user (pending). The judgement calls of the other nine are listed for the user in the private spot-check file.
- **Disclosed:** none of the 10 reports was opened before the freeze; the labeller is the developer of the reader, and the order
  (reader frozen, then labels, then run) limits that.
