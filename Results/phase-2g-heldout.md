# Phase 2g, step 3: the reader frozen, then the held-out labels (counts only)

Spec: `Specs/phase-2g-table-reader.md` (T7, T8). The held-out reports, their text and their labels are private
(`RealSet/pdf-heldout/`, git-ignored); this file holds counts and hashes only, and names no company.

## The freeze (written and committed before any statement page of the held-out reports is read)

The reader is frozen on 2026-11-02 at **commit 6919bd6**, the last commit that changes its sources. Until the held-out run (step 4)
is done, these files do not change:

| File | sha256 (first 12) |
|---|---|
| `FinancialEdgeAI/Services/StatementTable.swift` | `ff8f7bcca103` |
| `FinancialEdgeAI/Services/StatementTableReader.swift` | `6bf45df5c275` |
| `FinancialEdgeAI/Services/PDFStatementLines.swift` | `47d27570587b` |
| `Scripts/table_reader/main.swift` (the driver, ef16fad) | `e7833568b7f4` |
| `Scripts/table_reader.sh` | `6267c08690c3` |

At this commit no held-out report has been extracted: `RealSet/pdf-heldout/` does not exist yet. The held-out set is then built by
`Scripts/pdf_pilot.py heldout` (every report the pilot did not draw), its text extracted and its pages ranked by the pilot's
retrievers; the statement pages are located by their titles and labelled by hand by the rules of T8, before the reader runs on them.

## The held-out set and its labels (2026-11-02, after the freeze above)

- **The set:** `Scripts/pdf_pilot.py heldout`: the **12 reports** of the 17 that the pilot did not draw; set hash `601acb43f7dc`.
  The reports have 88 to 350 pages; both extractions give the same page count for every report. The pilot's retrievers ranked
  their pages (embedding time 201 s for both extractions together); nothing of the reader was run.
- **The labels:** the income statement and the cash flow statement of each report, located by their titles and read by hand by the
  rules of T8; `labels.json` sha256 **`acf0568af1f5`**.
  - **120 amounts** (10 per report), **112 stated** and **8 null**: in 8 reports the income statement prints no interest expense
    line of its own (only a net line of interest and other items, or components with no total). The three growth fields are null in
    all 12 (no percent on the statement pages).
  - Every stated label was checked by a script against its page: the number as printed (in the page's unit) appears on the page it
    was read from, 112 of 112.
  - Units: 11 reports in millions, 1 in thousands. Two reports print their years oldest first. Two reports show a loss in the
    current year in at least one of the labelled lines.
- **Spot-check:** one report, chosen by the pilot's committed seed (`random.Random(20261029).choice` over the sorted names), is
  checked by the user (pending). The judgement calls of the other eleven are listed for the user in the private spot-check file.
- **Disclosed:** the 17 reports were partly read for `real1` to `real3` (prose paragraphs); their statement pages were not used
  before. The labeller is the developer of the reader; the freeze order (reader, then labels, then run) limits that.
